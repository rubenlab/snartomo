#!/usr/bin/env python

import json
import os
import argparse
import ntpath
import re
import sys
from PyQt5 import QtGui
from PyQt5 import QtWidgets
from PyQt5 import QtCore
import glob
from functools import partial
import subprocess 
import shutil
import tqdm
import inspect
try:
    import mrcfile
except ImportError:
    print("ERROR!! mrcfile must be installed")
    exit(1)
# Image creation manipulation imports
import numpy as np
import matplotlib.pyplot as plt
from PIL import Image
import copy
import webbrowser

'''
Just add this information into the general_and_tilt dictionary. From there the GUI program can use it.

Additional metadata to add
    Dose (e/A2)
    cumulative dose per micrograph (may be generated in snartomo)
    cumulative exposure time 
    designated defocus (the one defined by the data collection software)
    
    
'''

USAGE = """
  For PACEtomo target files: %s --target_files '*tgts.txt' <options>
  For SerialEM MDOC files:   %s --mdoc_files   '*.mdoc'    <options>
  
  The quotes (single or double) are required if multiple files.
  
  For more info about options, enter: %s --help
""" % ( (os.path.basename(__file__),)*3 )

MODIFIED="Modified 2023 Dec 12"
MAX_VERBOSITY=9
VIRTUAL_TARGET_FILE='All tilt series'

# Information to extract from MDOC header & for each micrograph
desired_items_general = ['PixelSpacing', 'ImageFile', 'Voltage', 'Magnification', 'FilterSlitAndLoss',
                         'UncroppedSize', 'NumSubFrames', 'ExposureTime']
desired_items_tilt = ['[ZValue', 'TiltAngle', 'DoseRate', 'SubFramePath', 'DateTime']

