Outputs
=======

By directory:

Run directory
-------------

  * ``log-snartomo.txt'' -- specific for SNARTomoClassic
    * contains all screen output (except in the case of ``--testing`` or ``--verbosity=0``)
    * can be overridden by ``--log_file``

Top-level
---------

  * ``commands.txt``
    * contains the command line(s) that were used for runs sent to this output directory
    * If multiple run specified the same output directory, the command lines will be appended.
    * useful for bookkeeping
  * ``settings.txt``
    * contains settings -- both user-specified and default -- for last run
    * also repeated at the top of the log file
  * gain reference -- if input gain reference wasn't in MRC format, the MRC version will be here

Logs
----

Specific for SNARTomoPACE

  * ``snartomo.txt`` -- overall summary
  * ``files.txt`` -- file events: detection, MotionCor2, CTFFIND4, etc.
  * ``motioncor2.txt`` -- MotionCor2 screen output
  * ``ctffind4.txt`` -- CTFIND4 screen output
  * ``recon.txt`` -- Reconstruction (eTomo, AreTomo, etc.)
  * ``log-gpu.txt`` -- log of GPU memory usage
  * ``plot-gpu.gnu`` -- plot above with ``gnuplot --persist <logs_directory>/plot-gpu.gnu``
  * ``log-mem.txt`` -- log of memory usage
  * ``plot-mem.gnu`` -- plot above with ``gnuplot --persist <logs_directory>/plot-mem.gnu``

1-EER
-----

This directory will be empty with SNARTomoPACE

  * ``*.eer``
    * EER files will be moved here.
    * Moving the files was the easiest way to keep track of which files have been processed already.
  * ``*.mdoc`` -- Associated MDOC files, if present in the input directory, will be moved here also.

2-MotionCor2
------------

  * ``*_mic.mrc`` -- Non-dose-weighted motion-corrected micrographs
  * ``Logs/*mic.out`` -- screen output from MotionCor2
  * ``Logs/*Full.log`` -- shift parameters for each frame
  * ``Logs/*Tiff.log`` -- list of micrographs processed (will be a single micrograph in on-the-fly mode)

3-CTFFIND4
----------

  * ``SUMMARY.CTF``
    * summary of CTF fits for all micrographs -- extracted from ``*_ctf.txt`` files
    * 0: micrograph name
    * 1: micrograph number (1 in on-the-fly mode)
    * 2: defocus along minor axis
    * 3: defocus along major axis
    * 4: angle of astigmatism (azimuth)
    * 5: phase shift (not used for us)
    * 6: correlation value
    * 7: estimated resolution of fitting
  * ``*_ctf.txt`` -- fitting summary for each micrograph
  * ``*_ctf.mrc`` -- power spectra, experimental and fitted
  * ``*_ctf.out`` -- screen output from CTFFIND4
  * ``*_ctf_avrot.pdf`` -- 1D profiles, plotted, of experimental and fitted power spectra
  * ``*_ctf_avrot.txt`` -- 1D profiles, as text

4-Denoised
----------

  * ``*_mic.mrc`` -- Denoised, non-dose-weighted motion-corrected micrographs

5-Tomo
------

Each tilt series will generate its own subdirectory. The outputs will different depending on whether you computed the reconstruction using AreTomo (the default) or IMOD (using the ``--do_etomo`` flag).

**AreTomo**

  * ``*.rawtlt`` -- tilt angles, sorted from lowest (most negative) to highest
  * ``*.imod.txt`` -- list of micrographs -- needed by IMOD
  * ``*_newstack.mrc`` -- tilt-series micrographs, ordered from lowest angle (most negative) to highest
  * ``*_newstack.log`` -- output from IMOD's newstack
  * ``*_newstack.aln`` -- alignment parameters 
  * ``*_newstack.xf`` -- other (??) parameters
  * ``*_aretomo.mrc`` -- tomographic reconstruction
  * ``*_aretomo.log`` -- screen output from AreTomo 

**IMOD**

*UNDER CONSTRUCTION*

Images
------

**Central sections**

In the ``Images/Thumbnails`` subdirectory, a central section will be saved in JPG format for each reconstruction. A nice image-viewer is ``geeqie``.

**Dose-fitting**

This functionality is only available for the PACE version of SNARTomo at the moment.

In the ``Images/Dosefit`` subdirectory, the results of dose-fitting are plotted.

Color code:

  - green: points passing minimum and residual criteria
  - orange: points passing minimum criterion but not residual criteion
  - blue: points below minimum threshold

See the "Parameters" section above to see how to adjust these threshold parameters.

**Contour-removal**

A plot of the sorted residuals can be found in ``Images/Contours``:

The horizontal line represents the cutoff.

