SNARTomoClassic
===============

SNARTomoClassic is the non-PACE version of SNARTomo. Since the images are collected at a lower rate, a single GPU is sufficient to keep up.

Quick Start
-----------

An example of usage is:

``snartomo-classic --eer_dir frames/ --gain_file gain_reference --frame_file motioncor_frame_file --mdoc_file MDOC_file --outdir output_directory/ &``

More detailed usage will be described below.

Requirements
------------

The following requirement is specific to SNARTomoClassic.  This is in addition to the requirements of a gain file and a frame file. Also it needs to know the pixel size, either from an MDOC file or with the ``--apix`` flag.

**Filenames**

SNARTomo expects EER filenames with the following structure:

``arbitraryTiltSeriesName_tiltSeriesIndex_angle_date.eer``

  * ``arbitraryTiltSeriesName``
    * It must be the same for each micrograph in the tilt series.
    * Each tomogram will be written to a subdirectory with this name (see Outputs section below)
    * This is the only part of the filename that can have underscores other than those shown in the template above.
  * ``tiltSeriesIndex`` -- Each image in the tilt series is expected to have a unique (integer) index number.
  * ``angle`` -- SNARTomo will use that value as the tilt angle when computing the 3D reconstruction.
  * ``date`` -- This string can be anything, not necessarily the date.
  * ``eer`` -- SNARTomo is hardwired to look for EER files.

Getting started
---------------

SNARTomo runs on our on-the-fly server (codenamed "Lorelei"). To log in to the guest account:

``ssh rubsak-guest@10.143.192.4``

SerialEM under our default settings will write data to ``/mnt/f4server/TemScripting/EF-Falcon/``

Most settings have a default value (everything except the gain reference), so in principle, you could simply type ``snartomo-classic --gain_file gain_reference`` without any further options specified.  This is not recommended. Instead, I recommend a "dry run", as described below. 

Even better, enter ``snartomo-classic --help`` (or ``snartomo-classic -h``) to see the full list of settings.  
More information about the specific options can be found below.

Dry run
-------

I **strongly** recommend performing a dry run, with the ``--testing`` option:

``snartomo-classic --eer_dir frames/ --gain_file gain_reference --frame_file motioncor_frame_file --mdoc_file MDOC_file --outdir output_directory/ --testing``

The information written to the screen before SNARTomo starts looking for individual files includes summaries of how to use SNARTomo, and the settings used. Also note the ``Validation`` section. If required inputs are missing, they will be noted here. Some sanity checks will be performed here, to make sure your parameters are sensible.

If you are still collecting data, SNARTomo will continue to look for new files, and will not stop on its own. Enter ``ctrl-c`` to exit from a dry run.

If the dry run produces too much screen output, a useful parameter to change is ``--verbosity``. The default value is 4. A verbosity of 6 will print the full command lines for each operation. A verbosity of 3 will print a summary for each tomogram. A verbosity of 2 will show notable warnings. For example:

``snartomo-classic --eer_dir frames/ --gain_file gain_reference --frame_file motioncor_frame_file --mdoc_file MDOC_file --outdir output_directory/ --testing --verbosity=3``

In testing mode, I recommend a verbosity level of 3 or (for big data sets) 2.

MDOC input
----------

As of 2022 March 14, the pixel size is a required parameter. Previously, we specified the pixel size with the ``--apix`` command-line option. You can instead provide an example SerialEM MDOC file, in which case SNARTomo will extract the pixel size (and other information) from there.

``snartomo-classic --eer_dir frames/ --gain_file gain_reference --frame_file motioncor_frame_file --mdoc_file MDOC_file --outdir output_directory/ --testing --verbosity=3``

In addition to the pixel size, SNARTomo will check the defocus values and the number of frames in each micrograph. If you got outside of the defocus range (which CTFFINFD4 will use), it will print a warning. If you go outside of the number of frames, there may be something weird going on with your data collection. **PAY ATTENTION TO THE WARNINGS!!**

I will probably add other sanity checks in the future. I recommend using an MDOC file instead of supplying only the pixel size, and have updated the examples on this page accordingly.

Execute!
--------

Once you are satisfied with the results of the dry run, remove the ``--testing`` flag. A typical command to start a run might look like:

``snartomo-classic --eer_dir frames/ --gain_file gain_reference --frame_file motioncor_frame_file --mdoc_file MDOC_file --outdir output_directory/ &``

A log file -- by default ``log-snartomo.txt`` and overridden by ``--log_file`` -- will contain everything printed to the screen. If something goes wrong, the log file will be among the first things that we ask for.

You might want to use ``tmux`` to work elsewhere on the on-the-fly machine. If you would like to exit the session while SNARTomo is still running, you might want to start a ``screen`` session. Or you can simply leave that console open. I recommend adding an ampersand (``&``) at the end of the command; SNARTomoClassic seems to work more reliably after you've detached a screen session.

How to stop
-----------

SNARTomo would be content to wait for new data forever. There are two ways for SNARTomo to exit automatically:

  - a dummy file
  - a predetermined time limit

