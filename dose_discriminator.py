#!/usr/bin/env python

import sys
import numpy as np
from scipy import optimize
import matplotlib.pyplot as plt
import os
import argparse
from datetime import datetime

np.set_printoptions(suppress=True)

USAGE="""
Eliminates images which are too dark or deviate too much from a cosine function.

USAGE:
  %s <dose_list> <options>

""" % ((__file__,)*1)

MODIFIED="Modified 2023 Oct 11"
MAX_VERBOSITY=8

def print_log_msg(mesg, cutoff, options):
    """
    Prints messages to log file and, optionally, to the screen.
    
    Arguments:
        mesg : Message to write
        cutoff : Verbosity threshold
        options : (Namespace) Command-line options
    """

    if options.screen_verbose >= cutoff:
      print(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}: {mesg}")
      
    if options.log_file != None and options.log_verbose >= cutoff:
      with open(options.log_file, "a") as myfile:
        myfile.write(mesg+"\n")

def cosine_func(x, a, b ,c):
  return a + b * np.cos(x + c)

def main():
  options= parse_command_line()
  output_png= options.dose_plot  # sys.argv[4]

  # Clean up pre-existing file
  if options.log_file != None and os.path.exists(options.log_file):
    os.remove(options.log_file)
  
  unsorted_array= np.loadtxt(options.dose_list)
  sorted_array= unsorted_array[unsorted_array[:, 1].argsort()]

  # These arrays will be updated
  dose_array = sorted_array[:,2]
  tilt_array = sorted_array[:,1]
  idx_array= sorted_array[:,0].astype(int)  # make the array integer
  yrm_array= [""]*len(idx_array)

  # These arrays will be static
  dose_array0 = dose_array.copy()
  tilt_array0 = tilt_array.copy()
  idx_array0 = idx_array.copy()
  
  # Cutoffs now as a fraction of maximum
  max_dose= np.ndarray.max(dose_array0)
  dose_cutoff= max_dose * options.min_dose
  max_residual= max_dose * options.max_residual

  # Fit all points
  tilt_rad= np.radians(tilt_array)
  fit_params1,_ = optimize.curve_fit(cosine_func, tilt_rad, dose_array)
  fit_curve1 = fit_params1[0] + fit_params1[1] * np.cos(tilt_rad + fit_params1[2])
  residual_array1= abs(dose_array - cosine_func(tilt_rad, *fit_params1))

  # Scatter plot of raw data
  plt.figure( figsize=(9,9) )
  plt.scatter(tilt_array, dose_array)
  plt.plot(tilt_array, fit_curve1, label="all images")
  
  # Annotate
  print_log_msg(" SORT  ZV  ANGLE   DOSE_R RESID_1", 8, options)
  for idx in range(len(idx_array)):
    plt.annotate(idx_array[idx], (tilt_array[idx]-0.9, dose_array[idx]+max_dose/40), fontsize=6)
    print_log_msg(f"  {idx:2d},  {idx_array[idx]:2d}, {tilt_array[idx]:5.1f}, {dose_array[idx]:6.3f}, {residual_array1[idx]:6.3f}", 7, options)
    
  # Initialize counter
  rm_counter= 0

  # Remove outliers
  for sort_idx, img in reversed( list( enumerate(idx_array) ) ):
    if dose_array[sort_idx] < dose_cutoff :
      print_log_msg(f"  Removed image #{img}, dose rate: {dose_array[sort_idx]}", 6, options)
      idx_array= np.delete(idx_array, sort_idx)
      yrm_array[sort_idx]=" <- REMOVED, LOW DOSE RATE"
      tilt_array= np.delete(tilt_array, sort_idx)
      dose_array= np.delete(dose_array, sort_idx)
      rm_counter+=1
  
  plt.hlines(dose_cutoff, tilt_array0[0], tilt_array0[-1])

  # Re-fit
  tilt_rad = np.radians(tilt_array)
  fit_params2,_ = optimize.curve_fit(cosine_func, tilt_rad, dose_array)
  fit_curve2 = fit_params2[0] + fit_params2[1] * np.cos(tilt_rad + fit_params2[2])

  tilt_rad0= np.radians(tilt_array0)
  residual_array2= abs(dose_array0 - cosine_func(tilt_rad0, *fit_params2))
  
  print_log_msg(" SORT  ZV  ANGLE   DOSE_R RESID_1 RESID_2", 7, options)
  for sort_idx, img in enumerate(idx_array0):
    print_log_msg(f"  {sort_idx:2d},  {img:2d}, {tilt_array0[sort_idx]:5.1f}, {dose_array0[sort_idx]:6.3f}, {residual_array1[sort_idx]:6.3f}, {residual_array2[sort_idx]:6.3f} {yrm_array[sort_idx]}", 7, options)

  plt.scatter(tilt_array, dose_array)
  plt.plot(tilt_array, fit_curve2, label="dose cutoff")

  for sort_idx, img in reversed( list( enumerate(idx_array) ) ):
    # Residuals have original indexing
    idx0= np.where(idx_array0==img)[0][0]
    
    if residual_array2[idx0] > max_residual :
      print_log_msg(f"  Removed image #{img}, residual: {residual_array2[idx0]:6.3f}", 6, options)
      yrm_array[idx0]=" <- REMOVED, HIGH RESIDUAL"
      idx_array= np.delete(idx_array, sort_idx)
      tilt_array= np.delete(tilt_array, sort_idx)
      dose_array= np.delete(dose_array, sort_idx)
      rm_counter+=1
  
  # Re-fit
  tilt_rad = np.radians(tilt_array)
  
  # If too many points were removed, this step will fail.
  try:
    fit_params3,_ = optimize.curve_fit(cosine_func, tilt_rad, dose_array)
  except TypeError:
    print_log_msg(f"WARNING! Only {len(dose_array)}/{len(dose_array0)} images remaining after filtering out those with low dose rate", 1, options)
    np.savetxt(options.good_angles, idx_array0, fmt="%d")
    print_log_msg(f"  Saved all {len(dose_array0)} images to '{options.good_angles}'", 1, options)
    exit(12)
  
  fit_curve3 = fit_params3[0] + fit_params3[1] * np.cos(tilt_rad + fit_params3[2])

  tilt_rad0= np.radians(tilt_array0)
  residual_array3= abs(dose_array0 - cosine_func(tilt_rad0, *fit_params3))

  # Write summary
  print_log_msg(" SORT  ZV  ANGLE   DOSE_R RESID_1 RESID_2 RESID_3", 6, options)
  for sort_idx, img in enumerate(idx_array0):
    print_log_msg(f"  {sort_idx:2d},  {img:2d}, {tilt_array0[sort_idx]:5.1f}, {dose_array0[sort_idx]:6.3f}, {residual_array1[sort_idx]:6.3f}, {residual_array2[sort_idx]:6.3f}, {residual_array3[sort_idx]:6.3f} {yrm_array[sort_idx]}", 6, options)

  plt.scatter(tilt_array, dose_array)
  plt.plot(tilt_array, fit_curve3, label="residual cutoff")

  # Get yrange and pad top (for labels)
  yrange=plt.gca().get_ylim()
  plt.ylim(0, np.ndarray.max(dose_array0)*1.15)

  plt.legend(loc="upper right")
  plt.gcf().canvas.manager.set_window_title('Window title')  # not in PNG
  plt.xlabel('Tilt angle')
  plt.ylabel('Dose rate')
  plt.title( os.path.splitext( os.path.basename(output_png) )[0], fontsize=16)
  print(f"plt.gcf() '{plt.gcf()}'")
  print(f"plt.rcParams['figure.figsize'] '{plt.rcParams['figure.figsize']}'")
  plt.savefig(output_png)

  np.savetxt(options.good_angles, idx_array, fmt="%d")
  print_log_msg(f"Removed {rm_counter} images based on dose-fitting", 2, options)
  
