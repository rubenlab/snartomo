#!/usr/bin/env python

#import sys
import numpy as np
#from scipy import optimize
import matplotlib
import matplotlib.pyplot as plt
import os
import argparse
from datetime import datetime
import csv
import glob
import itertools
from matplotlib import ticker
import sys

matplotlib.use('agg')  # Gets rid of GUI dependencies
#np.set_printoptions(suppress=True)

USAGE="""
Plots CTF information for a tilt series.

USAGE:
  %s <CTF_summaries> <tilt_series_list> <ctf_by_ts_plot> <options>
  
<tilt_series_list> will be created if it doesn't exist.

Assumptions:
  The name of the tilt series is the parent directory name of the CTF file.
  Each CTF summary has the same name in each tilt-series directory.
  CTF summary has the same form as CTFFIND4, namely:
    1) micrograph name
    3) Major axis
    4) Minor axis
    7) CCFit
    8) Estimated resolution

""" % ((__file__,)*1)

MODIFIED="Modified 2024 Mar 25"
MAX_VERBOSITY=8

def print_log_msg(mesg, cutoff, options):
    """
    Prints messages to log file and, optionally, to the screen.
    
    Arguments:
        mesg : Message to write
        cutoff : Verbosity threshold
        options : (Namespace) Command-line options
    """

    if options.verbosity >= cutoff:
      print(f"{mesg}")
      
    if options.log_file != None and options.log_verbose >= cutoff:
      with open(options.log_file, "a") as myfile:
        myfile.write(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}: {mesg}\n")

