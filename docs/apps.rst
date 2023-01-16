Application-specific usage
==========================

This section describes usagefor specific applications. Unless noted, the following options are available with both SNARTomoPACE and SNARTomoClassic.

3D reconstruction
-----------------

**AreTomo**

AreTomo is currently the default, used if you don't have an eTomo batch directive file (see below).

Starting with AreTomo 1.2, the program now removes dark images by default, with a parameter called "DarkTol". This parameter (default: 0.7) can be changed with the SNARTomo flag ``--dark_tol``.

Another important parameter is the number of patches. During alignment, AreTomo can optionally divide the micrograph into patches. This parameter is set using the flag ``--are_patches``. The default is ``"0 0"``. To use a 5x5 array of patches, for example, add ``--are_patches "5 5"``. (The quotes around "5 5" are required.) The alignment will be better, but the cost is speed. Without patches, AreTomo takes <2 minutes, whereas with a 5x5 array, AreTomo takes ~30 minutes.

**eTomo**

This option is for people who prefer the reconstruction from IMOD's eTomo, and/or would like to refine the reconstruction later on using eTomo.

There are two additional parameters required: ``--do_etomo --batch_directive batch_directive.adoc``

If you provide a batch directive but not the ``--do_etomo`` flag, SNARTomo will complain, but will still use it.

*NOTE* : Users are responsible for making sure their batch directive files are consistent with their data. Currently, only the pixel size is confirmed.

Someday, we may provide a default batch directive file, but for now, it is a required input.

Denoising
---------

*NOTE* : Both JANNI and Topaz have been crashing the pre-processing server's GPUs (both in and outside of SNARTomo), so at the moment, we have limited denoising to the CPU, which takes longer (2-3 seconds per micrograph on the GPU, vs. 17-18 seconds on the CPU).

`JANNI <http://sphire.mpg.de/wiki/doku.php?id=janni>`_ and `Topaz <https://github.com/tbepler/topaz>`_ are two software packages for denoising. 

**JANNI**

To perform denoising in SNARTomo using JANNI, add the ``--do_janni`` flag.

To see the full set of parameters, add the ``--help`` flag, or check the SNARTomo web interface.

SNARTomo checks whether the JANNI executable is available (that is, whether it is in your $PATH). If it isn't in your $PATH, SNARTomo tries to load the JANNI conda environment. 

**Topaz**

For on-the-fly processing, denoising in 2D is currently the only feasible option. Denoising in 3D would be too slow.

To perform denoising in SNARTomo using Topaz, add the ``--do_topaz`` flag.

One notable parameter is the ``--topaz_patch`` flag. If not specified, the entire micrograph would be denoised all at once. Even with our 11GB video cards, Topaz complains, so this parameter is set to 2048 by default.

To see the full set of parameters, add the ``--help`` flag, or check the SNARTomo web interface.

SNARTomo checks whether the Topaz executable is available (that is, whether it is in your $PATH). If it isn't in your $PATH, SNARTomo tries to load the Topaz conda environment. 

Dose-fitting
------------

This functionality is only available for the PACE version of SNARTomo at the moment.

See the Outputs section below for the color code.

The strategy is adapted from Felix's idea.  It consists of three steps:

  - Fits the dose rates to a cosine curve (implemented in Python by Tat)
  - Removes the points below a threshold dose rate and re-fits
  - Removes the points exceeding a threshold residual

Since the dose can vary considerably, the thresholds are given as a fraction of the maximum dose rate.

  * ``--dosefit_min`` -- minimum dose rate allowed (default: 0.10 * maximum dose rate)
  * ``--dosefit_resid`` -- maximum residual (default: 0.10 * maximum dose rate)

Contour-removal
---------------

For eTomo reconstructions, the routine for removing bad contours is called "Ruotnocon" (reverse of "no contour"). Contours are removed on the basis of high residuals. The following is an extreme example:

Ruotnocon is controlled with the following parameters:

  * ``--do_ruotnocon`` -- True or false (default: false)
  * ``--ruotnocon_sd`` -- Number of standard deviations for residuals, beyond which contours will be removed (default: 3)

See the Outputs section for an example of the residual plot.