def parse_command_line():
    """
    Parse the command line.  Adapted from sxmask.py

    Arguments:
        None

    Returns:
        Parsed arguments object
    """

    parser= argparse.ArgumentParser(
        formatter_class=argparse.ArgumentDefaultsHelpFormatter, 
        usage=USAGE, 
        epilog=MODIFIED
        )
    
    parser.add_argument(
        "dose_list", 
        type=str, 
        help="Dose-versus-angle text file")

    parser.add_argument(
        "--min_dose", 
        type=float, 
        default=0.1, 
        help="Minimum dose, as a fraction of maximum dose rate")
    
    parser.add_argument(
        "--max_residual", 
        type=float, 
        default=0.1, 
        help="Maximum residual, as a fraction of maximum dose rate")
    
    parser.add_argument(
        "--dose_plot", 
        type=str, 
        default="plot.png", 
        help="Output fitted plot PNG")

    parser.add_argument(
        "--good_angles", 
        type=str, 
        default="good_angles.txt", 
        help="Output good-angles text file")

    parser.add_argument(
        "--log_file", 
        type=str, 
        default=None, 
        help="Output log file")

    parser.add_argument("--screen_verbose",
        type=int, 
        default=4, 
        help=f"Screen verbosity [0..{MAX_VERBOSITY}]")
    
    parser.add_argument("--log_verbose",
        type=int, 
        default=6, 
        help=f"Log verbosity [0..{MAX_VERBOSITY}]")
    
    return parser.parse_args()

if __name__ == "__main__":
    main()
