#!/bin/bash

# THIS SCRIPT CONTAINS FUNCTIONS COMMON TO BOTH SNARTomoClassic and SNARTomoPACE

function check_args() {
###############################################################################
#   Function:
#     Checks for unfamiliar arguments
#   
#   Global variables:
#     ARGS
#   Passed variables:
#     $1 (integer)
###############################################################################
  
  local num_positional_args=$1
  
  if [[ "${#ARGS[@]}" -gt "${num_positional_args}" ]]; then
    echo -e "\nERROR!!"
    echo      "  Found unfamiliar arguments: ${ARGS[@]}"
    echo      "  To list options & defaults, type:"
    echo -e   "    $(basename $0) --help\n"
    exit 1
  fi  
}

function create_directories() {
###############################################################################
#   Functions:
#     Creates directories
#     Writes command line to commands file
#     Writes settings to settings file
#   
#   Global variables:
#     vars
#     verbose
#     do_pace
#     rawdir
#     log_dir
#     temp_dir (PACE only)
#     mc2_logs
#     ctfdir
#     imgdir
#     thumbdir
#     dose_imgdir
#     contour_imgdir
#     cmd_file
#     set_file
#
###############################################################################
  
  # Remove output directory if '--overwrite' option chosen (PACE only)
  if [[ "${vars[overwrite]}" == true ]]; then
    if [[ "${do_pace}" != true ]]; then
      eer_template="${vars[outdir]}/${rawdir}/*.eer"
      num_moved_eers=$(ls ${eer_template} | wc -w 2> /dev/null)
    
      # If non-empty, throw error
      if [[ "${num_moved_eers}" -ge 1 ]]; then
        echo
        echo "ERROR!! Output directory '${vars[outdir]}/${rawdir}' has pre-existing '${num_moved_eers}' EER files!"
        echo "  1) If restarting from scratch, enter:"
        echo "    mv ${eer_template} ${vars[eer_dir]}/"
        echo "    Then restart."
        echo "  2) If continuing a partial run, move incomplete tilt series' EERs to input directory '${vars[eer_dir]}/'"
        echo "    Only newly detected EERs will be included in new tilt series."
        echo "Exiting..."
        echo
        exit
      fi
    fi
    # End PACE IF-THEN
    
    if [[ -d "${vars[outdir]}" ]]; then
      if [[ "$verbose" -ge 1 ]]; then
        echo -e "Removing directory '${vars[outdir]}/'"
      fi
    
      rm -r "${vars[outdir]}" 2> /dev/null
    fi
    # End outdir-exists IF-THEN
  fi
  # End overwrite IF-THEN
  
  if [[ "$verbose" -ge 1 ]]; then
    mkdir -pv "${vars[outdir]}" "${vars[outdir]}/${micdir}/$mc2_logs" 2> /dev/null
  else
    mkdir -p "${vars[outdir]}" "${vars[outdir]}/${micdir}/$mc2_logs" 2> /dev/null
  fi
  
  # Even in testing mode, writing the IMOD and angles text files (maybe don't need)
  mkdir "${vars[outdir]}/${recdir}" "${vars[outdir]}/${imgdir}" 2> /dev/null
  
  # If not testing
  if [[ "${vars[testing]}" == false ]]; then
    mkdir "${vars[outdir]}/${denoisedir}" "${vars[outdir]}/${imgdir}/${thumbdir}" "${vars[outdir]}/$ctfdir" 2> /dev/null
  fi
  
  # PACE-specific options
  if [[ "${do_pace}" == true ]]; then
    # The temp directory has some files which may befuddle later runs
    rm -r "${vars[outdir]}/${temp_dir}" 2> /dev/null
    
    mkdir "${vars[outdir]}/${log_dir}" "${vars[outdir]}/${temp_dir}" "${vars[outdir]}/${micdir}" "${vars[outdir]}/${imgdir}/${dose_imgdir}" "${vars[outdir]}/${imgdir}/${contour_imgdir}" 2> /dev/null
    
    if [[ "${vars[testing]}" == true ]]; then
      mkdir "${vars[outdir]}/$ctfdir" 2> /dev/null
    fi
  
  # If non-PACE
  else
    if [[ "${vars[testing]}" != true ]]; then
      mkdir "${vars[outdir]}/$rawdir"  
    fi
  fi
  # End PACE IF-THEN
    
  # Write command line to output directory
  echo -e "$0 ${@}\n" >> "${vars[outdir]}/${cmd_file}"
  print_arguments > "${vars[outdir]}/${set_file}"
  
  if [[ "${verbose}" -ge 1 ]]; then
    echo -e "Wrote settings to ${vars[outdir]}/${vars[settings]}\n"
  fi
}

function check_testing() {
###############################################################################
#   Function:
#     Checks whether we're testing or not
#   
#   Global variables:
#     vars
#     ctf_exe
#     do_pace
#     do_parallel
#     
###############################################################################
  
  if [[ "${vars[testing]}" == "true" ]]; then
    echo -e "TESTING...\n"
    
    # Instead of running, simply print that you're doing it
    ctf_exe="TESTING ctffind4"
  else
    ctf_exe="$(basename ${vars[ctffind_dir]}/ctffind)"
  fi
  # End testing IF-THEN
  
  # PACE's "slow" option only works with "testing"
  if [[ "${do_pace}" == true ]]; then
    if [[ "${vars[slow]}" == true ]] && [[ "${vars[testing]}" == false ]] ; then
      echo -e "ERROR!! '--slow' option only valid with '--testing' option!"
      exit
    fi
    
    # Set default
    do_parallel=true
    
    # Serial mode will be when testing is true and slow is false
    if [[ "${vars[testing]}" == true ]] ; then
      vars[outdir]="${vars[outdir]}/0-Testing"
      
      if [[ "${vars[slow]}" == false ]] ; then
        do_parallel=false
      fi
    else
      # Read GPU list as array
      IFS=' ' read -r -a gpu_list <<< "${vars[gpus]}"
    fi
    # End parallel IF-THEN
  fi
  # End PACE IF-THEN
}

function validate_inputs() {
###############################################################################
#   Function:
#     Makes sure necessary inputs exist
#   
#   Positional variable:
#     1) output log file
#   
#   Calls functions:
#     vprint
#     read_mdoc
#     check_file
#     check_dir
#     check_exe
#     check_python
#     
#   Global variables:
#     init_conda (OUTPUT)
#     vars
#     do_pace
#     imod_descr
#     ctffind_descr
#     validated
#     
###############################################################################
  
  local outlog=$1
  local validated=true

  vprint "\nValidating..." "1+" "${outlog}"
  
  # Note initial conda directory
  init_conda="$CONDA_DEFAULT_ENV"

  
  if [[ "${do_pace}" != true ]]; then
    read_mdoc "${outlog}"
  else
    check_targets "${outlog}"
    check_apix_pace "${outlog}"
    
    # If using live mode, then we need the last angle
    if [[ "${vars[live]}" == true ]] && [[ "${vars[last_tilt]}" == "$LAST_TILT" ]] ; then
      validated=false
      vprint "  ERROR!! In Live mode, need to define '--last_tilt'!" "0+" "${outlog}"
    fi
  fi
  # End PACE IF-THEN

  imod_descr="IMOD executables directory"
  check_dir "${vars[eer_dir]}" "EER directory" "${outlog}"
  check_dir "${vars[imod_dir]}" "${imod_descr}" "${outlog}"
  check_exe "$(which nvcc)" "CUDA libraries" "${outlog}"
  check_exe "${vars[motioncor_exe]}" "MotionCor2 executable" "${outlog}"
  
  # For MotionCor, check the number of GPUs
  check_mc2
  
  check_file "${vars[gain_file]}" "gain reference" "${outlog}"
  check_file "${vars[frame_file]}" "frame file" "${outlog}"
  
  ctffind_descr="CTFFIND executables directory"
  check_dir "${vars[ctffind_dir]}" "${ctffind_descr}" "${outlog}"
  
  # Can't use JANNI and Topaz simultaenously
  if [[ "${vars[do_janni]}" == true ]] && [[ "${vars[do_topaz]}" == true ]]; then
    validated=false
    vprint "  ERROR!! Can't use JANNI and Topaz simultaneously!" "0+" "${outlog}"
  fi
  
  if [[ "${vars[do_janni]}" == true ]]; then
# #     check_exe "janni_denoise.py" "JANNI executable" "${outlog}" "${vars[janni_env]}"
    try_conda "JANNI executable" "${vars[janni_env]}" "${outlog}"
    check_file "${vars[janni_model]}" "JANNI model" "${outlog}"
  fi
  
  if [[ "${vars[do_topaz]}" == true ]]; then
# #     check_exe "${vars[topaz_exe]}" "Topaz executable" "${outlog}" "${vars[topaz_env]}"
    try_conda "Topaz executable" "${vars[topaz_env]}" "${outlog}"
  fi
  
  if [[ "${vars[do_janni]}" == true ]] || [[ "${vars[do_topaz]}" == true ]]; then
    if [[ "${vars[denoise_gpu]}" == false ]]; then
      vprint "    Denoising using CPU..." "1+" "${outlog}"
    fi
  fi
  
  # IMOD
  if [[ "${vars[batch_directive]}" != "${batch_directive}" ]] && [[ "${vars[do_etomo]}" != true ]]; then
    vprint "  WARNING! Batch directive specified, but '--do_etomo' flag not specified. Using eTomo..." "1+" "${outlog}"
    vars[do_etomo]=true
  fi
  
  if [[ "${vars[do_etomo]}" == true ]]; then
    vprint "  Computing reconstruction using IMOD" "1+" "${outlog}"
    check_file "${vars[batch_directive]}" "IMOD batch directive" "${outlog}"
    update_adoc "${outlog}"
  else
    vprint "  Computing reconstruction using AreTomo" "1+" "${outlog}"
    check_exe "${vars[aretomo_exe]}" "AreTomo executable" "${outlog}"
  fi
  
  if [[ "${vars[do_ruotnocon]}" == true ]]; then
    if [[ "${vars[do_etomo]}" != true ]]; then
      validated=false
      vprint "  ERROR!! Can only remove contours if running eTomo!" "0+" "${outlog}"
    else
      vprint "  Removing contours with a residual greater than ${vars[ruotnocon_sd]} standard deviations" "2+" "${outlog}"
    fi
  fi
  
  if [[ "${do_pace}" != true ]] || [[ "${vars[do_ruotnocon]}" == true ]] ; then
    check_python "${outlog}"
  fi
  
  check_exe "$(which convert)" "Imagemagick convert executable" "${outlog}"
  
  # Summary
  if [[ "$validated" == false ]]; then
    vprint "Missing required inputs, exiting...\n" "0+" "${outlog}"
    exit 1
  else
    vprint "Found required inputs. Continuing...\n" "1+" "${outlog}"
  fi
}

