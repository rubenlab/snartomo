#!/bin/bash
# # set -u  # error if variable undefined

###############################################################################
# Function:
#
# Changelog:
#   2022-09-16 (trs) -- parallelized 3D reconstruction
#   2022-09-07 (trs) -- remove bad eTomo contours
#   2022-08-02 (trs & tcc) -- AreTomo 1.2.5 now the default
#   2022-07-22 (trs & tcc) -- added dose-fitting option
#   2022-06-10 (trs & ks) -- continue existing run
#   2022-06-10 (trs & tcc) -- targets file, last angle, and gain file are required parameters
#   2022-05-24 (trs & tcc) -- writing separate CTF summary files for each tomogram
#   
###############################################################################

function program_info() {
  echo "Running: SNARTomoPACE"
  echo "Modified 2022-12-09"
  date
  echo 
}

function print_usage() {
  echo "USAGE:     $(basename $0) 'target_files*.txt' --gain_file <gain_file> <options>"
  echo "LIVE MODE: $(basename $0) 'target_files*.txt' --gain_file <gain_file> --live --last_tilt <last_tilt_angle> <options>"
  echo "DRY RUN:   $(basename $0) 'target_files*.txt' --gain_file <gain_file> <options> --testing"
  echo "           Quotes (single or double) required if more than one targets file"
  echo
  echo "To list options & defaults, type:"
  echo "  $(basename $0) --help"
}

#################### Filenames ####################

shared_libs=snartomo-shared.bash              # Shared libraries
input_dir=frames                                   # Input directory for EER movies
frame_file=motioncor-frame.txt                     # Frames file
outdir=SNARTomoPACE                                # Output top-level directory

#################### Parameters ###################

# General parameters
LAST_TILT=-999.9                                  # Last (not highest) tilt angle in tilt series
tilt_tolerance=0.2                                # Angle difference of last tilt +/- this value will signal end of series
max_minutes=100                                   # Maximum run time, minutes
search_interval=2                                 # Monitors files & resources every N seconds
apix=-1.00                                        # A/px
voltage=300.0                                     # F20: 200, Krios: 300
gpus="0 1"                                        # List of GPUs to use, delimited by spaces
verbosity=5                                       # Verbosity level
#                                                 #   0: prints nothing
#                                                 #   1: prints brief overall summary
#                                                 #   2: prints warnings 
#                                                 #   3: prints summary for each tomogram 
#                                                 #   4: lists each micrograph 
#                                                 #   5: prints commands for each micrograph
#                                                 #   6: prints summary of reconstruction info
#                                                 #   7: prints full MotionCor/CTFFIND/IMOD/AreTomo info
#                                                 #   8: Shows file unlocking & locking

# MotionCor2
# # motioncor2_exe=/home/rubsak-admin/local/motioncor/MotionCor2
do_dosewt=false                                   # Flag to perform dose-weighting
mcor_patches="0 0"                                # Number of patches in x y, delimited by spaces
reffrm=1                                          # (boolean) Reference frame (0: first, 1: middle)
SplitSum=0                                        # (boolean) Split frames into even & odd half-sets (1: yes)
min_frames=400                                    # Minimum number of EER frames before warning
max_frames=1200                                   # Maximum number of EER frames before warning

# CTFFIND
# # ctffind4_bin=/home/rubsak-admin/local/ctffind/4.1.14/bin
ctf_slots=2                                       #!? Maximum number of CTFFIND4 processes to run concurrently
cs=2.7                                            # F20: 2.0, Krios: 2.7
ac=0.07                                           # 300.0 amplitude contrast: 0.07-0.1 for cryo data, 0.14-0.2 for neg.stain data
boxSz=512                                         # Box size
resL=30.0                                         # Low resolution limit for CTF fitting (Angstrom)
resH=9.0                                          # High resolution limit for CTF fitting (Angstrom)
defL=30000.0                                      # Minimal defocus value to consider during fitting (Angstrom)
defH=70000.0                                      # Maximal defocus value to consider during fitting (Angstrom)
dStep=500.0                                       # Defocus step
dAst=100.0                                        # Astigmatism restraint

# JANNI
do_janni=false                                    # Run Topaz denoise
# # janni_exe=janni_denoise.py                        # JANNI executable
# # janni_model=/home/rubsak-admin/local/janni/gmodel_janni_20190703.h5
# # janni_env=janni_cpu                               # JANNI conda environment
janni_overlap=24                                  # Overlap between patches, pixels
janni_batch=4                                     # Number of patches predicted in parallel

# TOPAZ
do_topaz=false                                    # Run Topaz denoise
# # topaz_exe=/home/rubsak-admin/local/miniconda3/4.10.3/envs/topaz/bin/topaz
# # topaz_env=topaz                                   # Topaz conda environment
topaz_patch=2048                                  # Patch size
topaz_time=5m                                     # Maximum duration, Topaz sometimes hangs

# DoseDiscriminator
dosefit_min=0.1                                   # Minimum dose rate allowed, as a fraction of maximum dose rate
dosefit_resid=0.1                                 # Maximum residual during dose-fitting, as a fraction of maximum dose rate
dosefit_verbose=6                                 # Verbosity level for dose-fitting log file (0..8)

# IMOD
# # imod_bin=/usr/local/IMOD/bin                      # IMOD directory
do_etomo=false                                    # Run IMOD reconstruction
batch_directive=batchDirective.adoc               # IMOD batchruntomo directive file
imod_slots=2                                      # Maximum number of IMOD processes to run concurrently

# Ruotnocon contour removal
do_ruotnocon=false                                # Remove bad contours
rnc_sd=3.0                                        # Contours with residuals greater than this multiple of sigma will be removed

# AreTomo parameters
# # aretomo_exe=/home/rubsak-admin/local/aretomo/1.2.5/AreTomo_1.2.5_Cuda112_08-01-2022
bin_factor=8                                      # Binning factor
vol_zdim=1600                                     # z-dimension for volume
rec_zdim=1000                                     # z-dimension for 3D reconstruction
tilt_axis=86.0                                    # Estimate for tilt-axis direction
dark_tol=0.7                                      # Tolerance for dark images
tilt_cor=1                                        # (boolean) Tilt-correct (1: yes, 0: no)
bp_method=1                                       # Reconstruction method (1: weighted backprojection, 0: SART)
flip_vol=1                                        # (boolean) Flip coordinates axes (1: yes, 0: no)
transfile=1                                       # (boolean) Generate IMOD XF files
are_patches="0 0"                                 # Number of patches in x & y (slows down alignment)
are_time=30m                                      # Maximum duration, AreTomo sometimes hangs

#################### Outputs ###################

cmd_file=commands.txt                              # Output commands file (in ${outdir})
set_file=settings.txt                              # Output settings file (in ${outdir})
log_dir=Logs                                       # Log file directory
rawdir=1-EER                                       # Directory where raw EER files will go
micdir=2-MotionCor2                                # MotionCor directory
mc2_logs=Logs                                      # Directory for MotionCor log files, relative to $MICDIR
ctfdir=3-CTFFIND4                                  # CTFFIND directory
denoisedir=4-Denoise                               # Denoised micrograph directory
recdir=5-Tomo                                      # Reconstruction directory
imgdir=Images                                      # Image directory
thumbdir=Thumbnails                                # Central sections of tomograms
dose_imgdir=DoseFit                                # Dose fitting plot directory
contour_imgdir=Contours                            # Contour removal plot directory
temp_dir=tmp                                       # Temporary files

# Log files (in ${log_dir})
main_log=snartomo.txt                              # Main log file
file_log=files.txt                                 # Events for individual files will be here
mc2_out=motioncor2.txt                             # MotionCor2 log file
ctf_log=ctffind4.txt                               # CTFFIND4 log file
rec_log=recon.txt                                  # Reconstruction log file
gpu_log=log-gpu.txt                                # Log of GPU-memory usage
gpu_plotfile=plot-gpu.gnu                          # Gnuplot script for GPU usage
mem_log=log-mem.txt                                # Log of system-memory usage
mem_plot=plot-mem.gnu                              # Gnuplot script for RAM usage
power_log=log-power.txt                            # Log of system-memory usage
power_plotfile=plot-power.gnu                      # Gnuplot script for RAM usage
heat_log=log-heat.txt                              # Log of system-memory usage
heat_plot=plot-heat.gnu                            # Gnuplot script for RAM usage
warn_log=warnings.txt                              # Warnings log
debug_log=debug.txt                                # Diagnostics log

# Temporary files (in $temp_dir)
init_eers=list-eer-init.txt
mc2_eers=list-eer-mc2.txt
gpu_status=status-gpu.txt
mc2_mics=list-mics-mc2.txt  # this file WON'T be subtracted from as CTFFIND proceeds
ctf_mics=list-mics-ctf.txt  # this file WILL  be subtracted from as CTFFIND proceeds
ctf_list=list-ctfs.txt
mdoc_list=list-mdocs.txt
tomo_list=list-tomos.txt
ctf_status=status-ctf.txt
recon_status=status-recon.txt
eers_done=DONE-eers.txt
mcor_done=DONE-motioncor.txt
ctf_done=DONE-ctffind.txt
rec_done=DONE-recon.txt

################ END BATCH HEADER ################

# Outline (multiline comment)
: '
main
  check_env
  parse_command_line
  check_testing
  create_directories
  prepare_logfiles
  program_info
  print_usage
  shared.check_args
  argparser.print_arguments
  shared.validate_inputs 
    read_mdoc
    check_dir {EER, IMOD, CTFFIND}
    check_exe {MotionCor2, JANNI, Topaz, AreTomo, convert}
    check_mc2
    check_file {gain reference, frame file, IMOD batch directive}
    check_python
  initialize_vars
  shared.check_gain_format 
  targets_init
  eers_init
  read_init {MotionCor2, CTFFIND4}
  resources.gpu_plot
  resources.ram_plot
  resources.power_plot
  resources.temperature_plot
  parse_targets
    detect_new_eers
    distribute_motioncor
  distribute_ctffind 
    ctffind_parallel
  compute_tomograms
    dose_discriminator.py
    shared.janni_denoise
    shared.topaz_denoise
    shared.imod_restack
    shared.wrapper_aretomo
    shared.wrapper_etomo
    shared.ruotnocon_wrapper
  shared.backup_file {eers_done, mcor_done, ctf_done, rec_done}
'

