#!/usr/bin/env fish

# Fish Function Reporter
# Analyzes and reports detailed information about Fish functions and their sources

function parse_function_source
    set func_name $argv[1]
    
    # Get function source file using functions -D
    set source_info (functions -D $func_name 2>/dev/null)
    
    if test -z "$source_info"
        return 1
    end
    
    set source_file ""
    set source_type ""
    set line_number ""
    
    # Parse source information
    if test "$source_info" = "stdin"
        set source_type "interactive"
        set source_file "interactive session"
    else if test -f "$source_info"
        set source_type "file"
        set source_file "$source_info"
        
        # Try to extract line number from function definition
        set func_def (functions $func_name)
        if string match -qr "# Defined in .* @ line (\d+)" $func_def
            set line_match (string match -r "# Defined in .* @ line (\d+)" $func_def)
            set line_number $line_match[2]
        end
    else
        set source_type "unknown"
        set source_file "$source_info"
    end
    
    echo $source_type
    echo $source_file
    echo $line_number
end

function analyze_function_definition
    set func_name $argv[1]
    
    # Get function definition
    set func_def (functions $func_name 2>/dev/null)
    
    if test -z "$func_def"
        return 1
    end
    
    set line_count (printf '%s\n' $func_def | wc -l)
    set has_arguments "false"
    set has_local_vars "false"
    set calls_commands "false"
    set complexity "simple"
    
    # Analyze function content
    if string match -q "*\$argv*" $func_def
        set has_arguments "true"
    end
    
    if string match -q "*set -l*" $func_def
        set has_local_vars "true"
    end
    
    # Look for command calls (simple heuristic)
    if string match -q "*|*" $func_def; or string match -q "*&&*" $func_def; or string match -q "*;*" $func_def
        set complexity "complex"
    else if test $line_count -gt 10
        set complexity "medium"
    end
    
    # Check for common command patterns
    if string match -q "*echo*" $func_def; or string match -q "*printf*" $func_def
        set calls_commands "true"
    end
    
    echo $line_count
    echo $has_arguments
    echo $has_local_vars
    echo $calls_commands
    echo $complexity
end

function check_function_conflicts
    set func_name $argv[1]
    
    set conflicts ""
    
    # Check for abbreviation with same name
    if abbr -q $func_name
        set conflicts "$conflicts abbreviation"
    end
    
    # Check for variable with same name
    if set -q $func_name
        set conflicts "$conflicts variable"
    end
    
    # Check for command with same name
    if type -q $func_name
        set cmd_type (type -t $func_name)
        if test "$cmd_type" != "function"  # avoid double-counting functions
            set conflicts "$conflicts $cmd_type"
        end
    end
    
    echo (string trim $conflicts)
end

function get_function_autoload_info
    set func_name $argv[1]
    
    # Check if function might be autoloaded
    set autoload_paths ~/.config/fish/functions /usr/share/fish/functions
    
    for path in $autoload_paths
        if test -f "$path/$func_name.fish"
            echo "autoload-available:$path/$func_name.fish"
            return
        end
    end
    
    echo "not-autoload"
end

function highlight_fish_syntax
    set line $argv[1]
    
    # Colors for syntax highlighting
    set KEYWORD_COLOR '\033[0;35m'    # Magenta for keywords
    set STRING_COLOR '\033[0;32m'     # Green for strings  
    set COMMENT_COLOR '\033[0;90m'    # Dark gray for comments
    set VARIABLE_COLOR '\033[0;36m'   # Cyan for variables
    set FUNCTION_COLOR '\033[1;33m'   # Bright yellow for function names
    set NC '\033[0m'
    
    # Simple approach: just highlight comments and make the text readable
    # Avoid complex regex that might interfere with Fish escaping
    
    set highlighted_line $line
    
    # Highlight comments (everything after #)
    if string match -q "*#*" $line
        set parts (string split -m 1 '#' $line)
        if test (count $parts) -eq 2
            set highlighted_line "$parts[1]$COMMENT_COLOR#$parts[2]$NC"
        end
    end
    
    # Simple keyword highlighting using string replace (safer than sed)
    if not string match -q "*#*" $line  # Don't modify lines with comments (already processed)
        # Highlight some key Fish keywords
        set highlighted_line (string replace -a " function " " $KEYWORD_COLOR""function$NC " $highlighted_line)
        set highlighted_line (string replace -a " end" " $KEYWORD_COLOR""end$NC" $highlighted_line)
        set highlighted_line (string replace -a " if " " $KEYWORD_COLOR""if$NC " $highlighted_line)
        set highlighted_line (string replace -a " else" " $KEYWORD_COLOR""else$NC" $highlighted_line)
        set highlighted_line (string replace -a " set " " $KEYWORD_COLOR""set$NC " $highlighted_line)
        set highlighted_line (string replace -a " echo " " $KEYWORD_COLOR""echo$NC " $highlighted_line)
        set highlighted_line (string replace -a " return " " $KEYWORD_COLOR""return$NC " $highlighted_line)
        set highlighted_line (string replace -a " test " " $KEYWORD_COLOR""test$NC " $highlighted_line)
        
        # Highlight function name in function declaration
        if string match -q "function *" $line
            set words (string split " " $line)
            if test (count $words) -ge 2
                set func_name $words[2]
                set highlighted_line (string replace " $func_name" " $FUNCTION_COLOR$func_name$NC" $highlighted_line)
            end
        end
    end
    
    echo -e "$highlighted_line"
end

