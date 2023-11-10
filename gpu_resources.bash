#!/bin/bash

###############################################################################
# Changelog:
#   2022-04-28 (trs) -- can monitor over time, as text or in Gnuplot
###############################################################################

if ! [ -x "$(which nvidia-smi 2> /dev/null)" ]; then
  echo "ERROR!! nvidia-smi not found! GPU monitoring will be disabled..."
  return
fi

function gpu_resources() {
###############################################################################
#   Function:
#     Shows GPU memory usage
#     In format of nvidia-smi
#     
#   Positional variables:
#     1) Units (optional)
#     
###############################################################################
  
  local default_unit="MiB"
  
  if [[ "$1" != "" ]]; then
    default_unit=$1
  fi
  
  if [ -x "$(which nvidia-smi)" ]; then
    prev_line=""

    # BASH 4 syntax
    readarray -t smi_array < <(nvidia-smi)
    
    for line_idx in ${!smi_array[@]} ; do 
      local curr_line=${smi_array[$line_idx]}
      num_words=$(echo $curr_line | wc -w | bc)
      
      if [[ "$curr_line" == *"%"* ]]; then
        local gpu_num=$(echo $prev_line | cut -d" " -f2)
        local gpu_usage=$(echo $curr_line | grep -o '\b\w*MiB\b' | head -n 1)
        echo "GPU $gpu_num: $gpu_usage"
      fi
      
      # Remember previous line
      local prev_line=$curr_line
    done
  else
    echo "ERROR!! nvidia-smi not found!"
  fi
}

function gpu_parse() {
###############################################################################
#   Function:
#     Shows GPU usage
#     Formatted as a a list of number with no units (default: MiB)
###############################################################################
  
  local WARNED=false
  local default_unit="MiB"

  while read -r gpu_line ; do
    # Parse only usage number (e.g., from "GPU 1: 5MiB / 11019MiB")
    memory_used=$(echo $gpu_line | cut -d' ' -f 3)
    
    # Extract number
    memory_num=$(echo $memory_used | grep -o -E '[0-9]+')
    
    # Extract units
    memory_unit=$(printf '%s\n' "${memory_used//[[:digit:]]/}")
    
    # Warn if not megabytes
    if [[ "${memory_unit}" != "${default_unit}" ]] && [[ "${WARNED}" == false ]] ; then
      echo "WARNING! gpu_parse: Expected units '${default_unit}', instead saw '${memory_unit}'"
      WARNED=true
    fi
    
    echo "$memory_num"
  done <<< $(gpu_resources)
}

function gpu_chart() {
###############################################################################
#   Function:
#     Shows GPU usage over time
#     Format: Date  GPU0  GPU1  ...
#     
#   Positional variables:
#     1) Duration, seconds (required)
#     2) Interval, seconds (optional, default: 2)
#     3) Log file (optional, default: output to screen)
###############################################################################
  
  local max_seconds=$1
  local DEFAULT_DELAY=2
  local WARNED=false
  local default_unit="MiB"
  local TIMEFMT="%Y-%m-%d %H:%M:%S"

  
  if [[ "$1" == "" ]]; then
    echo "ERROR!! Duration parameter required!"
    return
  fi
  
  if [[ "$2" != "" ]]; then
    local delay=$2
  else
    local delay=$DEFAULT_DELAY
  fi
  
  if [[ "$3" != "" ]]; then
    local DO_ECHO=false
    local logfile=$3
    rm "${logfile}" 2> /dev/null
  else
    local DO_ECHO=true
  fi
  
  local start_time=$SECONDS
  while (( $(echo "$(( $SECONDS - $start_time )) < $max_seconds" | bc) )) ; do
    line=$(date +"${TIMEFMT}")
    
    while read -r gpu_line ; do
      gpu_label=$(echo $gpu_line | cut -d':' -f 1)
      
      # Parse only usage number (e.g., from "GPU 1: 5MiB / 11019MiB")
      memory_used=$(echo $gpu_line | cut -d' ' -f 3)
      
      # Extract number
      memory_num=$(echo $memory_used | grep -o -E '[0-9]+')
      line+="\t$memory_num"
      
      # Check units
      memory_unit=$(printf '%s\n' "${memory_used//[[:digit:]]/}")
      
      # Warn if not megabytes
      if [[ "${memory_unit}" != "${default_unit}" ]] && [[ "${WARNED}" == false ]] ; then
        echo "WARNING! Expected units '${default_unit}', instead saw '${memory_unit}'"
        WARNED=true
      fi
      
    done <<< $(gpu_resources)
    # End GPU loop
    
    if [[ "${DO_ECHO}" == false ]] ; then
#       echo -e "$line" | tee -a "${logfile}"
      echo -e "$line" >> "${logfile}"
    else
      echo -e "$line"
    fi
    
    sleep "${delay}"
  done
  # End time loop
}

