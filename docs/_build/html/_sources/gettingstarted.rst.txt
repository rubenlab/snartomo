Getting Started
===============

Installation
------------

SNARTomo assumes prior installation of MotionCor2, CTFFIND4, IMOD, and optionally AreTomo, Topaz, and JANNI.

1. Create conda environment

``conda create --name snartomo python=3.7 matplotlib scipy --yes``


2. Copy ``snartomo.bashrc.template`` to ``snartomo.bashrc``, and edit with valid paths. For example:

::

  #!/bin/bash

  # Modified 2022-12-08

  ##### PLEASE DEFINE THE FOLLOWING #####

  export SNARTOMO_ENV="snartomo"                                                                 # SNARTomo conda environment
  export DENOISE_GPU="false"                                                                     # Denoise (Topaz or JANNI) using GPUs
  export MOTIONCOR2_EXE="/home/tapu/local/motioncor2/1.4.5/MotionCor2_1.4.5_Cuda101-10-22-2021"  # MotionCor2 exectuable
  export CTFFIND4_BIN="/home/tapu/local/ctffind/4.1.14/bin"                                      # CTFFIND4 directory (not executable)
  export JANNI_ENV="janni_pb320"                                                                 # JANNI conda environment
  export JANNI_MODEL="/home/tapu/local/janni/gmodel_janni_20190703.h5"                           # JANNI "h5" model file
  export TOPAZ_ENV="topaz"                                                                       # TOPAZ conda environment
  export IMOD_BIN="/usr/local/IMOD/bin"                                                          # IMOD executable directory
  export ARETOMO_EXE="/home/tapu/local/aretomo/1.2.5/AreTomo_1.2.5_Cuda101_08-01-2022"           # AreTomo executable

  ##### YOU SHOULDN'T NEED TO MODIFY ANYTHING BELOW THIS LINE #####

  if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo -e "\nERROR! Script '${BASH_SOURCE[0]}' is being executed!"
    echo -e   "  Please run it with: source ${BASH_SOURCE[0]}\n"
  else
    echo "script ${BASH_SOURCE[0]} is being sourced..."
    conda activate ${SNARTOMO_ENV}

    export SNARTOMO_DIR="$(dirname $BASH_SOURCE)"
    export PATH="$PATH:$SNARTOMO_DIR"

    echo -e "\nAdded '$SNARTOMO_DIR' to PATH\n"
  fi

Inputs
------

Frame file
^^^^^^^^^^

*NEW! (2022-11-28)* -- SNARTomoFrameCalc generates this file, given a few inputs.

The frame file is used by MotionCor2 for dose-weighting. It is a text file containing the following three values, separated by spaces:

  - The number of frames to include
  - The number of EER frames to merge in each motion-corrected frame
  - The dose per EER frame

The first value will probably simply be the total number of frames collected. However, you might limit the number frames to include if, for example, your exposure was too long, and you want to keep only the least radiation-damaged frames.

For the second value, a reasonable rule of thumb is to accumulate 0.15-0.20 electrons per Å :sup:`2`. For example, at a dose of 3e/Å :sup:`2` distributed over 600 frames, the dose per EER frame would be 0.005. To accumulate 0.15e/Å :sup:`2`, you would need to merge 0.15/(3/600) = 30 frames. The line in the frame file would thus be:

:: 
  
  600 30 0.005

In theory, a frames file can have multiple lines, if for example the first N frames were to be handled differently than the next M frames. However, we haven't tested this functionality yet.

Gain file
^^^^^^^^^

The gain file is used to compensate for systematic errors in the camera. 

The gain file can either be in TIFF or MRC format. If it's in TIFF format, SNARTomo will automatically convert it to MRC for use with MotionCor2.