function format_function_report
    set func_name $argv[1]
    
    # Colors for output
    set RED '\033[0;31m'
    set GREEN '\033[0;32m'
    set YELLOW '\033[0;33m'
    set BLUE '\033[0;34m'
    set MAGENTA '\033[0;35m'
    set CYAN '\033[0;36m'
    set WHITE '\033[1;37m'
    set NC '\033[0m' # No Color
    
    # Check if function exists
    if not functions -q $func_name
        echo -e "$RED""'$func_name' is not a function$NC"
        return 1
    end
    
    # Parse function source information
    set source_info (parse_function_source $func_name)
    if test (count $source_info) -lt 2
        echo -e "$RED""Unable to parse function source for '$func_name'$NC"
        return 1
    end
    
    set source_type $source_info[1]
    set source_file $source_info[2]
    set line_number $source_info[3]
    
    # Analyze function definition
    set analysis (analyze_function_definition $func_name)
    set line_count $analysis[1]
    set has_arguments $analysis[2]
    set has_local_vars $analysis[3]
    set calls_commands $analysis[4]
    set complexity $analysis[5]
    
    # Check for conflicts
    set conflicts (check_function_conflicts $func_name)
    
    # Get autoload information
    set autoload_info (get_function_autoload_info $func_name)
    
    # Generate report
    echo -e "$CYAN""Shell classification for '$WHITE$func_name$CYAN': function$NC"
    
    # Show conflicts if any
    if test -n "$conflicts"
        echo -e "$YELLOW""ℹ Also exists as: $conflicts$NC"
    end
    
    echo
    
    # Show source information
    switch $source_type
        case "interactive"
            echo -e "$MAGENTA""Source: $WHITE""Defined interactively$MAGENTA in current session$NC"
        case "file"
            echo -e "$MAGENTA""Source: $WHITE$source_file$NC"
            if test -n "$line_number"
                echo -e "$CYAN""Line: $WHITE$line_number$NC"
            end
        case "*"
            echo -e "$MAGENTA""Source: $WHITE$source_file$NC"
    end
    
    # Show function properties
    echo -e "$CYAN""Lines: $WHITE$line_count$NC"
    echo -e "$CYAN""Complexity: $WHITE$complexity$NC"
    
    if test "$has_arguments" = "true"
        echo -e "$GREEN""✓ Uses arguments (\$argv)$NC"
    end
    
    if test "$has_local_vars" = "true"
        echo -e "$GREEN""✓ Uses local variables$NC"
    end
    
    # Show autoload information
    if string match -q "autoload-available:*" $autoload_info
        set autoload_file (string sub -s 18 $autoload_info)
        echo -e "$YELLOW""ℹ Autoload available: $autoload_file$NC"
    end
    
    echo
    
    # Show function definition with syntax highlighting (truncated for long functions)
    echo -e "$GREEN""Function definition:$NC"
    set func_def (functions $func_name)
    
    if test $line_count -le 20
        # Show full definition for short functions
        printf '%s\n' $func_def | while read -l line
            set highlighted_line (highlight_fish_syntax $line)
            echo -e "  $highlighted_line"
        end
    else
        # Show truncated definition for long functions
        printf '%s\n' $func_def | head -n 10 | while read -l line
            set highlighted_line (highlight_fish_syntax $line)
            echo -e "  $highlighted_line"
        end
        echo -e "$YELLOW""  ... (truncated, $line_count total lines)$NC"
        # Show the end
        printf '%s\n' $func_def | tail -n 3 | while read -l line
            set highlighted_line (highlight_fish_syntax $line)
            echo -e "  $highlighted_line"
        end
    end
    
    # Show file contents preview if from file (but avoid redundancy for investigation function)
    if test "$source_type" = "file" -a -r "$source_file"
        set show_preview "true"
        
        # Skip source preview if this is the main investigation function to avoid redundancy
        if test "$func_name" = "i" -a (string match -q "*investigate.fish" "$source_file")
            set show_preview "false"
        end
        
        # Skip source preview for very short functions (already shown in definition)
        if test $line_count -le 10
            set show_preview "false"
        end
        
        if test "$show_preview" = "true"
            echo
            echo -e "$CYAN""Source file preview:$NC"
            echo -e "$YELLOW""File: $source_file$NC"
            if test -n "$line_number"
                echo -e "$YELLOW""Around line $line_number:$NC"
                # Show context around the function definition
                set start_line (math "$line_number - 2")
                if test $start_line -lt 1
                    set start_line 1
                end
                set end_line (math "$line_number + 5")
                sed -n "$start_line,$end_line"p "$source_file" 2>/dev/null | while read -l line
                    echo -e "$WHITE  $line$NC"
                end
            else
                echo -e "$WHITE""  (Line number not available)$NC"
            end
        end
    end
end

function demonstrate_function_reporter
    echo "Fish Function Reporter Demo"
    echo "==========================="
    echo
    
    # Create test functions
    function simple_func
        echo "Simple function"
    end
    
    function complex_func
        set -l local_var $argv[1]
        echo "Processing: $local_var"
        if test -n "$local_var"
            echo "Has argument" | string upper
        else
            echo "No argument"
        end
    end
    
    function recursive_func
        if test (count $argv) -gt 0
            echo "Level: $argv[1]"
            if test $argv[1] -gt 1
                recursive_func (math $argv[1] - 1)
            end
        end
    end
    
    echo "Created test functions for demo..."
    echo
    
    # Test each function
    set test_funcs simple_func complex_func recursive_func
    
    for func_name in $test_funcs
        format_function_report $func_name
        echo
    end
    
    # Clean up test functions
    functions -e simple_func complex_func recursive_func
    
    echo "Demo completed and test functions cleaned up."
end

# Main function - can be called with function name or run demo
# Only run if not being sourced by investigate.fish
if not set -q SOURCING_FOR_INVESTIGATE
    if test (count $argv) -eq 0
        demonstrate_function_reporter
    else if test "$argv[1]" = "--demo"
        demonstrate_function_reporter
    else
        format_function_report $argv[1]
    end
end