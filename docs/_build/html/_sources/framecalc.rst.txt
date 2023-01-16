FrameCalc
=========

I have written a script called SNARTomoFrameCalc which generates the frames file. It requires two general pieces of information (along with some other parameters):

  - the electron dose
  - the number of frames

There are a few ways of getting this information, and I tried to allow several paths to get there.

Parameters
----------

**Dose**

The dose can be given either per micrograph (``--dose_per_img``) or the total for the tilt series (``--dose_per_ts``). If the latter, then you need to provide an MDOC file which shows how many micrographs there are per tilt series (``--mdoc_file``).

**Number of frames**

The number of frames can be provided from one of three places:

  - from the command line (``--num_frames``)
  - an MDOC file (``--mdoc_file``)
  - an EER file (``--eer_file``)

**Other**

The other free parameter control how many EER frames to combine into one post-MotionCor frame (``--dose_per_combined``). The default is 0.15 electrons per square Angstrom.

Examples
--------

**Dose per micrograph**

``snartomo-framecalc --dose_per_img 3.24 --mdoc_file TS/lam_ts_001.mrc.mdoc``

**Dose per tilt series**

``snartomo-framecalc --dose_per_ts 133 --mdoc_file TS/lam_ts_001.mrc.mdoc``

**Number of frames provided directly**

``snartomo-framecalc --dose_per_img 3.24 --num_frames 448``

**Number of frames provided by MDOC**

``snartomo-framecalc --dose_per_img 3.24 --mdoc_file TS/lam_ts_001.mrc.mdoc``

**Number of frames provided by EER file**

``snartomo-framecalc --dose_per_img 3.24 --eer_file TS/pace_101_280_-51.0_Apr21.eer``

A command line can be generated with Tianming's web GUI.

Settings
--------

 ========================= ======= ===================== ===================================================================================== 
  Flag                      Type    Default               Description
 ========================= ======= ===================== ===================================================================================== 
  ``--dose_per_img``        FLOAT   -1                    Dose per image, electrons per square Angstrom                                        
  ``--dose_per_ts``         FLOAT   -1                    Dose per tilt series, electrons per square Angstrom (requires MDOC file)             
  ``--mdoc_file``           ANY     None                  MDOC file, required if dose provided per tilt series or if EER example not provided  
  ``--dose_per_combined``   FLOAT   0.15                  Dose per combined MotionCor frame, electrons per square Angstrom                     
  ``--eer_file``            ANY     None                  Example EER file, required if neither MDOC file nor number of frames provided        
  ``--num_frames``          INT     -1                    Number of frames per EER movie                                                       
  ``--frame_file``          ANY     motioncor-frame.txt   Output MotionCor2 frame file                                                         
  ``--verbosity``           INT     2                     Verbosity level (0..3)                                                               
 ========================= ======= ===================== ===================================================================================== 