function vprint() {
###############################################################################
#   Function:
#     Echoes string if verbosity meets condition
#   
#   USAGE:
#     vprint "string2print" "threshold"
#   
#   Positional arguments:
#     1) String to echo
#     2) verbosity threshold -- last character specifies range
#          + greather than or equal to
#          - less than or equal to
#          = equal to
#     3) optional log file (if provided, then will also write there)
#          An '=' at the beginning will only write to the log file, not to the screen.
#          Multiple log files can be written to, separated by a space.
#   
#   Global variables:
#     verbose
#     do_pace
#     time_format
#     vars
#     
###############################################################################
  
  local string2print=$1
  local threshold=$2
  local outlog=$3
  
  local do_print2file=false
  local do_echo2screen=false
  
  # Strip last character
  local lastchar=${threshold: -1}
  local threshold=${threshold%?}
  # (Adapted from https://stackoverflow.com/a/27658717/3361621)
  
  # Split list of log files into array
  IFS=' ' read -r -a log_array <<< "${outlog}"
#   printf "'%s'\n" "${log_array[@]}"
#   echo "length log_array: '${#log_array[@]}'"
  
  # Decide whether to print
  if [[ "${lastchar}" == "+" ]]; then
    if [[ "$verbose" -ge ${threshold} ]]; then
      do_print2file=true
      do_echo2screen=true
    fi
  elif [[ "${lastchar}" == "-" ]]; then
    if [[ "$verbose" -le ${threshold} ]]; then
      do_print2file=true
      do_echo2screen=true
    fi
  elif [[ "${lastchar}" == "=" ]]; then
    if [[ "$verbose" -eq ${threshold} ]]; then
      do_print2file=true
      do_echo2screen=true
    fi
  elif [[ "$threshold" == "" ]]; then
    # Simply echo if no second argument
    do_print2file=false
    do_echo2screen=true
  else
    # Print with warning
    string2print+="(WARNING, unknown comparator: ${lastchar})"
  fi
  
  # Clear log array, because debug flag might override
  if [[ "${do_print2file}" == false ]]; then
    unset log_array
  fi
  
  # If debug mode, then echo everything
  if [[ "${vars[debug]}" == true ]] && [[ "${string2print}" != "" ]]; then
    do_print2file=true
    
    # Remove leading newline if present
    string2print=$(echo -e $string2print | sed -z "s/^\n//g")
    
    # Prepend calling function
    string2print="${FUNCNAME[1]} : ${string2print}"
  fi
  
  # If logfile array is empty, set it to a dummy value so that it goes through the loop
  if [[ "${#log_array[@]}" -eq 0 ]]; then
    do_print2file=false
    log_array=("_")
  fi
  
  # Loop through logfile array
  for log_file in "${log_array[@]}" ; do
    if [[ "${do_print2file}" == true ]]; then
      # Check whether to print only to the log file
      local firstchar=${log_file:0:1}
      if [[ "${firstchar}" == "=" ]]; then
        do_echo2screen=false
        
        # Remove first character
        log_file=${log_file:1}
      else
        do_echo2screen=true
      fi
      
      if [[ "${do_echo2screen}" == true ]]; then
        # If no log file is specified simply write to the screen
        if [[ "${log_file}" == "" ]]; then
#           echo -e "'${#log_array[@]}' ${do_echo2screen} '${firstchar}' '${log_file}' '${string2print}'"
          echo -e "${string2print}"
        else
          # Log file name might be empty after stripping '='
          echo -e "${string2print}" | tee -a "${log_file}"
        fi
      
      # Don't echo to screen
      else
        # Log file name might be empty after stripping '='
        if [[ "$log_file" != "" ]] ; then
          # Only redirect to log file
          echo -e "${string2print}" >> "${log_file}"
          
          local status_code=$?
          if [[ "${status_code}" != 0 ]] ; then
            echo "status_code : '${status_code}'"
            echo "${FUNCNAME[1]}"
            echo "${log_file}" "$(dirname ${log_file})"
            echo -e "string2print : ${string2print}\n"
            exit
          fi
        fi
      fi
      # End echo-to-screen IF-THEN
    
    # If not printing to file but echoing to screen
    else
      if [[ "${do_echo2screen}" == true ]]; then
        echo -e "${string2print}"
      fi
    fi
    # End print-to-file IF-THEN
  done
  # End log-file loop
}

function read_mdoc() {
###############################################################################
#   Function:
#     Gets information from MDOC file
#     Currently only gets pixel size
#   
#   Calls functions:
#     check_apix_classic
#     check_range
#     vprint
#   
#   Global variables:
#     vars
#     verbose (by vprint)
###############################################################################
  
  local outlog=$1

  # Check if MDOC exists
  if [[ -f "${vars[mdoc_file]}" ]]; then
    vprint "  Found MDOC file: ${vars[mdoc_file]}" "1+" "${outlog}"
    check_apix_classic "${vars[mdoc_file]}" "${outlog}"
    check_range "defocus values" "${vars[df_lo]}" "${vars[df_hi]}" "${outlog}"
    vprint "" "7+" "${outlog}"
    check_range "frame numbers" "${vars[min_frames]}" "${vars[max_frames]}" "${outlog}"
  fi
  # End MDOC IF-THEN
  
  # Floating-point comparison from https://stackoverflow.com/a/31087503/3361621
  if (( $(echo "${vars[apix]} < 0.0" |bc -l) )); then
    vprint "\nERROR!! Pixel size ${vars[apix]} is negative!" "0+" "${outlog}"
    vprint "  Either provide pixel size (--apix) or provide MDOC file (--mdoc_file)" "0+" "${outlog}"
    vprint "  Exiting...\n" "0+" "${outlog}"
    exit 3
  else
    vprint "  Pixel size: ${vars[apix]}" "1+" "${outlog}"
  fi
}

function check_apix_pace() {
###############################################################################
#   Function:
#     Get pixel size from PACE MDOC files
#   
#   Positional variable:
#     1) output log file
#     
#   Calls functions:
#     check_apix_classic
#   
#   Global variable:
#     vars
#     
###############################################################################

  local outlog=$1
  
# #   printf "'%s'\n" "${ARGS[@]}" ; exit

  # Get first match (https://unix.stackexchange.com/a/156326)
  first_target=$(set -- ${vars[target_files]}; echo "$1")
  
  # Get first MDOC
  while read -r target_line ; do
    # Replace CRLFs
    no_crlfs=$(echo ${target_line} | sed 's/\r//')
    
    # Cut at '=' ('xargs' removes whitespace)
    local mdoc_file="$(dirname ${first_target})/$(echo $no_crlfs | cut -d'=' -f 2 | xargs).mdoc"
    break
  done <<< $(grep "^tsfile" "${first_target}")
  
  check_apix_classic "${mdoc_file}" "${outlog}"
}

function check_apix_classic() {
###############################################################################
#   Function:
#     Check pixel size
#   
#   Positional arguments:
#     1) MDOC file
#     2) Log file (optional)
#     
#   Calls functions:
#     vprint
#   
#   Global variables:
#     vars
#     verbose (by vprint)
#     
###############################################################################
  
  local mdoc_file=$1
  local outlog=$2
  
  # Get first instance of pixel size
  mdoc_apix=$(grep PixelSpacing "${mdoc_file}" | cut -d" " -f3 | head -n 1)
  
  # Strip ^M (Adapted from https://stackoverflow.com/a/8327426/3361621)
  mdoc_apix=${mdoc_apix/$'\r'/}
  
  # If no pixel size specified on the command line, then use MDOC's
  if (( $(echo "${vars[apix]} < 0.0" |bc -l) )); then
    vars[apix]="${mdoc_apix}"
    vprint "  Pixel size: ${vars[apix]}" "2+" "${outlog}"
  
  # If both the command line and MDOC files give pixel sizes, check that they're the same to 2 decimal places
  else
    cmdl_round=`printf "%.2f" "${vars[apix]}"`
    mdoc_round=`printf "%.2f" "${mdoc_apix}"`
    
    if (( $(echo "${mdoc_round} == ${cmdl_round}" |bc -l) )); then
      vprint "    WARNING! Pixel size specified on both command line (${vars[apix]}) and in MDOC file (${mdoc_apix}). Using former..." "2+" "${outlog}"
      vprint "" "3+" "${outlog}"
    else
      vprint "\nERROR!! Different pixel sizes specified on command line (${vars[apix]}) and in MDOC file (${mdoc_apix})!" "0+" "${outlog}"
      vprint "  Exiting...\n" "0+" "${outlog}"
      exit 2
    fi
  fi
  # End command-line IF-THEN
}

function check_range() {
###############################################################################
#   Function:
#     Check range of values from MDOC file
#   
#   Positional arguments:
#     1) Data description
#         "defocus values"
#         "frame numbers"
#     2) Lower limit
#     3) Upper limit
#     4) Log file (optional)
#     
#   Calls functions:
#     vprint
#   
#   Global variables:
#     vars
#     verbose (by vprint)
#     bad_counter
#     
###############################################################################
  
  local data_descr=$1
  local limitecho_lo=$2
  local limit_hi=$3
  local outlog=$4
  
  if [[ "${data_descr}" == "defocus values" ]]; then
    # Get defocus value(s)
    local list_values=$(grep Defocus ${vars[mdoc_file]} | grep -v TargetDefocus | cut -d" " -f3)
  elif [[ "${data_descr}" == "frame numbers" ]]; then
    local list_values=$(grep NumSubFrames ${vars[mdoc_file]} | cut -d" " -f3)
  else
    echo -e "\nERROR!! Data type unknown: ${data_descr} " 
    echo -e "  Exiting...\n"
    exit
  fi
  
  vprint "    Checking ${data_descr}..." "2+" "${outlog}"
  
  # Initialize counters
  local mic_counter=0
  bad_counter=0
  
  for mic_value in $list_values ; do
    # Strip ^M (Adapted from https://stackoverflow.com/a/8327426/3361621)
    local mic_value=${mic_value/$'\r'/}
    
    if [[ "${data_descr}" == "defocus values" ]]; then
      # MDOC shows defocus in microns, with underfocus negative, as opposed to CTFFIND
      local df_angs=$(echo ${mic_value}* -10000 | bc)
      local fmt_value=`printf "%.1f\n" "$df_angs"`
    elif [[ "${data_descr}" == "frame numbers" ]]; then
      local fmt_value=$(echo ${mic_value} | bc)
    else
      echo -e "\nERROR!! Data type unknown: ${data_descr} " 
      echo -e "  Exiting...\n"
      exit
    fi
    
    let "mic_counter++"
    
    if (( $(echo "${fmt_value} < ${limit_lo}" |bc -l) )) || (( $(echo "${fmt_value} > ${limit_hi}" |bc -l) )); then
        let "bad_counter++"
        vprint "      Micrograph #$mic_counter ${data_descr}: $fmt_value  (OUTSIDE OF RANGE)" "7+" "${outlog}"
    else
        vprint "      Micrograph #$mic_counter ${data_descr}: $fmt_value " "7+" "${outlog}"
    fi
  done
  
  if [[ "$bad_counter" == 0 ]]; then
    vprint "    Found $mic_counter micrographs with ${data_descr} within specified range [${limit_lo}, ${limit_hi}]" "5+" "${outlog}"
  else
    vprint "    WARNING! Found $bad_counter out of $mic_counter ${data_descr} in ${vars[mdoc_file]} outside of range [${limit_lo}, ${limit_hi}]" "2+" "${outlog}"
  fi
}

