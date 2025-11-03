#!/usr/bin/env fish

# Fish Investigation Tool (investigate.fish)
# Port of the Bash investigate.sh tool for Fish shell
# Provides comprehensive analysis of Fish shell objects: functions, variables, abbreviations, builtins, and commands

# Source the component reporters (but don't run their demos)
set script_dir (dirname (status --current-filename))

# Define a marker to prevent demos from running
set -g SOURCING_FOR_INVESTIGATE true

source $script_dir/fish_abbreviation_reporter.fish
source $script_dir/fish_variable_reporter.fish  
source $script_dir/fish_function_reporter.fish
source $script_dir/fish_command_reporter.fish

set -e SOURCING_FOR_INVESTIGATE

# Colors for output
set -g RED '\033[0;31m'
set -g GREEN '\033[0;32m'
set -g YELLOW '\033[0;33m'
set -g BLUE '\033[0;34m'
set -g MAGENTA '\033[0;35m'
set -g CYAN '\033[0;36m'
set -g WHITE '\033[1;37m'
set -g NC '\033[0m' # No Color

function show_usage
    echo "Fish Investigation Tool"
    echo "======================"
    echo
    echo "Usage: i [OPTIONS] <name>"
    echo
    echo "Investigates Fish shell objects and provides detailed information about:"
    echo "  • Functions (with source tracking)" 
    echo "  • Variables (with scope analysis)"
    echo "  • Abbreviations (with expansion analysis)"
    echo "  • Builtins and external commands"
    echo "  • Conflicts and shadowing between different object types"
    echo
    echo "Options:"
    echo "  -h, --help         Show this help message"
    echo "  -f, --functions    Show only functions"
    echo "  -v, --variables    Show only variables"
    echo "  -a, --abbreviations Show only abbreviations"
    echo "  -b, --builtins     Show only builtins"
    echo "  -c, --commands     Show only external commands"
    echo "  --all              Show all object types (default)"
    echo
    echo "Examples:"
    echo "  i ls               # Investigate 'ls' command"
    echo "  i --functions foo  # Show only if 'foo' is a function"
    echo "  i --variables PATH # Show only PATH variable details"
    echo "  i --abbreviations gco # Show only if 'gco' is an abbreviation"
end

function detect_all_object_types
    set target_name $argv[1]
    
    set object_types
    
    # Check for abbreviation
    if abbr -q $target_name
        set object_types $object_types "abbreviation"
    end
    
    # Check for variable
    if set -q $target_name
        set object_types $object_types "variable"
    end
    
    # Check for function
    if functions -q $target_name
        set object_types $object_types "function"
    end
    
    # Check for builtin/command using type
    if type -q $target_name
        set cmd_type (type -t $target_name)
        if test "$cmd_type" = "builtin"
            set object_types $object_types "builtin"
        else if test "$cmd_type" = "file"
            set object_types $object_types "command"
        end
    end
    
    printf '%s\n' $object_types
end

function determine_primary_object_type
    set target_name $argv[1]
    set all_types $argv[2..]
    
    # Fish resolution order (similar to bash but with abbreviations)
    # 1. Abbreviations (only during interactive typing)
    # 2. Functions
    # 3. Builtins  
    # 4. External commands
    # Note: Variables don't conflict since they use $ syntax
    
    for priority_type in "function" "builtin" "command" "abbreviation" "variable"
        if contains $priority_type $all_types
            echo $priority_type
            return
        end
    end
    
    # Fallback to first type found
    if test (count $all_types) -gt 0
        echo $all_types[1]
    else
        echo "unknown"
    end
end

function check_fish_conflicts
    set target_name $argv[1]
    set all_types $argv[2..]
    
    # In Fish, actual conflicts occur between:
    # - Functions vs builtins vs external commands
    # - Abbreviations exist separately (only work during typing)
    # - Variables use $ syntax so don't conflict with command names
    
    set conflicting_types
    set informational_types
    
    for obj_type in $all_types
        switch $obj_type
            case "function" "builtin" "command"
                set conflicting_types $conflicting_types $obj_type
            case "abbreviation" "variable"
                set informational_types $informational_types $obj_type
        end
    end
    
    echo "conflicting:"(string join ' ' $conflicting_types)
    echo "informational:"(string join ' ' $informational_types)
end

function show_object_conflicts
    set target_name $argv[1]
    set all_types $argv[2..]
    set primary_type $argv[-1]
    
    if test (count $all_types) -le 1
        return
    end
    
    set conflict_info (check_fish_conflicts $target_name $all_types)
    
    for line in $conflict_info
        if string match -q "conflicting:*" $line
            set conflicting (string sub -s 13 $line)
            if test -n "$conflicting" -a (count (string split ' ' $conflicting)) -gt 1
                set others
                for type in (string split ' ' $conflicting)
                    if test "$type" != "$primary_type"
                        set others $others $type
                    end
                end
                if test (count $others) -gt 0
                    set others_str (string join ', ' $others)
                    echo -e "$YELLOW⚠ Warning: '$target_name' also exists as $others_str but is overshadowed by the $primary_type.$NC"
                end
            end
        else if string match -q "informational:*" $line
            set informational (string sub -s 15 $line)
            for info_type in (string split ' ' $informational)
                switch $info_type
                    case "abbreviation"
                        echo -e "$CYAN""ℹ Also available as abbreviation (expands during typing)$NC"
                    case "variable"
                        echo -e "$CYAN""ℹ Also available as variable: \$$target_name$NC"
                end
            end
        end
    end
