#!/usr/bin/env python

import json
import os
import argparse
import sys
import subprocess

USAGE = """
  USAGE:: %s <even_stacks> <odd_stacks> <options>

  NOTE: If more than one stack, they should be separated by spaces and surrounded by quotes.
  
  For more info about options, enter: %s --help

""" % ( (os.path.basename(__file__),)*2 )

MODIFIED="Modified 2025 Aug 31"
MAX_VERBOSITY=7

def system_call_23(cmd, args, lenient=False, stdout=None, stderr=None, usempi=False, log=None, verbose=False):
    """
    Runs subprocess safely.

    Arguments:
        cmd : Executable
        args : Command-line arguments
        lenient : (boolean) Will simply print warning in case of error
        stdout : Where to direct standard out
        stderr : Where to direct standard error
        usempi : (boolean) Whether using MPI, in order to remove "OMPI_COMM_WORLD_RANK" from os.environ if necessary
        log : Logger instance
        verbose : (boolean) Whether to write to screen
    """

    # Check Python version
    python_version= sys.version.split()[0]

    # Keep up to one decimal
    version_float= float('.'.join(python_version.split('.', 2)[:2]))

    # Build command line
    cmdline= "%s %s" % (cmd, args)

    if verbose : print(f"Running: {cmdline}")

    if usempi:
        mpi_rank= os.environ["OMPI_COMM_WORLD_RANK"]
        del os.environ["OMPI_COMM_WORLD_RANK"]

    try:
        if version_float < 3.5:
            subprocess.check_call(cmdline, stdout=stdout, stderr=stderr, shell=True)
            # (shell=True is risky, but I couldn't get it to work without)
        else:
            subprocess.run([cmd] + args.split(), stdout=stdout, stderr=stderr)
    except subprocess.CalledProcessError:
        if not lenient:
            print("\nERROR!! Cannot execute '%s'." % cmdline, file=sys.stderr)
            if "OMPI_COMM_WORLD_RANK" in os.environ:
                print("Maybe try to remove 'OMPI_COMM_WORLD_RANK' from os.environ by using 'usempi=True' in 'system_call_23'.")
            print()
            exit(13)
        else:
            print("\nWARNING! Cannot execute '%s'\n" % cmdline)

    if usempi:
        os.environ["OMPI_COMM_WORLD_RANK"]= mpi_rank

def main():
    options= parse_command_line()
    ##print(options)
    ##exit()

    # Prepare data-extraction JSON
    extract_dict={}
    extract_dict['even'] = options.even.split()
    extract_dict['odd'] = options.odd.split()
    extract_dict['patch_shape'] = [options.shape,options.shape,options.shape]
    extract_dict['num_slices'] = options.slices
    extract_dict['split'] = 0.9  # I don't know what this does
    extract_dict['tilt_axis'] = options.axis
    extract_dict['n_normalization_samples'] = options.norm
    extract_dict['path'] = options.iodir

    dump_json(
        extract_dict,
        os.path.join(options.iodir, options.json_extract),
        verbose=options.verbosity>=7
        )

    train_dict={}
    train_dict['train_data'] = options.iodir
    train_dict['epochs'] = options.epochs
    train_dict['steps_per_epoch'] = options.steps
    train_dict['batch_size'] = options.batch
    train_dict['unet_kern_size'] = options.kernel
    train_dict['unet_n_depth'] = options.depth
    train_dict['unet_n_first'] = options.first
    train_dict['learning_rate'] = options.learn
    train_dict['model_name'] = options.model
    train_dict['path'] = options.iodir
    train_dict['gpu_id'] = f"[{','.join(options.gpus_train.split())}]"

    dump_json(
        train_dict,
        os.path.join(options.iodir, options.json_train),
        verbose=options.verbosity>=7
        )

    predict_dict={}
    predict_dict['path'] = os.path.join(options.iodir, options.model + ".tar.gz")
    predict_dict['even'] = options.even.split()
    predict_dict['odd'] = options.odd.split()
    predict_dict['n_tiles'] = options.tiles
    predict_dict['output'] = options.iodir
    predict_dict['overwrite'] = True
    predict_dict['gpu_id'] = options.gpu_predict

    dump_json(
        predict_dict,
        os.path.join(options.iodir, options.json_predict),
        verbose=options.verbosity>=7
        )

