#!/bin/bash

# THIS SCRIPT CONTAINS FUNCTIONS COMMON TO BOTH SNARTomoClassic and SNARTomoPACE

function check_vars() {
###############################################################################
#   Function:
#     Checks specific environmental variables which should be defined in snartomo.bashrc
#     Adapted from https://stackoverflow.com/a/6394846
#   
###############################################################################
  
  var_array=("SNARTOMO_VOLTAGE" "SNARTOMO_INTERVAL" "SNARTOMO_TILT_TOLERANCE")
  var_array+=("SNARTOMO_MINFRAMES" "SNARTOMO_MAXFRAMES" "SNARTOMO_RAM_WARN")
  var_array+=("SNARTOMO_RAM_KILL" "SNARTOMO_EER_WAIT" "SNARTOMO_MC2_PATCH")
  var_array+=("SNARTOMO_WAIT_TIME" "SNARTOMO_IMOD_SLOTS" "SNARTOMO_RUOTNOCON_SD")
  var_array+=("SNARTOMO_CTF_SLOTS" "SNARTOMO_CTF_CS" "SNARTOMO_AC")
  var_array+=("SNARTOMO_CTF_BOXSIZE" "SNARTOMO_CTF_RESLO" "SNARTOMO_CTF_RESHI")
  var_array+=("SNARTOMO_CTF_DFLO" "SNARTOMO_CTF_DFHI" "SNARTOMO_DF_STEP")
  var_array+=("SNARTOMO_CTF_DAST" "SNARTOMO_JANNI_BATCH" "SNARTOMO_JANNI_OVERLAP")
  var_array+=("SNARTOMO_TOPAZ_PATCH" "SNARTOMO_TOPAZ_TIME" "SNARTOMO_DOSEFIT_MIN")
  var_array+=("SNARTOMO_DOSEFIT_RESID" "SNARTOMO_BINNING" "SNARTOMO_VOL_ZDIM")
  var_array+=("SNARTOMO_REC_ZDIM" "SNARTOMO_TILT_AXIS" "SNARTOMO_DARKTOL")
  var_array+=("SNARTOMO_TILTCOR" "SNARTOMO_BP_METHOD" "SNARTOMO_FLIPVOL")
  var_array+=("SNARTOMO_TRANSFILE" "SNARTOMO_ARETOMO_PATCH" "SNARTOMO_ARETOMO_TIME")
  var_array+=("ISONET_ENV" "SNARTOMO_SNRFALLOFF" "SNARTOMO_SHARE")
  
  declare -a missing_array
  
  for curr_var in "${var_array[@]}" ; do
    eval curr_value=\$$curr_var
    
    if [[ "${curr_value}" == "" ]] ; then
      missing_array+=("$curr_var")
#     else
#       echo "34 curr_var '$curr_var=$curr_value'"
    fi
  done
  
  if [[ "${#missing_array[@]}" -ge 1 ]]; then
    echo -e "\nERROR!! The following ${#missing_array[@]} environmental variables are missing:"
    printf "  %s\n" "${missing_array[@]}"
    echo -e "You may need to update your 'snartomo.bashrc' file\n"
    exit
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
    vars[outdir]="${vars[outdir]}/0-Testing"
    
    # Weird output if MOTIONCOR2_EXE undefined
    if [ -z "$MOTIONCOR2_EXE" ] ; then
      vars[motioncor_exe]="MotionCor2"
      
      echo "WARNING! Environmental variable 'MOTIONCOR2_EXE' undefined"
      echo "  Are you sure that you sourced 'snartomo.bashrc'?"
      echo "  Continuing..."
      echo
    fi
#     
#     # Instead of running, simply print that you're doing it
#     ctf_exe="TESTING ctffind4"
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
      if [[ "${vars[slow]}" == false ]] ; then
        do_parallel=false
      fi
#     else
#       # Read GPU list as array
#       IFS=' ' read -r -a gpu_list <<< "${vars[gpus]}"
    fi
    # End parallel IF-THEN
  fi
  # End PACE IF-THEN
}

function check_args() {
###############################################################################
#   Function:
#     Checks for unfamiliar arguments
#   
#   Global variable:
#     ARGS
#     
#   Positional variable:
#     1) Number of expected positional arguments
#     2 (optional) minimum number of positional arguments
#     
###############################################################################
  
  local max_args=$1
  local min_args=$2
  
# #   echo "121 max_args '$max_args', ARGS (${#ARGS[@]}) '${ARGS[@]}'"
  
  if [[ "${#ARGS[@]}" -gt "${max_args}" ]] ; then
    echo
    echo "ERROR!!"
    echo "  Found unfamiliar arguments: ${ARGS[@]}"
    echo "  You may have forgotten quotes around wild cards or parameters with multiple values (such as GPUs)"
    echo "  To list options & defaults, type:"
    echo "    $(basename $0) --help"
    echo
    exit 1
  fi
  
  if [[ $min_args != "" ]] && [[ "${#ARGS[@]}" -lt "${min_args}" ]] ; then
    echo
    echo "ERROR!!"
    echo "  Need at least ${min_args} arguments"
    echo
    print_usage
#    echo "  To list options & defaults, type:"
#    echo "    $(basename $0) --help"
    echo
    exit 2
  fi  
}

function check_format() {
###############################################################################
#   Function:
#     Checks format for movies
#   
#   Global variable:
#     vars
#     movie_ext
#     
###############################################################################
  
  local dir_counter=0
  declare -a dir_array
  
  # Make sure only one format specified
  for key in eer_dir tif_dir mrc_dir ; do 
    if ! [[ -z "${vars[$key]}" ]] ; then
      let "dir_counter++"
      dir_array+=($key)
    fi
  done
  
  if [[ "${#dir_array[@]}" -eq 0 ]]; then
    echo
    echo "ERROR!! No movie directory provided!"
    echo "  Either '--eer_dir', '--mrc_dir', or '--tif_dir' must be provided"
    echo "  Exiting..."
    echo 
    exit
  elif [[ "${#dir_array[@]}" -ge 2 ]]; then
    echo
    echo   "ERROR!! ${#dir_array[@]} movie directories provided:"
    printf "  '--%s'\n" "${dir_array[@]}"
    echo
    echo   "  Only one can be provided"
    echo   "  Exiting..."
    echo 
    exit
  else
    movie_ext="${dir_array[0]%_dir}"  # strip extension
    vars[movie_dir]="${vars[${dir_array[0]}]}"
  fi
}

function create_directories() {
###############################################################################
#   Functions:
#     Creates directories
#     Writes command line to commands file
#     Writes settings to settings file
#   
#   Calls functions:
#     check_local_dir
#     print_arguments
#   
#   Global variables:
#     vars
#     rawdir
#     movie_ext
#     do_pace
#     verbose
#     log_dir
#     temp_dir
#     mc2_logs
#     ctfdir
#     imgdir
#     thumbdir
#     dose_imgdir
#     contour_imgdir
#     resid_imgdir
#     temp_local_dir (OUTPUT)
#     temp_share_dir (OUTPUT)
#     cmd_file
#     set_file
#
###############################################################################
  
  local movie_template="${vars[outdir]}/${rawdir}/*.${movie_ext}"
  
  # In Classic mode, move movies back to input directory 
  if [[ "${do_pace}" == false ]] && [[ "${vars[restore_movies]}" == true ]] ; then
    # Count movies
    local num_moved_movies=$(ls ${movie_template} 2> /dev/null | wc -w )
    
    if [[ "${num_moved_movies}" -eq 0 ]]; then
      if [[ "$verbose" -ge 1 ]]; then
        echo "WARNING! There are no already-moved movies in output directory '${vars[outdir]}/${rawdir}/'"
        echo "  Flag '--restore_movies' was not needed"
        echo "  Continuing..."
        echo
      fi
    else
      local move_cmd="mv ${movie_template} ${vars[movie_dir]}/"
      
      if [[ "$verbose" -ge 1 ]]; then
        echo -e "${move_cmd}\n"
      fi
      
      ${move_cmd}
      
      # Get status code
      local status_code=$?
      
      # Exit on error
      if [[ $status_code -ne 0 ]] ; then
        echo -e "\nERROR!! Couldn't move '${movie_template}' to '${vars[movie_dir]}'!"
        echo -e   "  Exiting...\n"
        exit 3
      fi
    fi
    # End zero-movie IF-THEN
  fi
  
  # Remove output directory if '--overwrite' option chosen (PACE only)
  if [[ "${vars[overwrite]}" == true ]]; then
    if [[ "${do_pace}" == false ]]; then
      local num_moved_movies=$(ls ${movie_template} 2> /dev/null | wc -w)
    
      # If non-empty, throw error
      if [[ "${num_moved_movies}" -ge 1 ]]; then
        echo
        echo "ERROR!! Output directory '${vars[outdir]}/${rawdir}' has pre-existing '${num_moved_movies}' movie files!"
        echo "  1) If restarting from scratch, enter:"
        echo "    mv ${movie_template} ${vars[movie_dir]}/"
        echo "    Then restart."
        echo "  2) If continuing a partial run, move incomplete tilt series' movies to input directory '${vars[movie_dir]}/'"
        echo "    Only newly detected movies will be included in new tilt series."
        echo "Exiting..."
        echo
        exit
      fi
    fi
    # End PACE IF-THEN
    
    if [[ -d "${vars[outdir]}" ]]; then
      if [[ "$verbose" -ge 1 ]]; then
        echo -e "Removing directory '${vars[outdir]}/'..."
      fi
      
      rm -rf "${vars[outdir]}" 2> /dev/null
      local rm_status=$?
      
      if [[ "${rm_status}" -ne 0 ]]; then
          echo "ERROR!! Can't delete '${vars[outdir]}'!"
          
        # Check owner
        dir_owner=$(stat -c '%U' "${vars[outdir]}")
        
        if [[ "${dir_owner}" != "$(whoami)" ]]; then
          echo "  Owner of '${vars[outdir]}' is '${dir_owner}'!"
          echo "  Use a different directory, or ask them to change the permissions!"
          echo "  Exiting..."
          echo
          exit
        fi
      fi
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
  mkdir -p "${vars[outdir]}/${recdir}" "${vars[outdir]}/${imgdir}/${dose_imgdir}" 2> /dev/null
  
  # If not testing
  if [[ "${vars[testing]}" == false ]]; then
    mkdir "${vars[outdir]}/${denoisedir}" "${vars[outdir]}/${imgdir}/${thumbdir}" "${vars[outdir]}/$ctfdir" 2> /dev/null
  fi
  
  if [[ "${vars[do_laudiseron]}" == true ]] && [[ "${vars[testing]}" == false ]] ; then
    mkdir "${vars[outdir]}/${imgdir}/${resid_imgdir}" 2> /dev/null
  fi
    
  if [[ "${vars[do_ruotnocon]}" == true ]] && [[ "${vars[testing]}" == false ]] ; then
    mkdir "${vars[outdir]}/${imgdir}/${contour_imgdir}" 2> /dev/null
  fi
    
  # PACE-specific options
  if [[ "${do_pace}" == true ]] ; then
    # The temp directory has some files which may befuddle later runs
    rm -r "${vars[outdir]}/${temp_dir}" 2> /dev/null
    
    mkdir "${vars[outdir]}/${log_dir}" "${vars[outdir]}/${temp_dir}" "${vars[outdir]}/${micdir}" 2> /dev/null
    
    if [[ "${vars[testing]}" == true ]]; then
      mkdir "${vars[outdir]}/$ctfdir" 2> /dev/null
    fi
  
    # Shared-memory directory
    if [[ -z "${vars[temp_share]}" ]] ; then
      vars[temp_share]="/dev/shm/SNARTomo-$USER"
    fi
    
    temp_share_dir="${vars[temp_share]}/$$"
    
    if [[ "$verbose" -ge 1 ]]; then
      mkdir -pv "${temp_share_dir}" 2> /dev/null
    else
      mkdir -p "${temp_share_dir}" 2> /dev/null
    fi
  
  # If non-PACE
  else
    if [[ "${vars[testing]}" == false ]]; then
      mkdir "${vars[outdir]}/$rawdir"  
    fi
  fi
  # End PACE IF-THEN
    
  # If SNARTOMO_LOCAL was empty, then try a default
  if [[ -z "${vars[temp_local]}" ]] ; then
    vars[temp_local]="/tmp/SNARTomo-$USER"
  fi
  
  # In case we need to copy EERs locally, remember the PID ($$)
  temp_local_dir="${vars[temp_local]}/$$"
  
  if [[ "${vars[eer_local]}" == "true" ]] ; then
    if [[ "$verbose" -ge 1 ]]; then
      mkdir -pv "${temp_local_dir}" 2> /dev/null
    else
      mkdir -p "${temp_local_dir}" 2> /dev/null
    fi
  fi
  
  # Write command line to output directory
  echo -e "$0 ${@}\n" >> "${vars[outdir]}/${cmd_file}"
  print_arguments > "${vars[outdir]}/${set_file}"
  
  if [[ "${verbose}" -ge 1 ]]; then
    echo -e "Wrote settings to ${vars[outdir]}/${vars[settings]}\n"
  fi
}