function gpu_plot() {
###############################################################################
#   Function:
#     Shows GPU usage over time, and generates gnuplot script
#     
#   Usage:
#     gpu_plot 1000 2 log-gpu.txt plot.gnu
#     
#   Calls functions:
#     gpu_resources
#     
#   Positional variables:
#     1) Duration, seconds (required)
#     2) Interval, seconds (optional, default: 2)
#     3) Log file (optional, default: output to screen)
#     4) Gnuplot script name -- to run, type: 'gnuplot <script_name> --persist'
#     5) Termination file
#     
###############################################################################
  
  local max_seconds=$1
  local DEFAULT_DELAY=2
  local WARNED=false
  local default_unit="MiB"
  declare -a gpu_array
#   local DO_COUNT=true
  local TIMEFMT='%Y-%m-%d-%H:%M:%S'
  hdr_line="#\t\t"

  if [[ "$1" == "" ]]; then
    echo "ERROR!! Duration parameter required!"
    return
  fi
  
  if [[ "$2" != "" ]]; then
    local delay=$2
  else
    local delay=$DEFAULT_DELAY
  fi
  
  if [[ "$3" != "" ]]; then
    local DO_ECHO=false
    local logfile=$3
  else
    local DO_ECHO=true
  fi
  
  local plotfile=$4
  local termination_file=$5
  
  # Write Gnuplot script (can write in advance)
  if [[ "${plotfile}" != "" ]]; then
    rm "${plotfile}" 2> /dev/null
    echo "set xdata time" >> "${plotfile}"
    echo "set timefmt  '${TIMEFMT}'" >> "${plotfile}"
    echo "set format x '${TIMEFMT}'" >> "${plotfile}"
    echo "set xtics rotate" >> "${plotfile}"
    echo "set ylabel 'Memory usage (${default_unit})'" >> "${plotfile}"
    echo "plot \\" >> "${plotfile}"
    gpu_counter=1
    while read -r gpu_line ; do
      gpu_label=$(echo $gpu_line | cut -d':' -f 1)
      let "gpu_counter++"
      echo "'$(realpath ${logfile})' using 1:${gpu_counter} with lines title '${gpu_label}', \\" >> "${plotfile}"
    done <<< $(gpu_resources)
  fi
  
  # Get GPU IDs
  readarray -t gpu_array < <(nvidia-smi -q | grep "^GPU") 2> /dev/null
  buildHeader
  
  # Write header line
  if ! [[ -f "${logfile}" ]] && [[ "${DO_ECHO}" == false ]] ; then
    echo -e "$hdr_line" >> "${logfile}"
  else
    if [[ "${DO_ECHO}" == true ]] ; then
      echo -e "$hdr_line"
    fi
  fi

  local start_time=$SECONDS
  while (( $(echo "$(( $SECONDS - $start_time )) < $max_seconds" | bc) )) ; do
    line=$(date +"${TIMEFMT}")
    
#     while read -r gpu_line ; do
# # # #       echo "232 gpu_line '$gpu_line'"
#       
#       # Parse only usage number (e.g., from "GPU 1: 5MiB / 11019MiB")
#       memory_used=$(echo $gpu_line | cut -d' ' -f 3)
#       echo "234 memory_used '$memory_used'"
#       
#       # Extract number
#       memory_num=$(echo $memory_used | grep -o -E '[0-9]+')
#       echo "237 memory_num '$memory_num'"
#       line+="\t$memory_num"
#       
#       # Check units
#       memory_unit=$(printf '%s\n' "${memory_used//[[:digit:]]/}")
#       echo "241 memory_unit '$memory_unit'"
# # #       return  ### TESTING
#       
#       # Warn if not megabytes
#       if [[ "${memory_unit}" != "${default_unit}" ]] && [[ "${WARNED}" == false ]] ; then
#         WARNED=true
#         
#         # Units could be wrong or, worse, blank if there's a problem with graphics driver
#         if [[ "${memory_unit}" != "" ]] ; then
#           echo "WARNING! gpu_plot: Expected units '${default_unit}', instead saw '${memory_unit}'"
#         else
#           echo    "WARNING! gpu_plot: Expected units '${default_unit}'"
#           echo    "  nvidia-smi output: "
#           echo    "$(nvidia-smi)"
#           echo -e "Exiting gpu_plot...\n"
#           return  # 'exit' will close terminal
#         fi
#       fi
#       
#     done <<< $(gpu_resources)
    
    # BASH 4 syntax
    mapfile -t resource_array < <(gpu_resources) 
# # #     for gpu_line in ${resource_array[@]} ; do 
    for gpu_idx in ${!resource_array[@]} ; do 
      local gpu_line=${resource_array[$gpu_idx]}
# # #       echo "305 gpu_line '${gpu_line}'"
      
      # Parse only usage number (e.g., from "GPU 1: 5MiB / 11019MiB")
      memory_used=$(echo $gpu_line | cut -d' ' -f 3)
# # #       echo "309 memory_used '$memory_used'"
      
      # Extract number
      memory_num=$(echo $memory_used | grep -o -E '[0-9]+')
# # #       echo "313 memory_num '$memory_num'"
      line+="\t$memory_num"
      
      # Check units
      memory_unit=$(printf '%s\n' "${memory_used//[[:digit:]]/}")
# # #       echo "318 memory_unit '$memory_unit'"
    done
# # #     return  ### TESTING
    
    if [[ "${DO_ECHO}" == false ]] ; then
      echo -e "$line" >> "${logfile}"
    else
      echo -e "$line"
    fi
    
    if [[ -f "${termination_file}" ]]; then
#       echo "gpu_plot: Found ${termination_file}, exiting..."
      break
    fi
    
    sleep "${delay}"
  done
}

