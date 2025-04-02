#############################
############## Dynamic option
#############################

# !!!!!!!!!!!
# Declare a dictionary/hashtable with the commandline options
# !!!!!!!!!!!

# This needs to be used in the dictionary
OPTION_SEP="1238sdf4134"

function add_argument() {
###############################################################################
#   Function:
#     Adds single argument
#   
#   Add arguments with the following form:
#     add_argument "OPTION_NAME" "DEFAULT_VALUE" "OPTION DESCRIPTION" "OPTION_TYPE"
#   Quotes are required.
#   
#   Valid option types are:
#     INT : integer
#     UINT : unsigned integer
#     FLOAT : floating point
#     BOOL : Boolean
#     FILE : filename, must exist
#     DIR : directory, must exist
#     REGEX : integer
#     ANY : arbitrary
#   Unassigned options will be assigned to array ARGS.
#   
#   Global variables:
#     original_vars : non-associative array
#     var_sequence : associative array, maintaining the order of the variables
#     argument_idx : index for ARGUMENTS key
#   
###############################################################################
        
    local key=$1
    local default=$2
    local description=$3
    local type=$4
    
    original_vars[${key}]="${default} ${OPTION_SEP} ${description} ${OPTION_SEP} ${type}"
    var_sequence+=(${key})
    
#     # DIAGNOSTIC
#     echo ${#var_sequence[@]} ${key}
    
    # Remember index for "arguments" key
    if [[ ${key} = ARGUMENTS ]]; then
        argument_idx=$(( ${#var_sequence[@]} - 1 ))
    fi
}

function print_arguments() {
    regex_split="^\(.*\)${OPTION_SEP}\(.*\)${OPTION_SEP}\(.*\)$"
    local section_counter=0
    
    echo -e "\n=== Input Settings, Value, Description ==="

    # Suppress keys
    for var_idx in "${!var_sequence[@]}"
    do
        # Check if there are any remaining section headings
        if [[ "${#section_vars[@]}" -gt "${section_counter}" ]]; then
            # Check if next section index is current var index
            if [[ "${section_sequence[${section_counter}]}" == "${var_idx}" ]]; then
                section_name=`echo ${section_vars[${var_idx}]} | awk -F" ${OPTION_SEP} " '{print $1}'`
                echo -e "${section_name}"
                let "section_counter++"
            fi
        fi
        
        key="${var_sequence[${var_idx}]}"
        description="$(echo "${original_vars[${key}]}" | sed "s|${regex_split}|\2|g")"
        echo -e "  --${key} \t${vars[${key}]} \t${description}"
    done
    echo ""
}

function add_section() {
###############################################################################
#   Function:
#     Adds single argument
#   
#   Add sections with the following form:
#     add section "SECTION NAME" "SECTION DESCRIPTION"
#   Quotes are required.
#   
#   Global variables:
#     var_sequence : associative array, maintaining the order of the variables
#     section_vars : non-associative array
#     section_sequence : records position of the sections
#   
###############################################################################
    
    # Positional arguments
    local section_name=$1
    local description=$2
    
    local curr_idx=${#var_sequence[@]}
    local curr_str="${section_name} ${OPTION_SEP} ${description}"
    
    # Update arrays
    section_sequence+=(${curr_idx})
    section_vars[${curr_idx}]="${curr_str}"
    
#     # DIAGNOSTIC
#     echo -e "${#section_vars[@]}" "${#section_sequence[@]}" "${curr_idx}" "${section_vars[${curr_idx}]}"
    
}

function dynamic_parser(){
###############################################################################
#   Function:
#     Top-level function for parsing command line
#   
#   Passed arguments:
#     ${@} : command-line arguments
#   
#   Calls functions:
#     clean_up_variables
#     format_help
#     format_options
#     suppress_entries
#     fill_dictionary
#     check_test_cases
#     sanity_checks
#   
#   Global variables:
#     original_vars : non-associative array, before cleaning
#     var_sequence : associative array, aintaining the order of the variables
#     commandline_args : command-line arguments, may be modified
#     vars : final options array
#     ARGS : command-line arguments not accounted for as options will be here
#   
#   Unused/optional functions:
#     print_arguments
#     print_vars
#     do_unit_test
#   
###############################################################################

    commandline_args=("$@")
    
    clean_up_variables
    format_help
    format_options
    suppress_entries
    fill_dictionary "${commandline_args[@]}"
    check_test_cases "${commandline_args[@]}"
    sanity_checks
}    
    
    function clean_up_variables() {
        for idx in "${!var_sequence[@]}"
        do
            key="${var_sequence[${idx}]}"
#             echo    "ORIGINAL ${original_vars[${key}]}"
            # Remove leading and trailing whitespaces from the help
            cleaned_version=$(echo "${original_vars[${key}]}" | sed 's|^ *||g' | sed 's| *$||g' | sed "s| *${OPTION_SEP} *|${OPTION_SEP}|g")
#             echo -e "FINAL    ${cleaned_version}\n"
            original_vars[${key}]="${cleaned_version}"
            vars[${key}]="${original_vars[${key}]}"
        done
    }
    
    function format_help() {
        # This is dynamic to create the help based on the dictionary
        usage="
        Usage:
        bash ${0} "

        regex_split="^\(.*\)${OPTION_SEP}\(.*\)${OPTION_SEP}\(.*\)$"

        unset_array=()
        has_arguments=false
        tmp_usage=""
        
        # Suppress keys
        for var_idx in "${!var_sequence[@]}"
        do
            key="${var_sequence[${var_idx}]}"
            default_value=$(echo "${vars[${key}]}" | sed "s|${regex_split}|\1|g")
            sanity_check=$(echo "${original_vars[${key}]}" | sed "s|${regex_split}|\3|g")
            
            if ! [[ ${key} =~ _SUPPRESS$ ]]; then
                if [[ ${sanity_check} = BOOL ]]; then
                    tmp_usage+="--${key,,} "
                    diag_usage="--${key,,} "
                elif [[ ${key} = ARGUMENTS ]]; then
                    usage+="arg1 arg2 .. argN "
                    has_arguments=true
                else
                    local value=$(echo "${vars[${key}]}" | sed "s|${regex_split}|\1|g")
                    if [[ "${value}" == '' ]] ; then
                        tmp_usage+="--${key,,}='' "
                        diag_usage="--${key,,}='' "
                    else
                        tmp_usage+="--${key,,}=${value} "
                        diag_usage="--${key,,}=${value} "
                    fi
                fi
                    
#                 echo "var_idx ${var_idx} key ${key} var_sequence[var_idx]"
            else
                use_key=${key%_SUPPRESS}
                tmp_usage+="--${use_key,,} "
                diag_usage="--${use_key,,} "
                
                # Replace key in vars array
                vars[${use_key}]="${vars[${key}]}"
                unset vars[${key}]
                unset var_sequence[${var_idx}]
                unset_array=("${unset_array[@]}" "${use_key}")
                    
#                 echo "var_idx ${var_idx} key ${key} use_key ${use_key} vars[use_key]"
            fi
        done
        usage+="${tmp_usage}\n"
        
        # Format variables
        if [[ ${has_arguments} = true ]]; then
            default_value=$(echo "${vars["ARGUMENTS"]}" | sed "s|${regex_split}|\1|g")
# #             var_type=$(echo "${vars["ARGUMENTS"]}" | sed "s|${regex_split}|\3|g")
# #             var_description=$(echo "${vars["ARGUMENTS"]}" | sed "s|${regex_split}|\2|g")
            usage+="
        ARGUMENTS
            Description: $(echo "${vars["ARGUMENTS"]}" | sed "s|${regex_split}|\2|g")
            Type: $(echo "${vars["ARGUMENTS"]}" | sed "s|${regex_split}|\3|g")
            Default: ${default_value}\n\n"

            unset vars["ARGUMENTS"]
            unset var_sequence[${argument_idx}]
        fi
        
        usage+="\n"
    }

    function format_options() {
        local section_counter=0
    
        # Format options
        for var_idx in "${!var_sequence[@]}"
        do
            # Check if there are any remaining section headings
            if [[ "${#section_vars[@]}" -gt "${section_counter}" ]]; then
                # Check if next section index is current var index
                if [[ "${section_sequence[${section_counter}]}" == "${var_idx}" ]]; then
                    section_name=`echo ${section_vars[${var_idx}]} | awk -F" ${OPTION_SEP} " '{print $1}'`
                    section_description=`echo ${section_vars[${var_idx}]} | awk -F" ${OPTION_SEP} " '{print $2}'`
                    usage+="        ${section_name}\n          ${section_description}\n\n"
                    let "section_counter++"
                fi
            fi
            
            key="${var_sequence[${var_idx}]}"
            default_value=$(echo "${vars[${key}]}" | sed "s|${regex_split}|\1|g")
    #         echo ${var_idx} ${key} ${default_value}
            usage+="          --${key,,}\n"
            usage+="              Description: $(echo "${vars[${key}]}" | sed "s|${regex_split}|\2|g")\n"
            usage+="              Type: $(echo "${vars[${key}]}" | sed "s|${regex_split}|\3|g")\n"
            usage+="              Default: ${default_value}\n\n"

            vars[${key}]="${default_value}"
        done
    }
    
    function suppress_entries() {
    
        # Remove suppressed entries
        for entry in ${unset_array[@]}
        do
            unset vars[${entry}]
        done
    }
    
    function fill_dictionary() {
        # Fill the dictionary with the provided options dynamically
        for idx in "${!var_sequence[@]}"
        do
            key="${var_sequence[${idx}]}"
            sanity_check=$(echo "${original_vars[${key}]}" | sed "s|${regex_split}|\3|g")
            next=false
            new_cmd=()
            for arg in "${commandline_args[@]}"
            do
                if [[ ${next} != false ]]
                then
                    missing_argument=false
                    for idx in "${!var_sequence[@]}"
                    do
                        key_comp="${var_sequence[${idx}]}"
                        if [[ "${arg}" =~ --${key_comp,,} ]]
                        then
                            missing_argument=true
                        fi
                    done

                    if [[ ${missing_argument} = true ]]
                    then
                        echo "ERROR: option --${key,,} cannot be empty!"
                        exit 1
                    fi
                    vars["${key}"]="${arg}"
                    next=false
                elif [[ ${arg} =~ --${key,,}= ]]
                then
                    vars["${key}"]="${arg#*=}"
                    next=false
                elif [[ ${arg} =~ ^--${key,,}$ ]]
                then
                    next=false
                    if [[ ${sanity_check} = BOOL ]]
                    then
                        vars["${key}"]=true
                    else
                        vars["${key}"]=""
                        next=${key}
                    fi
                else
                    new_cmd=("${new_cmd[@]}" "${arg}")
                fi
            done
            commandline_args=("${new_cmd[@]}")
        done
    }

    function check_test_cases() {
        do_setx=false
        for i in "${commandline_args[@]}"
        do
        case $i in

            -h|--help)
            # Use help also with -h even though it is not put in the help automatically, yet.
            echo -e "${usage}"
            exit 1
            shift # past argument=value
            ;;

            --verbose_setx)
            # Enable set -x after succesful error check
            do_setx=true
            shift
            ;;

            --test_me)
            # Run unit tests
            do_unit_test
            exit 1
            shift # past argument=value
            ;;

            *)
            # Everything else is treated as an input folder
            ARGS=("${ARGS[@]}" "$i")
            shift
            ;;
        esac
        done

        if [[ ${do_setx} = true ]]
        then
            set -x
        fi
    }

    function do_unit_test() {
        echo "No unit tests installed, yet"
    }

    function sanity_checks() {
    # Sanity checks for data type
    error=false
    for idx in "${!var_sequence[@]}"
    do
        key="${var_sequence[${idx}]}"
        sanity_check=$(echo "${original_vars[${key}]}" | sed "s|${regex_split}|\3|g")
        value="${vars[${key}]}"
#         echo "key '${key}' value '${value}' "
        
        if [[ ${sanity_check} = BOOL ]]
        then
            : # pass do nothing
        elif [[ ${sanity_check} = ANY ]]
        then
            : # pass do nothing
        elif [[ -z ${value} ]]
        then
            echo "--${key,,}" cannot be empty!
            error=true
#         elif [[ ${sanity_check} = ANY ]]
#         then
#             : # pass do nothing
        elif [[ ${sanity_check} = FILE ]]
        then
            if [[ ! -f ${value} ]]
            then
                echo Input to --${key,,} needs to be an existing file!
                error=true
            fi
        elif [[ ${sanity_check} = DIR ]]
        then
            if [[ ! -d ${value} ]]
            then
                echo Input to --${key,,} needs to be an existing directory!
                error=true
            fi
        else
            sanity_regex=${sanity_check}
            sanity_message=${sanity_regex}
            case ${sanity_check} in
                INT)
                sanity_regex=^[0-9-]*$
                ;;
                UINT)
                sanity_regex=^[0-9]*$
                ;;
                FLOAT)
                sanity_regex=^[0-9.-]*$
                ;;
            esac
            if [[ ! ${value} =~ ${sanity_regex} ]]
            then
                echo Input to --${key,,} needs to follow ${sanity_message}
                error=true
            fi
        fi
    done

    if [[ ${error} = true ]]
    then
        echo Error detected in input settings! Abort.
        exit 1
    fi
}

