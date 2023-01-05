#!/bin/bash

# Inputs
orig_dir="OrigMDOC"    # directory where original MDOCs are located
mdoc_prefix="Oocyte_L1_PACE2_ts"   # files assumed to be of the form: ${orig_dir}/${mdoc_prefix}_???.mrc.mdoc

# Parameters
num_series=22
delay=0.05              # delay between micrographs, seconds

# Outputs

outdir="."             # for final MDOC files
eer_dir="frames"       # directory for (empty) EER files
chunk_dir="ChunkMDOC"  # intermediate files will go here
tsdir_suffix="ts"      # files for each tilt series will be of the form: ${chunk_dir}/?{tsdir_suffix}/${chunk_prefix}??.${chunk_ext}
chunk_prefix="chunk"   # prefix for chunk files
chunk_ext="txt"        # extension for chunk files

function generate_mdoc() {
  clean_up
  split_mdoc
  mdoc_header
  build_mdoc
}

function clean_up() {
  # If chunk directory exists, remove
  if [[ -d ${chunk_dir} ]] ; then
    rm -r ${chunk_dir}
  fi
  
  # Remove pre-existing MDOCs
  for series_num in $(seq "$num_series"); do
    local out_mdoc=$(num_to_mdoc "${series_num}")
    rm "${out_mdoc}" 2>/dev/null
  done
  
  # Create frames directory, if necessary
  if ! [[ -d ${eer_dir} ]] ; then
    mkdir -v ${eer_dir}
  fi
}

function num_to_mdoc() {
  local pad_num=$(printf "%03d" $1)
  echo "${mdoc_prefix}_${pad_num}.mrc.mdoc"
}

function split_mdoc() {
# Adapted from:
#   https://www.cyberciti.biz/faq/sed-remove-m-and-line-feeds-under-unix-linux-bsd-appleosx/
#   https://stackoverflow.com/a/60972105/3361621

  mkdir -pv ${chunk_dir}
  
  for series_num in $(seq "$num_series"); do
    local pad_series=$(printf "%03d" ${series_num})
    
    # Remove CRLF
    local mdoc_nocrlf=$(get_nocrlf_filename "${pad_series}")
    sed 's/\r//' ${orig_dir}/${mdoc_prefix}_${pad_series}.mrc.mdoc > ${mdoc_nocrlf}
    local status_code=$?
# #     echo "status_code : $status_code" ; exit
    
    if [[ $status_code -ne 0 ]] ; then
      echo -e "ERROR!!\n"
      exit 3
    fi
    
    local curr_tsdir="${chunk_dir}/${series_num}${tsdir_suffix}"
    mkdir -p ${curr_tsdir}
    
    csplit --quiet --prefix=${curr_tsdir}/${chunk_prefix} --suffix-format=%02d.${chunk_ext} --suppress-matched ${mdoc_nocrlf} /^$/ {*}
  done
}

function get_nocrlf_filename() {
  local pad_series=$1
  echo "${chunk_dir}/${mdoc_prefix}_${pad_series}.mrc.mdoc.txt"
}

function mdoc_header() {
  # The first 3 entries contain header information common to all micrographs
  
  for series_num in $(seq "$num_series"); do
    out_mdoc="${mdoc_prefix}_$(printf "%03d" ${series_num}).mrc.mdoc"
    
    for filenum in {00..02} ; do
      local chunk_file="${chunk_dir}/${series_num}${tsdir_suffix}/${chunk_prefix}${filenum}.${chunk_ext}"
      (cat $chunk_file ; echo) >> ${out_mdoc}
    done
  done
}

function build_mdoc() {
  # Generate rest of MDOC file
  local img_counter=0
  
  # Get last entry in MDOC
  local mdoc_nocrlf=$(get_nocrlf_filename "001")
  local last_z=$(search_mdoc_file $mdoc_nocrlf 'ZValue')
  local last_idx=$(( $last_z + 3 ))
  
  for curr_idx in $(seq 3 ${last_idx}) ; do
    for series_num in $(seq "$num_series"); do
      
      # Get output MDOC filename
      local out_mdoc=$(num_to_mdoc "${series_num}")
      
      # Get chunk filename
      local pad_idx=$(printf "%02d" $curr_idx)
      chunk_file="${chunk_dir}/${series_num}${tsdir_suffix}/${chunk_prefix}${pad_idx}.${chunk_ext}"
      
      # Delay
      sleep $delay
      
      # Append
      (cat $chunk_file ; echo) >> ${out_mdoc}
      
      # Print to screen
      date_time=$(search_mdoc_file $chunk_file 'DateTime')
      let "img_counter++"
      imgnum=$(search_mdoc_file $chunk_file 'ZValue')
      eer_name=$(search_mdoc_file $chunk_file 'SubFramePath')
    
      if [[ $status_code -ne 0 ]] ; then
        echo -e "ERROR!!\n"
        echo "status_code : $status_code"
        echo "chunk_file : '$chunk_file'"
        exit 4
      fi
      
      tilt_angle=$(search_mdoc_file $chunk_file 'TiltAngle')
      echo "$(search_mdoc_file $chunk_file 'DateTime'): cumulative #${img_counter}, tilt series #${series_num}, ZValue #${imgnum}, TiltAngle: ${tilt_angle}, EER: $eer_name"
      
      # Create fake EER
      touch "$eer_dir/$eer_name"
      local status_code=$?
      
      if [[ $status_code -ne 0 ]] ; then
        echo -e "ERROR!!\n"
        echo "status_code : $status_code"
        exit 5
      fi
    done
  done
}

function search_mdoc_file() {
  mdoc_file=$1
  search_target=$2
  
  # Search for last line with target string
  line=$(grep $search_target $mdoc_file | tail -n 1)
  
  # Extract everything after the '=' (i.e., the 3rd space-delimited string onward)
  hit=$(echo $line | cut -d' ' -f3-)
  
  # Remove trailing ']' for ZValue line)
  if [[ "${search_target}" == "ZValue" ]]; then
    hit=$(echo $hit | sed 's/]*$//g')
  fi
  
  # For EER file, get basename
  if [[ "${search_target}" == "SubFramePath" ]]; then
    # Substitute backslash with forward slash (https://stackoverflow.com/a/18053055/3361621)
    hit=$(basename ${hit##*[/|\\]})
    status_code=$?
  fi
  
  echo $hit
}

# Check whether script is being sourced or executed (https://stackoverflow.com/a/2684300/3361621)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
#   echo "script ${BASH_SOURCE[0]} is being executed..."
   generate_mdoc
# else
#   echo "script ${BASH_SOURCE[0]} is being sourced..."
fi