class MdocTreeView(QtWidgets.QMainWindow):
    """
    Outline:
        checkJson
            countData
        parseTargetsOrMdocs
        parseJson
            buildMdocLut
        buildJson
            parseTargetFile
            parseMdoc
                readCtf
                setPathAndWarn
        cleanJsonData
        countData
        buildStatMap
        buildGUI
            drawButtons
            drawTargetData
                buildStatList
                    addMicWidget
    """

    def __init__(self, options, debug=False):
        super().__init__()

        # Set parameters
        self.options= options
        self.target_files= options.target_files
        self.indir= options.in_dir
        self.mdoc_files= options.mdoc_files
        self.verbosity= options.verbose
        self.micthumb_suffix= options.micthumb_suffix
        self.ctfthumb_suffix= options.ctfthumb_suffix
        self.thumb_format= options.thumb_format
        self.imgsize= options.imgsize
        self.do_show_imgs= not options.no_imgs
        self.do_rotate= not options.no_rotate
        self.debug= options.debug
        self.json= self.options.json
        self.ctfbyts_tgts= self.options.ctfbyts_tgts
        
        # Initialize
        self.loaded_json= False
        self.list_targets= []
        self.new_targets= []
        self.temp_targets= []
        self.list_mdocs= []
        self.new_mdocs= []
        self.mdoc_lut={}  # Lookup table for full path of MDOCs
        self.data4json={}
        self.unsaved_changes= False
        self.mic2qt_lut= {}  # Lookup table for checkboxes
        self.warn_keys= ['MicThumbnail', 'CtfThumbnail', 'MoviePath', 'McorrMic', 'TiffFile', 'DenoiseMic', 'slices', 'OrigMdoc']
        self.warn_dict= {key: False for key in self.warn_keys}
        self.incinerate_subdirs={}
        self.incinerate_subdirs=  ['movie_dir','tif_dir', 'mic_dir', 'denoise_dir','ts_dir']
        self.incinerate_jsonkeys= ['MoviePath','TiffFile','McorrMic','DenoiseMic']  # 'ts_dir' will be handled separately
        self.incinerated_tsdict={}
        self.incinerated_mvlist=[]
        self.generic_text="EDIT TEXT"
        self.editable_column=3  # in column #3 (TiltAngle) and only for depth=1 (tilt series)
        self.incinerate_dir= re.sub('\$IN_DIR', self.options.in_dir, self.options.incinerate_dir)
        
        # Do stuff
        self.checkJson()
        self.parseTargetsOrMdocs()
        
        # Will give an error if no JSON, no targets, and no MDOCs
        if self.loaded_json: 
            self.parseJson()
            
        if self.new_targets or self.new_mdocs:
            self.buildJson()
            self.add_cumulative_data()
            self.cleanJsonData()
            if self.loaded_json: 
                self.countData(post_msg=' including new files')
            else:
                self.countData()
        
        if not self.options.no_gui:
            # Set column widths & formats
            self.stat_map= self.buildStatMap(debug=debug)
            
            # Initialize column list (in the order in which they will be displayed)
            self.list_columns=['Micrograph', 'CtfFind4'] + self.stat_map.keys
            
            # Draw GUI
            self.buildGUI()
        else:
            exit(0)

    def checkJson(self):
        """
        Check if JSON file exists. 
        If so, read it. 
        If not, build it.
        
        Creates:
            self.data4json : dictionary of dictionaries
        """
        
        if self.options.new:
            if not os.path.exists(self.json):
                if self.verbosity>=1 : print("Building new JSON file...")
            else:
                backup_json= self.json + '.BAK'
                if self.verbosity>=1 : print(f"Backing up JSON file '{self.json}' to '{backup_json}'...")
                shutil.copy2(self.json, backup_json)
        else:
            # Check if json is present
            if os.path.exists(self.json):
                if self.verbosity>=1 : print(f"Found JSON file: {self.json}")
                self.data4json = read_json(self.json)
                self.loaded_json = True
                self.countData(post_msg=' of old files')
        # End new-json IF-THEN
    
    def countData(self, post_msg=''):
        """
        Summarized data types encountered in JSON data
        
        Parameter:
            post_msg (str) : Text appended to summary print statement
        """
        
        # Running counters
        num_targets= 0
        num_mdocs= 0
        num_movies= 0
        mdoc_keys= ['CtfSummary',   'CentralSlice',         'CtfBytsPlot',                  'DosefitPlot']
        mdoc_tags= ['CTF summaries','tilt-series CTF plots','reconstruction central slices','dose-fitting plots']
        mic_keys= ['MoviePath',        'TiffFile',  'McorrMic',                    'MicThumbnail',         'CtfThumbnail',             'DenoiseMic']
        mic_tags= ['micrograph movies','TIFF files','motion-corrected micrographs','micrograph thumbnails','power-spectrum thumbnails','denoised micrographs']
        found_dict= {key: 0 for key in ['target_files','target_ctfplots','target_ctfplots','mdocs','selected_mdocs','MdocSelected'] + mdoc_keys + mic_keys }
        num_targets= len( self.data4json.keys() )
                              
        # Loop through target files (real or virtual)
        for curr_target in self.data4json.keys():
            if self.debug: print(f"  Target '{curr_target}' {os.path.exists(curr_target)} {'CtfBytsPlot' in self.data4json[curr_target]} {os.path.exists(self.data4json[curr_target]['CtfBytsPlot'])}")
            if os.path.exists(curr_target) : found_dict['target_files']+= 1
            if definedAndExists('CtfBytsPlot', self.data4json[curr_target]) : found_dict['target_ctfplots']+= 1
            target_data= self.data4json[curr_target]
            
            # Loop through (possible) MDOC files
            for curr_mdoc in target_data.keys():
                # Might be the CtfByTS plot
                if isinstance(target_data[curr_mdoc], list):
                    num_mdocs+= 1
                    if self.debug : print(f"    MDOC '{curr_mdoc}'")
                    if os.path.exists(curr_mdoc) : found_dict['mdocs']+= 1
                    
                    for curr_key in mdoc_keys:
                        if definedAndExists(curr_key, target_data[curr_mdoc][0]) : found_dict[curr_key]+= 1
                        
                    # Check if MDOC selection should be 0, 1, or 2
                    all_selected= True
                    none_selected= True
                    
                    # Loop through micrographs
                    for mic_idx, curr_mic in enumerate(target_data[curr_mdoc][1]):
                        num_movies+= 1
                        for curr_key in mic_keys:
                            if definedAndExists(curr_key, target_data[curr_mdoc][1][curr_mic]) : found_dict[curr_key]+= 1
                            
                        if 'MicSelected' in target_data[curr_mdoc][1][curr_mic]:
                            mic_selected= target_data[curr_mdoc][1][curr_mic]['MicSelected']
                            if mic_selected:     none_selected= False
                            if not mic_selected: all_selected= False
                        else: 
                            self.data4json[curr_target][curr_mdoc][1][curr_mic]['MicSelected'] = True
                    # End micrograph loop
                    
                    # Set MDOC selection value
                    if 'MdocSelected' in target_data[curr_mdoc][0]:
                        if target_data[curr_mdoc][0]['MdocSelected'] > 0 : found_dict['MdocSelected']+= 1
                    else:
                        if all_selected:
                            self.data4json[curr_target][curr_mdoc][0]['MdocSelected'] = 2
                        else:
                            if none_selected: 
                                self.data4json[curr_target][curr_mdoc][0]['MdocSelected'] = 0
                            else:
                                self.data4json[curr_target][curr_mdoc][0]['MdocSelected'] = 1
                    if self.debug: print(f"230 {os.path.basename(curr_mdoc)}: MdocSelected={self.data4json[curr_target][curr_mdoc][0]['MdocSelected']}")
                # End MDOC IF-THEN
            # End MDOC loop
        # End target loop
        
        # If no target files, there will be a virtual one
        if found_dict['target_files']==0 : found_dict['target_files']=1
        
        # Print summary
        if self.verbosity>= 4:
            print()
            print(f"Input summary{post_msg}:")
            print(f"  Found {found_dict['target_files']}/{num_targets} target files (real or virtual)")
            print(f"  Found {found_dict['target_ctfplots']}/{len( self.data4json.keys() )} target CTF scatter plots")
            print(f"  Found {found_dict['mdocs']}/{num_mdocs} MDOC files")
            print(f"  Found {found_dict['MdocSelected']}/{found_dict['mdocs']} selected tilt series")
            
            # Iterate through two lists (['CTF summaries','tilt-series CTF plots','reconstruction central slices','dose-fitting plots'])
            for curr_key, curr_tag in zip(mdoc_keys, mdoc_tags):
                print(f"  Found {found_dict[curr_key]}/{found_dict['mdocs']} {curr_tag}")
            
            # Iterate through two lists (['micrograph movies','TIFF files','motion-corrected micrographs','micrograph thumbnails','power-spectrum thumbnails','denoised micrographs'])
            for curr_key, curr_tag in zip(mic_keys, mic_tags):
                print(f"  Found {found_dict[curr_key]}/{num_movies} {curr_tag}")
            print()
        
    def parseTargetsOrMdocs(self):
        """
        Reads either target files or MDOC files
        
        Creates:
            self.new_targets : new target files which actually exist
            self.new_mdocs
            self.temp_targets : dummy target file in case of no real ones
        """
        
        if self.target_files: 
            self.new_targets= expandInputFiles(self.target_files)
        
        if self.mdoc_files: 
            self.new_mdocs= expandInputFiles(self.mdoc_files, extension='.mdoc')
            
            # Sanity check for top-level input directory
            test_indir= None
            for curr_mdoc in self.new_mdocs:
                curr_topdir= re.sub(os.getcwd() + os.path.sep, '', os.path.abspath(curr_mdoc)).split(os.path.sep)[0]
                
                if not test_indir:
                    test_indir= curr_topdir
                else:
                    if curr_topdir != test_indir:
                        print(f"ERROR!! It is assumed the MDOCs have the same top-level directory, e.g., '{test_indir}'!")
                        exit(6)
                
            if test_indir != self.options.in_dir:
                if self.debug: print(f"DEBUG: Updating '--indir' from '{self.options.in_dir}' to '{test_indir}'")
                self.options.in_dir= test_indir
        
        # Sanity check
        if self.target_files and self.mdoc_files:
            print(f"\nERROR!! Can't specify both target files ({len(self.new_targets)}) and MDOC files ({len(self.new_mdocs)}) Exiting...\n")
            exit(7)
        if not self.target_files and not self.mdoc_files and not self.loaded_json:
            print(f"\nERROR!! Have to specify either target file(s) or MDOC file(s)! Exiting...\n")
            exit(8)
        elif len(self.new_targets)==0 and len(self.new_mdocs)==0 and not self.loaded_json:
            print(f"\nERROR!! List of target files and MDOC files ('{self.target_files or self.mdoc_files}') are both empty! Please check filenames...\n")
            exit(9)
        
        if self.verbosity>=2 and len(self.new_targets)>=1: print(f"Found {len(self.new_targets)} targets file(s)")
        if self.verbosity>=2 and len(self.new_mdocs)  >=1: print(f"Found {len(self.new_mdocs)} MDOC file(s)")
        
        # Loop through targets or dummy list
        if len(self.new_targets) == 0: 
            if len(self.new_mdocs) >= 1: 
                self.new_targets = [VIRTUAL_TARGET_FILE]
                self.temp_targets = [VIRTUAL_TARGET_FILE]
        else: 
            self.temp_targets = self.new_targets
            
        if self.debug: print(f"310 self.temp_targets ({len(self.temp_targets)}) {self.temp_targets}")
        
    def parseJson(self):
        """
        Extract metadata out of JSON file
        
        Creates:
            ts_dir
            ctfbyts_tgts
            temp_targets : dummy target file in case of no real ones
            mdoc_lut : from the basename, points to the full path of an MDOC
            list_mdocs : if no target file
        """
        
        self.ts_dir=       None
        self.ctfbyts_tgts= re.sub('\$IN_DIR', self.options.in_dir, self.options.ctfbyts_tgts)
        
        self.temp_targets= list( self.data4json.keys() )  # .keys() is not a list and thus cannot be directly subscripted

        if self.debug: 
            print(f"330 self.temp_targets ({len(self.temp_targets)}) {self.temp_targets}")
        
        for curr_target in self.temp_targets:
            if os.path.exists(curr_target) : self.list_targets.append(curr_target)
        
        if len(self.list_targets) == 0:
            self.buildMdocLut(curr_target, self.data4json[ self.temp_targets[0] ])
        else:
            # Loop through targets
            for curr_target in self.temp_targets:
                self.buildMdocLut(curr_target, self.data4json[curr_target])
                
    def buildMdocLut(self, curr_target, mdoc_dict):
        """
        Associates basename of MDOC with full path
        """
        
        # Loop through potential MDOCs
        for curr_mdoc in mdoc_dict.keys():
            if isinstance(mdoc_dict[curr_mdoc], list):
                self.list_mdocs.append(curr_mdoc)
                self.mdoc_lut[os.path.basename(curr_mdoc)] = curr_mdoc
                
                # Sanity check
                tomo_dir= os.path.basename( os.path.dirname(curr_mdoc) )
                if not os.path.basename(curr_mdoc).startswith(tomo_dir):
                    print(f"\nERROR!! It is assumed that the MDOC parent directory ({tomo_dir}) is part of the name of the MDOC ({curr_mdoc})!\n")
                    exit(3)
                ts_dir= re.sub(tomo_dir, '$MDOC_STEM', os.path.dirname(curr_mdoc))
                
                if not self.ts_dir:
                    self.ts_dir= ts_dir
                else:
                    if ts_dir != self.ts_dir:
                        print(f"ERROR!! It is assumed that the tilt series directories have the same parent directory, e.g., '{self.ts_dir}'!")
                        exit(4)
            elif curr_mdoc == 'CtfBytsPlot':
                ctfbyts_tgts= re.sub(os.path.splitext(curr_target)[0], '', os.path.splitext(mdoc_dict[curr_mdoc])[0]) + "*"
                if not os.path.basename(ctfbyts_tgts).rstrip("*").startswith( os.path.basename(self.ctfbyts_tgts.split('*')[0]) ):
                    print(f"ERROR!! It is assumed the CTF plots have the same pattern, e.g., '{ctfbyts_tgts}' != '{self.ctfbyts_tgts}'!")
                    exit(5)
                                
    def buildJson(self):
        """
        Build metadata from sources other than a JSON file
        
        Creates:
            ts_dir
            ctfbyts_tgts
            mdoc_lut
            data4json
        """
        
        # Perform some substitutions
        assert self.options.in_dir != '', "ERROR!! Argument '--in_dir' cannot be empty!"
        assert os.path.isdir(self.options.in_dir), f"ERROR!! Argument '--in_dir={self.options.in_dir}' does not exist!"
        self.ts_dir=       re.sub('\$IN_DIR', self.options.in_dir, self.options.ts_dir)
        self.ctfbyts_tgts= re.sub('\$IN_DIR', self.options.in_dir, self.options.ctfbyts_tgts)
        
        # Loop through target files
        for tgt_idx in range( len(self.new_targets) ):
            curr_target=self.new_targets[tgt_idx]
            curr_list_mdocs=[]
            
            if curr_target != VIRTUAL_TARGET_FILE:
                curr_list_mdocs= self.parseTargetFile(
                    curr_target, 
                    ts_dir=self.ts_dir, 
                    tgt_idx=tgt_idx+1, 
                    msg='Building JSON data for target ')
                target_base=os.path.basename(curr_target)
            else:
                curr_list_mdocs=self.new_mdocs
                target_base=''
            
            # Initialize row for target file if not already present
            if not curr_target in self.data4json:
                self.data4json[curr_target] = {}
            else:
                if self.debug: print(f"343 data4json already has '{curr_target}'")
            
            # Try to find CtfByTS plots
            if self.do_show_imgs:
                ctfbyts_plot= self.findCtfbytsPlots(target_base, debug=self.debug)
                if ctfbyts_plot:
                    self.data4json[curr_target]['CtfBytsPlot'] = ctfbyts_plot
                else:
                    if self.debug : print(f"buildJson Didn't find ctfbyts_plot '{ctfbyts_plot}' '{target_base}'")
            
            # Loop through tilt series
            for curr_mdoc in curr_list_mdocs:
                self.parseMdoc(curr_mdoc, curr_target)
                
                # Add MDOC, if necessary
                if not curr_mdoc in self.list_mdocs: 
                    self.list_mdocs.append(curr_mdoc)
                    self.mdoc_lut[os.path.basename(curr_mdoc)] = curr_mdoc
            # End MDOC loop
            
            if not curr_target in self.temp_targets: self.temp_targets.append(curr_target)
        # End target loop

    '''
    START OF CUMULATIVE DATA FUNCTION STUFF :)
    '''
    def add_cumulative_data(self):
        '''
        BUILD CUMULATIVE STUFF HERE!
            - Get MDOC file locations from mdoc_lut dictionary
            - Calculate cumulative exposure & dose for original mdoc file
            - Then transfer values to respective tilts via subframepath identifier
        '''
        
        # Create dictionary of original mdoc files (here assumed as the mdoc-path + '.orig' appended at the end)
        self.mdoc_origs = {}
        for mdoc in self.mdoc_lut.keys():
            self.mdoc_origs[mdoc] = {}
            ###self.mdoc_origs[mdoc]['FilePath'] = self.mdoc_lut[mdoc] + '.orig'  # TODO: hardwired path
            
            # Stem is everything up to first dot
            orig_base= os.path.basename(self.mdoc_lut[mdoc]).split('.')[0] + self.options.orig_mdoc_suffix
            mdoc_dir= os.path.dirname(self.mdoc_lut[mdoc])
            self.mdoc_origs[mdoc]['FilePath'] = os.path.join(mdoc_dir, orig_base)
        
        # For each mdoc in the original mdoc dictionary, calculate cumulative exposure and dose
        for mdoc_orig in self.mdoc_origs.keys():
            orig_path= self.mdoc_origs[mdoc_orig]['FilePath']
            
            if os.path.exists(orig_path):
                # Read general & tilt information for original mdoc
                general, tilt = readMdocHeader(orig_path)
                
                # Calculate exposure and dose based on tilt information available in the original mdoc, save into dictionary
                path_exposure_dose = self.get_cumulative_data(tilt)
                self.mdoc_origs[mdoc_orig]['CumulativeData'] = path_exposure_dose
            else:
                if not self.warn_dict['OrigMdoc']:
                    if self.verbosity >= 1: print(f"WARNING! Original MDOC not found for '{os.path.basename(mdoc_orig)}', setting dose/exposure to -1")
                    self.warn_dict['OrigMdoc'] = True
        
        # Transfer cumulative values to JSON
        for targets_file in self.data4json.keys():
            for mdoc in self.data4json[targets_file].keys():
                if mdoc == 'CtfBytsPlot':
                    continue
                for tilt_num in self.data4json[targets_file][mdoc][1].keys():
                    subframepath = self.data4json[targets_file][mdoc][1][tilt_num]['SubFramePath']
                    mdoc_base= os.path.basename(mdoc)  # mdoc.split('/')[-1]
                    self.data4json[targets_file][mdoc][1][tilt_num]['CumExposure'] = -1
                    self.data4json[targets_file][mdoc][1][tilt_num]['CumDose'] = -1
                    if 'CumulativeData' in self.mdoc_origs[mdoc_base]:
                        if subframepath in self.mdoc_origs[mdoc_base]['CumulativeData']:
                            cum_exposure, cum_dose = self.mdoc_origs[mdoc_base]['CumulativeData'][subframepath]
                        
                            # Save cumulative exposure/dose into data4json
                            self.data4json[targets_file][mdoc][1][tilt_num]['CumExposure'] = cum_exposure
                            self.data4json[targets_file][mdoc][1][tilt_num]['CumDose'] = cum_dose
                            
    def get_cumulative_data(self, tilt_data):
        '''
        Args:
            tilt_data: List of z_blocks from parsing an .mdoc file.

        Returns:
            path_dose_exposure: Dictionary, where each key is the absolute path of an .eer file and the item is a list of two numbers: 
                1) accumulated exposure time (read from the .mdoc z_blocks) and 
                2) accumulated dose. 
              
            If the dose per image could not be calculated (because of a missing motioncor-frame.txt file for example), it will be set to -1.
        '''
        # Define cumulative data dictionary
        path_dose_exposure = {}
        
        # Try to get dose per image
        dose_per_image = self.get_dose_per_image()
        cum_dose = 0
        cum_exposure = 0
        
        # Loop through each tilt and calculate cumulative exposure time and dosage (if possible)
        for tilt_information in tilt_data:
            frame_path = ''
            for line in tilt_information:
                if "SubFramePath" in line:
                    # Saves frame path
                    frame_path = line.strip().split()[2]
                elif "ExposureTime" in line:
                    # Saves exposure time
                    exposure_time = float(line.strip().split()[2])
            
            # Create entry in data dictionary for each tilt and add cumulative exposure first
            cum_exposure += exposure_time
            path_dose_exposure[frame_path] = [cum_exposure]
            
            # If cumulative dose was found, add cumulative dose to data dictionary, otherwise add -1
            if cum_dose == -1:
                path_dose_exposure[frame_path].append(-1)
            else:
                cum_dose += dose_per_image
                path_dose_exposure[frame_path].append(cum_dose)
            
            ## print(frame_path + ' has accumulated dose of ' + str(cum_dose) + ' e⁻/A² and exposure of ' + str(
            ##    cum_exposure) + ' s.')
        
        return path_dose_exposure

    def get_dose_per_image(self):
        '''
        Returns:
            Dose per image calculated from found motioncor-frame.txt file.

            Tries to get the name of the motioncor-frame file from the SNARTomo settings file
            (should be saved in <SNARTomoDir>/Logs/settings.txt). The motioncor-frame file is assumed to be saved in the
            same directory from which SNARTomo was originally executed.

            Will return -1 if it couldn't read a frames file.
        '''
        
        dose_per_image= -1  # default
        
        if self.options.dose:
            dose_per_image = self.options.dose
        
        else:
            # Find name of motioncor frames file
            if os.path.exists(self.options.frame_file):
                frames_file= self.options.frame_file  # "motioncor-frame.txt"
            else:
                # Read settings.txt file (saved under SNARTomo/settings.txt
                settings_file= re.sub('\$IN_DIR', self.options.in_dir, self.options.settings)  #### os.path.join(self.indir, 'settings.txt')
                
                if os.path.exists(settings_file):
                    with open(settings_file) as settings_fin:
                        for line in settings_fin:
                            if "--frame_file" in line:
                                #print(frames_file)
                                frames_file = line.strip().split(' ')[1].replace('\t', '')
                                #print('Found frames file (' + frames_file + ') in ' + settings_file + '.')
            # END frames-file IF-THEN
            
            if os.path.exists(frames_file):
                # read frame file and calculate dose per image
                with open(frames_file) as frame_fin:
                    frames, grouping, dose_per_frame = frame_fin.readline().split()
                    dose_per_image = float(frames) * float(dose_per_frame)
                
                ##print("Calculated the dose per image based on found motioncor-frame.txt file. Setting it to " + str(
                ##    dose_per_image) + ' e⁻/A².')
        
        return dose_per_image

    '''
    END OF CUMULATIVE DATA FUNCTION STUFF :(
    '''

    def parseTargetFile(self, target_file, ts_dir=None, tgt_idx=None, msg='Parsing target file '):
        """
        Within a target file, finds MDOC files
        
        Parameters:
            target_file : target file
            ts_dir (optional) : directory in which to look for MDOC
            tgt_idx : counter for target files for display
            
        Returns:
            list of MDOCs
        """
        
        if self.verbosity>=2: 
            msg+=target_file
            if tgt_idx:
                msg+= f" ({tgt_idx}/{len(self.temp_targets)})"
            print(msg + '...')

        # Grep target file for 'tsfile'
        result= grep('tsfile', target_file)
        curr_list_mdocs=[]

        for line in result:
            mdoc_stem= re.sub( '.mrc', '', line.split('=')[1].strip() )
            mdoc_base= mdoc_stem + '.mrc.mdoc'

            # If MDOC directory specified, then use it
            if ts_dir:
                mdoc_path= os.path.join(
                    re.sub('\$MDOC_STEM', mdoc_stem, ts_dir),
                    mdoc_base
                    )
            
            # If MDOC directory not specified, use directory of target file
            else:
                mdoc_path= os.path.join(
                    os.path.dirname(target_file),
                    mdoc_base
                    )

            if os.path.exists(mdoc_path):
                curr_list_mdocs.append(mdoc_path)
                if self.verbosity>=7: print(f"  Found MDOC file: {mdoc_path}")
            else:
                print(f"  WARNING! Couldn't find MDOC file: {mdoc_path}")
        # End line loop
        
        return curr_list_mdocs
    
    def parseMdoc(self, curr_mdoc, curr_target):
        """
        Extracts information from for each tilt series:
            MDOC file
            defocus info
            image paths
            CTF and dose-fitting plots
        
        Parameters:
            curr_mdoc : MDOC file
            curr_target : target file (real or virtual)
        """
        
        # Strip extensions from MDOC
        mdoc_base= re.sub( '.mrc.mdoc$', '', os.path.basename(curr_mdoc) )
        general_and_tilt = read_mdoc(curr_mdoc)
        
        # Read CTF information from summary file
        curr_ctf_summary= os.path.join(os.path.dirname(curr_mdoc), self.options.ctf_summary)
        general_and_tilt[1] = self.readCtf(general_and_tilt[1], curr_ctf_summary)
        if os.path.exists(curr_ctf_summary) : general_and_tilt[0]['CtfSummary'] = curr_ctf_summary
        
        # Get central-slice JPEG(s)
        slice_jpg= getLatest(
            mdoc_base + '*' + self.options.slice_jpg, 
            os.path.join(os.path.dirname(curr_mdoc))
            )
        
        if os.path.exists(curr_ctf_summary) : 
            general_and_tilt[0]['CentralSlice'] = slice_jpg
        else:
            if self.do_show_imgs and self.verbosity>=1 and not self.warn_dict['slices']: 
                print(f"  WARNING! Central slice '{slice_jpg}' not found, skipping...")
                self.warn_dict['slices']= True
        
        # Extract tilt angles
        angles_list= [float(general_and_tilt[1][k]['TiltAngle']) for k in general_and_tilt[1].keys()]
        
        # Sort by angle (Adapted from https://stackoverflow.com/a/7851166)
        sorted_idx_list = [i for i, x in sorted(enumerate(angles_list), key=lambda x: x[1])]

        sorted_angles_list=[]
        for angle_idx, curr_angle in enumerate(angles_list):
            sorted_angles_list.append(list( general_and_tilt[1].keys() )[ sorted_idx_list[angle_idx] ])  # .keys() is not a list and thus cannot be directly subscripted

        # Loop through micrographs
        for sorted_idx, tilt_key in enumerate(sorted_angles_list):
            tilt_idx= sorted_idx_list[sorted_idx]

            # Generate paths
            movie_base= ntpath.basename(general_and_tilt[1][tilt_key]['SubFramePath'])
            movie_path= os.path.join(self.options.movie_dir, movie_base)
            mic_path= os.path.join(
                re.sub('\$IN_DIR', self.options.in_dir, self.options.mic_dir), 
                os.path.splitext(movie_base)[0] + self.options.mic_pattern
                )
            tiff_path= os.path.join(
                re.sub('\$IN_DIR', self.options.in_dir, self.options.tif_dir), 
                os.path.splitext(movie_base)[0] + '.tif'
                )
            curr_micthumb_dir= os.path.join(
                os.path.dirname(curr_mdoc),
                self.options.micthumb_dir
                )
            thumbnail_idx='.' + str(sorted_idx).zfill(3) + '.'  # pad to 3 digits
            mic_thumb_path= os.path.join(
                curr_micthumb_dir,
                mdoc_base + self.micthumb_suffix + thumbnail_idx + self.thumb_format
                )

            ctf_thumb_base= mdoc_base + self.ctfthumb_suffix + thumbnail_idx + self.thumb_format
            ctf_thumb_path=os.path.join(curr_micthumb_dir, ctf_thumb_base)
            denoise_path= os.path.join(
                re.sub('\$IN_DIR', self.options.in_dir, self.options.denoise_dir), 
                os.path.splitext(movie_base)[0] + self.options.mic_pattern
                )
            
            # Add to dictionary
            general_and_tilt[1][tilt_key] = self.setPathAndWarn(movie_path, general_and_tilt[1][tilt_key], 'MoviePath', 'Micrograph movie')
            general_and_tilt[1][tilt_key] = self.setPathAndWarn(mic_path, general_and_tilt[1][tilt_key], 'McorrMic', 'Motion-corrected micrograph')
            general_and_tilt[1][tilt_key] = self.setPathAndWarn(tiff_path, general_and_tilt[1][tilt_key], 'TiffFile', 'Compressed TIFF')
            general_and_tilt[1][tilt_key] = self.setPathAndWarn(mic_thumb_path, general_and_tilt[1][tilt_key], 'MicThumbnail', 'Micrograph thumbnail')

            if self.warn_dict['MicThumbnail'] == True:
                try:
                    micrograph_data = open_mrc(mic_path)
                    bin16_micrograph_data = bin_nparray(micrograph_data, 16)
                    #display_nparray(bin16_micrograph_data)
                    save_as_image(bin16_micrograph_data, mic_thumb_path)
                    if self.verbosity >= 6:
                        print('Created thumbnail from motion-corrected micrograph. Saved it under ' + mic_thumb_path + '.')
                except:
                    print('Could not create thumbnail image. Make sure motioncorrected .mrcs exist!')

            general_and_tilt[1][tilt_key] = self.setPathAndWarn(ctf_thumb_path, general_and_tilt[1][tilt_key], 'CtfThumbnail', 'Power-spectrum image')
            general_and_tilt[1][tilt_key] = self.setPathAndWarn(denoise_path, general_and_tilt[1][tilt_key], 'DenoiseMic', 'Denoised micrograph')
            
            # Set selection flag (if starting from scratch, starts as 'True')
            general_and_tilt[1][tilt_key]['MicSelected'] = True
            
            if self.verbosity==8: print(f"  {sorted_idx}: ZValue {tilt_idx}, {mic_thumb_path}, {ctf_thumb_path}, {ntpath.basename(general_and_tilt[1][tilt_key]['SubFramePath'])}")
        # End micrograph loop
        
        ctfbyts_plot= getLatest( self.options.ctfbyts_1ts, os.path.dirname(curr_mdoc) )
        dosefit_plot= getLatest( self.options.dosefit_plot, os.path.dirname(curr_mdoc) )
            
        if ctfbyts_plot: general_and_tilt[0]['CtfBytsPlot'] = ctfbyts_plot
        if dosefit_plot: general_and_tilt[0]['DosefitPlot'] = dosefit_plot
        
        if os.path.basename(curr_mdoc) in self.mdoc_lut:
            if curr_mdoc in self.data4json[curr_target].keys():
                print(f"WARNING! '{curr_mdoc}' already present in '{self.json}'")
                print(f"  Use '--new' flag to force overwrite")
        else:
            # Remember full path of MDOC file
            self.mdoc_lut[os.path.basename(curr_mdoc)] = curr_mdoc
            
            # Append data to running list to be written to JSON
            self.data4json[curr_target][curr_mdoc] = general_and_tilt
        # End found-mdoc IF-THEN
        
    def readCtf(self, json_data, summary_file):
        """
        Parses CTFFIND info
        
        Parameters:
            json_data (dict) : metadata which will be eventually written to JSON file
            summary_file (str) : input summary file with CTFFIND data for each micrograph in tilt series
        
        Returns:
            updated metadata which will be eventually written to JSON file
        """
        
        for json_key in json_data.keys():
            search_string= os.path.splitext(ntpath.basename( json_data[json_key]['SubFramePath']) )[0]
            
            # The CTF summary is appended to, so pick only the last match
            search_result= grep(search_string, summary_file)[-1].split()
            avg_df= -1*(float(search_result[2]) + float(search_result[3]))/2
            res_fit= float(search_result[7])
            json_data[json_key]['CtfFind4'] = avg_df
            json_data[json_key]['MaxRes'] = res_fit
        # End tilt-series loop
        
        return json_data
    
    def setPathAndWarn(self, curr_path, curr_dict, curr_key, curr_type):
        """
        1) Checks path 
        2) Sets dictionary if file exists 
        3) Prints warning if absent
        
        Warns only once.
        
        Parameters:
            curr_path : path to test
            curr_dict : dictionary to update
            curr_key : key to modify
            curr_type (str) : description to print upon warning
            
        Returns:
            Updated dictionary
        """
        
        if os.path.exists(curr_path):
            curr_dict[curr_key] = curr_path
            if self.verbosity>=6:
                print(f" HOORAY! {curr_type} '{curr_path}' found :)")
        else:
            if not self.warn_dict[curr_key] and self.verbosity>=6:
                print(f"  WARNING! {curr_type} '{curr_path}' not found")
                self.warn_dict[curr_key] = True
                
        return curr_dict
    
    def cleanJsonData(self):
        """
        If there are targets without associated MDOCs, then remove them
        """
        
        data_copy= copy.deepcopy(self.data4json)  # Can't modify dict while iterating through it
        
        # Loop through targets
        for curr_target in data_copy:
            keep_target= False
            
            # Loop through MDOC candidates
            for curr_mdoc in data_copy[curr_target]:
                if isinstance(data_copy[curr_target][curr_mdoc], list):
                    keep_target= True
                else:
                    if curr_mdoc != 'CtfBytsPlot':
                        print(f"ERROR!! Unknown entry type '{curr_mdoc}' in target '{curr_target}'! Exiting... ")
                        exit(16)
        
            # Remove target
            if keep_target == False:
                if self.verbosity >= 1: 
                    if curr_target == VIRTUAL_TARGET_FILE:
                        print("MDOC files already accounted for, ignoring new ones...")
                    else:
                        print(f"Removing redundant/empty target '{curr_target}'")
                del self.data4json[curr_target]
                self.temp_targets.remove(curr_target)
                if curr_target in self.new_targets : self.new_targets.remove(curr_target)
                if self.debug:
                    print(f"418 data_copy.keys() ({len(data_copy.keys())} {data_copy.keys()})")
                    print(f"419 self.list_targets ({len(self.list_targets)}) {self.list_targets})")
                    print(f"420 self.new_targets ({len(self.new_targets)}) {self.new_targets})")
                    print(f"420 self.temp_targets ({len(self.temp_targets)}) {self.temp_targets})")
        
        # Save to JSON
        save_json(self.data4json, filename=self.json, verbosity=self.verbosity)
        if self.verbosity >= 9: 
            print(f"\n{os.path.basename(self.json)}:")
            system_call_23('cat', self.json)
            print()
        
    def buildStatMap(self, debug=False):
        """
        Set up stat columns in the order in which they will be displayed.
        The "Micrograph" and "CtfFind4" columns will be displayed first and second, respectively.
        """
        
        self.default_width= 80
        stat_map=MdocColumnAttrs()
        stat_map.add_column('DoseRate',      self.default_width, '4.2f', QtCore.Qt.AlignCenter)
        stat_map.add_column('TiltAngle',     self.default_width, '5.2f')
        stat_map.add_column('MaxRes',        self.default_width, '6.2f')
        stat_map.add_column('DateTime',      175,                'str' )
        
        if debug: print(f"DEBUG: The following data ('stat_map.keys') will be displayed: {stat_map.keys}\n")
        
        return stat_map
        
    def buildGUI(self):
        """
        Draws Qt treeview window
        
        Create:
            self.tree_view
        """
        
        self.setWindowTitle('SNARTomo Heatwave')  # Set the window title
        win_height= 864
        if self.do_show_imgs:
            win_width= 2*self.imgsize + 1024
            self.setGeometry(0, 18, win_width, win_height)  # Set window size and position
        else:
            self.setGeometry(0, 18, 1140, win_height)

        # Create a QWidget as the central widget of the main window
        central_widget= QtWidgets.QWidget(self)
        self.setCentralWidget(central_widget)

        # Create a QVBoxLayout to hold the QTreeView
        box_layout= QtWidgets.QVBoxLayout(central_widget)
        button_layout= self.drawButtons()
        box_layout.addLayout(button_layout)

        # Create a QTreeView
        self.tree_view = QtWidgets.QTreeView()
        box_layout.addWidget(self.tree_view)
        
        # Menus (Adapted from http://pharma-sas.com/common-manipulation-of-qtreeview-using-pyqt5)
        self.tree_view.setContextMenuPolicy(QtCore.Qt.CustomContextMenu)
        self.tree_view.customContextMenuRequested.connect(self.openMenu)

        # (I don't know what these two lines do)
        selmod = self.tree_view.selectionModel()
        self.tree_view.setSelectionBehavior(QtWidgets.QAbstractItemView.SelectRows)

        self.item_model= QtGui.QStandardItemModel()
        self.item_model.setHorizontalHeaderLabels(self.list_columns)
        self.item_model.itemChanged.connect(self.item_changed)

        self.tree_view.setModel(self.item_model)
        
        # Allow editing
        self.line_edit= LineEditDelegate(column=self.editable_column)
        self.tree_view.setItemDelegate(self.line_edit)

        # Set widths of columns with images
        if self.do_show_imgs:
            col_width= self.imgsize+350
            self.tree_view.setColumnWidth(0, col_width)
            self.tree_view.setColumnWidth(1, self.imgsize + self.default_width)
            self.tree_view.setColumnWidth(2, self.imgsize)
        else:
            self.tree_view.setColumnWidth(0, 350)
            self.tree_view.setColumnWidth(1, self.default_width)
            self.tree_view.setColumnWidth(2, self.default_width)

        # Set width of other columns
        for stat_idx, curr_stat in enumerate(self.stat_map.keys):
            self.tree_view.setColumnWidth(stat_idx+3, self.stat_map.column_dict[curr_stat].width)

        self.warn_dict['slices']= False
        did_warn_ctfplot= False
        
        # Loop through target files
        for tgt_idx, curr_target in enumerate(self.temp_targets):
            self.drawTargetData(curr_target)

        if self.options.expand: 
            self.tree_view.expandAll()
        else: 
            self.tree_view.expandToDepth(0)

        ## select last row (I don't know what this does)
        # selmod = self.tree_view.selectionModel()

        self.show()

    def drawButtons(self):
        """
        Draws buttons and sets shortcuts
        """
        
        button_layout= QtWidgets.QHBoxLayout()
        
        save_button= QtWidgets.QPushButton('Save JSON')
        save_button.setSizePolicy(QtWidgets.QSizePolicy.Fixed, QtWidgets.QSizePolicy.Fixed)
        save_button.clicked.connect(self.saveSelection)
        save_shortcut= QtWidgets.QShortcut(QtGui.QKeySequence("Ctrl+s"), self)
        save_shortcut.activated.connect(self.saveSelection)
        button_layout.addWidget(save_button)
        
        restack_button= QtWidgets.QPushButton('Restack micrographs')
        restack_button.setToolTip("Remove deselected micrographs from stacks and MDOCs")
        restack_button.setSizePolicy(QtWidgets.QSizePolicy.Fixed, QtWidgets.QSizePolicy.Fixed)
        restack_button.clicked.connect(self.restackDeselected)
        restack_shortcut= QtWidgets.QShortcut(QtGui.QKeySequence("Ctrl+r"), self)
        restack_shortcut.activated.connect(self.restackDeselected)
        button_layout.addWidget(restack_button)
        
        incinerate_button= QtWidgets.QPushButton('Incinerate tilt series')
        incinerate_button.setToolTip("Purge data from deselected tilt series")
        incinerate_button.setStyleSheet("background-color: #ff3333")
        incinerate_button.setSizePolicy(QtWidgets.QSizePolicy.Fixed, QtWidgets.QSizePolicy.Fixed)
        incinerate_button.clicked.connect(self.incinerateData)
        incinerate_shortcut= QtWidgets.QShortcut(QtGui.QKeySequence("Ctrl+i"), self)
        incinerate_shortcut.activated.connect(self.incinerateData)
        button_layout.addWidget(incinerate_button)
        
        unincinerate_button= QtWidgets.QPushButton('Unincinerate files')
        unincinerate_button.setToolTip("Restore data inincerated <b>during this session</b>. You will need to re-add the corresponding MDOC files for your next session.")
        unincinerate_button.setSizePolicy(QtWidgets.QSizePolicy.Fixed, QtWidgets.QSizePolicy.Fixed)
        unincinerate_button.clicked.connect(self.undoIncineration)
        unincinerate_shortcut= QtWidgets.QShortcut(QtGui.QKeySequence("Ctrl+u"), self)
        unincinerate_shortcut.activated.connect(self.undoIncineration)
        button_layout.addWidget(unincinerate_button)
        
        button_layout.addSpacerItem(QtWidgets.QSpacerItem(0, 0, QtWidgets.QSizePolicy.Expanding, QtWidgets.QSizePolicy.Minimum))
        
        # Help menu
        help_button= QtWidgets.QPushButton('Help')
        help_menu= QtWidgets.QMenu(help_button)
        
        # Shortcut menu item
        shortcut_action= QtWidgets.QAction('Keyboard shortcuts', self)
        help_menu.addAction(shortcut_action)
        shortcut_action.triggered.connect(self.showShortcuts)
        
        # WWW-help menu item
        www_action= QtWidgets.QAction('WWW help', self)
        help_menu.addAction(www_action)
        www_action.triggered.connect(self.openWWW)
        
        # About menu item
        about_action= QtWidgets.QAction('About Heatwave', self)
        help_menu.addAction(about_action)
        about_action.triggered.connect(self.showAbout)
        
        button_layout.addWidget(help_button)
        help_button.clicked.connect( lambda: self.showPopupMenu(help_button, help_menu) )
        
        quit_button= QtWidgets.QPushButton('Quit')
        quit_button.setSizePolicy(QtWidgets.QSizePolicy.Fixed, QtWidgets.QSizePolicy.Fixed)
        quit_button.clicked.connect(self.closeEvent)
        quit_shortcut= QtWidgets.QShortcut(QtGui.QKeySequence("Ctrl+q"), self)
        quit_shortcut.activated.connect(self.closeEvent)
        button_layout.addWidget(quit_button)
        
        test_shortcut= QtWidgets.QShortcut(QtGui.QKeySequence("Ctrl+t"), self)
        test_shortcut.activated.connect(self.testFunction)
        
        return button_layout
    
    def showPopupMenu(self, widget, menu):
        # Get the global position of the button
        pos = widget.mapToGlobal(widget.rect().bottomLeft())

        # Show the menu at the adjusted position
        menu.exec_(pos)

    def showShortcuts(self):
        msg= "Ctrl+s\tSave JSON\n"
        msg+="Ctrl+r\tRestack micrographs\n"
        msg+="Ctrl+i\tIncinerate tilt series\n"
        msg+="Ctrl+u\tUnincinerate files\n"
        msg+="Ctrl+q\tQuit\n"
        shortcut_box= QtWidgets.QMessageBox()
        shortcut_box.setWindowTitle("Shortcuts")
        shortcut_box.setText(msg)
        shortcut_box.setStandardButtons(QtWidgets.QMessageBox.Ok)
        shortcut_box.exec_()
    
    def openWWW(self):
        webbrowser.open('https://github.com/rubenlab/snartomo/wiki/SNARTomoHeatwave')
    
    def showAbout(self):
        QtWidgets.QMessageBox.information(
            self, 
            "About", 
            f"SNARTomo Heatwave\n{MODIFIED} ",
            QtWidgets.QMessageBox.Ok
            )
    
    def drawTargetData(self, curr_target):
        """
        Draws data in GUI for a given target file (real or virtual)
        
        Parameters:
            curr_target : target file
        """
        
        if curr_target != VIRTUAL_TARGET_FILE:
            curr_list_mdocs=[]
            for potential_mdoc in self.data4json[curr_target].keys():
                if isinstance(self.data4json[curr_target][potential_mdoc], list):
                    curr_list_mdocs.append(potential_mdoc)
            target_base=os.path.basename(curr_target)
            target_item = QtGui.QStandardItem(target_base)
        else:
            curr_list_mdocs=self.list_mdocs
            target_item = QtGui.QStandardItem(curr_target)
            target_base=''
        
        if self.debug: print(f"860 curr_list_mdocs {len(curr_list_mdocs)} {curr_list_mdocs}")
        
        # Initialize row for target file (real or fake) 
        target_item_list= [target_item]
        
        # Try to find CtfByTS plots
        if self.do_show_imgs:
            if 'CtfBytsPlot' in self.data4json[curr_target]:
                ctfbyts_plot= self.data4json[curr_target]['CtfBytsPlot']
            else:
                ctfbyts_plot= None 
            
            if ctfbyts_plot:
                ctfbyts_item= CustomStandardItem(ctfbyts_plot, size=self.imgsize, debug=self.debug, id=curr_target)
                target_item_list.append(ctfbyts_item)
            else:
                if self.debug : print(f"  DEBUG buildGUI 244 Didn't find ctfbyts_plot '{ctfbyts_plot}'")
        
        # Loop through tilt series
        disableTF= self.verbosity>4 or self.verbosity<2 or self.debug
        for mdoc_idx, curr_mdoc in enumerate( tqdm.tqdm(curr_list_mdocs, unit=' mdoc', disable=disableTF) ):
            # Strip extensions from MDOC
            mdoc_base= re.sub( '.mrc.mdoc$', '', os.path.basename(curr_mdoc) )
            
            try:
                slice_jpg= self.data4json[curr_target][curr_mdoc][0]['CentralSlice']
            except KeyError as e:
                print(f"drawTargetData: {type(e)}")
                print(f"  data4json ({len( self.data4json.keys() )}) {self.data4json.keys()}")
                print(f"  curr_target '{curr_target}'")
                print(f"  curr_mdoc '{curr_mdoc}'")
                print(f"  data4json[curr_target] ({len( self.data4json[curr_target].keys() )}) {self.data4json[curr_target].keys()}")
                exit()
            
            if slice_jpg and self.do_show_imgs:
                ts_parent_item= CustomStandardItem(slice_jpg, size=self.imgsize, text=os.path.basename(curr_mdoc), is_checkable=True)
            else:
                ts_parent_item= QtGui.QStandardItem( os.path.basename(curr_mdoc) )
                ts_parent_item.setCheckable(True)
                if self.do_show_imgs and self.verbosity>=1 and not self.warn_dict['slices'] and self.loaded_json: 
                    print(f"  WARNING! Central slice '{slice_jpg}' not found, skipping...")
                    self.warn_dict['slices']= True
                    # If we built the JSON file from scratch, there will have been a warning earlier
            
            self.mic2qt_lut[curr_mdoc] = {}
            ts_parent_item, ts_select= self.buildStatList(ts_parent_item, self.data4json[curr_target][curr_mdoc][1], curr_mdoc)
            ts_item_list= [ts_parent_item]
            ts_parent_item.setAutoTristate(True)
            
            if 'MdocSelected' in self.data4json[curr_target][curr_mdoc][0]:
                mdoc_select= self.data4json[curr_target][curr_mdoc][0]['MdocSelected']
                #if self.data4json[curr_target][curr_mdoc][0]['MdocSelected'] != ts_select:
                    #if self.verbosity>=1: 
                        #print(f"WARNING! Inconsistent selection value for MDOC '{os.path.basename(curr_mdoc)}' between JSON ({mdoc_select}) and micrographs. Using: {ts_select}")
            ts_parent_item.setCheckState(ts_select)
            self.mic2qt_lut[curr_mdoc]['widget']= ts_parent_item
            
            ts_parent_item.setCheckState(ts_select)
            self.mic2qt_lut[curr_mdoc]['widget']= ts_parent_item
            
            # Add CtfByTS and dose-fitting plots
            if self.do_show_imgs:
                if 'CtfBytsPlot' in self.data4json[curr_target][curr_mdoc][0]:
                    ts_item_list= self.addTSImgs(self.data4json[curr_target][curr_mdoc][0]['CtfBytsPlot'], ts_item_list)
                else:
                    # Add blank item to preserve columns
                    ts_item_list= self.addTSImgs(None, ts_item_list)
                    
                    if not did_warn_ctfplot: 
                        if self.verbosity >= 1: print(f"WARNING! CTF plot not found for '{os.path.basename(curr_mdoc)}'")
                        did_warn_ctfplot= True
                    
                ts_item_list= self.addTSImgs(self.data4json[curr_target][curr_mdoc][0]['DosefitPlot'], ts_item_list)
                        
            # Free-text box
            if 'TextNote' in self.data4json[curr_target][curr_mdoc][0]:
                starting_text= self.data4json[curr_target][curr_mdoc][0]['TextNote']
            else:
                starting_text= self.generic_text
            textbox= QtGui.QStandardItem(starting_text)
            ts_item_list.append(textbox)
            
            # Add micrograph data to target tree
            target_item.appendRow(ts_item_list)

            ## span container columns (I don't know what this means, but if I uncomment it, the target-file CTF plots disappear except for the last one)
            #self.tree_view.setFirstColumnSpanned(mdoc_idx, self.tree_view.rootIndex(), True)
        # End tilt-series loop
        
        # Add to target-file parent
        self.item_model.appendRow(target_item_list)
        
    def buildStatList(self, ts_parent_item, tilt_data, curr_mdoc):
        """
        Build stat table for each micrograph
        
        Parameters:
            ts_parent_item : Qt widget to which data will be added
            tilt_data (dict) : metadata which will be eventually written to JSON file
            curr_mdoc (str) : MDOC file
            
        Returns:
            updated Qt widget
        """
        
        # Extract tilt angles
        angles_list= [float(tilt_data[k]['TiltAngle']) for k in tilt_data.keys()]
        
        # Sort by angle (Adapted from https://stackoverflow.com/a/7851166)
        sorted_idx_list = [i for i, x in sorted(enumerate(angles_list), key=lambda x: x[1])]

        sorted_angles_list=[]
        for angle_idx, curr_angle in enumerate(angles_list):
            sorted_angles_list.append(list( tilt_data.keys() )[ sorted_idx_list[angle_idx] ])  # .keys() is not a list and thus cannot be directly subscripted

        did_warn_thumbs= False
        did_warn_ctfs= False
        all_selected= True
        none_selected= True

        # Loop through micrographs
        for sorted_idx, tilt_key in enumerate(sorted_angles_list):
            # Initialize row of micrograph stats
            stat_list, did_warn_thumbs, did_warn_ctfs= self.addMicWidget(tilt_data, tilt_key, curr_mdoc, sorted_idx, did_warn_thumbs, did_warn_ctfs)
            
            # Loop through stats
            for stat_key in self.stat_map.column_dict.keys():
                if stat_key in self.stat_map.column_dict:
                    # Clean up if path
                    if stat_key=='SubFramePath':
                        stat_value=ntpath.basename(tilt_data[tilt_key][stat_key])
                    else:
                        # If string, then don't format
                        stat_format= self.stat_map.column_dict[stat_key].format
                        if stat_format=='str':
                            stat_value = tilt_data[tilt_key][stat_key]
                        else:
                            stat_value=f"{float(tilt_data[tilt_key][stat_key]):{stat_format}}"

                    stat_item= QtGui.QStandardItem(stat_value)
                    
                    # Align if necessary
                    stat_align= self.stat_map.column_dict[stat_key].align
                    if stat_align: stat_item.setTextAlignment(QtCore.Qt.AlignCenter)
                    
                    stat_list.append(stat_item)
                # End found stat_key IF-THEN

                if self.verbosity>=8: print(f"  {stat_key} : '{stat_value}'")
            # End stat loop

            ts_parent_item.appendRow(stat_list)
            if self.verbosity>=8: print()
        # End micrograph loop
        
        # Set selection status for tilt series
        ts_select= 1
        if all_selected: 
            ts_select=2
        else:
            if none_selected: ts_select= 0
        
        return ts_parent_item, ts_select
                    
    def addMicWidget(self, tilt_data, tilt_key, curr_mdoc, sorted_idx, did_warn_thumbs, did_warn_ctfs):
        """
        Initializes row of micrograph stats, depending on where images are on or off
        
        Paremeters:
            tilt_data (dict) : tilt-series data
            tilt_key : key in tilt-series dictionary
            curr_mdoc : MDOC file
            sorted_idx : index number of tilt key, need for position of QStandardItem
            did_warn_thumbs (bool, updated) 
            did_warn_ctfs (bool, updated) 
        
        Returns:
            stat_list : list of Qt widgets
            did_warn_thumbs : updated boolean
            did_warn_ctfs  : updated boolean
        """
        
        movie_base= ntpath.basename(tilt_data[tilt_key]['SubFramePath'])
        ctffind_val= "{:5.2f}".format( float(tilt_data[tilt_key]['CtfFind4']) )
        
        # Check if selected
        if not 'MicSelected' in tilt_data[tilt_key]:
            mic_select=2
            none_selected= False
        else:
            if tilt_data[tilt_key]['MicSelected'] == True:
                mic_select=2
                none_selected= False
            else:
                mic_select=0
                all_selected= False

        if self.do_show_imgs:
            mic_thumb_path= tilt_data[tilt_key]['MicThumbnail']

            # Add micrograph entry
            if os.path.exists(mic_thumb_path):
                mic_item= CustomStandardItem(mic_thumb_path, size=self.imgsize, text=movie_base, is_checkable=True)
                mic_item.setCheckState(mic_select)
                self.mic2qt_lut[curr_mdoc][movie_base] = mic_item
                stat_list= [mic_item]
            else:
                mic_item= QtGui.QStandardItem(f'{sorted_idx + 1}: {movie_base}')
                mic_item.setCheckable(True)
                mic_item.setCheckState(mic_select)  # 1 is intermediate
                self.mic2qt_lut[curr_mdoc][movie_base] = mic_item
                stat_list= [mic_item]

                if not did_warn_thumbs and self.verbosity>=1 and self.loaded_json:
                    print(f"  WARNING! Micrograph thumbnail '{mic_thumb_path}' not found, skipping...")
                    did_warn_thumbs=True

            ctf_thumb_path= tilt_data[tilt_key]['CtfThumbnail']
            
            if os.path.exists(ctf_thumb_path):
                mic_item= CustomStandardItem(ctf_thumb_path, size=self.imgsize, text=ctffind_val)
                stat_list.append(mic_item)
                
            else:
                stat_list.append( QtGui.QStandardItem(f'{sorted_idx+1}: {tilt_key}') )
                if not did_warn_ctfs and self.verbosity>=1 and self.loaded_json:
                    print(f"  WARNING! CTF image '{ctf_thumb_path}' not found, skipping...")
                    did_warn_ctfs=True

        else:
            mic_item= QtGui.QStandardItem(f'{sorted_idx + 1}: {movie_base}')
            mic_item.setCheckable(True)
            mic_item.setCheckState(mic_select)  # 1 is intermediate
            self.mic2qt_lut[curr_mdoc][movie_base] = mic_item
            stat_list= [mic_item]
            stat_list+= [QtGui.QStandardItem(ctffind_val)]
        # End show-images IF-THEN
        
        ## Remember widget 
        #self.mic2qt_lut[curr_mdoc][movie_base] = mic_item
        ##(For some reason, Python forgets the address mic_item after the IF-THEN, so I need to save it to the lookup table right away
        
        return stat_list, did_warn_thumbs, did_warn_ctfs
        
    def openMenu(self, position):
        """
        Builds right click menu (Adapted from http://pharma-sas.com/common-manipulation-of-qtreeview-using-pyqt5)
        
        Parameter:
            position passed from the Qt widget
        """
        
        indexes= self.sender().selectedIndexes()
        mdlIdx = self.tree_view.indexAt(position)
        if not mdlIdx.isValid():
            print("WARNING, not a valid area")
            return
        #item = self.item_model.itemFromIndex(mdlIdx)
        #if len(indexes) > 0:
            #depth = 0
            #index = indexes[0]
            #while index.parent().isValid():
                #index = index.parent()
                #depth += 1
        #else:
            #depth = 0
        depth= find_depth( self.item_model.itemFromIndex(mdlIdx) )
        
        self.right_click_menu = QtWidgets.QMenu()
        
        # If debugging
        if self.debug:
            act_add = self.right_click_menu.addAction(self.tr("Debug: Test MDOC directory"))
            act_add.triggered.connect( partial(self.probeMdocDir, depth, mdlIdx) )
            
        # Menu options for file types
        mdoc_dir= self.probeMdocDir(depth, mdlIdx)
        if mdoc_dir:
            list_ctfstacks= glob.glob( os.path.join(mdoc_dir, "*" + self.ctfthumb_suffix + ".mrcs") )
            
            # Micrograph stacks might end in '.st'
            list_newstacks= glob.glob( os.path.join(mdoc_dir, "*" + self.micthumb_suffix + ".mrc") )
            list_newstacks+= glob.glob( os.path.join(mdoc_dir, "*" + self.micthumb_suffix + ".st") )
            
            # AreTomo reconstructions are of the form "*_aretomo.mrc"
            list_recons=[]
            for curr_pattern in self.options.recon_pattern.split():
                list_recons+= glob.glob( os.path.join(mdoc_dir, curr_pattern) )
            
            # CTF scatter plot
            ts_ctf_plot= glob.glob( os.path.join(mdoc_dir, self.options.ctfbyts_1ts) )
            
            # Dose-fitting plot
            ts_dose_plot= glob.glob( os.path.join(mdoc_dir, self.options.dosefit_plot) )
            
            self.addListAction(list_newstacks, "tilt series")
            self.addListAction(list_ctfstacks, "power-spectrum stack")
            self.addListAction(list_recons, "reconstruction", voltype='rec')
            self.addListAction(ts_ctf_plot, "CTF plot", voltype='img')
            self.addListAction(ts_dose_plot, "dose-fitting plot", voltype='img')
        # End directory-exists IF-THEN
        
        # (I don't know what this does)
        self.right_click_menu.exec_(self.sender().viewport().mapToGlobal(position))
            
    def probeMdocDir(self, depth, mdlIdx, verbose=False):
        """
        Checks for files within the tilt-series directory.
        It is assumed that the data for each series is in one directory.
        
        Parameters:
            depth (int) : depth of the cell (0<-target file, 1<-MDOC file, 2<-micrograph)
            mdlIdx : QModelIndex
            verbose (boolean) : flag to print corresponding MDOC (self.debug will print a lot more info)
        
        Returns:
            Directory containing the data for one tilt series
        """
        
        cell_text= self.item_model.itemFromIndex(mdlIdx).text()
        
        if self.debug : 
            print()
            print(f"466 depth                 : {depth}")
            print(f"467 cell_text             : '{cell_text}'")
            print(f"471 tree_view.model.data  : '{self.tree_view.model().data( self.tree_view.model().index( mdlIdx.row(), 0, mdlIdx.parent() ) )}'")
            print(f"474 column                : {mdlIdx.column()}")
            print(f"475 row                   : {mdlIdx.row()}")
        
        if len(self.temp_targets) > 0 and depth==0: 
            # See if there's a CtfByTS plot
            first_cell= self.tree_view.model().data( self.tree_view.model().index( mdlIdx.row(), 0, mdlIdx.parent() ) )
            ctfbyts_plot= self.findCtfbytsPlots(first_cell)
            
            if ctfbyts_plot:
                self.addListAction([ctfbyts_plot], "CTF plot", voltype='img')
            else:
                print(f"WARNING! No known metadata file associated with current selection")
                
            return
        
        elif (len(self.temp_targets) == 0 and depth==0) or (len(self.temp_targets) > 0 and depth==1): 
            if depth==1 and mdlIdx.column()==self.editable_column:
                mdoc_base= self.tree_view.model().data( self.tree_view.model().index( mdlIdx.row(), 0, mdlIdx.parent() ) )
                curr_mdoc= self.mdoc_lut[mdoc_base]
            elif cell_text != '':
                curr_mdoc= self.mdoc_lut[cell_text]
            else:
                first_column_index= self.tree_view.model().index( mdlIdx.row(), 0, mdlIdx.parent() )
            
                try:
                    curr_mdoc= self.mdoc_lut[self.tree_view.model().data(first_column_index)]
                except KeyError:
                    print(f"\KeyError!!")
                    print(f"  len(temp_targets)    : {len(self.temp_targets)}")
                    print(f"  depth                : {depth}")
                    print(f"  cell_text            : '{cell_text}'")
                    print(f"  self.mdoc_lut.keys() : {self.mdoc_lut.keys()}")
                    print(f"\n  Exiting...\n")
                    
                    exit(11)
            
            if self.debug: print(f"505 curr_mdoc : '{curr_mdoc}'")
        
        elif (len(self.temp_targets) > 0 and depth>1) or (len(self.temp_targets) <= 1 and depth==1):
            try:
                curr_mdoc= self.mdoc_lut[self.item_model.itemFromIndex(mdlIdx).parent().text()]
            except KeyError:
                print(f"\n539 KeyError!!")
                print(f"\tattempted key : '{self.item_model.itemFromIndex(mdlIdx).parent().text()}'")
                print(f"\texisting keys : {self.mdoc_lut.keys()}")
                return
            if verbose: print(f"parent mdoc '{self.mdoc_lut[self.item_model.itemFromIndex(mdlIdx).parent().text()]}'")
        else:
            print(f"ERROR!! Unknown condition! len(self.temp_targets)={len(self.temp_targets)}, depth={depth}")
            return
        
        return os.path.dirname(curr_mdoc)
        
    def addListAction(self, current_list, type_string, voltype=None):
        """
        Adds a menu option
        
        Parameters:
            current_list (list) : list of files that can be opened
            type_string (str) : brief text description
            voltype (str, optional) : data type
        """
        
        if len(current_list) == 0:
            insert_menuopt= self.right_click_menu.addAction( self.tr(f"(Didn't find any {type_string})") ).setDisabled(True)
        else:
            for fn in current_list:
                insert_menuopt= self.right_click_menu.addAction(self.tr(f"Open {type_string}: {os.path.basename(fn)}"))
                
                if voltype=='img':
                    insert_menuopt.triggered.connect( partial(self.openImgView, fn) )
                else:
                    insert_menuopt.triggered.connect( partial(self.openThreedMod, fn, voltype=voltype) )
        
    def openThreedMod(self, fn, voltype=None):
        """
        Opens 3dmod
        
        Parameters:
            fn (str) : filename
            voltype (str, optional) : data type
        """
        
        # Check if IMOD in PATH
        path_3dmod= self.check_exe('3dmod', verbose=self.verbosity>=5)
        path_header= self.check_exe('header', verbose=self.verbosity>=5)
        
        if path_3dmod is None or path_header is None:
            print(f"WARNING! IMOD programs '3dmod' and/or 'header' are not in PATH")
            if not 'IMOD_BIN' in os.environ:
                print("'IMOD_BIN' is not among your environmental variables. Maybe you're not in the SNARTomo environment?")
            return
        
        # Read header
        hdr_out = subprocess.run([path_header, fn], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        
        # Try to catch subprocess errors
        if hdr_out.returncode!= 0:
            print(f"ERROR!! IMOD 'header' command failed! \n\t{hdr_out.stderr.decode('utf-8')}\tExiting...\n")
            exit(12)
        
        # Split into lines
        hdr_lines = hdr_out.stdout.decode('utf-8').split('\n')
        
        # Find line with 'sections'
        section_lines= [x for x in hdr_lines if 'sections' in x]
        assert len(section_lines) == 1, f"ERROR!! IMOD header output has multiple lines (or none) containing the string 'sections'! \n\t'{section_lines}'"
        
        # Get last three entries containing dimensions
        mrc_dims= [ eval(i) for i in section_lines[0].split()[-3:] ]
        
        # Find minimum (x->0, y->1, z->2)
        min_axis= mrc_dims.index( min(mrc_dims) )
        
        if self.do_rotate and min_axis!=2: 
            fn= "-Y " + fn
            if self.verbosity>=4 : print("\nAutorotating...")
            
        system_call_23(path_3dmod, fn, verbose=self.verbosity>=4)
    
    def openImgView(self, fn, voltype=None):
        """
        Opens image-viewer
        
        Parameters:
            fn (str) : filename
            voltype (str, optional) : data type
        """
        
        path_imgview= self.check_exe(self.options.img_viewer, verbose=self.verbosity>=4)
        if path_imgview:
            hdr_out = subprocess.run([path_imgview, fn], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    
    def findCtfbytsPlots(self, target_base, debug=False):
        """
        Find CTFFIND scatter plots
        
        Parameters:
            target_base (str) : basename of target file
            debug (bool) : flag to print debug information
        
        Returns:
            plot filename
        """
        
        fn=None  # initialize

        list_ctfplots= glob.glob(self.ctfbyts_tgts)
        target_prefix= os.path.splitext(target_base)[0]
        search_matches= [s for s in list_ctfplots if target_prefix in s]
        
        # If a unique match then use it
        if len(search_matches) == 1:
            fn= search_matches[0]
        else:
            # If there's a generic ctfbyts.png, use it
            imgdir= os.path.dirname(self.ctfbyts_tgts)
            generic_fn= os.path.join(imgdir, self.options.ctfbyts_1ts)
            if os.path.exists(generic_fn): fn= generic_fn
        
        return fn
    
    def addTSImgs(self, latest_plot, item_list):
        """
        Tries to find plot, and creates an empty widget if plot unavailable
        
        Parameters:
            latest_plot (str) : plot filename
            item_list (list, modified) : list of Qt widgets
        
        Returns:
            1) updated list of Qt widgets
        """
        
        if latest_plot:
            ts_item= CustomStandardItem(latest_plot, size=self.imgsize)
            item_list.append(ts_item)
        else:
            item_list.append( QtGui.QStandardItem() )
            
        return item_list

    def check_exe(self, search_exe, verbose=False):
        """
        Looks for executable path
        
        Parameters:
            search_exe (str) : executable to check
            verbose (bool, optional) : flag to write path
        
        Returns:
            executable path
        """
        
        exe_path= None
        if search_exe== 'header' or search_exe== '3dmod':
            # If IMOD directory is defined, then use it
            if self.options.imod_bin:
                exe_path= os.path.join(self.options.imod_bin, search_exe)
                if self.debug: print(f"Path for '{search_exe}' ({self.options.imod_bin}) specified on the command line")
            
            # Try SNARTomo environmental variables
            elif 'IMOD_BIN' in os.environ:
                path_attempt= os.path.join(os.environ['IMOD_BIN'], search_exe)
                
                #Make sure it's an executable
                if os.access(path_attempt, os.X_OK):
                    exe_path= path_attempt
                    if self.debug: print(f"Path for '{search_exe}' found from SNARTomo environmental variable 'IMOD_BIN'")
                else:
                    if self.debug: print(f"Found SNARTomo environmental variables, but not path for '{search_exe}' ")
        
        # If not found yet, simply try a 'which'
        if exe_path is None:
            exe_path = shutil.which(search_exe) 
            if exe_path and self.debug: print(f"DEBUG: Executable '{search_exe}' found in $PATH")

        # If still not found, throw an error
        if exe_path is None:
            print(f"WARNING! No executable found for command '{search_exe}'")
        else:
            if verbose : print(f"Path to executable '{search_exe}': {exe_path}")    
            
        return exe_path
        
    def item_changed(parent, self):
        """
        Change the MDOC checkbox/textbox depending on whether all, none, or some micrographs are selected
        
        NOTE: "self" here refers to the QWidget containing the checkbox/textbox, while "parent" is the TreeView
        """
        
        if parent.unsaved_changes == False:
            parent.unsaved_changes= True
            if parent.debug: print("DEBUG: First click")
        
        # If checkbox was clicked
        if self.isCheckable():
            index= parent.item_model.indexFromItem(self)
            if index.isValid():
                curr_parent_text= self.parent().text()
                # Only proceed if depth=2
                if find_depth(self) == 2:
                    # Find MDOC in QStandardItemModel
                    root_item= parent.item_model.invisibleRootItem()
                    mdoc_list= []
                    
                    # Loop through targets
                    for target_key in range(root_item.rowCount()):
                        target_item= root_item.child(target_key)
                        
                        # Loop through MDOCs
                        for test_mdoc in range( target_item.rowCount() ):
                            mdoc_item= target_item.child(test_mdoc)
                            if curr_parent_text == mdoc_item.text() : mdoc_list.append(mdoc_item)
                    
                    # Sanity check
                    if len(mdoc_list) == 0:
                        print(f"\nUH OH! Couldn't find '{curr_parent_text}' in target files")
                        return
                    elif len(mdoc_list) >= 2:
                        print(f"\nUH OH! Found '{curr_parent_text}' in {len(mdoc_list)} target files: {mdoc_list}")
                        return
                    else:
                        # Get full MDOC path
                        mdoc_path= parent.mdoc_lut[curr_parent_text]
                        curr_mdoc_item= mdoc_list[0]
                        
                        all_selected= True
                        none_selected= True
                        
                        # Loop through micrographs
                        for mic_idx in range( curr_mdoc_item.rowCount() ):
                            mic_item= curr_mdoc_item.child(mic_idx)
                            curr_state= mic_item.checkState()
                            if curr_state==0: all_selected= False
                            if curr_state==2: none_selected=False
                        # End micrograph loop
                        
                        # Update state, with sanity check
                        assert not all_selected or not none_selected, "ERROR!! Unknown state!"
                        if all_selected: 
                            curr_mdoc_item.setCheckState(2)
                        elif none_selected:
                            curr_mdoc_item.setCheckState(0)
                        else:
                            curr_mdoc_item.setCheckState(1)
                            
                        if parent.debug: print(f"  1462 {curr_mdoc_item.text()} '{curr_mdoc_item.checkState()}'")
                # End depth=2 IF-THEN
            # End valid-index IF-THEN
        # If line-edit
        else:
            index= parent.tree_view.currentIndex()
            edited_text = parent.get_edited_text(index)
            target_file= parent.get_position_in_tree(index)
            mdoc_base= parent.tree_view.model().data( parent.tree_view.model().index( index.row(), 0, index.parent() ) )
            if parent.debug: print(f"1480 mdoc_base '{mdoc_base}', edited_text '{edited_text}', target_file {target_file}")
            curr_mdoc= parent.mdoc_lut[mdoc_base]
            parent.data4json[target_file][curr_mdoc][0]['TextNote'] = edited_text
        # End checkbox IF-THEN
        
    def testFunction(self):
        msg=f"There are still N remaining files in '{self.incinerate_dir}', presumably from a previous session. "
        msg+="If you would like to restore them, you will need to do so manually."
        QtWidgets.QMessageBox.warning(self, 'NOTE', msg, QtWidgets.QMessageBox.Ok)

    def saveSelection(self):
        # Loop through target files (real or virtual)
        for curr_target in self.data4json.keys():
            target_data= self.data4json[curr_target]
            
            # Loop through (possible) MDOC files
            for curr_mdoc in target_data.keys():
                # Might be the CtfByTS plot
                if isinstance(target_data[curr_mdoc], list):
                    if not curr_mdoc in self.mic2qt_lut:
                        print(f"UH OH! Can't find widget dictionary for MDOC '{curr_mdoc}'")
                        return()
                    
                    if self.debug: 
                        print(f"1500 MDOC {os.path.basename(curr_mdoc)} before: data4json {target_data[curr_mdoc][0]['MdocSelected']}, mic2qt_lut {self.mic2qt_lut[curr_mdoc]['widget'].checkState()}")
                    if target_data[curr_mdoc][0]['MdocSelected'] != self.mic2qt_lut[curr_mdoc]['widget'].checkState():
                        self.data4json[curr_target][curr_mdoc][0]['MdocSelected'] = self.mic2qt_lut[curr_mdoc]['widget'].checkState()
                    if self.debug: 
                        print(f"1504 MDOC {os.path.basename(curr_mdoc)} after: data4json {self.data4json[curr_target][curr_mdoc][0]['MdocSelected']}, mic2qt_lut {self.mic2qt_lut[curr_mdoc]['widget'].checkState()}")
                    
                    # Loop through micrographs
                    for mic_idx, curr_mic in enumerate(target_data[curr_mdoc][1]):
                        movie_base= ntpath.basename(target_data[curr_mdoc][1][curr_mic]['SubFramePath'])
                        if not movie_base in self.mic2qt_lut[curr_mdoc]:
                            print(f"UH OH! Can't find widget for micrograph '{movie_base}'")
                            return
                        
                        # Update only when necessary
                        if target_data[curr_mdoc][1][curr_mic]['MicSelected'] and not self.mic2qt_lut[curr_mdoc][movie_base].checkState(): 
                            self.data4json[curr_target][curr_mdoc][1][curr_mic]['MicSelected'] = False
                        if self.mic2qt_lut[curr_mdoc][movie_base].checkState() and not target_data[curr_mdoc][1][curr_mic]['MicSelected']:
                            self.data4json[curr_target][curr_mdoc][1][curr_mic]['MicSelected'] = True
                    # End micrograph loop
                # End MDOC IF-THEN
            # End MDOC loop
        # End target loop
        
        save_json(self.data4json, filename=self.json, verbosity=self.verbosity)
        self.unsaved_changes= False
        
    def restackDeselected(self):
        if not self.unsaved_changes:
            print("\nNo unsaved changes!")
            return
        
        # Loop through target files (real or virtual)
        for curr_target in self.data4json.keys():
            target_data= self.data4json[curr_target]
            
            # Loop through (possible) MDOC files
            for curr_mdoc in target_data.keys():
                # Might be the CtfByTS plot
                if isinstance(target_data[curr_mdoc], list):
                    if not curr_mdoc in self.mic2qt_lut:
                        print(f"UH OH! Can't find widget dictionary for MDOC '{curr_mdoc}'")
                        return()
                    
                    some_deselected= False
                    num_selected= 0
                    select_list= []
                    deselect_list = []
                    mic_list= []
                    
                    # Loop through micrographs
                    for mic_idx, curr_mic in enumerate(target_data[curr_mdoc][1]):
                        movie_base= ntpath.basename(target_data[curr_mdoc][1][curr_mic]['SubFramePath'])
                        if not movie_base in self.mic2qt_lut[curr_mdoc]:
                            print(f"UH OH! Can't find widget for movie '{movie_base}'")
                            return
                        
                        if self.mic2qt_lut[curr_mdoc][movie_base].checkState() == 0:
                            some_deselected= True
                            deselect_list.append(movie_base)
                            if self.debug: print(f"1437 Deselected: '{movie_base}'")
                        else:
                            num_selected+= 1
                            assert 'McorrMic' in target_data[curr_mdoc][1][curr_mic], "ERROR!! Micrograph path not stored here!"
                            mic_path= target_data[curr_mdoc][1][curr_mic]['McorrMic']
                            assert os.path.exists(mic_path), f"ERROR!! Micrograph '{mic_path}' not found!"
                            select_list+= [mic_path, '/']
                            mic_list.append( os.path.basename(mic_path) )
                    # End micrograph loop
                    
                    # Only if micrographs were deselected
                    if some_deselected:
                        # Prepare MDOC file
                        general_lines, tilt_data= readMdocHeader(curr_mdoc)

                        # Loop through ZValues
                        num_counter= 0
                        for mic_data in tilt_data:
                            movie_base= subframeFromZvalueData(mic_data)
                            
                            # Build corresponding micrograph
                            mic_base= os.path.splitext(movie_base)[0] + self.options.mic_pattern
                            if mic_base in mic_list:
                                # Number ZValue consecutively
                                for line_idx, line_text in enumerate(mic_data):
                                    if line_text.startswith('[ZValue') :
                                        key_value = line_text.split('=')[1]
                                        int_value= int(key_value.split(']')[0])
                                        new_line= re.sub(str(int_value), str(num_counter), line_text)
                                        
                                        # Replace in mic_data
                                        line_text= new_line
                                
                                    general_lines.append(line_text)
                                # End micrograph-data loop
                                
                                general_lines.append('')
                                num_counter+= 1
                            else:
                                # Sanity check if absent
                                movie_base= subframeFromZvalueData(mic_data)
                                assert movie_base in deselect_list, f"UH OH! Data for '{movie_base}' seems not to be in delesection list {deselect_list}"
                        # End ZValue loop
                        
                        if self.debug:
                            writeAsText(general_lines, curr_mdoc + '.TEST', do_backup=False, verbose=True,              description='MDOC file')
                        else:
                            writeAsText(general_lines, curr_mdoc,           do_backup=True,  verbose=self.verbosity>=1, description='MDOC file')
                        
                        # Restack
                        self.imodRestack(curr_mdoc, select_list, num_selected)
                    else:
                        if self.debug: print(f"1599 MDOC '{os.path.basename(curr_mdoc)}': num_selected '{num_selected}', some_deselected '{some_deselected}'")
                # End MDOC IF-THEN
            # End MDOC loop
        # End target loop
        
    def imodRestack(self, curr_mdoc, select_list, num_selected):
        """
        Writes new stack with only selected micrographs
        Policy is to save only one backup copy
        
        Parameters:
            curr_mdoc : MDOC filename (needed only for filenames)
            select_list : selection list, containing micrographs separated by a lone slash
            num_selected : number of selected micrographs
        """
        
        mdoc_dir= os.path.dirname(curr_mdoc)
        mdoc_prefix= os.path.basename(curr_mdoc).split('.')[0]
        
        # Write file list for newstack
        fileinlist= os.path.join(
            mdoc_dir,
            mdoc_prefix + "_heatwave.txt"
            )
        
        # IMOD expects the number of images at the beginning of the list
        select_list.insert(0, num_selected)
        writeAsText(select_list, fileinlist, do_backup=True, verbose=self.verbosity>=1, description='selection file')
        if self.verbosity >= 9: system_call_23('cat', fileinlist)
        
        # Check if IMOD in PATH (TODO: Move to function)
        path_newstack= self.check_exe('newstack', verbose=self.verbosity>=4)
        
        if path_newstack is None:
            print(f"WARNING! IMOD program 'newstack' is not in PATH")
            if not 'IMOD_BIN' in os.environ:
                print("'IMOD_BIN' is not among your environmental variables. Maybe you're not in the SNARTomo environment?")
            return
        
        # Get stack name(s) (TODO: Save to JSON rather than parse here)
        list_newstacks= glob.glob( os.path.join(mdoc_dir, "*" + self.micthumb_suffix + ".mrc") )
        list_newstacks+= glob.glob( os.path.join(mdoc_dir, "*" + self.micthumb_suffix + ".st") )
        
        # If more than 1, then throw error
        if len(list_newstacks) > 1: 
            print(f"ERROR!! Found more than one stack! {list_newstacks}\n  Aborting")
            return
        else:
            # Back up stack if it exists
            if len(list_newstacks) == 1: 
                reordered_stack= list_newstacks[0]
                backup_stack= reordered_stack + '.BAK'
                if not self.debug: os.rename(reordered_stack, backup_stack)
                if self.verbosity>=1: print(f"\nRenamed '{os.path.basename(reordered_stack)}' to '{os.path.basename(backup_stack)}'")
            else:
                reordered_stack= os.path.join(mdoc_dir, mdoc_prefix + self.micthumb_suffix + ".mrc")
            
            newstack_args=f"-filei {fileinlist} -ou {reordered_stack}"
            if self.debug: 
                print(f"DEBUG: newstack {newstack_args}")
            else:
                if self.verbosity>= 3: print(f"Running: newstack {newstack_args}\n  Please wait...")
                newstack_out= subprocess.run([path_newstack] + newstack_args.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                
                # Try to catch subprocess errors
                if newstack_out.returncode!= 0:
                    print(f"ERROR!! IMOD 'newstack' command failed! Error code: {newstack_out.returncode}")
                    if newstack_out.stdout: print(f"  stdout:\n\t'{newstack_out.stdout.decode('utf-8')}'")
                    if newstack_out.stderr: print(f"  stderr:\n\t'{newstack_out.stderr.decode('utf-8')}'")
                    print(f"\tExiting...\n")
                    exit(17)
                else:
                    # TODO: Make sure MDOC has the same number of entries as the stack file
                    if self.verbosity>= 1: print(f"  Wrote new stack: {reordered_stack}")
                    newstack_log= re.sub('.mrc.mdoc$', self.options.stack_suffix + '.out', curr_mdoc)
                    writeAsText(newstack_out.stdout.decode('utf-8'), newstack_log, do_backup=True, verbose=self.verbosity>=3, description='restack output log')
    
    def incinerateData(self):
        num_deselected_ts= 0
        
        # Count number of deselected tilt series
        for curr_target in self.data4json.keys():
            target_data= self.data4json[curr_target]
            for curr_mdoc in target_data.keys():
                if isinstance(target_data[curr_mdoc], list):
                    if not curr_mdoc in self.mic2qt_lut:
                        print(f"UH OH! Can't find widget dictionary for MDOC '{curr_mdoc}'")
                        return()
                    if self.mic2qt_lut[curr_mdoc]['widget'].checkState() == 0:
                        num_deselected_ts+= 1
            # End possible-MDOC loop
        # End target loop
        
        if num_deselected_ts == 0:
            print("\nNo tilt series delesected. An entire tilt series must be deselected to move to incinerator bin...")
            return
        else:
            if not self.debug:
                choice= QtWidgets.QMessageBox.question(
                    self, 
                    'WARNING!', 
                    f"There are {num_deselected_ts} tilt series to be incinerated. Are you sure you want to continue?",
                    QtWidgets.QMessageBox.Yes | QtWidgets.QMessageBox.No
                    )
                if choice== QtWidgets.QMessageBox.No: return
        
        # Loop through target files (real or virtual) (TODO: Move to function)
        for curr_target in self.data4json.keys():
            target_data= self.data4json[curr_target]
            
            # Loop through (possible) MDOC files
            for curr_mdoc in target_data.keys():
                # Might be the CtfByTS plot
                if isinstance(target_data[curr_mdoc], list):
                    if not curr_mdoc in self.mic2qt_lut:
                        print(f"UH OH! Can't find widget dictionary for MDOC '{curr_mdoc}'")
                        return()
                    
                    # Only incinerate if completely deselected
                    if self.mic2qt_lut[curr_mdoc]['widget'].checkState() == 0:
                        self.option_dict= vars(self.options)
                        ###self.incinerate_dir= re.sub('\$IN_DIR', self.options.in_dir, self.options.incinerate_dir)
                        self.createIncinerateSubdirs()
                    
                        # Move tilt series directory
                        tomo_dir= os.path.basename( os.path.dirname(curr_mdoc) )
                        ts_dir= re.sub('$MDOC_STEM', tomo_dir, os.path.dirname(curr_mdoc))
                        outdir= os.path.basename( os.path.dirname(curr_mdoc) )
                        dest_dir= os.path.join(self.incinerate_subdirs['ts_dir'], outdir)
                        assert not os.path.isdir(dest_dir), f"UH OH, {dest_dir} already exists!"
                        self.incinerated_mvlist.append([ts_dir, dest_dir])
                        
                        if not self.debug:
                            shutil.move(ts_dir, dest_dir)
                        else:
                            if self.verbosity>=4: print(f"DEBUG: mv {ts_dir} {self.incinerate_subdirs['ts_dir']}")
                            
                        except_tsdir= self.incinerate_subdirs.copy()
                        except_tsdir.remove('ts_dir')
                        
                        # Loop through data types
                        for json_key, incinerate_key in zip(self.incinerate_jsonkeys, except_tsdir):
                            for curr_mic in target_data[curr_mdoc][1]:
                                self.moveIfExists(self.data4json[curr_target][curr_mdoc][1][curr_mic], json_key, incinerate_key)
                            if self.verbosity>=4: print(f"Finished incinerating files of type '{json_key}'")
                        # End data-type loop
                    
                        # Incinerate GUI data for current MDOC
                        self.incinerateGuiData(curr_mdoc)
                    # End deselected IF-THEN
                # End MDOC IF-THEN
            # End MDOC loop
        # End target loop
        
        # Update JSON data
        data_copy= copy.deepcopy(self.data4json)
        for curr_target in data_copy.keys():
            target_data= data_copy[curr_target]
            for curr_mdoc in target_data.keys():
                if isinstance(target_data[curr_mdoc], list):
                    if not curr_mdoc in self.mic2qt_lut:
                        print(f"UH OH! Can't find widget dictionary for MDOC '{curr_mdoc}'")
                        return()
                    if self.mic2qt_lut[curr_mdoc]['widget'].checkState() == 0:
                        if self.debug: print(f"1779 data4json {type(self.data4json[curr_target][curr_mdoc])}, mic2qt_lut {type(self.mic2qt_lut[curr_mdoc])}")
                        
                        # Remember stuff
                        self.incinerated_tsdict[curr_mdoc]={}
                        self.incinerated_tsdict[curr_mdoc]['target'] = curr_target
                        self.incinerated_tsdict[curr_mdoc]['json_data'] = self.data4json[curr_target][curr_mdoc]
                        
                        # Delete
                        del self.data4json[curr_target][curr_mdoc]
                        del self.mdoc_lut[os.path.basename(curr_mdoc)]
                # End deselected IF-THEN
            # End MDOC loop
        # End target loop
        
        # Update JSON file
        self.saveSelection()
        
        if not self.debug: 
            if self.verbosity>=1: print(f"Incinerated {num_deselected_ts} tilt series")
        else:
            print(f"\nDEBUG: Incinerated {num_deselected_ts} tilt series")
        
    def createIncinerateSubdirs(self):
        """
        Creates incinerator directories if they don't exist
        """
        
        if not os.path.isdir(self.incinerate_dir): 
            os.makedirs(self.incinerate_dir)  # os.mkdir() can only operate one directory deep
            if self.verbosity>=1 : print(f"Created directory: {self.incinerate_dir}")
        
        # Loop through directory keys
        for key in self.incinerate_subdirs: 
            if key == 'movie_dir':
                outdir= os.path.join(self.incinerate_dir, self.option_dict[key])
            elif key == 'ts_dir':
                parent_dir= os.path.dirname(self.option_dict[key])
                subdir= re.sub('\$IN_DIR' + os.sep, '', parent_dir)
                outdir= os.path.join(self.incinerate_dir, subdir)
            else:
                subdir= re.sub('\$IN_DIR' + os.sep, '', self.option_dict[key])
                outdir= os.path.join(self.incinerate_dir, subdir)
            # End special-cases IF-THEN
            
            if not os.path.isdir(outdir): 
                os.makedirs(outdir)
            
            # Remember directory
            self.incinerate_subdirs[key] = outdir
        # End directory loop
    
    def moveIfExists(self, mic_data, json_key, incinerate_key):
        """
        1) Moves data type to incincerator bin
        2) Inactivates checkbox
        
        Parameters:
            mic_data
            json_key
            incinerate_key
        """
        
        if json_key in mic_data:
            source= mic_data[json_key]
            assert os.path.isdir(self.incinerate_subdirs[incinerate_key]), f"UH OH, {self.incinerate_subdirs[incinerate_key]} is not a directory!"
            destination= os.path.join( self.incinerate_subdirs[incinerate_key], os.path.basename(source) )
            if os.path.exists(source): 
                self.incinerated_mvlist.append([source, destination])
                if not self.debug: 
                    shutil.move(source, destination)
                else:
                    print(f"DEBUG:   mv {source} {destination}")
            else:
                print(f"WARNING! Filename '{source}' does not exist")
            
    def incinerateGuiData(self, curr_mdoc):
        # Incinerate GUI data for current MDOC
        curr_widget= self.mic2qt_lut[curr_mdoc]['widget']
        root_item= self.item_model.invisibleRootItem()
        if self.debug: print(f"1832 root_item.rowCount() {root_item.rowCount()}")
        
        # Loop through targets
        target_removal_list=[]
        for target_key in range(root_item.rowCount()):
            target_item= root_item.child(target_key)
            assert target_item is not None, f"UH OH, target key #{target_key} is 'NoneType'!"
            if self.debug: print(f"  1840 #{target_key} target_item {target_item.text()} {type(target_item)}")
            target_index= self.item_model.indexFromItem(target_item)
            if self.debug: print(f"  1841 {target_item.text()}: rowCount {target_item.rowCount()}, row #{target_index.row()}")
            
            # Loop through MDOCs
            mdoc_removal_list=[]
            for test_mdoc in range( target_item.rowCount() ):
                mdoc_item= target_item.child(test_mdoc)
                msg=f"    1849 {mdoc_item.text()} {mdoc_item} {str( mdoc_item.text()==os.path.basename(curr_mdoc) )} "
                mdoc_index= self.item_model.indexFromItem(mdoc_item)
                if mdoc_index.isValid(): msg+= str( mdoc_index.row() )
                if self.debug: print(msg)
                if mdoc_item.text()==os.path.basename(curr_mdoc): 
                    assert mdoc_item==self.mic2qt_lut[curr_mdoc]['widget'], f"UH OH! Mismatch: {mdoc_item} != {self.mic2qt_lut[curr_mdoc]['widget']}"
                    mdoc_removal_list.append( mdoc_index.row() )
            # End MDOC loop
            
            # Remove empty tilt series
            for curr_row in mdoc_removal_list: target_item.takeRow(curr_row)
            
            # If no tilt series remaining, then remove target also (outside of loop, because we're iterating)
            if self.debug: print(f"  1860 {target_item.text()}: rowCount {target_item.rowCount()}, row #{target_index.row()}")
            if target_item.rowCount() == 0: target_removal_list.append( target_item.row() )
        # End target loop
        
        # Remove empty targets
        for curr_row in target_removal_list: root_item.takeRow(curr_row)
    
    def undoIncineration(self):
        """
        Restores files in incinerator
        """
        
        if len(self.incinerated_mvlist) == 0:
            print("There are no files that can be restored.")
            
            # Count remaining files in incinerator
            total_files= countFiles(self.incinerate_dir)
            if total_files: 
                print(f"  There are {total_files} in '{self.incinerate_dir}'")
                print( "  To restore them, you'll need to move them manually.\n")
            return
        
        old_mdoc_list=[]
        mdoc_warning= False
        for file_idx, file_pair in enumerate(self.incinerated_mvlist):
            source= file_pair[1]
            destination= file_pair[0]
            
            # Check if a directory
            if os.path.isdir(source):
                if self.verbosity>=3: print(f"Restoring '{os.path.basename(source)}'")
            
            if not self.debug:
                assert not os.path.exists(destination), f"UH OH, {destination} already exists!"
                shutil.move(source, destination)
                
                if os.path.isdir(destination):
                    # Look for MDOC files (TODO: Confirm that it's a tomo directory)
                    dir_mdocs= expandInputFiles( os.path.join(destination, '*.mdoc') )
                    if len(dir_mdocs) == 0:
                        print(f"WARNING! Couldn't find any MDOC files in '{os.path.basename(destination)}'")
                        mdoc_warning= True
                    elif len(dir_mdocs) > 1:
                        print(f"WARNING! Found multiple MDOC files ({len(dir_mdocs)}) in '{os.path.basename(destination)}'")
                        mdoc_warning= True
                    else:
                        old_mdoc_list.append(dir_mdocs[0])
            else:
                print(f"  {file_idx} mv {source} {destination} ")
                
        # Restore data in GUI
        for curr_mdoc in self.incinerated_tsdict.keys():
            curr_target= self.incinerated_tsdict[curr_mdoc]['target']
            self.data4json[curr_target][curr_mdoc] = self.incinerated_tsdict[curr_mdoc]['json_data']
            self.data4json[curr_target][curr_mdoc][0]['MdocSelected'] = 2
            self.mdoc_lut[os.path.basename(curr_mdoc)] = curr_mdoc
        
        self.saveSelection()
        
        # If I don't explicitly record the position, the rebuilt window may go somewhere weird
        xcoord= self.pos().x()
        ycoord= self.pos().y()
        self.buildGUI()
        self.move(xcoord, ycoord)
        
        # Count remaining files in incinerator
        total_files= countFiles(self.incinerate_dir)
        if total_files: 
            msg=f"There are still {total_files} remaining files in '{self.incinerate_dir}', presumably from a previous session. "
            msg+="If you would like to restore them, you will need to do so manually."
            QtWidgets.QMessageBox.warning(self, 'NOTE', msg, QtWidgets.QMessageBox.Ok)
            if self.verbosity>=1 : print(msg)
    
    # Adapted from https://stackoverflow.com/a/9249527
    def closeEvent(self, event=None):
        if self.debug: 
            print(f"2178 position {type( self.pos() )} ({self.pos().x()},{self.pos().y()})")
            print(f"2179 closeEvent: event {type(event)}")
        if self.unsaved_changes == True:
            if self.debug:
                print("DEBUG: Exiting with unsaved changes...")
                if not event: exit()
            else:
                # Adapted from https://pythonprogramming.net/pop-up-messages-pyqt-tutorial/
                choice= QtWidgets.QMessageBox.question(
                    self, 
                    'WARNING!', 
                    "There are unsaved changes. Are you sure you want to quit?",
                    QtWidgets.QMessageBox.Yes | QtWidgets.QMessageBox.No
                    )
                # TODO: If there are 3+ buttons (e.g., Save+Quit), I don't know how to center them
                
                if choice== QtWidgets.QMessageBox.Yes:
                    if self.verbosity>=1 : print("Exiting...")
                    if not event: exit()
                
                # TODO: This option sometimes gives an XCB warning that I can't figure out.
                elif choice== QtWidgets.QMessageBox.No:
                    return
                else:
                    print(f"Uh oh! Unknown option: {choice}")
            # End debug IF-THEN
        else:
            if self.verbosity>=1 : print("Exiting...")
            exit()

    def get_edited_text(self, index):
        depth= find_depth( self.item_model.itemFromIndex(index) )
        if index.isValid() and depth==1 and index.column() == self.editable_column:
            return self.item_model.data(index, QtCore.Qt.EditRole)

    def get_position_in_tree(self, index):
        if index.isValid():
            path = []
            while index.isValid():
                item = self.item_model.itemFromIndex(index)
                path.insert(0, item.text())
                index = index.parent()
            return path[0]

## END CLASS MDOCTREEVIEW ##

class MdocColumnAttrs:
    """
    Contains attributes for each item displayed from the MDOC file:
        width
        format
    """

    def __init__(self, column_list=[]):
        self.keys=column_list
        self.column_dict={}

    def add_column(self, name, width, format, align=None):
        self.keys.append(name)
        self.column_dict[name]= argparse.Namespace()
        self.column_dict[name].width=width
        self.column_dict[name].format=format
        self.column_dict[name].align=align

    def list_info(self):
        longest=-1
        for key in self.keys:
            if len(key)>longest: longest=len(key)

        print("Keys:")
        for key in self.keys:
            string2print=f"  {key.ljust(longest)}: "
            string2print+=f"{self.column_dict[key].width}\t"
            string2print+=f"{self.column_dict[key].format}\t"
            print(string2print)

class CustomStandardItem(QtGui.QStandardItem):
    """
    A QStandardItem plus an image
    """
    
    def __init__(self, icon, text='', size=256, debug=False, id=None, is_checkable=False):
        """
        Parameters:
            icon : image
            text (optional) : text places to the right of the image
            size (optional) : image size
            debug (optional) : print debug info
            id (optional) : text label for debug info
            is_checkable (boolean) : flag to add checkbox
        """
        
        super().__init__(text)
        self.debug=debug
        if id: self.filename= os.path.basename(id)
        
        if isinstance(icon, QtGui.QIcon):
            self.my_icon= icon
        else:
            self.my_icon= QtGui.QIcon(icon)
        
        self.setIcon(self.my_icon)
        self._icon_size = QtCore.QSize(size, size)
        
        if is_checkable: 
            self.setCheckable(True)
            self.setCheckState(2)  # 1 is intermediate

    def data(self, role):
        # Refreshes the image (I think?)
        
        if role == QtCore.Qt.DecorationRole:
            icon = super().data(role)
            if icon and isinstance(icon, QtGui.QIcon):
                pixmap = self.my_icon.pixmap(self._icon_size)
                return pixmap
        return super().data(role)

class LineEditDelegate(QtWidgets.QStyledItemDelegate):
    def __init__(self, column=1):
        super().__init__()
        self.column= column 
        
    def createEditor(self, parent, option, index):
        if index.column() == self.column:
            editor = QtWidgets.QLineEdit(parent)
            return editor
        else:
            return super().createEditor(parent, option, index)

    def setEditorData(self, editor, index):
        if index.column() == self.column:
            value = index.model().data(index, QtCore.Qt.DisplayRole)
            editor.setText(str(value))
        else:
            super().setEditorData(editor, index)

    def setModelData(self, editor, model, index):
        if index.column() == self.column:
            model.setData(index, editor.text(), QtCore.Qt.EditRole)
        else:
            super().setModelData(editor, model, index)

def grep(pattern, file):
    """
    Looks for string in a file (From https://blog.gitnux.com/code/python-grep/)
    
    Parameters:
        pattern (str) : pattern to search
        file (str) : filename
    
    Returns:
        list of matching lines
    """
    
    with open(file, 'r') as f:
        lines = f.readlines()

    matched_lines = [line for line in lines if re.search(pattern, line)]

    return matched_lines

def expandInputFiles(string2split, extension=None):
    """
    Expands a space-delimited string (which may include wild cards) and returns a list of files
    
    Parameters:
        string2split : space-delimited string (which may include wild cards)
        extension (optional) : only files with this extension will be used
    
    Returns:
        a list of files
    """
    
    file_list=[]
    list_strings=string2split.split()
    
    for curr_string in list_strings:
        list_expanded= glob.glob(curr_string)
        
        for fn in list_expanded:
            if extension:
                if os.path.splitext(fn)[1] == extension: 
                    file_list.append(fn)
            else:
                file_list.append(fn)
    
    return file_list
        
def read_mdoc(mdoc_file):
    """
    Parses MDOC file
    
    Parameters:
        mdoc_file : MDOC file
    
    Returns:
        list of dictionaries
            list[0]: dictionary of header information
            list[1]: dictionary for micrograph-specific data
    """
    
    # Initialize MDOC data
    general_lines, tilt_data= readMdocHeader(mdoc_file)
    
    # Parse general Information
    general_information = {}
    
    # Add mdoc name & location to general information
    general_information['Mdoc_name'] = mdoc_file
    general_information['Mdoc_location'] = os.path.realpath(mdoc_file)
    
    for line in general_lines:
        key_value = line.split('=')
        if len(key_value) == 2:
            if "Titan Krios" in line:
                general_information['CollectionDate'] = line.strip()[-20:-1]
                continue
            key = key_value[0].strip()
            value = key_value[1].strip()
            if key in desired_items_general:
                general_information[key] = value
        elif "Tilt axis angle" in line:
            data = line.split('=')
            general_information['Tilt axis angle'] = data[2].strip()[0:4]
            general_information['Binning'] = data[3].strip()[0]
            general_information['Spotsize'] = data[4].strip()[0]
    
    # Parse information for every tilt
    general_information['NumTilts'] = str(len(tilt_data))
    tilt_information = {}
    num_counter = 0
    
    for mic_data in tilt_data:
        num_counter += 1
        tilt_num = 'tilt_no_' + str(num_counter)
        tilt_information[tilt_num] = {}
        for line in mic_data:
            key_value = line.split('=')
            key = key_value[0].strip()
            value = key_value[1].strip()
            if key in desired_items_general:
                general_information[key] = value
            elif key in desired_items_tilt:
                if key == '[ZValue' :
                    key= key.split('[')[1]
                    value= int(value.split(']')[0])
                tilt_information[tilt_num][key] = value
    
    # Returning list of two dictionaries containing general and tilt specific information
    general_and_tilt = [general_information, tilt_information]
    
    return general_and_tilt

def readMdocHeader(mdoc_file):
    """
    Parses MDOC and splits into common header and micrograph-specific data
    
    Parameter: 
        mdoc_file : filename
    
    Returns:
        list : header data
        list : micrograph-specific data
    """
    
    # Read file
    with open(mdoc_file) as fin:
        lines= fin.readlines()

    # Initialize
    general_lines= []
    tilt_data= []
    z_block= []
    in_z= False
    prev_line= None
    
    for curr_line in lines:
        curr_line= curr_line.strip()
        if curr_line[0:2] != "[Z" and not in_z:
            general_lines.append(curr_line)
        elif curr_line[0:2] == "[Z":
            # Start a new z_block
            z_block= [curr_line]
            in_z= True
        elif in_z and curr_line != "":
            z_block.append(curr_line)
        else:
            if prev_line != "": 
                tilt_data.append(z_block)
            
        # Remember previous line in case MDOC ends in multiple carriage returns
        prev_line= curr_line
    # End line loop

    return general_lines, tilt_data

def subframeFromZvalueData(mic_data):
    """
    Find list element which starts with SubFramePath
    
    Parameter:
        mic_data : list of data corresponding to a ZValue in an MDOC
        
    Returns:
        basename of SubFramePath entry
    """

    result = [i for i in mic_data if i.startswith('SubFramePath')]
    assert len(result) == 1, f"UH OH! more than one MDOC entry starts with 'SubFramePath': {result}"
    key_value= result[0].split('=')
    value= key_value[1].strip()
    
    return ntpath.basename(value)

def definedAndExists(curr_key, curr_dict):
    """
    Checks if dictionary has key, and whether that key's value corresponds to a valid path
    
    Parameters:
        curr_key : potential dictionary key, whose value corresponds to a path
        curr_dict : dictionary
    
    Returns:
        boolean : whether value is a valid file path
    """
    
    # Initialize
    does_it_exist= False
    
    assert isinstance(curr_dict, dict), f"ERROR!! Is a {type(curr_dict)} rather than a dictionary!"
    
    # Check first if dictionary has key
    if curr_key in curr_dict:
        assert isinstance(curr_dict[curr_key], str), f"ERROR!! Is a {type(curr_dict[curr_key])} rather than a string!"
        if os.path.exists(curr_dict[curr_key]):
            does_it_exist= True
            
    return does_it_exist

def save_json(data, filename='output.json', verbosity=0):
    """
    Saves metadata to JSON file
    
    Parameters:
        data (list/dict) : metadata of arbitrary complexity
        filename (str) : output filename
        verbosity (int) : verbosity (1+, prints save message, 9+ prints contents)
    """
    
    # Save as JSON
    with open(filename, 'w') as f:
        json.dump(data, f, indent=3)
    
    if verbosity>=1: print(f'Data exported and saved as {filename}')
    if verbosity>=9: 
        try:
            print(f"\n{os.path.basename(filename)}:")
            system_call_23('cat', filename)
            print()
        except:
            print(":(")

def read_json(json_file):
    """
    Reads metadata from JSON file
    
    Parameters:
        json_file : JSON filename
    
    Returns:
        metadata of arbitrary complexity
    """
    
    with open(json_file, 'r') as f:
        json_data = json.load(f)
    return json_data

def getLatest(file_pattern, dir_name='.', debug=False):
    """
    Returns latest file from a file pattern.
    Returns 'None' if no file found
    """
    
    file_list= glob.glob( os.path.join(dir_name, file_pattern) )
    
    # If more than one, get latest (adapted from https://stackoverflow.com/a/39327156)
    if len(file_list) > 0 : 
        latest_file= max(file_list, key=os.path.getctime)
    else:
        latest_file= None
        
    if debug: print(f"DEBUG getLatest 863: Looking for '{file_pattern}', found '{latest_file}'")
    
    return latest_file

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
    
    if verbose : print(cmdline)
    
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
            print("\nERROR!! Cannot execute '%s'." % cmdline)
            if "OMPI_COMM_WORLD_RANK" in os.environ:
                print("Maybe try to remove 'OMPI_COMM_WORLD_RANK' from os.environ by using 'usempi=True' in 'system_call_23'.")
            print()
            exit(13)
        else:
            print("\nWARNING! Cannot execute '%s'\n" % cmdline)

    if usempi:
        os.environ["OMPI_COMM_WORLD_RANK"]= mpi_rank

def find_depth(item, depth=0):
    if hasattr(item, 'parent'):
        if item.parent() is None:
            return depth
        return find_depth(item.parent(), depth + 1)
    else:
        return depth
    
# Image creation & manipulation functions
def open_mrc(mrc_file):
    """
    Reads MRC file
    
    Parameters:
        mrc_file (str) : MRC filename
    
    Returns:
        MRC data as NumPy array
    """
    
    # Opens a mrc and returns it as a numpy array
    with mrcfile.open(mrc_file) as mrc:
        # Read the data from the MRC-stack as a NumPy array
        data = np.array(mrc.data)
        # Flipping around the X-axis because by default the x-axis is mirrored in numpy
        mirrored_data = np.flipud(data)
    return mirrored_data

def bin_nparray(data, binning=1):
    """
    Downsamples NumPy array
    
    Parameters:
        data : NumPy array
        binning (int) : downsampling factor
    
    Returns:
        downsampled NumPy array
    """
    
    # Bins a 2D numpy array according to binning factor provided
    height, width = data.shape
    
    # New dimensions after binning
    new_height = height // binning
    new_width = width // binning
    
    # Reshape the matrix into a new shape with the binned dimensions
    reshaped_matrix = data[:new_height * binning, :new_width * binning].reshape(new_height, binning, new_width, binning)
    
    # Take the mean along the binned axes (axis=1 and axis=3)
    binned_matrix = np.mean(reshaped_matrix, axis=(1, 3))
    
    return binned_matrix

def display_nparray(data):
    """
    Displays NumPy array as image
    
    Parameters:
        data : NumPy array
    """
    
    plt.imshow(data, cmap='gray')
    plt.axis('off')
    plt.show()
    return 0

def save_as_image(data, filename='file'):
    """
    Saves NumPy array as image
    
    Parameters:
        data : NumPy array
        filename (str) : filename
    """

    # Check if directory exists, if not create it
    file_path = filename
    directory = os.path.dirname(file_path)
    if not os.path.exists(directory):
        # Create the directory if it doesn't exist
        os.makedirs(directory)
    
    # Scale the array values to the range [0, 255]
    scaled_matrix = (data - np.min(data)) / (np.max(data) - np.min(data)) * 255
    
    # Convert the scaled array to unsigned 8-bit integers
    scaled_matrix = scaled_matrix.astype(np.uint8)
    
    # Create a PIL image from the array
    image = Image.fromarray(scaled_matrix, mode='L')
    
    # Save the image as a raw grayscale file
    image.save(filename, mode='L')
    
def writeAsText(data, filename, do_backup=False, verbose=False, description=''):
    """
    Write data as text
    
    Parameters:
        data : will change to list if not already a list
        filename
        backup (boolean)
        verbose (boolean)
        description (str)
    """
    
    # Convert to list if not already
    if not isinstance(data, list): data=[data]
        
    backup(filename, verbose=verbose)
    with open(filename, 'w') as fp:
        for item in data:
            fp.write("%s\n" % item)
    if verbose: print(f"Wrote {description}: {filename}")

def backup(filename, verbose=False):
    if os.path.exists(filename):
        found_vacancy = 0
        tiebreaker = 0
        shortdir = os.path.basename(os.path.dirname(filename))
        
        while not found_vacancy:
            test_filename = filename + '_' + str(tiebreaker)
            
            if os.path.exists(test_filename):
                tiebreaker += 1
            else:
                found_vacancy = 1
                short_old = os.path.join(shortdir, os.path.basename(filename))
                short_new = os.path.join(shortdir, os.path.basename(test_filename))
                os.rename(filename, test_filename)
                if verbose: print(f"\nRenamed '{os.path.basename(short_old)}' to '{os.path.basename(short_new)}'")
                
def countFiles(directory):
    # Count files (adapted from https://stackoverflow.com/a/16910459)
    total_files= 0
    for root, dirs, files in os.walk(directory):
        total_files+= len(files)
        
    return total_files
    
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
        "--new", "-n",
        action="store_true",
        help="Create a new JSON file from scratch, even if it exists")
    parser.add_argument(
        "--json", "-j",
        type=str,
        default='heatwave.json',
        help="JSON metadata file, will be created if it doesn't exist, and if the necessary inputs are provided")
    
    required= parser.add_argument_group(
        title="Input target or MDOC files",
        description="One of these types of files must be provided if JSON file doesn't exist.")
    
    required.add_argument(
        "--target_files", "-t",
        type=str,
        help="PACE target files (surrounded by quotes if more than one)")

    required.add_argument(
        "--mdoc_files", "-m",
        type=str,
        help="MDOC files (surrounded by quotes if more than one)")


    parameters= parser.add_argument_group(
        title="Parameters"
        )
    
    parameters.add_argument(
        '--no_imgs',
        action="store_true",
        help='Flag to skip image display')

    parameters.add_argument(
        "--imgsize",
        type=int,
        default=160,
        help=f"Image size")

    parameters.add_argument(
        '--expand',
        action="store_true",
        help="Flag to start with expanded tree")

    parameters.add_argument(
        "--verbose", "-v", "--verbosity",
        type=int,
        default=3,
        help=f"Screen verbosity [0..{MAX_VERBOSITY}]")
    """
    0: None, except errors & warnings
    1: One-time events
    2: Found target and MDOC files
    3: (default) Progress bar, warnings for each MDOC
    4: Summary of data types, executable calls
    5: (not used)
    6: Warnings for absent metadata
    7: Found MDOC files
    8: Stat line for each micrograph
    9: Dump JSON contents to screen
    """

    parameters.add_argument(
        '--no_rotate',
        action="store_true",
        help='Flag to skip auto-rotation during 3dmod display')

    parameters.add_argument(
        '--no_gui',
        action="store_true",
        help="Flag to skip GUI, only create JSON")

    parameters.add_argument(
        '--debug',
        action="store_true",
        help='Flag to add debugging information')


    doseinfo= parser.add_argument_group(
        title="Dose information",
        description="Information needed for dose calculation.")
    
    doseinfo.add_argument(
        "--dose", 
        type=float,
        help="Dose per micrograph, e-/A2")

    doseinfo.add_argument(
        "--frame_file",
        type=str,
        default='motioncor-frame.txt',
        help="MotionCor2 frames file")


    patterns= parser.add_argument_group(
        title="File patterns",
        description="Default values are established by SNARTomo.")
    
    patterns.add_argument(
        "--in_dir", "-i", 
        type=str,
        default='SNARTomo',
        help="Top-level directory for inputs")

    patterns.add_argument(
        "--settings",
        type=str,
        default='$IN_DIR/settings.txt',
        help="SNARTomo settings file ('$IN_DIR' will be replaced)")

    patterns.add_argument(
        "--movie_dir",
        type=str,
        default='frames',
        help="Movie directory (e.g., EER, TIF, MRC)")

    patterns.add_argument(
        "--micthumb_dir",
        type=str,
        default='Thumbnails',
        help="Directory relative to MDOC file")

    patterns.add_argument(
        "--tif_dir",
        type=str,
        default='$IN_DIR/1-Compressed',
        help="Relative path of compressed-movie directory ('$IN_DIR' will be replaced)")

    patterns.add_argument(
        "--mic_dir",
        type=str,
        default='$IN_DIR/2-MotionCor2',
        help="Relative path of motion-corrected micrograph directory ('$IN_DIR' will be replaced)")

    patterns.add_argument(
        "--mic_pattern",
        type=str,
        default='_mic.mrc',
        help="Suffix for motion-corrected micrograph, including extension")

    patterns.add_argument(
        "--micthumb_suffix",
        type=str,
        default='_newstack',
        help="Suffix appended to MDOC basename in micrograph thumbnail images (and pattern in micrograph stack ending in '.mrcs' or '.st')")

    patterns.add_argument(
        "--ctfthumb_suffix",
        type=str,
        default='_ctfstack_center',
        help="Suffix appended to MDOC basename in CTF thumbnail images (and pattern in CTF stack)")

    patterns.add_argument(
        "--recon_pattern",
        type=str,
        default='*_rec*mrc *_aretomo*.mrc',
        help="Pattern for reconstuctions (if more than one, separated by spaces)")

    patterns.add_argument(
        "--ctf_summary",
        type=str,
        default='SUMMARY_CTF.txt',
        help="CTFFIND4 summary file, in same directory as MDOC file")
    
    patterns.add_argument(
        "--ctfbyts_tgts",
        type=str,
        default='$IN_DIR/Images/ctfbyts*.png',
        help="File pattern for target-file CTF scatter plot ('$IN_DIR' will be replaced)")

    patterns.add_argument(
        "--ctfbyts_1ts",
        type=str,
        default='ctfbyts.png',
        help="Single-tilt-series CTF scatter plot, in same directory as MDOC file")

    patterns.add_argument(
        "--denoise_dir",
        type=str,
        default='$IN_DIR/4-Denoise',
        help="Relative path of denoised-micrograph directory ('$IN_DIR' will be replaced)")

    patterns.add_argument(
        "--ts_dir",
        type=str,
        default='$IN_DIR/5-Tomo/$MDOC_STEM',
        help="Relative path of tilt-series data directory ('$IN_DIR' and '$MDOC_STEM' will be replaced)")

    patterns.add_argument(
        "--orig_mdoc_suffix",
        type=str,
        default='.mrc.mdoc.orig',
        help="Pattern for original MDOC file up until the first '.', in same directory as current MDOC")

    patterns.add_argument(
        "--slice_jpg",
        type=str,
        default='_slice_norm.jpg',
        help="Suffix for central-slice image in MDOC directory, including extension")

    patterns.add_argument(
        "--dosefit_plot",
        type=str,
        default='*_dose_fit.png',
        help="Pattern for dose-fitting plot, in same directory as MDOC file")

    patterns.add_argument(
        "--stack_suffix",
        type=str,
        default='_restack',
        help="Suffix for restacking text output, without extension")

    patterns.add_argument(
        "--thumb_format",
        type=str,
        default='jpg',
        help="Image format for micrographs and power-spectrum thumbnails")

    patterns.add_argument(
        "--incinerate_dir",
        type=str,
        default='$IN_DIR/INCINERATE',
        help="Relative path of directory where incinerated files will be moved ('$IN_DIR' will be replaced)")


    paths= parser.add_argument_group(
        title="Executable paths",
        description="The following programs are used for display from the GUI.")
    
    paths.add_argument(
        "--imod_bin",
        type=str,
        default=None,
        help="IMOD binary directory (only needed if not in $PATH)")

    paths.add_argument(
        "--img_viewer",
        type=str,
        default='display',
        help="Image-viewer executable")

    return parser.parse_args()


if __name__ == '__main__':
    options = parse_command_line()
    # print(options)
    # exit(14)
    verbosity=options.verbose

    tree_app = QtWidgets.QApplication(sys.argv)
    window = MdocTreeView(options, debug=options.debug)
    sys.exit( tree_app.exec_() )
