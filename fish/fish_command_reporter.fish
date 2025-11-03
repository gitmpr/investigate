#!/usr/bin/env fish

# Fish Command Reporter
# Analyzes and reports detailed information about Fish builtins and external commands

function detect_command_type
    set command_name $argv[1]
    
    # Use Fish's type command to get detailed information
    set type_output (type -a $command_name 2>/dev/null)
    
    if test -z "$type_output"
        echo "not-found"
        return 1
    end
    
    # Parse the type output to get all forms
    set results
    
    for line in $type_output
        if string match -q "*is a builtin*" $line
            set results $results "builtin:builtin"
        else if string match -q "*is a function*" $line
            set results $results "function:function"
        else if string match -qr ".*is (.+)" $line
            set path_match (string match -r ".*is (.+)" $line)
            set results $results "file:$path_match[2]"
        end
    end
    
    printf '%s\n' $results
end

function analyze_builtin_command
    set command_name $argv[1]
    
    # Check if it's a builtin
    if not type -t $command_name >/dev/null 2>&1; or test (type -t $command_name) != "builtin"
        return 1
    end
    
    set has_help "false"
    set is_keyword "false"
    set category "general"
    
    # Check if help documentation file exists instead of calling help command
    set possible_help_paths \
        "/usr/share/doc/fish/cmds/$command_name.html" \
        "/usr/local/share/doc/fish/cmds/$command_name.html"
    
    for help_file in $possible_help_paths
        if test -r "$help_file"
            set has_help "true"
            break
        end
    end
    
    # Categorize common builtins
    switch $command_name
        case "set" "test" "string" "math" "count" "contains"
            set category "core"
        case "cd" "pwd" "pushd" "popd" "dirs"
            set category "navigation"
        case "echo" "printf" "read"
            set category "io"
        case "if" "while" "for" "switch" "function" "begin" "end"
            set category "control"
            set is_keyword "true"
        case "source" "eval" "exec"
            set category "execution"
        case "jobs" "bg" "fg" "disown"
            set category "job-control"
        case "complete" "bind" "abbr"
            set category "shell-config"
        case "history" "commandline"
            set category "interactive"
    end
    
    echo $has_help
    echo $is_keyword
    echo $category
end

function analyze_external_command
    set command_path $argv[1]
    
    if not test -f "$command_path"
        return 1
    end
    
    set file_type ""
    set is_script "false"
    set interpreter ""
    set permissions ""
    
    # Get file type
    set file_info (file -b "$command_path" 2>/dev/null)
    if test -n "$file_info"
        set file_type "$file_info"
    end
    
    # Check if it's a script
    if test -r "$command_path"
        set first_line (head -n1 "$command_path" 2>/dev/null)
        if string match -q "#!*" $first_line
            set is_script "true"
            set interpreter (string sub -s 3 $first_line | string split " " | head -n1)
        end
    end
    
    # Get permissions
    set permissions (ls -l "$command_path" 2>/dev/null | cut -d' ' -f1)
    
    echo $file_type
    echo $is_script
    echo $interpreter
    echo $permissions
end

function check_command_conflicts
    set command_name $argv[1]
    
    set conflicts ""
    set unique_types ""
    
    # Get all types for this command
    set all_types (type -a $command_name 2>/dev/null)
    
    # Count unique types, not duplicate file locations
    for line in $all_types
        if string match -q "*builtin*" $line
            if not contains "builtin" $unique_types
                set unique_types $unique_types "builtin"
            end
        else if string match -q "*function*" $line
            if not contains "function" $unique_types
                set unique_types $unique_types "function"
            end
        else if string match -qr ".*is (.+)" $line
            if not contains "file" $unique_types
                set unique_types $unique_types "file"
            end
        end
    end
    
    # Only report conflicts if there are actually different types
    if test (count $unique_types) -gt 1
        set conflicts (string join " " $unique_types)
    end
    
    # Check for abbreviation with same name
    if abbr -q $command_name
        set conflicts "$conflicts abbreviation"
    end
    
    # Check for variable with same name
    if set -q $command_name
        set conflicts "$conflicts variable"
    end
    
    echo (string trim $conflicts)