function ram_resources() {
###############################################################################
#   Function:
#     Shows RAM usage
#     In format of 'free -g'
#     
#   Adapted from gpu_resources()
###############################################################################
 
  readarray -t free_array < <(free -g)
  
  # Parse column line
  IFS=' ' read -r -a col_array <<< $(echo ${free_array[0]} | tr -s ' ')
  
  # Parse memory line
  IFS=' ' read -r -a mem_array <<< $(echo ${free_array[1]} | tr -s ' ')
  
  # Remove "Mem:" and re-index
  unset mem_array[0]
  mem_array=("${mem_array[@]}")
  
  # Assign values to column
  declare -A val_array
  for idx in ${!col_array[@]} ; do
    echo "${col_array[$idx]}=$(echo ${mem_array[$idx]} | tr -dc '[. [:digit:]]')"
  done
}

function ram_plot() {
###############################################################################
#   Function:
#     Shows RAM usage
#     In format of 'free -g' (gigabytes, integer)
#     
#   Positional variables:
#     1) Duration, seconds (required)
#     2) Interval, seconds (optional, default: 2)
#     3) List of columns to print. Options are:
#           total
#           used
#           free (DEFAULT)
#           shared
#           buff/cache
#           available
#     4) Log file (optional, default: output to screen)
#     5) Plot file (optional)
#     6) Termination file (optional) : will exit when file is detected
#     
#   Adapted from gpu_chart()
###############################################################################
 
  local DEFAULT_DELAY=2  # units: seconds
  local TIMEFMT="%Y-%m-%d-%H:%M:%S" 
  local default_unit="Gi"
  local hdr_line="#\t\t"
  
  local max_seconds=$1
  
  if [[ "$1" == "" ]]; then
    echo "ERROR!! Duration parameter required!"
    return
  fi
  
  if [[ "$2" != "" ]]; then
    local delay=$2
  else
    local delay=$DEFAULT_DELAY
  fi
  
  local col_list=$3
  if [[ "${col_list}" == "" ]]; then
    local col_list="free"
  fi
  
  if [[ "$4" != "" ]]; then
    local DO_ECHO=false
    local logfile=$4
  else
    local DO_ECHO=true
  fi
  
  local plotfile=$5
  local termination_file=$6
  
  # Build header line
  while read -r mem_line ; do
    curr_col=$(echo "${mem_line}" | cut -d "=" -f 1)
    
    # Search input list for string
    if [[ "${col_list}" =~ .*"${curr_col}".* ]]; then
      let "col_counter++"
      mem_label=$(echo $mem_line | cut -d'=' -f 1)
      hdr_line+="\t$mem_label"
    
#     # Diagnostic
#     else
#       echo "'$curr_col' not in '$col_list'"
    fi
  done <<< $(ram_resources)

  # Write Gnuplot script (can write in advance)
  if [[ "${plotfile}" != "" ]]; then
    rm "${plotfile}" 2> /dev/null
    echo "set xdata time" >> "${plotfile}"
    echo "set timefmt  '${TIMEFMT}'" >> "${plotfile}"
    echo "set format x '${TIMEFMT}'" >> "${plotfile}"
    echo "set xtics rotate" >> "${plotfile}"
    echo "set ylabel 'Memory usage (${default_unit})'" >> "${plotfile}"
    echo "plot \\" >> "${plotfile}"
    col_counter=1
    while read -r mem_line ; do
      curr_col=$(echo "${mem_line}" | cut -d "=" -f 1)
      
      # Search input list for string
      if [[ "${col_list}" =~ .*"${curr_col}".* ]]; then
        let "col_counter++"
        mem_label=$(echo $mem_line | cut -d'=' -f 1)
        echo "'$(realpath ${logfile})' using 1:${col_counter} with lines title '${mem_label}', \\" >> "${plotfile}"
      fi
      # TODO: make sure at least one value is plotted
    done <<< $(ram_resources)
  fi
  
  # Write header line
  if ! [[ -f "${logfile}" ]] && [[ "${DO_ECHO}" == false ]] ; then
    echo -e "$hdr_line" >> "${logfile}"
  else
    if [[ "${DO_ECHO}" == true ]] ; then
      echo -e "$hdr_line"
    fi
  fi

  local start_time=$SECONDS
  while (( $(echo "$(( $SECONDS - $start_time )) < $max_seconds" | bc) )) ; do
    local timept_line=$(date +"${TIMEFMT}")
    
    while read -r mem_line ; do
      curr_col=$(echo "${mem_line}" | cut -d "=" -f 1)
      
      # Search input list for string
      if [[ "${col_list}" =~ .*"${curr_col}".* ]]; then
        value=$(echo "${mem_line}" | cut -d "=" -f 2)
        timept_line+="\t$value"
      fi
    done <<< $(ram_resources)
    
    if [[ "${DO_ECHO}" == false ]] ; then
      echo -e "$timept_line" >> "${logfile}"
    else
      echo -e "$timept_line"
    fi
    
    if [[ -f "${termination_file}" ]]; then
      break
    fi
    
    sleep "${delay}"
  done
}