def main():
  options= parse_command_line()
  ###print_log_msg("", 2, options)
  
  ts_file= options.tilt_list
  ctf_plot= options.ctf_by_ts_plot
  
  # Read file series (might be space-seperated with wild cards)
  tilt_ctfs=[]  # glob.glob(options.tilt_ctfs)
  for curr_pattern in options.tilt_ctfs.split():
    tilt_ctfs+= glob.glob(curr_pattern)

  # Sanity check
  if len(tilt_ctfs)==0:
    print(f"\nERROR! list of CTF summaries ('{options.tilt_ctfs}') resulted in zero files")
    print("  Exiting...\n")
    exit(5)

  # Sort (adapted from https://stackoverflow.com/a/23430865)
  tilt_ctfs.sort(key=os.path.getmtime)
  
  # Sanity check: Make sure plot extension is legal
  plot_ext= os.path.splitext(ctf_plot)[1].lstrip('.')
  allow_fmts="eps, jpeg, jpg, pdf, pgf, png, ps, raw, rgba, svg, svgz, tif, tiff"  # copied from error
  if not any( plot_ext in s for s in allow_fmts.split(',') ):
      print(f"\nERROR!! Plot extension '{plot_ext}' not recognized!")
      print(f"\tAllowed formats: {allow_fmts}")
      print("\tExiting...")
      exit(4)
  
  # UPDATE TILT-SERIES LIST (TODO: Move to function)
  
  # If TS list exists, read it
  if options.overwrite or not os.path.exists(ts_file):
    ts_list=[]
    print_log_msg(f"\nCreating new file: {ts_file}", 2, options)
  else:
    with open(ts_file) as file:
      ts_list= [line.rstrip() for line in file]
    print_log_msg(f"Read {len(ts_list)} entries from '{ts_file}'", 2, options)
  # End new file IF-THEN
  
  # Loop through CTF files
  for curr_ctf in tilt_ctfs:
    # Add to list
    ts_name= os.path.basename (os.path.dirname(curr_ctf) )
    
    # If it's the current directory, ts_name will be blank
    if ts_name== '' : ts_name='.'
    
    ts_list+=[ts_name]
    print_log_msg(f"  Adding '{ts_name}' to '{ts_file}'", 5, options)
    
    # If single image
    if len(tilt_ctfs) == 1 and options.verbosity == 2:
      print(f"Adding '{ts_name}' to '{ts_file}'")
    
    # Remember the rest of the filename structure also
    ctf_fn= os.path.basename(curr_ctf)
    tomo_dir= os.path.dirname( os.path.dirname(curr_ctf) )
  # End CTF loop
    
  # Make sure there are no repeats (https://www.w3schools.com/python/python_howto_remove_duplicates.asp)
  length_before= len(ts_list)
  ts_list= list(dict.fromkeys(ts_list))
  length_after= len(ts_list)
  num_dupes= length_before - length_after
  
  with open(ts_file, 'w') as fp:
    for item in ts_list:
        # write each item on a new line
        fp.write("%s\n" % item)
        print_log_msg(f"  Writing '{item}' to '{ts_file}'", 6, options)
    
    mesg=f"Wrote {length_after} entries to '{ts_file}'"
    if num_dupes != 0 : mesg+= f" (after removing {num_dupes} duplicates)"
    print_log_msg(mesg, 2, options)
  
  # PROCESS CTF SUMMARIES (TODO: Move to function)
  
  cccoef=[]
  resoln=[]
  defocus=[]
  
  # Loop through tilt series
  for ts_idx, curr_ts in enumerate(ts_list):
    curr_ctf= os.path.join(tomo_dir, curr_ts, ctf_fn)
  
    # Read CTF summary (https://stackoverflow.com/a/54698969)
    with open(curr_ctf,'r') as f:
      ctf_lines= list(csv.reader(f, delimiter = ' ', skipinitialspace = True))
    # (Tab delimiters will still be present.)
    
    # Make sure there are no duplicates (adapted from https://stackoverflow.com/a/2213973)
    length_before= len(ctf_lines)
    ctf_lines= sorted(ctf_lines)
    ctf_lines= list(ctf_lines for ctf_lines,_ in itertools.groupby(ctf_lines))
    length_after= len(ctf_lines)
    num_dupes= length_before - length_after
    if num_dupes != 0 : print_log_msg(f"  Ignored {num_dupes} duplicate CTF entries from '{curr_ctf}'", 4, options)
    
    # Unsuccessful CTFFIND runs will have non-numeric information in the table, so we need to clean
    ctf_lines= clean_up_summary(
      ctf_lines,
      [2,3,6,7],
      verbose=options.verbosity,
      tilt_series=curr_ts
      )
    
    # Optionally keep only first N images 
    if options.first > 0 : ctf_lines= ctf_lines[:options.first]
    
    # Extract 6th & 7th columns (numbering from 0)
    try:
      defocus+=[( float(el[2])+float(el[3]) )/20000 for el in ctf_lines]
    except ValueError:
      eprint(curr_ctf, ctf_lines, 2)
      eprint(curr_ctf, ctf_lines, 3)
      exit(1)
    
    try:
      resoln+=[1/float(el[7]) for el in ctf_lines]
    except ValueError:
      eprint(curr_ctf, ctf_lines, 7)
      exit(2)
    
    try:
      cccoef+=[float(el[6]) for el in ctf_lines]
    except ValueError:
      eprint(curr_ctf, ctf_lines, 6)
      exit(3)
    
    # If points aren't at exact same x, you can see if they pile up
    slant=0.025
    
    if ts_idx == 0 :
      xvalue= np.linspace(-slant,slant, len(ctf_lines), endpoint=False)
      color_list= np.arange( len(ctf_lines) )
    else:
      # Append to x array
      xvalue= np.concatenate( (xvalue, np.linspace(ts_idx-slant,ts_idx+slant, len(ctf_lines), endpoint=False) ) )
      color_list= np.concatenate( (color_list, np.arange( len(ctf_lines) ) ) )
    
  # Plot setup
  psiz= options.pointsize
  fig, ax = plt.subplots(3, sharex=True)
  plt.xlim(-0.5, len(ts_list) - 0.5)
  
  # Resolution plot
  ax[0].set(ylabel='Resolution (1/Å)')
  ax2= ax[0].secondary_yaxis('right')
  ax2.set_ylabel('Resolution (Å)')
  angstrom_labels= [50, 25, 15, 10, 7, 5]
  ax[0].scatter(xvalue, resoln, c=color_list, cmap=options.color, s=psiz)
  ax2.set_ticks([1/a for a in angstrom_labels])
  ax2.set_yticklabels(angstrom_labels)  #, fontsize=10)
  ###plt.get(ax2)
  
  # CCFit plot
  ax[1].set(ylabel='CCFit')
  ax[1].scatter(xvalue, cccoef, c=color_list, cmap=options.color, s=psiz)
  
  # Defocus plot
  ax[2].set(ylabel='Defocus (μm)')
  ax[2].yaxis.set_major_formatter(ticker.FormatStrFormatter('%.1f'))
  ax[2].scatter(xvalue, defocus, c=color_list, cmap=options.color, s=psiz)
  
  # Use reasonable defaults for font size (don't go smaller than 5, 10 is the default)
  if len(ts_list) >= 100:
    fontsize=5
  if len(ts_list) >= 75:
    fontsize=6
  else:
    fontsize=10
  ###print(f"232 fontsize: {fontsize}")

  # Label with tilt-series name
  plt.xticks(np.arange( len(ts_list) ), ts_list, fontsize=fontsize)
  plt.xticks(rotation=90)
  
  # Makes margins sensible
  plt.tight_layout()
  
  # Set size
  plt.gcf().set_size_inches(options.figuresize, options.figuresize)

  # Save plot (need to write it before displaying it, or else it'll be blank)
  plt.savefig(ctf_plot)
  print_log_msg(f"Wrote plot to {ctf_plot}", 2, options)
  
  if options.gui : plt.show()
  
  print_log_msg("", 2, options)
  