function print_vars(){
###############################################################################
#   Function:
#     Prints variables
#   
#   Global variables:
#     vars : final options array
#     var_sequence : associative array, maintaining the order of the variables
#     section_vars : non-associative array
#     section_sequence : records position of the sections
#   
###############################################################################
    
    # Print to screen
    echo "=== Input Settings ==="
    echo "Input args: ${ARGS[@]}"
    
    local section_counter=0
    
    for var_idx in "${!var_sequence[@]}"
    do
        # Check if there are any remaining section headings
        if [[ "${#section_vars[@]}" -gt "${section_counter}" ]]; then
            # Check if next section index is current var index
            if [[ "${section_sequence[${section_counter}]}" == "${var_idx}" ]]; then
                section_name=`echo ${section_vars[${var_idx}]} | awk -F" ${OPTION_SEP} " '{print $1}'`
                echo -e "\n${section_name}"
                let "section_counter++"
            fi
        fi
        
        key="${var_sequence[${var_idx}]}"
        echo "  --${key,,}=""${vars[${key}]}"
    done
}

#######
#
# Move this section to the actual script and just source this argumentparser from there if you want to use it as a module
#
#######

declare -A original_vars
declare -a var_sequence
declare -A vars
declare -A section_vars
declare -a section_sequence

# If running as a standalone script, then run this test.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    add_section "NUMERICAL ARGUMENTS" "Description"
    # integer
    add_argument "OPTION_INT" "-888" "OPTIONARG0 description." "INT"
    # Positive integer
    add_argument "OPTION_UINT" "888" "OPTIONARG1 description." "UINT"
    # Float value
    add_argument "OPTION_FLOAT" "-888.8" "OPTIONARG2 description." "FLOAT"
    add_section "STRING/OTHER ARGUMENTS" "Description"
    # Can be anything
    add_argument "OPTION_ANY" "DEFAULT_OPTIONARG3_VALUE" "OPTIONARG3 description." "ANY"
    # Is an existing file
    add_argument "OPTION_FILE" "${0}" "OPTIONARG4 description." "FILE"
    # Is an existing directory
    add_argument "OPTION_DIR" "." "OPTIONARG5 description." "DIR"
    # Is an bool, note that the default value needs to be false
    add_argument "OPTION_BOOL" "false" "OPTIONARG5 description." "BOOL"
    # Specific regex
    add_argument "OPTION_REGEX" "Huhu" "OPTIONARG6 description." "^Huhu$"
    # This is the description for non option arguments. Needs to be named ARGUMENTS.
    add_argument "ARGUMENTS" "Unknown args treated as input." "Description for undefined names" "ANY"
    # Arguments with default special behaviour defined with _SUPPRESS which will be removed in the process.
    add_argument "TEST_ME_SUPPRESS" "false" "If you have unit tests, you can run the test_me command to run them" "BOOL"
    add_argument "HELP_SUPPRESS" "false" "Show the usage instructions." "BOOL"
    add_argument "VERBOSE_SETX_SUPPRESS" "false" "Enable set -x after option parsing" "BOOL"

    dynamic_parser "${@}"
#     print_vars
    print_arguments
fi
