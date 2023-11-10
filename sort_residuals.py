#!/usr/bin/env python

import numpy as np
import argparse
import matplotlib
import matplotlib.pyplot as plt

matplotlib.use('agg')  # Gets rid of GUI dependencies
np.set_printoptions(suppress=True)

USAGE="""
Shows entries with highest residual and optionally plots.

USAGE:
  %s <residual_table> <options>

""" % ((__file__,)*1)

MODIFIED="Modified 2022 Nov 10"
MAX_VERBOSITY=3

def main():
  options= parse_command_line()
  #print(options)
  #exit()

  with open(options.angles_log) as f:
    skip_first= f.readlines()[options.skip:]

  header_line= skip_first[0].split()
  
  # Parse header line
  h2c= {k: v for v, k in enumerate(header_line)}
  #print(f"'{h2c}'")  # '{0: '#', 1: 'X', 2: 'Y', 3: 'Z', 4: 'obj', 5: 'cont', 6: 'resid-nm', 7: 'Weights'}'

  contour_data= np.loadtxt(options.angles_log, skiprows=options.skip+1)
  residual_array= contour_data[:, h2c['resid-nm'] ]
  sigma_residual= np.std(residual_array)
  min_residual= np.min(residual_array)
  #min_residual= np.mean(residual_array)
  #min_residual= 0
  #print('min_residual', type(min_residual), min_residual )

  # Sort
  sorted_array= contour_data[residual_array.argsort()]
  worst_countour= int(sorted_array[-1][0])
  worst_idx= np.argmax(residual_array)
  
  residual_cutoff= min_residual + options.sd * sigma_residual
  
  # If residual exceeds the threshold...
  if sorted_array[-1][ h2c['resid-nm'] ] >= (residual_cutoff) :
    # Print just the contour number
    if options.verbose==1:
      print( worst_countour )
    
    # Print all contours exceeding threshold
    elif options.verbose==2:
      # Reverse array
      reversed_array= sorted_array[::-1]
      
      # Initialize string to print
      list_bad=""
      
      # Loop through array
      for idx, line in enumerate(reversed_array):
        if reversed_array[idx][ h2c['resid-nm'] ] >= (residual_cutoff) :
          # Simply print contour number
          list_bad+=f"{int(reversed_array[idx][0])} "
        else:
          break  # no need to continue loop
      # End array loop
      
      ###print(f"'{list_bad}'")
      print(list_bad)
      
    # Print more detailed information
    elif options.verbose==3:
      print(f"Minimum: {min_residual:.2f}, sigma: {sigma_residual:.2f}nm, cutoff: minimum + {options.sd:.2f}*sigma = {residual_cutoff:.2f}")
      print("Indices exceeding cutoff:")
      
      # Reverse array
      reversed_array= sorted_array[::-1]
      
      # Loop through array
      for idx, line in enumerate(reversed_array):
        if reversed_array[idx][ h2c['resid-nm'] ] >= (residual_cutoff) :
          print(f"  Index: {int(reversed_array[idx][0])}, residual: {reversed_array[idx][ h2c['resid-nm'] ]:.2f}nm")
        else:
          break  # no need to continue loop
      
    # Print everything
    elif options.verbose>=4:
      print(sorted_array, type(sorted_array), sorted_array.shape, sigma_residual )

  # Remove row from array
  contour_data= np.delete(contour_data, worst_idx, axis=0)
  #print(contour_data)
  
  # Write to file
  if options.overwrite or options.outfile:
    # Overwrite input if no output specified
    if options.overwrite and not options.outfile: options.outfile= options.angles_log
    
    #os.remove(options.outfile)
    np.savetxt(options.outfile, [header_line], fmt='%-10s')
    with open(options.outfile, "ab") as f:
      np.savetxt(f, contour_data, fmt='%-10s')
  
  # Plot
  x = range( 1, len(residual_array)+1 )
  if options.plot:
    plt.scatter( x, np.sort(residual_array) )
    
    #print( h2c.keys() )
    for idx in range(len(residual_array)):
      plt.annotate( int(sorted_array[idx][0]), (x[idx]-0.7, sorted_array[idx][ h2c['resid-nm'] ]+np.ndarray.max(residual_array)/60), fontsize=6)
      #print( int(sorted_array[idx][0]), x[idx], sorted_array[idx][ h2c['resid-nm'] ] )
    
    plt.xlabel('Index number (sorted)')
    plt.ylabel('Residual (nm)')
    plt.hlines(residual_cutoff, x[0], x[-1])
    #plt.title( os.path.splitext( os.path.basename(options.plot) )[0], fontsize=16)
    plt.savefig(options.plot)
    ###plt.show()
  
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
        "angles_log", 
        type=str, 
        help="Log file from eTomo containing residuals")

    parser.add_argument(
        "--sd", "--sigma_cutoff", 
        type=float, 
        default=3, 
        help="Sigma cutoff, values above this threshold times sigma will be excluded")
    
    parser.add_argument(
        "--outfile", "-o",
        type=str, 
        default=None, 
        help="Output log file")

    parser.add_argument(
        "--overwrite",
        type=bool, 
        default=False, 
        help="Overwrite input")

    parser.add_argument(
        "--plot", 
        type=str, 
        default=None, 
        help="Residual plot PNG")

    parser.add_argument(
        "--verbose", "-v", "--verbosity", 
        type=int, 
        default=2, 
        help=f"Screen verbosity [0..{MAX_VERBOSITY}]")
    
    parser.add_argument(
        "--skip", 
        type=int, 
        default=1, 
        help="Number of lines before header row in input file")

    return parser.parse_args()

if __name__ == "__main__":
    main()
