#!/usr/bin/env fish

# Fish Abbreviation Reporter
# Analyzes and reports detailed information about Fish abbreviations

function parse_abbreviation_definition
    set abbr_def $argv[1]
    
    # Parse the abbreviation definition line
    # Format: abbr -a [--position anywhere] [--regex pattern] -- name 'expansion'
    
    set name ""
    set expansion ""
    set position "command"  # default
    set pattern_type "literal"  # default
    set regex_pattern ""
    
    # Use regex to extract name and expansion more reliably
    if string match -qr "^abbr.*-- (\S+) '(.*)'" $abbr_def
        set matches (string match -r "^abbr.*-- (\S+) '(.*)'" $abbr_def)
        set name $matches[2]
        set expansion $matches[3]
    end
    
    # Check for position modifier
    if string match -q "*--position anywhere*" $abbr_def
        set position "anywhere"
    end
    
    # Check for regex pattern
    if string match -q "*--regex*" $abbr_def
        set pattern_type "regex"
        # Extract regex pattern - this is more complex
        if string match -qr "--regex '([^']+)'" $abbr_def
            set regex_matches (string match -r "--regex '([^']+)'" $abbr_def)
            set regex_pattern $regex_matches[2]
        else if string match -qr "--regex (\S+)" $abbr_def
            set regex_matches (string match -r "--regex (\S+)" $abbr_def)
            set regex_pattern $regex_matches[2]
        end
    end
    
    # Return parsed components as a list
    echo $name
    echo $expansion  
    echo $position
    echo $pattern_type
    echo $regex_pattern
end

function analyze_abbreviation_expansion
    set expansion $argv[1]
    
    # Extract the first word (command) from expansion
    set first_word (echo $expansion | string split " " | head -n1)
    
    # Check if the first word is a valid command
    set command_type ""
    set command_path ""
    
    if type -q $first_word
        set command_type (type -t $first_word)
        if test "$command_type" = "file"
            set command_path (type -p $first_word)
        end
    end
    
    echo $first_word
    echo $command_type
    echo $command_path
end

function check_abbreviation_conflicts
    set name $argv[1]
    
    set conflicts ""
    
    # Check for function with same name
    if functions -q $name
        set conflicts "$conflicts function"
    end
    
    # Check for command with same name
    if type -q $name
        set cmd_type (type -t $name)
        if test "$cmd_type" != "function"  # avoid double-counting functions
            set conflicts "$conflicts $cmd_type"
        end
    end
    
    # Check for variable with same name
    if set -q $name
        set conflicts "$conflicts variable"
    end
    
    echo (string trim $conflicts)
end

function format_abbreviation_report
    set name $argv[1]
    
    # Colors for output
    set RED '\033[0;31m'
    set GREEN '\033[0;32m'
    set YELLOW '\033[0;33m'
    set BLUE '\033[0;34m'
    set MAGENTA '\033[0;35m'
    set CYAN '\033[0;36m'
    set WHITE '\033[1;37m'
    set NC '\033[0m' # No Color
    
    # Check if abbreviation exists
    if not abbr -q $name
        echo -e "$RED""'$name' is not an abbreviation$NC"
        return 1
    end
    
    # Get abbreviation definition
    set abbr_def (abbr -s | grep -E "^abbr.*-- $name ")
    
    # Parse the definition
    set parsed (parse_abbreviation_definition $abbr_def)
    set abbr_name $parsed[1]
    set expansion $parsed[2]
    set position $parsed[3]
    set pattern_type $parsed[4]
    set regex_pattern $parsed[5]
    
    # Analyze expansion
    set expansion_analysis (analyze_abbreviation_expansion $expansion)
    set target_command $expansion_analysis[1]
    set target_type $expansion_analysis[2]
    set target_path $expansion_analysis[3]
    
    # Check for conflicts
    set conflicts (check_abbreviation_conflicts $name)
    
    # Generate report
    echo -e "$CYAN""Shell classification for '$WHITE$name$CYAN': abbreviation$NC"
    
    # Show conflicts if any
    if test -n "$conflicts"
        echo -e "$YELLOW⚠ Warning: '$name' also exists as $conflicts but is overshadowed by the abbreviation.$NC"
    end
    
    echo
    echo -e "$MAGENTA""Abbreviation expansion: '$WHITE$name$MAGENTA' → $expansion$NC"
    
    # Show abbreviation properties
    if test "$position" != "command"
        echo -e "$CYAN""Position: Can appear $position in the command line$NC"
    end
    
    if test "$pattern_type" = "regex"
        echo -e "$CYAN""Pattern type: Regular expression '$WHITE$regex_pattern$CYAN'$NC"
    end
    
    echo -e "$YELLOW""ℹ Note: Abbreviations only expand during interactive typing, not in scripts$NC"
    
    echo
    
    # Analyze expansion target
    if test -n "$target_type"
        echo -e "$GREEN""Expansion target '$WHITE$target_command$GREEN' is a $target_type$NC"
        if test "$target_type" = "file" -a -n "$target_path"
            echo -e "$GREEN""Located at: $YELLOW$target_path$NC"
        end
    else
        echo -e "$RED""⚠ Warning: Expansion target '$WHITE$target_command$RED' not found$NC"
    end
    
    # If expansion contains function calls, note it
    if string match -q "*(*)*" $expansion
        echo -e "$CYAN""ℹ Expansion contains function calls or command substitution$NC"
    end
end

function demonstrate_abbreviation_reporter
    echo "Fish Abbreviation Reporter Demo"
    echo "==============================="
    echo
    
    # Create test abbreviations in current session
    abbr gco 'git checkout'
    abbr -p anywhere ll 'ls -la'
    abbr current_time 'echo (date)'
    abbr fake_cmd 'nonexistent_program --flag'
    
    # Also create a function with same name as abbreviation to test conflicts
    function gco
        echo "This is the gco function"
    end
    
    echo "Created test abbreviations and function for demo..."
    echo
    
    # Test each abbreviation
    set test_abbrs gco ll current_time fake_cmd
    
    for abbr_name in $test_abbrs
        format_abbreviation_report $abbr_name
        echo
    end
    
    # Clean up test abbreviations
    abbr -e gco ll current_time fake_cmd 2>/dev/null
    functions -e gco 2>/dev/null
    
    echo "Demo completed and test abbreviations cleaned up."
end

# Main function - can be called with abbreviation name or run demo
# Only run if not being sourced by investigate.fish
if not set -q SOURCING_FOR_INVESTIGATE
    if test (count $argv) -eq 0
        demonstrate_abbreviation_reporter
    else if test "$argv[1]" = "--demo"
        demonstrate_abbreviation_reporter
    else
        format_abbreviation_report $argv[1]
    end
end