def dump_json(dict_to_dump, json_relpath, verbose=False):
    """
    Write JSON file and optionally print it to screen

    Arguments:
        dict_to_dump : dictionary to write to JSON
        json_relpath : path to output JSON file
        verbose : (bool) Flag to print to screen

    Returns:
        Parsed arguments object
    """

    with open(json_relpath, 'w') as outfile:
        json.dump(dict_to_dump, outfile, indent=2)

    if verbose:
        print(f"\n{os.path.basename(json_relpath)}:")
        system_call_23('cat', json_relpath)
        print('\n')

def parse_command_line():
    """
    Parse the command line.  Adapted from sxmask.py

    Arguments:
        None

    Returns:
        Parsed arguments object
    """

    parser = argparse.ArgumentParser(
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
        usage=USAGE,
        epilog=MODIFIED
    )

    parser.add_argument(
        "even",
        type=str,
        help="Even-frame micrograph stacks (if more than one, separated by spaces and enclosed in quotes)")

    parser.add_argument(
        "odd",
        type=str,
        help="Odd-frame micrograph stacks (if more than one, separated by spaces and enclosed in quotes)")

    parser.add_argument(
        "iodir",
        type=str,
        help="Input/output directory")

    parser.add_argument(
        "--model",
        type=str,
        default='model',
        help="Name of the model (in input/output directory).")

    parser.add_argument(
        "--verbosity", "-v",
        type=int,
        default=7,
        help=f"Screen verbosity [0..{MAX_VERBOSITY}]")
    """
    0: None, except errors & warnings
    1: (default) Write summary
    6: Write each file
    7: Dump JSON contents to screen
    """

    extract_info= parser.add_argument_group(
        title="Extraction-data preparation parameters",
        description="Parameters needed for 'cryoCARE_extract_train_data.py'.")
    
    extract_info.add_argument(
        "--json_extract",
        type=str,
        default='train_data_config.json',
        help="Extraction-data preparation configuration file (in input/output directory).")

    extract_info.add_argument(
        "--shape",
        type=int,
        default=72,
        help="Size of the sub-volumes used for training, should not be smaller than 64.")

    extract_info.add_argument(
        "--slices",
        type=int,
        default=1200,
        help="Number of sub-volumes extracted per tomogram.")

    extract_info.add_argument(
        "--axis",
        type=str,
        default="Y",
        help="Tilt-axis of the tomograms.")

    extract_info.add_argument(
        "--norm",
        type=int,
        default=500,
        help="Number of sub-volumes extracted per tomogram for normalization.")

    train_info= parser.add_argument_group(
        title="Training parameters",
        description="Parameters needed for 'cryoCARE_train.py'.")

    train_info.add_argument(
        "--json_train",
        type=str,
        default='train_config.json',
        help="Training configuration file (in input/output directory).")

    train_info.add_argument(
        "--epochs",
        type=int,
        default=100,
        help="Number of epochs used to train the network.")

    train_info.add_argument(
        "--steps",
        type=int,
        default=200,
        help="Number of gradient steps performed per epoch.")

    train_info.add_argument(
        "--batch",
        type=int,
        default=16,
        help="Training batch size.")

    train_info.add_argument(
        "--kernel",
        type=int,
        default=3,
        help="Convolution kernel size of the U-Net, must be an odd number.")

    train_info.add_argument(
        "--depth",
        type=int,
        default=3,
        help="Depth of the U-Net.")

    train_info.add_argument(
        "--first",
        type=int,
        default=16,
        help="Number of initial feature channels.")

    train_info.add_argument(
        "--learn",
        type=float,
        default=0.0004,
        help="Learning rate of the model training.")

    train_info.add_argument(
        "--gpus_train",
        type=str,
        default='0',
        help="ID(s) of the GPUs used for training (if more than one, separated by spaces and enclosed in quotes).")

    predict_info= parser.add_argument_group(
        title="Prediction parameters",
        description="Parameters needed for 'cryoCARE_predict.py'.")

    predict_info.add_argument(
        "--json_predict",
        type=str,
        default='predict_config.json',
        help="Prediction configuration file (in input/output directory).")

    predict_info.add_argument(
        "--tiles",
        type=int,
        default=1,
        help="Initial tiles per dimension, increased if the tiles do not fit on the GPU.")

    predict_info.add_argument(
        "--gpu_predict",
        type=int,
        default=0,
        help="ID of the GPU used for prediction (only single GPU supported).")

    return parser.parse_args()

if __name__ == "__main__":
    main()