end

function i
    # Parse arguments
    set target_name ""
    set filter_type "all"
    
    # Simple argument parsing for Fish
    set i 1
    while test $i -le (count $argv)
        switch $argv[$i]
            case "-h" "--help"
                show_usage
                return 0
            case "-f" "--functions"
                set filter_type "function"
            case "-v" "--variables" 
                set filter_type "variable"
            case "-a" "--abbreviations"
                set filter_type "abbreviation"
            case "-b" "--builtins"
                set filter_type "builtin"
            case "-c" "--commands"
                set filter_type "command"
            case "--all"
                set filter_type "all"
            case "*"
                if test -z "$target_name"
                    set target_name $argv[$i]
                else
                    echo -e "$RED""Error: Multiple targets specified. Use only one target name.$NC"
                    return 1
                end
        end
        set i (math $i + 1)
    end
    
    # Check if target name provided
    if test -z "$target_name"
        echo -e "$RED""Error: No target name provided.$NC"
        echo "Use 'i --help' for usage information."
        return 1
    end
    
    # Detect all object types for the target
    set all_types (detect_all_object_types $target_name)
    
    if test (count $all_types) -eq 0
        echo -e "$RED""'$target_name' not found as any Fish object type.$NC"
        return 1
    end
    
    # Apply filter if specified
    if test "$filter_type" != "all"
        if not contains $filter_type $all_types
            echo -e "$RED""'$target_name' is not a $filter_type.$NC"
            return 1
        end
        set all_types $filter_type
    end
    
    # Determine primary type for display order
    set primary_type (determine_primary_object_type $target_name $all_types)
    
    # Show primary object first
    echo -e "$CYAN""=== Primary: $target_name ($primary_type) ===$NC"
    
    switch $primary_type
        case "abbreviation"
            format_abbreviation_report $target_name
        case "variable"
            format_variable_report $target_name
        case "function"
            format_function_report $target_name
        case "builtin" "command"
            format_command_report $target_name
        case "*"
            echo -e "$RED""Unknown object type: $primary_type$NC"
    end
    
    echo
    
    # Show conflicts/additional information
    show_object_conflicts $target_name $all_types $primary_type
    
    # Show additional object types if multiple exist and not filtered
    if test "$filter_type" = "all" -a (count $all_types) -gt 1
        echo
        echo -e "$CYAN""=== Additional Definitions ===$NC"
        
        for obj_type in $all_types
            if test "$obj_type" != "$primary_type"
                echo
                echo -e "$MAGENTA""--- $target_name as $obj_type ---$NC"
                
                switch $obj_type
                    case "abbreviation"
                        format_abbreviation_report $target_name
                    case "variable"
                        format_variable_report $target_name
                    case "function"
                        format_function_report $target_name
                    case "builtin" "command"
                        format_command_report $target_name
                end
            end
        end
    end
    
    return 0
end

# Set up Fish completions for the i function
# Clear any existing completions first to avoid conflicts
complete -c i -e

# Add basic flag completions
complete -c i -f
complete -c i -s h -l help -d "Show help message"
complete -c i -s f -l functions -d "Show only functions"
complete -c i -s v -l variables -d "Show only variables"
complete -c i -s a -l abbreviations -d "Show only abbreviations"
complete -c i -s b -l builtins -d "Show only builtins"
complete -c i -s c -l commands -d "Show only external commands"
complete -c i -l all -d "Show all object types (default)"

# Helper function to get only user-defined functions (excluding builtins)
function __fish_get_user_functions
    # Get all functions, then filter out those that are also builtins
    for func in (functions -n)
        if not builtin -q $func
            echo $func
        end
    end
end

# Context-aware completions based on filter flags
# When -f/--functions is specified, only complete with function names (excluding builtins)
complete -c i -f -n "__fish_contains_opt -s f functions" -a "(__fish_get_user_functions)"

# When -v/--variables is specified, only complete with variable names
complete -c i -f -n "__fish_contains_opt -s v variables" -a "(set -n)"

# When -a/--abbreviations is specified, only complete with abbreviation names
complete -c i -f -n "__fish_contains_opt -s a abbreviations" -a "(abbr -l)"

# When -b/--builtins is specified, only complete with builtin commands
complete -c i -f -n "__fish_contains_opt -s b builtins" -a "(builtin -n)"

# When -c/--commands is specified, only complete with external commands (from PATH)  
complete -c i -f -n "__fish_contains_opt -s c commands" -a "(__fish_complete_command)"

# Default completion (no filter flags): complete with all available commands, functions, etc.
complete -c i -f -n "not __fish_contains_opt -s f functions; and not __fish_contains_opt -s v variables; and not __fish_contains_opt -s a abbreviations; and not __fish_contains_opt -s b builtins; and not __fish_contains_opt -s c commands; and not __fish_contains_opt -s h help" -a "(__fish_complete_command)"

echo "Fish Investigation Tool loaded. Use 'i --help' for usage information."