function clean_local_dir() {
###############################################################################
#   Function:
#     Clean local directory if necessary
#   
#   Positional arguments:
#     1) key (in dictionary vars, corresponding to command-line parameter --KEY)
#     2) optional log file
#     
#   Calls functions:
#     vprint
#   
#   Global variables:
#     vars
#     warn_log
#     do_pace
#     temp_share_dir
#     temp_local_dir
#   
###############################################################################
  
  local key=$1
  local outlog=$2
  
#   vprint "" "1+" "${outlog}"
#   
#   echo "412 key '${vars[${key}]}'"
  
  # This condition shouldn't happen, but better to be safe before delecting directories
  if [[ -z "${vars[${key}]}" ]] ; then
    vprint "WARNING! Parameter '--${key}' should be non-empty" "0+" "${outlog} =${warn_log}"
  else
    if [[ "${do_pace}" == true ]] && [[ "${key}" == "temp_local" ]] ; then
      mv ${temp_share_dir}/* ${vars[outdir]}/${temp_dir}
    fi
    
    # Delete old subdirectories unless they are recent
    mapfile -t dir_array < <(find ${vars[${key}]} -mindepth 1 -type d 2> /dev/null)
    
    for curr_dir in ${dir_array[@]} ; do 
      # Make sure directory is empty
      if [ "$(ls -A ${curr_dir})" ]; then 
        vprint "WARNING! ${curr_dir} not empty" "0+" "${outlog} =${warn_log}"
      
      else
        if [[ "$verbose" -ge 1 ]] && [[ vars[eer_local] == "true" ]] && [[ "${key}" == "temp_local" ]] ; then
          rmdir -v "${curr_dir}" 2> /dev/null
        else
          rmdir "${curr_dir}" 2> /dev/null
        fi
      fi
      # End non-empty IF-THEN
    done
  fi
  # End empty-directory IF-THEN
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
#     echo "do_print2file '${do_print2file}', log_file '${log_file}', string2print '${string2print}'"
#     
    if [[ "${do_print2file}" == true ]]; then
      # Check whether to print only to the log file
      local firstchar=${log_file:0:1}
      if [[ "${firstchar}" == "=" ]] ; then
        # Remove first character
        log_file=${log_file:1}
        
        do_echo2screen=false
      else
        do_echo2screen=true
      fi
      
      if [[ "${firstchar}" == "=" ]] && [[ "$log_file" == "" ]] ; then
        do_echo2screen=true
      fi
      
      if [[ "${do_echo2screen}" == true ]]; then
        # If no log file is specified simply write to the screen
        if [[ "${log_file}" == "" ]]; then
#           echo -e "'${#log_array[@]}' ${do_echo2screen} '${firstchar}' '${log_file}' '${string2print}'"  ### TESTING
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
            echo "calling function: ${FUNCNAME[1]}"
            echo "log file '${log_file}'"
            echo -e "string2print '${string2print}'\n"
            exit
          fi
        fi
        # End empty-logfile IF-THEN
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
#     read_mdoc (Classic only)
#     check_targets (PACE only)
#     check_file
#     check_dir
#     check_exe
#     check_python
#     
#   Global variables:
#     init_conda (OUTPUT)
#     vars
#     do_pace
#     do_cp_note (PACE only)
#     imod_descr
#     movie_ext
#     ctffind_descr
#     validated
#     
###############################################################################
  
  local outlog=$1
  validated=true

  vprint "\nValidating..." "1+" "${outlog}"
  
  # Note initial conda directory
  init_conda="$CONDA_DEFAULT_ENV"

  
  if [[ "${do_pace}" == true ]]; then
    check_targets "${outlog}"
    check_apix_pace "${outlog}"
    
    # If using live mode, then we need the last angle
    if [[ "${vars[live]}" == true ]] && [[ "${vars[last_tilt]}" == "$LAST_TILT" ]] ; then
      validated=false
      vprint "  ERROR!! In Live mode, need to define '--last_tilt'!" "0+" "${outlog}"
    fi
  else
    read_mdoc "${outlog}"
  
    # Local copying is noted in paralleized process, so need to write a file.
    if [[ "${vars[eer_local]}" == "true" ]] && [[ "${do_pace}" == true ]] ; then
      touch "${do_cp_note}"
    fi
  fi
  # End PACE IF-THEN

  imod_descr="IMOD executables directory"
  check_dir "${vars[movie_dir]}" "movie directory" "${outlog}"
  check_dir "${vars[imod_dir]}" "${imod_descr}" "${outlog}"
  check_exe "$(which nvcc)" "CUDA libraries" "${outlog}"
  check_exe "${vars[motioncor_exe]}" "MotionCor2 executable" "${outlog}"
  
  # Check old MotionCor syntax
  if [[ "${vars[split_sum]}" == 1 ]] ; then
    vprint "  WARNING! Syntax '--split_sum=1' is deprecated." "1+" "${outlog}"
    vprint "    Use 'do_splitsum' instead. Continuing..." "1+" "${outlog}"
  fi
  
  if [[ "${vars[gain_file]}" != "" ]]; then
    check_file "${vars[gain_file]}" "gain reference" "${outlog}"
  else
    # If you didn't supply a gain file, you probbaly forgot
    if [[ "${vars[no_gain]}" == false ]]; then
      vprint "  ERROR!! Gain file not supplied!" "1+" "${outlog}"
      vprint "    Add flag '--no_gain' and restart..." "1+" "${outlog}"
      validated=false
    fi
  fi
  
  if [[ "${movie_ext}" == "eer" ]] ; then
    check_file "${vars[frame_file]}" "frame file" "${outlog}"
  elif [[ "${movie_ext}" != "mrc" ]] && [[ "${movie_ext}" != "tif" ]]; then
    vprint "  ERROR!! Unrecognized movie format: '${movie_ext}'" "0+" "${outlog}"
    validated=false
  fi
  
  ctffind_descr="CTFFIND executables directory"
  check_dir "${vars[ctffind_dir]}" "${ctffind_descr}" "${outlog}"
  check_exe "$(which pdftoppm)" "PDF converter" "${outlog}"
  
  # Can't use JANNI and Topaz simultaenously
  if [[ "${vars[do_janni]}" == true ]] && [[ "${vars[do_topaz]}" == true ]]; then
    validated=false
    vprint "  ERROR!! Can't use JANNI and Topaz simultaneously!" "0+" "${outlog}"
  fi
  
  if [[ "${vars[do_janni]}" == true ]] || [[ "${vars[do_topaz]}" == true ]]; then
    if [[ "${vars[do_janni]}" == true ]]; then
      vprint "  Denoising using JANNI" "1+" "${outlog}"
      try_conda "JANNI executable" "${vars[janni_env]}" "${outlog}"
      check_file "${vars[janni_model]}" "JANNI model" "${outlog}"
    fi
    
    if [[ "${vars[do_topaz]}" == true ]]; then
      vprint "  Denoising using Topaz" "1+" "${outlog}"
      try_conda "Topaz executable" "${vars[topaz_env]}" "${outlog}"
    fi
    
    if [[ "${vars[denoise_gpu]}" == false ]]; then
      vprint "    Denoising using CPU..." "1+" "${outlog}"
    else
      vprint "    Denoising using GPU..." "1+" "${outlog}"
    fi
  fi
  # End denoising IF-THEN
  
  if [[ ! -z "${vars[batch_directive]}" ]]; then
    vprint "  Computing reconstruction using IMOD" "1+" "${outlog}"
    check_file "${vars[batch_directive]}" "IMOD batch directive" "${outlog}"
  else
    vprint "  Computing reconstruction using AreTomo" "1+" "${outlog}"
    check_exe "${vars[aretomo_exe]}" "AreTomo executable" "${outlog}"
  fi
  
  if [[ "${vars[do_ruotnocon]}" == true ]] || [[ "${vars[do_laudiseron]}" == true ]] ; then
    if [[ -z "${vars[batch_directive]}" ]]; then
      validated=false
      vprint "  ERROR!! Can only remove contours if running eTomo!" "0+" "${outlog}"
    else
      vprint "  Removing contours with a residual greater than ${vars[ruotnocon_sd]} standard deviations" "2+" "${outlog}"
    fi
  fi
  
  if [[ "${vars[do_deconvolute]}" == true ]]; then
    vprint "  Deconvoluting using IsoNet" "1+" "${outlog}"
    try_conda "IsoNet executable" "${vars[isonet_env]}" "${outlog}"
  fi
  
  if [[ "${do_pace}" == false ]] || [[ "${vars[do_ruotnocon]}" == true ]] || [[ "${vars[do_laudiseron]}" == true ]] ; then
    check_python "${outlog}"
  fi
  
  check_exe "$(which convert)" "Imagemagick convert executable" "${outlog}"
  
  # Summary
  if [[ "$validated" == false ]]; then
    vprint "Missing required inputs, exiting...\n" "0+" "${outlog}"
    exit 4
  else
    vprint "Found required inputs. Continuing...\n" "1+" "${outlog}"
  fi
}

  function read_mdoc() {
  ###############################################################################
  #   Function:
  #     Gets information from MDOC file
  #     SNARTomoClassic only
  #   
  #   Calls functions:
  #     vprint
  #     check_apix_classic
  #     check_range
  #   
  #   Global variables:
  #     vars
  #     verbose (by vprint)
  #     validated
  #     
  ###############################################################################
    
    local outlog=$1

    if [[ "${vars[mdoc_dir]}" != "" ]] ; then
      # If mdoc_dir is specified, make sure that it's in mdoc_dir
      if [[ "${vars[mdoc_files]}" != "" ]] ; then
        if ! [ -e "${vars[mdoc_dir]}/${vars[mdoc_files]}" ] ; then
          vprint "\nERROR!! MDOC file '${vars[mdoc_files]}' expected to be in '${vars[mdoc_dir]}'!" "0+" "${outlog}"
          validated=false
        else
          vprint "  WARNING! Flags '--mdoc_dir' and '--mdoc_file' are redundant" "2+" "${outlog}"
        fi
      else
        # Get first MDOC
        local mdoc_files=(${vars[mdoc_dir]}/*.mdoc)
        vars[mdoc_files]="${mdoc_files[0]}"
      fi
      # End MDOC-exists IF-THEN
    fi
    # End MDOC-directory IF-THEN
    
    # Check if MDOC exists
    if [[ -f "${vars[mdoc_files]}" ]]; then
      vprint "  Found MDOC file: ${vars[mdoc_files]}" "1+" "${outlog}"
      check_apix_classic "${vars[mdoc_files]}" "${outlog}"
      check_range "defocus values" "${vars[df_lo]}" "${vars[df_hi]}" "${outlog}"
      vprint "" "7+" "${outlog}"
      check_range "frame numbers" "${vars[min_frames]}" "${vars[max_frames]}" "${outlog}"
    fi
    # End MDOC IF-THEN
    
    # Floating-point comparison from https://stackoverflow.com/a/31087503/3361621
    if (( $(echo "${vars[apix]} < 0.0" |bc -l) )); then
      vprint "\nERROR!! Pixel size ${vars[apix]} is negative!" "0+" "${outlog}"
      vprint   "  Either provide pixel size (--apix) or provide MDOC file (--mdoc_file)" "0+" "${outlog}"
      vprint   "  Exiting...\n" "0+" "${outlog}"
      exit 5
    else
      vprint "  Pixel size: ${vars[apix]}" "1+" "${outlog}"
    fi
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
      local limit_lo=$2
      local limit_hi=$3
      local outlog=$4
      
      if [[ "${data_descr}" == "defocus values" ]]; then
        # Get defocus value(s)
        readarray -t list_values < <(grep Defocus ${vars[mdoc_files]} | grep -v TargetDefocus | cut -d" " -f3)
      elif [[ "${data_descr}" == "frame numbers" ]]; then
        readarray -t list_values < <(grep NumSubFrames ${vars[mdoc_files]} | grep -v TargetDefocus | cut -d" " -f3)
      else
        vprint "\nERROR!! Data type unknown: ${data_descr} "  "0+" "${outlog}"
        vprint "  Exiting...\n" "0+" "${outlog}"
        exit
      fi
      
      vprint "    Checking ${data_descr}..." "2+" "${outlog}"
      
      if [[ ${#list_values[@]} -eq 0 ]] ; then
        vprint "\nERROR!! Couldn't find '${data_descr}' in '${vars[mdoc_files]}'!"  "0+" "${outlog}"
        vprint "  Exiting...\n" "0+" "${outlog}"
        exit
      fi
      
      # Initialize counters
      local mic_counter=0
      bad_counter=0
      
      for mic_value in "${list_values[@]}" ; do
        # Strip ^M (Adapted from https://stackoverflow.com/a/8327426/3361621)
        local mic_value=${mic_value/$'\r'/}
        
        if [[ "${data_descr}" == "defocus values" ]]; then
          # MDOC shows defocus in microns, with underfocus negative, as opposed to CTFFIND
          local df_angs=$(echo ${mic_value}* -10000 | bc)
          local fmt_value=`printf "%.1f\n" "$df_angs"`
        elif [[ "${data_descr}" == "frame numbers" ]]; then
          local fmt_value=$(echo ${mic_value} | bc)
        else
          vprint "\nERROR!! Data type unknown: ${data_descr}" "0+" "${outlog}"
          vprint "  Exiting...\n" "0+" "${outlog}"
          exit
        fi
        
        let "mic_counter++"
        
        if (( $(echo "${fmt_value} < ${limit_lo}" | bc -l) )) || (( $(echo "${fmt_value} > ${limit_hi}" | bc -l) )); then
            let "bad_counter++"
            vprint "      Micrograph #$mic_counter ${data_descr}: $fmt_value  (OUTSIDE OF RANGE)" "7+" "${outlog}"
        else
            vprint "      Micrograph #$mic_counter ${data_descr}: $fmt_value " "7+" "${outlog}"
        fi
      done
      # End micrograph loop
      
      if [[ "$bad_counter" == 0 ]]; then
        vprint "    Found $mic_counter micrographs with ${data_descr} within specified range [${limit_lo}, ${limit_hi}]" "5+" "${outlog}"
      else
        vprint "    WARNING! Found $bad_counter out of $mic_counter ${data_descr} in ${vars[mdoc_files]} outside of range [${limit_lo}, ${limit_hi}]" "2+" "${outlog}"
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
      
      # Get first match 
      local first_target=$(echo $(ls -tr ${vars[target_files]} | head -n 1 ) )
      
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
      
      # Sanity check
      if [[ "${mdoc_apix}" == "" ]] ; then
        vprint "\nERROR!! MDOC file '${mdoc_file}' doesn't contain pixel size!" "0+" "${outlog}"
        vprint   "  Exiting...\n" "0+" "${outlog}"
        exit 6
      fi
      
      # Strip ^M (Adapted from https://stackoverflow.com/a/8327426/3361621)
      mdoc_apix=${mdoc_apix/$'\r'/}
      
      # If no pixel size specified on the command line, then use MDOC's
      if (( $(echo "${vars[apix]} < 0.0" | bc -l) )); then
        vars[apix]="${mdoc_apix}"
        vprint "  Pixel size: ${vars[apix]}" "2+" "${outlog}"
      
      # If both the command line and MDOC files give pixel sizes, check that they're the same to 2 decimal places
      else
        cmdl_round=$(printf "%.2f" "${vars[apix]}")
        mdoc_round=$(printf "%.2f" "${mdoc_apix}")
        
        if (( $(echo "${mdoc_round} == ${cmdl_round}" |bc -l) )); then
          vprint "    WARNING! Pixel size specified on both command line (${vars[apix]}) and in MDOC file (${mdoc_apix}). Using former..." "2+" "${outlog}"
        else
          vprint "\nERROR!! Different pixel sizes specified on command line (${vars[apix]}) and in MDOC file (${mdoc_apix})!" "0+" "${outlog}"
          vprint   "  Exiting...\n" "0+" "${outlog}"
          exit 7
        fi
      fi
      # End command-line IF-THEN
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
  #     debug_cuda (NOT WORKING)
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
      
      if [[ "${exe_descr}" == "MotionCor2 executable" ]] ; then
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
            
            # Check if you own MotionCor's temporary file (NOW CHECKS BEFORE EVERY MICROGRAPH)
            if [[ "${tempfile_owner}" != "$(whoami)" ]]; then
              if [[ "${vars[testing]}" == true ]]; then
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
      if [[ "${exe_descr}" == "PDF converter" ]] ; then
        vprint "  WARNING! ${exe_descr} not found" "1+" "${outlog}"
        vprint "    CTFFIND 1D spectra will not be converted to images" "2+" "${outlog}"
        vprint "    Install pdftoppm to enable this function" "2+" "${outlog}"
        return
      fi
      
      if [[ "${vars[testing]}" == true ]]; then
        vprint    "  WARNING! ${exe_descr} not found. Continuing..." "1+" "${outlog}"
      else
        validated=false
        vprint "  ERROR!! ${exe_descr} not found!" "0+" "${outlog}"
      fi
    fi
    # End PATH check
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

  function check_integer() {
  ###############################################################################
  #   Function:
  #     Checks integer versus floating point
  #   
  #   Positional variables:
  #     1) variable to check
  #     2) correct variable type
  #     3) description (for printing)
  #     4) output log
  #   
  #   Calls functions:
  #     vprint
  #   
  #   Global variables:
  #     validated
  #   
  ###############################################################################
    
    local to_check=$1
    local should_be=$2
    local describe_var=$3
    local outlog=$4
    
    local to_int=$(printf "%.0f" "$to_check")
    
    if (( $(echo "${to_check} == ${to_int}" | bc -l) )) ; then
  # #     vprint "  Integer : '$to_check'" "1+" "${outlog}"
      local var_type="int"
    else
  # #     vprint "  Float   : '$to_check'" "1+" "${outlog}"
      local var_type="float"
    fi
    
    if [[ "$should_be" != "" ]] ; then
      if [[ "${var_type}" == "${should_be}" ]] ; then
        vprint "    ${describe_var}  : ${to_check} \tOK,    is ${var_type}, should be ${should_be}" "1+" "${outlog}"
      else
        vprint "    ${describe_var}  : ${to_check} \tUH OH! is ${var_type}, should be ${should_be}" "1+" "${outlog}"
        validated=false
      fi
    fi
    # End validation IF-THEN
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
    
# #     echo "1222 '$exe_descr' '$conda_env' '$outlog'" ; exit  ### TESTING
    
    if [[ "${vars[testing]}" == "false" ]]; then
      vprint "    Current conda environment: ${CONDA_DEFAULT_ENV}" '5+' "${outlog}"
      vprint "    Temporarily activating conda environment: ${conda_env}" "5+" "${outlog}"
      
      vprint '    Executing: eval "$(conda shell.bash hook)"' "5+" "${outlog}"
      eval "$(conda shell.bash hook)"
      # (Can't combine the eval command into a variable and run it, for some reason)
      
      local conda_cmd="conda activate ${conda_env}"
      vprint "    Executing: $conda_cmd" "5+" "${outlog}"
      $conda_cmd 2> /dev/null
      
      # Sanity check
      if [[ "${CONDA_DEFAULT_ENV}" == "${conda_env}"  ]]; then
        vprint "    New conda environment: ${CONDA_DEFAULT_ENV}" "5+" "${outlog}"
      else
        echo -e "\nERROR!! Conda environment '${conda_env}' not found!"
        echo    "Install '${conda_env}' or disable option,"
        echo -e "Exiting...\n"
        exit
      fi
      
      # TODO: For IsoNet, make sure isonet.py is in the PATH
      
      # Matplotlib won't work later on
      conda deactivate
    fi
    # End testing IF-THEN
  }

  function check_targets() {
  ###############################################################################
  #   Function:
  #     Only used in PACE mode
  #     Looks for target files
  #     If single MDOC file is provided, then a fake targets file is generated
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
  #     temp_dir
  #     
  ###############################################################################
    
    local outlog=$1
    
    # MDOC option
    if [[ "${vars[mdoc_files]}" != "" ]] ; then
      if [[ "${vars[target_files]}" != "" ]] ; then
        echo -e "  ERROR!! Flags '--target_files' and '--mdoc_files' cannot be used simultaneously!\n"
        exit 7
      else
        # Read MDOC list as array
        mapfile -t mdoc_array < <(ls ${vars[mdoc_files]} 2> /dev/null)
        
        local fake_targets="${vars[outdir]}/${temp_dir}/single_tgts.txt"
        rm ${fake_targets} 2> /dev/null
        vprint "  Creating target file: ${fake_targets} with ${#mdoc_array[@]} MDOCs" "1+" "${outlog}"
        
        for curr_mdoc in ${mdoc_array[@]} ; do
          # Strip extension and write to fake targets file
          echo "tsfile = $(basename ${curr_mdoc%.mdoc})" >> ${fake_targets}
          
          # Copy MDOC to tmp directory
          cp ${curr_mdoc} ${vars[outdir]}/${temp_dir}/
        done
        # End MDOC loop
        
        # Sanity check: Check that there are subframes
        local num_subframes=$(grep -c SubFramePath ${mdoc_array[0]})
        
        # Maybe in Live mode, there won't be any subframes yet
        if [[ "${vars[live]}" == false ]] ; then
          if [[ $num_subframes -eq 0 ]] ; then
            validated=false
            vprint "  ERROR!! MDOC file '${mdoc_array[0]}' has no subframes!" "0+" "${outlog}"
            vprint "          Maybe you provided the wrong kind of file?" "0+" "${outlog}"
          else
            vprint "    First MDOC file '${mdoc_array[0]}' OK: has valid subframe entries" "2+" "${outlog}"
          fi
        fi
        
# #         echo "1311 num_subframes '$num_subframes'" ; exit
        
        # Remember for later
        vars[target_files]="${fake_targets}"
      fi
    else
      target_array=$(ls ${vars[target_files]} 2> /dev/null)
# #       printf "'%s'\n" "${target_array[@]}"
      local num_targets=$(echo $target_array | wc -w)
    
      if [[ "${num_targets}" -eq 0 ]]; then
        validated=false
        echo -e "  ERROR!! At least one target file is required!\n"
        exit 8
      elif [[ "${num_targets}" -eq 1 ]]; then
        vprint "  Found target file: ${target_array[0]}" "1+" "${outlog}"
      else
        vprint "  Found ${num_targets} targets files" "1+" "${outlog}"
      fi
    fi
    # End MDOC IF-THEN
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
    
      # Print instructions on creating a frame file (only for EER format)
      if [[ "${file_type}" == "frame file" ]]; then
        howto_frame
      fi
      
      if [[ "${vars[testing]}" == true ]]; then
        echo    "    To validate testing, type:"
        echo -e "      touch ${search_file}"
      fi
      
    else
      vprint "  Found ${file_type}: ${search_file}" "1+" "${outlog}"
      
      if [[ "${file_type}" == "frame file" ]]; then
        check_mc2_frame "${outlog}"
      fi
    fi
    # End existence IF-THEN
  }

    function howto_frame() {
      echo
      echo "  The frame file is a text file containing the following three values, separated by spaces:"
      echo "    1) The number of frames to include"
      echo "    2) The number of EER frames to merge in each motion-corrected frame"
      echo "    3) The dose per EER frame"
      echo 
      echo "  For the second value, a reasonable rule of thumb is to accumulate 0.15-0.20 electrons per A2."
      echo "    For example, at a dose of 3e/A2 distributed over 600 frames, the dose per EER frame would be 0.005."
      echo "    To accumulate 0.15e/A2, you would need to merge 0.15/(3/600) = 30 frames."
      echo "    The line in the frame file would thus be:"
      echo "      600 30 0.005"
      echo 
      echo "  You can create a frame file with SNARTomo's FrameCalc: "
      echo "    https://rubenlab.github.io/snartomo-gui/#/framecalc"
      echo
      echo "  The first N frames can be handled differently than the next M frames, "
      echo "    and thus the frame file would contain multiple lines, on for each set of conditions."
      echo "    However, we haven't tested this functionality yet."
      echo
      echo "  For more information, see MotionCor2 manual."
      echo
    }

    function check_mc2_frame() {
    ###############################################################################
    #   Function:
    #     Validates MotionCor2 frame file
    #   
    #   Positional variables:
    #     1) output log
    #   
    #   Calls functions:
    #     vprint
    #     check_integer
    #   
    #   Global variables:
    #     vars
    #     validated
    #   
    ###############################################################################
      
      local outlog=$1
      
      # Read space-delimited string as array
      IFS=' ' read -r -a frame_array <<< "$(cat ${vars[frame_file]})"
      local mic_dose=$(printf "%.3f" $(echo "${frame_array[0]} * ${frame_array[2]}" | bc 2> /dev/null) )
      
      # If the dose is less than 10, show a warning and perform a sanity check on the frames file
      if (( $( echo "$mic_dose < 10" | bc -l) )) ; then
        vprint "  Dose per micrograph : $mic_dose e-/A2" "1+" "${outlog}"
      else
        vprint "  WARNING! Dose per micrograph : $mic_dose e-/A2" "1+" "${outlog}"
        
        # Sanity check on frames file
        check_integer "${frame_array[0]}" "int"   "Number of frames" "${outlog}"
        check_integer "${frame_array[1]}" "int"   "Frames to merge " "${outlog}"
        check_integer "${frame_array[2]}" "float" "Dose per frame  " "${outlog}"
        
        if [[ "$validated" == false ]]; then
          vprint "  ERROR!! Frame file '${vars[frame_file]}' has the wrong format!" "0+" "${outlog}"
        fi
      fi
      # End dose IF-THEN
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

function get_version_number() {
###############################################################################
#   Function:
#     Gets version number to two decimal places of MotionCor2 and AreTomo executables
#   
#   Positional argument:
#     1) filename (can be soft link)
#   
#   Returns:
#     version number (as an echo statement)
#     
###############################################################################
  
  local exe2check=$1
  
  local version_number=$(basename $(realpath $exe2check) | cut -d_ -f2)
  echo $version_number  | cut -d. -f1-2
}

function check_gain_format() {
###############################################################################
#   Function:
#     Checks format of gain file
#   
#   Positional argument:
#     1) output log file
#   
#   Calls functions:
#     vprint
#     file_stem
#     
#   Global variables:
#     vars
#     main_log
#     outdir
#     
###############################################################################
  
  local outlog=$1
  
  # Don't need to do anything if "--no_gain" flag used
  if [[ "${vars[no_gain]}" == false ]]; then
    # Check if MRC or TIFF
    local ext=$(echo "${vars[gain_file]}" | rev | cut -d. -f1 | rev)
    
    vprint "Gain file format: $ext" "1+" "${main_log}"
    
    if [[ ! "$ext" == "mrc" ]]; then
#       # Late versions of MotionCor2 v1.5+ allows GAIN format natively (FALSE)
#       if (( $( $(get_version_number ${vars[motioncor_exe]}) >= 1.5" | bc -l) )) ; then
#         vprint "  TIFF-format gain file allowed with MotionCor2 v${version_number}" "1+" "${main_log}"
#       else
        # Remove extension (last period-delimited string)
        local stem_gain="$(file_stem ${vars[gain_file]})"
        local mrc_gain="${vars[outdir]}/${stem_gain}.mrc"
        
        # Build command
        local convert_cmd="${vars[imod_dir]}/tif2mrc ${vars[gain_file]} ${mrc_gain}"
        
        # Assume it's a TIFF, and try to convert it
# #         vprint "  MRC-format gain file required with MotionCor2 v${version_number}" "1+" "${main_log}"
        vprint "  Attempting conversion..." "1+" "${main_log}"
        vprint "    Running: $convert_cmd\n" "1+" "${main_log}"
      
        if [[ "${vars[testing]}" == false ]]; then
          if [[ "$verbose" -ge 1 ]]; then
            $convert_cmd | sed 's/^/    /'
          else
            $convert_cmd > /dev/null
          fi
          
          # Check exit status
          local status_code=$?
          # (0=successful, 1=fail)
          
          if [[ ! "$status_code" == 0 ]]; then
            echo -e "ERROR!! tif2mrc failed with exit status $status_code\n"
            exit 9
          fi
          
          # Update gain file
          vars[gain_file]="${mrc_gain}"
        fi
        # End testing IF-THEN
#       fi
#       # End new-version IF-THEN
    fi
    # End MRC IF-THEN
  fi
  # End no-gain IF-THEN
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
  
  if ! [[ -f "${vars[batch_directive]}" ]] ; then
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
    
    vprint "Updated pixel size $pxsz_nm nm (${vars[apix]} A) in ADOC file '$new_adoc'\n" "1+"
    
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
  
    vprint "Added pixel size $pxsz_nm nm (${vars[apix]} A) in ADOC file '$new_adoc'\n" "1+"
  fi
  # End pixel-found IF-THEN
}

function check_frames() {
###############################################################################
#   Function:
#     Checks number of frames (EERs only)
#     Checks if we need to copy the EER files locally
#   
#   Positional variable:
#     1) output log file
#     
#   Requires:
#     IMOD's header program
#   
#   Global variables:
#     vars
#     first_local
#     fn
#     warn_log
#     temp_local_dir
#     do_cp_note (PACE only)
#     min_frames
#     max_frames
#     
###############################################################################
  
  local outlog=$1
  
  # Get number of frames
  if [[ "${vars[testing]}" == false ]]; then
    # Optionally copy EERs locally 
    if [[ "${vars[eer_local]}" == true ]] ; then
      copy_local "${outlog}"
    fi
    # End local-copy IF-THEN
      
    # Record both the line with the numbers of sections and the time
    local hdr_out=$( TIMEFORMAT="%R" ; { time ${vars[imod_dir]}/header $fn | grep sections ; } 2>&1 )
    
    if [[ "${hdr_out}" == *"Fail"* ]] ; then
      vprint "    ERROR!!! Unable to read micrograph $fn, may be corrupted!" "0+" "${outlog} =${warn_log}"
      vprint "      $(echo $hdr_out | grep Fail)" "0+" "${outlog} =${warn_log}"
      vprint "      Enter CTRL-c to exit..." "0+" "${outlog}"
      exit
    
    else
      local num_sections=$(echo "$hdr_out" | head -n 1 | rev | cut -d" " -f1 | rev)
      local hdr_time=$(echo "$hdr_out" | tail -n 1)
      
      vprint "    Micrograph $fn  \tnumber of frames: $num_sections (read in ${hdr_time} sec)\n" "1+" "=${outlog}"
      
      # Check read time
      if (( $( echo "${hdr_time} > ${vars[eer_latency]}" | bc -l ) )) && [[ "${vars[eer_local]}" != "true" ]] ; then
        if [[ "${do_pace}" == false ]]; then
          vprint "    WARNING! Micrograph '$fn' header took ${hdr_time} seconds to load. Will copy locally...\n" "0+" "${outlog} =${warn_log}"
          mkdir -pv "${temp_local_dir}"
          
          # Start copying locally
          vars[eer_local]="true"
          copy_local "${outlog}"
        else
          # Parallel process may have created temp file already
          if ! [[ -f "${do_cp_note}" ]]; then
            vprint "    WARNING! Micrograph '$fn' header took ${hdr_time} seconds to load. Will copy locally...\n" "0+" "${outlog} =${warn_log}"
            mkdir -pv "${temp_local_dir}" 2>&1 | tee -a "${outlog}"
            touch "${do_cp_note}"
          fi
          
# #             echo "1707 temp_local '${vars[temp_local]}/$$', temp_local_dir '$temp_local_dir', whoami '$(whoami)'"
          vars[eer_local]="true"
          copy_local "${outlog}"
        fi
        # End PACE IF-THEN
#         
#       # TESTING
#       else
#         vprint "   1728 fn $fn, hdr_time ${hdr_time}, eer_latency ${vars[eer_latency]}, eer_local '${vars[eer_local]}'\n" "0+" "${outlog}"
      fi
      # End read-time IF-THEN
      
      # Check if within range
      if [[ "$num_sections" -lt "${vars[min_frames]}" ]] || [[ "$num_sections" -gt "${vars[max_frames]}" ]] ; then
        vprint "    WARNING! Micrograph $fn: number of frames ($num_sections) outside of range (${vars[min_frames]} to ${vars[max_frames]})" "0+" "${outlog} =${warn_log}"
      fi
    fi
    # End success IF-THEN
    
  fi
  # End testing IF-THEN
}

  function copy_local() {
  ###############################################################################
  #   Function:
  #     Copies file to local temp directory
  #   
  #   Positional variables:
  #     1) log file
  #   
  #   Calls functions:
  #     vprint
  #   
  #   Global variables:
  #     fn
  #     temp_local_dir
  #     vars
  #     temp_dir
  #     warn_log
  #   
  ###############################################################################
    
    local outlog=$1
    
    local cp_time=$( TIMEFORMAT="%R" ; { time cp "$fn" "${temp_local_dir}/" ; } 2>&1 )
    
    # Sanity check
    if [[ -e "${temp_local_dir}/$(basename $fn)" ]]; then
# #       vprint "    Copied '$fn'  \tto: ${temp_local_dir} (in ${cp_time} sec)" "0+" "${outlog}"
      
      # Update EER name
      fn="${temp_local_dir}/$(basename $fn)"
      vprint "    Copied to '$fn' (in ${cp_time} sec)" "0+" "=${outlog}"
    else
      vprint "WARNING! Couldn't copy '$fn' to ${temp_local_dir}. Continuing..." "0+" "${outlog} =${warn_log}"
      vprint "  temp_local_dir '$temp_local_dir'\n" "0+" "${outlog}"
    fi
  }

function check_freegpus() {
###############################################################################
#   Function:
#     Check if someone else owns /tmp/MotionCor2_FreeGpus.txt
#   
#   Positional variables:
#     1) log file
#   
#   Calls functions:
#     vprint
#   
#   Global variables:
#     vars
#   
###############################################################################
  
  local outlog=$1
  
  # Check owner of /tmp/MotionCor2_FreeGpus.txt
  local mc2_tempfile="/tmp/MotionCor2_FreeGpus.txt"
  
  # Check if file exists
  if [[ -e "${mc2_tempfile}" ]]; then
    # Try to remove it
    \rm -r ${mc2_tempfile} 2> /dev/null
    
    # Check if it still exists
    if [[ -e "${mc2_tempfile}" ]]; then
      # Get owner
      local tempfile_owner=$(stat -c '%U' "${mc2_tempfile}")
      
      # Check if you own
      if [[ "${tempfile_owner}" != "$(whoami)" ]]; then
        # Wait for file to disappear
        local start_time=$SECONDS
        while [[ $( echo "$(( $SECONDS - $start_time )) < ${vars[mc2_wait]}" | bc -l ) ]] ; do
        
          sleep "${vars[search_interval]}"
          local tempfile_owner=$(stat -c '%U' "${mc2_tempfile}" 2> /dev/null)
          
          # If file disappears, then exit loop
          if ! [[ -e "${mc2_tempfile}" ]] ; then
            local curr_wait=$(( $SECONDS - $start_time ))
            vprint "  Waited ${curr_wait} seconds for '${mc2_tempfile}' to be released by ${last_owner}" "1+" "${outlog}"
            
            break
          
          # If file is now owned by me, then exit loop
          elif [[ "${tempfile_owner}" == "$(whoami)" ]] ; then
            local curr_wait=$(( $SECONDS - $start_time ))
            vprint "  After ${curr_wait} seconds, '${mc2_tempfile}' now owned by ${tempfile_owner}" "1+" "${outlog}"
            
            break
          
          # Else keep waiting until time limit reached
          else
            local last_owner=$tempfile_owner
          fi
        done
        # End WHILE loop
        
        # Print warning if time limit reached
        if (( $( echo "$(( $SECONDS - $start_time )) > ${vars[mc2_wait]}" | bc -l ) )) && [[ "${tempfile_owner}" != "$(whoami)" ]] ; then
            vprint "  WARNING! ${mc2_tempfile} owned by '${last_owner}' and not you" "1+" "${outlog}"
            vprint "    Continuing...\n" "1+" "${outlog}"
        fi
      fi
      # End not-owner IF-THEN
    fi
    # End still-exists IF-THEN
  fi
  # End file-exists IF-THEN
}

function wait_for_file() {
###############################################################################
#   Function:
#     Check if someone else owns /tmp/MotionCor2_FreeGpus.txt or /tmp/tmp.txt
#   
#   Positional variables:
#     1) file to wait for
#     2) log file
#   
#   Calls functions:
#     vprint
#   
#   Global variables:
#     vars
#   
###############################################################################
  
  local wait_file=$1  # WAS "/tmp/MotionCor2_FreeGpus.txt"
  local outlog=$2
  
  # Check if file exists
  if [[ -e "${wait_file}" ]]; then
    # Try to remove it
    \rm -r ${wait_file} 2> /dev/null
    
    # Check if it still exists
    if [[ -e "${wait_file}" ]]; then
      # Get owner
      local tempfile_owner=$(stat -c '%U' "${wait_file}")
      
      # Check if you own
      if [[ "${tempfile_owner}" != "$(whoami)" ]]; then
        # Wait for file to disappear
        local start_time=$SECONDS
        while [[ $( echo "$(( $SECONDS - $start_time )) < ${vars[temp_wait]}" | bc -l ) ]] ; do
        
          sleep "${vars[search_interval]}"
          local tempfile_owner=$(stat -c '%U' "${wait_file}" 2> /dev/null)
          
          # If file disappears, then exit loop
          if ! [[ -e "${wait_file}" ]] ; then
            local curr_wait=$(( $SECONDS - $start_time ))
            vprint "    Waited ${curr_wait} seconds for '${wait_file}' to be released by ${last_owner}" "1+" "=${outlog}"
            
            break
          
          # If file is now owned by me, then exit loop
          elif [[ "${tempfile_owner}" == "$(whoami)" ]] ; then
            local curr_wait=$(( $SECONDS - $start_time ))
            vprint "    After ${curr_wait} seconds, '${wait_file}' now owned by ${tempfile_owner}" "1+" "=${outlog}"
            
            break
          
          # Else keep waiting until time limit reached
          else
            local last_owner=$tempfile_owner
          fi
        done
        # End WHILE loop
        
        # Print warning if time limit reached
        if (( $( echo "$(( $SECONDS - $start_time )) > ${vars[temp_wait]}" | bc -l ) )) && [[ "${tempfile_owner}" != "$(whoami)" ]] ; then
            vprint "  WARNING! ${wait_file} owned by '${last_owner}' and not you" "1+" "=${outlog}"
            vprint "    Continuing...\n" "1+" "=${outlog}"
        fi
      fi
      # End not-owner IF-THEN
    fi
    # End still-exists IF-THEN
  fi
  # End file-exists IF-THEN
}

function run_motioncor() {
###############################################################################
#   Function:
#     Returns MotionCor command line (as an echo statement)
#   
#   Positional variable:
#     1) movie file
#     2) GPU number
#     
#   Calls functions:
#     vprint
#   
#   Global variables:
#     vars
#     movie_ext
#     cor_mic
#     mc2_logs
#     stem_movie
#     
###############################################################################
  
  local fn=$1
  local gpu_local=$2
  
  # Get single GPU number if there are more than one
  get_gpu

  # Initialize command
  local mc_command=""
  
  if [[ "${vars[testing]}" == true ]]; then
    local mc_exe="$(basename ${vars[motioncor_exe]})"
  else
    local mc_exe=${vars[motioncor_exe]}
  fi
  
  mc_command="    ${mc_exe} "
  
  if [[ "${movie_ext}" == "eer" ]] ; then
    mc_command+="-InEer $fn \
    -FmIntFile ${vars[frame_file]} "
  elif [[ "${movie_ext}" == "mrc" ]] ; then
    mc_command+="-InMrc $fn "
  elif [[ "${movie_ext}" == "tif" ]]; then
    mc_command+="-InTiff $fn "
  else
    echo '  ERROR!! Unrecognized movie format: ${movie_ext}'
    exit
  fi
  
  mc_command+="-Gain ${vars[gain_file]} \
  -OutMrc $cor_mic  \
  -Patch ${vars[mcor_patches]} \
  -FmRef ${vars[reffrm]} \
  -Iter 10  \
  -Tol 0.5 \
  -Serial 0 \
  -SumRange 0 0 \
  -Gpu ${gpu_local} \
  -LogFile ${vars[outdir]}/$micdir/${mc2_logs}/${stem_movie}_mic.log"
  
  if [[ "${vars[split_sum]}" == 1 || "${vars[do_splitsum]}" == true ]]; then
    mc_command+="-SplitSum 1 "
  fi

  if [[ "${vars[do_dosewt]}" == true ]]; then
    mc_command+="-Kv ${vars[kv]} \
    -PixSize ${vars[apix]} "
  fi

  if [[ "${vars[do_outstack]}" == true ]]; then
    mc_command+="-Outstack 1 "
  fi

  # Remove whitespace
  echo ${mc_command} | xargs
}

function remove_local() {
###############################################################################
#   Function:
#     Removes locally-copied EER
#   
#   Positional variables:
#     1) filename
#     2) verbosity (boolean)
#   
#   Global variables:
#     vars
#     temp_dir
#   
###############################################################################
  
  local fn=$1
  local do_verbose=$2
  
  # Make sure it's in the temp directory and not the original
  if [[ "${vars[eer_local]}" == "true" ]] ; then
    if [[ "${do_verbose}" == "true" ]] ; then
    \rm -v "${temp_local_dir}/$(basename $fn)"
    else
    \rm "${temp_local_dir}/$(basename $fn)" 2> /dev/null
    fi
  fi
}

function mic_to_ctf() {
###############################################################################
#   Function:
#     Generates CTFFIND MRC filename from motion-corrected micrograph
#   
#   Parameter:
#     1) Input filename
#     
#   Global variables:
#     vars
#     ctfdir
#     
#   Returns:
#     Output filename
#     
###############################################################################

  local current_input=$1
  
  local file_stem="$(basename ${current_input%_mic.mrc})"
  echo "${vars[outdir]}/${ctfdir}/${file_stem}_ctf.mrc"
}

function ctffind_common() {
###############################################################################
#   Function:
#     Wrapper for CTFFIND4: parallel & serial
#   
#   Positional variables:
#     1) Stem of output files
#     
#   Calls functions:
#     stem2ctfout
#     run_ctffind4
#     vprint
#   
#   Global variables:
#     vars
#     ctfdir
#     ctf_summary
#     warn_msg (OUTPUT)
#     do_pace
#     cor_mic
#     mic_counter (Classic only)
#     ctf_out
#     ctf_log (PACE only)
#     verbose
#     remaining_files (Classic only)
#     movie_ext (Classic only)
#     
###############################################################################

  local stem_movie=$1
  
  local ctf_txt=$(stem2ctfout "$stem_movie")
  local curr_summary="${vars[outdir]}/${ctfdir}/${ctf_summary}"
  local avg_rot="${vars[outdir]}/${ctfdir}/${stem_movie}_ctf_avrot.txt"
  local rot_pdf="${vars[outdir]}/${ctfdir}/${stem_movie}_ctf_avrot.pdf"
  local png_stem="${vars[outdir]}/${ctfdir}/${stem_movie}_ctf_avrot"  # extension added automatically by pdftoppm
  warn_msg=''
  
  if [[ "${do_pace}" == false ]]; then
    vprint "    Running CTFFIND4 on $cor_mic, micrograph #${mic_counter}, ${remaining_files} remaining" "5+"
  fi
    
  if [[ "${vars[testing]}" == false ]]; then
    # Print command
    if [[ "${do_pace}" == true ]] ; then
      echo ""
      run_ctffind4 "false"
    fi

    if [[ "$verbose" -ge 7 ]] || [[ "${do_pace}" == true ]] ; then
      run_ctffind4 "true" 2>&1 | tee $ctf_out
    else
      run_ctffind4 "true" > $ctf_out 2> /dev/null
    fi

    # Append to log file (PACE only)
    if [[ "${do_pace}" == true ]] ; then
      cat $ctf_out >> ${ctf_log}
    fi
    
    # Print notable CTF information to screen
    if [[ "$verbose" -eq 6 ]]; then
      echo ""
      grep "values\|good" $ctf_out | sed 's/^/    /'  # (prepends spaces to output)
      echo ""
    fi
    
    # Plot 1D profiles
    if [[ -f "$avg_rot" ]]; then
      if [[ "${do_pace}" == true ]] ; then
        vprint "    Running: ctffind_plot_results.sh $avg_rot" "5+"
      fi
      
      # If someone else owns /tmp/tmp.txt (hardwired by CTFFIND4), wait for it to be released
      wait_for_file "/tmp/tmp.txt"
      
      # Plot results
      ${vars[ctffind_dir]}/ctffind_plot_results.sh $avg_rot 1> /dev/null
      
      # (Temp file may cause problems if lying around)
      \rm /tmp/tmp.txt 2> /dev/null
    else
      warn_msg="WARNING! CTFFIND4 output $avg_rot does not exist"
    fi

    # Convert PDF to PNG
    if [[ -f "$rot_pdf" ]]; then
      # If pdftoppm in $PATH (https://stackoverflow.com/a/6569837), then convert to PNG
      if [[ $(type -P pdftoppm) ]] ; then
        local png_cmd="pdftoppm $rot_pdf $png_stem -png -r ${vars[ctf1d_dpi]}"
      
        if [[ "${do_pace}" == true ]] || [[ "$verbose" -ge 5 ]] ; then
          echo "    Running: ${png_cmd}"
        fi
        
        # Convert to PNG
        ${png_cmd} 1> /dev/null
        
#         else
#           echo "Not found!"
      fi
    else
      warn_msg="WARNING! CTFFIND4 output $rot_pdf does not exist"
    fi

    # Write last line of CTF text output to summary
    if [[ -f "$ctf_txt" ]]; then
      echo -e "${stem_movie}:    \t$(tail -n 1 $ctf_txt)" >> ${curr_summary}
    else
      warn_msg="WARNING! CTFFIND4 output $ctf_txt does not exist"
    fi
  
    if [[ "${do_pace}" == false ]] && [[ "$verbose" -ge 5 ]] ; then
      remaining_files=$(ls 2>/dev/null -Ubad -- ${vars[movie_dir]}/*.${movie_ext} | wc -w)
      echo -e "\n    Finished CTFFIND4 on $cor_mic, micrograph #${mic_counter}, ${remaining_files} remaining"
      echo -e   "    $(date)\n"
    fi

  # If testing
  else
    if [[ "${do_pace}" == true ]] || [[ "$verbose" -ge 5 ]] ; then
      echo ""
      run_ctffind4 "false"
    fi
  fi
  # End testing IF-THEN
}

  function stem2ctfout() {
  ###############################################################################
  #   Function:
  #     Template for CTFFIND text output
  #   
  #   Positional variables:
  #     1) micrograph stem
  #   
  #   Global variables:
  #     vars
  #     ctfdir
  #   
  ###############################################################################
    
    local stem_movie=$1
    echo "${vars[outdir]}/${ctfdir}/${stem_movie}_ctf.txt"
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
#     
###############################################################################

  local do_run=$1

  # Simply print command
  if [[ "${do_run}" == false ]]; then
    local ctf_cmd=$(echo "    ${ctf_exe} \
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
      no" | xargs)
  
    if [[ "${vars[testing]}" == true ]]; then
      echo "    TESTING: ${ctf_cmd}"
      echo "    TESTING: ctffind_plot_results.sh $avg_rot"
    else
      echo "    RUNNING: ${ctf_cmd}"
    fi
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

function dose_fit() {
###############################################################################
#   Function:
#     Wrapper for dose_discriminator.py
#   
#   Positional variables:
#     1) stem for current tomo files
#     2) original MDOC file
#     3) output MDOC file
#     4) tomogram log file
#   
#   Calls functions:
#     vprint
#     dose_discriminator.py
#   
#   Global variables:
#     dose_list (OUTPUT)
#     tomo_root
#     good_angles_file (OUTPUT)
#     mdoc_angle_array
#     new_subframe_array
#     dose_rate_array
#     main_log
#     warn_log
#     vars
#     micdir
#     stem_movie
#     cor_ext
#     verbose
#   
###############################################################################
  
  local tomo_base=$1
  local old_mdoc=$2
  local tomo_log=$3
  
  dose_list="${tomo_root}_dose.txt"
  local dose_plot="${vars[outdir]}/${imgdir}/${dose_imgdir}/${tomo_base}_dose_fit.png"
  good_angles_file="${tomo_root}_goodangles.txt"
  local dose_log="${tomo_root}_dosefit.log"
  
  # Clean up pre-existing files
  rm ${dose_list} 2> /dev/null

  # Loop through angles
  for mdoc_idx in "${!mdoc_angle_array[@]}"; do 
    # Get movie filename
    local movie_file=$(echo ${new_subframe_array[${mdoc_idx}]##*[/\\]} )
# #     echo "2248 movie_file '${movie_file}'"
    
    # Get motion-corrected micrograph name
    local stem_movie=$(echo ${movie_file} | rev | cut -d. -f2- | rev)
    local mc2_mic="${vars[outdir]}/${micdir}/${stem_movie}${cor_ext}"
    
    # Check that motion-corrected micrograph exists
    if [[ -f "$mc2_mic" ]]; then
      printf "%2d  %5.1f  %6.3f\n" "$mdoc_idx" "${mdoc_angle_array[${mdoc_idx}]}" "${dose_rate_array[${mdoc_idx}]}" >> ${dose_list}
    fi
  done
  # End angles loop
  
  # Fit dose to cosine function
  if [[ ! -f "${dose_list}" ]]; then
    vprint "\nWARNING! Dose list '${dose_list}' not found" "0+" "${main_log} =${warn_log}"
    vprint "  Continuing...\n" "0+" "${main_log} =${warn_log}"
  else
    local dosefit_cmd="$(echo dose_discriminator.py \
      ${dose_list} \
      --min_dose ${vars[dosefit_min]} \
      --max_residual ${vars[dosefit_resid]} \
      --dose_plot ${dose_plot} \
      --good_angles ${good_angles_file} \
      --screen_verbose ${verbose} \
      --log_file ${dose_log} \
      --log_verbose ${vars[dosefit_verbose]} | xargs)"
    
    vprint "\n  $dosefit_cmd\n" "1+" "=${tomo_log}"
    local error_code=$(${SNARTOMO_DIR}/$dosefit_cmd 2>&1)
    
# #     echo "2419 error_code '$error_code'"
    
    if [[ "$error_code" == *"Error"* ]] ; then
      echo -e "\nERROR!!"
      echo -e "${error_code}\n"
      echo -e "Conda environments: initial '$init_conda', current '$CONDA_DEFAULT_ENV'"
      echo -e "  Maybe this is the wrong environment?\n"
      exit
    elif [[ "$error_code" == *"WARNING"* ]] ; then
      vprint "$error_code" "1+" "${tomo_log}"
    else
      vprint "$error_code" "1+" "=${tomo_log}"
    fi
    # End error IF-THEN
  fi
  # End dose-list IF-THEN
}

function write_angles_lists() {
###############################################################################
#   Function:
#     Write angles to file
#     
#   Positional variables:
#     1) MDOC file (may be empty)
#     2) output log file
#   
#   Global variables:
#     good_angles_file
#     stripped_angle_array
#     mcorr_mic_array
#     denoise_array
#     ctf_stk_array
#     vars
#     tomo_root
#     mcorr_list (OUTPUT)
#     denoise_list (OUTPUT)
#     angles_list (OUTPUT)
#     ctf_list (OUTPUT)
#     tomo_mic_dir
#     ts_mics (OUTPUT)
#     
###############################################################################
  
  local outlog=$1

  # TODO: Test in Classic mode w/o MDOC
#   if [[ $found_mdoc == "" ]] ; then
#     sort_array_keys
#   fi
  
  mapfile -t sorted_keys < $good_angles_file

#   echo "2412  $(ls -l --full-time ${good_angles_file})"
#   echo "2414 sorted_keys ${#sorted_keys[*]}:"
#   printf "  '%s'\n" "${sorted_keys[@]}"
#   echo "2415 stripped_angle_array ${#stripped_angle_array[*]}:"
#   printf "  '%s'\n" "${stripped_angle_array[@]}"
#   exit
  
  mcorr_list="${tomo_root}_mcorr.txt"
  angles_list="${tomo_root}_newstack.rawtlt"
  denoise_list="${tomo_root}_denoise.txt"
  ctf_list="${tomo_root}_ctfs.txt"
  
  # Write new IMOD list file (overwrites), starting with number of images
  echo ${#sorted_keys[*]} > $mcorr_list
  echo ${#sorted_keys[*]} > $ctf_list
  if [[ "${vars[do_topaz]}" == true ]] || [[ "${vars[do_janni]}" == true ]] ; then
    echo ${#sorted_keys[*]} > $denoise_list
    local do_denoise=true  # IF-OR statement is a mouthful
  fi
  
  # Delete pre-existing angles file (AreTomo will crash if appended to)
  if [[ -f "$angles_list" ]]; then
    \rm $angles_list
  fi
  
  # Loop through sorted keys 
  for idx in "${sorted_keys[@]}" ; do
    echo    "${stripped_angle_array[${idx}]}" >> $angles_list
    echo -e "${mcorr_mic_array[$idx]}\n/" >> $mcorr_list
    echo -e "${ctf_stk_array[$idx]}\n/" >> $ctf_list
    
    # If denoising
    if [[ "${do_denoise}" == true ]]; then
      echo -e "${denoise_array[$idx]}\n/" >> $denoise_list
      
      # Temporarily move to temporary directory
      if [[ "${vars[testing]}" == false ]] ; then
        mv ${mcorr_mic_array[$idx]} ${tomo_mic_dir}/
      fi
    fi
  done  
  
  ts_mics="${#sorted_keys[*]}"
  vprint "  Wrote list of ${ts_mics} angles to $angles_list" "2+" "=${outlog}"
  vprint "  Wrote list of ${ts_mics} images to $mcorr_list" "2+" "=${outlog}"
  
  if [[ "${do_denoise}" == true ]]; then
    vprint "  Wrote list of ${ts_mics} images to $denoise_list" "2+" "=${outlog}"
  fi
  
  vprint "" "2+" "=${outlog}"
}

  function sort_array_keys() {
  ###############################################################################
  #   Function:
  #     Sort array accourding to angle
  #   
  #   Global variables:
  #     good_angles_file
  #     stripped_angle_array
  #     
  ###############################################################################
    
    \rm $good_angles_file
    
    # Sort by angle (Adapted from https://stackoverflow.com/a/54560296)
    for KEY in ${!stripped_angle_array[@]}; do
      echo "${stripped_angle_array[$KEY]}:::$KEY"
    done | sort -n | awk -F::: '{print $2}' >> $good_angles_file
    
# #     echo -e "\n2407 $good_angles_file (${#stripped_angle_array[@]}):" ; nl $good_angles_file #; exit ### TESTING
  }

function plot_tomo_ctfs() {
###############################################################################
#   Function:
#     Writes CTF data for a tilt series
#     Plots CTF data for tilt series
#   
#   Positional variable:
#     1) MDOC file (may be empty in Classic mode)
#     
#   Global variables:
#     vars
#     tomo_dir
#     ctf_summary
#     found_mdoc
#     new_subframe_array
#     mcorr_mic_array
#     imgdir
#     ts_list
#     ctf_plot
#     verbose
#     
###############################################################################
  
  local found_mdoc=$1
  
  local tomo_ctfs="${vars[outdir]}/${tomo_dir}/${ctf_summary}"
  
  if [[ "${vars[testing]}" == false ]] ; then
    if [[ $found_mdoc != "" ]] ; then
      # Loop through angles
      for mdoc_idx in "${!new_subframe_array[@]}"; do 
        # Get movie filename
        local movie_file=$(echo ${new_subframe_array[${mdoc_idx}]##*[/\\]} )
        
        # Get motion-corrected micrograph name
        local stem_movie=$(echo ${movie_file} | rev | cut -d. -f2- | rev)
        local ctf_txt=$(stem2ctfout "$stem_movie")
        
        # Check that file exists
        if [[ -f "$ctf_txt" ]]; then
          # Write CTF summary
          echo -e "${stem_movie}:    \t$(tail -n 1 $ctf_txt)" >> ${tomo_ctfs}
        fi
      done
      # End angles loop
    
    # If MDOC not used...
    else
        
      # Loop through micrographs
      for fn in ${mcorr_mic_array[@]} ; do
        local stem_mic=$(basename $fn | rev | cut -d. -f2- | rev)
        local stem_movie=${stem_mic%_mic}
        local ctf_txt=$(stem2ctfout "$stem_movie")
        
        # Check that file exists
        if [[ -f "$ctf_txt" ]]; then
          # Write CTF summary
          echo -e "${stem_movie}:    \t$(tail -n 1 $ctf_txt)" >> ${tomo_ctfs}
        fi
      done
      # End micrograph-loop
    fi
    # End MDOC IF-THEN
    
    # "<" suppreses filename (TODO: Sanity check for length 0)
    local len_before=$(wc -l < $tomo_ctfs)  
    
    # Look for duplicates (Might be able to do this without intermediate file)
    awk '!seen[$0]++' $tomo_ctfs > ${tomo_ctfs}.tmp 
    local len_after=$(wc -l < ${tomo_ctfs}.tmp)
    mv ${tomo_ctfs}.tmp ${tomo_ctfs}
    
    if [[ ${len_before} -ne ${len_after} ]] && [[ "$verbose" -ge 2 ]] ; then
      echo -e "\n  Removed $(( ${len_before} - ${len_after} )) duplicates from ${tomo_ctfs}"
    fi
    
    # Plot CTF summary
    local ctfbyts_cmd=$(echo ctfbyts.py \
      ${tomo_ctfs} \
      ${vars[outdir]}/${imgdir}/${ts_list} \
      ${vars[outdir]}/${imgdir}/${ctf_plot} \
      --first=${vars[ctfplot_first]} \
      --verbosity=$verbose | xargs)
    
    if [[ "$verbose" -ge 2 ]]; then
      echo -e "\n  Running: $ctfbyts_cmd"
    fi
    
    $ctfbyts_cmd
  fi
  # End testing IF-THEN
}

function denoise_wrapper() {
###############################################################################
#   Function:
#     Runs JANNI or Topaz denoising
#
#   Positional variables:
#     1) JANNI or Topaz
#     2) input directory
#     3) output log
#     4) (optional) GPU number 
#   
#   Global variables:
#     gpu_local
#     vars
#     tomo_dns_dir
#     
###############################################################################
  
  local dns_type=$1
  local indir=$2
  local outlog=$3
  gpu_local=$4  # might be updated
  
# #   echo "1917 gpu_local '${gpu_local}'"
  
  # Get single GPU number if there are more than one
  get_gpu

# #   echo -e "1922 gpu_local '${gpu_local}'\n"
  
  # Optionally use CPU
  if [[ "${vars[denoise_gpu]}" == false ]]; then
    gpu_local=-1
  fi
  
  if [[ "${dns_type}" == "janni" ]] ; then
    local conda_cmd="conda activate ${vars[janni_env]}"
    local denoise_exe="janni_denoise.py"
    local denoise_args="--ignore-gooey denoise --overlap=${vars[janni_overlap]} --batch_size=${vars[janni_batch]} --gpu=${gpu_local} -- ${indir} ${tomo_dns_dir} ${vars[janni_model]}"
    local denoise_cmd="${denoise_exe} ${denoise_args}"
    local dns_name="JANNI"
    
    # For some reason JANNI appends the input directory to the output directory
    if [[ "${vars[testing]}" == false ]]; then
      tomo_dns_dir="${tomo_dns_dir}/$(basename ${indir})"
    fi
  elif [[ "${dns_type}" == "topaz" ]] ; then
    local conda_cmd="conda activate ${vars[topaz_env]}"
    local denoise_exe="topaz"
    local denoise_args="denoise ${indir}/*_mic.mrc --device ${gpu_local} --patch-size ${vars[topaz_patch]} --output ${tomo_dns_dir}"
    local denoise_cmd="timeout ${vars[topaz_time]} ${denoise_exe} ${denoise_args}"
    local dns_name="Topaz"
  else
    echo -e "\nERROR!! Denoising type unknown: ${dns_type} " 
    echo -e "  Exiting...\n"
    exit
  fi
      
  if [[ "${vars[testing]}" == false ]]; then
    vprint "\n  Executing: $conda_cmd" "2+" "=${outlog}"
    $conda_cmd
    vprint   "    conda environment: '$CONDA_DEFAULT_ENV'" "2+" "=${outlog}"
    vprint   "    Denoising using ${dns_name}..." "2+" "=${outlog}"
    vprint   "    Executing: ${denoise_cmd}" "2+" "=${outlog}"
    
    # Run denoising
    if [[ "$verbose" -le 2 ]]; then
      $denoise_cmd 2>&1 > /dev/null
      # Suppress all output
      
    elif [[ "$verbose" -eq 6 ]]; then
      vprint "      $(date)" "6=" "=${outlog}"
      
      # Time execution and redirect output (https://stackoverflow.com/a/2409214)
      { time ${denoise_cmd} 2> /dev/null ; } 2>&1 | grep real | sed 's/real\t/    Run time: /'
      local status_code=("${PIPESTATUS[0]}")
      # Do NOT use quotes around ${denoise_cmd} above...
    elif [[ "$verbose" -ge 7 ]]; then
      time $denoise_cmd
      local status_code=("${PIPESTATUS[0]}")
    else
      if [[ "${outlog}" != "" ]] ; then
        $denoise_cmd >>${outlog} 2>&1
        local status_code=("${PIPESTATUS[0]}")
      else
        # Suppress output (https://stackoverflow.com/a/46009371)
        $denoise_cmd >/dev/null 2>&1
        local status_code=("${PIPESTATUS[0]}")
      fi
    fi
    
    # TODO: Figure out why Topaz hangs sometimes
    vprint "    ${dns_name} complete, status code: ${status_code}" "3+" "=${outlog}"
    # Topaz status code 124: bad
    
    local num_orig="$(ls ${indir}/*_mic.mrc | wc -w)"
    local num_dns="$(ls ${tomo_dns_dir}/*_mic.mrc | wc -w)"
    if [[ "${num_orig}" -ne "${num_dns}" ]] ; then
      vprint "\n    WARNING!" "2+" "=${outlog}"
    fi
    
    vprint "    Denoised ${num_dns}/${num_orig} micrographs" "3+" "=${outlog}"
  
    # Clean up
    conda deactivate
    vprint "  conda environment: '$CONDA_DEFAULT_ENV'\n" "2+" "=${outlog}"
  
  # Testing
  else
    vprint "  TESTING: ${denoise_exe} ${denoise_args}\n" "3+" "=${outlog}"
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
#     gpu_local
#     vars
#   
###############################################################################
  
  if [[ "$gpu_local" == "" ]]; then
    # If GPU number specified, use it
    if [[ "${vars[gpus]}" != "" ]]; then
      gpu_local=$(echo "${vars[gpus]}" | awk '{print $1}')
    else
      # Use CPU, if allowed
      gpu_local="-1"
    fi
  fi
}

function clean_up_mdoc() {
###############################################################################
#   Function:
#     Removes entries from MDOC for non-existent movies
#   
#   Positional variables:
#     1) original MDOC file (can contain missing files)
#     2) output cleaned MDOC file (can be same as input MDOC)
#     3) temporary MDOC-fragment directory
#   
#   Calls functions:
#     vprint
#   
#   Global variables:
#     chunk_prefix
#     good_angles_file
#     vars
#     micdir
#     cor_ext
#   
###############################################################################
  
  local old_mdoc=$1
  local new_mdoc=$2
  local temp_mdoc_dir=$3
  
  if [[ "$3" == "" ]]; then
    echo -e "\nERROR!! Old MDOC, new MDOC, and temp directory required!\n"
    return
  fi
  
  split_mdoc "${old_mdoc}" "${temp_mdoc_dir}"
  
  # Parse MDOC (awk notation from Tat)
  mapfile -t old_subframe_array < <( grep "SubFramePath" "${old_mdoc}" | awk '{print $3}' | sed 's/\r//' )
  
  # Read angles from dose-fitting
  readarray -t good_angle_array < $good_angles_file
  
  # Sort (https://stackoverflow.com/a/11789688)
  IFS=$'\n' sorted_good_angles=($(sort -n <<<"${good_angle_array[*]}"))
  unset IFS
  
  # Find boundaries of MDOC file
  local movie_file=$(echo ${old_subframe_array[0]##*[/\\]} )
  local stem_movie=$(echo ${movie_file} | rev | cut -d. -f2- | rev)
  local first_movie_file="$(grep -l $stem_movie ${chunk_prefix}*)"  # assuming single hit
  local first_movie_chunk="$(basename $first_movie_file | sed 's/[^0-9]*//g')"
  local last_header_chunk=$(( $first_movie_chunk - 1 ))
  
  declare -a good_mdoc_array
  
  # Loop through movies
  for mdoc_idx in "${sorted_good_angles[@]}"; do 
    # Get movie filename
    local movie_file=$(echo ${old_subframe_array[${mdoc_idx}]##*[/\\]} )
    
    # Get motion-corrected micrograph name
    local stem_movie=$(echo ${movie_file} | rev | cut -d. -f2- | rev)
    local mc2_mic="${vars[outdir]}/${micdir}/${stem_movie}${cor_ext}"
    
    # Check that motion-corrected micrograph exists
    if [[ -f "$mc2_mic" ]]; then
      good_mdoc_array+=($mdoc_idx)
    fi
  done
  # End angles loop
  
  # Build new MDOC
  rm $new_mdoc 2> /dev/null
  touch $new_mdoc
  
  # MDOC header may contain variable number of CR-delimited blocks before first micrograph
  for filenum in $(seq 0 $last_header_chunk) ; do
    cat "${chunk_prefix}$(printf '%02d' $filenum).txt" >> $new_mdoc
    echo >> $new_mdoc
  done
  
  local good_counter=0
  
#   # Backup good-angles file
#   local good_angles_copy="${good_angles_file%.txt}_0-orig.txt"
#   mv ${good_angles_file} ${good_angles_copy}
  
  # Append micrograph-related chunks
  for mdoc_idx in "${!good_mdoc_array[@]}"; do 
    local old_idx="${good_mdoc_array[mdoc_idx]}"
    local curr_chunk="${chunk_prefix}$(printf '%02d' $(( $old_idx + $last_header_chunk + 1 )) ).txt"
    
    # Remove regex characters (https://stackoverflow.com/a/28563120)
    local zvalue_line="$(\grep '\[ZValue' ${curr_chunk} | sed -e 's/[]$.*[\^]/\\&/g' )"
    local zvalue_orig="$(echo $zvalue_line | sed 's/[^0-9]*//g')"
    
    # Replace ZValue
    local new_line=$(echo ${zvalue_line/$zvalue_orig/$good_counter})
    sed -i "s/${zvalue_line}/${new_line}/" $curr_chunk
    let "good_counter++"
    
    # Append
    cat $curr_chunk >> $new_mdoc
    echo >> $new_mdoc
  done
  
#   echo "2815 good_mdoc_array ${#good_mdoc_array[*]}:"
#   printf "  '%s'\n" "${good_mdoc_array[@]}"
#   echo "2823 ${good_angles_file} '$(cat ${good_angles_file} | wc -l )'"
#   echo "2821 $(ls -l --full-time ${good_angles_file})"
#   exit
  
  # Clean up 
  rm -r $temp_mdoc_dir 2> /dev/null
}


function split_mdoc() {
###############################################################################
#   Function:
#     Split MDOC into chunks
#   
#   Positional variables:
#     1) MDOC file
#     2) output directory
#     3) temporary MDOC file w/o CRLFs
#   
#   Calls functions:
#   
#   Global variables:
#     chunk_prefix (OUTPUT)
#   
###############################################################################
  
  local old_mdoc=$1
  local temp_mdoc_dir=$2
  
  # Clean up pre-existing files
  rm -r $temp_mdoc_dir 2> /dev/null
  mkdir $temp_mdoc_dir
  
  # Remove CRLF (https://www.cyberciti.biz/faq/sed-remove-m-and-line-feeds-under-unix-linux-bsd-appleosx/)
  local mdoc_nocrlf="$temp_mdoc_dir/$(basename $old_mdoc).txt"
  sed 's/\r//' $old_mdoc > ${mdoc_nocrlf}
  local status_code=$?
  
  if [[ $status_code -ne 0 ]] ; then
    echo -e "ERROR!! Status code: '$status_code'\n"
    exit 10
  fi
  
  # Split MDOC (Adapted from https://stackoverflow.com/a/60972105/3361621)
  chunk_prefix="${temp_mdoc_dir}/chunk"
  csplit --quiet --prefix=$chunk_prefix --suffix-format=%02d.txt --suppress-matched ${mdoc_nocrlf} /^$/ {*}
}

function imod_restack() {
###############################################################################
#   Function:
#     Runs IMOD's restack and alterheader
#     Write JPEGs of micrographs and power spectra
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
#     ctf_list
#     reordered_stack (OUTPUT)
#     ctf_stack (OUTPUT)
#     verbose
#     warn_log
#     tomo_dir
#     thumbdir
#     
###############################################################################
  
  local outlog=$1

  # Output files
  local newstack_log="${tomo_root}_newstack.log"
  
  # Choose list for restacking
  if [[ "${vars[do_janni]}" == true ]] || [[ "${vars[do_topaz]}" == true ]]; then
    local imod_list="${denoise_list}"
  else
    local imod_list="${mcorr_list}"
  fi
  
  # AreTomo and IMOD expect different extensions for stacks
  if [[ ! -z "${vars[batch_directive]}" ]] ; then
    reordered_stack="${tomo_root}_newstack.mrc"
  else
    reordered_stack="${tomo_root}_newstack.st"
  fi
  
  ctf_stack="${tomo_root}_ctfstack.mrcs"

  # Delete pre-existing files (IMOD will back them up otherwise)
  if [[ -f "$reordered_stack" ]]; then
    \rm $reordered_stack
  fi
  if [[ -f "$ctf_stack" ]]; then
    \rm $ctf_stack
  fi
  
  local restack_cmd="newstack -filei $imod_list -ou $reordered_stack"
  local apix_cmd="alterheader -PixelSize ${vars[apix]},${vars[apix]},${vars[apix]} $reordered_stack"
  local ctf_cmd="newstack -filei $ctf_list -ou $ctf_stack"
  
  if [[ "${vars[testing]}" == false ]]; then
    # Check if output already exists (TODO: not necessary, checked above)
    if [[ ! -e $reordered_stack ]]; then
      vprint "  Running: ${restack_cmd}\n" "3+" "=${outlog}"
      
      if [[ "$verbose" -ge 7 ]]; then
        ${vars[imod_dir]}/${restack_cmd} 2>&1 | tee -a $newstack_log
        local newstack_status=("${PIPESTATUS[0]}")
      elif [[ "$verbose" -eq 6 ]]; then
        # ${vars[imod_dir]}/${restack_cmd} | tee -a $newstack_log | grep --line-buffered "RO image"
        ${vars[imod_dir]}/${restack_cmd} | tee -a $newstack_log | stdbuf -o0 grep "RO image" | sed 's/^/   /'
        # line-buffered & stdbuf: https://stackoverflow.com/questions/7161821/how-to-grep-a-continuous-stream
        
        local newstack_status=("${PIPESTATUS[0]}")
      else
        ${vars[imod_dir]}/${restack_cmd} >> $newstack_log
        local newstack_status=("${PIPESTATUS[0]}")
      fi
    
      # Sanity check
      if [[ ! -f "$reordered_stack" ]]; then
        # Check log file for errors
        if grep --quiet ERROR $newstack_log ; then
          grep ERROR $newstack_log | sed 's/^/  /'
        fi
        
        if [[ "$verbose" -ge 1 ]]; then
          vprint "  WARNING! Newstack output '$reordered_stack' does not exist! Status code: ${newstack_status}" "0+" "${outlog} =${warn_log}"
          vprint "    Continuing...\n" "0+" "${outlog} =${warn_log}"
        fi
      else
        # Update pixel size
        vprint "  Running: ${apix_cmd}" "3+" "=${outlog}"
        
        if [[ "$verbose" -ge 7 ]]; then
          ${vars[imod_dir]}/${apix_cmd} 2>&1 | tee -a $newstack_log
        elif [[ "$verbose" -eq 6 ]]; then
          ${vars[imod_dir]}/${apix_cmd} | tee -a $newstack_log | stdbuf -o0 grep "Pixel spacing" | sed 's/^/   /'
          # line-buffered & stdbuf: https://stackoverflow.com/questions/7161821/how-to-grep-a-continuous-stream
        else
          ${vars[imod_dir]}/${apix_cmd} >> $newstack_log
        fi
      fi
      # End sanity-check IF-THEN
      
    # If pre-existing output (shouldn't exist, since we deleted any pre-existing stack above)
    else
      vprint "  IMOD restack output $reordered_stack already exists" "0+" "=${outlog}"
      vprint "    Skipping...\n" "0+" "=${outlog}"
    fi
    # End pre-existing IF-THEN
  
    # Stack CTF power spectra (TODO: sanity check)
    vprint "  Running: ${ctf_cmd}\n" "3+" "=${outlog}"
    
    if [[ "$verbose" -ge 7 ]]; then
      ${vars[imod_dir]}/${ctf_cmd} 2>&1 | tee -a $newstack_log
    elif [[ "$verbose" -eq 6 ]]; then
      ${vars[imod_dir]}/${ctf_cmd} | tee -a $newstack_log | stdbuf -o0 grep "RO image" | sed 's/^/   /'
    else
      ${vars[imod_dir]}/${ctf_cmd} >> $newstack_log
    fi
    
    # Write JPEGs of tilt series and power spectra
    draw_thumbnails "$outlog"
    
  # Testing
  else
    vprint "  TESTING: ${restack_cmd}" "3+" "=${outlog}"
    vprint "  TESTING: ${apix_cmd}" "3+" "=${outlog}"
    vprint "  TESTING: ${ctf_cmd}" "3+" "=${outlog}"
    draw_thumbnails "$outlog"
  fi
  # End testing IF-THEN
}

function draw_thumbnails() {
###############################################################################
#   Function:
#     Writes JPEG thumbnail images for GUI
#   
#   Positional variables:
#     1) output log file
#   
#   Calls functions:
#   
#   Global variables:
#     tomo_dir
#     thumbdir
#     vars
#     tomo_root
#     reordered_stack
#   
###############################################################################
  
  local outlog=$1

  # Downsample tilt series
  local tomo_thumb_dir="${vars[outdir]}/${tomo_dir}/${thumbdir}"
  local binned_stack="${tomo_root}_bin.mrcs"
  local bin_cmd="binvol -z 1 -x ${vars[thumb_bin]} -y ${vars[thumb_bin]} ${reordered_stack} ${binned_stack}"
  
  # Convert to JPEGs
  local micjpg_prefix="${tomo_thumb_dir}/$(basename ${tomo_root})_newstack"
  local mic2jpg_cmd="mrc2tif -j ${binned_stack} ${micjpg_prefix}"
  
  # Calculate edge of CTF fitting region
  local half_width=$(echo ${vars[box]}*${vars[apix]}/${vars[res_hi]}+1 | bc)
  local box_width=$(echo $half_width*2 | bc)
  
  # Crop power spectra
  local win_ctf="${tomo_root}_ctfstack_center.mrcs"
  local clip_cmd="clip resize -2d -ox ${box_width} -oy ${box_width} ${ctf_stack} ${win_ctf}"
  
  # Convert to JPEGs
  local ctf_prefix="${tomo_thumb_dir}/$(basename ${tomo_root})_ctfstack_center"
  local ctf2jpg_cmd="mrc2tif -j ${win_ctf} ${ctf_prefix}"
  
  if [[ "${vars[testing]}" == false ]]; then
    mkdir -p ${tomo_thumb_dir} 2> /dev/null
    
    vprint "  Running: ${bin_cmd}\n" "3+" "=${outlog}"
    if [[ $verbose -ge 3 ]] ; then
      ${vars[imod_dir]}/$bin_cmd >> ${outlog}
    else
      ${vars[imod_dir]}/$bin_cmd > /dev/null
    fi
    
    
    vprint "  Running: ${mic2jpg_cmd}\n" "3+" "=${outlog}"
    if [[ $verbose -ge 3 ]] ; then
      ${vars[imod_dir]}/${mic2jpg_cmd} >> ${outlog}
    else
      ${vars[imod_dir]}/${mic2jpg_cmd} > /dev/null
    fi
    \rm ${binned_stack} 2> /dev/null
    
    vprint "  Running: ${clip_cmd}\n" "3+" "=${outlog}"
    if [[ $verbose -ge 3 ]] ; then
      ${vars[imod_dir]}/${clip_cmd} >> ${outlog}
    else
      ${vars[imod_dir]}/${clip_cmd} > /dev/null
    fi
    
    vprint "  Running: ${ctf2jpg_cmd}\n" "3+" "=${outlog}"
    if [[ $verbose -ge 3 ]] ; then
      ${vars[imod_dir]}/${ctf2jpg_cmd} >> ${outlog}
    else
      ${vars[imod_dir]}/${ctf2jpg_cmd} > /dev/null
    fi
  
  else
    vprint "\n  TESTING: ${bin_cmd}" "3+" "=${outlog}"
    vprint   "  TESTING: ${mic2jpg_cmd}" "3+" "=${outlog}"
    vprint   "  TESTING: ${clip_cmd}" "3+" "=${outlog}"
    vprint   "  TESTING: ${ctf2jpg_cmd}" "3+" "=${outlog}"
  fi
  
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
#     
#   Calls functions:
#     run_aretomo
#     get_central_slice
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
  local gpu_local=$2
  
  local do_reconstruct=true
  
  # Output files
  tomogram_3d="${tomo_root}_aretomo.mrc"
  local aretomo_log="${tomo_root}_aretomo.log"
  local aretomo_cmd=$(run_aretomo ${gpu_local})
  
  # Run AreTomo
  if [[ "${vars[testing]}" != true ]]; then
    # Check if output already exists
    if [[ -e $tomogram_3d ]]; then
      if [[ "${vars[no_redo3d]}" == true ]] ; then
        do_reconstruct=false
        
        if [[ "$verbose" -ge 2 ]]; then
          echo -e "\n  AreTomo output $tomogram_3d already exists, skipping..."
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
        echo      "  Computing tomogram reconstruction '`basename $tomogram_3d`' from $num_mics micrographs on GPU #${gpu_local}"
        echo -e "\n  Running: ${aretomo_cmd}"
      elif [[ "$verbose" -eq 3 ]]; then
        echo      "  Computing tomogram reconstruction '`basename $tomogram_3d`' from $num_mics micrographs on GPU #${gpu_local}"
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
      
      # Sanity check
      if [[ ! -f "$tomogram_3d" ]]; then
        if [[ "$verbose" -ge 1 ]]; then
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
          vprint "\n$(date)" "1+"
          vprint   "Finished reconstructing '$tomogram_3d'\n" "1+"
      fi
      # End do-reconstruct IF-THEN
    fi
    # End do-reconstruction IF-THEN
  
  # Testing
  else
# #     if [[ "${do_overwrite}" == false ]] && [[ "${vars[no_redo3d]}" == true ]] ; then
    if [[ "${vars[no_redo3d]}" == true ]] ; then
      if [[ "$verbose" -ge 2 ]]; then
        echo -e "\n  AreTomo output $tomogram_3d already exists, skipping..."
      fi
    else
      if [[ "$verbose" -ge 3 ]]; then
        echo      "  TESTING: tomogram reconstruction '`basename $tomogram_3d`' from $num_mics micrographs"
      fi
      
      touch "$tomogram_3d"
    fi
    # End overwrite IF-THEN
  fi
  # End testing IF-THEN
  
  vprint "" "2+"
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
  #     gpu_local
  #     vars
  #     reordered_stack
  #     tomogram_3d
  #     angles_list
  #     
  ###############################################################################
    
    gpu_local=$1  # might be updated
    
    # Get single GPU number if there are more than one
    get_gpu
    
    echo "${vars[aretomo_exe]} \
      -InMrc $reordered_stack \
      -OutMrc $tomogram_3d \
      -AngFile $angles_list \
      -AlignZ ${vars[rec_zdim]} \
      -VolZ ${vars[vol_zdim]} \
      -OutBin ${vars[are_bin]} \
      -TiltAxis ${vars[tilt_axis]} \
      -Gpu ${gpu_local} \
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
  
# #   if [[ "${vars[batch_directive]}" != "" ]]; then
  if [[ ! -z "${vars[batch_directive]}" ]] ; then
    tomogram_3d="${vars[outdir]}/${tomo_dir}/${tomo_base}_newstack_full_rec.mrc"
    etomo_out="${vars[outdir]}/${tomo_dir}/${tomo_base}_std.out"
  else
    tomogram_3d="${tomo_root}_aretomo.mrc"
  fi
  
# #   echo $tomogram_3d
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
#     3) (boolean) flag to remove bad micrographs
#     4) additional batchruntomo parameters
#     
#   Calls functions:
#     vprint
#   
#   Global variables:
#     vars
#     tomo_dir
#     tomogram_3d (OUTPUT)
#     verbose
# 
###############################################################################
  
  local tomo_base=$1
  local num_mics=$2
  local do_laudiseron=$3
  local more_flags=$4
  
  local do_reconstruct=true
  local etomo_out="${vars[outdir]}/${tomo_dir}/${tomo_base}_std.out"
  local etomo_cmd="batchruntomo -RootName ${tomo_base}_newstack -CurrentLocation ${vars[outdir]}/${tomo_dir} -DirectiveFile ${vars[batch_directive]} ${more_flags}"
  tomogram_3d="${vars[outdir]}/${tomo_dir}/${tomo_base}_newstack_full_rec.mrc"
  
  if [[ "${vars[testing]}" == false ]]; then
    # Check if output already exists
    if [[ -e $tomogram_3d ]]; then
      if [[ "${vars[no_redo3d]}" == true ]] ; then
        do_reconstruct=false
        
        if [[ "$verbose" -ge 2 ]]; then
          echo -e "\n  eTomo output $tomogram_3d already exists, skipping..."
        fi
      else
        if [[ "$verbose" -ge 2 ]]; then
          echo -e "\n  WARNING: eTomo output $tomogram_3d already exists"
          echo "    $(mv -v $tomogram_3d ${tomogram_3d}.bak)"
        else
          mv $tomogram_3d ${tomogram_3d}.bak
        fi
      fi
    fi
    
    if [[ "${do_reconstruct}" == true ]] ; then
      vprint "\n  $(date)" "3+"
      vprint   "  Computing tomogram reconstruction 'batchruntomo' from $num_mics micrographs" "3+"
      vprint "\n  Running: ${etomo_cmd}" "3+"

      # Full screen output
      if [[ "$verbose" -ge 7 ]]; then
        ${vars[imod_dir]}/${etomo_cmd} | tee ${etomo_out}
      
      # Quiet mode
      elif [[ "$verbose" -le 1 ]]; then
        ${vars[imod_dir]}/${etomo_cmd} > ${etomo_out}
      
      else
        ${vars[imod_dir]}/${etomo_cmd} | tee ${etomo_out} | stdbuf -o0 grep "Residual error mean and sd" | sed 's/^/   /'
        # (greps on the fly, and prepends spaces to output)
        
        grep "Final align" "${vars[outdir]}/${tomo_dir}/batchruntomo.log" 2> /dev/null | sed 's/^/    /'
      fi
      # End verbosity cases
      
      # Remove bad micrographs
      if [[ "${do_laudiseron}" == true ]] ; then
        run_laudiseron "${tomo_dir}" "${tomo_base}"
      fi
      
      local do_split_alignment=false
      if [[ "${vars[do_ruotnocon]}" == true ]] || [[ "${do_laudiseron}" == true ]] ; then
        do_split_alignment=true
      fi
      
      # If final alignment
      if [[ "${more_flags}" == "-start 6" ]] || [[ "${do_split_alignment}" == false ]] ; then
        
        # Sanity check: tomogram exists
        if [[ ! -f "$tomogram_3d" ]]; then
          vprint "\n$(date)" "1+"
          vprint   "WARNING! eTomo output '$tomogram_3d' does not exist\n" "1+"
          vprint   "Stdout ${etomo_out}:" "1+"
          cat ${etomo_out}
          vprint "\n         Continuing...\n" "1+"
          
          return
        
        # Tomogram found
        else
          vprint "\n$(date)" "1+"
          vprint   "Finished reconstructing '$tomogram_3d'\n" "1+"
          
          \rm ${etomo_out} 2> /dev/null
# #           get_central_slice ${tomogram_3d}
        fi
        # End sanity IF-THEN
      fi
      # End final-alignment IF-THEN
    fi
    # End do-reconstruct IF-THEN
  
  # If testing
  else
    if [[ "${vars[no_redo3d]}" == true ]] ; then
      do_reconstruct=false
      vprint "\n  eTomo output $tomogram_3d already exists, skipping..." "2+"
    else
      if [[ "$verbose" -ge 3 ]]; then
        echo -e "  TESTING $etomo_cmd\n"
      elif [[ "$verbose" -eq 2 ]]; then
        echo      "  ${etomo_cmd}"
      fi
      
      touch $tomogram_3d
    fi
    # End overwrite IF-THEN
  fi
  # End testing IF-THEN
}

  function run_laudiseron() {
  ###############################################################################
  #   Function:
  #     Removes micrographs with eTomo alignment residual exceeding a threshold
  #   
  #   Requires:
  #     sort_residuals.py
  #     
  #   Positional variables:
  #     1) sorted-residual plot file
  #     2) residual cutoff, units of sigma
  #   
  #   Global variables:
  #     tomo_dir
  #     sort_exe
  #     vars
  #     imgdir
  #     good_angles_file
  #     new_mdoc
  #   
  ###############################################################################
    
    tomo_dir=$1
    local tomo_base=$2
  
    # Sanity check for Python script
    sort_sanity
    
    local sort_cmd="$(echo ${sort_exe} \
      ${vars[outdir]}/${tomo_dir}/taSolution.log \
      --skip=4 \
      --sd ${vars[laudiseron_sd]} \
      --plot ${vars[outdir]}/${imgdir}/${resid_imgdir}/${tomo_base}_residuals.png | xargs)"
    
    vprint "\n  Finding micrographs with residuals exceeding ${vars[laudiseron_sd]}*SD..." "4+"
    vprint   "    ${sort_cmd}\n" "4+"
    
    IFS=' ' read -r -a bad_residuals <<< $($sort_cmd)
    unset IFS
    
    mapfile -t sorted_by_angle < $good_angles_file
    
    # Sort (adapted from https://stackoverflow.com/a/11789688)
    IFS=$'\n' sorted_bad=($(sort -r <<<"${bad_residuals[*]}")) ; unset IFS
    # (Sorting from highest to lowest in case indices are renumbered, which I don't believe is the case)
    
    # Remove array entries for bad micrographs
    for bad_idx in "${sorted_bad[@]}" ; do
      local mic2rm=$(( $bad_idx - 1))  # numbered from 0
      unset stripped_angle_array[${sorted_by_angle[$mic2rm]}]
    done
    
    vprint   "    Removed ${#sorted_bad[@]} micrographs from tilt series based on residual" "4+"
    
    # Write updated goodangles file
    sort_array_keys
    
    # Write new angles lists, restack micrographs, and update MDOC
    vprint   "" "4+"
    write_angles_lists
    imod_restack
    
    # Update MDOC
    local mdoc_copy="${vars[outdir]}/${tomo_dir}/${mdoc_base%.mrc.mdoc}_1-pre-laudiseron.mrc.mdoc"
    local temp_mdoc_dir="$(dirname ${new_mdoc})/tmp_mdoc"
    \cp ${new_mdoc} ${mdoc_copy}
    clean_up_mdoc "${mdoc_copy}" "${new_mdoc}" "$temp_mdoc_dir"
  }

function sort_sanity() {
###############################################################################
#   Function:
#     Sanity check for sort_residuals.py
#   
#   Requires:
#     sort_residuals.py
#     
#   Positional variables:
#     1) sorted-residual plot file
#     2) residual cutoff, units of sigma
#   
#   Global variables:
#     sort_exe
#   
###############################################################################
  
  # Sanity check
  if ! [ -z $SNARTOMO_DIR ] ; then
    sort_exe="python ${SNARTOMO_DIR}/sort_residuals.py"
  else
    if [[ -f "./sort_residuals.py" ]]; then
      sort_exe="python ./sort_residuals.py"
    else
      if [[ "${test_contour}" != true ]]; then
        echo -e "\nERROR!! Can't find 'sort_residuals.py'!"
        echo      "  Either copy to current directory or define 'SNARTOMO_DIR'"
        echo -e   "  Exiting...\n"
        exit
      else
        echo -e "\nWARNING! Can't find 'sort_residuals.py'"
        sort_exe="python sort_residuals.py"
        exit
      fi
      # End testing IF-THEN
    fi
    # End local IF-THEN
  fi
  # End SNARTOMO IF-THEN
  
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
#     contour_imgdir
#   
###############################################################################
  
  local tomo_dir=$1
  local tomo_base=$2
  
  local fid_file="${vars[outdir]}/${tomo_dir}/${tomo_base}_newstack.fid"
  
  ruotnocon_run \
    "${fid_file}" \
    "${vars[outdir]}/${tomo_dir}/taCoordinates.log" \
    "${fid_file}" \
    "${vars[ruotnocon_sd]}" \
    "${vars[outdir]}/${imgdir}/${contour_imgdir}/${tomo_base}_residuals.png" \
    "${vars[outdir]}/${tomo_dir}/tmp_contours" \
    "${vars[testing]}" \
    "${vars[imod_dir]}"
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
  #     find_bad_contours
  #     remove_contours
  #     backup_copy
  #   
  #   Global variables:
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
      vprint "  Creating directory: ${temp_contour_dir}/" "5+"
      mkdir ${temp_contour_dir}
    fi
    
    # Convert FID model to WIMP-format text file
    local convertmod_cmd="convertmod ${fid_file} ${wimp_file}"
    if [[ ${verbose} -ge 4 ]] ; then
      echo
      echo "  Converting to WIMP format: ${fid_file}"
      echo "    Running: $convertmod_cmd"
    fi
    
    if [[ "${test_contour}" != true ]]; then
      ${contour_imod_dir}/$convertmod_cmd
  #     local status_code=$?  # will be 1 on error, 0 if OK
    
      # Split WIMP file into chunks
      split_wimp "${wimp_file}"
    fi
    
    # Get contours exceeding residual cutoff (space-delimited list)
    find_bad_contours "${contour_plot}" "${num_sd}"
    
    if [[ "${test_contour}" != true ]]; then
      # Remove contours
      remove_contours
      
      # Get z-scale factor
      local zscale=$(${contour_imod_dir}/imodinfo -a ${fid_file} | grep scale | grep -v refcurscale | rev | cut -d" " -f1 | rev)
      
      # Convert to FID model
      local wmod2imod_cmd="${contour_imod_dir}/wmod2imod -z ${zscale} ${new_wimp} ${tmp_fid}"
      if [[ ${verbose} -ge 4 ]] ; then
        echo -e "\n  Converting to FID model..."
        echo -e "    Running: $wmod2imod_cmd"
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
        echo -e "    Running: $imodjoin_cmd"
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

    function find_bad_contours() {
    ###############################################################################
    #   Function:
    #     Get contours exceeding residual cutoff
    #   
    #   Positional variables:
    #     1) sorted-residual plot file
    #     2) residual cutoff, units of sigma
    #   
    #   Calls functions:
    #     sort_sanity
    #     
    #   Global variables:
    #     sort_exe
    #     test_contour
    #     contour_resid_file
    #     verbose
    #     bad_residuals (defined here)
    #   
    ###############################################################################
      
      local contour_plot=$1
      local num_sd=$2
      
      sort_sanity
      
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

        vprint "    Removed contour #${curr_resid}" "3+"
      
        # Remove index from array
        unset 'chunk_array[$contour2rm]'
        vprint "  chunk_array: '${#chunk_array[@]}' '${chunk_array[@]}'" "7+"
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
        
        cat ${chunk_file} >> ${new_wimp}
      done
        
      # Make sure not the last contour (which may have extra lines in the chunk file)
      if [[ ${contour2rm} -eq ${#chunk_array[@]} ]] ; then
        echo ""      >>  ${new_wimp}
        echo "  END" >>  ${new_wimp}
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
      
      if [ -z "$verbose" ] ; then
        local verbose=1
      fi
      
      # Check if file exists
      if [[ -f "$fn" ]]; then
        vprint "  File exists: '$fn'" "8+"
        
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

function backup_file() {
###############################################################################
#   Function:
#     Appends existing file with version number if it exists
#     
#   Positional variable:
#     1) Filename (required)
#     2) verbosity (default=1)
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
    if [ -z "$verbose" ] ; then
      local verbose=1
    fi
  fi
  
  # Check if file exists
  if [[ -f "$fn" ]]; then
    vprint "File exists: '$fn'" "8+"
    
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

function deconvolute_wrapper() {
###############################################################################
#   Function:
#     Runs deconvolution filter using IsoNet
#   
#   Positional variables:
#     1) I/O directory
#     2) MDOC file
#     3) Log file (optional)
#   
#   Global variables:
# #     stripped_angle_array
# #     mcorr_mic_array
#     df_angstroms
#     vars
#       isonet_env
#       apix
# #     chunk_prefix
#     isonet_star
#     tomogram_3d
#   
#   Calls functions:
#     get_untilted_defocus
#     vprint
#   
###############################################################################
  
  local io_dir=$1
  local mdoc_file=$2
  local outlog=$3
  
  # IsoNet creates a directory called './deconv_temp', so let's change to a unique directory where parallel processes won't conflict.
  local abs_outlog=$(realpath ${outlog} 2> /dev/null)
  local abs_tomo=$(realpath $tomogram_3d)
  
  get_untilted_defocus "$io_dir" "$mdoc_file"
  pushd ${io_dir} > /dev/null
  
  local temp_indir="InIsonet"
  local temp_outdir="OutIsonet"
  
  # Link tomogram so that there aren't multiple MRCs when we generate the STAR file
  mkdir $temp_indir 2> /dev/null
  ln -sf ${abs_tomo} $(realpath ${temp_indir}/)
  
  local conda_cmd="conda activate ${vars[isonet_env]}"
  local isonet_exe="isonet.py"
  
  # Get pixel size in binned reconstruction
  if [[ "${vars[testing]}" == false ]]; then
    local bin_apix=$(${vars[imod_dir]}/header $abs_tomo | grep Pixel | awk '{print $4}')
  else
    if [[ "${vars[batch_directive]}" == "" ]]; then
      local bin_apix=$(echo ${vars[are_bin]}* ${vars[apix]} | bc)
    else
      # We switched directories
      pushd 1> /dev/null
      local bin_factor=$(grep "runtime.AlignedStack.any.binByFactor" ${vars[batch_directive]} | cut -d '=' -f 2 | sed 's/\r//')
      pushd 1> /dev/null
# #       echo "4027 bin_factor '$bin_factor', apix '${vars[apix]}'" ; exit
      local bin_apix=$(echo ${bin_factor}* ${vars[apix]} | bc)
    fi
    # End eTomo IF-THEN
#     
#     echo "4031 bin_apix '$bin_apix'" ; exit
  fi
  # End testing IF-THEN
  
  # Prepare STAR file
  local star_args="prepare_star ${temp_indir} --output_star ${isonet_star} --pixel_size ${bin_apix} --defocus ${df_angstroms}"
  local star_cmd="${isonet_exe} ${star_args}"
  
  # Deconvolute
  local deconvolute_args="deconv ${isonet_star} --snrfalloff ${vars[snr_falloff]} --deconv_folder ${temp_outdir}"
  local deconvolute_cmd="${isonet_exe} ${deconvolute_args}"
  
  if [[ "${vars[testing]}" == false ]]; then
    vprint "\n  Executing: $conda_cmd" "2+" "=${abs_outlog}"
    $conda_cmd 2> /dev/null
    vprint   "    conda environment: '$CONDA_DEFAULT_ENV'" "2+" "=${abs_outlog}"
    
    vprint "\n    Executing: ${star_cmd}" "2+" "=${abs_outlog}"
    if [[ "${do_pace}" == true ]]; then
      $star_cmd        >>${abs_outlog} 2>&1
    else
      $star_cmd
    fi
    
    vprint "\n    Executing: $deconvolute_cmd" "2+" "=${abs_outlog}"
    if [[ "${do_pace}" == true ]]; then
      $deconvolute_cmd >> ${abs_outlog} 2>&1
    else
      $deconvolute_cmd
    fi
    
    # Move to io_dir and use this volume from now on
    local tomo_base=$(basename $tomogram_3d)
    local orig_location="${temp_outdir}/${tomo_base}"
    local new_location="${tomo_base%.mrc}_deconv.mrc"
    local move_cmd="mv $orig_location $new_location"
    $move_cmd 2> /dev/null
    popd > /dev/null
    new_location="${io_dir}/${new_location}"
    
    # Sanity check
    if [[ -e $new_location ]] ; then
      vprint "  Moved '$(basename ${temp_outdir})/${tomo_base}' to $(basename ${new_location})" "2+" "=${outlog}"
      tomogram_3d=$new_location
      \rm -r ${temp_dir} 2> /dev/null
    else
      vprint "\nWARNING! IsoNet output '$new_location' does not exist!" "1+" "${main_log} =${warn_log} =${outlog}"
      vprint   "         Attempted command line: '$move_cmd'" "1+" "=${outlog}"
      vprint   "         Continuing...\n" "1+" "=${outlog}"
    fi
    
    # Clean up
    conda deactivate
    vprint "  conda environment: '$CONDA_DEFAULT_ENV'\n" "2+" "=${outlog}"
  
  # Testing
  else
    # Clean up
    \rm ${temp_indir}/$(basename $tomogram_3d)
    rmdir ${temp_indir}
    
    popd > /dev/null
    vprint "  TESTING: ${star_cmd}" "3+" "=${abs_outlog}"
    vprint "  TESTING: ${deconvolute_cmd}\n" "3+" "=${abs_outlog}"
  fi
  # End testing IF-THEN
}

  function get_untilted_defocus() {
  ###############################################################################
  #   Function:
  #     Gets defocus for minimum angle from MDOC file
  #   
  #   Positional variables:
  #     1) I/O directory
  #     2) MDOC file
  #   
  #   Calls functions:
  #     split_mdoc
  #   
  #   Global variables:
  #     stripped_angle_array
  #     mcorr_mic_array
  #     vars
  #     chunk_prefix
  #     ctf_summary
  #     df_angstroms (OUTPUT)
  #   
  ###############################################################################
    
    local io_dir=$1
    local mdoc_file=$2
    
    local min_angle=360
    local min_index=-1
    
    for idx in "${!stripped_angle_array[@]}" ; do
      local curr_angle=${stripped_angle_array[$idx]}
      
      # Take absolute value (from https://stackoverflow.com/a/47240327)
      local abs_angle=${curr_angle#-}
      
      # Update if minimum
      if (( $(echo "${abs_angle} < ${min_angle}" |bc -l) )); then
        min_angle=${abs_angle}
        min_index=${idx}
      fi
    done
    
    if [[ $mdoc_file != "" ]] ; then
      local temp_dir="${io_dir}/tmp_mdoc"
      split_mdoc "${mdoc_file}" "${temp_dir}"
      local min_mic_stem=$(basename ${mcorr_mic_array[$min_index]%_mic.mrc})
      
      # Get defocus value
      if [[ "${vars[testing]}" == true ]]; then
        local min_chunk=$(grep -l $min_mic_stem ${chunk_prefix}*)
        local df_microns=$(grep "CtfFind =" $min_chunk | awk '{print $3}' )
        
  #       ### TESTING
  #       grep "CtfFind =" $min_chunk
  #       echo "2979 df_microns '$df_microns'"
  #       exit

        df_angstroms=$(echo -10000*${df_microns} | bc)
      else
        # Get data from CTFFIND
        local tomo_ctfs="${io_dir}/${ctf_summary}"
        local ctf_data=$(grep $min_mic_stem ${tomo_ctfs} | tail -n 1 | xargs)
        local df_minor=$(echo $ctf_data | cut -d " " -f 3)
        local df_major=$(echo $ctf_data | cut -d " " -f 4)
        df_angstroms=$(echo $df_minor/2 + $df_major/2 | bc)
      fi
    else
      df_angstroms="0.0"
    fi
    # End MDOC IF-THEN
#     
#     echo " 4145 df_angstroms '$df_angstroms'" ; exit
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
#     axis_array
#     verbose
#     imgdir
#     thumbdir
#   
###############################################################################
  
  local fn=$1

  local trim_log="${vars[outdir]}/${tomo_dir}/trimvol.log"
  
  local dimension_string=$(${vars[imod_dir]}/header $fn | grep sections | xargs | rev | cut -d' ' -f1-3 | rev)
  IFS=' ' read -r -a dimension_array <<< ${dimension_string}
  
  # initialize minimum
  min_dim=99999
  axis_array=("-nx" "-ny" "-nz")
  
  # Get minimimum dimension & axis
  get_shortest_axis
#   for idx in "${!dimension_array[@]}" ; do
#     if (( $( echo "${dimension_array[$idx]} < $min_dim" | bc -l ) )) ; then
#       min_dim=${dimension_array[$idx]}
#       min_axis=${axis_array[$idx]}
#     fi
#   done
#   
  min_axis=${axis_array[$min_idx]}
  
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
  echo ""
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
  vprint "    $trim_cmd" "3+"

  if [[ "$verbose" -ge 7 ]]; then
    ${vars[imod_dir]}/$trim_cmd 2>&1 | tee ${trim_log}
  else
    ${vars[imod_dir]}/$trim_cmd 1> ${trim_log}
  fi
  
  jpg_slice="${tomo_stem}_slice.jpg"
  jpg_cmd="mrc2tif -j ${mrc_slice} ${jpg_slice}"
  vprint "    $jpg_cmd" "3+"
  
  # Suppress "Writing JPEG images"
  if [[ "$verbose" -le 6 ]]; then
#     ${vars[imod_dir]}/$jpg_cmd #&& rm ${mrc_slice} 2> /dev/null
    ${vars[imod_dir]}/$jpg_cmd 1> /dev/null
  else
    ${vars[imod_dir]}/$jpg_cmd #&& rm mrc_slice${}
  fi
  
  central_slice_jpg="${vars[outdir]}/${imgdir}/${thumbdir}/$(basename ${tomo_stem})_slice_norm.jpg"
  norm_cmd="convert ${jpg_slice} -normalize $central_slice_jpg "
  vprint "    $norm_cmd" "3+"
  $norm_cmd && rm ${jpg_slice}
}

function get_shortest_axis() {
###############################################################################
#   Function:
#     FUNCTION
#   
#   Positional variables:
#   
#   Calls functions:
#   
#   Global variables:
#     vars
#     fn
#     min_dim (OUTPUT)
#     min_idx (OUTPUT)
#   
###############################################################################
  
  local dimension_string=$(${vars[imod_dir]}/header $fn | grep sections | xargs | rev | cut -d' ' -f1-3 | rev)
  IFS=' ' read -r -a dimension_array <<< ${dimension_string}
  
  # initialize minimum
  min_dim=99999
  
  # Get minimimum (https://stackoverflow.com/a/40642705)
  for idx in "${!dimension_array[@]}" ; do
    if (( $( echo "${dimension_array[$idx]} < $min_dim" | bc -l ) )) ; then
      min_dim=${dimension_array[$idx]}
      min_idx=$idx
    fi
  done
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