function parse_command_line() {
###############################################################################
#   Function:
#     Parses command line
#   
#   Passed arguments:
#     ${@} : command-line arguments
#   
#   Global variables:
#     OPTION_SEP : (from argumentparser_dynamic.sh) hopefully-unique separator for variable fields
#     original_vars : non-associative array, before cleaning
#     var_sequence : associative array, maintaining the order of the variables
#     commandline_args : command-line arguments, may be modified
#     vars : final options array
#     verbose : shortened copy of vars[verbosity]
#   
###############################################################################
  
  add_section "REQUIRED SETTINGS" "These files/directories are required."
  add_argument "target_files" "" "PACE target files (more than one -> must be enclosed in quotes)" "ANY"
  add_argument "gain_file" "" "Input gain file" "ANY"
  
  add_section "GLOBAL SETTINGS" "These settings affect multiple steps."
  add_argument "eer_dir" "${input_dir}" "Input EER directory" "DIR"
  add_argument "frame_file" "${frame_file}" "Input MotionCor2 frame file" "ANY"
  add_argument "live" "false" "Flag to detect new files on-the-fly" "BOOL"
  add_argument "last_tilt" "${LAST_TILT}" "Last (not highest) tilt angle in tilt series (required in live mode)" "FLOAT"
  add_argument "tilt_tolerance" "${tilt_tolerance}" "Angle difference of last tilt +/- this value will signal end of series" "FLOAT"
  add_argument "apix" "${apix}" "Pixel size, A/px" "FLOAT"
  add_argument "outdir" "${outdir}" "Output directory" "ANY"
  add_argument "verbosity" "${verbosity}" "Verbosity level (0..8)" "INT"
  add_argument "testing" "false" "Testing flag" "BOOL"
  add_argument "slow" "false" "Flag to simulate delays between files during testing" "BOOL"
  add_argument "debug" "false" "Flag for debugging" "BOOL"
  add_argument "overwrite" "false" "Flag to overwrite pre-existing output directory" "BOOL"
  add_argument "max_minutes" "${max_minutes}" "Maximum run time, minutes" "INT"
  add_argument "wait" "${search_interval}" "Interval to check for files and resources, seconds" "INT"
  add_argument "kv" "${voltage}" "Voltage, kV" "FLOAT"
  add_argument "gpus" "${gpus}" "GPUs to use (surrounding quotes & space-delimited if more than one)" "ANY"
  add_argument "no_redo3d" "false" "Flag to NOT overwrite pre-existing 3D reconstructions" "BOOL"
  add_argument "denoise_gpu" "${DENOISE_GPU}" "Flag to denoise using GPUs" "BOOL"

  # MotionCor2
  add_section "MOTIONCOR2 SETTINGS" "Settings for motion-correction."
  add_argument "motioncor_exe" "${MOTIONCOR2_EXE}" "MotionCor2 executable" "ANY"
  add_argument "do_dosewt" "${do_dosewt}" "Flag to perform dose-weighting" "BOOL"
  add_argument "mcor_patches" "${mcor_patches}" "Number of patches in x y, surrounding quotes & delimited by spaces" "ANY"
  add_argument "do_outstack" "false" "Flag to write aligned stacks" "BOOL"
  add_argument "do_splitsum" "false" "Flag to split frames into even & odd half-sets" "BOOL"
  add_argument "split_sum" "${SplitSum}" "(DEPRECATED) Split frames into even & odd half-sets (0: no, 1: yes)" "INT"
  add_argument "reffrm" "${reffrm}" "Reference frame (0: first, 1: middle)" "INT"
  add_argument "min_frames" "${min_frames}" "Minimum number of EER frames before warning" "INT"
  add_argument "max_frames" "${max_frames}" "Maximum number of EER frames before warning" "INT"

  # CTFFIND
  add_section "CTFFIND4 SETTINGS" "Settings for CTF estimation."
  add_argument "ctffind_dir" "${CTFFIND4_BIN}" "CTFFIND executable directory" "ANY"
  add_argument "ctf_slots" "${ctf_slots}" "Maximum number of CTFFIND4 processes to run concurrently" "INT"
  add_argument "cs" "${cs}" "Spherical aberration constant (F20: 2.0, Krios: 2.7)" "FLOAT"
  add_argument "ac" "${ac}" "Amplitude contrast (0.07-0.1 for cryo data, 0.14-0.2 for neg.stain data)" "FLOAT"
  add_argument "box" "${boxSz}" "Tile size for power-spectrum calculation" "INT"
  add_argument "res_lo" "${resL}" "Low-resolution limit for CTF fitting, Angstroms" "FLOAT"
  add_argument "res_hi" "${resH}" "High-resolution limit for CTF fitting, Angstroms" "FLOAT"
  add_argument "df_lo" "${defL}" "Minimum defocus value to consider during fitting, Angstroms" "FLOAT"
  add_argument "df_hi" "${defH}" "Maximum defocus value to consider during fitting, Angstroms" "FLOAT"
  add_argument "df_step" "${dStep}" "Defocus search step during fitting, Angstroms" "FLOAT"
  add_argument "ast_step" "${dAst}" "Astigmatism search step during fitting, Angstroms" "FLOAT"

  # JANNI
  add_section "JANNI SETTINGS" "Settings for JANNI denoise."
  add_argument "do_janni" "${do_janni}" "Denoise micrographs using JANNI" "BOOL"
#   add_argument "janni_env" "${JANNI_ENV}" "JANNI conda environment" "ANY"
#   add_argument "janni_exe" "${janni_exe}" "JANNI executable" "ANY"
#   add_argument "janni_model" "${JANNI_MODEL}" "JANNI general model" "ANY"
  add_argument "janni_batch" "${janni_batch}" "Number of patches predicted in parallel" "INT"
  add_argument "janni_overlap" "${janni_overlap}" "Overlap between patches, pixels" "INT"

  # TOPAZ
  add_section "TOPAZ SETTINGS" "Settings for Topaz denoise."
  add_argument "do_topaz" "${do_topaz}" "Denoise micrographs using Topaz" "BOOL"
# #   add_argument "topaz_exe" "${topaz_exe}" "Topaz executable" "ANY"
  add_argument "topaz_patch" "${topaz_patch}" "Patch size for Topaz denoising" "INT"
  add_argument "topaz_env" "${TOPAZ_ENV}" "Topaz conda environment" "ANY"

  # DoseDiscriminator
  add_section "DOSEDISCRIMINATOR SETTINGS" "Settings for dose-fitting."
  add_argument "dosefit_min" "${dosefit_min}" "Minimum dose rate allowed, as a fraction of maximum dose rate" "FLOAT"
  add_argument "dosefit_resid" "${dosefit_resid}" "Maximum residual during dose-fitting, as a fraction of maximum dose rate" "FLOAT"
  add_argument "dosefit_verbose" "${dosefit_verbose}" "Verbosity level for dose-fitting log file (0..8)" "ANY"

  # IMOD
  add_section "IMOD SETTINGS" "Settings for IMOD: restacking and optional eTomo reconstruction."
  add_argument "imod_dir" "${IMOD_BIN}" "IMOD executable directory" "ANY"
  add_argument "do_etomo" "${do_etomo}" "Compute reconstruction using IMOD" "BOOL"
  add_argument "batch_directive" "${batch_directive}" "IMOD eTomo batch directive file" "ANY"
  add_argument "imod_slots" "${imod_slots}" "Maximum number of IMOD reconstructions to run concurrently" "INT"
  
  # Ruotnocon contour removal
  add_section "RUOTNOCON SETTINGS" "Settings for contour removal."
  add_argument "do_ruotnocon" "${do_ruotnocon}" "Remove contours based on residual" "BOOL"
  add_argument "ruotnocon_sd" "${rnc_sd}" "Contours with residuals greater than this multiple of sigma will be removed" "FLOAT"

  # AreTomo parameters
  add_section "ARETOMO SETTINGS" "Reconstruction will be computed either with AreTomo (default) or IMOD."
  add_argument "aretomo_exe" "${ARETOMO_EXE}" "AreTomo executable" "ANY"
  add_argument "bin" "${bin_factor}" "Binning factor for reconstruction" "INT"
  add_argument "vol_zdim" "${vol_zdim}" "z-dimension for volume" "INT"
  add_argument "rec_zdim" "${rec_zdim}" "z-dimension for 3D reconstruction" "INT"
  add_argument "tilt_axis" "${tilt_axis}" "Estimate for tilt-axis direction, degrees" "FLOAT"
  add_argument "dark_tol" "${dark_tol}" "Tolerance for dark images (0.0-1.0)" "FLOAT"
  add_argument "tilt_cor" "${tilt_cor}" "Tilt-correction flag (1: yes, 0: no)" "INT"
  add_argument "bp_method" "${bp_method}" "Reconstruction method (1: weighted backprojection, 0: SART)" "INT"
  add_argument "flip_vol" "${flip_vol}" "Flag to flip coordinates axes (1: yes, 0: no)" "INT"
  add_argument "transfile" "${transfile}" "Flag to generate IMOD XF files (1: yes, 0: no)" "INT"
  add_argument "are_patches" "${are_patches}" "Number of patches in x & y (surrounding quotes & delimited by spaces)" "ANY"
  add_argument "are_time" "${are_time}" "Maximum duration (AreTomo sometimes hangs)" "ANY"

  dynamic_parser "${@}"
#   print_vars
#   printf "'%s'\n" "${ARGS[@]}" ; exit
  
  # We're going to use this variable a lot
  verbose="${vars[verbosity]}"
}

function main() {
###############################################################################
#   Passed arguments:
#     ${@} : command-line arguments
#   
###############################################################################
  
  # BASH arrays can't be returned, so declare them here
  declare -A original_vars
  declare -a var_sequence
  declare -A vars
  
  do_pace=true
  check_env
  parse_command_line "${@}"
  
  check_testing
  
  # Need to create directories first to save log files
  create_directories "${@}"
  prepare_logfiles
  
  print2log "program_info" "1+" "${main_log}"
  print2log "print_usage" "1+" "${main_log}"
  print2log "check_args 0" "0+" "${main_log}"
  print2log "print_arguments" "7+" "${set_file}"
  
  validate_inputs "${main_log}"
  target_array=$(ls ${vars[target_files]} | sort -n 2> /dev/null)
  
  check_gain_format "${main_log}"
  
  # Loop through targets files
  for current_target in ${target_array} ; do
    initialize_vars
    declare -a mdoc_array=()  # needs to be initialized here
    
    # Easier to dump the current target file into "vars"
    vars[target_file]="${current_target}"
  
    if [[ "${vars[last_tilt]}" != "${LAST_TILT}" ]] ; then
      vprint "\n$(date +"$time_format"): Looking for files in target file '${vars[target_file]}' until a tilt angle of ${vars[last_tilt]} is reached, for up to ${vars[max_minutes]} minutes\n" "1+" "${main_log} =${file_log}"
    else
      vprint "\n$(date +"$time_format"): Looking for files in target file '${vars[target_file]}' for up to ${vars[max_minutes]} minutes\n" "1+" "${main_log} =${file_log}"
    fi
      
    # Parse PACE targets file
    targets_init
    
    # Read initial EERS
    eers_init
    last_old_angle=$eer_angle  # need when detecting new EERs
    cp "${mc2_eers}" "${init_eers}"
    
    # Read pre-existing MotionCor files
    read_init "${mc2_eers}" "${mc2_mics}" "eer_to_mic" "EER"        "MotionCor2" "micrographs"
    cp "${mc2_mics}" "${ctf_mics}"  # make copy for CTFFIND
    
    # Read pre-existing CTFFIND files
    read_init "${ctf_mics}" "${ctf_list}" "mic_to_ctf" "MotionCor2" "CTFFIND4"   "CTFs"
    
    # If fast testing, run in series
    if [[ "${do_parallel}" == false ]] ; then
      parse_targets
      distribute_ctffind
      compute_tomograms
    else
      # Kill subprocesses if main process is killed
      trap 'kill -9 %1' 2
      
      # Prepare resource plots
      gpu_plot "${max_seconds}" "${vars[wait]}" "${gpu_log}" "${gpu_plotfile}" "${rec_done}" &
      ram_plot "${max_seconds}" "${vars[wait]}" "used free available" "${mem_log}" "${mem_plot}" "${rec_done}" &
      power_plot "${max_seconds}" "${vars[wait]}" "${power_log}" "${power_plotfile}" "${rec_done}" &
      temperature_plot "${max_seconds}" "${vars[wait]}" "${heat_log}" "${heat_plot}" "${rec_done}" &
      
      # Do real work
      parse_targets &
      distribute_ctffind &  
      compute_tomograms &
      wait
      
      # Clean up
      backup_file "$eers_done" "0"
      backup_file "$mcor_done" "0"
      backup_file "$ctf_done" "0"
      backup_file "$rec_done" "0"
      rm $eers_done $mcor_done $ctf_done $rec_done 2> /dev/null
    fi
  done
  # End targets loop
  
  elapsed_min=$((${SECONDS}/60))
  elapsed_sec=$((${SECONDS}%60))
  printf -v date_string "$(date +"$time_format"): Exiting after ${elapsed_min}m%02ds" "${elapsed_sec}"
  vprint "\n${date_string}" "1+" "${main_log} =${file_log}"
  vprint "" "1+"
}

function check_env() {
###############################################################################
#   Functions:
#     Checks whether environmental variable SNARTOMO_DIR is set
#     Sources shared functions from central SNARTomo directory
#     
#   Global variables:
#     do_pace
#     
###############################################################################

  if [[ "${SNARTOMO_DIR}" == "" ]]; then
    echo -e "\nERROR!! Environmental variable 'SNARTOMO_DIR' undefined!"
    echo      "  Set variable with: export SNARTOMO_DIR=<path_to_snartomo_files>"
    echo -e   "  Exiting...\n"
    exit
  else
    source "${SNARTOMO_DIR}/${shared_libs}"
    source "${SNARTOMO_DIR}/argumentparser_dynamic.sh"
    
    if [[ "${do_pace}" == true ]]; then
      source "${SNARTOMO_DIR}/gpu_resources.bash"
    fi
  fi
}

function prepare_logfiles() {
###############################################################################
#   Function:
#     Define paths for log and temp files
#     Needs to happen after command line is parsed
#   
#   Global variables:
#     vars
#     log_dir
#     temp_dir
#     main_log
#     set_file
#     file_log
#     mc2_out
#     ctf_log
#     rec_log
#     gpu_log
#     gpu_plotfile
#     mem_log
#     mem_plot
#     power_log
#     power_plotfile
#     heat_log
#     heat_plot
#     mc2_eers
#     gpu_status
#     mc2_mics
#     ctf_mics
#     ctf_list
#     mdoc_list
#     tomo_list
#     ctf_status
#     recon_status
#     eers_done
#     mcor_done
#     ctf_done
#     rec_done
#     time_format
#     
###############################################################################
  
  main_log=${vars[outdir]}/${log_dir}/${main_log}
  set_file=${vars[outdir]}/${log_dir}/${set_file}
  file_log=${vars[outdir]}/${log_dir}/${file_log}
  mc2_out=${vars[outdir]}/${log_dir}/${mc2_out}
  ctf_log=${vars[outdir]}/${log_dir}/${ctf_log}
  rec_log=${vars[outdir]}/${log_dir}/${rec_log}
  gpu_log=${vars[outdir]}/${log_dir}/${gpu_log}
  gpu_plotfile=${vars[outdir]}/${log_dir}/${gpu_plotfile}
  mem_log=${vars[outdir]}/${log_dir}/${mem_log}
  mem_plot=${vars[outdir]}/${log_dir}/${mem_plot}
  power_log=${vars[outdir]}/${log_dir}/${power_log}
  power_plotfile=${vars[outdir]}/${log_dir}/${power_plotfile}
  heat_log=${vars[outdir]}/${log_dir}/${heat_log}
  heat_plot=${vars[outdir]}/${log_dir}/${heat_plot}
  warn_log=${vars[outdir]}/${log_dir}/${warn_log}
  debug_log=${vars[outdir]}/${log_dir}/${debug_log}
  mc2_eers=${vars[outdir]}/${temp_dir}/${mc2_eers}
  init_eers=${vars[outdir]}/${temp_dir}/${init_eers}
  gpu_status=${vars[outdir]}/${temp_dir}/${gpu_status}
  mc2_mics=${vars[outdir]}/${temp_dir}/${mc2_mics}
  ctf_mics=${vars[outdir]}/${temp_dir}/${ctf_mics}
  ctf_list=${vars[outdir]}/${temp_dir}/${ctf_list}
  ctf_status=${vars[outdir]}/${temp_dir}/${ctf_status}
  mdoc_list=${vars[outdir]}/${temp_dir}/${mdoc_list}
  tomo_list=${vars[outdir]}/${temp_dir}/${tomo_list}
  recon_status=${vars[outdir]}/${temp_dir}/${recon_status}
  eers_done=${vars[outdir]}/${temp_dir}/${eers_done}
  mcor_done=${vars[outdir]}/${temp_dir}/${mcor_done}
  ctf_done=${vars[outdir]}/${temp_dir}/${ctf_done}
  rec_done=${vars[outdir]}/${temp_dir}/${rec_done}
  
  time_format='%Y-%m-%d %T'

  if [[ ! -f "${file_log}" ]]; then
    vprint "$(date +"$time_format"): Starting SNARTomoPACE" "0+" "=${file_log}"
  else
    vprint "\n$(date +"$time_format"): Continuing SNARTomoPACE" "0+" "=${file_log}"
  fi
}

