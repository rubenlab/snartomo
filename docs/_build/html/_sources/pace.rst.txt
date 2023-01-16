SNARTomoPACE
============

PACE is a data-collection scheme developed by Rado Danev and colleagues. Briefly, it uses beam shift to collect multiple tilt series in parallel, which bypasses the rate-limiting step in tomographic data collection: stage movement.

Data collection is much faster, and is organized differently, compared to typical SerialEM data collection. Thus, the rate-limiting steps have been parallelized.

Quick Start
-----------

An example of usage is:

``snartomo-pace --target_files "target_file*.txt" --gain_file gain_reference --frame_file motioncor_frame_file --last_tilt last_tilt_angle --eer_dir frames --outdir output_directory --live``

More detailed usage will be described below.

Requirements
------------

The following requirements are specific to SNARTomoPACE. These are in addition to the requirements of a gain file and a frame file.

**Target files**

A key input for SNARTomoPace is one or more target files, typically with a filename of the 
form ``*_tgts.txt``. SNARTomoPACE expects the tilt-series MDOC files (typically with a filename of the form ``*ts*.mdoc``) to be in the same directory as the target file.

To briefly summarize how SNARTomoPACE works, it reads the target file, and determines the name of the associated tilt-series MDOC files. New EER files are then scanned, in the sequence in which the corresponding tilt-series MDOC file appears in the target file.

SNARTomoPACE, as of 2022-11-18 accepts multiple targets files. If more than one is specified, they must be enclosed in quotes.

**Last angle**

In on-the-fly mode, SNARTomoPACE needs a signal to decide when to start computing the 3D reconstruction. That signal is when the last angle in the last tilt series in the target file is reached.

NOTE1: If you leave out the ``--live`` flag, you don't need this parameter. Instead, SNARTomo will simply search the contents of the MDOC files, assuming that they are complete.

NOTE2: The last angle does not necessarily correspond to the **highest** tilt angle, simply the chronologically **last** tilt angle. Under typical usage, the last tilt angle will generally be the most-negative angle.

NOTE3: It is assumed that every tilt series is collected to the same last angle. If the last angle varies, the program may get stuck while looking for an EER file which will never exist. Instead, run SNARTomoPACE separately for tilt series which are collected to a different last angle.

Getting started
---------------

SNARTomo runs on our on-the-fly server (codenamed "Lorelei"). To log in to the guest account:

``ssh rubsak-guest@10.143.192.4``

SerialEM under our default settings will write data to ``/mnt/f4server/TemScripting/EF-Falcon/``

Most settings have a default value. The following parameters are required:

  * ``--target_files`` -- If more than one target file is specified, surround them in quotes.
  * ``--last_tilt`` -- If you're not running SNARTomoPACE in live mode, this parameter is optional.
  * ``--gain_file``

In principle, you could simply type ``snartomo-pace --target_files "target_files*.txt" --gain_file gain_reference --last_tilt last_tilt_angle`` without any further options specified.  This is not recommended. Instead, I recommend a "dry run", as described below. 

Even better, enter ``snartomo-pace --help`` (or ``snartomo-pace -h``) to see the full list of settings.  
More information about the specific options can be found below.

Dry run
-------

I recommend performing a dry run, with the ``--testing`` option. 

In contrast to SNARTomoClassic, I recommend directing the output to a test directory. The test run creates dummy files, which may confuse the script when you execute a real run.

``snartomo-pace --target_files "target_files*.txt" --gain_file gain_reference --frame_file motioncor_frame_file --last_tilt last_tilt_angle --eer_dir frames --outdir output_directory --testing``

The information written to the screen before SNARTomo starts looking for individual files includes summaries of how to use SNARTomo, and the settings used. Also note the Validation section. If required inputs are missing, they will be noted here. Some sanity checks will be performed here, to make sure your parameters are sensible.

If you are still collecting data, SNARTomo will continue to look for new files, and will not stop on its own. Enter ``ctrl-c`` to exit from a dry run.

Since SNARTomoPACE is parallelized, it produces output faster, and in a wider variety. Only a summary is written to the console terminal, for example, validation, and a summary of detected files. Instead, more detailed information will be written to specialized files in the ``Logs`` output subdirectory. The main log file, ``Logs/snartomo.txt``, will closely resemble the screen output. The MotionCor2 output file, ``Logs/motioncor2.txt``, will contain the detailed screen output of MotionCor2, et cetera. A more complete list of the log files is listed in the ``Outputs section``.