function check_dir() {
###############################################################################
#   Function:
#     Looks for directory
#   
#   Positional arguments:
#     1) search directory
#     2) directory description (for echoing purposes)
#     3) output log file
#   
#   Calls functions:
#     vprint
#   
#   Global variables:
#     validated
#     vars
#     verbose
#     imod_descr
#     ctffind_descr
#     
###############################################################################
  
  local search_dir=$1
  local dir_descr=$2
  local outlog=$3
  
  # Check if search file exists
  if [[ ! -d "${search_dir}" ]]; then
    if [[ "${vars[testing]}" == true ]]; then
      # Some directories are not strictly required for testing
      # (Notation adapted from https://unix.stackexchange.com/a/111518/504277)
      if [[ "${dir_descr}" =~ ^("${imod_descr}"|"${ctffind_descr}")$ ]]; then
        vprint "  WARNING! ${dir_descr} not found. Continuing..." "1+" "${outlog}"
      fi
    else
      validated=false
      vprint "  ERROR!! ${dir_descr} not found!" "0+" "${outlog}"
    fi
    # End testing IF-THEN
    
  else
    vprint "  Found ${dir_descr}: ${search_dir}/" "1+" "${outlog}"
  fi
  # End existence IF-THEN
    
  # CTFFIND plotting script is hardwired to /tmp/tmp.txt, will cause problems if written by someone else
  if [[ "${dir_descr}" == "${ctffind_descr}" ]]; then
    local ctffind4_tempfile="/tmp/tmp.txt"
    
    # Check if file exists
    if [[ -e "${ctffind4_tempfile}" ]]; then
      # Get owner
      tempfile_owner=$(stat -c '%U' "${ctffind4_tempfile}")
      
      # Check if you own CTFFIND's temporary file
      if [[ "${tempfile_owner}" != "$(whoami)" ]]; then
        vprint "  WARNING! ${ctffind4_tempfile} owned by ${tempfile_owner} and not you" "1+" "${outlog}"
        vprint "    CTFFIND4's ctffind_plot_results.sh writes a temporary file called '${ctffind4_tempfile}'" "2+" "${outlog}"
      fi
    fi
    # End file-exists IF-THEN
  fi
  # End CTFFIND IF-THEN
}

function check_exe() {
###############################################################################
#   Function:
#     Checks executable
#   
#   Positional arguments:
#     1) search executable
#     2) description (for echoing purposes)
#     3) output log file
#     4) conda environment (for executables requiring conda environments)
#   
#   Calls functions:
#     vprint
#     try_conda
#     debug_cuda
#
#   Global variables:
#     validated
#     
###############################################################################
  
  local search_exe=$1
  local exe_descr=$2
  local outlog=$3
  local conda_env=$4
  
  # First, check that the executable simply exists
  if [[ -f "${search_exe}" ]]; then
    vprint "  Found ${exe_descr}: ${search_exe}" "1+" "${outlog}"
    local exe_base=$(basename $search_exe)
    
#     # Check if in $PATH (adapted from https://stackoverflow.com/a/26759734/3361621)
#     if [[ "${exe_descr}" == "JANNI executable" ]] || [[ "${exe_descr}" == "Topaz executable" ]] ; then
#       if ! [[ -x $(command -v "${exe_base}") ]]; then
#         # Executable exists but isn't in the $PATH
#         try_conda "${exe_descr}" "${conda_env}" "${outlog}"
#       fi
#       
#       if [[ "${exe_descr}" == "JANNI executable" ]] ; then
#         check_file "${vars[janni_model]}" "JANNI model" "${outlog}"
#       fi
#     fi
#     # End denoising cases
  
    if [[ "${exe_descr}" == "MotionCor2 executable" ]]; then
      # Check owner of /tmp/MotionCor2_FreeGpus.txt
      local mc2_tempfile="/tmp/MotionCor2_FreeGpus.txt"
      
      # Check if file exists
      if [[ -e "${mc2_tempfile}" ]]; then
        # Try to remove it
        \rm -r ${mc2_tempfile} 2> /dev/null
        
        # Check if it still exists
        if [[ -e "${mc2_tempfile}" ]]; then
          # Get owner
          tempfile_owner=$(stat -c '%U' "${mc2_tempfile}")
          
          # Check if you own MotionCor's temporary file
          if [[ "${tempfile_owner}" != "$(whoami)" ]]; then
            if [[ "${vars[testing]}" == false ]]; then
              validated=false
              vprint "  ERROR!! ${mc2_tempfile} owned by ${tempfile_owner} and not you!" "1+" "${outlog}"
              vprint "    MotionCor writes a temporary file called '${mc2_tempfile}'." "2+" "${outlog}"
              vprint "    Get the owner to delete this file." "2+" "${outlog}"
            else
              vprint "  WARNING! ${mc2_tempfile} owned by ${tempfile_owner} and not you" "1+" "${outlog}"
              vprint "    MotionCor writes a temporary file called '${mc2_tempfile}'" "2+" "${outlog}"
            fi
          fi
          # End not-owner IF-THEN
        fi
        # End still-exists IF-THEN
      fi
      # End file-exists IF-THEN
      
#       # Run program without any arguments, and check exit status (TODO: not working)
#       debug_cuda "${search_exe}" "${exe_descr}"
#       # (TODO: Might work with AreTomo with minimal changes)
    fi
    # End MotionCor case
  else
    if [[ "${vars[testing]}" == true ]]; then
      vprint    "  WARNING! ${exe_descr} not found. Continuing..." "1+" "${outlog}"
    else
      validated=false
      echo "  ERROR!! ${exe_descr} not found!"
    fi
  fi
  # End PATH check
}

function try_conda() {
###############################################################################
#   Function:
#     Tries to find conda environment
#   
#   Positional arguments:
#     1) description (for echoing purposes)
#     2) conda environment
#     3) output log file
#   
#   Global variables:
#     vars
#     
###############################################################################
  
  local exe_descr=$1
  local conda_env=$2
  local outlog=$3
  
  if [[ "${vars[testing]}" == "false" ]]; then
    vprint "    Current conda environment: ${CONDA_DEFAULT_ENV}" '2+' "${outlog}"
    vprint "    Temporarily activating conda environment: ${conda_env}" "1+" "${outlog}"
    
    vprint '    Executing: eval "$(conda shell.bash hook)"' "2+" "${outlog}"
    eval "$(conda shell.bash hook)"
    # (Can't combine the eval command into a variable and run it, for some reason)
    
    local conda_cmd="conda activate ${conda_env}"
    vprint "    Executing: $conda_cmd" "2+" "${outlog}"
    $conda_cmd
    
    # Sanity check
    if [[ "${CONDA_DEFAULT_ENV}" == "${conda_env}"  ]]; then
      vprint "    New conda environment: ${CONDA_DEFAULT_ENV}" "2+" "${outlog}"
    else
      echo -e "\nERROR!! Conda environment not found: ${conda_env}"
      echo    "Install ${conda_env} or disable option!"
      echo -e "Exiting...\n"
      exit
    fi
    
    # Matplotlib won't work later on
    conda deactivate
  fi
  # End testing IF-THEN
}