function print2log() {
###############################################################################
#   Function:
#     Prints to log file and optionally to screen
#   
#   Positional variables:
#     1) command
#     2) verbosity threshold (adapted from vprint)
#          + greather than or equal to
#          - less than or equal to
#          = equal to
#     3) output log file
#     
###############################################################################
  
  local cmd=$1
  local threshold=$2
  local outlog=$3
  local do_print=false
  
  # Strip last character
  local lastchar=${threshold: -1}
  threshold=${threshold%?}
  # (Adapted from https://stackoverflow.com/a/27658717/3361621)
  
  if [[ "${lastchar}" == "+" ]]; then
    if [[ "$verbose" -ge "${threshold}" ]]; then
      do_print=true
    fi
  elif [[ "${lastchar}" == "-" ]]; then
    if [[ "$verbose" -le "${threshold}" ]]; then
      do_print=true
    fi
  elif [[ "${lastchar}" == "=" ]]; then
    if [[ "$verbose" -eq "${threshold}" ]]; then
      do_print=true
    fi
  else
    # Simply print if no or unknown second argument
    do_print=true
  fi
  
  if [[ "${do_print}" == true ]]; then
    $cmd | tee -a "${outlog}"
    local status_code=("${PIPESTATUS[0]}")
    # (Save exit code after piping to tee: https://stackoverflow.com/a/6871917)
  else
    $cmd >> "${outlog}"
    local status_code=$?
  fi
  
  # If an error was returned, then exit
  if [[ "${status_code}" != 0 ]] ; then
    # If output wasn't printed before, then print it now
    if [[ "${do_print}" == false ]]; then
      $cmd
    fi
    exit
  fi
  
#   echo "status_code: ${status_code}"
  
  return $status_code
}

function initialize_vars() {
###############################################################################
#   Function:
#     Initializes data structures
#   
#   Global variables:
#     mcorr_array
#     denoise_array
#     angle_array
#     time_format
#     max_seconds
#     cor_ext
#     eer_counter
#
###############################################################################
  
  declare -A mcorr_array=()
  declare -A denoise_array=()
  declare -A angle_array=()
# #   declare -a mdoc_array=()  # needs to be declared in calling function for some reason
  
#   tomo_counter=0
#   kill_all_humans=false
  
  max_seconds=$(echo "${vars[max_minutes]}"*60 | bc)
  cor_ext="_mic.mrc"
  eer_counter=0
}

function targets_init() {
###############################################################################
#   Function:
#     Initialize parsing of targets file
#     
#   Global variables:
#     eer_array (OUTPUT)
#     mc2_eers
#     vars
#     temp_dir
#   
###############################################################################
  
  # Initialize
  declare -a eer_array
  rm ${mc2_eers} 2> /dev/null
  touch ${mc2_eers}
  
  # Initialize MDOC list
  while read -r target_line ; do
    # Replace CRLFs
    no_crlfs=$(echo ${target_line} | sed 's/\r//')
    
    # Cut at '=' ('xargs' removes whitespace)
    local mdoc_file="$(dirname ${vars[target_file]})/$(echo $no_crlfs | cut -d'=' -f 2 | xargs).mdoc"
    mdoc_array+=(${mdoc_file})
    
    # Save previous version of MDOC file
    local old_mdoc=$(get_backup_name "${mdoc_file}")
    
    rm "${old_mdoc}" 2> /dev/null
    touch "${old_mdoc}"
  done <<< $(grep "^tsfile" "${vars[target_file]}")
  # TODO: May need to look for new tilt series later too
  
  # Write it out so that the reconstruction step can read it
  declare -p mdoc_array > ${mdoc_list}
}

function get_backup_name() {
###############################################################################
#   Function:
#     Sets name of backup file
#     
#   Global variables:
#     vars
#     temp_dir
#     
#   Parameters:
#     1: filename
#   
#   Returns:
#     Backup filename
#   
###############################################################################
  
  local current_file=$1
  
  echo "${vars[outdir]}/${temp_dir}/$(basename ${current_file}).old"
}

