#!/usr/bin/env fish

# Fish Variable Reporter
# Analyzes and reports detailed information about Fish variables and their scoping

function parse_variable_info
    set var_name $argv[1]
    
    # Get variable info using set -S
    set var_info_lines (set -S $var_name 2>/dev/null)
    
    if test (count $var_info_lines) -eq 0
        return 1
    end
    
    # Parse the variable information
    # First line format: $var_name: set in [scope] scope, [exported/unexported], with N elements
    # Following lines format: $var_name[N]: |value|
    
    set scope ""
    set exported "false"
    set element_count 0
    set value_lines
    
    set info_line $var_info_lines[1]
    
    # Extract scope information from first line
    if string match -q "*set in local scope*" $info_line
        set scope "local"
    else if string match -q "*set in global scope*" $info_line
        set scope "global"
    else if string match -q "*set in universal scope*" $info_line
        set scope "universal"
    else if string match -q "*set in function scope*" $info_line
        set scope "function"
    end
    
    # Check if exported from first line
    if string match -q "*unexported*" $info_line
        set exported "false"
    else if string match -q "*exported*" $info_line
        set exported "true"
    end
    
    # Extract element count from first line
    if string match -qr "with (\d+) elements" $info_line
        set count_match (string match -r "with (\d+) elements" $info_line)
        set element_count $count_match[2]
    end
    
    # Extract value lines (skip the first info line)
    if test (count $var_info_lines) -gt 1
        set value_lines $var_info_lines[2..]
    end
    
    # Return parsed components
    echo $scope
    echo $exported  
    echo $element_count
    printf '%s\n' $value_lines
end

function analyze_variable_type
    set var_name $argv[1]
    set element_count $argv[2]
    set value_lines $argv[3..]
    
    set var_type "scalar"
    set description ""
    
    if test $element_count -gt 1
        set var_type "array"
        set description "Array with $element_count elements"
    else if test $element_count -eq 1
        # Check if it's a special variable type
        if string match -q "*=*" $value_lines[1]
            set var_type "associative"
            set description "Key-value pair"
        else
            set var_type "scalar"
            set description "Single value"
        end
    else
        set var_type "empty"
        set description "Empty variable"
    end
    
    echo $var_type
    echo $description
end

function check_variable_conflicts
    set var_name $argv[1]
    
    set conflicts ""
    
    # Check for function with same name
    if functions -q $var_name
        set conflicts "$conflicts function"
    end
    
    # Check for abbreviation with same name
    if abbr -q $var_name
        set conflicts "$conflicts abbreviation"
    end
    
    # Check for command with same name (but not if it's a function we already found)
    if type -q $var_name
        set cmd_type (type -t $var_name)
        if test "$cmd_type" != "function"
            set conflicts "$conflicts $cmd_type"
        end
    end
    
    echo (string trim $conflicts)
end

function get_variable_special_properties
    set var_name $argv[1]
    
    set properties ""
    
    # Check if it's a special Fish variable
    switch $var_name
        case "PATH"
            set properties "$properties special:PATH"
        case "HOME"
            set properties "$properties special:HOME"
        case "USER" 
            set properties "$properties special:USER"
        case "PWD"
            set properties "$properties special:PWD"
        case "fish_*"
            set properties "$properties special:fish-config"
        case "_*"
            set properties "$properties special:private"
    end
    
    # Check if it's readonly (Fish doesn't have readonly like bash, but some vars are special)
    switch $var_name
        case "version" "FISH_VERSION" "hostname" "status"
            set properties "$properties readonly"
    end
    
    echo (string trim $properties)
end

function format_variable_scope_description
    set scope $argv[1]
    set exported $argv[2]
    
    set description ""
    
    switch $scope
        case "local"
            set description "Local to current function"
        case "global"  
            set description "Global to current session"
        case "universal"
            set description "Universal across all sessions"
        case "function"
            set description "Function-scoped"
        case "*"
            set description "Unknown scope"
    end
    
    if test "$exported" = "true"
        set description "$description, exported to child processes"
    else
        set description "$description, not exported"
    end
    
    echo $description
end