function debug_cuda() {
###############################################################################
#   Function:
#     Check CUDA programs and try to identify any incompatibility
#     Specifically for MotionCor2, but may work for AreTomo
#   
#   Positional arguments:
#     1) search executable
#     2) description (for echoing purposes)
#     3) output log file
#   
#   Calls functions:
#     check_exe
#   
#   Called by:
#     check_exe (also)
#   
###############################################################################
  
  local search_exe=$1
  local exe_descr=$2
  local exe_base=$(basename $search_exe)
  local outlog=$3
  
  # Run program without any arguments, and check exit status
  # (Adapted from https://stackoverflow.com/a/962268/3361621)
  local error_code=$($search_exe 2>&1 /dev/null)
  
  # Should get exit code 1 because inputs weren't provided
  if [[ "${status_code}" == "1"  ]]; then
    vprint "    Executable OK: ${exe_base}" "2+" "${outlog}"
  
  # Exit code 0 means success, which it shouldn't without input files
  elif [[ "${status_code}" == "0"  ]]; then
    echo -e "\nERROR!! ${exe_base} (with no inputs) should return an error (instead returned ${status_code})"
    echo -e "  Exiting...\n"
    exit
  
  else
    echo -e "\nERROR!! Reported by: ${exe_base}:"
    echo -e "  ${error_code}\n"
    
    # Check CUDA version
    echo "Checking CUDA version..."
    check_exe "$(command -v cuda)" "CUDA compiler"
    
    local nvcc_output=$(nvcc --version 2>&1)
    local cuda_version=$(echo ${nvcc_output#*release} | cut -d' ' -f1 | sed '$s/,$//')
    # (Syntax to remove trailing comma: https://www.unix.com/shell-programming-and-scripting/216582-how-remove-comma-last-character-end-last-line-file.html)
    echo -e "  CUDA version: ${cuda_version}"
    
    # Check for link or file ("command" expands path, "realpath" follows links)
    local following_links=$( basename $( realpath $(command -v ${search_exe}) ) )
    local version_number=`echo ${following_links} | awk -F"Cuda" '{print $2}' | awk -F"-" '{print $1}'`
    # For AreTomo: echo ${following_links} | awk -F"Cuda" '{print $2}'
    
    echo    "  ${exe_descr} version is: ${version_number} (full path: ${following_links})"
    echo -e "  Maybe there's a version incompatibility?\n"
    
    echo -e "  Exiting...\n"
  fi
}

function check_targets() {
###############################################################################
#   Function:
#     Looks for target files
#   
#   Positional arguments:
#     1) output log file
#   
#   Calls functions:
#     vprint
#     
#   Global variables:
#     validated
#     vars
#     
###############################################################################
  
  local outlog=$1
  
# #   read -a target_array <<< "${vars[target_files]}"
  target_array=$(ls ${vars[target_files]} 2> /dev/null)  # will exclude non-existent files
#   echo "target_files: '${vars[target_files]}'"
#   printf "'%s'\n" "${target_array[@]}"
#   exit
  local num_targets=$(echo $target_array | wc -w)
  
  if [[ "${num_targets}" -eq 0 ]]; then
    validated=false
    echo -e "  ERROR!! At least one target file is required!\n"
    exit 3
  elif [[ "${num_targets}" -eq 1 ]]; then
    vprint "  Found target file: ${target_array[0]}" "1+" "${outlog}"
  else
    vprint "  Found ${num_targets} targets files" "1+" "${outlog}"
  fi
}

function check_file() {
###############################################################################
#   Function:
#     Looks for file
#   
#   Positional arguments:
#     1) search filename
#     2) file type (for echoing purposes)
#     3) output log file
#   
#   Calls functions:
#     vprint
#     howto_frame
#     
#   Global variables:
#     validated
#     vars
#     
###############################################################################
  
  local search_file=$1
  local file_type=$2
  local outlog=$3
  
  # Check if search file exists
  if [[ ! -f "${search_file}" ]]; then
    validated=false
    echo "  ERROR!! ${file_type^} not found: ${search_file}"
    # ("${string^}" capitalizes first letter: https://stackoverflow.com/a/12487455)
  
    # Print instructions on creating a frame file
    if [[ "${file_type^}" == "frame file" ]]; then
      howto_frame
    fi
    
    if [[ "${vars[testing]}" == true ]]; then
      echo    "    To validate testing, type:"
      echo -e "      touch ${search_file}"
    fi
    
  else
    vprint "  Found ${file_type}: ${search_file}" "1+" "${outlog}"
  fi
  # End existence IF-THEN
}

function check_mc2() {
###############################################################################
#   Function:
#     Checks MotionCor2 parameters
# #     The '-OutStack' '-SplitSum' options seem to require more memory.
#   
#   Calls functions:
#     vprint
#     
#   Global variables:
#     validated
#     vars
#     verbose
#     
###############################################################################
  
  # Check old MotionCor syntax
  if [[ "${vars[split_sum]}" == 1 ]] ; then
    vprint "  WARNING! Syntax '--split_sum=1' is deprecated." "1+" "${outlog}"
    vprint "    Use 'do_splitsum' instead. Continuing..." "1+" "${outlog}"
  fi
#   
#   # Check how many GPUs were requested
#   num_gpus=$(echo ${vars[gpus]} | wc -w)
#   
#   if [[ "$num_gpus" -gt 3 ]]; then
#     if [[ "${vars[testing]}" == true ]]; then
#       vprint "  WARNING! Please reduce the number of GPUs from ${num_gpus} to 3 or fewer. Continuing..." "1+" "${outlog}"
#     else
#       validated=false
#       vprint "  ERROR!! Please reduce the number of GPUs from ${num_gpus} to 3 or fewer!" "0+" "${outlog}"
#     fi
#   fi
}

function howto_frame() {
  echo    "  The frame file is a text file containing the following three values, separated by spaces:"
  echo    "    1) The number of frames to include"
  echo    "    2) The number of EER frames to merge in each motion-corrected frame"
  echo -e "    3) The dose per EER frame\n"
  
  echo    "  For the second value, a reasonable rule of thumb is to accumulate 0.15-0.20 electrons per A2."
  echo    "    For example, at a dose of 3e/A2 distributed over 600 frames, the dose per EER frame would be 0.005."
  echo    "    To accumulate 0.15e/A2, you would need to merge 0.15/(3/600) = 30 frames."
  echo    "    The line in the frame file would thus be:"
  echo -e "      600 30 0.005\n"
  
  echo    "  The first N frames can be handled differently than the next M frames, "
  echo    "    and thus the frame file would contain multiple lines, on for each set of conditions."
  echo -e "    However, we haven't tested this functionality yet.\n"
  
  echo -e "  For more information, see MotionCor2 manual.\n\n"
}

function check_gain_format() {
###############################################################################
#   Function:
#     Checks format of gain file
#   
#   Positional argument:
#     1) output log file
#   
#   Calls function:
#     vprint
#     
#   Global variables:
#     vars
#     main_log
#     outdir
#     
###############################################################################
  
  local outlog=$1
  
  # Check if MRC or TIFF
  local ext=`echo "${vars[gain_file]}" | rev | cut -d. -f1 | rev`
  
  vprint "Gain file format: $ext" "1+" "${main_log}"
  
  if [[ ! "$ext" == "mrc" ]]; then
    # Remove extension (last period-delimited string)
    local stem_gain="$(file_stem ${vars[gain_file]})"
    local mrc_gain="${vars[outdir]}/${stem_gain}.mrc"
    
    # Build command
    local cmd="${vars[imod_dir]}/tif2mrc ${vars[gain_file]} ${mrc_gain}"
    
    # Assume it's a TIFF, and try to convert it
    vprint "  Attempting conversion..." "1+" "${main_log}"
    vprint "    Running: $cmd\n" "1+" "${main_log}"
    
    if [[ "${vars[testing]}" == false ]]; then
      if [[ "$verbose" -ge 1 ]]; then
        $cmd | sed 's/^/    /'
      else
        $cmd > /dev/null
      fi
      
      # Check exit status
      local status_code=$?
      # (0=successful, 1=fail)
      
      if [[ ! "$status_code" == 0 ]]; then
        echo -e "ERROR!! tif2mrc failed with exit status $status_code\n"
        exit
      fi
      
      # Update gain file
      vars[gain_file]="${mrc_gain}"
    fi
    # End testing IF-THEN
  
  fi
  # End MRC IF-THEN
}

function check_python() {
###############################################################################
#   Function:
#     Checks Python version and libraries
#   
#   Positional arguments:
#     1) output log file
#   
#   Calls functions:
#     vprint
#
#   Global variables:
#     validated
#     verbose
#     
###############################################################################
  
  local outlog=$1
  
  # Check Python version
  local python_version=$(python --version | cut -d' ' -f2 | cut -d'.' -f1)
  
  if [[ "$python_version" -le 2 ]]; then
    validated=false
    vprint "  ERROR!! Python needs to be version 3 or higher!" "0+" "${outlog}"
  else
    vprint "  Python version OK" "6+" "${outlog}"
  fi
  
  # Check the following libraries
  declare -a lib_array=("sys" "numpy" "scipy" "matplotlib" "os" "argparse" "datetime")
  declare -a not_found=()
  
  # Loop through libraries
  for curr_lib in ${lib_array[@]}; do
    # Try to import, and store status code
    python -c "import ${curr_lib}" 2> /dev/null
    local status_code=$?
    
    # If it fails, then save
    if [[ "$status_code" -ne 0 ]]; then
      vprint "    Couldn't find: '${curr_lib}'" "7+" "${outlog}"
      not_found+=("${curr_lib}")
    else
      vprint "    Found: '${curr_lib}'" "7+" "${outlog}"
    fi
  done
  # End library loop
  
  if [[ "${#not_found[@]}" > 0 ]] ; then
    validated=false
    vprint "  ERROR!! Couldn't find the following Python libraries: ${not_found[*]}" "0+" "${outlog}"
  else
    vprint "  Python version and libraries OK" "1+" "${outlog}"
  fi
}

function file_stem() {
###############################################################################
#   Function:
#     Splits directory name and extension from filename
#   
#   Positional variables:
#     1) filename
#   
###############################################################################

  local filename=$1
  
  # Remove extension (last period-delimited string)
  local stem=`basename $filename | rev | cut -d. -f2- | rev`
  # (Syntax adapted from https://unix.stackexchange.com/a/64673)
  
  echo $stem
}

function update_adoc() {
###############################################################################
#   Function:
#     Updates batch directive to include correct pixel size
#   
#   Positional variables:
#     log file
#   
#   Calls functions:
#     vprint
#   
#   Global variables:
#     vars
#   
###############################################################################
  
  local outlog=$1
  
  if ! [[ -f "${vars[batch_directive]}" ]]; then
    return
  fi
  
  # Copy batch directive to output directory
  cp "${vars[batch_directive]}" "${vars[outdir]}"
  
  # Use copy from now on
  local new_adoc="${vars[outdir]}/$(basename ${vars[batch_directive]})"
  vars[batch_directive]="${new_adoc}"
  
  # Check if setupset.copyarg.pixel is present
  local search_term="setupset.copyarg.pixel"
  local pxsz_nm=$( printf "%.4f" $(bc <<< "scale=4; ${vars[apix]}/10") )
  local new_line="${search_term}=${pxsz_nm}"
  
  if grep -q ${search_term} "$new_adoc" ; then
    local old_line=$(grep ${search_term} ${new_adoc})  # | sed 's/\r//')
    sed -i "s/.*$old_line.*/$new_line/" $new_adoc
    # Double quotes are required here for some reason.
    # (Wild card ".*" replaces whole line)
    
    vprint "    Updated pixel size $pxsz_nm nm (${vars[apix]} A) in ADOC file '$new_adoc'" "1+"
    
  else
    local dual_term="setupset.copyarg.dual"
    
    # Check if copyarg.dual is in this ADOC
    if grep -q "$dual_term" "$new_adoc" ; then
      # Get line number and add 1
      local line_num=$(echo $(sed -n "/$dual_term/=" $new_adoc) + 1 | bc)
      sed -i "${line_num} i ${new_line}" $new_adoc
    else
      # Add it at line 5
      sed -i "5 i ${new_line}" $new_adoc
    fi
    # End dual-found IF-THEN
  
    vprint "    Added pixel size $pxsz_nm nm (${vars[apix]} A) in ADOC file '$new_adoc'" "1+"
  fi
  # End pixel-found IF-THEN
}

function check_frames() {
###############################################################################
#   Function:
#     Checks number of frames
#   
#   Positional variable:
#     1) output log file
#     
#   Requires:
#     IMOD's header program
#   
#   Global variables:
#     Imod_bin
#     fn
#     min_frames
#     max_frames
#     verbose
#     
###############################################################################
  
  local outlog=$1
  
  # Get number of frames
  if [[ "${vars[testing]}" == false ]]; then
    local section_line=$("${vars[imod_dir]}"/header $fn | grep sections)
  fi
  local num_sections=$(echo $section_line | rev | cut -d" " -f1 | rev)
  
  if [[ "$verbose" -ge 1 ]]; then
    if [[ "${outlog}" != "" ]]; then
      echo -e "    Micrograph $fn  \tnumber of frames: $num_sections\n" >> "${outlog}"
    else
      echo -e "    Micrograph $fn  \tnumber of frames: $num_sections\n"
    fi
  fi
  
  # Check if within range
  if [[ "$verbose" -ge 1 ]]; then
    if [[ "$num_sections" -lt "${vars[min_frames]}" || "$num_sections" -gt "${vars[max_frames]}" ]]; then
      vprint "    WARNING! Micrograph $fn: number of frames ($num_sections) outside of range (${vars[min_frames]} to ${vars[max_frames]})\n" "0+" "${outlog}"
    fi
  fi
}

function run_motioncor() {
###############################################################################
#   Function:
#     Returns MotionCor command line (as an echo statement)
#   
#   Positional variable:
#     1) EER file
#     2) GPU number
#     
#   Calls functions:
#     vprint
#   
#   Global variables:
#     vars
#     cor_mic
#     mc2_logs
#     stem_eer
#     
###############################################################################
  
  local fn=$1
  local gpu_num=$2
  
  # Initialize command
  local mc_command=""
  
  if [[ "${vars[testing]}" == true ]]; then
    local mc_exe="$(basename ${vars[motioncor_exe]})"
  else
    local mc_exe=${vars[motioncor_exe]}
  fi
  
  mc_command="    ${mc_exe} \
  -InEer $fn \
  -Gain ${vars[gain_file]} \
  -FmIntFile ${vars[frame_file]} \
  -OutMrc $cor_mic  \
  -Patch ${vars[mcor_patches]} \
  -FmRef ${vars[reffrm]} \
  -Iter 10  \
  -Tol 0.5 \
  -Serial 0 \
  -SumRange 0 0 \
  -Gpu ${gpu_num} \
  -LogFile ${vars[outdir]}/$micdir/${mc2_logs}/${stem_eer}_mic.log"
  
  if [[ "${vars[split_sum]}" == 1 || "${vars[do_splitsum]}" == true ]]; then
    mc_command="${mc_command} -SplitSum 1"
  fi

  if [[ "${vars[do_dosewt]}" == true ]]; then
    mc_command="${mc_command} \
    -Kv ${vars[kv]} \
    -PixSize ${vars[apix]} \
    "
  fi

  if [[ "${vars[do_outstack]}" == true ]]; then
    mc_command="${mc_command} -Outstack 1"
  fi

  echo ${mc_command} | xargs
  # (xargs removes whitespace)
}

function run_ctffind4() {
###############################################################################
#   Function:
#     Runs CTFFIND4
#     Default behavior is to NOT overwrite pre-existing outputs.
#   
#   Global variables:
#     verbose
#     vars
#     cor_mic
#     ctf_mrc
#     avg_rot
#     ctf_exe
###############################################################################

  local do_run=$1
  
  # Simply print command
  if [[ "${do_run}" != "true" ]]; then
    if [[ "$verbose" -ge 5 ]]; then
      echo "    ${ctf_exe} \
$cor_mic \
$ctf_mrc \
${vars[apix]} \
${vars[kv]} \
${vars[cs]} \
${vars[ac]} \
${vars[box]} \
${vars[res_lo]} \
${vars[res_hi]} \
${vars[df_lo]} \
${vars[df_hi]} \
${vars[df_step]} \
no \
no \
yes \
${vars[ast_step]} \
no \
no"
  
      if [[ "${vars[testing]}" == true ]]; then
        echo "    TESTING ctffind_plot_results.sh $avg_rot"
      fi
    fi
    # End verbose IF-THEN
  fi
  # End printing IF-THEN
  
  # Actually run
  if [[ "${do_run}" == "true" ]]; then
    "${vars[ctffind_dir]}"/ctffind << eof
$cor_mic
$ctf_mrc
${vars[apix]}
${vars[kv]}
${vars[cs]}
${vars[ac]}
${vars[box]}
${vars[res_lo]}
${vars[res_hi]}
${vars[df_lo]}
${vars[df_hi]}
${vars[df_step]}
no
no
yes
${vars[ast_step]}
no
no
eof
        
  fi
  # End testing IF-THEN
}

function janni_denoise() {
###############################################################################
#   Function:
#     Runs JANNI denoising
#
#   Positional variables:
#     1) output log
#     2) (optional) GPU number 
#   
#   Global variables:
#     gpu_num
#     vars
#     denoisedir
#     
###############################################################################
  
  local outlog=$1
  gpu_num=$2  # might be updated
  
  # Get single GPU number if there are more than one
  get_gpu

  # Optionally use CPU
  if [[ "${vars[denoise_gpu]}" == false ]]; then
    gpu_num=-1
  fi
  
  local janni_args="--ignore-gooey denoise --overlap=${vars[janni_overlap]} --batch_size=${vars[janni_batch]} --gpu=${gpu_num} -- ${vars[outdir]}/${micdir} ${vars[outdir]}/${denoisedir}_tmp ${vars[janni_model]}"
  local janni_cmd="janni_denoise.py ${janni_args}"
    
  vprint "$(date +"$time_format"): Denoising using JANNI..." "3+" "=${outlog}"
  
  if [[ "${vars[testing]}" == false ]]; then
    local conda_cmd="conda activate ${vars[janni_env]}"
    vprint "    Executing: $conda_cmd" "2+" "=${outlog}"
    $conda_cmd
    
    vprint "\n  Denoising using JANNI..." "3+" "=${outlog}"
    vprint   "    Running: janni_denoise.py ${janni_args}" "3+" "=${outlog}"
    
    # Run JANNI
    if [[ "$verbose" -le 2 ]]; then
      $janni_cmd 2>&1 > /dev/null
      # Suppress all output
      
    elif [[ "$verbose" -eq 6 ]]; then
      vprint "    $(date)" "6=" "=${outlog}"
      
      # https://stackoverflow.com/a/2409214
      { time ${janni_cmd} 2> /dev/null ; } 2>&1 | grep real | sed 's/real\t/    Run time: /'
      # Do NOT use quotes around ${janni_cmd} above...
    elif [[ "$verbose" -ge 7 ]]; then
      time $janni_cmd
    else
      $janni_cmd 2> /dev/null >> "${outlog}"
      # (Output will be written in chunks to the log file.)
    fi
    
    # JANNI writes output to <output_directory>/<input_directory>, so fix it.
    mv ${vars[outdir]}/${denoisedir}_tmp/${micdir}/* ${vars[outdir]}/${denoisedir}/ && rmdir -p ${vars[outdir]}/${denoisedir}_tmp
    vprint "    Denoised $(ls ${vars[outdir]}/${denoisedir}/${prev_name}*_mic.mrc | wc -w) micrographs\n" "3+" "=${outlog}"
    
    # Clean up
    conda deactivate
    vprint "conda environment: $CONDA_DEFAULT_ENV\n" "3+" "=${outlog}"
  
  # Testing
  else
    vprint "\n  TESTING: janni_denoise.py ${janni_args}\n" "3+" "=${outlog}"
  fi
  # End testing IF-THEN
}

function topaz_denoise() {
###############################################################################
#   Function:
#     Runs Topaz denoising
#
#   Positional variables:
#     1) output log
#     2) (optional) GPU number 
#   
#   Global variables:
#     gpu_num
#     vars
#     denoisedir
#     
###############################################################################
  
  local outlog=$1
  gpu_num=$2  # might be updated
  
  # Get single GPU number if there are more than one
  get_gpu

  # Optionally use CPU
  if [[ "${vars[denoise_gpu]}" == false ]]; then
    gpu_num=-1
  fi
  
  local topaz_args="denoise ${vars[outdir]}/${micdir}/${prev_name}*_mic.mrc --device ${gpu_num} --patch-size ${vars[topaz_patch]} --output ${vars[outdir]}/${denoisedir}"
  local topaz_cmd="timeout ${vars[topaz_time]} topaz ${topaz_args}"
    
  if [[ "${vars[testing]}" != true ]]; then
    local conda_cmd="conda activate ${vars[janni_env]}"
    vprint "    Executing: $conda_cmd" "2+" "${outlog}"
    $conda_cmd
    
    vprint "$(date +"$time_format"): Denoising using Topaz..." "3+" "${main_log}"
    vprint "\n  Denoising using Topaz..." "3+" "=${outlog}"
    vprint   "    Running: topaz ${topaz_args}" "3+" "=${outlog}"
    
    # Run Topaz
    if [[ "$verbose" -le 2 ]]; then
      $topaz_cmd 2>&1 > /dev/null
      # Suppress all output
      
    elif [[ "$verbose" -eq 6 ]]; then
      vprint "    $(date)" "6=" "=${outlog}"
      
      # https://stackoverflow.com/a/2409214
      { time ${topaz_cmd} 2> /dev/null ; } 2>&1 | grep real | sed 's/real\t/    Run time: /'
      local status_code=("${PIPESTATUS[0]}")
      # Do NOT use quotes around ${topaz_cmd} above...
    elif [[ "$verbose" -ge 7 ]]; then
      time $topaz_cmd
      local status_code=("${PIPESTATUS[0]}")
    else
      $topaz_cmd 2> /dev/null
      local status_code=("${PIPESTATUS[0]}")
    fi
    
    # TODO: Figure out why Topaz hangs sometimes
    vprint "    Topaz complete, status code: ${status_code}" "3+" "=${outlog}"
    vprint "    Denoised $(ls ${vars[outdir]}/${denoisedir}/${prev_name}*_mic.mrc | wc -w) micrographs\n" "3+" "=${outlog}"
  
    # Clean up
    conda deactivate
    vprint "conda environment: $CONDA_DEFAULT_ENV" "3+" "=${outlog}"
  
  # Testing
  else
    vprint "\n  TESTING: topaz ${topaz_args}\n" "3+" "=${outlog}"
  fi
  # End testing IF-THEN
}

function get_gpu() {
###############################################################################
#   Function:
#     Gets single GPU number
#     Intended for serial GPU usage
#   
#   Global variables:
#     gpu_num
#     vars
#   
###############################################################################
  
#   echo "gpu_num, before '${gpu_num}'"
  
  if [[ "$gpu_num" == "" ]]; then
    # If GPU number specified, use it
    if [[ "${vars[gpus]}" != "" ]]; then
      gpu_num=$(echo "${vars[gpus]}" | awk '{print $1}')
    else
      # Use CPU, if allowed
      gpu_num="-1"
    fi
  fi
  
#   echo "gpu_num, after '${gpu_num}'"
}

function sort_array_keys() {
###############################################################################
#   Function:
#     Sort array accourding to angle
#   
#   Global variables:
#     stripped_angle_array
#     
###############################################################################
  
  # Sort by angle (Adapted from https://stackoverflow.com/a/54560296)
  for KEY in ${!stripped_angle_array[@]}; do
    echo "${stripped_angle_array[$KEY]}:::$KEY"
  done | sort -n | awk -F::: '{print $2}'
}

function write_angles_lists() {
###############################################################################
#   Function:
#     Write angles to file
#     
#   Positional variables:
#     1) output log file
#   
#   Global variables:
#     stripped_angle_array
#     mcorr_mic_array
#     denoise_array
#     vars
#     mcorr_list
#     denoise_list
#     angles_list
#     
###############################################################################
  
  local outlog=$1

  # Sort
  sorted_keys=$(sort_array_keys "${stripped_angle_array[@]}")
#   printf "  '%s'\n" "${sorted_keys[@]}"
#   printf "  '%s'\n" "${stripped_angle_array[@]}"
  
  # Write new IMOD list file (overwrites), starting with number of images
  echo ${#mcorr_mic_array[*]} > $mcorr_list
  if [[ "${vars[do_topaz]}" == true ]]; then
    echo ${#denoise_array[*]} > $denoise_list
  fi
  
  # Delete pre-existing angles file (AreTomo will crash if appended to)
  if [[ -f "$angles_list" ]]; then
    \rm $angles_list
  fi
  
  # Loop through sorted keys 
  for idx in $sorted_keys ; do
    echo    "${stripped_angle_array[${idx}]}" >> $angles_list
    echo -e "${mcorr_mic_array[$idx]}\n/" >> $mcorr_list
    if [[ "${vars[do_topaz]}" == true ]]; then
      echo -e "${denoise_array[$idx]}\n/" >> $denoise_list
    fi
  done  
  
  vprint "  Wrote list of ${#stripped_angle_array[*]} angles to $angles_list" "2+" "=${outlog}"
  vprint "  Wrote list of ${#mcorr_mic_array[*]} images to $mcorr_list" "2+" "=${outlog}"
  if [[ "${vars[do_topaz]}" == true ]]; then
    vprint "  Wrote list of ${#denoise_array[*]} images to $denoise_list" "2+" "=${outlog}"
  fi
  
  vprint "" "2+" "=${outlog}"

  # Clean up
  unset mcorr_mic_array
  unset denoise_array
  unset stripped_angle_array
}

function imod_restack() {
###############################################################################
#   Function:
#     Runs IMOD's restack
#     Default behavior is to NOT overwrite pre-existing outputs.
#     
#   Positional variables:
#     1) output log file
#   
#   Global variables:
#     tomo_root
#     vars
#     mcorr_list
#     denoise_list
#     reordered_stack : output
#     verbose
#     main_log
#     warn_log
#     
###############################################################################
  
  local outlog=$1

  # Output files
  local newstack_log="${tomo_root}_newstack.log"
  
  # Choose list for restacking
  if [[ "${vars[do_janni]}" == true ]] && [[ "${vars[do_topaz]}" == true ]]; then
    local imod_list="${denoise_list}"
  else
    local imod_list="${mcorr_list}"
  fi
  
  # AreTomo and IMOD expect different extensions for stacks
  if [[ "${vars[do_etomo]}" == false ]]; then
    reordered_stack="${tomo_root}_newstack.mrc"
  else
    reordered_stack="${tomo_root}_newstack.st"
  fi

  # Delete pre-existing file (IMOD will back it up otherwise)
  if [[ -f "$reordered_stack" ]]; then
    \rm $reordered_stack
  fi
  
  if [[ "${vars[testing]}" == false ]]; then
    # Check if output already exists
    if [[ ! -e $reordered_stack ]]; then
      vprint "  Running: newstack -filei $imod_list -ou $reordered_stack\n" "3+" "=${outlog}"
      
      if [[ "$verbose" -ge 8 ]]; then
        "${vars[imod_dir]}"/newstack -filei $imod_list -ou $reordered_stack 2>&1 | tee $newstack_log
      elif [[ "$verbose" -ge 6 ]]; then
        # "${vars[imod_dir]}"/newstack -filei $imod_list -ou $reordered_stack | tee $newstack_log | grep --line-buffered "RO image"
        "${vars[imod_dir]}"/newstack -filei $imod_list -ou $reordered_stack | tee $newstack_log | stdbuf -o0 grep "RO image" | sed 's/^/   /'
        # line-buffered & stdbuf: https://stackoverflow.com/questions/7161821/how-to-grep-a-continuous-stream
      else
        "${vars[imod_dir]}"/newstack -filei $imod_list -ou $reordered_stack > $newstack_log
      fi
    
      # Sanity check
      if [[ ! -f "$reordered_stack" ]]; then
        # Check log file for errors
        if grep --quiet ERROR $newstack_log ; then
          grep ERROR $newstack_log | sed 's/^/  /'
        fi
        
        if [[ "$verbose" -ge 1 ]]; then
          vprint "WARNING! restack output $reordered_stack does not exist!" "0+" "${main_log} =${outlog} =${warn_log}"
          vprint "         Continuing...\n" "0+" "${main_log} =${outlog} =${warn_log}"
        fi
      fi
    
    # If pre-existing output (shouldn't exist, since we deleted any pre-existing stack above)
    else
      vprint "  IMOD restack output $reordered_stack already exists" "0+" "=${outlog}"
      vprint "    Skipping...\n" "0+" "=${outlog}"
    fi
    # End pre-existing IF-THEN
  
  # Testing
  else
    vprint "  TESTING newstack -filei $imod_list -ou $reordered_stack" "3+" "=${outlog}"
  fi
  # End testing IF-THEN
}

function wrapper_aretomo() {
###############################################################################
#   Function:
#     Wrapper for AreTomo
#     Default behavior is to BACK UP pre-existing reconstruction only (can be overridden).
#   
#   Positional variable:
#     1) number of micrographs in tilt series
#     2) GPU number
#     3) (boolean) redo pre-existing reconstruction (default: true, old file backed up)
#     
#   Calls functions:
#     run_aretomo
#   
#   Global variables:
#     tomo_root
#     vars
#     reordered_stack
#     tomogram_3d (OUTPUT)
#     angles_list
#     verbose
#     
###############################################################################
  
  local num_mics=$1
  local gpu_num=$2
  
  if [[ "$3" == "" ]]; then
    local do_overwrite=true
  else
    local do_overwrite=false
  fi
  local do_reconstruct=true
  
  # Output files
  tomogram_3d="${tomo_root}_aretomo.mrc"
  local aretomo_log="${tomo_root}_aretomo.log"
  local aretomo_cmd=$(run_aretomo ${gpu_num})
  
  # Run AreTomo
  if [[ "${vars[testing]}" != true ]]; then
    # Check if output already exists
    if [[ -e $tomogram_3d ]]; then
      if [[ "${do_overwrite}" == false ]] && [[ "${vars[no_redo3d]}" != "false" ]] ; then
        do_reconstruct=false
        
        if [[ "$verbose" -ge 2 ]]; then
          echo -e "\n  AreTomo output $tomogram_3d already exists, skipping..."
        else
          mv $tomogram_3d ${tomogram_3d}.bak
        fi
      else
        if [[ "$verbose" -ge 2 ]]; then
          echo -e "\n  WARNING: AreTomo output $tomogram_3d already exists"
          echo "    $(mv -v $tomogram_3d ${tomogram_3d}.bak)"
        else
          mv $tomogram_3d ${tomogram_3d}.bak
        fi
      fi
    fi
    
    if [[ "${do_reconstruct}" == true ]] ; then
      aretomo_cmd="timeout ${vars[are_time]} ${aretomo_cmd}"
      
      if [[ "$verbose" -ge 4 ]]; then
        echo -e "\n  $(date)"
        echo      "  Computing tomogram reconstruction '`basename $tomogram_3d`' from $num_mics micrographs on GPU #${gpu_num}"
        echo -e "\n  Running: ${aretomo_cmd}"
      elif [[ "$verbose" -eq 3 ]]; then
        echo      "  Computing tomogram reconstruction '`basename $tomogram_3d`' from $num_mics micrographs on GPU #${gpu_num}"
      fi

      if [[ "$verbose" -ge 7 ]]; then
        ${aretomo_cmd} 2>&1 | tee $aretomo_log
        status_code=("${PIPESTATUS[0]}")
      
      elif [[ "$verbose" -ge 6 ]]; then
        ${aretomo_cmd} | tee $aretomo_log | stdbuf -o0 grep "tilt axis" | sed 's/^/    /'
        status_code=("${PIPESTATUS[0]}")
        # (Save exit code after piping to tee: https://stackoverflow.com/a/6871917)
        
        # Print summary (after printing incremental tilt estimates)
        grep "Rotation align score" $aretomo_log | sed 's/^/    /'
        grep "Total time" $aretomo_log | sed 's/^/    /'
    
      # Quiet mode
      elif [[ "$verbose" -le 1 ]]; then
        ${aretomo_cmd} > $aretomo_log
        status_code=("${PIPESTATUS[0]}")
      
      # Sort-of-quiet mode
      else
        echo "Please wait..."
        
        ${aretomo_cmd} > $aretomo_log
        status_code=("${PIPESTATUS[0]}")
      
        # Print summary
        echo 
        grep "Error" $aretomo_log | sed 's/^/    /'
        grep "New tilt axis" $aretomo_log | tail -n 1 | sed 's/^/    /'
        grep "Rotation align score" $aretomo_log | sed 's/^/    /'
        grep "Total time" $aretomo_log | sed 's/^/    /'
      fi
      # End verbosity cases
      
  # #     echo -e "\nstatus_code: '$status_code'\n"  # TESTING will go to recon log
      
      # Sanity check
      if [[ ! -f "$tomogram_3d" ]]; then
        if [[ "$verbose" -ge 1 ]]; then
          echo    ""
          date
          if [[ "$status_code" -eq 139 ]]; then
            echo    "WARNING! AreTomo output $tomogram_3d does not exist!"
            echo    "         Exit status code was: $status_code, maybe a segmentation fault"
          elif [[ "$status_code" -eq 2 ]]; then
            echo    "WARNING! AreTomo output $tomogram_3d does not exist!"
            echo    "         Exit status code was: $status_code"
            echo    "         Maybe an input was missing or illegal (check length)"
          elif [[ "$status_code" -eq 127 ]]; then
            echo    "WARNING! AreTomo output $tomogram_3d does not exist!"
            echo    "         Exit status code was: $status_code"
            echo    "         Maybe CUDA version is incorrect?"
          elif [[ "$status_code" -eq 0 ]]; then
            echo    "  SUCCESS!! AreTomo completed with exit status '$status_code'"
          else
            echo    "WARNING! AreTomo output $tomogram_3d does not exist!"
            echo    "         Maybe maximum direction (${vars[are_time]}) was reached"
            echo    "         Exit status code was: $status_code"
          fi
          
          echo -e "         Continuing...\n"
        fi
        
        return
      
      # Tomogram found
      else
        get_central_slice ${tomogram_3d}
      fi
      # End do-reconstruct IF-THEN
    fi
    # End do-reconstruction IF-THEN
  
  # Testing
  else
    if [[ "${do_overwrite}" == false ]] && [[ "${vars[no_redo3d]}" != "false" ]] ; then
      if [[ "$verbose" -ge 2 ]]; then
        echo -e "\n  AreTomo output $tomogram_3d already exists, skipping..."
      fi
    else
      if [[ "$verbose" -ge 4 ]]; then
        echo -e "\n  TESTING ${aretomo_cmd}"
      elif [[ "$verbose" -eq 3 ]]; then
        echo      "  TESTING tomogram reconstruction '`basename $tomogram_3d`' from $num_mics micrographs"
      fi
      
      touch "$tomogram_3d"
    fi
    # End overwrite IF-THEN
  fi
  # End testing IF-THEN
  
  vprint "" "2+"
}


function mdoc2tomo() {
###############################################################################
#   Function:
#     Construct filename from tomographic reconstruction from MDOC file
#   
#   Positional variables:
#     1. MDOC filename (can be full path)
#   
#   Global variables:
#     vars
#     tomo_base
#     recdir
#     tomo_dir
#     tomo_root
#     tomogram_3d (returned)
#   
#   Returns:
#     tomogram_3d
#     
###############################################################################
  
  local mdoc_file=$1
  
  # MDOC might have dots other than extension
  tomo_base="$(basename ${mdoc_file%.mrc.mdoc})"
  
  tomo_dir="${recdir}/${tomo_base}"
  tomo_root="${vars[outdir]}/${tomo_dir}/${tomo_base}"
  
  if [[ "${vars[do_etomo]}" == true ]]; then
    tomogram_3d="${vars[outdir]}/${tomo_dir}/${tomo_base}_newstack_full_rec.mrc"
    etomo_out="${vars[outdir]}/${tomo_dir}/${tomo_base}_std.out"
  else
    tomogram_3d="${tomo_root}_aretomo.mrc"
  fi
  
# #   echo $tomogram_3d
}

function run_aretomo() {
###############################################################################
#   Function:
#     Runs AreTomo
#   
#   Positional variable:
#     1) (optional) GPU number 
#   
#   Global variables:
#     gpu_num
#     vars
#     reordered_stack
#     tomogram_3d
#     angles_list
#     
###############################################################################
  
  gpu_num=$1  # might be updated
  
  # Get single GPU number if there are more than one
  get_gpu
  
  echo "${vars[aretomo_exe]} \
    -InMrc $reordered_stack \
    -OutMrc $tomogram_3d \
    -AngFile $angles_list \
    -AlignZ ${vars[rec_zdim]} \
    -VolZ ${vars[vol_zdim]} \
    -OutBin ${vars[bin]} \
    -TiltAxis ${vars[tilt_axis]} \
    -Gpu ${gpu_num} \
    -TiltCor ${vars[tilt_cor]} \
    -FlipVol ${vars[flip_vol]} \
    -PixSize ${vars[apix]} \
    -Wbp ${vars[bp_method]} \
    -Patch ${vars[are_patches]} \
    -OutXF ${vars[transfile]} \
    -DarkTol ${vars[dark_tol]} \
    " | xargs
    # (xargs removes whitespace)
}

function get_central_slice() {
###############################################################################
#   Function:
#     Gets central slice
#     Requires ImageMagick's convert
#   
#   Positional variable:
#     1) tomogram name
#     
#   Global variables:
#     vars
#     tomo_dir
#     verbose
#     imgdir
#     thumbdir
#   
###############################################################################
  
  local fn=$1
# #   local tomo_dir="$(dirname $(dirname $fn))"
  local trim_log="${vars[outdir]}/${tomo_dir}/trimvol.log"
  
  dimension_string=$(${vars[imod_dir]}/header $fn | grep sections | xargs | rev | cut -d' ' -f1-3 | rev)
#   echo "dimension_string '$dimension_string'"
  IFS=' ' read -r -a dimension_array <<< ${dimension_string}
#   printf "'%s'\n" "${dimension_array[@]}"
  
  # initialize minimum
  min_dim=99999
  axis_array=("-nx" "-ny" "-nz")
  
  # Get minimimum (https://stackoverflow.com/a/40642705)
  for idx in "${!dimension_array[@]}" ; do
#     echo "$idx: ${dimension_array[$idx]}"
    if (( ${dimension_array[$idx]} < min_dim )) ; then
      min_dim=${dimension_array[$idx]}
      min_axis=${axis_array[$idx]}
    fi
  done
  
  # If short axis along y, then rotate (or else, there'll be N images of width 1)
  local rot_flag=""
  if [[ "${min_axis}" == "-ny" ]]; then
    rot_flag="-rx"
  elif [[ "${min_axis}" == "-nx" ]]; then
    echo -e "    WARNING! Untested with short dimension along x...\n"
    rot_flag="-rx"
  elif [[ "${min_axis}" == "-nz" ]]; then
    rot_flag=""
  else
    echo -e "    WARNING! unrecognized axis: ${min_axis}\n"
    rot_flag=""
  fi
  
  central_slice_num=$(echo "${min_dim}"/2 | bc)
  echo "  Extracting central slice:"
  echo "    Shortest dimension: ${min_dim}"
  echo "    Shortest axis:      ${min_axis}"
  echo "    Central slice:      ${central_slice_num}"
  echo ""
  
  # Strip extension
  tomo_stem="${fn%.mrc}"
  
  # Take central slice
  mrc_slice="${tomo_stem}_slice.mrc"
  trim_cmd="trimvol ${rot_flag} ${min_axis} 1 $fn ${mrc_slice}" 
  if [[ "$verbose" -ge 3 ]]; then
    echo -e "    $trim_cmd"
  fi
  if [[ "$verbose" -ge 8 ]]; then
    ${vars[imod_dir]}/$trim_cmd 2>&1 | tee ${trim_log}
  else
    ${vars[imod_dir]}/$trim_cmd 1> ${trim_log}
  fi
  
  jpg_slice="${tomo_stem}_slice.jpg"
  jpg_cmd="mrc2tif -j ${mrc_slice} ${jpg_slice}"
  if [[ "$verbose" -ge 3 ]]; then
    echo -e "    $jpg_cmd"
  fi
  
  # Suppress "Writing JPEG images"
  if [[ "$verbose" -le 6 ]]; then
#     ${vars[imod_dir]}/$jpg_cmd #&& rm ${mrc_slice} 2> /dev/null
    ${vars[imod_dir]}/$jpg_cmd 1> /dev/null
  else
    ${vars[imod_dir]}/$jpg_cmd #&& rm mrc_slice${}
  fi
  
  central_slice_jpg="${vars[outdir]}/${imgdir}/${thumbdir}/$(basename ${tomo_stem})_slice_norm.jpg"
  norm_cmd="convert ${jpg_slice} -normalize $central_slice_jpg "
  if [[ "$verbose" -ge 3 ]]; then
    echo "    $norm_cmd"
  fi
  $norm_cmd && rm ${jpg_slice}
}

function wrapper_etomo() {
###############################################################################
#   Function:
#     Wrapper for etomo
#     Default behavior is to BACK UP pre-existing reconstruction (can be overridden).
#   
#   Positonal arguments:
#     1) Prefix for output filenames, including directory
#     
#   Positional variables:
#     1) file stem (including relative path)
#     2) number of images in tilt series
#     3) additional batchruntomo parameters
#     4) (boolean) redo pre-existing reconstruction (default: true, old file backed up)
#     
#   Calls functions:
#     vprint
#   
#   Global variables:
#     vars
#     tomo_dir
#     tomogram_3d
#     verbose
# 
###############################################################################
  
  local tomo_base=$1
  local num_mics=$2
  local more_flags=$3
  
  if [[ "$4" == "" ]]; then
    local do_overwrite=true
  else
    local do_overwrite=false
  fi
  local do_reconstruct=true
  
  local etomo_out="${vars[outdir]}/${tomo_dir}/${tomo_base}_std.out"
  local run_cmd="batchruntomo -RootName ${tomo_base}_newstack -CurrentLocation ${vars[outdir]}/${tomo_dir} -DirectiveFile ${vars[batch_directive]} ${more_flags}"
  tomogram_3d="${vars[outdir]}/${tomo_dir}/${tomo_base}_newstack_full_rec.mrc"
  
  if [[ "${vars[testing]}" == false ]]; then
    # Check if output already exists
    if [[ -e $tomogram_3d ]]; then
      if [[ "${do_overwrite}" == false ]] && [[ "${vars[no_redo3d]}" != "false" ]] ; then
        do_reconstruct=false
        
        if [[ "$verbose" -ge 2 ]]; then
          vprint "\n  eTomo output $tomogram_3d already exists, skipping..."
        else
          mv $tomogram_3d ${tomogram_3d}.bak
        fi
      else
        if [[ "$verbose" -ge 2 ]]; then
          vprint "\n  WARNING: eTomo output $tomogram_3d already exists"
          echo "    $(mv -v $tomogram_3d ${tomogram_3d}.bak)"
        else
          mv $tomogram_3d ${tomogram_3d}.bak
        fi
      fi
    fi
    
    if [[ "${do_reconstruct}" == true ]] ; then
      vprint "\n  $(date)" "3+"
      vprint   "  Computing tomogram reconstruction 'batchruntomo' from $num_mics micrographs" "2+"
      vprint "\n  Running: ${run_cmd}" "3+"

      # Full screen output
      if [[ "$verbose" -ge 7 ]]; then
        ${vars[imod_dir]}/${run_cmd} | tee ${etomo_out}
      
      # Quiet mode
      elif [[ "$verbose" -le 1 ]]; then
        ${vars[imod_dir]}/${run_cmd} > ${etomo_out}
      
      else
        ${vars[imod_dir]}/${run_cmd} | tee ${etomo_out} | stdbuf -o0 grep "Residual error mean and sd" | sed 's/^/   /'
        # (greps on the fly, and prepends spaces to output)
        
        grep "Final align" "${vars[outdir]}/${tomo_dir}/batchruntomo.log" 2> /dev/null | sed 's/^/    /'
      fi
      # End verbosity cases
      
      vprint "" "2+"
      
      # If final alignment
      if [[ "${vars[do_ruotnocon]}" == false ]] || [[ "${more_flags}" == "-start 6" ]] ; then
        # Sanity check: tomogram exists
        if [[ ! -f "$tomogram_3d" ]]; then
          vprint "\n$(date)" "1+"
          vprint   "WARNING! eTomo output $tomogram_3d does not exist!\n" "1+"
          cat ${etomo_out}
          vprint "\n         Continuing...\n" "1+"
          
          return
        
        # Tomogram found
        else
          \rm ${etomo_out} 2> /dev/null
          get_central_slice ${tomogram_3d}
        
        fi
        # End sanity IF-THEN
      fi
      # End final-alignment IF-THEN
    fi
    # End do-reconstruct IF-THEN
  
  # If testing
  else
    if [[ "${do_overwrite}" == false ]] && [[ "${vars[no_redo3d]}" != "false" ]] ; then
      do_reconstruct=false
      
      if [[ "$verbose" -ge 2 ]]; then
        vprint "\n  eTomo output $tomogram_3d already exists, skipping..."
      fi
    else
      if [[ "$verbose" -ge 3 ]]; then
        vprint "\n  TESTING $run_cmd\n"
      elif [[ "$verbose" -eq 2 ]]; then
        vprint "  ${run_cmd}"
      fi
      
      touch $tomogram_3d
    fi
    # End overwrite IF-THEN
  fi
  # End testing IF-THEN
}

function ruotnocon_wrapper() {
###############################################################################
#   Function:
#     Simplify input for ruotnocon_run()
#   
#   Positional variables:
#     1) tomogram directory, relative to vars[outdir]
#     2) prefix for output filenames
#   
#   Calls functions:
#     ruotnocon_run
#   
#   Global variables:
#     vars
#     imgdir
#   
###############################################################################
  
  local tomo_dir=$1
  local tomo_base=$2
# #   local outlog=$3
  
  local fid_file="${vars[outdir]}/${tomo_dir}/${tomo_base}_newstack.fid"
  
  ruotnocon_run \
    "${fid_file}" \
    "${vars[outdir]}/${tomo_dir}/taCoordinates.log" \
    "${fid_file}" \
    "${vars[ruotnocon_sd]}" \
    "${vars[outdir]}/${imgdir}/${contour_imgdir}/${tomo_base}_residuals.png" \
    "${vars[outdir]}/${tomo_dir}/tmp_contours" \
    "${vars[testing]}" \
    "${vars[imod_dir]}"  #>> "${outlog}"
}

function ruotnocon_run() {
###############################################################################
#   Function:
#     Removes bad contours
#   
#   Requires IMOD programs:
#     convertmod
#     imodinfo
#     wmod2imod
#     imodjoin
#   
#   Positional variables:
#     1) FID input file
#     2) Alignment log file
#     3) Output FID file (can be same as input, will back up if it exists)
#     4) (optional) Residual cutoff, in units of sigma (default: 3)
#     5) (optional) Residual plot file (default: "plot_residuals.png")
#     6) (optional) Temporary directory
#     7) (optional) Testing (boolean)
#     8) (optional) IMOD executable directory
#   
#   Calls functions:
#     extract_residuals
#     split_wimp
#     remove_contours
#     backup_copy
#   
#   Global variables:
#     contour_resid_file : defined here
#     temp_contour_dir : defined here
#     num_chunks
#     verbose
#     contour_imod_dir
#     num_bad_residuals : defined here
#   
###############################################################################
  
  local fid_file=$1
  local contour_resid_file=$2
  local out_fid_file=$3
  local num_sd=$4
  local contour_plot=$5
  temp_contour_dir=$6
  local test_contour=$7
  contour_imod_dir=$8
  
  if [[ $# -lt 3 ]]; then
    echo -e "\nUSAGE: "
    echo -e "  $0 <input_fid> <ta_coords> <output_fid> <optional_num_sigma> <optional_plot> <optional_temp_directory> <optional_testing_flag> <optional_imod_directory>\n"
    exit
  fi
  
  if [ -z "$num_sd" ] ; then
    num_sd=3
  fi
  
  if [ -z $contour_plot ] ; then
    contour_plot="plot_residuals.png"
  fi
  
  if [ -z $temp_contour_dir ] ; then
    temp_contour_dir="tmp_contours"
  fi
  
  if [ -z $contour_imod_dir ] ; then
    # Check if in $PATH (adapted from https://stackoverflow.com/a/26759734/3361621)
    if [[ -x $(command -v convertmod) ]]; then
      contour_imod_dir="$(dirname $(command -v convertmod) )"
    fi
  fi
  
  declare -a chunk_array
  declare -a bad_residuals
  
  # Temporary files
  wimp_file="${temp_contour_dir}/1-convertmod.txt"
  contour_prefix="chunk"
  new_wimp="${temp_contour_dir}/2-wimp.txt"
  tmp_fid="${temp_contour_dir}/3-wmod2imod.fid"

  # Create temporary directory
  if [[ "${test_contour}" != true ]]; then
    \rm -r ${temp_contour_dir} 2> /dev/null
    if [[ ${verbose} -ge 5 ]] ; then
      echo "  Creating directory: ${temp_contour_dir}/"
    fi
    mkdir ${temp_contour_dir}
  fi
  
  # Convert FID model to WIMP-format text file
  local convertmod_cmd="convertmod ${fid_file} ${wimp_file}"
  if [[ ${verbose} -ge 4 ]] ; then
    echo "  Converting to WIMP format: ${fid_file}"
    echo "    $convertmod_cmd"
  fi
  
  if [[ "${test_contour}" != true ]]; then
    ${contour_imod_dir}/$convertmod_cmd
#     local status_code=$?  # will be 1 on error, 0 if OK
  
    # Split WIMP file into chunks
    split_wimp "${wimp_file}"
  fi
  
  # Get contours exceeding residual cutoff (space-delimited list)
  highest_residuals "${contour_plot}" "${num_sd}"
  
  if [[ "${test_contour}" != true ]]; then
    # Remove contours
    remove_contours
    
    # Get z-scale factor
    local zscale=$(${contour_imod_dir}/imodinfo -a ${fid_file} | grep scale | grep -v refcurscale | rev | cut -d" " -f1 | rev)
    
    # Convert to FID model
    local wmod2imod_cmd="${contour_imod_dir}/wmod2imod -z ${zscale} ${new_wimp} ${tmp_fid}"
    if [[ ${verbose} -ge 4 ]] ; then
      echo -e "\n  Converting to FID model..."
      echo -e "    $wmod2imod_cmd"
    fi
    $wmod2imod_cmd
    local status_code=$?  # will be 3 on error, 0 if OK
    
    if [[ ${status_code} -ne 0 ]] ; then
      echo -e "  ERROR!! Exiting with status code: '${status_code}'\n"
      exit
    fi
    
    # Back up pre-existing output
    backup_copy ${out_fid_file}
    
    # Copy header from input to output (more literally: replace object 1 from second model into first model)
    local imodjoin_cmd="${contour_imod_dir}/imodjoin -r 1 ${fid_file} ${tmp_fid} ${out_fid_file}"
    if [[ ${verbose} -ge 4 ]] ; then
      echo -e "  Copying header from input to output..."
      echo -e "    $imodjoin_cmd"
    fi
    $imodjoin_cmd > /dev/null
    local status_code=$?
    
    # Sanity check before cleaning up
    if [[ -f "${out_fid_file}" ]]; then
      if [[ ${verbose} -ge 5 ]] ; then
        echo "  Cleaning up..."
      fi
      rm -r ${temp_contour_dir} 2> /dev/null
    else
      echo -e "  ERROR!! File '${out_fid_file}' does not exist! Exiting with status code: '${status_code}'\n"
      exit
    fi
    
    num_bad_residuals=${#bad_residuals[@]}
    if [[ ${verbose} -ge 1 ]] ; then
      echo "  Removed ${num_bad_residuals}/${num_chunks} contours from '${fid_file}' and wrote to '${out_fid_file}'"
    fi
  fi
  # End testing IF-THEN
}

function split_wimp() {
###############################################################################
#   Function:
#     FUNCTION
#   
#   Positional variables:
#     1. WIMP-format text file
#   
#   Global variables:
#     temp_contour_dir
#     num_chunks
#     verbose
#     chunk_array
#   
###############################################################################

  local wimp_file=$1
  
  # Split into chunks (Adapted from https://stackoverflow.com/a/1825810)
  awk '/  Object #:/{n++}{print > "'${temp_contour_dir}/${contour_prefix}'" sprintf("%03d", n) ".txt"}' ${wimp_file}
  
  num_chunks=$(( $(ls ${temp_contour_dir}/${contour_prefix}* | wc -w) - 1))
  
  if [[ ${verbose} -ge 4 ]] ; then
    echo "  Split WIMP file into ${num_chunks} chunks (not including header)"
  fi
  
  chunk_array=($(seq -f "%03g" ${num_chunks}))
}

function highest_residuals() {
###############################################################################
#   Function:
#     Get contours exceeding residual cutoff
#   
#   Requires:
#     sort_residuals.py
#     
#   Positional variables:
#     1) sorted-residual plot file
#     2) residual cutoff, units of sigma
#   
#   Calls functions:
#   
#   Global variables:
#     test_contour
#     contour_resid_file
#     bad_residuals
#     verbose
#   
###############################################################################
  
  local contour_plot=$1
  local num_sd=$2
  
  # Sanity check
  if ! [ -z $SNARTOMO_DIR ] ; then
    local sort_exe="python ${SNARTOMO_DIR}/sort_residuals.py"
  else
    if [[ -f "./sort_residuals.py" ]]; then
      local sort_exe="python ./sort_residuals.py"
    else
      if [[ "${test_contour}" != true ]]; then
        echo -e "\nERROR!! Can't find 'sort_residuals.py'!"
        echo      "  Either copy to current directory or define 'SNARTOMO_DIR'"
        echo -e   "  Exiting...\n"
        exit
      else
        echo -e "\nWARNING! Can't find 'sort_residuals.py'"
        local sort_exe="python sort_residuals.py"
        exit
      fi
      # End testing IF-THEN
    fi
    # End local IF-THEN
  fi
  # End SNARTOMO IF-THEN
  
  local sort_cmd="${sort_exe} ${contour_resid_file} --sd ${num_sd} --plot ${contour_plot}"
  
  if [[ ${verbose} -ge 4 ]] ; then
    echo "  Finding contours with residuals exceeding ${num_sd}*SD..."
    echo "    ${sort_cmd}"
  fi
  
  # Read space-delimited list into array
  if [[ "${test_contour}" != true ]]; then
    IFS=' ' read -r -a bad_residuals <<< $($sort_cmd)
  fi
}

function remove_contours() {
###############################################################################
#   Function:
#     Remove multiple contours
#   
#   Positional variables:
#     1. Contour number to remove
#   
#   Global variables:
#     bad_residuals
#     chunk_array
#     verbose
#     new_wimp
#   
###############################################################################
  
#   printf "'%s'\n" "${bad_residuals[@]}"
#   echo "bad_residuals: '${#bad_residuals[@]}'"
  
  # Remove bad residuals from array
  for curr_resid in "${bad_residuals[@]}" ; do
    local contour2rm=$(( $curr_resid - 1))

    if [[ ${verbose} -ge 3 ]] ; then
      echo "    Removed contour #${curr_resid}"
    fi
  
  
    # Remove index from array
    unset 'chunk_array[$contour2rm]'
    if [[ ${verbose} -ge 7 ]] ; then
      echo "  chunk_array: '${#chunk_array[@]}' '${chunk_array[@]}'"
    fi
  done
  
  # Initialize new array
  cp "${temp_contour_dir}/${contour_prefix}000.txt" ${new_wimp}
  
  # Formatting
  local counter=0
  local num_digits=11
  local fmt_spc="          "
  
  # Loop through remaining array
  for contour_idx in "${chunk_array[@]}"; do
    local chunk_file="${temp_contour_dir}/${contour_prefix}${contour_idx}.txt"
    
    # Object numbers in contour file have to be consecutive
    local old_line=$(grep "Object #:" ${chunk_file})
    
    let "counter++"
    
    # String may have fixed width (https://unix.stackexchange.com/a/354493)
    local new_line="  Object #: ${fmt_spc:0:$(($num_digits - ${#counter}))}${counter:0:$num_digits}"
    
#     sed -i "s/.*$old_line.*/${new_line}/" "${chunk_file}"
    # Double quotes are required here for some reason.
    # (Wild card ".*" replaces whole line)
    
    cat ${chunk_file} >> ${new_wimp}
  done
    
  # Make sure not the last contour (which may have extra lines in the chunk file)
  if [[ ${contour2rm} -eq ${#chunk_array[@]} ]] ; then
    echo ""      >>  ${new_wimp}
    echo "  END" >>  ${new_wimp}
  fi
}

function backup_file() {
###############################################################################
#   Function:
#     Appends existing file with version number if it exists
#     
#   Positional variable:
#     1) Filename (required)
#     
#   Global variable:
#     verbose : default=1
#     
###############################################################################
 
  local fn=$1
  
  if [[ "$1" == "" ]]; then
    echo "ERROR!! Filename required!"
    return
  fi
  
  if [[ "$2" != "" ]]; then
    local verbose=$2
  else
    if [[ "$verbose" == "" ]]; then
      local verbose=1
    fi
  fi
  
  # Check if file exists
  if [[ -f "$fn" ]]; then
    if [[ "$verbose" -ge 8 ]]; then
      echo "File exists: '$fn'"
    fi
    
    # Initialize version counter
    counter=0
    
    until [[ ! -f "${fn}_${counter}" ]] ; do
      let "counter++"
    done
  
    if [[ "$verbose" -ge 1 ]]; then
      mv -v "${fn}" "${fn}_${counter}"
    else
      mv "${fn}" "${fn}_${counter}"
    fi
  fi
}

function backup_copy() {
###############################################################################
#   Function:
#     Appends existing file with version number if it exists
#     Adapted from gpu_resources.bash
#     
#   Positional variable:
#     1) Filename (required)
#     
#   Global variable:
#     verbose
#     
###############################################################################
 
  local fn=$1
  
  if [[ "$1" == "" ]]; then
    echo "ERROR!! Filename required!"
    return
  fi
  
  if [[ "$verbose" == "" ]]; then
    local verbose=1
  fi
  
  # Check if file exists
  if [[ -f "$fn" ]]; then
    if [[ "$verbose" -ge 7 ]]; then
      echo "  File exists: '$fn'"
    fi
    
    # Initialize version counter
    local counter=0
    
    until [[ ! -f "${fn}_${counter}" ]] ; do
      let "counter++"
    done
  
    # Guest doesn't have permission to preserve modification times
    if [[ "$verbose" -ge 2 ]]; then
      \mv -fv "${fn}" "${fn}_${counter}"
    else
      \mv -f "${fn}" "${fn}_${counter}"
    fi
    \cp -f "${fn}_${counter}" "${fn}"
  fi
}

function DUMMY_FUNCTION() {
###############################################################################
#   Function:
#     FUNCTION
#   
#   Positional variables:
#   
#   Calls functions:
#   
#   Global variables:
#   
###############################################################################
  
  return
}