Batch vs. live mode
-------------------

Once you are satisfied with the results of the dry run, remove the ``--testing`` flag. 

The two general ways to process data using SNARTomoPACE are: live (on-the-fly) and batch modes.

**Batch mode**

In batch mode, the last tilt angle is not required.

``snartomo-pace --target_files "target_files*.txt" --gain_file gain_reference --frame_file motioncor_frame_file--eer_dir frames --outdir output_directory``

In batch mode, the MDOC files will be assumed to be complete, and SNARTomoPACE will not continuously look for new EER files.

**Live mode**

In live mode, the ``--live`` flag tells SNARTomoPACE to look for new EER files continuously.  In addition, the ``--last_tilt`` flag tells SNARTomoPACE when to compute the 3D reconstructions.

``snartomo-pace --target_files "target_files*.txt" --gain_file gain_reference --frame_file motioncor_frame_file --last_tilt last_tilt_angle --eer_dir frames --outdir output_directory --live``

**tmux/screen**

In both live and batch modes, there will be text written continuously to the screen, so it may be impractical to continue using that console. You might want to use ``tmux`` to work elsewhere on the on-the-fly machine. If you would like to exit the session while SNARTomo is still running, you might want to start a ``screen`` session. Or you can simply leave that console open.

Settings
--------

For the most current settings, enter:

``snartomo-pace --help``

You can alternatively simply enter ``snartomo-pace -h``

Any of these parameters can be overridden on the command with the use of the appropriate flag, using the form:

``snartomo-pace --flag_to-override=your_new value``

The ``=`` is optional, and can be replaced by one or more spaces.

Data type as defined in `Markus Stabrin's argumentparser_dynamic.sh <https://gitlab.gwdg.de/mpi-dortmund/ze-edv-public/general-scripts-public/-/blob/master/bash/snippets/argumentparser/argumentparser_dynamic.sh>`_.

**Required**

 ==================== ======= ========= ==========================================================
  Flag                 Type    Default               Description
 ==================== ======= ========= ==========================================================
  ``--target_files``   FILE    None      Input target files, surround by quotes if more than one  
  ``--gain_file``      FILE    None      Input gain file                                          
 ==================== ======= ========= ==========================================================

**Global**

 ====================== ======= ===================== ==============================================================
  Flag                   Type    Default               Description
 ====================== ======= ===================== ==============================================================
  ``--eer_dir``          DIR     frames                 Input EER directory
  ``--frame_file``       ANY     motioncor-frame.txt    Input MotionCor2 frame file
  ``--live``             BOOL    false                  On-the-fly mode
  ``--last_tilt``        FLOAT   None                   Last tilt angle, degrees
  ``--tilt_tolerance``   FLOAT   0.2                    Pixel size, Å/px
  ``--outdir``           ANY     SNARTomo               Output directory
  ``--apix``             FLOAT   -1.0                   Pixel size, Å/px
  ``--testing``          BOOL    false                  Testing mode
  ``--slow``             BOOL    false                  In testing mode, simulates a delay in file creation
  ``--overwrite``        BOOL    false                  Overwrite output directory (only if no EERs)
  ``--max_minutes``      INT     100                    Maximum run time, minutes
  ``--verbosity``        INT     5                      Verbosity level (0..9)
  ``--wait``             INT     2                      Interval to check for new micrographs, seconds
  ``--kv``               FLOAT   300.0                  Voltage, kV
  ``--gpus``             ANY     "0 1 2"                GPUs to use (space-delimited and in quotes if more than one)
 ====================== ======= ===================== ==============================================================

**MotionCor2**

 ===================== ======= ========== ==============================================================
  Flag                  Type    Default    Description
 ===================== ======= ========== ==============================================================
  ``--mcor_patches``    ANY     '0 0'      Number of patches in x y, delimited by spaces and in quotes
  ``--reffrm``          INT     1          Reference frame (0: first, 1: middle)
  ``--do_splitsum``     BOOL    False      Split frames into half-sets
  ``--split_sum``       INT     0          (Deprecated) Split frames into half-sets (0: no, 1: yes)
  ``--do_outstack``     BOOL    False      Write aligned stacks
  ``--min_frames``      INT     400        Minimum number of EER frames before warning
  ``--max_frames``      INT     1200       Maximum number of EER frames before warning
 ===================== ======= ========== ==============================================================