def clean_up_summary(ctf_lines, column_list, verbose=0, tilt_series=None):
    """
    Echoes to both stdout nad stderr before exiting
    Adapted from https://stackoverflow.com/a/14981125

    Arguments:
      CTF-summary data (list of lists)
      list of columns
      verbosity
      tilt_series
      
    Returns:
      new list of lists
    """
    
    new_list=[]
    if verbose>=7:
      if tilt_series:
        print(f"CTF-summary data for tilt series '{tilt_series}'")
      else:
        print("CTF-summary data for current tilt series")

    # Loop through lines
    for curr_line in ctf_lines:
      if verbose>=7 : print(f"  {' '.join(curr_line)}")
      
      if verbose>=8:
        # Loop through columns
        for col in column_list:
          value= curr_line[col]
          print(f"    column {col}, value {value}, type {type(value)}")
        # End column loop
      
      try:
        new_row= [float(curr_line[c]) for c in column_list]
        new_list.append(curr_line)
      except ValueError:
        #print(curr_line)
        if verbose>=1 : print(f"  WARNING! Entry '{curr_line[0].rstrip(':')}' has non-numeric values, may have failed")
    # End line loop
    
    return new_list
    
def eprint(fn, ctf_lines, col):
    """
    Echoes column from list of lists to both stdout and stderr
    Adapted from https://stackoverflow.com/a/14981125
    TODO: Pinpoint and excise weird values

    Arguments:
      1) filename
      2) CTF data (list of lists)
      3) column number
    """
    
    string=f"{fn}, column {col}: {list(zip(*ctf_lines))[col]}\n"
    print( os.path.basename(os.path.dirname(fn) ), string)
    print( os.path.basename(os.path.dirname(fn) ), string, file=sys.stderr)

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
        "tilt_ctfs", 
        type=str, 
        help="Input CTF summaries for tilt series (surrounded by quotes if more than one)")

    parser.add_argument(
        "tilt_list", 
        type=str, 
        help="Output list of tilt series (appended if existing)")

    parser.add_argument(
        "ctf_by_ts_plot", 
        type=str, 
        help="Output plot of CTFs by tilt series")

    parser.add_argument(
        "--first",
        type=int, 
        default=-1, 
        help="Plot only the first N images from the tilt series")
    
    parser.add_argument(
        "--color", 
        type=str, 
        default="viridis", 
        help="Color map (other option: gnuplot)")

    parser.add_argument(
        "--pointsize", "-ps",
        type=int,
        default=32,
        help="Point size in plot")

    parser.add_argument(
        "--figuresize", "-fs",
        type=int,
        default=9,
        help="Figure size of plot, inches")

    parser.add_argument(
        "--verbosity", "-v",
        type=int, 
        default=4, 
        help=f"Verbosity [0..{MAX_VERBOSITY}]")
    
    parser.add_argument(
        "--overwrite",
        default=False, 
        action='store_true', 
        help="Overwrite tilt-series list")

    parser.add_argument(
        "--gui",
        default=False, 
        action='store_true', 
        help="Open interactive plot")

    parser.add_argument(
        "--log_file", 
        type=str, 
        default=None, 
        help="Log file")

    return parser.parse_args()

if __name__ == "__main__":
    main()