function eers_init() {
###############################################################################
#   Function:
#     Generates initial list of EERs 
#   
#   Calls functions:
#     get_backup_name
#     get_new_entries
#     get_eer_from_mdoc
#     vprint
#     
#   Global variables:
#     vars
#     mdoc_array
#     mc2_eers
#     file_log
#     eer_counter
#     eer_angle: OUTPUT, need later
#     
###############################################################################

  declare -a eer_array
  
  # Set range for last tilt angle ( $((expression)) works only for integers)
  if [[ "${vars[last_tilt]}" != "${LAST_TILT}" ]] ; then
    local min_tilt=$(echo ${vars[last_tilt]} - ${vars[tilt_tolerance]} | bc)
    local max_tilt=$(echo ${vars[last_tilt]} + ${vars[tilt_tolerance]} | bc)
  fi
  
  # Loop through tilt series
  for mdoc_idx in "${!mdoc_array[@]}" ; do
    local mdoc_file="${mdoc_array[${mdoc_idx}]}"
    
    # Get backup filename (needs to be consistent with targets_init)
    local old_mdoc=$(get_backup_name "${mdoc_file}")
    
    # Find number after last underscore
    series_num="$(echo ${mdoc_file} | rev | cut -d'_' -f 1 | rev | sed 's/[^0-9]*//g' | sed 's/^0*//')"
    
    # Read new-angles list as array (https://stackoverflow.com/questions/13823706/capture-multiline-output-as-array-in-bash)
    mapfile -t new_angles < <(get_new_entries "${old_mdoc}" "${mdoc_file}" "false" | grep "TiltAngle" )
    
    # Read new-EER list as array 
    new_eers=$(get_new_entries "${old_mdoc}" "${mdoc_file}" "true" | grep "SubFramePath" )
    if [[ "${new_eers}" != "" ]]; then
      new_idx=0
      
      while read -r eer_line ; do
        local current_eer=$(get_eer_from_mdoc "${eer_line}")
        
        # Greedy search after last space, and remove CRLF terminator
        eer_angle="$(echo ${new_angles[${new_idx}]##* } | tr -d '\r')"
        
        # Sometimes angle is blank, and we need it for the termination signal
        if [[ "${eer_angle}" == "" ]]; then
          echo "ERROR!! eer_angle is blank"
          exit
        fi
        
        let "new_idx++"
        let "eer_counter++"
        
        # Sanity check: look for duplicates
        if [[ ! " ${eer_array[*]} " =~ " ${current_eer} " ]]; then
          # Make sure that EER exists
          eer_array+=("${current_eer}")
#           if [[ -f "${vars[eer_dir]}/${current_eer}" ]]; then
#             # Append to cumulative EER list
#           else
#             echo -e "\n'${vars[eer_dir]}/${current_eer}'\n"
#             vprint "WARNING! EER file '${vars[eer_dir]}/${current_eer}' found in '${mdoc_file}' doesn't exist" "2+" "${main_log} =${warn_log}"
#           fi
        else
          echo "ERROR!! FOUND DUPLICATE: ${eer_line}"
          exit
        fi
        
        # Check if last angle reached
        if [[ "${vars[last_tilt]}" != "${LAST_TILT}" ]] ; then
          if [ $(echo "(${eer_angle} > $min_tilt) && (${eer_angle} < $max_tilt)" | bc -l) -eq 1 ]; then
            # If last tilt series, print results
            if [[ "$(( $mdoc_idx + 1 ))" -eq "${#mdoc_array[@]}" ]]; then
              vprint "$(date +"$time_format"): Found last EER in last tilt series (#${series_num}): angle: ${eer_angle}" "1+" "${main_log}"
            fi
            
            # Sanity check: Are there still more EERs in this tilt series?
            local more_angles=$(( ${#new_angles[@]} -  $new_idx))
            if [[ "$more_angles" -gt 0 ]]; then
              vprint "$(date +"$time_format"): WARNING! In '${mdoc_file}', there are $more_angles more angle(s) beyond ${vars[last_tilt]} degrees" "2+" "${main_log} =${warn_log}"
            fi
            
            # Stop checking this tilt series
            break
          fi
          # End reached-angle IF-THEN
        else
          if [[ "${vars[live]}" == true ]] ; then
            echo -e "ERROR!! Unknown state! --live='${vars[live]}' --last_tilt='${vars[last_tilt]}'\n"
            exit
          fi
        fi
        # End checking-last IF-THEN
            
        vprint "$(date +"$time_format"): Found EER in tilt series #${series_num}, MDOC '$(basename $mdoc_file)': ${eer_array[-1]}, angle: ${eer_angle}, remaining EERs: ${#eer_array[@]}" "0+" "=${file_log}"
        
        if [[ "$verbose" -ge 1 ]]; then
          echo -ne "Accumulated ${eer_counter} pre-existing EERs\r"
        fi
        
      done <<< "${new_eers}"
      # End new-entry loop
      
    # If no EERs found, set angle to dummy value so that while loop isn't broken before all tilt series have been generated
    else
      eer_angle="-99.9"
    fi
    # End new-EERs IF-THEN
  done
  # End tilt-series loop
        
  # Update list on disk
  printf '%s\n' "${eer_array[@]}" > ${mc2_eers}
  
  # Clear array, but don't undeclare it
  eer_array=()
      
  # While loop will finish either when last image has been collected or when time limit reached
  vprint "\n$(date +"$time_format"): Found initial ${eer_counter} EERs from targets file '${vars[target_file]}', last angle ${eer_angle}" "1+" "${main_log}"
}

function get_new_entries() {
###############################################################################
#   Function:
#     Get differences between 2 files and update old file
#   
#   Positional arguments:
#     1) new file
#     2) old file
#     3) (boolean) flag to update old file (default=true)
#     
###############################################################################

  local old=$1
  local new=$2
  local do_update=$3
  
  # Get differences (from https://stackoverflow.com/a/15384969/3361621)
  diff --unchanged-group-format='' "${new}" "${old}" | uniq
  # (Sometimes there are duplicates, so am trying uniq)
  
  # May not want to update if we want to run it multiple times in a row
  if [[ "${do_update}" == true ]]; then
    cp "${new}" "${old}"
  fi
}

function get_eer_from_mdoc() {
###############################################################################
#   Function:
#     Gets EER filename from line in MDOC file
#     
#   Passed arguments:
#     1) line from MDOC file
#     
###############################################################################
  
  local eer_line=$1
  
  # Convert CRLF terminator
  local eer_unix="$(echo $eer_line | tr -d '\r')"
  
  # Cut after the last forward- or backslash
  echo "${eer_unix##*[/\\]}"
}

function parse_targets() {
###############################################################################
#   Function:
#     Parse targets file
#     
#   Calls functions:
#     detect_new_eers
#     distribute_motioncor
#     vprint
#     get_backup_name
#     
#   Global variables:
#     vars
#     do_parallel
#     main_log
#   
###############################################################################
  
  # If fast testing, run in series
  if [[ "${do_parallel}" == false ]] ; then
    detect_new_eers
    distribute_motioncor
  else
    detect_new_eers &
    distribute_motioncor &
    wait
  fi
  
  vprint "$(date +"$time_format"): Cleaning up EER temp files..." "1+" "${main_log}"
  for mdoc_file in "${mdoc_array[@]}" ; do
    local old_mdoc=$(get_backup_name "${mdoc_file}")
    rm "${old_mdoc}"
  done
}

function detect_new_eers() {
###############################################################################
#   Function:
#     Generates list of EERs from growing MDOC files
#   
#   Calls functions:
#     get_backup_name
#     get_new_entries
#     get_eer_from_mdoc
#     vprint
#     
#   Global variables:
#     vars
#     max_seconds
#     mdoc_array
#     mc2_eers
#     init_eers
#     main_log
#     eer_counter
#     do_parallel
#     last_old_angle
#     eers_done
#     
###############################################################################

  # Make sure EERs-complete file doesn't exist (It should have been cleaned in main, but...)
  rm $eers_done 2> /dev/null
  
  if [[ "${vars[live]}" == true ]] ; then
    # Set range for last tilt angle ( $((expression)) works only for integers)
    local min_tilt=$(echo ${vars[last_tilt]} - ${vars[tilt_tolerance]} | bc)
    local max_tilt=$(echo ${vars[last_tilt]} + ${vars[tilt_tolerance]} | bc)
    
    vprint "" "1+" "${main_log}"
    
    local start_time=$SECONDS
    while (( $(( $SECONDS - $start_time )) < $max_seconds )) ; do
      # Loop through tilt series
      for mdoc_file in "${mdoc_array[@]}" ; do
        local old_mdoc=$(get_backup_name "${mdoc_file}")
        
        # Find number after last underscore
        series_num="$(echo ${mdoc_file} | rev | cut -d'_' -f 1 | rev | sed 's/[^0-9]*//g' | sed 's/^0*//')"
        
        # Read new-angles list as array (https://stackoverflow.com/questions/13823706/capture-multiline-output-as-array-in-bash)
        mapfile -t new_angles < <(get_new_entries "${old_mdoc}" "${mdoc_file}" "false" | grep "TiltAngle" )
        
        # Read new-EER list as array 
        new_eers=$(get_new_entries "${old_mdoc}" "${mdoc_file}" "true" | grep "SubFramePath" )
        if [[ "${new_eers}" != "" ]]; then
          new_idx=0
          
          # Read EER list from disk (only need when continuing)
          readarray -t eer_array < "${mc2_eers}"
          
          while read -r eer_line ; do
            local current_eer=$(get_eer_from_mdoc "${eer_line}")
            
            # Sanity check: look for duplicates
            if [[ ! " ${eer_array[*]} " =~ " ${current_eer} " ]]; then
              # Make sure that EER exists
              eer_array+=("${current_eer}")
#               if [[ -e "${vars[eer_dir]}/${current_eer}" ]]; then
#                 # Append to cumulative EER list
#               else
#                 vprint "WARNING! EER file '${vars[eer_dir]}/${current_eer}' found in '${mdoc_file}' doesn't exist" "2+" "${main_log} =${warn_log}"
#               fi
            else
              echo "ERROR!! FOUND DUPLICATE: ${eer_line}"
              exit
            fi
            
            # Greedy search after last space, and remove CRLF terminator
            eer_angle="$(echo ${new_angles[${new_idx}]##* } | tr -d '\r')"
            
            # Sometimes angle is blank, and we need it for the termination signal
            if [[ "${eer_angle}" == "" ]]; then
              echo "ERROR!! eer_angle is blank!"
              exit
            fi
            
            vprint "$(date +"$time_format"): Found EER in tilt series #${series_num}, MDOC '$(basename mdoc_file)': ${eer_array[-1]}, angle: ${eer_angle}, remaining EERs: ${#eer_array[@]}" "0+" "=${file_log}"
            
            let "new_idx++"
            let "eer_counter++"
            
            if [[ "$verbose" -ge 1 ]]; then
              echo -ne "Accumulated ${eer_counter} EERS\r"
            fi
            
          done <<< "${new_eers}"
          # End new-entry loop
          
          # Make sure no one else is modiying the EER list (only need when continuing)
          if [[ "${do_parallel}" == true ]] ; then
            file_lock "${mc2_eers}" "3" "${FUNCNAME[0]}"
            local eer_lock=${lock_file}
          
            # Update list on disk
            printf '%s\n' "${eer_array[@]}" > ${mc2_eers}
            
            # Remove lock file
            rm ${eer_lock} 2> /dev/null
          else
            # Update list on disk
            printf '%s\n' "${eer_array[@]}" > ${mc2_eers}
          fi
          
          # Clear array, but don't undeclare it
          eer_array=()
          
        # If no EERs found, set angle to dummy value so that while loop isn't broken before all tilt series have been generated
        else
          # If last tilt series, use last tilt angle from initial scan
          if [[ "${mdoc_file}" == "${mdoc_array[-1]}" ]] ; then
            eer_angle=${last_old_angle}
          else
            eer_angle="-99.9"
          fi
          # End last-series IF-THEN
        fi
        # End new-EERs IF-THEN
        
  #       vprint "t=$SECONDS, mdoc_file ${mdoc_file}, eer_angle ${eer_angle}"
      done
      # End tilt-series loop
      
      # Check if last angle reached
      if [ $(echo "(${eer_angle} > $min_tilt) && (${eer_angle} < $max_tilt)" | bc -l) -eq 1 ]; then
        vprint "$(date +"$time_format"): Found last EER in last tilt series (#${series_num}): angle: ${eer_angle}" "1+" "${main_log}"
        break
  # 
  #       # TESTING
  #       else
  #         echo "Continuing: series_num: ${series_num}, eer_angle: '${eer_angle}'"
      fi

      sleep "${vars[wait]}"
    done
    # End WHILE loop
  fi
  # End live IF-THEN
  
  # While loop will finish either when last image has been collected or when time limit reached
  vprint "$(date +"$time_format"): Found ${eer_counter} EERs in total from targets file '${vars[target_file]}'" "1+" "${main_log}"
  if [[ "${do_parallel}" == false ]] ; then
    vprint "" "1+" "${main_log}"
  fi
  
  echo "${eer_counter}" > "${eers_done}"
  
  # Combine inital & new EERs
  cat ${mc2_eers} >> ${init_eers}
  
  # Remove duplicates
  awk '!seen[$0]++' ${init_eers} > ${init_eers}-tmp
  mv ${init_eers}-tmp ${init_eers}
}

function distribute_motioncor() {
###############################################################################
#   Function:
#     Distribute MotionCor processes to GPUs in parallel
#   
#   Calls functions:
#     file_lock
#     motioncor_parallel
#     monitor_ram
#   
#   Global variables:
#     vars
#     gpu_list
#     ctf_mics
#     do_parallel
#     mc2_out
#     gpu_status
#     cor_ext
#     mc2_eers
#     lock_file
#     mcor_done
#     
###############################################################################

  # When various tasks finished, these flags will be set to the number of EERs
  local eers_found=""
  
  # Make sure MotionCor-complete file doesn't exist (It should have been cleaned in main, but...)
  rm $mcor_done 2> /dev/null
  
  # Read GPU list as array
  declare -A gpu_array
  IFS=' ' read -r -a gpu_list <<< "${vars[gpus]}"

  # Initialize GPU states
  for gpu_idx in "${!gpu_list[@]}" ; do
    gpu_array[${gpu_list[${gpu_idx}]}]="FREE"
  done
  declare -p gpu_array > ${gpu_status}
  
  # Read pre-existing CTFFIND outputs as array
  readarray -t mic_array < "${mc2_mics}"
  
  local num_mics=$(grep -cve '^\s*$' ${mc2_mics})
  local counter=0
  local found=false

  # This array will contain in-progress micrographs (easier to delete from associative array)
  declare -A new_mics
  
  local start_time=$SECONDS
# #     while (( $(echo "$SECONDS < $max_seconds" | bc) )) ; do
  while (( $(( $SECONDS - $start_time )) < $max_seconds )) ; do
    # Read GPU state
    source ${gpu_status}
    
    # Loop through GPUs
    for gpu_num in "${!gpu_array[@]}" ; do
      # Check if GPU is free
      if [[ "${gpu_array[${gpu_num}]}" == "FREE" ]]; then
        # Lock EER list
        if [[ "${do_parallel}" == true ]]; then
          file_lock "${mc2_eers}" "3" "${FUNCNAME[0]}"
          local eer_lock=${lock_file}
        fi
        
        # Get EER list
        readarray -t eer_array < "${mc2_eers}"
        num_eers=${#eer_array[@]}
        
        # If there are EERs, get first one, remove from array, update list, and write list
        if (( "${num_eers}" > 0 )); then
          local current_eer=${eer_array[0]}
          unset eer_array[0]
          
          # Re-index array (doesn't remove empty entries)
          eer_array=("${eer_array[@]}")
          printf '%s\n' "${eer_array[@]}" > ${mc2_eers}
  
          if [[ "${do_parallel}" == true ]]; then
            # Remove lock file
            rm ${eer_lock} 2> /dev/null
          fi
          
          # Make sure string isn't empty
          if [[ "${current_eer}" != "" ]]; then
            # TODO: print that EER was found?
            
            # Check whether output already exists 
            local cor_mic="$(eer_to_mic ${current_eer})"
            
            # If no pre-existing output
            if [[ ! -e $cor_mic ]]; then
              # Sanity check that EER exists
              if [[ -e "${vars[eer_dir]}/${current_eer}" ]]; then
                local computed_anew=true
                
                # Lock GPU list
                if [[ "${do_parallel}" == true ]]; then
                  file_lock "${gpu_status}" "4" "${FUNCNAME[0]}"
                  local gpu_lock=${lock_file}
                  source ${gpu_status}
            
                  # Update GPU status
                  gpu_array[${gpu_num}]="MOTIONCORR"
                  declare -p gpu_array > ${gpu_status}
                  rm ${gpu_lock} 2> /dev/null
                fi
                
                # Add to in-progress array (easier to delete from associative array)
                new_mics[${cor_mic}]="$(to_tempname ${cor_mic})"
                
                let "counter++"
                
                motioncor_parallel "${vars[eer_dir]}/${current_eer}" "${gpu_num}" "${#eer_array[@]}" &
                
                # Monitor RAM
                if [[ "${vars[testing]}" == false ]]; then
                  monitor_ram
                fi
                
              else
                vprint "WARNING! EER file "${vars[eer_dir]}/${current_eer}" doesn't exist, EER list may be corrupted" "2+" "${main_log} =${warn_log}"
              fi
            
            # If pre-exising output
            else
              sleep 0.2
              rm ${gpu_lock} 2> /dev/null
              local computed_anew=false
              
              # If not overwriting, no big deal if output already exists
              if [[ "${vars[overwrite]}" == false ]]; then
                vprint "$(date +"$time_format"): MotionCor2 output $cor_mic already exists" "0+" "=${file_log}"
              
              else
                # If overwriting, something weird is happening if output already exists
                vprint "$(date +"$time_format"): ERROR!! MotionCor2 output $cor_mic already exists!" "0+" "${main_log} ${file_log}"
                
                # Save EER list for debugging
                if [[ ! -e "${mc2_eers}.bak" ]]; then
                  cp -av "${mc2_eers}" "${mc2_eers}.bak"
                fi
                exit
              fi
              # End overwriting IF-THEN
            fi
            # End pre-existing output IF-THEN
            
#           # If EER filename empty
#           else
#             rm ${gpu_lock} 2> /dev/null
          fi
          # End empty-string IF-THEN
          
        # If zero EERs
        else
          if [[ "${do_parallel}" == true ]]; then
            # Remove lock file
            rm ${eer_lock} 2> /dev/null
          fi
          
#           vprint "$(date +"$time_format"): Waiting for MotionCor output" "1+" "${main_log}"
        fi
        # End non-zero EERs IF-THEN
#           
#       else
#         echo "$SECONDS, gpu_array[${gpu_num}]: ${gpu_array[${gpu_num}]}"
      fi
      # End free-GPU IF-THEN
    done
    # End GPU loop
    
    # Check if subprocess is finished
    for mic_key in "${!new_mics[@]}" ; do
      local temp_mic="${new_mics[${mic_key}]}"
      
      if [ -e "${temp_mic}" ]; then
        # Remove from in-progress array
        unset new_mics[$mic_key]
        
        # Remove temp file
        rm "${temp_mic}"
        
        # Add to in-core cumulative array
        mic_array+=("${mic_key}")
        
#         if [[ "${do_parallel}" == false ]] ; then
#           sleep 0.1
#         fi
    
        # Get number of micrographs
        local num_mics="${#mic_array[@]}"

        if [[ "$verbose" -ge 1 ]]; then
          echo -ne "Accumulated\t\t${num_mics} micrographs\r"
        fi
        
        # Append to list
        if [[ "${do_parallel}" == true ]]; then
          file_lock "${ctf_mics}" "10" "${FUNCNAME[0]}"
          local mic_lock=${lock_file}
        fi
        
        echo "${mic_key}" >> "${ctf_mics}"  # TODO: Sanity check?
          
        if [[ "${do_parallel}" == true ]]; then
          rm ${mic_lock} 2> /dev/null
        fi
      fi
    done
    # End subprocess loop
    
    # If we're running in parallel and if we just generated a new motion-corrected micrograph, then wait
    if [[ "${do_parallel}" == true ]] && [[ "${computed_anew}" == true ]] ; then
#       echo "SLEEP -- do parallel: ${do_parallel}, computed anew: ${computed_anew} (CTRL-c to exit)"
      sleep "${vars[wait]}"
# #     else
# #       sleep 0.5
#     else
#       echo "NOT SLEEPING -- do parallel: ${do_parallel}, computed anew: ${computed_anew}"
    fi
    
    if [[ -f "${eers_done}" ]]; then
      # Read number of EERs (once)
      if [[ "${eers_found}" == "" ]]; then
        local eers_found=$(cat ${eers_done})
# #         echo -e "eers_found : $eers_found\n"
      else
        local num_mics="${#mic_array[@]}"  # shouldn't need to recount
        
        if [[ "${eers_found}" -eq "${num_mics}" ]]; then
          vprint "$(date +"$time_format"): EER detection complete, found ${eers_found} EERs, waiting for MotionCor2..." "1+" "${main_log}"
          
          # TESTING
          backup_file "${ctf_mics}.test" '0'
          printf "'%s'\n" "${mic_array[@]}" > "${ctf_mics}.test"
          
          break
        fi
      fi
      # End ongoing-detection IF-THEN
    fi
    # End file-exists IF-THEN
  done
  # End WHILE loop
  
  # While loop will finish either when last image has been processed or when time limit reached
  check_completion "${num_mics}" "${eers_found}" "MotionCor2" "${mcor_done}" "$start_time"
# #   vprint "\n$(date +"$time_format"): MotionCor2 completed on ${num_mics} files" "1+" "${main_log}"
# #   echo "${num_mics}" > "${mcor_done}"
  
  # TESTING
  echo -e "$(ls --full-time ${mcor_done})    \t$(cat ${mcor_done})" >> "${debug_log}"
}

function motioncor_parallel() {
###############################################################################
#   Function:
#     Wrapper for MotionCor2
#     Default behavior is to NOT overwrite pre-existing outputs.
#   
#   Positional variables:
#     1) EER filename
#     2) GPU number
#     
#   Calls functions:
#     run_motioncor
#     check_frames
#     file_lock
#     resource_liberate
#   
#   Global variables:
#     fn (OUTPUT)
#     gpu_num (OUTPUT)
#     time_format
#     vars
#     cor_mic
#     mc2_out
#     verbose
#     ali_out
#     ali_err
#     mc2_wait (OUTPUT)
#     main_log
#     mc2_eers
#     do_parallel
#     ctf_mics
#     gpu_status
#     
###############################################################################
  
  fn=$1
  gpu_num=$2
  
  local remaining_eers=$3
  local mc2_pid=-1
  
  # Filenames
  stem_eer=$(basename ${fn} | rev | cut -d. -f2- | rev)
  cor_mic="${vars[outdir]}/${micdir}/${stem_eer}${cor_ext}"
  ali_out="${vars[outdir]}/${micdir}/${mc2_logs}/${stem_eer}_mic.out"
  ali_err="${vars[outdir]}/${micdir}/${mc2_logs}/${stem_eer}_mic.err"
  
  vprint "$(date +"$time_format"): Starting MotionCor2 on '${fn}' on GPU #${gpu_num}, EERs remaining: ${remaining_eers}" "0+" "=${file_log}"
  
  # Print command
  vprint "$(run_motioncor ${fn} $gpu_num)" "5+" "=${mc2_out}" 

  if [[ "${vars[testing]}" == false ]]; then
    # Check number of frames
    check_frames "${mc2_out}"
    
    local mc2_cmd=$(run_motioncor ${fn} $gpu_num)
    
    if [[ "$verbose" -le 6 ]]; then
      # Suppress warning: "TIFFReadDirectory: Warning, Unknown field with tag 65001 (0xfde9) encountered."
      ${mc2_cmd} 2> ${ali_err} 1> $ali_out
      mc2_pid=$!
    
    # Full output
    else
      # If I use a "|", then I can't store the PID (https://stackoverflow.com/a/59011390)
      ${mc2_cmd} 2>&1 > >(tee $ali_out)
      mc2_pid=$!
    fi
    
    # Append to log file 
    cat $ali_out >> ${mc2_out}
    # (TODO: May need to lock. Processes might try to write at the same time.)
      
  # If testing
  else
    vprint "" "5+" "=${mc2_out}" 

    # Delay in slow mode
    if [[ "${vars[slow]}" == true ]]; then
      sleep $(( (RANDOM % 4) + 2 ))
#     else
#       sleep 0.1
    fi
    
    touch "${cor_mic}"
  fi
  # End testing IF-THEN
  
  # Make sure process is actually gone (TODO: Move to function)
  if [[ "$mc2_pid" -gt 0 ]]; then
    mc2_wait=0
    local wait_incr=0.25
    
    # Check process ID
    pid_wait "$mc2_pid" "$wait_incr"
    
    # Check child processes
    if [[ "$(ps --ppid $mc2_pid -o "%p" --noheaders | wc -w)" -gt 0 ]]; then
      while read -r child_process ; do
        pid_wait "$child_process" "$wait_incr"
      done <<< $(ps --ppid $mc2_pid -o "%p" --noheaders)
    fi
    
    vprint "WAITED $mc2_wait SEC TOTAL FOR PID $mc2_pid\n" "8+" "=${mc2_out}"
  fi
  
  # Make sure output exists
  if [[ ! -f "$cor_mic" ]]; then
    vprint "\n$(date +"$time_format"): WARNING! MotionCor2 output '$cor_mic' does not exist" "2+" "${main_log} =${warn_log}"
    vprint "             Command line was:" "2+" "${main_log}"
    vprint "             ${mc2_cmd}" "2+" "${main_log}"
    vprint "             Re-adding to queue\n" "2+" "${main_log}"
    
    # Add to EER list (TODO: function)
    
    # Lock EER list
    if [[ "${do_parallel}" == true ]]; then
      file_lock "${mc2_eers}" "2" "${FUNCNAME[0]}"
      local eer_lock=${lock_file}
    fi
    
    # Read EER list
    readarray -t eer_array < "${mc2_eers}"
    
    # Append to array
    eer_array+=( $(basename ${fn}) )
    
    # Update EER list & unlock
    printf '%s\n' "${eer_array[@]}" > ${mc2_eers}
    
    if [[ "${do_parallel}" == true ]]; then
      rm ${eer_lock} 2> /dev/null
    fi
    
  # Output exists
  else
    # Add to micrograph list for own self (TODO: function)
    if [[ "${do_parallel}" == true ]]; then
      file_lock "${mc2_mics}" "4" "${FUNCNAME[0]}"
      local mic_lock=${lock_file}
    fi
    
    readarray -t mic_array < "${mc2_mics}"
    mic_array+=(${cor_mic})
    printf '%s\n' "${mic_array[@]}" > ${mc2_mics}
    
    if [[ "${do_parallel}" == true ]]; then
      rm ${mic_lock} 2> /dev/null
    fi
    
    if [[ "${vars[testing]}" == false ]]; then
      # Write information to log file
      vprint "\n    Finished MotionCor2 on micrograph $fn" "0+" "=${mc2_out}"
      
      local mesg=$(grep 'Total time' $ali_out)
      if [[ "$mc2_pid" -gt 0 ]]; then
        local wait_float=$(printf "%.2f" "$mc2_wait")
        mesg="$mesg, waited $wait_float sec for PID $mc2_pid to clear"
      fi
      vprint   "    ${mesg}\n" "0+" "=${mc2_out}"
    fi
  fi
  # End output-exists IF-THEN
  
  # Update GPU status
  if [[ "${do_parallel}" == true ]]; then
    resource_liberate "${gpu_status}" "${gpu_num}" "2" "1"
  fi
  
  vprint "$(date +"$time_format"): Finished MotionCor2 on '${fn}' on GPU #${gpu_num}" "0+" "=${file_log}"
  
  # Create temporary file to indicate to watcher that we're finished
  touch "$(to_tempname ${cor_mic})"
}

function pid_wait() {
###############################################################################
#   Function:
#     Wait for process to disappear
#   
#   Positional variables:
#     1) process ID
#     2) wait interval
#   
#   Global variables:
#     mc2_wait
#   
###############################################################################
  
  local mc2_pid=$1
  local wait_incr=$2
  
  while ps -p $mc2_pid > /dev/null ; do 
    # Increment wait time
    mc2_wait=$(echo $mc2_wait + $wait_incr | bc)
    
    # Wait
    sleep $wait_incr
  done

  vprint "Waited $mc2_wait sec for PID $mc2_pid" "8+" "=${mc2_out}"
}

function file_lock() {
###############################################################################
#   Function:
#     Creates lock file
#     Waits for existing file to disappear
#   
#   Positional variables:
#     1) lock file
#     2) wait time, seconds (integer)
#     3) display message
#   
#   Calls function:
#     vprint
#
#   Global variables:
#     temp_dir
#     lock_file (OUTPUT): need to remove it outside of this function
#     main_log
#     
###############################################################################

  file2lock="$(basename $1)"
  local time_limit=$2
  local id_msg=$3
  lock_file="${vars[outdir]}/${temp_dir}/LOCK-${file2lock}"
  
  if [[ -f ${lock_file} ]] ; then
    
    end=$(($SECONDS+${time_limit}))
    while [[ "$SECONDS" -lt "$end" ]]; do
      if [[ -f ${lock_file} ]]; then
        sleep 1
        
        mesg="$(date +"$time_format"): Waiting to unlock '${file2lock}' for ${time_limit} sec"
        if [[ "${id_msg}" != "" ]]; then
          mesg+=", ${id_msg}"
        fi
        vprint "${mesg}" "8+" "${main_log}"
  #       echo "$SECONDS"
      else
        break
      fi
    done
    # End WHILE loop
#   else
#     if [[ "${id_msg}" != "" ]] ; then
#       echo "$SECONDS: LOCK DOESN'T EXIST ${id_msg}"
#     fi
  fi
  
  if ! [[ -f ${lock_file} ]] ; then
    echo "${id_msg} $(date +"$time_format")" > "${lock_file}"
    
    mesg="$(date +"$time_format"): Locked '${file2lock}'"
    if [[ "${id_msg}" != "" ]]; then
      mesg+=" by ${id_msg}"
    fi
    vprint "${mesg}" "9+" "${main_log}"
  else
    local locked_by=$(cat ${lock_file} 2> /dev/null)
    # https://stackoverflow.com/a/18086548
    eval "$( cat ${lock_file} \
        2> >(lockederr=$(cat); typeset -p lockederr) \
         > >(locked_by=$(cat); typeset -p locked_by) )"
    
    if [[ "${locked_by}" == "" ]]; then
      locked_by="${FUNCNAME[1]} time unknown"
    fi
    
    vprint "$(date +"$time_format"): WARNING! Time limit reached, file_lock ${file2lock} attempted by ${id_msg}, locked by ${locked_by}" "0+" "${warn_log}"
    
    if [[ "${locked_by}" == "" ]]; then
      vprint "$(date +"$time_format"): WARNING! Error reading ${file2lock} attempted by ${id_msg}" "0+" "${warn_log}"
      vprint "$(date +"$time_format"):          stderr: '${lockederr}'" "0+" "${warn_log}"
    fi
  fi
}

function resource_liberate() {
###############################################################################
#   Function:
#     Creates lock file
#     Waits for existing file to disappear
#     Dones nothing if not in parallel mode
#   
#   Example: 'resource_liberate "${gpu_num}" "${gpu_status}" "2" "1" "${gpu_array[@]}"'
#     Equivalent to (analogous for CPU array):
#       file_lock "${gpu_status}" "2" "motioncor_parallel"
#       local gpu_lock=${lock_file}
#       source ${gpu_status}
#       gpu_array[${gpu_num}]="FREE"
#       declare -p gpu_array > ${gpu_status}
#       sleep 1
#       rm ${gpu_lock} 2> /dev/null
#
#   Positional variables:
#     1) status_file: must be gpu_status or ctf_status
#     2) slot_number
#     3) lock_time
#     4) sleep_time
#   
#   Calls function:
#     file_lock
#     
#   Global variables:
#     gpu_status
#     ctf_status
#     recon_status
#   
###############################################################################
  
  local status_file=$1
  local slot_number=$2
  local lock_time=$3
  local sleep_time=$4
  
  # Lock file for a given time, and pass calling function's name (for debug mode)
  file_lock "${status_file}" "${lock_time}" "${FUNCNAME[0]}"
  
  # "lock_file" is a global variable in file_lock
  local lock_file=${lock_file}
  
  # Read array from status file
  source ${status_file}
  
  # Set GPU/CPU array
  if [[ "${status_file}" == "${gpu_status}" ]] ; then
    gpu_array[${slot_number}]="FREE"
    declare -p gpu_array > ${status_file}
  elif [[ "${status_file}" == "${ctf_status}" ]] ; then
    cpu_array[${slot_number}]="FREE"
    declare -p cpu_array > ${status_file}
  elif [[ "${status_file}" == "${recon_status}" ]] ; then
    slot_array[${slot_number}]="FREE"
    declare -p slot_array > ${status_file}
  else
    echo "ERROR!! Don't know status file '${status_file}'!"
    exit
  fi
  # End GPU-vs-CPU IF-THEN
  
  # Delay
  sleep "${sleep_time}"

  # Remove lock file
  rm ${lock_file} 2> /dev/null
    
  unset resource_array
}

function monitor_ram() {
###############################################################################
#   Function:
#     Monitors system memory
#   
#   Calls functions:
#     ram_resources (from gpu_resources.bash)
#   
###############################################################################
  
  local ram_avail=$(ram_resources | grep available | cut -d '=' -f 2)
  
  if [[ "$ram_avail" -lt 20 ]]; then
    vprint    "  ERROR!! Available RAM down to ${ram_avail}GB! Exiting..." "0+" "${main_log} =${warn_log}"
    exit
  fi
  if [[ "$ram_avail" -lt 40 ]]; then
    vprint    "  WARNING! Available RAM down to ${ram_avail}GB. Continuing..." "0+" "${main_log} =${warn_log}"
  fi
}

function read_init() {
###############################################################################
#   Function:
#     Looks for generic pre-existing outputs
#   
#   Parameters:
#     1. Input list
#     2. List of pre-existing output files
#     3. Function to convert input filename to output filename
#     4. Input program name
#     5. Output program name
#     6. Output file type (brief, plural)
#     
#   Calls functions:
#     vprint
#     
#   Global variables:
#     vars
#     
###############################################################################

  input_list=$1
  output_list=$2
  io_function=$3
  input_program=$4
  output_program=$5
  output_type=$6
  
  local new_counter=0
  local old_counter=0
  declare -a new_input_array
  declare -a output_array
  
  vprint "" "1+" "${main_log}"
    
  # Read micrograph list
  readarray -t old_input_array < "${input_list}"
  num_input_files=${#old_input_array[@]}
  
  # Empty array will be of length 1 with empty string
  if [[ "${num_input_files}" -eq 1 ]] && [[ "${old_input_array[0]}" -eq "" ]]; then
    num_input_files=0
  fi
  
  # If there are pre-existing outputs, remove corresponding input from array
  if (( "${num_input_files}" > 0 )); then
    # Loop through inputs
    for current_input in "${old_input_array[@]}"; do 
      # Remove first element from array (unset simply sets element to null)
      old_input_array=("${old_input_array[@]:1}")
      
      # Make sure string isn't empty
      if [[ "${current_input}" != "" ]]; then
        # Check whether output already exists
        local current_output="$(${io_function} ${current_input})"
        
        # If pre-exising output
        if [[ -e $current_output ]]; then
          let "old_counter++"
          
          # Add to micrograph list
          output_array+=("$current_output")
          
          # If not overwriting, no big deal if output already exists
          if [[ "${vars[overwrite]}" == false ]]; then
            vprint "$(date +"$time_format"): ${output_program} output $current_output already exists" "0+" "=${file_log}"
          
          else
            # If overwriting, something weird is happening if output already exists
            vprint "$(date +"$time_format"): ERROR!! ${output_program} output $current_output already exists!" "0+" "${main_log} ${file_log}"
            
            # Save micrograph list for debugging
            if [[ ! -e "${input_list}.bak" ]]; then
              cp -av "${input_list}" "${input_list}.bak"
            fi
            exit
          fi
          # End overwriting IF-THEN
        
        # Add to list to run MotionCor
        else
          let "new_counter++"
          new_input_array+=("${current_input}")
#           echo "Need to run ${output_program} #${new_counter} ${current_input}"
        fi
        # End pre-existing output IF-THEN
      fi
      # End empty-string IF-THEN
    done
    # End EER loop
  fi
  # End non-zero CTFs IF-THEN

  if [[ "$verbose" -ge 1 ]]; then
    echo -ne "Accumulated ${old_counter} pre-existing ${output_type}\r"
  fi
    
  # Empty arrays write file with blank line, which can cause problems
  if [[ "${#new_input_array[@]}" -ge 1 ]]; then
    printf '%s\n' "${new_input_array[@]}" > ${input_list}
#   else
#     rm "${input_list}" 2> /dev/null
#     touch "${input_list}"
  fi
  
  if [[ "${#output_array[@]}" -ge 1 ]]; then
    printf '%s\n' "${output_array[@]}" > ${output_list}
  else
    rm "${output_list}" 2> /dev/null
    touch "${output_list}"
  fi
  
  vprint "\n$(date +"$time_format"): Found ${old_counter} pre-existing ${output_type} out of ${num_input_files} ${input_program} files" "1+" "${main_log}"
}

function eer_to_mic() {
###############################################################################
#   Function:
#     Generates motion-corrected micrograph filename from EER filename
#   
#   Parameter:
#     1. Input filename
#     
#   Global variables:
#     vars
#     micdir
#     cor_ext
#     
#   Returns:
#     Output filename
#     
###############################################################################

  local current_input=$1
  
  local file_stem=$(basename ${current_input} | rev | cut -d. -f2- | rev)
  echo "${vars[outdir]}/${micdir}/${file_stem}${cor_ext}"
}

function mic_to_ctf() {
###############################################################################
#   Function:
#     Generates CTFFIND MRC filename from motion-corrected micrograph
#   
#   Parameter:
#     1. Input filename
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

function distribute_ctffind() {
###############################################################################
#   Function:
#     Looks for motion-corected micrographs and sends to CTFFIND4
#   
#   Calls functions:
#     ctffind_parallel
#     file_lock
#   
#   Global variables:
#     max_seconds
#     vars
#     ctf_mics
#     ctf_status
#     ctf_list
#     temp_dir
#     mcor_done
#     ctf_done
#     
###############################################################################

  local counter=0
  declare -a mic_array
  
  # Make sure CTF-complete file doesn't exist (It should have been cleaned in main, but...)
  rm $ctf_done 2> /dev/null
  
  # Initial micrograph list
  old_mics=$(get_backup_name "${ctf_mics}")
  
  # Initialize CPU array
  declare -a cpu_array
  for cpu_num in $(seq "${vars[ctf_slots]}") ; do
    cpu_array[${cpu_num}]="FREE"
  done
  declare -p cpu_array > ${ctf_status}
  
  # Read pre-existing CTFFIND outputs as array
  readarray -t ctf_array < "${ctf_list}"

  # This array will contain in-progress CTFs (easier to delete from associative array)
  declare -A new_ctfs
  
  # If CTFs missing, only warn once
  local already_warned=false
  local mics_found=""
  
  # TODO: Split into smaller functions
    local start_time=$SECONDS
    while (( $(( $SECONDS - $start_time )) < $max_seconds )) ; do
    # Check whether MotionCor is finished
    if [[ -f "${mcor_done}" ]]; then
      # Read number of motion-corrected micrographs (once)
      if [[ "${mics_found}" == "" ]]; then
        local mics_found=$(cat ${mcor_done})
        vprint "\n$(date +"$time_format"): MotionCor2 completed on ${mics_found} files, waiting for CTFFIND4...\n" "1+" "${main_log}"
      else
        if [[ "${mics_found}" -eq "${num_ctfs}" ]]; then
          break
        else
          if [[ "${do_parallel}" == true ]] ; then
            
            if (( "$(($num_ctfs + ${#new_ctfs[@]}))" < "${mics_found}" )); then
#               if [[ "${#new_ctfs[@]}" -ge 1 ]]; then
#                 echo "In-progress CTFS:"
#                 printf "  '%s'\n" "${new_ctfs[@]}"
#               fi
              
              if [[ "${already_warned}" == false ]] ; then
                # Only warn once
                already_warned=true
                vprint "\n$(date +"$time_format"): WARNING! $(($mics_found - $num_ctfs)) CTFs missing" "0+" "${main_log} =${warn_log}"
              fi
              
              rescue_ctfs >> ${warn_log}
            fi
            # End missing-CTFs IF-THEN
            
            sleep "${vars[wait]}"
          fi
          # End do-parallel IF-THEN
        fi
        # End correct-number IF-THEN
      fi
      # End non-empty IF-THEN
    fi
    # End file-exists IF-THEN
    
    # Read CPU state
    source ${ctf_status}
    
    # Loop through CPU slots
    for cpu_num in $(seq "${vars[ctf_slots]}") ; do
      # Check if CPU is free
      if [[ "${cpu_array[${cpu_num}]}" == "FREE" ]]; then
        # Lock micrograph list
        if [[ "${do_parallel}" == true ]]; then
          file_lock "${ctf_mics}" "8" "${FUNCNAME[0]}"
          local mic_lock=${lock_file}
        fi
        
        # Get current file list (may contain empty entries)
        readarray -t mic_array < "${ctf_mics}"
        
        # If there are micrographs, get first one, remove from array, update list, and write list
        if (( "${#mic_array[@]}" > 0 )); then
          local current_mic=${mic_array[0]}
          unset mic_array[0]
          
          # Re-index array (doesn't remove empty entries)
          mic_array=("${mic_array[@]}")
          printf '%s\n' "${mic_array[@]}" > ${ctf_mics}
          
          if [[ "${do_parallel}" == true ]]; then
            rm ${mic_lock} 2> /dev/null
          fi
          
          # Make sure string isn't empty
          if [[ "${current_mic}" != "" ]]; then
            vprint "$(date +"$time_format"): Found motion-corrected micrograph: '${current_mic}'" "0+" "=${file_log}"
            
            local ctf_mrc="$(mic_to_ctf ${current_mic})"
            local temp_ctf="$(to_tempname ${ctf_mrc})"
            
            # If no pre-existing output
            if [[ ! -e $ctf_mrc ]]; then
              if [[ "${do_parallel}" == true ]] ; then
                # Lock CPU list (This function isn't running in background, only subroutines.)
                file_lock "${ctf_status}" "4" "${FUNCNAME[0]}"
                local cpu_lock=${lock_file}
                source ${ctf_status}
                
                # Update CPU status
                cpu_array[${cpu_num}]="$(basename ${current_mic})"
                declare -p cpu_array > ${ctf_status}
                rm ${cpu_lock} 2> /dev/null
            
                # Run CTFFIND in background
                ctffind_parallel "${current_mic}" "${cpu_num}" "${ctf_mrc}" &
                sleep "${vars[wait]}"
              else
                # Run CTFFIND in foreground
                ctffind_parallel "${current_mic}" "${cpu_num}" "${ctf_mrc}" 
              fi
            else
              touch "$temp_ctf"
            fi
            # End pre-existing IF-THEN
            
            # Add to in-progress array (easier to delete from associative array)
            new_ctfs[${ctf_mrc}]="$temp_ctf"
            
          # If empty filename
          else
            if [[ "${do_parallel}" == true ]]; then
              rm ${mic_lock} 2> /dev/null
            fi
          fi
          # End non-empty filename IF-THEN
        else
          if [[ "${do_parallel}" == true ]]; then
            rm ${mic_lock} 2> /dev/null
          fi
        fi
        # End non-zero micrographs IF-THEN
#       
#       else
#         # TESTING
#         echo "t=$SECONDS, CPU slot $cpu_num occupied by '${cpu_array[${cpu_num}]}'"
# #         bat "${ctf_status}"
      fi
      # End free-CPU IF-THEN
    done
    # End CPU loop
    
    # Check if subprocess is finished
    for ctf_mrc in "${!new_ctfs[@]}" ; do
      local temp_ctf="${new_ctfs[${ctf_mrc}]}"
      
      if [ -e "${temp_ctf}" ]; then
        # Remove from in-progress array
        unset new_ctfs[$ctf_mrc]
        
        # Remove temp file
        rm "${temp_ctf}"
        
        # Check if array has value
        if [[ ! " ${ctf_array[*]} " =~ " ${ctf_mrc} " ]]; then
          # Add to in-core cumulative array if CTF MRC exists (temp output may exist without MRC output)
          if [[ -f "$ctf_mrc" ]]; then
            ctf_array+=("${ctf_mrc}")
            
            # Append to CTF list
            echo "${ctf_mrc}" >> "${ctf_list}"
          
          # If it doesn't exist, then re-add to queue
          else
            local mic_stem=$(basename ${ctf_mrc%_ctf.mrc})
            local current_mic="${vars[outdir]}/${micdir}/${mic_stem}_mic.mrc"
            vprint "$(date +"$time_format"): Re-adding '$current_mic' to queue" "1+" "=${warn_log}"
            
            if [[ "${do_parallel}" == true ]]; then
              file_lock "${ctf_mics}" "4" "${FUNCNAME[0]}"
              local mic_lock=${lock_file}
            fi
            
            echo "${current_mic}" >> "${ctf_mics}"
            backup_file "${ctf_mics}" "0"
            
            if [[ "${do_parallel}" == true ]]; then
              rm ${mic_lock} 2> /dev/null
            fi
          fi
          # End MRC-exists IF-THEN
#           
#         else
#           vprint "$(date +"$time_format"): WARNING! Already present: '${ctf_mrc}' in ctf_array ${#ctf_array[@]}" "0+" "${main_log} =${warn_log}"
        fi
        # End has-value IF-THEN
      fi
      # End file-exists IF-THEN
    done
    
    # Get number of CTFs
    local num_ctfs="${#ctf_array[@]}"

    if [[ "$verbose" -ge 1 ]]; then
      echo -ne "Accumulated\t\t\t\t\t${num_ctfs} CTFs\r"
    fi
          
#     # In parallel mode, check every N seconds
#     if [[ "${do_parallel}" == true ]] ; then
#       sleep "${vars[wait]}"
# #       echo "t=$SECONDS, ${num_ctfs}"
#     else
#       sleep 0.01
#     fi
    
    # Keep CPU from shooting to 100% if stuck in loop
    sleep 0.01
  done
  # End WHILE loop
  
  # While loop will finish either when last image has been processed or when time limit reached
  check_completion "${num_ctfs}" "${mics_found}" "CTFFIND4" "${ctf_done}" "$start_time"
  
#   # TESTING
#   vprint "\n$(date +"$time_format"):" "0+" "=${debug_log}"
#   echo -e "$(ls --full-time ${ctf_done})    \t$(cat ${ctf_done})" >> "${debug_log}"
}

  function ctffind_parallel() {
  ###############################################################################
  #   Function:
  #     Run CTFFIND4 in parallel
  #     TODO: combine with ctffind_serial
  #   
  #   Positional variables:
  #     1) Micrograph name
  #     2) CPU number
  #     3) Output MRC
  #     
  #   Calls functions:
  #     mic_to_ctf
  #     to_tempname
  #   
  #   Global variables:
  #     vars
  #     time_format
  #     file_log
  #     do_parallel
  #     
  ###############################################################################

    local cor_mic=$1
    local cpu_num=$2
    local ctf_mrc=$3
    
    local stem_eer="$(basename ${current_mic%_mic.mrc})"
    local ctf_out="${vars[outdir]}/${ctfdir}/${stem_eer}_ctf.out"
    local ctf_txt="${vars[outdir]}/${ctfdir}/${stem_eer}_ctf.txt"
    local ctf_summary="${vars[outdir]}/${ctfdir}/SUMMARY_CTF.txt"
    local avg_rot="${vars[outdir]}/${ctfdir}/${stem_eer}_ctf_avrot.txt"
    local warn_msg=''
    
    # Sanity check: Look for existing CTFFIND output
    if [[ ! -e $ctf_mrc ]]; then
      vprint "$(date +"$time_format"): Starting CTFFIND4 on '${current_mic}' on slot #${cpu_num}/${vars[ctf_slots]}" "0+" "=${file_log}"
    
      if [[ "${vars[testing]}" == false ]]; then
        # Print command
        if [[ "$verbose" -ge 5 ]]; then
          run_ctffind4 "false" >> ${ctf_log}
        fi

        if [[ "$verbose" -ge 7 ]]; then
          run_ctffind4 "true" 2>&1 | tee $ctf_out
        else
          run_ctffind4 "true" > $ctf_out 2> /dev/null
        fi

        # Append to log file
        cat $ctf_out >> ${ctf_log}
        
        # Print notable CTF information to screen
        if [[ "$verbose" -eq 6 ]]; then
          echo "" >> ${ctf_log}
          grep "values\|good" $ctf_out | sed 's/^/    /' >> ${ctf_log}
          # (prepends spaces to output)
          echo "" >> ${ctf_log}
        fi
        
        if [[ -f "$avg_rot" ]]; then
          if [[ "$verbose" -ge 5 ]]; then
            echo "    Running: ctffind_plot_results.sh $avg_rot" >> ${ctf_log}
          else
            "${vars[ctffind_dir]}"/ctffind_plot_results.sh $avg_rot 1> /dev/null >> ${ctf_log}
          fi
        else
          warn_msg="$(date +"$time_format"): WARNING! CTFFIND4 output $avg_rot does not exist, re-adding to queue..."
        fi

        # Write last line of CTF text output to summary
        if [[ -f "$ctf_txt" ]]; then
          echo -e "${stem_eer}:    \t$(tail -n 1 $ctf_txt)" >> ${ctf_summary}
        else
          warn_msg="$(date +"$time_format"): WARNING! CTFFIND4 output $ctf_txt does not exist, re-adding to queue..."
        fi
      
      # If testing
      else
        echo "" >> ${ctf_log}
        run_ctffind4 "false" >> ${ctf_log}
      fi
      # End testing IF-THEN
      
      vprint "$(date +"$time_format"): Finished CTFFIND4 on '${current_mic}' on slot #${cpu_num}/${vars[ctf_slots]}" "0+" "=${file_log}"

    # If output already exists
    else
      vprint "$(date +"$time_format"): CTFFIND4 output $ctf_mrc already exists" "0+" "=${file_log}"
    fi
    # End preexisting-file IF-THEN
    
    
    # In testing mode, add a delay
    if [[ "${vars[testing]}" == true ]]; then
      if [[ "${vars[slow]}" == true ]]; then
        sleep $(( (RANDOM % 2) + 3 ))
      fi
      
      touch "${vars[outdir]}/${ctfdir}/${stem_eer}_ctf.mrc"
    fi
        
    # Free CPU
    if [[ "${do_parallel}" == true ]] ; then
      resource_liberate "${ctf_status}" "${cpu_num}" "3" "0"
    fi
    
    # Make sure output exists
    if [[ ! -f "$ctf_mrc" ]]; then
      warn_msg="$(date +"$time_format"): WARNING! CTFFIND4 output '$ctf_mrc' does not exist, re-adding to queue..."
    fi
    
    # Print only one warning message per micrograph
    if [[ "${warn_msg}" != "" ]]; then
      vprint "$warn_msg" "0+" "${main_log} =${warn_log}"
      
      # Don't exit if in serial mode
      if [[ "${do_parallel}" == true ]] ; then
        exit
      fi
    fi
    
    # Create temporary file to indicate to watcher that we're finished
    touch "$(to_tempname ${ctf_mrc})"
  }

  function rescue_ctfs() {
  ###############################################################################
  #   Function:
  #     Rescue unaccounted-for CTFs
  #     
  #   Global variables:
  #     mc2_mics
  #     ctf_list
  #     ctf_mics
  #     ctfdir
  #     vars
  #     time_format
  #     do_parallel
  #     
  #   Calls functions:
  #     vprint
  #     
  ###############################################################################
    
    
    # Remove duplicates and read as array (https://stackoverflow.com/a/13825568/3361621)
    mapfile -t mc2_array < <(awk '!seen[$0]++' ${mc2_mics})
    # printf "'%s'\n" "${mc2_array[@]}"
    # echo "mc2_array '${#mc2_array[@]}'"

    local mic_counter=0

    # Loop through micrographs
    for curr_mic in "${mc2_array[@]}" ; do
      local mic_stem=$(basename ${curr_mic%_mic.mrc})
      local curr_ctf="${vars[outdir]}/${ctfdir}/${mic_stem}_ctf.mrc"
      
      # Check if in CTF list
      if ! grep -Fxq "$curr_ctf" $ctf_list ; then
        let "mic_counter++"
        echo "$(date +"$time_format"): Didn't find '$curr_ctf', re-adding micrograph to queue"
        
        # Safely re-add to micrograph list
        if [[ "${do_parallel}" == true ]]; then
          file_lock "${ctf_mics}" "7" "${FUNCNAME[0]}"
          local mic_lock=${lock_file}
        fi
        
        echo $curr_mic >> $ctf_mics
        
        if [[ "${do_parallel}" == true ]]; then
          rm ${mic_lock} 2> /dev/null
        fi
      fi
    done
    # End micrograph loop
    
# #     echo "$(date +"$time_format"): Found $mic_counter missing CTFs"
  }

function to_tempname() {
###############################################################################
#   Function:
#     Generates temporary filename
#   
#   Parameter:
#     1. Input filename
#     
#   Global variables:
#     vars
#     temp_dir
#     
#   Returns:
#     Output filename
#     
###############################################################################

  local infile=$1
  
  echo "${vars[outdir]}/${temp_dir}/DONE-$(basename ${infile})"
}

function check_completion() {
###############################################################################
#   Function:
#     Checks if to completion or somply ran out of time
#   
#   Positional variables:
#     1) number of actual outputs
#     2) number of expected outputs
#     3) name of program (for echoing purposes)
#     4) file to create with number of outputs
#     5) start time
#   
#   Calls functions:
#     vprint
#   
#   Global variables:
#     main_log
#     warn_log
#     max_seconds
#     time_format
#   
###############################################################################
  
  local num_actual=$1
  local num_expected=$2
  local program_name=$3
  local done_file=$4
  local start_time=$5
  
  if [[ "${num_actual}" -eq "${num_expected}" ]]; then
    vprint "\n$(date +"$time_format"): Completed ${program_name} on ${num_actual}/${num_expected} files" "1+" "${main_log}"
    echo "${num_actual}" > "${done_file}"
  else
# #     echo "DIAGNOSTIC: '$(( $SECONDS - $start_time ))' '$max_seconds'"
    
    # Maybe ran out of time?
    if (( $(( $SECONDS - $start_time )) < $max_seconds )) ; then
      vprint "\n$(date +"$time_format"): ERROR!! Found only ${num_actual} outputs!" "0+" "${main_log} =${warn_log}"
    else
      vprint "\n$(date +"$time_format"): ERROR!! Ran out of time before completing ${program_name}!" "0+" "${main_log} =${warn_log}"
      vprint   "                       Increase parameter '--max_minutes' from current value: ${vars[max_minutes]}" "0+" "${main_log} =${warn_log}"
      vprint   "                       To resume, don't use '--overwrite flag'" "0+" "${main_log} =${warn_log}"
    fi
    
    vprint "                       Exiting ${program_name} for target file '${vars[target_file]}'...\n" "0+" "${main_log} =${warn_log}"
    exit
  fi
}

function compute_tomograms() {
###############################################################################
#   Function:
#     1) Run IMOD's newstack command
#     2) Compute tomographic recontruction with AreTomo or eTomo
#     
#     Default behavior is to OVERWRITE pre-existing outputs.
#   
#   Global variables:
#     mcor_done
#     ctf_done
#     mdoc_list
#     vars
#     main_log
#     recdir
#     imgdir
#     dose_imgdir
#     file_log
#     denoisedir
#     rec_log
#     ctfdir
#     verbose
#     tomo_list
#     
#   Calls functions:
#     vprint
#     get_eer_from_mdoc
#     tomogram_parallel
#   
#   Adapted from SNARTomoClassic
#     
###############################################################################
  
  local mics_found=""
  local num_ctfs=""
  
  # Wait for CTFFIND to finish
  local start_time=$SECONDS
  while (( $(( $SECONDS - $start_time )) < $max_seconds )) ; do
    if [[ -f "${ctf_done}" ]] && [[ -f "${mcor_done}" ]] ; then 
      local mics_found=$(cat ${mcor_done})
      local num_ctfs=$(cat ${ctf_done})
      
      # TESTING
      vprint "\n$(date +"$time_format"):" "0+" "=${debug_log}"
      echo -e "$(ls --full-time ${mcor_done})    \t$(cat ${mcor_done})" >> "${debug_log}"
      echo -e "$(ls --full-time ${ctf_done})    \t$(cat ${ctf_done})" >> "${debug_log}"
      
      if [[ "${mics_found}" != "${num_ctfs}" ]] ; then
        vprint "\n$(date +"$time_format"): WARNING! Micrographs from MotionCor2 (${mics_found}) not equal to from CTFFIND4 (${num_ctfs})" "0+" "${main_log} =${warn_log}"
      fi
      
      break
    fi
    # End IF-THEN for CTFFIND completion
    
    sleep "${vars[wait]}"
  done
  # End while loop
  
  # Read MDOC list from disk (array was created in a background process)
  source ${mdoc_list}
  num_mdocs=${#mdoc_array[@]}
  
  # Sanity check
  if [[ "${mics_found}" == "" ]] || [[ "${num_ctfs}" == "" ]] ; then
    vprint "\n$(date +"$time_format"): ERROR!! MotionCor2 and/or CTFFIND4 did not finish!" "0+" "${main_log} =${warn_log}"
    vprint "                       Exiting reconstruction for target file '${vars[target_file]}'..." "0+" "${main_log} =${warn_log}"
    exit
  else
    vprint "\n$(date +"$time_format"): Finished MotionCor2/CTFFIND4 on $mics_found/$num_ctfs micrographs, computing ${num_mdocs} 3D reconstructions" "1+" "${main_log}"
  fi
  
  if [[ "${vars[do_etomo]}" == true ]]; then
    local slot_list=( $(seq "${vars[imod_slots]}") )
  else
    IFS=' ' read -r -a slot_list <<< "${vars[gpus]}"
  fi
  
  # Initialize slot array
  declare -A slot_array
  for slot_num in $(seq "${slot_list[@]}") ; do
    slot_array[${slot_num}]="FREE"
  done
  declare -p slot_array > ${recon_status}
  
  local mdoc_idx=0
  local rec_counter=0
  local good_counter=0
  local num_tomos=0
  
  # This associative array will contain in-progress CTFs (easier to delete from associative array than indexed array)
  declare -A new_tomos
  declare -a tomo_array
  
  vprint "" "1+" "${main_log}"
  
    local start_time=$SECONDS
    while (( $(( $SECONDS - $start_time )) < $max_seconds )) ; do
    # Read slot state
    source ${recon_status}
    
    # Loop through slots
    for slot_num in $(seq "${slot_list[@]}") ; do
      # Check if slot is free
      if [[ "${slot_array[${slot_num}]}" == "FREE" ]]; then
        # Get MDOC filename
        local mdoc_file="${mdoc_array[${mdoc_idx}]}"
        
        # Remove from in-progress array
        unset mdoc_array[$mdoc_idx]
        
        # Increment MDOC counter
        let "mdoc_idx++"
        
        # Make sure string isn't empty
        if [[ "${mdoc_file}" != "" ]]; then
          if [[ "${do_parallel}" == true ]] ; then
            # Lock slot list (This function isn't running in background, only subroutines.)
            file_lock "${recon_status}" "1" "${FUNCNAME[0]}"
            local cpu_lock=${lock_file}
            source ${recon_status}
            
            # Update slot status
            slot_array[${slot_num}]="$(basename ${mdoc_file})"
            declare -p slot_array > ${recon_status}
            rm ${cpu_lock} 2> /dev/null
          fi

          # Easier to delete from associative array
          new_tomos[${mdoc_file}]="$(to_tempname ${mdoc_file})"
          
          tomogram_parallel "${mdoc_file}" "${slot_num}" &
          
#         else
#           echo "mdoc_file is empty"
        fi
        # End if non-empty IF-THEN
#       
#       else
#         # TESTING
#         echo "t=$SECONDS, slot $slot_num occupied by '${slot_array[${slot_num}]}'"
      fi
      # End free-slot IF-THEN
    done
    # End slot loop
    
    # Check if subprocess is finished
    for mdoc_key in "${!new_tomos[@]}" ; do
      local temp_mdoc="${new_tomos[${mdoc_key}]}"
      
      if [ -e "${temp_mdoc}" ]; then
        # Remove from in-progress array
        unset new_tomos[$mdoc_key]
        
        # Remove temp file
        rm "${temp_mdoc}"
        
        # Add to in-core cumulative array
        tomo_array+=("${mdoc_key}")
        
        # Append to list
        echo "${mdoc_key}" >> "${tomo_list}"
#       else
#         echo "Doesn't exist: '${mdoc_key}' '${temp_mdoc}'"
      fi
    done
    
    # Get number of tomograms
    local num_tomos="${#tomo_array[@]}"

    if [[ "$verbose" -ge 1 ]]; then
      echo -ne "Accumulated ${num_tomos} tomograms\r"
    fi
          
    # In parallel mode, check every N seconds
    if [[ "${do_parallel}" == true ]] ; then
      sleep "${vars[wait]}"
    else
      sleep 0.04
    fi
    
    if [[ $num_tomos -eq $num_mdocs ]] ; then
      vprint "\n$(date +"$time_format"): Finished computing ${num_tomos} 3D reconstructions.\n" "1+" "${main_log}"
      break
    fi
  done
  # End WHILE loop
  
  echo "${#tomo_array[@]}" > "${rec_done}"
  
  if (( $num_tomos < $num_mdocs )) ; then
    vprint "\n$(date +"$time_format"): WARNING! Computed ${num_tomos}/$num_mdocs 3D reconstructions within time limit.\n" "1+" "${main_log} =${warn_log}"
  fi
}

function tomogram_parallel() {
###############################################################################
#   Function:
#     Prepares micrograph lists and compute tomograms
#   
#   Positional variables:
#     1) MDOC file
#     2) slot number
#   
#   Calls functions:
#     resource_liberate
#     wrapper_aretomo
#     wrapper_etomo
#   
#   Global variables:
#     recdir
#     vars
#     verbose
#     imgdir
#     dose_imgdir
#     cor_ext
#     denoisedir
#     ctfdir
#     num_bad_residuals : from ruotnocon_wrapper
#     tomogram_3d : from wrapper functions
#     rec_log
#   
###############################################################################
  
  local mdoc_file=$1
  local slot_num=$2
  
  # MDOC might have dots other than extension
  local tomo_base="$(basename ${mdoc_file%.mrc.mdoc})"
  
  local tomo_dir="${recdir}/${tomo_base}"
  tomo_root="${vars[outdir]}/${tomo_dir}/${tomo_base}"
  local tomo_log="${tomo_root}_snartomo.log"
  
  
  # Make sure MDOC exists
  if [[ ! -e $mdoc_file ]]; then
    vprint "$(date +"$time_format"): WARNING! MDOC file '${mdoc_file}' does not exist. Skipping..." "1+" "${main_log} =${warn_log} =${tomo_log}"
  else
    mcorr_list="${tomo_root}_mcorr.txt"
    denoise_list="${tomo_root}_denoise.txt"
    angles_list="${tomo_root}_newstack.rawtlt"
    local ctf_summary="${vars[outdir]}/${tomo_dir}/SUMMARY_CTF.txt"
    local dose_list="${tomo_root}_dose.txt"
    local dose_plot="${vars[outdir]}/${imgdir}/${dose_imgdir}/${tomo_base}_dose_fit.png"
    local good_angles_file="${tomo_root}_goodangles.txt"
    local dose_log="${tomo_root}_dosefit.log"
    
    declare -a stripped_angle_array=()
    declare -a mcorr_mic_array=()
    declare -a denoise_array=()
    
    if [[ "${vars[do_janni]}" == true ]]; then
      local mic_type="JANNI-denoised micrographs"
    elif [[ "${vars[do_topaz]}" == true ]]; then
      local mic_type="Topaz-denoised micrographs"
    else
      local mic_type="micrographs"
    fi
    
    mkdir -p "${vars[outdir]}/${tomo_dir}"
    touch ${ctf_summary}
    
    # Parse MDOC (awk notation from Tat)
    mapfile -t mdoc_angle_array < <( grep "TiltAngle" "${mdoc_file}" | awk '{print $3}' | sed 's/\r//' )
    mapfile -t eer_array < <( grep "SubFramePath" "${mdoc_file}" | awk '{print $3}' | sed 's/\r//' )
    mapfile -t dose_rate_array < <( grep "DoseRate" "${mdoc_file}" | awk '{print $3}' | sed 's/\r//' )
    # TODO: Sanity check that arrays have same length
    
    # Clean up pre-existing files
    rm ${dose_list} 2> /dev/null
    
    # Loop through angles
    for mdoc_idx in "${!mdoc_angle_array[@]}"; do 
      # Get EER filename
      eer_file=$(echo ${eer_array[${mdoc_idx}]##*[/\\]} )
      
      # Get motion-corrected micrograph name
      local stem_eer=$(echo ${eer_file} | rev | cut -d. -f2- | rev)
      local mc2_mic="${vars[outdir]}/${micdir}/${stem_eer}${cor_ext}"
      
      # Check that motion-corrected micrograph exists
      if [[ -f "$mc2_mic" ]]; then
        printf "%2d  %5.1f  %6.3f\n" "$mdoc_idx" "${mdoc_angle_array[${mdoc_idx}]}" "${dose_rate_array[${mdoc_idx}]}" >> ${dose_list}
        
        stripped_angle_array+=(${mdoc_angle_array[${mdoc_idx}]})
        
        # Append to micrograph lists
        mcorr_mic_array+=($mc2_mic)
        denoise_array+=(${vars[outdir]}/${denoisedir}/${stem_eer}${cor_ext})
        
        # Write CTF summary
        if [[ "${vars[testing]}" == false ]] ; then
          local ctf_txt="${vars[outdir]}/${ctfdir}/${stem_eer}_ctf.txt"
          echo -e "${stem_eer}:    \t$(tail -n 1 $ctf_txt)" >> ${ctf_summary}
        fi
  #       else
  #         echo "WARNING: $mc2_mic doesn't exist"
      fi
    done
    # End angles loop
    
    # TODO: Move to function
    if [[ ! -f "${dose_list}" ]]; then
        vprint "\nWARNING! Dose list '${dose_list}' not found" "0+" "${main_log} =${warn_log}"
        vprint "  Continuing...\n" "0+" "${main_log} =${warn_log}"
    else
      dosefit_cmd="$(echo dose_discriminator.py \
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
      
      if [[ "$error_code" == *"Error"* ]] ; then
        echo -e "\nERROR!!"
        echo -e "${error_code}\n"
        echo -e "Conda environments: initial '$init_conda', current '$CONDA_DEFAULT_ENV'"
        echo -e "  Maybe this is the wrong environment?\n"
        exit
      else
        vprint "$error_code" "1+" "=${tomo_log}"
      fi
      # End error IF-THEN
        
      mapfile -t sorted_keys < $good_angles_file
    fi
    # End dose-list IF-THEN
    
    # Clean up pre-existing files
    rm ${angles_list} ${mcorr_list} ${denoise_list} 2> /dev/null
    
    # Write new IMOD list file (overwrites), starting with number of images
    echo ${#sorted_keys[*]} > $mcorr_list
    if [[ "${vars[do_janni]}" == true ]] || [[ "${vars[do_topaz]}" == true ]] ; then
      echo ${#sorted_keys[*]} > $denoise_list
    fi
    
    # Write sorted micrograph filenames
    for idx in ${sorted_keys[@]} ; do
      echo    "${stripped_angle_array[${idx}]}" >> $angles_list
      echo -e "${mcorr_mic_array[$idx]}\n/" >> $mcorr_list
      if [[ "${vars[do_janni]}" == true ]] || [[ "${vars[do_topaz]}" == true ]]; then
        echo -e "${denoise_array[$idx]}\n/" >> $denoise_list
      fi
    done  
    
    local ts_mics="${#stripped_angle_array[*]}"
    vprint "  Wrote list of ${ts_mics} angles to $angles_list" "2+" "=${tomo_log}"
    vprint "  Wrote list of ${#mcorr_mic_array[*]} images to $mcorr_list" "2+" "=${tomo_log}"
    if [[ "${vars[do_janni]}" == true ]] || [[ "${vars[do_topaz]}" == true ]]; then
      vprint "  Wrote list of ${#denoise_array[*]} images to $denoise_list" "2+" "=${tomo_log}"
    fi
    
    vprint "" "2+" "=${tomo_log}"

    # Clean up
    unset mcorr_mic_array
    unset denoise_array
    unset stripped_angle_array
    
    # Optionally denoise
    if [[ "${vars[do_janni]}" == true ]]; then
      janni_denoise "${tomo_log}"
    elif [[ "${vars[do_topaz]}" == true ]]; then
      topaz_denoise "${tomo_log}"
    fi
      
    imod_restack "${tomo_log}"
    
    vprint "$(date +"$time_format"): Start computing 3D reconstruction from ${mic_type} from MDOC file '${mdoc_file}' on slot #${slot_num}" "1+" "=${file_log} =${tomo_log} =${rec_log}"
    
    if [[ "${vars[do_etomo]}" == false ]]; then
      wrapper_aretomo "${ts_mics}" "${slot_num}" "false" >> "${tomo_log}"
    else
      # If removing bad contours
      if [[ "${vars[do_ruotnocon]}" == true ]]; then
        local fid_file="${vars[outdir]}/${tomo_dir}/${tomo_base}_newstack.fid"
        
        wrapper_etomo "${tomo_base}" "${ts_mics}" "-end 6" "false" >> "${tomo_log}"
        ruotnocon_wrapper "${tomo_dir}" "${tomo_base}" >> "${tomo_log}"
        
        if [[ "${vars[testing]}" == false ]] ; then
          vprint "$(date +"$time_format"): Removed ${num_bad_residuals} contours based on residuals" "1+" "=${tomo_log}"
        fi
        
        wrapper_etomo "${tomo_base}" "${ts_mics}" "-start 6" "false" >> "${tomo_log}"
      else
        wrapper_etomo "${tomo_base}" "${ts_mics}" "false" >> "${tomo_log}"
      fi
    fi
    # End AreTomo-vs-eTomo IF-THEN
    
    # If dose list is missing, tomogram_3d isn't defined until here
    if [[ ! -f "${dose_list}" ]]; then
      # So that calling function doesn't stall
      touch "${tomogram_3d}"
    fi
    
    # Sanity check
    if [[ -f "$tomogram_3d" ]]; then
      vprint "$(date +"$time_format"): Finished computing 3D reconstruction from MDOC file '${mdoc_file}'" "1+" "=${file_log} =${tomo_log}"
      vprint "" "1+" "=${tomo_log}"
    fi
    
    # In testing mode, add a delay
    if [[ "${vars[testing]}" == true ]]; then
      if [[ "${vars[slow]}" == true ]]; then
        sleep $(( (RANDOM % 8) + 3 ))
      fi
      
      touch "${tomogram_3d}"
    fi
        
    # Append log file (need to lock?)
    cat $tomo_log >> ${rec_log}
    
    # Free slot
    if [[ "${do_parallel}" == true ]] ; then
      resource_liberate "${recon_status}" "${slot_num}" "1" "0"
    fi
    
    touch "$(to_tempname ${mdoc_file})"
    
  fi
  # End MDOC-exists IF-THEN
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

########################################################################################

main "$@"