function power_resources() {
###############################################################################
#   Function:
#     Shows GPU power usage
#     Unformatted: nvidia-smi -q | grep --color=never "^GPU\|GPU Current Temp\|Power Draw"
###############################################################################
  
  if [ -x "$(which nvidia-smi)" ]; then
    # Read GPU devices into array
    readarray -t gpu_array   < <(nvidia-smi -q | grep "^GPU") 2> /dev/null
    readarray -t power_array < <(nvidia-smi -q | grep "Power Draw" --color=never | cut -d: -f2 | sed -e 's/^[[:space:]]*//')
    readarray -t temp_array  < <(nvidia-smi -q | grep "GPU Current Temp" --color=never | cut -d: -f2 | sed -e 's/^[[:space:]]*//')
    
    # Loop through GPUs
    for gpu_idx in "${!gpu_array[@]}"; do 
      echo "${gpu_array[$gpu_idx]}"
      echo "  Power Draw       : ${power_array[$gpu_idx]}"
      echo "  GPU Current Temp : ${temp_array[$gpu_idx]}"
    done
  else
    echo "ERROR!! nvidia-smi not found!"
  fi
}

function power_plot() {
###############################################################################
#   Function:
#     Shows GPU power usage
#     
#   Positional variables:
#     1) Duration, seconds (required)
#     2) Interval, seconds (optional, default: 2)
#     3) Power log file (optional, default: output to screen)
#     4) Plot file (optional)
#     5) Termination file (optional) : will exit when file is detected
#     
#   Adapted from ram_plot()
###############################################################################
 
  local DEFAULT_DELAY=2  # units: seconds
  local TIMEFMT="%Y-%m-%d-%H:%M:%S" 
  local default_unit="W"
  hdr_line="#\t\t"
  
  local max_seconds=$1
  
  if [[ "$1" == "" ]]; then
    echo "ERROR!! Duration parameter required!"
    return
  fi
  
  if [[ "$2" != "" ]]; then
    local delay=$2
  else
    local delay=$DEFAULT_DELAY
  fi
  
  if [[ "$3" != "" ]]; then
    local DO_ECHO=false
    local logfile=$3
  else
    local DO_ECHO=true
  fi
  
  local plotfile=$4
  local termination_file=$5
  
  # Get GPU IDs
  readarray -t gpu_array < <(nvidia-smi -q | grep "^GPU") 2> /dev/null
  
  # Build header line
  buildHeader
#   for gpu_num in "${!gpu_array[@]}"; do 
#     local gpu_line="${gpu_array[$gpu_num]}"
#     local gpu_id=$(echo ${gpu_line} | cut -d" " -f2)
#     
#     # If all 0s before first colon, then ignore
#     local before_colon=$(echo ${gpu_id} | cut -d: -f1 | sed 's/0//g')
#     if [[ "${before_colon}" == "" ]]; then
# #         echo "before_colon : <blank>"
#       local gpu_label=$(echo ${gpu_id} | cut -d: -f2-)
#       gpu_array[$gpu_num]=${gpu_label}
#     else
# #         echo "before_colon : '${before_colon}'"
#       local gpu_label=${gpu_id}
#     fi
#     
#     hdr_line+="\t$gpu_label"
#   done 
  
  # Write Gnuplot script (can write in advance)
  if [[ "${plotfile}" != "" ]]; then
    rm "${plotfile}" 2> /dev/null
    echo "set xdata time" >> "${plotfile}"
    echo "set timefmt  '${TIMEFMT}'" >> "${plotfile}"
    echo "set format x '${TIMEFMT}'" >> "${plotfile}"
    echo "set xtics rotate" >> "${plotfile}"
    echo "set ylabel 'Power draw (${default_unit})'" >> "${plotfile}"
    echo "plot \\" >> "${plotfile}"
    col_counter=1
    for gpu_line in "${gpu_array[@]}"; do 
      curr_col=$(echo "${gpu_line}" | cut -d "=" -f 1)
      
      # Search input list for string
      let "col_counter++"
      gpu_label=$(echo $gpu_line | cut -d'=' -f 1)
#         echo "${col_counter} ${gpu_label}"
      echo "'$(realpath ${logfile})' using 1:${col_counter} with lines title '${gpu_line}', \\" >> "${plotfile}"
      # TODO: make sure at least one value is plotted
    done
  fi
  
  # Write header line
  if ! [[ -f "${logfile}" ]] && [[ "${DO_ECHO}" == false ]] ; then
    echo -e "$hdr_line" >> "${logfile}"
  else
    if [[ "${DO_ECHO}" == true ]] ; then
      echo -e "$hdr_line"
    fi
  fi

  local start_time=$SECONDS
  while (( $(echo "$(( $SECONDS - $start_time )) < $max_seconds" | bc) )) ; do
    local timept_line=$(date +"${TIMEFMT}")
    
    while read -r gpu_line ; do
      local no_units=$(echo ${gpu_line} | sed 's/ W//g')
#       echo "no_units : '${no_units}'" ; exit
      timept_line+="\t$no_units"
    done <<< $(nvidia-smi -q | grep "Power Draw" --color=never | cut -d: -f2 | sed -e 's/^[[:space:]]*//')
    
    if [[ "${DO_ECHO}" == false ]] ; then
      echo -e "$timept_line" >> "${logfile}"
    else
      echo -e "$timept_line"
    fi
    
    if [[ -f "${termination_file}" ]]; then
#       echo "Found ${termination_file}, exiting..."
      break
    fi
    
    sleep "${delay}"
  done
}