**Dummy file** : After your data collection has finished, create a dummy file in your EER directory that breaks the file-naming convention above, such as ``done.eer``. (SNARTomo will also recognize such a file in testing mode. An example command to create a dummy file would be

``touch frames/done.eer``

**Time limit** : Alternatively, SNARTomo will stop looking for files after a predetermined limit, set by the command-line option ``--max_minutes``. The default is 600 minutes, i.e., 10 hours.

**NOTE** : The last 3D reconstruction will not be computed until SNARTomo thinks that data-collection has ended.

Troubleshooting
---------------

**UNDER CONSTRUCTION**

  * **General difficulty** -- Perform a dry run, and pay close attention to the errors and warnings.
  * **Program finds only one tilt series or one micrograph** -- make sure your filenames follow the standard convention.

Settings
--------

For the most current settings, enter:

``snartomo-classic --help``

You can alternatively enter ``snartomo-classic -h``

Any of these values can be overridden on the command with the use of the appropriate flag, using the form:

``snartomo-classic --flag_to-override=your_new value``

The ``=`` is optional, and can be replaced by one or more spaces.

Data type as defined in `Markus Stabrin's argumentparser_dynamic.sh <https://gitlab.gwdg.de/mpi-dortmund/ze-edv-public/general-scripts-public/-/blob/master/bash/snippets/argumentparser/argumentparser_dynamic.sh>`_.

**Required**

 =================== ======= ========= ==============================================================
  Flag                Type    Default   Description
 =================== ======= ========= ==============================================================
  ``--gain_file``     FILE    None      Input gain file  
  ``--frame_file``    ANY     None      Input MotionCor2 frame file  
 =================== ======= ========= ==============================================================

**Global**

 =================== ======= ==================================== ==============================================================
  Flag                Type    Default                              Description
 =================== ======= ==================================== ==============================================================
  ``--eer_dir``       DIR     frames                               Input EER directory  
  ``--mdoc_file``     ANY     None                                 Input example MDOC file  
  ``--log_file``      ANY     log-snartomo.txt                     Output log file  
  ``--outdir``        ANY     SNARTomo                             Output directory  
  ``--cmd_file``      ANY     commands.txt                         Commands log file, in ``outdir``  
  ``--settings``      ANY     settings.txt                         Settings file, in ``outdir``  
  ``--verbosity``     INT     4 (3 or 2 recommended for testing)   Verbosity level (0..9)  
  ``--testing``       BOOL    false                                Testing mode  
  ``--overwrite``     BOOL    false                                Overwrite output directory (only if no EERs)  
  ``--max_minutes``   INT     600                                  Maximum run time, minutes  
  ``--wait``          INT     4                                    Interval to check for new micrographs, seconds  
  ``--apix``          FLOAT   -1.0                                 Pixel size, Å/px  
  ``--kv``            FLOAT   300.0                                Voltage, kV  
  ``--gpus``          ANY     0                                    GPUs to use (space-delimited and in quotes if more than one)  
 =================== ======= ==================================== ==============================================================

**MotionCor2**

 ==================== ======= ========= ==============================================================
  Flag                 Type    Default   Description
 ==================== ======= ========= ==============================================================
  ``--mcor_patches``   ANY     '0 0'     Number of patches in x y, delimited by spaces and in quotes  
  ``--reffrm``         INT     1         Reference frame (0: first, 1: middle)  
  ``--do_splitsum``    BOOL    False     Split frames into half-sets  
  ``--split_sum``      INT     0         (Deprecated) Split frames into half-sets (0: no, 1: yes)  
  ``--do_outstack``    BOOL    False     Write aligned stacks  
  ``--min_frames``     INT     400       Minimum number of EER frames before warning  
  ``--max_frames``     INT     1200      Maximum number of EER frames before warning  
 ==================== ======= ========= ==============================================================

**CTFFIND4**

 =================== ======= ========= ==============================================================
  Flag                Type    Default   Description
 =================== ======= ========= ==============================================================
  ``--cs``            FLOAT   2.7       Spherical aberration constant  
  ``--ac``            FLOAT   0.07      Amplitude contrast  
  ``--box``           INT     512       Tile size for power-spectrum calculation  
  ``--res_lo``        FLOAT   30.0      Low-resolution limit for CTF fitting, Å  
  ``--res_hi``        FLOAT   9.0       High-resolution limit for CTF fitting, Å  
  ``--df_lo``         FLOAT   30000.0   Minimum defocus value, Å  
  ``--df_hi``         FLOAT   70000.0   Maximum defocus value, Å  
  ``--ast_step``      FLOAT   100.0     Astigmatism search step during fitting, Å  
 =================== ======= ========= ==============================================================

**JANNI**

 ===================== ======== ========= ==============================================================
  Flag                  Type     Default   Description
 ===================== ======== ========= ==============================================================
  ``--do_janni``        BOOL     false     Flag to denoise using JANNI 
  ``--janni_batch``     INT      24        Number of patches predicted in parallel  
  ``--janni_overlap``   INT      4         Overlap between patches, pixels  
 ===================== ======== ========= ==============================================================

**Topaz**

 =================== ======= ========= ==============================================================
  Flag                Type    Default   Description
 =================== ======= ========= ==============================================================
  ``--do_topaz``      BOOL    false     Flag to denoise  
  ``--topaz_patch``   INT     2048      Patch size  
 =================== ======= ========= ==============================================================

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
