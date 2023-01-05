#!/usr/bin/env python

import numpy as np
import argparse
import matplotlib.pyplot as plt

np.set_printoptions(suppress=True)

USAGE="""
Shows contour with highest residual and optionally plots.

USAGE:
  %s <residual_table> <options>

""" % ((__file__,)*1)

MODIFIED="Modified 2022 Sep 02"
MAX_VERBOSITY=3

def main():
  options= parse_command_line()
  #print(options)
  #exit()

  with open(options.angles_log) as f:
    skip_first= f.readlines()[1:]

  header_line= skip_first[0].split()
  
  # Parse header line
  h2c= {k: v for v, k in enumerate(header_line)}
  #print(f"'{h2c}'")  # '{0: '#', 1: 'X', 2: 'Y', 3: 'Z', 4: 'obj', 5: 'cont', 6: 'resid-nm', 7: 'Weights'}'

  contour_data= np.loadtxt(options.angles_log, skiprows=2)
  residual_array= contour_data[:, h2c['resid-nm'] ]
  sigma_residual= np.std(residual_array)
  ###print(residual_array, type(residual_array), sigma_residual )

  # Sort
  sorted_array= contour_data[residual_array.argsort()]
  worst_countour= int(sorted_array[-1][0])
  worst_idx= np.argmax(residual_array)
  
  residual_cutoff= options.sd * sigma_residual
  
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
      print(f"Sigma: {sigma_residual:.1f}nm, cutoff: {options.sd:.2f}*sigma")
      print("Contours exceeding cutoff:")
      
      # Reverse array
      reversed_array= sorted_array[::-1]
      
      # Loop through array
      for idx, line in enumerate(reversed_array):
        if reversed_array[idx][ h2c['resid-nm'] ] >= (residual_cutoff) :
          print(f"  Contour: {int(reversed_array[idx][0])}, residual: {reversed_array[idx][ h2c['resid-nm'] ]:.1f}nm")
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
  ##x = list( range( 1, len(residual_array)+1 ) )
  ##print(x)
  x = range( 1, len(residual_array)+1 )
  #for i in x:
    #print(i)
  if options.plot:
    plt.scatter( x, np.sort(residual_array) )
    plt.xlabel('Contour number (sorted)')
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
        help="Sigma cutoff, only contour above this threshold times sigma will be displayed")
    
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
    
    return parser.parse_args()

if __name__ == "__main__":
    main()
