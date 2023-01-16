.. SNARTomo documentation master file, created by
   sphinx-quickstart on Thu Jan 12 15:52:47 2023.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

Welcome to SNARTomo's documentation!
====================================

SNARTomo is our set of scripts for on-the-fly tomographic reconstruction. 
{{ :computers:snartomo2.png?direct&200|}}
The name is derived from the programs that were originally run by it:

  * **S** ee-tee-eff-find-four (CTFFIND4)
  * **N** ewstack, from IMOD
  * **AR** e **Tomo**

We since added other functionalities, such as MotionCor2, IMOD, Topaz, PACE, and JANNI, but the name remains.

Now on GitHub: [[https://github.com/rubenlab/snartomo]]

Changelog
=========

  * 2022-12-09 -- posted on GitHub
  * 2022-11-28 -- added FrameCalc to generate MotionCor frames file
  * 2022-11-18 -- PACE version can accept multiple targets files
  * 2022-09-08 -- contour-removal implemented
  * 2022-08-02 -- AreTomo 1.2.5 now the default
  * 2022-07-25 -- denoising using JANNI
  * 2022-07-22 -- dose-fitting implemented
  * 2022-03-12 -- can use example MDOC file as input
  * 2022-03-09 -- denoising (2D) using Topaz
  * 2022-02-28 -- can compute reconstruction using IMOD instead of AreTomo
  * 2022-02-07 -- exits upon unfamiliar command-line options
  * 2021-12-12 -- all options can be set from command line
  * 2021-12-11 -- times out after specified number of minutes
  * 2021-12-09 -- on-the-fly mode works correctly
  
Web Interface
=============

SNARTomoGUI is a web interface to help you generate a SNARTomo command.

[[https://rubenlab.github.io/snartomo-gui/#/]]
  
  
.. toctree::
   :maxdepth: 2
   :caption: Contents:
   
   gettingstarted
   framecalc
   pace
   classic
   apps
   outputs

Indices and tables
==================

* :ref:`genindex`
* :ref:`search`