function format_variable_report
    set var_name $argv[1]
    
    # Colors for output
    set RED '\033[0;31m'
    set GREEN '\033[0;32m'
    set YELLOW '\033[0;33m'
    set BLUE '\033[0;34m'
    set MAGENTA '\033[0;35m'
    set CYAN '\033[0;36m'
    set WHITE '\033[1;37m'
    set NC '\033[0m' # No Color
    
    # Check if variable exists
    if not set -q $var_name
        echo -e "$RED""'$var_name' is not a variable$NC"
        return 1
    end
    
    # Parse variable information
    set parsed (parse_variable_info $var_name)
    if test (count $parsed) -lt 3
        echo -e "$RED""Unable to parse variable information for '$var_name'$NC"
        return 1
    end
    
    set scope $parsed[1]
    set exported $parsed[2]
    set element_count $parsed[3]
    set value_lines $parsed[4..]
    
    # Analyze variable type
    set type_info (analyze_variable_type $var_name $element_count $value_lines)
    set var_type $type_info[1]
    set type_description $type_info[2]
    
    # Check for conflicts
    set conflicts (check_variable_conflicts $var_name)
    
    # Get special properties
    set properties (get_variable_special_properties $var_name)
    
    # Generate report
    echo -e "$CYAN""Shell classification for '$WHITE\$$var_name$CYAN': variable$NC"
    
    # Show conflicts if any
    if test -n "$conflicts"
        echo -e "$YELLOW""ℹ Also exists as: $conflicts$NC"
    end
    
    echo
    
    # Show scope and export status
    set scope_desc (format_variable_scope_description $scope $exported)
    echo -e "$MAGENTA""Scope: $WHITE$scope$MAGENTA ($scope_desc)$NC"
    
    # Show variable type and element count
    echo -e "$CYAN""Type: $WHITE$var_type$CYAN ($type_description)$NC"
    
    # Show special properties if any
    if test -n "$properties"
        echo -e "$YELLOW""Properties: $properties$NC"
    end
    
    echo
    
    # Show variable contents
    echo -e "$GREEN""Variable contents:$NC"
    
    if test $element_count -eq 0
        echo -e "$YELLOW""  (empty)$NC"
    else if test $element_count -le 5
        # Show all elements for small arrays
        for line in $value_lines
            echo -e "$WHITE""  $line$NC"
        end
    else
        # Show first few elements for large arrays
        set shown_count 0
        for line in $value_lines
            if test $shown_count -lt 3
                echo -e "$WHITE""  $line$NC"
                set shown_count (math $shown_count + 1)
            else
                break
            end
        end
        set remaining (math $element_count - 3)
        echo -e "$YELLOW""  ... and $remaining more elements$NC"
    end
    
    # Special handling for PATH-like variables
    if test "$var_name" = "PATH" -o "$var_name" = "MANPATH" -o "$var_name" = "LD_LIBRARY_PATH"
        echo
        echo -e "$CYAN""Path analysis:$NC"
        set path_count 0
        set valid_paths 0
        set invalid_paths 0
        
        for path_element in $$var_name
            set path_count (math $path_count + 1)
            if test -d "$path_element"
                set valid_paths (math $valid_paths + 1)
            else
                set invalid_paths (math $invalid_paths + 1)
            end
        end
        
        echo -e "$GREEN""  Total paths: $path_count$NC"
        echo -e "$GREEN""  Valid directories: $valid_paths$NC"
        if test $invalid_paths -gt 0
            echo -e "$RED""  Invalid/missing paths: $invalid_paths$NC"
        end
    end
end

function demonstrate_variable_reporter
    echo "Fish Variable Reporter Demo"
    echo "==========================="
    echo
    
    # Create test variables in current session
    set -l local_test "local value"
    set -g global_test "global value"
    set -x exported_test "exported value"
    set -g array_test one two three four five six
    set -g empty_test
    
    echo "Created test variables for demo..."
    echo
    
    # Test each variable type
    set test_vars local_test global_test exported_test array_test empty_test PATH
    
    for var_name in $test_vars
        format_variable_report $var_name
        echo
    end
    
    echo "Demo completed."
end

# Main function - can be called with variable name or run demo
# Only run if not being sourced by investigate.fish
if not set -q SOURCING_FOR_INVESTIGATE
    if test (count $argv) -eq 0
        demonstrate_variable_reporter
    else if test "$argv[1]" = "--demo"
        demonstrate_variable_reporter
    else
        format_variable_report $argv[1]
    end
end