end

function extract_fish_builtin_help
    set command_name $argv[1]
    
    # Try multiple possible locations for Fish documentation
    set possible_paths \
        "/usr/share/doc/fish/cmds/$command_name.html" \
        "/usr/local/share/doc/fish/cmds/$command_name.html"
    
    for html_file in $possible_paths
        if test -r "$html_file"
            # Extract text content from HTML using comprehensive processing
            set content (cat "$html_file" | \
                sed 's/<\/p>/\n/g; s/<\/li>/\n/g; s/<\/dt>/:/g; s/<\/dd>/\n/g' | \
                sed 's/<[^>]*>//g' | \
                sed 's/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g; s/&quot;/"/g; s/&#8212;/-/g' | \
                grep -A 15 -E "($command_name \[|$command_name - |Synopsis)" | \
                head -n 12 | \
                sed '/^[[:space:]]*$/d' | \
                sed 's/^[[:space:]]*//' | \
                grep -v '^¶$')
            
            if test -n "$content"
                echo "html-available"
                printf '%s\n' $content
                return
            end
        end
    end
    
    echo "no-help"
end

function get_command_documentation
    set command_name $argv[1]
    set command_type $argv[2]
    
    set doc_info ""
    
    if test "$command_type" = "builtin"
        # Try to extract from Fish HTML documentation
        set fish_help (extract_fish_builtin_help $command_name)
        set help_type $fish_help[1]
        
        if test "$help_type" = "html-available"
            set doc_info "html-help-available"
        else
            set doc_info "no-help"
        end
    else if test "$command_type" = "file"
        # Check for man page
        if man -w $command_name >/dev/null 2>&1
            set doc_info "man-page-available"
        else if test -x (which $command_name 2>/dev/null)
            # Try --help flag
            set help_test (eval $command_name --help 2>/dev/null | head -n5)
            if test -n "$help_test"
                set doc_info "help-flag-available"
            else
                set doc_info "no-documentation"
            end
        end
    end
    
    echo $doc_info
end

