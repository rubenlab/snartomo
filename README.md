# snartomo

On-the-fly tomographic reconstruction

## Installation

1. Create conda environment
```
conda create --name snartomo python=3.7 matplotlib scipy --yes
```

2. Edit the snartomo.bashrc with valid paths.

``` bash
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

```