function buildHeader() {
###############################################################################
#   Function:
#     Constructs header line
#   
#   Positional variables:
#   
#   Calls functions:
#   
#   Global variables:
#     gpu_array
#     hdr_line (MODIFIED)
#   
###############################################################################
  
  # Build header line
  for gpu_num in "${!gpu_array[@]}"; do 
    local gpu_line="${gpu_array[$gpu_num]}"
    local gpu_id=$(echo ${gpu_line} | cut -d" " -f2)
    
    # If all 0s before first colon, then ignore
    local before_colon=$(echo ${gpu_id} | cut -d: -f1 | sed 's/0//g')
    if [[ "${before_colon}" == "" ]]; then
#         echo "before_colon : <blank>"
      local gpu_label=$(echo ${gpu_id} | cut -d: -f2-)
      gpu_array[$gpu_num]=${gpu_label}
    else
#         echo "before_colon : '${before_colon}'"
      local gpu_label=${gpu_id}
    fi
    
    hdr_line+="\t$gpu_label"
  done 
}

function temperature_plot() {
###############################################################################
#   Function:
#     Shows GPU current temperature
#     
#   Positional variables:
#     1) Duration, seconds (required)
#     2) Interval, seconds (optional, default: 2)
#     3) Power log file (optional, default: output to screen)
#     4) Plot file (optional)
#     5) Termination file (optional) : will exit when file is detected
#     
#   Adapted from ram_plot()
###############################################################################
 
  local DEFAULT_DELAY=2  # units: seconds
  local TIMEFMT="%Y-%m-%d-%H:%M:%S" 
  local default_unit="C"
  local hdr_line="#\t\t"
  
  local max_seconds=$1
  
  if [[ "$1" == "" ]]; then
    echo "ERROR!! Duration parameter required!"
    return
  fi
  
  if [[ "$2" != "" ]]; then
    local delay=$2
  else
    local delay=$DEFAULT_DELAY
  fi
  
  if [[ "$3" != "" ]]; then
    local DO_ECHO=false
    local logfile=$3
  else
    local DO_ECHO=true
  fi
  
  local plotfile=$4
  local termination_file=$5
  
  # Get GPU IDs
  readarray -t gpu_array < <(nvidia-smi -q | grep "^GPU") 2> /dev/null
  buildHeader
  
#   # Build header line
#   for gpu_num in "${!gpu_array[@]}"; do 
#     local gpu_line="${gpu_array[$gpu_num]}"
#     local gpu_id=$(echo ${gpu_line} | cut -d" " -f2)
#     
#     # If all 0s before first colon, then ignore
#     local before_colon=$(echo ${gpu_id} | cut -d: -f1 | sed 's/0//g')
#     if [[ "${before_colon}" == "" ]]; then
# #         echo "before_colon : <blank>"
#       local gpu_label=$(echo ${gpu_id} | cut -d: -f2-)
#       gpu_array[$gpu_num]=${gpu_label}
#     else
# #         echo "before_colon : '${before_colon}'"
#       local gpu_label=${gpu_id}
#     fi
#     
#     hdr_line+="\t$gpu_label"
#   done 
  
  # Write Gnuplot script (can write in advance)
  if [[ "${plotfile}" != "" ]]; then
    rm "${plotfile}" 2> /dev/null
    echo "set xdata time" >> "${plotfile}"
    echo "set timefmt  '${TIMEFMT}'" >> "${plotfile}"
    echo "set format x '${TIMEFMT}'" >> "${plotfile}"
    echo "set xtics rotate" >> "${plotfile}"
    echo "set ylabel 'Power draw (${default_unit})'" >> "${plotfile}"
    echo "plot \\" >> "${plotfile}"
    col_counter=1
    for gpu_line in "${gpu_array[@]}"; do 
      curr_col=$(echo "${gpu_line}" | cut -d "=" -f 1)
      
      # Search input list for string
      let "col_counter++"
      gpu_label=$(echo $gpu_line | cut -d'=' -f 1)
#         echo "${col_counter} ${gpu_label}"
      echo "'$(realpath ${logfile})' using 1:${col_counter} with lines title '${gpu_line}', \\" >> "${plotfile}"
      # TODO: make sure at least one value is plotted
    done
  fi
  
  # Write header line
  if ! [[ -f "${logfile}" ]] && [[ "${DO_ECHO}" == false ]] ; then
    echo -e "$hdr_line" >> "${logfile}"
  else
    if [[ "${DO_ECHO}" == true ]] ; then
      echo -e "$hdr_line"
    fi
  fi

  local start_time=$SECONDS
  while (( $(echo "$(( $SECONDS - $start_time )) < $max_seconds" | bc) )) ; do
    local timept_line=$(date +"${TIMEFMT}")
    
    while read -r gpu_line ; do
      local no_units=$(echo ${gpu_line} | sed 's/ C//g')
#       echo "no_units : '${no_units}'" ; exit
      timept_line+="\t$no_units"
    done <<< $(nvidia-smi -q | grep "GPU Current Temp" --color=never | cut -d: -f2 | sed -e 's/^[[:space:]]*//')
    
    if [[ "${DO_ECHO}" == false ]] ; then
      echo -e "$timept_line" >> "${logfile}"
    else
      echo -e "$timept_line"
    fi
    
    if [[ -f "${termination_file}" ]]; then
#       echo "Found ${termination_file}, exiting..."
      break
    fi
    
    sleep "${delay}"
  done
}

########################################################################################

# Check whether script is being sourced or executed (https://stackoverflow.com/a/2684300/3361621)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
#   echo "script ${BASH_SOURCE[0]} is being executed..."
   gpu_plot "$@"
# else
#   echo "script ${BASH_SOURCE[0]} is being sourced..."
fi