function format_command_report
    set command_name $argv[1]
    
    # Colors for output
    set RED '\033[0;31m'
    set GREEN '\033[0;32m'
    set YELLOW '\033[0;33m'
    set BLUE '\033[0;34m'
    set MAGENTA '\033[0;35m'
    set CYAN '\033[0;36m'
    set WHITE '\033[1;37m'
    set NC '\033[0m' # No Color
    
    # Detect command type
    set type_results (detect_command_type $command_name)
    if test "$type_results[1]" = "not-found"
        echo -e "$RED""'$command_name' not found$NC"
        return 1
    end
    
    # Parse results (format: "type:path")
    set command_types
    set command_paths
    
    for result in $type_results
        set parts (string split ":" $result)
        set command_types $command_types $parts[1]
        set command_paths $command_paths $parts[2]
    end
    
    # Get primary type (first one found)
    set primary_type $command_types[1]
    set primary_path $command_paths[1]
    
    # Check for conflicts
    set conflicts (check_command_conflicts $command_name)
    
    # Generate report
    echo -e "$CYAN""Shell classification for '$WHITE$command_name$CYAN': $primary_type$NC"
    
    # Show conflicts if any
    if test -n "$conflicts" -a (count (string split " " $conflicts)) -gt 1
        set conflict_list (string split " " $conflicts | string join ", ")
        echo -e "$YELLOW""⚠ Warning: '$command_name' also exists as $conflict_list$NC"
    end
    
    echo
    
    # Analyze based on primary type
    if test "$primary_type" = "builtin"
        set builtin_info (analyze_builtin_command $command_name)
        set has_help $builtin_info[1]
        set is_keyword $builtin_info[2] 
        set category $builtin_info[3]
        
        echo -e "$MAGENTA""Type: $WHITE""Fish builtin command$NC"
        echo -e "$CYAN""Category: $WHITE$category$NC"
        
        if test "$is_keyword" = "true"
            echo -e "$YELLOW""ℹ This is a language keyword$NC"
        end
        
        if test "$has_help" = "true"
            echo -e "$GREEN""✓ Help available$NC"
            
            echo
            echo -e "$GREEN""Built-in help:$NC"
            
            # Try to extract from Fish HTML documentation first
            set fish_help (extract_fish_builtin_help $command_name)
            set help_type $fish_help[1]
            
            if test "$help_type" = "html-available"
                set help_content $fish_help[2..]
                for line in $help_content
                    echo -e "$WHITE""  $line$NC"
                end
            else
                # Fallback to trying help command (might open browser)
                echo -e "$YELLOW""  Documentation available via 'help $command_name'$NC"
            end
        else
            echo -e "$RED""✗ No help available$NC"
        end
        
    else if test "$primary_type" = "file"
        echo -e "$MAGENTA""Type: $WHITE""External command$NC"
        echo -e "$CYAN""Path: $WHITE$primary_path$NC"
        
        if test -f "$primary_path"
            set file_info (analyze_external_command $primary_path)
            set file_type $file_info[1]
            set is_script $file_info[2]
            set interpreter $file_info[3]
            set permissions $file_info[4]
            
            echo -e "$CYAN""File type: $WHITE$file_type$NC"
            echo -e "$CYAN""Permissions: $WHITE$permissions$NC"
            
            if test "$is_script" = "true"
                echo -e "$GREEN""✓ Script file$NC"
                echo -e "$CYAN""Interpreter: $WHITE$interpreter$NC"
            end
            
            # Show file size and modification time
            set file_stats (ls -lh "$primary_path" 2>/dev/null)
            if test -n "$file_stats"
                set size (echo $file_stats | awk '{print $5}')
                set mod_time (echo $file_stats | awk '{print $6, $7, $8}')
                echo -e "$CYAN""Size: $WHITE$size$NC"
                echo -e "$CYAN""Modified: $WHITE$mod_time$NC"
            end
        end
        
        # Check for documentation
        set doc_info (get_command_documentation $command_name $primary_type)
        switch $doc_info
            case "html-help-available"
                echo -e "$GREEN""✓ Fish documentation available$NC"
            case "man-page-available"
                echo -e "$GREEN""✓ Manual page available (try 'man $command_name')$NC"
                
                # Show whatis description if available
                set whatis_desc (whatis $command_name 2>/dev/null | head -n1)
                if test -n "$whatis_desc"
                    # Extract just the description part after the command name
                    set clean_desc (echo "$whatis_desc" | sed "s/^[^-]*- *//" | sed 's/^[[:space:]]*//')
                    if test -n "$clean_desc"
                        echo -e "$CYAN""Description: $WHITE$clean_desc$NC"
                    end
                end
            case "help-flag-available"
                echo -e "$GREEN""✓ Help flag available (try '$command_name --help')$NC"
            case "*"
                echo -e "$YELLOW""ℹ No obvious documentation found$NC"
        end
        
    else if test "$primary_type" = "function"
        echo -e "$MAGENTA""Type: $WHITE""Fish function$NC"
        echo -e "$YELLOW""ℹ Use the function reporter for detailed analysis$NC"
    end
    
    # Show all alternative locations if multiple exist
    if test (count $command_types) -gt 1
        echo
        echo -e "$CYAN""Alternative locations:$NC"
        set i 2
        while test $i -le (count $command_types)
            set alt_type $command_types[$i]
            set alt_path $command_paths[$i]
            echo -e "$WHITE""  $alt_type: $alt_path$NC"
            set i (math $i + 1)
        end
    end
end

function demonstrate_command_reporter
    echo "Fish Command Reporter Demo"
    echo "=========================="
    echo
    
    # Test various command types
    set test_commands echo ls git type help nonexistent
    
    for command_name in $test_commands
        echo "Testing: $command_name"
        format_command_report $command_name
        echo
    end
    
    echo "Demo completed."
end

# Main function - can be called with command name or run demo
# Only run if not being sourced by investigate.fish
if not set -q SOURCING_FOR_INVESTIGATE
    if test (count $argv) -eq 0
        demonstrate_command_reporter
    else if test "$argv[1]" = "--demo"
        demonstrate_command_reporter
    else
        format_command_report $argv[1]
    end
end