**CTFFIND4**

 =================== ======= ========== ==============================================================
  Flag                Type    Default    Description
 =================== ======= ========== ==============================================================
  ``--cs``            FLOAT    2.7       Spherical aberration constant
  ``--ac``            FLOAT    0.07      Amplitude contrast
  ``--box``           INT      512       Tile size for power-spectrum calculation
  ``--res_lo``        FLOAT    30.0      Low-resolution limit for CTF fitting, Å
  ``--res_hi``        FLOAT    9.0       High-resolution limit for CTF fitting, Å
  ``--df_lo``         FLOAT    30000.0   Minimum defocus value, Å
  ``--df_hi``         FLOAT    70000.0   Maximum defocus value, Å
  ``--ast_step``      FLOAT    100.0     Astigmatism search step during fitting, Å
 =================== ======= ========== ==============================================================

**JANNI**

 ===================== ======= ========= ==============================================================
  Flag                  Type    Default   Description
 ===================== ======= ========= ==============================================================
   ``--do_janni``       BOOL    false     Flag to denoise using JANNI
  ``--janni_batch``     INT     24        Number of patches predicted in parallel
  ``--janni_overlap``   INT     4         Overlap between patches, pixels
 ===================== ======= ========= ==============================================================

**Topaz**

 ==================== ======= ========= ==============================================================
  Flag                 Type    Default   Description
 ==================== ======= ========= ==============================================================
  ``--do_topaz``       BOOL    false     Flag to denoise using Topaz
  ``--topaz_patch``    INT     2048      Patch size
  ``--topaz_env``      ANY     topaz     Conda environment
 ==================== ======= ========= ==============================================================

**DoseDiscriminator**

 ======================= ======= ========= ==============================================================
  Flag                    Type    Default   Description
 ======================= ======= ========= ==============================================================
  ``--dosefit_min``       FLOAT   0.10      Minimum dose rate allowed, as a fraction of maximum dose rate
  ``--dosefit_resid``     FLOAT   0.10      Maximum residual during dose-fitting, as a fraction of maximum
  ``--dosefit_verbose``   INT     6         Verbosity in log file (0..8)
 ======================= ======= ========= ==============================================================

**IMOD**

 ======================= ======= ===================== ==============================================================
  Flag                    Type    Default               Description
 ======================= ======= ===================== ==============================================================
  ``--do_etomo``          BOOL    false                 Flag to reconstruct using eTomo
  ``--batch_directive``   ANY     batchDirective.adoc   IMOD batch directive file
 ======================= ======= ===================== ==============================================================

**Ruotnocon**

 ==================== ======= ========= ==============================================================
  Flag                 Type    Default   Description
 ==================== ======= ========= ==============================================================
  ``--do_ruotnocon``   BOOL    false     Flag to remove contours
  ``--ruotnocon_sd``   FLOAT   3.0       Cutoff in units of sigma for residual
 ==================== ======= ========= ==============================================================

**AreTomo**

 =================== ======= ========= ==============================================================
  Flag                Type    Default   Description
 =================== ======= ========= ==============================================================
  ``--bin``           INT     8         Binning factor for reconstruction
  ``--vol_zdim``      INT     1600      z-dimension for volume
  ``--rec_zdim``      INT     1000      z-dimension for reconstruction
  ``--dark_tol``      FLOAT   0.7       Tolerance for dark images (0.0-1.0)
  ``--tilt_cor``      INT     1         Tilt-correction flag (1: yes, 0: no)
  ``--bp_method``     INT     1         Reconstruction method (1: weighted backprojection, 0: SART)
  ``--tilt_axis``     FLOAT   86.0      Estimate for tilt-axis direction, degrees
  ``--flip_vol``      INT     1         Flag to flip coordinates axes (1: yes, 0: no)
  ``--transfile``     INT     1         Flag to generate IMOD XF files (1: yes, 0: no)
  ``--are_patches``   ANY     0 0       Number of patches in x & y (delimited by spaces)
  ``--duration``      ANY     30m       Maximum duration (AreTomo sometimes hangs)
 =================== ======= ========= ==============================================================
