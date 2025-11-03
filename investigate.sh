#!/bin/bash
DEBUG_LEVEL=${DEBUG_LEVEL:-0}

# Box drawing characters
declare -A BOX_CHARS=(
    ["TOP_LEFT"]='╭'
    ["TOP_RIGHT"]='╮'
    ["BOTTOM_LEFT"]='╰'
    ["BOTTOM_RIGHT"]='╯'
    ["HORIZONTAL"]='─'
    ["VERTICAL"]='│'
    ["TEE_LEFT"]='├'
    ["TEE_RIGHT"]='┤'
)

# Debug logging functions removed for performance

# Calculate visible length of a string (excluding ANSI escape sequences)
calculate_visible_length() {
    local str="$1"
    local visible_str

    # Handle both actual escape sequences and literal \033 strings
    local temp_str="$str"
    # Replace literal \033 with actual escape character
    temp_str="${temp_str//\\033/$'\033'}"

    # Remove actual escape sequences
    visible_str=""
    local in_escape=false
    local i=0
    while [[ $i -lt ${#temp_str} ]]; do
        local char="${temp_str:$i:1}"
        if [[ "$char" == $'\033' ]]; then
            in_escape=true
        elif [[ $in_escape == true && "$char" =~ [mKJH] ]]; then
            in_escape=false
        elif [[ $in_escape == false ]]; then
            visible_str+="$char"
        fi
        ((i++))
    done
    echo ${#visible_str}
}

# Parse a line into a character stream with color states
# Each element: "char|color_state" where color_state is current active color
parse_to_character_stream() {
    local line="$1"
    local -n char_stream_ref=$2
    
    char_stream_ref=()
    local i=0
    local current_color=""
    
    while [[ $i -lt ${#line} ]]; do
        if [[ "${line:$i:4}" == "\033" ]]; then
            # Extract the complete color code
            local color_start=$i
            i=$((i + 4))  # Skip \033[
            
            # Find the end of the color sequence
            while [[ $i -lt ${#line} && ! "${line:$i:1}" =~ [mKJH] ]]; do
                ((i++))
            done
            
            if [[ $i -lt ${#line} ]]; then
                ((i++))  # Include the terminating character
                local color_code="${line:$color_start:$((i-color_start))}"
                current_color="$color_code"
            fi
        else
            # Add character with current color state
            char_stream_ref+=("${line:$i:1}|$current_color")
            ((i++))
        fi
    done
}

# Legacy function for backward compatibility
parse_line_tokens() {
    local line="$1"
    local -n tokens_ref=$2
    
    tokens_ref=()
    local i=0
    local current_text=""
    
    while [[ $i -lt ${#line} ]]; do
        if [[ "${line:$i:4}" == "\033" ]]; then
            # Save any accumulated text
            if [[ -n "$current_text" ]]; then
                tokens_ref+=("text:$current_text")
                current_text=""
            fi
            
            # Extract the complete color code
            local color_start=$i
            i=$((i + 4))  # Skip \033[
            
            # Find the end of the color sequence
            while [[ $i -lt ${#line} && ! "${line:$i:1}" =~ [mKJH] ]]; do
                ((i++))
            done
            
            if [[ $i -lt ${#line} ]]; then
                ((i++))  # Include the terminating character
                local color_code="${line:$color_start:$((i-color_start))}"
                tokens_ref+=("color:$color_code")
            fi
        else
            current_text+="${line:$i:1}"
            ((i++))
        fi
    done
    
    # Save any remaining text
    if [[ -n "$current_text" ]]; then
        tokens_ref+=("text:$current_text")
    fi
}

# Get plain text from character stream
get_plain_text_from_char_stream() {
    local -n char_stream_ref=$1
    local plain_text=""
    
    for char_color in "${char_stream_ref[@]}"; do
        local char="${char_color%%|*}"
        plain_text+="$char"
    done
    
    echo "$plain_text"
}

# Legacy function for backward compatibility
get_plain_text_from_tokens() {
    local -n tokens_ref=$1
    local plain_text=""
    
    for token in "${tokens_ref[@]}"; do
        if [[ "$token" =~ ^text: ]]; then
            plain_text+="${token#text:}"
        fi
    done
    
    echo "$plain_text"
}

# Wrap character stream at word boundaries
wrap_character_stream() {
    local -n char_stream_ref=$1
    local max_width="$2"
    local -n result_streams_ref=$3
    
    result_streams_ref=()
    
    # Convert character stream to words with color info
    local -a words_with_colors=()
    local current_word_chars=()
    
    for char_color in "${char_stream_ref[@]}"; do
        local char="${char_color%%|*}"
        
        if [[ "$char" == " " ]]; then
            # End of word
            if [[ ${#current_word_chars[@]} -gt 0 ]]; then
                # Store word as array of char|color elements
                words_with_colors+=("$(printf '%s\n' "${current_word_chars[@]}" | tr '\n' '\001')")
                current_word_chars=()
            fi
        else
            current_word_chars+=("$char_color")
        fi
    done
    
    # Add final word
    if [[ ${#current_word_chars[@]} -gt 0 ]]; then
        words_with_colors+=("$(printf '%s\n' "${current_word_chars[@]}" | tr '\n' '\001')")
    fi
    
    # Wrap words into lines
    local current_line_chars=()
    local current_line_length=0
    
    for word_data in "${words_with_colors[@]}"; do
        # Convert back to array
        local -a word_chars=()
        IFS=$'\001' read -ra word_chars <<< "$word_data"
        
        local word_length=${#word_chars[@]}
        local new_length
        
        if [[ ${#current_line_chars[@]} -gt 0 ]]; then
            new_length=$((current_line_length + 1 + word_length))  # +1 for space
        else
            new_length=$word_length
        fi
        
        if [[ $new_length -le $max_width ]]; then
            # Add to current line
            if [[ ${#current_line_chars[@]} -gt 0 ]]; then
                current_line_chars+=("||")  # Space placeholder
                current_line_length=$((current_line_length + 1))
            fi
            current_line_chars+=("${word_chars[@]}")
            current_line_length=$((current_line_length + word_length))
        else
            # Complete current line
            if [[ ${#current_line_chars[@]} -gt 0 ]]; then
                result_streams_ref+=("$(printf '%s\n' "${current_line_chars[@]}" | tr '\n' '\001')")
            fi
            
            # Start new line
            current_line_chars=("${word_chars[@]}")
            current_line_length=$word_length
        fi
    done
    
    # Add final line
    if [[ ${#current_line_chars[@]} -gt 0 ]]; then
        result_streams_ref+=("$(printf '%s\n' "${current_line_chars[@]}" | tr '\n' '\001')")
    fi
}

# Render character stream to colored string
render_character_stream() {
    local -n char_stream_ref=$1
    local result=""
    local current_color=""
    
    # Convert stream data back to array if needed
    local -a chars=()
    if [[ ${#char_stream_ref[@]} -eq 1 ]]; then
        # Single string with \001 separators
        IFS=$'\001' read -ra chars <<< "${char_stream_ref[0]}"
    else
        chars=("${char_stream_ref[@]}")
    fi
    
    for char_color in "${chars[@]}"; do
        if [[ "$char_color" == "||" ]]; then
            # Space placeholder
            result+=" "
            continue
        fi
        
        local char="${char_color%%|*}"
        local color="${char_color#*|}"
        
        # Insert color code if state changed
        if [[ "$color" != "$current_color" ]]; then
            if [[ -n "$color" ]]; then
                result+="$color"
            fi
            current_color="$color"
        fi
        
        result+="$char"
    done
    
    echo "$result"
}

# Legacy function for backward compatibility
apply_colors_to_wrapped_lines() {
    local -n tokens_ref=$1
    local -n wrapped_lines_ref=$2
    local -n result_ref=$3
    
    result_ref=()
    
    # Build a position map of where colors should go
    local -A color_map=()
    local text_pos=0
    
    for token in "${tokens_ref[@]}"; do
        if [[ "$token" =~ ^text: ]]; then
            local text_content="${token#text:}"
            text_pos=$((text_pos + ${#text_content}))
        elif [[ "$token" =~ ^color: ]]; then
            local color_content="${token#color:}"
            color_map[$text_pos]="$color_content"
        fi
    done
    
    # Function to determine what color is active at a given position
    get_active_color_at_position() {
        local pos=$1
        local active_color=""
        
        # Go through all color positions up to this point to find the last active color
        for color_pos in $(printf '%s\n' "${!color_map[@]}" | sort -n); do
            if [[ $color_pos -le $pos ]]; then
                local color_code="${color_map[$color_pos]}"
                if [[ "$color_code" == "\033[0m" ]]; then
                    active_color=""  # Reset clears color
                else
                    active_color="$color_code"  # New color becomes active
                fi
            else
                break  # Don't process colors beyond our position
            fi
        done
        
        echo "$active_color"
    }
    
    # Process each wrapped line
    local line_start=0
    
    for plain_line in "${wrapped_lines_ref[@]}"; do
        local line_end=$((line_start + ${#plain_line}))
        local colored_line="$plain_line"
        
        # Get the active color at the start of this line
        local line_start_color
        line_start_color=$(get_active_color_at_position $line_start)
        
        # If there's an active color, prepend it to the line
        if [[ -n "$line_start_color" ]]; then
            colored_line="${line_start_color}${colored_line}"
        fi
        
        # Find colors that should be inserted within this line
        local -a insertions=()
        for pos in $(printf '%s\n' "${!color_map[@]}" | sort -n); do
            if [[ $pos -gt $line_start && $pos -lt $line_end ]]; then
                local relative_pos=$((pos - line_start))
                # Account for any color code we added at the beginning
                if [[ -n "$line_start_color" ]]; then
                    relative_pos=$((relative_pos + ${#line_start_color}))
                fi
                insertions+=("$relative_pos:${color_map[$pos]}")
            fi
        done
        
        # Apply insertions in reverse order to maintain positions
        local -a sorted_insertions=($(printf '%s\n' "${insertions[@]}" | sort -rn))
        for insertion in "${sorted_insertions[@]}"; do
            local insert_pos="${insertion%%:*}"
            local color_code="${insertion#*:}"
            colored_line="${colored_line:0:$insert_pos}${color_code}${colored_line:$insert_pos}"
        done
        
        result_ref+=("$colored_line")
        line_start=$((line_end + 1))  # +1 for the space that was removed during wrapping
    done
}

# New word wrap function using character stream approach
word_wrap_line() {
    local line="$1"
    local max_width="$2"
    local -n result_lines=$3
    
    
    # Parse into character stream
    local -a char_stream=()
    parse_to_character_stream "$line" char_stream
    
    # Get plain text for length calculation
    local plain_text
    plain_text=$(get_plain_text_from_char_stream char_stream)
    local plain_length=${#plain_text}
    
    if [[ $plain_length -le $max_width ]]; then
        result_lines+=("$line")  # Use original line with colors preserved
        return
    fi
    
    
    # Wrap character stream at word boundaries
    local -a wrapped_streams=()
    wrap_character_stream char_stream "$max_width" wrapped_streams
    
    # Render each wrapped stream to final colored strings
    result_lines=()
    for stream_data in "${wrapped_streams[@]}"; do
        local -a stream_array=("$stream_data")
        local colored_line
        colored_line=$(render_character_stream stream_array)
        result_lines+=("$colored_line")
    done
    
}

# Process content array to handle word wrapping
process_content_for_width() {
    local -n input_content=$1
    local -n output_content=$2
    local terminal_width="$3"
    
    
    local max_content_width=$((terminal_width - 4))
    [[ $max_content_width -lt 20 ]] && max_content_width=20
    
    
    output_content=()
    
    for line in "${input_content[@]}"; do
        if [[ "$line" == "---EMPTY---" || "$line" == "---SEPARATOR---" ]]; then
            output_content+=("$line")
        else
            local wrapped_lines=()
            word_wrap_line "$line" "$max_content_width" wrapped_lines
            output_content+=("${wrapped_lines[@]}")
        fi
    done
    
}

# Build a content line with proper padding
build_content_line() {
    local content="$1"
    local box_width="$2"
    local padding_char="${3:- }"
    
    local content_length
    content_length=$(calculate_visible_length "$content")
    
    local available_width=$((box_width - 4))
    local padding_needed=$((available_width - content_length))
    
    if [[ $padding_needed -lt 0 ]]; then
        echo "[ERROR] Content too long for box width: $content_length > $available_width" >&2
        return 1
    fi
    
    local padding=""
    for ((i=0; i<padding_needed; i++)); do
        padding+="$padding_char"
    done
    
    # Check if content has color codes - if so, don't add our own reset codes that interfere
    if [[ "$content" =~ \\033\[ ]]; then
        # Content has colors - ensure reset happens before closing border
        echo -e "${CYAN}${BOX_CHARS[VERTICAL]}${NC} ${content}${padding}${NC} ${CYAN}${BOX_CHARS[VERTICAL]}${NC}"
    else
        # Content has no colors - safe to use our normal coloring
        echo -e "${CYAN}${BOX_CHARS[VERTICAL]}${NC} ${content}${padding} ${CYAN}${BOX_CHARS[VERTICAL]}${NC}"
    fi
}

# Build a horizontal line (top, bottom, or separator)
build_horizontal_line() {
    local line_type="$1"
    local box_width="$2"
    
    local left_char right_char
    case "$line_type" in
        "top")
            left_char="${BOX_CHARS[TOP_LEFT]}"
            right_char="${BOX_CHARS[TOP_RIGHT]}"
            ;;
        "bottom")
            left_char="${BOX_CHARS[BOTTOM_LEFT]}"
            right_char="${BOX_CHARS[BOTTOM_RIGHT]}"
            ;;
        "separator")
            left_char="${BOX_CHARS[TEE_LEFT]}"
            right_char="${BOX_CHARS[TEE_RIGHT]}"
            ;;
        *)
            echo "[ERROR] Unknown line type: $line_type" >&2
            return 1
            ;;
    esac
    
    local horizontal_chars=""
    for ((i=0; i<box_width-2; i++)); do
        horizontal_chars+="${BOX_CHARS[HORIZONTAL]}"
    done
    
    echo -e "${CYAN}${left_char}${horizontal_chars}${right_char}${NC}"
}

# Build an empty line (just borders)
build_empty_line() {
    local box_width="$1"
    
    local spaces=""
    for ((i=0; i<box_width-2; i++)); do
        spaces+=" "
    done
    
    echo -e "${CYAN}${BOX_CHARS[VERTICAL]}${spaces}${BOX_CHARS[VERTICAL]}${NC}"
}

# Calculate the required box width for given content
calculate_box_width() {
    local -n content_array=$1
    local min_width="${2:-60}"
    local max_width="${3:-}"
    
    
    local max_content_length=0
    
    for line in "${content_array[@]}"; do
        local line_length
        line_length=$(calculate_visible_length "$line")
        
        if [[ $line_length -gt $max_content_length ]]; then
            max_content_length=$line_length
        fi
    done
    
    local required_width=$((max_content_length + 4))
    local final_width=$((required_width > min_width ? required_width : min_width))
    
    if [[ -n "$max_width" && $final_width -gt $max_width ]]; then
        final_width=$max_width
    fi
    
    
    echo $final_width
}

# Main function to render a framed box
render_box() {
    local title="$1"
    local -n lines=$2
    local min_width="${3:-60}"
    local show_separator="${4:-true}"
    local terminal_width="${5:-}"
    
    
    # Get terminal width if not provided
    if [[ -z "$terminal_width" ]]; then
        terminal_width=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
    fi
    
    
    # Process content for responsive width
    local processed_content=()
    process_content_for_width lines processed_content "$terminal_width"
    
    # Prepare all content for width calculation
    local all_content=()
    [[ -n "$title" ]] && all_content+=("$title")
    all_content+=("${processed_content[@]}")
    
    # Calculate box width with terminal width as maximum
    local box_width
    box_width=$(calculate_box_width all_content "$min_width" "$terminal_width")
    
    
    # Render the box
    build_horizontal_line "top" "$box_width"
    
    if [[ -n "$title" ]]; then
        build_content_line "$title" "$box_width"
        [[ "$show_separator" == "true" ]] && build_horizontal_line "separator" "$box_width"
    fi
    
    for line in "${processed_content[@]}"; do
        case "$line" in
            "---EMPTY---")
                build_empty_line "$box_width"
                ;;
            "---SEPARATOR---")
                build_horizontal_line "separator" "$box_width"
                ;;
            *)
                build_content_line "$line" "$box_width"
                ;;
        esac
    done
    
    build_horizontal_line "bottom" "$box_width"
    
}

i() {
    : i stands for "investigate"
    local file="" debug=0 found=0 use_color=1
    local preview_lines=15 indent="" depth=0 no_truncate=0
    local investigation_chain=()
    local shown_alias_target_inode=""  # Track inode of target shown during alias investigation
    local shown_alias_target_path=""   # Track path of target shown during alias investigation
    local shown_file_path=""           # Track path of file shown in main section
    [[ -t 1 ]] || use_color=0
    [[ $use_color -eq 1 ]] && {
        BLACK='\033[0;30m'; RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
        BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m';
        WHITE='\033[1;37m';
        BRIGHT_BLACK='\033[0;90m'; BRIGHT_RED='\033[0;91m'; BRIGHT_GREEN='\033[0;92m'; BRIGHT_YELLOW='\033[0;93m'
        BRIGHT_BLUE='\033[0;94m'; BRIGHT_MAGENTA='\033[0;95m'; BRIGHT_CYAN='\033[0;96m';
        BRIGHT_WHITE='\033[1;97m';
        ORANGE='\033[38;5;208m'; NC='\033[0m'
    } || {
        RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''; 
        WHITE=''; NC=''
    }
    
    # Debug output removed for performance

    # Helper function to track alias target for deduplication
    track_alias_target() {
        local target_path="$1"
        local resolved
        resolved=$(readlink -f "$target_path" 2>/dev/null || echo "$target_path")
        local inode
        inode=$(stat -Lc '%d:%i' "$resolved" 2>/dev/null)
        shown_alias_target_inode="$inode"
        shown_alias_target_path="$resolved"
    }

    # Helper function for recursive investigation with indentation
    investigate_target() {
        local target="$1"
        local current_depth="$2"
        local debug_flag=""
        [[ $debug -eq 1 ]] && debug_flag="--debug"
        
        # Strip ANSI color codes from target to prevent contamination
        local clean_target
        clean_target=$(echo "$target" | sed -e 's/\x1b\[[0-9;]*m//g' | sed -e 's/\\033\[[0-9;]*m//g')
        
        # Check for circular reference before investigation
        if [[ "${investigation_chain[*]}" =~ " $clean_target " || "${investigation_chain[0]}" == "$clean_target" ]]; then
            # Create tree prefix based on depth
            local tree_prefix=""
            for ((i=0; i<current_depth; i++)); do
                tree_prefix+="│  "
            done
            echo -e "${RED}${tree_prefix}↳ Circular reference detected: '${WHITE}$clean_target${RED}' is already being investigated in this chain${NC}"
            echo -e "${YELLOW}${tree_prefix}  Chain: ${investigation_chain[*]} → $clean_target${NC}"
            return
        fi

        # Create tree prefix based on depth
        local tree_prefix=""
        for ((i=0; i<current_depth; i++)); do
            tree_prefix+="│  "
        done

        # Print target with tree structure
        if [[ $current_depth -eq 0 ]]; then
            echo "↳ Investigating: $clean_target"
        else
            echo "${tree_prefix}└─ Investigating: $clean_target"
        fi
        local chain_str=""
        for item in "${investigation_chain[@]}"; do
            chain_str+="$item "
        done
        i "$clean_target" $debug_flag --depth=$((current_depth + 1)) --chain="$chain_str$file"
    }
    
    # Function to display variable information
    show_variable_info() {
        local var_name="$1"
        
        # Get variable declaration info
        local var_declaration
        var_declaration=$(declare -p "$var_name" 2>/dev/null)
        
        if [[ -z "$var_declaration" ]]; then
            echo -e "${RED}Variable '${WHITE}$var_name${RED}' is not set or declared.${NC}"
            return
        fi
        
        # Parse the declaration to get type and value
        local var_type="variable"
        if [[ "$var_declaration" =~ ^declare\ -([aAilnrtux]+) ]]; then
            local flags="${BASH_REMATCH[1]}"
            case "$flags" in
                *A*) var_type="associative array" ;;
                *a*) var_type="indexed array" ;;
                *i*) var_type="integer variable" ;;
                *l*) var_type="lowercase variable" ;;
                *n*) var_type="nameref variable" ;;
                *r*) var_type="readonly variable" ;;
                *t*) var_type="traced variable" ;;
                *u*) var_type="uppercase variable" ;;
                *x*) var_type="exported variable" ;;
                *) var_type="string variable" ;;
            esac
        fi
        
        # Use correct article (a/an) based on first letter
        local article="a"
        if [[ "$var_type" =~ ^[aeiouAEIOU] ]]; then
            article="an"
        fi
        echo -e "${CYAN}'${WHITE}$var_name${CYAN}' is $article $var_type${NC}"
        echo
        
        # Show the declaration (includes the value)
        echo -e "${MAGENTA}Declaration: ${NC}$var_declaration"

        # For arrays, show elements
        if [[ "$var_declaration" =~ ^declare\ -[aA] ]]; then
            # For arrays, show element count and first few elements
            if [[ "$var_declaration" =~ ^declare\ -a ]]; then
                # Indexed array
                local -n array_ref="$var_name"
                local array_size=${#array_ref[@]}
                echo -e "${YELLOW}Array size: ${NC}$array_size elements"
                
                if [[ $array_size -gt 0 ]]; then
                    echo -e "${YELLOW}First few elements:${NC}"
                    local count=0
                    for index in "${!array_ref[@]}"; do
                        if [[ $count -ge 5 ]]; then
                            echo "${indent}... (showing first 5 of $array_size elements)"
                            break
                        fi
                        echo "${indent}[$index] = '${array_ref[$index]}'"
                        ((count++))
                    done
                fi
            elif [[ "$var_declaration" =~ ^declare\ -A ]]; then
                # Associative array
                local -n assoc_ref="$var_name"
                local assoc_size=${#assoc_ref[@]}
                echo -e "${YELLOW}Associative array size: ${NC}$assoc_size elements"
                
                if [[ $assoc_size -gt 0 ]]; then
                    echo -e "${YELLOW}First few key-value pairs:${NC}"
                    local count=0
                    for key in "${!assoc_ref[@]}"; do
                        if [[ $count -ge 5 ]]; then
                            echo "${indent}... (showing first 5 of $assoc_size pairs)"
                            break
                        fi
                        echo "${indent}['$key'] = '${assoc_ref[$key]}'"
                        ((count++))
                    done
                fi
            fi
        fi
        echo
    }
    
    # Optimized show_usage function with static output for common widths
    show_usage() {
        local terminal_width=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
        local max_usage_width=100
        if [[ $terminal_width -gt $max_usage_width ]]; then
            terminal_width=$max_usage_width
        fi
        
        # Use static pre-formatted output for terminals ≥80 columns (most common case)
        if [[ $terminal_width -ge 80 ]]; then
            # Static output optimized for 80-column terminals
            echo -e "${CYAN}╭──────────────────────────────────────────────────────────────────────────────╮${NC}"
            echo -e "${CYAN}│${NC} ${WHITE}i${NC} ${BRIGHT_CYAN}(investigate): Inspect bash shell commands, functions, files, and more${NC}     ${CYAN}│${NC}"
            echo -e "${CYAN}├──────────────────────────────────────────────────────────────────────────────┤${NC}"
            echo -e "${CYAN}│${NC} ${YELLOW}Usage:${NC} ${WHITE}i${NC} ${GREEN}<name>${NC} ${BLUE}[options]${NC}                                                    ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}                                                                              ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC} ${YELLOW}Description:${NC}                                                                 ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC} Thoroughly investigates any given name, showing detailed information about   ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC} files, commands, aliases, functions, builtins, and keywords.                 ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}                                                                              ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC} ${YELLOW}Arguments:${NC}                                                                   ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}   ${GREEN}<name>${NC}      Required. The target to investigate                            ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}                                                                              ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC} ${YELLOW}Options:${NC}                                                                     ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}   ${BLUE}--debug${NC}            Shows verbose output when tracing function sources      ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}   ${BLUE}--functions, -f${NC}    Show only if target is a function                       ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}   ${BLUE}--aliases, -a${NC}      Show only if target is an alias                         ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}   ${BLUE}--variables, -v${NC}    Show only if target is a variable                       ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}   ${BLUE}--builtins, -b${NC}     Show only if target is a builtin or keyword             ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}   ${BLUE}--files${NC}            Show only if target is a file                           ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}   ${BLUE}--commands, -c${NC}     Show only if target is an executable command            ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}   ${BLUE}--no-truncate, -n${NC}  Show full content without truncating file previews      ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}                                                                              ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC} ${YELLOW}Examples:${NC}                                                                    ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}   ${WHITE}i${NC} ${GREEN}grep${NC}                   ${MAGENTA}# Inspect the grep command${NC}                        ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}   ${WHITE}i${NC} ${GREEN}my_function${NC}            ${MAGENTA}# Analyze a custom shell function${NC}                 ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}   ${WHITE}i${NC} ${GREEN}script.sh${NC} ${BLUE}--debug${NC}      ${MAGENTA}# Debug function source tracing${NC}                   ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}   ${WHITE}i${NC} ${GREEN}ls${NC} ${BLUE}--functions${NC}         ${MAGENTA}# Only show if 'ls' is a function${NC}                 ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}   ${WHITE}i${NC} ${GREEN}ll${NC} ${BLUE}-a${NC}                  ${MAGENTA}# Only show if 'll' is an alias${NC}                   ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}   ${WHITE}i${NC} ${GREEN}PATH${NC} ${BLUE}--variables${NC}       ${MAGENTA}# Only show if 'PATH' is a variable${NC}               ${CYAN}│${NC}"
            echo -e "${CYAN}│${NC}   ${WHITE}i${NC} ${GREEN}cd${NC} ${BLUE}-b${NC}                  ${MAGENTA}# Only show if 'cd' is a builtin${NC}                  ${CYAN}│${NC}"
            echo -e "${CYAN}╰──────────────────────────────────────────────────────────────────────────────╯${NC}"
        else
            # Fall back to dynamic calculation for narrow terminals
            local usage_content=(
                "${WHITE}i${NC} ${BRIGHT_CYAN}(investigate): Inspect bash shell commands, functions, files, and more${NC}"
                "---SEPARATOR---"
                "${YELLOW}Usage:${NC} ${WHITE}i${NC} ${GREEN}<name>${NC} ${BLUE}[options]${NC}"
                "---EMPTY---"
                "${YELLOW}Description:${NC}"
                "Thoroughly investigates any given name, showing detailed information about"
                "files, commands, aliases, functions, builtins, and keywords."
                "---EMPTY---"
                "${YELLOW}Arguments:${NC}"
                "  ${GREEN}<name>${NC}      Required. The target to investigate"
                "---EMPTY---"
                "${YELLOW}Options:${NC}"
                "  ${BLUE}--debug${NC}         Shows verbose output when tracing function sources"
                "  ${BLUE}--functions, -f${NC} Show only if target is a function"
                "  ${BLUE}--aliases, -a${NC}   Show only if target is an alias"
                "  ${BLUE}--variables, -v${NC} Show only if target is a variable"
                "  ${BLUE}--builtins, -b${NC}  Show only if target is a builtin or keyword"
                "  ${BLUE}--files${NC}         Show only if target is a file"
                "  ${BLUE}--commands, -c${NC}  Show only if target is an executable command"
                "  ${BLUE}--no-truncate, -n${NC} Show full content without truncating file previews"
                "---EMPTY---"
                "${YELLOW}Examples:${NC}"
                "  ${WHITE}i${NC} ${GREEN}grep${NC}                   ${MAGENTA}# Inspect the grep command${NC}"
                "  ${WHITE}i${NC} ${GREEN}my_function${NC}            ${MAGENTA}# Analyze a custom shell function${NC}"
                "  ${WHITE}i${NC} ${GREEN}script.sh${NC} ${BLUE}--debug${NC}      ${MAGENTA}# Debug function source tracing${NC}"
                "  ${WHITE}i${NC} ${GREEN}ls${NC} ${BLUE}--functions${NC}         ${MAGENTA}# Only show if 'ls' is a function${NC}"
                "  ${WHITE}i${NC} ${GREEN}ll${NC} ${BLUE}-a${NC}                  ${MAGENTA}# Only show if 'll' is an alias${NC}"
                "  ${WHITE}i${NC} ${GREEN}PATH${NC} ${BLUE}--variables${NC}       ${MAGENTA}# Only show if 'PATH' is a variable${NC}"
                "  ${WHITE}i${NC} ${GREEN}cd${NC} ${BLUE}-b${NC}                  ${MAGENTA}# Only show if 'cd' is a builtin${NC}"
            )
            render_box "" usage_content 80 false "$terminal_width"
        fi
    }

    declare -A bash_keywords=(
      [if]="Starts a conditional statement."
      [then]="Begins the command block for a true condition."
      [else]="Begins the command block if the condition is false."
      [elif]="Introduces a new condition if the previous one is false."
      [fi]="Ends an if statement."
      [case]="Starts a multi-branch conditional statement."
      [esac]="Ends a case statement."
      [for]="Begins a for loop."
      [select]="Creates a user selection menu loop."
      [while]="Begins a loop that runs while a condition is true."
      [until]="Begins a loop that runs until a condition becomes true."
      [do]="Begins the body of a loop or conditional block."
      [done]="Ends the body of a loop or conditional block."
      [in]="Specifies the list to iterate over in a loop."
      [function]="Defines a named function."
      [time]="Measures execution time of a command or pipeline."
      ["{"]="Begins a group of commands in a block."
      ["}"]="Ends a group of commands in a block."
      ["!"]="Negates the exit status of a command or pipeline."
      ["[["]="Begins a conditional test expression."
      ["]"]="Ends a conditional test expression."
      [coproc]="Starts a coprocess for asynchronous communication."
    )

    # Parse arguments - handle flags and options
    local args=()
    local filter_type=""
    local filter_types=()  # Support multiple filters
    
    # Expand combined short flags (e.g., -bvf -> -b -v -f)
    local expanded_args=()
    for arg in "$@"; do
        if [[ "$arg" =~ ^-[a-z]{2,}$ ]]; then
            # Combined short flags like -bvf
            local flag_chars="${arg#-}"
            for ((i=0; i<${#flag_chars}; i++)); do
                expanded_args+=("-${flag_chars:$i:1}")
            done
        else
            expanded_args+=("$arg")
        fi
    done
    
    # Process the expanded arguments
    for arg in "${expanded_args[@]}"; do
        if [[ "$arg" == "--debug" ]]; then
            debug=1
        elif [[ "$arg" =~ ^--depth=([0-9]+)$ ]]; then
            depth="${BASH_REMATCH[1]}"
            # Indentation disabled - keep flat output
            indent=""
        elif [[ "$arg" =~ ^--chain=(.*)$ ]]; then
            # Parse the investigation chain from parent call
            IFS=' ' read -ra investigation_chain <<< "${BASH_REMATCH[1]}"
        elif [[ "$arg" == "--functions" || "$arg" == "-f" ]]; then
            filter_types+=("function")
            filter_type="function"  # Keep for backward compatibility
        elif [[ "$arg" == "--aliases" || "$arg" == "-a" ]]; then
            filter_types+=("alias")
            filter_type="alias"  # Keep for backward compatibility
        elif [[ "$arg" == "--variables" || "$arg" == "-v" ]]; then
            filter_types+=("variable")
            filter_type="variable"  # Keep for backward compatibility
        elif [[ "$arg" == "--builtins" || "$arg" == "-b" ]]; then
            filter_types+=("builtin")
            filter_type="builtin"  # Keep for backward compatibility
        elif [[ "$arg" == "--files" ]]; then
            filter_type="file"
        elif [[ "$arg" == "--commands" || "$arg" == "-c" ]]; then
            filter_type="file"  # commands are executable files
        elif [[ "$arg" == "--no-truncate" || "$arg" == "-n" ]]; then
            no_truncate=1
        else
            args+=("$arg")
        fi
    done

    if [ ${#args[@]} -eq 0 ]; then
        show_usage
        return 1
    fi

    if [ ${#args[@]} -gt 1 ]; then
        echo -e "${RED}Error: Too many arguments (expected 1 name, got ${#args[@]}).${NC}"
        echo -e "${YELLOW}Tip: Use '${WHITE}i --help${YELLOW}' or just '${WHITE}i${YELLOW}' to see usage information.${NC}"
        return 1
    fi

    file="${args[0]}"
    
    # Handle help requests
    if [[ "$file" == "--help" || "$file" == "-h" ]]; then
        show_usage
        return 0
    fi

    declare -A inspected_inodes_map=()
    local inspected_paths=()

    show_file_preview() {
        local target="$1"
        [[ ! -r "$target" ]] && return
        # Don't preview directories
        [[ -d "$target" ]] && return
        
        if head -c 4 "$target" | grep -q $'^\x7fELF'; then
            echo "${indent}(Skipping preview: Binary ELF file)"
            return
        fi
        if LC_ALL=C grep -qP '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]' "$target"; then
            echo "${indent}(Skipping preview: File contains binary control characters)"
            return
        fi
        if grep -q $'\e\[' "$target"; then
            echo "${indent}(Skipping preview: Contains ANSI escape sequences)"
            return
        fi

        local line_count
        line_count=$(wc -l < "$target" 2>/dev/null)
        echo "${indent}The file has $line_count lines."
        
        # Determine how many lines to actually show
        local lines_to_show=$preview_lines
        if [[ $no_truncate -eq 1 ]]; then
            lines_to_show=$line_count
        else
            local truncated_lines=$((line_count - preview_lines))
            if [[ $line_count -gt $preview_lines && $truncated_lines -le 10 ]]; then
                # If we would only truncate 10 or fewer lines, show them all instead
                lines_to_show=$line_count
            fi
        fi
        
        if [ "$line_count" -le "$lines_to_show" ]; then
            echo "${indent}Displaying all content:"
        else
            echo "${indent}Displaying the first $lines_to_show lines:"
        fi
        
        # Get terminal width for line wrapping
        local terminal_width=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
        local max_line_width=$((terminal_width - ${#indent} - 4))  # Account for indent and some margin
        [[ $max_line_width -lt 40 ]] && max_line_width=40  # Minimum readable width
        
        if command -v bat &>/dev/null; then
            if [[ $use_color -eq 1 ]]; then
                bat --style=plain --color=always --paging=never --line-range=1:$lines_to_show --wrap=character --terminal-width="$max_line_width" "$target" | sed "s/^/${indent}/"
            else
                bat --style=plain --color=never --paging=never --line-range=1:$lines_to_show --wrap=character --terminal-width="$max_line_width" "$target" | sed "s/^/${indent}/"
            fi
        else
            # Wrap long lines manually for non-bat output
            head -n "$lines_to_show" "$target" | while IFS= read -r line; do
                if [[ ${#line} -le $max_line_width ]]; then
                    echo "${indent}${line}"
                else
                    # Wrap the line
                    local pos=0
                    while [[ $pos -lt ${#line} ]]; do
                        local chunk="${line:$pos:$max_line_width}"
                        echo "${indent}${chunk}"
                        pos=$((pos + max_line_width))
                    done
                fi
            done
        fi
        if [[ $no_truncate -eq 0 && "$line_count" -gt "$lines_to_show" ]]; then
            local actual_truncated=$((line_count - lines_to_show))
            echo "${indent}[...truncated $actual_truncated more lines...]"
        fi
        echo
    }

    inspect_file() {
        local path="$1"
        local is_path_executable="${2:-false}"  # Optional: true if from PATH, false for local files
        [ ! -e "$path" ] && return

        local stat_out dev inode
        stat_out=$(stat -Lc '%d:%i' "$path" 2>/dev/null) || return
        dev="${stat_out%%:*}"
        inode="${stat_out##*:}"
        local key="$dev:$inode"

        if [[ -n "${inspected_inodes_map[$key]}" ]]; then
            local existing_path="${inspected_inodes_map[$key]}"
            # Only show hardlink message if the paths are truly different
            # (not just relative vs absolute paths to the same file)
            local path_abs existing_abs
            path_abs=$(realpath "$path" 2>/dev/null)
            existing_abs=$(realpath "$existing_path" 2>/dev/null)
            
            if [[ "$path_abs" != "$existing_abs" ]]; then
                echo -e "${YELLOW}${indent}'${WHITE}$path${YELLOW}' is a hardlink to '${YELLOW}${existing_path}${YELLOW}'.${NC}"
            fi
            return
        fi

        inspected_paths+=("$path")
        inspected_inodes_map["$key"]="$path"

        echo -e "${GREEN}File '${YELLOW}${path}${GREEN}' found.${NC}"
        
        # Get file type and format it nicely
        local file_type
        file_type=$(file -b "$path")
        
        # Smart line wrapping: split at commas when lines get too long
        if [[ ${#file_type} -gt 80 ]]; then
            local formatted_type="Type: "
            local current_line="Type: "
            local remaining="$file_type"
            
            while [[ -n "$remaining" ]]; do
                # Find the next comma
                if [[ "$remaining" == *,* ]]; then
                    local next_part="${remaining%%,*},"
                    remaining="${remaining#*,}"
                    remaining="${remaining# }" # Remove leading space
                    
                    # Check if adding this part would make the line too long
                    if [[ ${#current_line} -gt 10 && $((${#current_line} + ${#next_part} + 1)) -gt 80 ]]; then
                        # Start a new line
                        formatted_type="${formatted_type}\n${indent}      ${next_part}"
                        current_line="${indent}      ${next_part}"
                    else
                        # Add to current line
                        if [[ "$current_line" == *,* ]]; then
                            formatted_type="${formatted_type} ${next_part}"
                            current_line="${current_line} ${next_part}"
                        else
                            formatted_type="${formatted_type}${next_part}"
                            current_line="${current_line}${next_part}"
                        fi
                    fi
                else
                    # Last part, no more commas
                    if [[ ${#current_line} -gt 10 && $((${#current_line} + ${#remaining} + 1)) -gt 80 ]]; then
                        formatted_type="${formatted_type}\n${indent}      ${remaining}"
                    else
                        if [[ "$current_line" == *,* ]]; then
                            formatted_type="${formatted_type} ${remaining}"
                        else
                            formatted_type="${formatted_type}${remaining}"
                        fi
                    fi
                    break
                fi
            done
            
            echo -e "${indent}${formatted_type}"
        else
            echo "${indent}Type: $file_type"
        fi
        if [ -d "$path" ]; then
            echo "${indent}Directory contents:"
            local dir_listing total_items max_items=20
            if [[ $use_color -eq 1 ]]; then
                dir_listing=$(ls -lh "$path" --color=auto)
            else
                dir_listing=$(ls -lh "$path" --color=never)
            fi
            total_items=$(echo "$dir_listing" | wc -l)
            echo "$dir_listing" | head -n "$max_items" | sed "s/^/${indent}/"
            if [ "$total_items" -gt "$max_items" ]; then
                echo "${indent}[...truncated $((total_items - max_items)) more items]"
            fi
        else
            if [[ $use_color -eq 1 ]]; then
                ls -lh "$path" --color=auto | sed "s/^/${indent}/"
            else
                ls -lh "$path" --color=never | sed "s/^/${indent}/"
            fi
        fi

        if [ -L "$path" ]; then
            # Follow the symlink and investigate the target
            local target_path
            target_path=$(readlink -f "$path" 2>/dev/null)
            if [[ -n "$target_path" && -e "$target_path" ]]; then
                echo -e "${CYAN}Following symlink to: ${YELLOW}$target_path${NC}"
                echo

                # Show target file information directly without recursion to avoid inode conflicts
                # (indentation disabled for flat output)

                echo -e "${GREEN}File '${YELLOW}${target_path}${GREEN}' found.${NC}"
                
                # Get file type and format it nicely
                local file_type
                file_type=$(file -b "$target_path")
                
                # Smart line wrapping: split at commas when lines get too long
                if [[ ${#file_type} -gt 80 ]]; then
                    local formatted_type="Type: "
                    local current_line="Type: "
                    local remaining="$file_type"
                    
                    while [[ -n "$remaining" ]]; do
                        # Find the next comma
                        if [[ "$remaining" == *,* ]]; then
                            local next_part="${remaining%%,*},"
                            remaining="${remaining#*,}"
                            remaining="${remaining# }" # Remove leading space
                            
                            # Check if adding this part would make the line too long
                            if [[ ${#current_line} -gt 10 && $((${#current_line} + ${#next_part} + 1)) -gt 80 ]]; then
                                # Start a new line
                                formatted_type="${formatted_type}\n${indent}      ${next_part}"
                                current_line="${indent}      ${next_part}"
                            else
                                # Add to current line
                                if [[ "$current_line" == *,* ]]; then
                                    formatted_type="${formatted_type} ${next_part}"
                                    current_line="${current_line} ${next_part}"
                                else
                                    formatted_type="${formatted_type}${next_part}"
                                    current_line="${current_line}${next_part}"
                                fi
                            fi
                        else
                            # Last part, no more commas
                            if [[ ${#current_line} -gt 10 && $((${#current_line} + ${#remaining} + 1)) -gt 80 ]]; then
                                formatted_type="${formatted_type}\n${indent}      ${remaining}"
                            else
                                if [[ "$current_line" == *,* ]]; then
                                    formatted_type="${formatted_type} ${remaining}"
                                else
                                    formatted_type="${formatted_type}${remaining}"
                                fi
                            fi
                            break
                        fi
                    done
                    
                    echo -e "${indent}${formatted_type}"
                else
                    echo "${indent}Type: $file_type"
                fi
                
                # Show file listing
                if [ -d "$target_path" ]; then
                    echo "${indent}Directory contents:"
                    local dir_listing total_items max_items=20
                    if [[ $use_color -eq 1 ]]; then
                        dir_listing=$(ls -lh "$target_path" --color=auto)
                    else
                        dir_listing=$(ls -lh "$target_path" --color=never)
                    fi
                    total_items=$(echo "$dir_listing" | wc -l)
                    echo "$dir_listing" | head -n "$max_items" | sed "s/^/${indent}/"
                    if [ "$total_items" -gt "$max_items" ]; then
                        echo "${indent}[...truncated $((total_items - max_items)) more items]"
                    fi
                else
                    if [[ $use_color -eq 1 ]]; then
                        ls -lh "$target_path" --color=auto | sed "s/^/${indent}/"
                    else
                        ls -lh "$target_path" --color=never | sed "s/^/${indent}/"
                    fi
                fi
                
                # Show file preview for the target
                show_file_preview "$target_path"
            else
                echo -e "${RED}${indent}Symlink target could not be resolved or does not exist.${NC}"
            fi
        else
            show_file_preview "$path"
        fi

        # Check for manual page and show description if available (only for PATH executables)
        if [[ "$is_path_executable" == "true" ]]; then
            local command_name
            command_name=$(basename "$path")
            if man -w "$command_name" &>/dev/null; then
                echo -e "${GREEN}${indent}✓ Manual page available (try '${BRIGHT_BLUE}man $command_name${GREEN}')${NC}"

                # Show whatis description if available
                local whatis_desc
                whatis_desc=$(whatis "$command_name" 2>/dev/null | head -n1)
                if [[ -n "$whatis_desc" ]]; then
                    # Extract just the description part after the command name and dash
                    local clean_desc
                    clean_desc=$(echo "$whatis_desc" | sed 's/^[^-]*- *//' | sed 's/^[[:space:]]*//')
                    if [[ -n "$clean_desc" ]]; then
                        echo -e "${CYAN}${indent}Description: ${WHITE}$clean_desc${NC}"
                    fi
                fi
            fi
        fi
    }

    # Helper function to display function definition
    show_function_definition() {
        local funcname="$1"
        local show_source_search="${2:-true}"
        
        local func_def total_lines
        func_def=$(declare -f "$funcname")
        total_lines=$(echo "$func_def" | wc -l)
        
        # Determine how many lines to actually show
        local lines_to_show=$preview_lines
        if [[ $no_truncate -eq 1 ]]; then
            lines_to_show=$total_lines
        else
            local truncated_lines=$((total_lines - preview_lines))
            if [[ $total_lines -gt $preview_lines && $truncated_lines -le 10 ]]; then
                # If we would only truncate 10 or fewer lines, show them all instead
                lines_to_show=$total_lines
            fi
        fi
        
        if [ "$total_lines" -le "$lines_to_show" ]; then
            echo -e "${CYAN}'${WHITE}$funcname${CYAN}' is a shell function:${NC}"
        else
            echo -e "${CYAN}'${WHITE}$funcname${CYAN}' is a shell function (showing first $lines_to_show lines):${NC}"
        fi
        
        # Get terminal width for line wrapping
        local terminal_width=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
        local max_line_width=$((terminal_width - ${#indent} - 4))  # Account for indent and some margin
        [[ $max_line_width -lt 40 ]] && max_line_width=40  # Minimum readable width
        
        # Use bat for syntax highlighting if available
        if command -v bat &>/dev/null; then
            if [[ $use_color -eq 1 ]]; then
                echo "$func_def" | head -n "$lines_to_show" | bat --style=plain --color=always --paging=never --language=bash --wrap=character --terminal-width="$max_line_width" | sed "s/^/${indent}/"
            else
                echo "$func_def" | head -n "$lines_to_show" | bat --style=plain --color=never --paging=never --language=bash --wrap=character --terminal-width="$max_line_width" | sed "s/^/${indent}/"
            fi
        else
            # Wrap long lines manually for non-bat output
            echo "$func_def" | head -n "$lines_to_show" | while IFS= read -r line; do
                if [[ ${#line} -le $max_line_width ]]; then
                    echo "${indent}${line}"
                else
                    # Wrap the line, trying to break at reasonable points
                    local pos=0
                    while [[ $pos -lt ${#line} ]]; do
                        local chunk="${line:$pos:$max_line_width}"
                        echo "${indent}${chunk}"
                        pos=$((pos + max_line_width))
                    done
                fi
            done
        fi
        
        if [[ $no_truncate -eq 0 && "$total_lines" -gt "$lines_to_show" ]]; then
            local actual_truncated=$((total_lines - lines_to_show))
            echo "${indent}[...truncated $actual_truncated more lines...]"
        fi
        echo

        # Only show source search if requested (avoid redundancy)
        if [[ "$show_source_search" == "true" ]]; then
            echo -e "${CYAN}Searching for function '${WHITE}$funcname${CYAN}' definition source file...${NC}"
            local src_file=""

            # Call find_function_source directly (timeout subprocess was broken)
            src_file=$(find_function_source "$funcname")
            
            if [[ -n "$src_file" ]]; then
                local file_and_line="$src_file"
                local found_file="${src_file%:*}"
                local found_line="${src_file##*:}"
                
                # Check if we have a sourcing trail from recursive search
                if [[ "$src_file" == *"|TRAIL|"* ]]; then
                    file_and_line="${src_file%|TRAIL|*}"
                    local trail="${src_file#*|TRAIL|}"
                    found_file="${file_and_line%:*}"
                    found_line="${file_and_line##*:}"
                fi
                
                echo -e "${GREEN}Function '${WHITE}$funcname${GREEN}' found in: ${YELLOW}$found_file${GREEN}, line $found_line${NC}"
                
                # Always check for backward sourcing trail - find what sourced this file
                local backward_trail=""
                local search_file="$found_file"
                
                # Search through common config files to find where this file was sourced
                local config_files=(
                    "$HOME/.bashrc"
                    "$HOME/.bash_profile" 
                    "$HOME/.bash_login"
                    "$HOME/.profile"
                    "/etc/bash.bashrc"
                    "/etc/profile"
                )
                
                for config_file in "${config_files[@]}"; do
                    if [[ -r "$config_file" ]]; then
                        # Look for lines that source our found file with enhanced patterns
                        local source_line=""
                        local basename_file=$(basename "$search_file")
                        local full_path_escaped=$(printf '%s\n' "$search_file" | sed 's/[[\.*^$()+?{|]/\\&/g')
                        
                        # Multiple patterns to catch different sourcing styles:
                        # 1. source filename or . filename
                        # 2. source ./path or . ./path  
                        # 3. source /full/path or . /full/path
                        # 4. builtin source filename
                        # 5. source with variables like source "$FILE"
                        source_line=$(grep -n -E "(^|[[:space:]])(\.|source|builtin[[:space:]]+source)[[:space:]]+[\"\']{0,1}([^[:space:]\"\']*/)?(${basename_file}|${full_path_escaped})[\"\']{0,1}([[:space:]]|$|#)" "$config_file" 2>/dev/null | head -1 | cut -d: -f1)
                        
                        if [[ -n "$source_line" ]]; then
                            backward_trail="${config_file}:${source_line}"
                            break
                        fi
                    fi
                done
                
                # Display the complete sourcing trail
                echo -e "${CYAN}Sourcing trail:${NC}"
                
                # Show backward trail if found
                if [[ -n "$backward_trail" ]]; then
                    echo -e "${CYAN}  ${MAGENTA}${backward_trail%:*}${CYAN}:${backward_trail##*:} ${CYAN}sources -> ${YELLOW}${found_file}${NC}"
                fi
                
                # Show forward trail if it exists (from recursive search)
                if [[ "$src_file" == *"|TRAIL|"* ]]; then
                    local trail="${src_file#*|TRAIL|}"
                    local trail_parts
                    IFS=' -> ' read -ra trail_parts <<< "$trail"
                    
                    for i in "${!trail_parts[@]}"; do
                        local trail_file="${trail_parts[$i]}"
                        if [[ $((i + 1)) -lt ${#trail_parts[@]} ]]; then
                            local next_file="${trail_parts[$((i + 1))]}"
                            # Find the line where next_file is sourced in trail_file
                            local source_line=""
                            if [[ -r "$trail_file" ]]; then
                                source_line=$(grep -n "source.*$(basename "$next_file")\|\..*$(basename "$next_file")" "$trail_file" 2>/dev/null | head -1 | cut -d: -f1)
                            fi
                            if [[ -n "$source_line" ]]; then
                                echo -e "${CYAN}  ${MAGENTA}${trail_file}${CYAN}:${source_line} ${CYAN}sources -> ${YELLOW}${next_file}${NC}"
                            else
                                echo -e "${CYAN}  ${MAGENTA}${trail_file} ${CYAN}sources -> ${YELLOW}${next_file}${NC}"
                            fi
                        fi
                    done
                fi
                
                # Always show where the function is defined
                echo -e "${CYAN}  ${YELLOW}${found_file}${CYAN}:${found_line} ${CYAN}defines -> ${WHITE}${funcname}()${NC}"
                echo
            else
                echo -e "${YELLOW}Function '${WHITE}$funcname${YELLOW}' definition not found in common source files.${NC}"
                echo
            fi
        fi
    }

    find_function_definition() {
        local funcname="$1"
        local file="$2"
        local maxdepth="$3"
        local trail_ref="$4"  # Optional reference to array for sourcing trail
        declare -A visited_files=()
        local start_time=$(date +%s)
        local search_call_count=0

        _search_file() {
            local f="$1"
            local depth="$2"
            local current_trail="$3"  # Current sourcing path
            
            # Increment call counter to prevent runaway recursion
            ((search_call_count++))
            if (( search_call_count > 100 )); then
                echo "TIMEOUT"
                return 124
            fi
            
            [[ ! -r "$f" || -d "$f" ]] && return 1
            local abs_path
            abs_path=$(realpath "$f" 2>/dev/null || readlink -f "$f") || return 1
            
            # Check if we've already visited this file
            [[ -n "${visited_files[$abs_path]}" ]] && return 1
            visited_files["$abs_path"]=1

            local current_time=$(date +%s)
            if (( current_time - start_time > 3 )); then
                echo "TIMEOUT" 
                return 124
            fi


            # Much simpler and more flexible function matching
            # Look for: funcname() anywhere in the line (with optional whitespace/function keyword)
            local line_num
            line_num=$(grep -En "\\b${funcname}\\s*\\(" "$abs_path" | head -n1 | cut -d: -f1)
            
            if [[ -n "$line_num" ]]; then
                local result="${abs_path}:${line_num}"
                # If we have a trail reference, add the sourcing trail
                if [[ -n "$trail_ref" && -n "$current_trail" ]]; then
                    result="${result}|TRAIL|${current_trail}"
                fi
                echo "$result"
                return 0
            fi

            if (( depth > 0 )); then
                local sourced_files=()
                
                # Debug: show what sourcing lines we're finding
                
                while IFS= read -r line; do
                    # Skip comments
                    [[ "$line" =~ ^[[:space:]]*# ]] && continue
                    
                    # Debug: show each line we're checking
                    
                    # Handle multiple sourcing patterns more explicitly
                    local raw=""
                    
                    # Enhanced patterns to catch more sourcing variations:
                    # Pattern 1: source filename (with optional quotes)
                    if [[ "$line" =~ ^[[:space:]]*source[[:space:]]+[\"\']{0,1}([^[:space:]\;\&\|#\"\']+)[\"\']{0,1} ]]; then
                        raw="${BASH_REMATCH[1]}"
                    
                    # Pattern 2: . filename (dot sourcing with optional quotes)
                    elif [[ "$line" =~ ^[[:space:]]*\.[[:space:]]+[\"\']{0,1}([^[:space:]\;\&\|#\"\']+)[\"\']{0,1} ]]; then
                        raw="${BASH_REMATCH[1]}"
                        
                    # Pattern 3: builtin source filename
                    elif [[ "$line" =~ ^[[:space:]]*builtin[[:space:]]+source[[:space:]]+[\"\']{0,1}([^[:space:]\;\&\|#\"\']+)[\"\']{0,1} ]]; then
                        raw="${BASH_REMATCH[1]}"
                    fi
                    
                    if [[ -n "$raw" ]]; then
                        # Clean up the path
                        raw="${raw%\"}"; raw="${raw#\"}"  # Remove quotes
                        raw="${raw%\'}"; raw="${raw#\'}"  # Remove quotes
                        
                        # Skip if contains variables, command substitution, etc.
                        if [[ "$raw" == *\$* || "$raw" == *\`* || "$raw" == *\<\(* ]]; then
                            continue
                        fi
                        
                        # Expand tilde
                        [[ "$raw" == ~* ]] && raw="${raw/#~/$HOME}"
                        
                        # Handle relative paths
                        [[ "$raw" != /* ]] && raw="$(dirname "$abs_path")/$raw"
                        
                        # Resolve the path
                        local norm
                        norm=$(realpath "$raw" 2>/dev/null || readlink -f "$raw" 2>/dev/null)
                        
                        if [[ -n "$norm" && -e "$norm" ]]; then
                            # Additional check to prevent circular sourcing before adding
                            if [[ -z "${visited_files[$norm]}" ]]; then
                                sourced_files+=("$norm")
                            fi
                        fi
                    fi
                done < "$abs_path"

                # Recursively search sourced files
                for sf in "${sourced_files[@]}"; do
                    if [[ -e "$sf" ]]; then
                        local result
                        # Build trail for this sourcing path
                        local new_trail="$current_trail"
                        if [[ -n "$new_trail" ]]; then
                            new_trail="${new_trail} -> ${abs_path}"
                        else
                            new_trail="$abs_path"
                        fi
                        result=$(_search_file "$sf" $((depth - 1)) "$new_trail")
                        if [[ "$result" == "TIMEOUT" ]]; then
                            echo "TIMEOUT"
                            return 124
                        elif [[ -n "$result" ]]; then
                            echo "$result"
                            return 0
                        fi
                    fi
                done
            fi
            return 1
        }

        _search_file "$file" "$maxdepth" ""
    }

    # Wrapper function to find function source
    find_function_source() {
        local funcname="$1"
        local src_file=""
        
        # Comprehensive list of files and directories that bash typically sources
        local candidate_paths=(
            # User-specific files (login shells)
            "$HOME/.bash_profile"
            "$HOME/.bash_login"
            "$HOME/.profile"
            
            # User-specific files (non-login interactive shells)
            "$HOME/.bashrc"
            
            # Current directory and subdirectories (but not if we're in home dir)
            # Add current directory search if not in home directory to avoid noise
            $(if [[ "$PWD" != "$HOME" ]]; then
                echo "."
            fi)

            # Common additional user files
            "$HOME/.bash_aliases"
            "$HOME/.bash_functions"
            "$HOME/.bash_exports"
            "$HOME/.bash_local"
            "$HOME/.local/share/bash-completion/bash_completion"
            
            # System-wide files
            "/etc/profile"
            "/etc/bash.bashrc"
            "/etc/bashrc"
            
            # Distribution-specific locations
            "/etc/profile.d/"
            "/usr/share/bash-completion/bash_completion"
            
            # macOS specific
            "/etc/bashrc_Apple_Terminal"
            "/usr/local/etc/bash_completion"
            
            # Additional common locations
            "$HOME/.config/bash/bashrc"
            "$HOME/.bash/bashrc"
            "$HOME/.dotfiles/bash/"
            "$HOME/.dotfiles/bashrc"
            
            # Oh My Bash / Bash-it framework files
            "$HOME/.oh-my-bash/oh-my-bash.sh"
            "$HOME/.bash_it/bash_it.sh"
            
            # Conda/Anaconda
            "$HOME/.conda/etc/profile.d/conda.sh"
            
            # Homebrew
            "/opt/homebrew/etc/bash_completion"
            "/usr/local/etc/bash_completion"
        )
        
        # Build list of actual files to search
        local candidate_files=()
        local file_count=0
        local max_files=200  # Safety limit to prevent searching too many files

        # Add individual files first
        for path in "${candidate_paths[@]}"; do
            # Stop if we've collected enough files
            [[ $file_count -ge $max_files ]] && break

            if [[ -f "$path" ]]; then
                candidate_files+=("$path")
                ((file_count++))
            elif [[ -d "$path" ]]; then
                # For directories, find files but limit results
                local remaining=$((max_files - file_count))
                [[ $remaining -le 0 ]] && break

                while IFS= read -r found_file && [[ $file_count -lt $max_files ]]; do
                    candidate_files+=("$found_file")
                    ((file_count++))
                done < <(find "$path" -maxdepth 3 -type f -readable 2>/dev/null | head -n "$remaining")
            fi
        done
        
        for f in "${candidate_files[@]}"; do
            [[ -f "$f" ]] || continue
            local result
            # Pass a dummy trail reference to enable trail tracking
            if [[ $debug -eq 1 ]]; then
                result=$(find_function_definition "$funcname" "$f" 3 "enable_trail")
            else
                result=$(find_function_definition "$funcname" "$f" 3 "enable_trail" 2>/dev/null)
            fi
            
            if [[ "$result" == "TIMEOUT" ]]; then
                echo "TIMEOUT"
                return
            elif [[ -n "$result" ]]; then
                echo "$result"
                return
            fi
        done
        
        # Return empty string if not found (not "TIMEOUT")
        echo ""
    }

    # Function to find alias definition source file  
    find_alias_source() {
        local aliasname="$1"
        local candidate_files=()
        
        # Use the same candidate paths as function search
        local candidate_paths=(
            # User-specific files (login shells)
            "$HOME/.bash_profile"
            "$HOME/.bash_login" 
            "$HOME/.profile"
            
            # User-specific files (non-login interactive shells)
            "$HOME/.bashrc"
            
            # Current directory and subdirectories (but not if we're in home dir)
            $(if [[ "$PWD" != "$HOME" ]]; then
                echo "."
            fi)
            
            # User config directory
            "$HOME/.config"
            
            # Common additional user files
            "$HOME/.bash_aliases"
            "$HOME/.bash_functions" 
            "$HOME/.bash_exports"
            "$HOME/.bash_local"
            
            # System-wide files
            "/etc/profile"
            "/etc/bash.bashrc"
            "/etc/bashrc"
            
            # Distribution-specific locations
            "/etc/profile.d/"
            
            # Additional common locations
            "$HOME/.config/bash/bashrc"
            "$HOME/.bash/bashrc"
            "$HOME/.dotfiles/bash/"
            "$HOME/.dotfiles/bashrc"
        )
        
        # Build candidate files list
        for path in "${candidate_paths[@]}"; do
            if [[ -f "$path" ]]; then
                candidate_files+=("$path")
            elif [[ -d "$path" ]]; then
                # For directories, find all readable files recursively (max depth 3)
                while IFS= read -r -d '' found_file; do
                    candidate_files+=("$found_file")
                done < <(find "$path" -maxdepth 3 -type f -readable -print0 2>/dev/null)
            fi
        done
        
        # Search for alias definition in candidate files
        for f in "${candidate_files[@]}"; do
            [[ -f "$f" ]] || continue
            local result
            # Search for alias definition pattern: "alias aliasname=" or "alias aliasname " 
            if [[ $debug -eq 1 ]]; then
                result=$(find_alias_definition "$aliasname" "$f" 3)
            else
                result=$(find_alias_definition "$aliasname" "$f" 3 2>/dev/null)
            fi
            
            if [[ "$result" == "TIMEOUT" ]]; then
                echo "TIMEOUT"
                return
            elif [[ -n "$result" ]]; then
                echo "$result"
                return
            fi
        done
        
        # Return empty string if not found
        echo ""
    }
    
    # Function to find alias definition in a specific file
    find_alias_definition() {
        local aliasname="$1"
        local filepath="$2"
        local maxdepth="$3"
        
        [[ ! -r "$filepath" ]] && return 1
        [[ -d "$filepath" ]] && return 1
        
        # Search for alias definition patterns
        local line_num
        line_num=$(grep -n "^[[:space:]]*alias[[:space:]]\+$aliasname[[:space:]]*=" "$filepath" | head -1 | cut -d: -f1)
        
        if [[ -n "$line_num" ]]; then
            echo "$filepath:$line_num"
            return 0
        fi
        
        return 1
    }

    # Check for name clashes by examining all types that exist for this name
    local all_types=()
    local primary_kind
    primary_kind=$(type -t "$file")
    
    # If type -t didn't find anything, check if it's a variable
    if [[ -z "$primary_kind" ]] && declare -p "$file" &>/dev/null; then
        primary_kind="variable"
    fi
    
    # Apply type filter if specified
    if [[ ${#filter_types[@]} -gt 0 ]]; then
        local matches_any_filter=false
        local rejection_messages=()
        
        for filter in "${filter_types[@]}"; do
            # Handle special cases for filter matching
            if [[ "$filter" == "builtin" && "$primary_kind" == "keyword" ]]; then
                # Keywords are often grouped with builtins
                matches_any_filter=true
                break
            elif [[ "$filter" == "file" && "$primary_kind" == "file" ]]; then
                # Direct match
                matches_any_filter=true
                break
            elif [[ "$filter" == "$primary_kind" ]]; then
                matches_any_filter=true
                break
            else
                rejection_messages+=("'${file}' is not a ${filter}.")
            fi
        done
        
        if [[ "$matches_any_filter" == "false" ]]; then
            # Show all rejection messages
            for msg in "${rejection_messages[@]}"; do
                echo -e "${YELLOW}$msg${NC}"
            done
            return 1
        fi
    elif [[ -n "$filter_type" ]]; then
        # Legacy single filter support
        if [[ "$filter_type" == "builtin" && "$primary_kind" == "keyword" ]]; then
            # Keywords are often grouped with builtins
            :  # Allow this match
        elif [[ "$filter_type" == "file" && "$primary_kind" == "file" ]]; then
            :  # Direct match
        elif [[ "$filter_type" != "$primary_kind" ]]; then
            echo -e "${YELLOW}'${WHITE}$file${YELLOW}' is not a $filter_type.${NC}"
            return 1
        fi
    fi
    
    # Debug: Show what we're checking
    
    # Check for each possible type using more reliable detection methods
    if alias "$file" &>/dev/null; then
        all_types+=("alias")
    fi
    
    # Check for variables (both set and unset but declared)
    if declare -p "$file" &>/dev/null; then
        all_types+=("variable")
    fi
    
    if declare -f "$file" &>/dev/null; then
        all_types+=("function")
    fi
    
    if [[ -n "$(type -t "$file" 2>/dev/null)" && "$(type -t "$file")" == "builtin" ]]; then
        all_types+=("builtin")
    fi
    
    if [[ -n "$(type -t "$file" 2>/dev/null)" && "$(type -t "$file")" == "keyword" ]]; then
        all_types+=("keyword")
    fi
    
    # Check for executable file in PATH (even if overshadowed by function/alias)
    if command -v "$file" &>/dev/null; then
        local exec_path
        exec_path=$(type -P "$file" 2>/dev/null)  # type -P finds the executable path even if overshadowed
        if [[ -n "$exec_path" && -f "$exec_path" ]]; then
            all_types+=("file")
        fi
    fi
    
    
    # Remove duplicates while preserving order
    local unique_types=()
    for type_item in "${all_types[@]}"; do
        local already_added=false
        for existing in "${unique_types[@]}"; do
            [[ "$existing" == "$type_item" ]] && { already_added=true; break; }
        done
        [[ "$already_added" == false ]] && unique_types+=("$type_item")
    done
    
    
    if [ -n "$primary_kind" ]; then
        found=1
        # Only show shell classification at top level to avoid duplication
        if [[ $depth -eq 0 ]]; then
            echo -e "${CYAN}Shell classification for '${WHITE}$file${CYAN}': ${ORANGE}$primary_kind${NC}"

            # For files, show which one will execute
            if [[ "$primary_kind" == "file" ]]; then
                local exec_path
                exec_path=$(command -v "$file" 2>/dev/null)
                if [[ -n "$exec_path" ]]; then
                    echo -e "${CYAN}Executes: ${YELLOW}$exec_path${NC}"
                    shown_file_path="$exec_path"
                fi
            fi
        fi
        
        # Show name clash warning if multiple types exist (excluding variables)
        if [[ ${#unique_types[@]} -gt 1 ]]; then
            local other_types=()
            local variable_exists=false
            
            for type_item in "${unique_types[@]}"; do
                if [[ "$type_item" != "$primary_kind" ]]; then
                    if [[ "$type_item" == "variable" ]]; then
                        variable_exists=true
                    else
                        other_types+=("$type_item")
                    fi
                fi
            done
            
            # Show clash warning only for actually conflicting types (not variables)
            if [[ ${#other_types[@]} -gt 0 ]]; then
                # Make type names more descriptive for the warning
                local descriptive_types=()
                for type in "${other_types[@]}"; do
                    if [[ "$type" == "file" ]]; then
                        descriptive_types+=("executable file in PATH")
                    else
                        descriptive_types+=("$type")
                    fi
                done
                
                local types_str
                if [[ ${#descriptive_types[@]} -eq 1 ]]; then
                    types_str="${descriptive_types[0]}"
                else
                    local last_type="${descriptive_types[-1]}"
                    unset 'descriptive_types[-1]'
                    types_str=$(IFS=', '; echo "${descriptive_types[*]}")
                    types_str="$types_str and $last_type"
                fi
                # Only show note at top level to avoid duplication during recursive investigations
                if [[ $depth -eq 0 ]]; then
                    echo -e "${CYAN}Note: '${WHITE}$file${CYAN}' also exists as $types_str (not used, $primary_kind takes precedence)${NC}"
                fi
            fi
            
            # Show variable information separately (not as a clash)
            if [[ "$variable_exists" == "true" && "$primary_kind" != "variable" ]]; then
                echo -e "${CYAN}ℹ Also available as variable: ${GREEN}\${$file}${NC}"
            fi
                
                # Special warning for function overriding PATH executable
                if [[ "$primary_kind" == "function" ]]; then
                    for type_item in "${other_types[@]}"; do
                        if [[ "$type_item" == "file" ]]; then
                            local exec_path
                            exec_path=$(type -P "$file" 2>/dev/null)
                            if [[ -n "$exec_path" && -x "$exec_path" ]]; then
                                echo -e "${RED}⚠ CRITICAL: Function '${WHITE}$file${RED}' is overriding the PATH executable '${YELLOW}$exec_path${RED}'. This may cause unexpected behavior!${NC}"
                                echo -e "${CYAN}💡 Tip: Use 'command $file' or '\\$file' to call the original executable.${NC}"
                            fi
                            break
                        fi
                    done
                fi
            fi
        fi
        
        # Add keyword description if it's a keyword
        if [[ "$primary_kind" == "keyword" && -n "${bash_keywords[$file]}" ]]; then
            echo -e "${MAGENTA}Keyword description: ${bash_keywords[$file]}${NC}"
        fi
        echo

        if [ "$primary_kind" = "alias" ]; then
            local alias_def
            alias_def=$(alias "$file" | sed -E "s/^alias $file='(.*)'/\1/" | sed "s/'$//" | sed -e 's/\x1b\[[0-9;]*m//g' | sed -e 's/\\033\[[0-9;]*m//g')
            # Only show alias expansion at top level to avoid duplication during recursive investigations
            if [[ $depth -eq 0 ]]; then
                echo -e "${MAGENTA}Alias expansion: '${WHITE}$file${MAGENTA}' → $alias_def${NC}"
            fi
            echo
            
            # Search for alias definition source file (similar to function search)
            # Only show search message at top level to avoid duplication
            if [[ $depth -eq 0 ]]; then
                echo -e "${CYAN}Searching for alias '${WHITE}$file${CYAN}' definition source file...${NC}"
            fi
            local alias_src_file=""

            # Call alias source search directly (timeout subprocess was broken)
            alias_src_file=$(find_alias_source "$file" 2>/dev/null || echo "")

            if [[ -n "$alias_src_file" ]]; then
                local found_file found_line
                if [[ "$alias_src_file" =~ \|TRAIL\| ]]; then
                    # Contains trail information
                    local file_and_line="${alias_src_file%|TRAIL|*}"
                    local trail="${alias_src_file#*|TRAIL|}"
                    found_file="${file_and_line%:*}"
                    found_line="${file_and_line##*:}"
                else
                    # Simple file:line format
                    found_file="${alias_src_file%:*}"
                    found_line="${alias_src_file##*:}"
                fi
                
                # Only show source search results at top level
                if [[ $depth -eq 0 ]]; then
                    echo -e "${GREEN}Alias '${WHITE}$file${GREEN}' found in: ${YELLOW}$found_file${GREEN}, line $found_line${NC}"
                    
                    # Show sourcing trail similar to functions
                    local backward_trail=""
                    local search_file="$found_file"
                    
                    if [[ "$alias_src_file" =~ \|TRAIL\| ]]; then
                        local trail="${alias_src_file#*|TRAIL|}"
                        echo -e "${CYAN}Sourcing trail:${NC}"
                        echo -e "${YELLOW}  $trail${NC}"
                    fi
                    echo
                fi
            else
                # Only show not found message at top level
                if [[ $depth -eq 0 ]]; then
                    echo -e "${YELLOW}Alias '${WHITE}$file${YELLOW}' definition not found in common source files.${NC}"
                    echo
                fi
            fi
            
            # Extract first word more carefully to avoid command execution
            local first_word
            first_word=$(echo "$alias_def" | sed -e 's/\x1b\[[0-9;]*m//g' | sed -e 's/\\033\[[0-9;]*m//g' | awk '{print $1}')
            
            # Skip analysis if the alias contains shell operators that could cause execution
            if [[ "$alias_def" =~ [\&\|\;] ]]; then
                echo -e "${YELLOW}Alias contains shell operators (&&, ||, ;, etc.). Skipping target analysis to prevent execution.${NC}"
                echo
            elif [[ "$first_word" = /* || "$first_word" = .* ]]; then
                # Absolute or relative path
                [ -x "$first_word" ] && {
                    echo -e "${GREEN}${indent}Alias target '${WHITE}$first_word${GREEN}' appears to be a file. Inspecting...${NC}"
                    if [[ $depth -lt 3 ]]; then  # Prevent infinite recursion
                        investigate_target "$first_word" "$depth"
                    else
                        echo -e "${YELLOW}${indent}Maximum nesting depth reached. Use 'i $first_word' to investigate further.${NC}"
                    fi
                }
            else
                # Check if it's another alias first
                local target_type
                target_type=$(type -t "$first_word" 2>/dev/null)
                
                if [[ "$target_type" == "alias" ]]; then
                    # Follow the alias one level (like bash does)
                    local nested_alias_def
                    nested_alias_def=$(alias "$first_word" 2>/dev/null | sed -E "s/^alias $first_word='(.*)'/\1/" | sed "s/'$//" | sed -e 's/\x1b\[[0-9;]*m//g' | sed -e 's/\\033\[[0-9;]*m//g')
                    if [[ -n "$nested_alias_def" ]]; then
                        # Extract first word of the nested alias
                        local nested_first_word
                        nested_first_word=$(echo "$nested_alias_def" | sed -e 's/\x1b\[[0-9;]*m//g' | sed -e 's/\\033\[[0-9;]*m//g' | awk '{print $1}')

                        # Check if this is a self-referential alias (alias tree='tree -c')
                        if [[ "$nested_first_word" == "$first_word" ]]; then
                            # Self-referential alias - bash only expands once
                            if [[ $depth -eq 0 ]]; then
                                echo -e "${CYAN}${indent}Alias target '${WHITE}$first_word${CYAN}' references itself: '${YELLOW}$nested_alias_def${CYAN}'${NC}"
                                echo -e "${GREEN}${indent}Note: Bash performs single-level alias expansion only.${NC}"
                                echo -e "${GREEN}${indent}The second '${WHITE}$first_word${GREEN}' will resolve to the actual command from PATH.${NC}"
                                echo
                            fi

                            # Find the actual command that would execute (bypass the alias)
                            # Use 'type -P' to find the executable in PATH, ignoring aliases
                            local actual_command
                            actual_command=$(type -P "$first_word" 2>/dev/null)
                            if [[ -n "$actual_command" ]]; then
                                if [[ $depth -eq 0 ]]; then
                                    local extra_args="${nested_alias_def#* }"
                                    if [[ "$extra_args" == "$nested_alias_def" ]]; then
                                        # No extra arguments
                                        echo -e "${GREEN}${indent}Actual command that executes: '${YELLOW}$actual_command${GREEN}'${NC}"
                                    else
                                        echo -e "${GREEN}${indent}Actual command that executes: '${YELLOW}$actual_command${GREEN}' with arguments: '${YELLOW}$extra_args${GREEN}'${NC}"
                                    fi
                                fi

                                # Track the final resolved target to avoid duplicates in secondary PATH matches
                                track_alias_target "$actual_command"

                                if [[ $depth -lt 3 ]]; then
                                    investigate_target "$actual_command" "$depth"
                                else
                                    echo -e "${YELLOW}${indent}Maximum nesting depth reached. Use 'i $actual_command' to investigate further.${NC}"
                                fi
                            else
                                echo -e "${RED}${indent}Could not find actual command '${WHITE}$first_word${RED}' in PATH.${NC}"
                            fi
                        else
                            # Normal nested alias - follow it
                            if [[ $depth -eq 0 ]]; then
                                echo -e "${CYAN}${indent}Alias target '${WHITE}$first_word${CYAN}' is also an alias: '${YELLOW}$nested_alias_def${CYAN}'${NC}"
                            fi

                            if [[ $depth -lt 3 ]]; then  # Prevent infinite recursion
                                investigate_target "$first_word" "$depth"
                            else
                                echo -e "${YELLOW}${indent}Maximum nesting depth reached. Use 'i $first_word' to investigate further.${NC}"
                            fi
                        fi
                    fi
                    echo
                elif [[ "$target_type" == "function" ]]; then
                    echo -e "${CYAN}${indent}Alias target '${WHITE}$first_word${CYAN}' is a function. Showing definition:${NC}"
                    echo
                    if [[ $depth -lt 3 ]]; then  # Prevent infinite recursion
                        investigate_target "$first_word" "$depth"
                    else
                        echo -e "${YELLOW}${indent}Maximum nesting depth reached. Use 'i $first_word' to investigate further.${NC}"
                    fi
                elif command -v "$first_word" &>/dev/null; then
                    local target
                    target=$(type -P "$first_word" 2>/dev/null)
                    if [[ -n "$target" && -f "$target" ]]; then
                        echo -e "${GREEN}${indent}Alias target '${WHITE}$first_word${GREEN}' resolves to '${YELLOW}$target${GREEN}'. Inspecting...${NC}"

                        # Track the final resolved target to avoid duplicates in secondary PATH matches
                        track_alias_target "$target"

                        if [[ $depth -lt 3 ]]; then  # Prevent infinite recursion
                            investigate_target "$target" "$depth"
                        else
                            echo -e "${YELLOW}${indent}Maximum nesting depth reached. Use 'i $target' to investigate further.${NC}"
                        fi
                    else
                        echo -e "${YELLOW}${indent}Alias target '${WHITE}$first_word${YELLOW}' is a ${target_type:-command} but could not determine file path.${NC}"
                        echo
                    fi
                fi
            fi
        elif [ "$primary_kind" = "function" ]; then
            show_function_definition "$file" "true"
        elif [[ "$primary_kind" == "builtin" || "$primary_kind" == "keyword" || "$primary_kind" == "file" ]]; then
            local path
            path=$(command -v "$file")
            
            # Path resolution shown by inspect_file, no need to duplicate
            
            # Show help for builtins
            if [[ "$primary_kind" == "builtin" ]]; then
                echo -e "${CYAN}Built-in help for '${WHITE}$file${CYAN}':${NC}"
                local help_output
                help_output=$(help "$file" 2>/dev/null)
                if [[ -n "$help_output" ]]; then
                    if [[ $no_truncate -eq 1 ]]; then
                        echo "$help_output" | sed "s/^/${indent}/"
                    else
                        echo "$help_output" | head -n "$preview_lines" | sed "s/^/${indent}/"
                        local help_lines
                        help_lines=$(echo "$help_output" | wc -l)
                        if [[ "$help_lines" -gt "$preview_lines" ]]; then
                            local truncated_lines=$((help_lines - preview_lines))
                            # Only show truncation message if more than 10 lines would be truncated
                            if [ "$truncated_lines" -gt 10 ]; then
                                echo "${indent}[...truncated $truncated_lines more lines...]"
                            fi
                        fi
                    fi
                else
                    echo "${indent}No help available for this builtin."
                fi
                echo
            fi


            if [[ "$primary_kind" == "file" ]]; then
                inspect_file "$path" "true"
            fi
            echo
        elif [ "$primary_kind" = "variable" ]; then
            show_variable_info "$file"
        fi
    # Show additional details for overshadowed items (only at top level to avoid duplication)
    if [[ ${#unique_types[@]} -gt 1 && $depth -eq 0 ]]; then
        # Determine what types of additional items we have
        local has_conflicting=false
        local has_variables=false
        
        for type_item in "${unique_types[@]}"; do
            if [[ "$type_item" != "$primary_kind" ]]; then
                if [[ "$type_item" == "variable" ]]; then
                    has_variables=true
                else
                    has_conflicting=true
                fi
            fi
        done
        
        # Show appropriate header based on what we found
        if [[ "$has_conflicting" == "true" && "$has_variables" == "true" ]]; then
            echo -e "${CYAN}Additional details for other definitions:${NC}"
        elif [[ "$has_conflicting" == "true" ]]; then
            echo -e "${CYAN}Additional details for overshadowed definitions:${NC}"
        elif [[ "$has_variables" == "true" ]]; then
            echo -e "${CYAN}Related variable information:${NC}"
        fi
        echo
        
        for type_item in "${unique_types[@]}"; do
            
            if [[ "$type_item" == "$primary_kind" ]]; then
                continue
            fi
            
            
            case "$type_item" in
                "function")
                    
                    # Test function definition retrieval
                    local test_func_def
                    test_func_def=$(declare -f "$file" 2>/dev/null)
                    
                    echo -e "${CYAN}Overshadowed function '${WHITE}$file${CYAN}':${NC}"
                    show_function_definition "$file" "false"
                    ;;
                "alias")
                    local alias_def
                    alias_def=$(alias "$file" 2>/dev/null | sed -E "s/^alias $file='(.*)'/\1/" | sed "s/'$//" | sed -e 's/\x1b\[[0-9;]*m//g' | sed -e 's/\\033\[[0-9;]*m//g')
                    if [[ -n "$alias_def" ]]; then
                        echo -e "${CYAN}Overshadowed alias '${WHITE}$file${CYAN}': ${MAGENTA}$alias_def${NC}"
                        echo
                    fi
                    ;;
                "builtin")
                    echo -e "${CYAN}Overshadowed builtin '${WHITE}$file${CYAN}':${NC}"
                    local help_output
                    help_output=$(help "$file" 2>/dev/null)
                    if [[ -n "$help_output" ]]; then
                        if [[ $no_truncate -eq 1 ]]; then
                            echo "$help_output" | sed "s/^/${indent}/"
                        else
                            echo "$help_output" | head -n 5 | sed "s/^/${indent}/"
                            local help_lines
                            help_lines=$(echo "$help_output" | wc -l)
                            if [[ "$help_lines" -gt 5 ]]; then
                                local truncated_lines=$((help_lines - 5))
                                # Only show truncation message if more than 10 lines would be truncated
                                if [ "$truncated_lines" -gt 10 ]; then
                                    echo "${indent}[...truncated $truncated_lines more lines...]"
                                fi
                            fi
                        fi
                    else
                        echo "${indent}No help available for this builtin."
                    fi
                    echo
                    ;;
                "file")
                    local file_path
                    file_path=$(command -v "$file" 2>/dev/null)
                    if [[ -n "$file_path" && -f "$file_path" ]]; then
                        echo -e "${CYAN}Overshadowed executable '${WHITE}$file${CYAN}' at: ${YELLOW}$file_path${NC}"
                        inspect_file "$file_path" "true"
                        echo
                    fi
                    ;;
                "variable")
                    echo -e "${CYAN}Variable ${GREEN}\${$file}${CYAN}:${NC}"
                    show_variable_info "$file"
                    ;;
                *)
                    ;;
            esac
        done
    fi
    

    # Get other matches from $PATH, excluding the primary one we already showed
    local match_lines=()
    local primary_path
    primary_path=$(command -v "$file" 2>/dev/null || true)
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^.*\ is\ / ]]; then
            local this_path="${line#* is }"
            # Only include if it's different from the primary path we already showed
            if [[ "$this_path" != "$primary_path" ]]; then
                match_lines+=("$line")
            fi
        fi
    done < <(type -a "$file" 2>/dev/null)

    # Only show "Other matches from $PATH" if there are actually other matches (only at top level)
    # For aliases/functions, skip if they don't use PATH (no file overshadowed)
    local show_secondary=false
    if [ "${#match_lines[@]}" -gt 0 ] && [[ $depth -eq 0 ]]; then
        if [[ "$primary_kind" == "alias" ]] || [[ "$primary_kind" == "function" ]]; then
            # Only show if there's an overshadowed file in PATH
            for type_item in "${other_types[@]}"; do
                if [[ "$type_item" == "file" ]]; then
                    show_secondary=true
                    break
                fi
            done
        else
            show_secondary=true
        fi
    fi

    if [[ "$show_secondary" == "true" ]]; then
        # Process all PATH matches and deduplicate by resolved target
        local -A seen_targets=()      # Maps inode -> first path that showed it
        local -a all_path_info=()     # Array of "original_path|resolved_target|inode"

        # Pre-seed with alias target if one was shown
        if [[ -n "$shown_alias_target_inode" ]]; then
            seen_targets["$shown_alias_target_inode"]="$shown_alias_target_path"
        fi

        # Pre-seed with file shown in main section (for regular files)
        if [[ -n "$shown_file_path" ]]; then
            local shown_file_inode
            shown_file_inode=$(stat -Lc '%d:%i' "$shown_file_path" 2>/dev/null)
            if [[ -n "$shown_file_inode" ]]; then
                seen_targets["$shown_file_inode"]="$shown_file_path"
            fi
        fi

        # First pass: resolve all paths
        for line in "${match_lines[@]}"; do
            local match_path="${line#* is }"
            [[ ! "$match_path" = /* || ! -e "$match_path" ]] && continue

            # Skip exact path matches we've already investigated (for aliases or files)
            if [[ -n "$shown_alias_target_path" && "$match_path" == "$shown_alias_target_path" ]]; then
                continue
            fi
            if [[ -n "$shown_file_path" && "$match_path" == "$shown_file_path" ]]; then
                continue
            fi

            # Resolve the target (follow symlinks)
            local resolved_target
            resolved_target=$(readlink -f "$match_path" 2>/dev/null || echo "$match_path")

            # Get inode of resolved target
            local inode
            inode=$(stat -Lc '%d:%i' "$resolved_target" 2>/dev/null)

            # Store for categorization
            all_path_info+=("$match_path|$resolved_target|$inode")
        done

        # Second pass: categorize by showing only unique targets
        local -a paths_to_show=()
        local -a hardlink_pairs=()
        local -a symlink_pairs=()

        for info in "${all_path_info[@]}"; do
            local match_path="${info%%|*}"
            local rest="${info#*|}"
            local resolved_target="${rest%%|*}"
            local inode="${rest##*|}"

            if [[ -n "${seen_targets[$inode]}" ]]; then
                # This target was already shown (earlier in PATH or during alias investigation)
                local first_shown="${seen_targets[$inode]}"

                if [[ -L "$match_path" ]]; then
                    # It's a symlink pointing to already-shown target
                    symlink_pairs+=("$match_path|$resolved_target")
                else
                    # It's a hardlink to already-shown target
                    hardlink_pairs+=("$match_path|$first_shown")
                fi
            else
                # New unique target - will show full details
                paths_to_show+=("$match_path")
                seen_targets["$inode"]="$resolved_target"
            fi
        done

        # Show results
        local has_content=false
        if [ "${#paths_to_show[@]}" -gt 0 ] || [ "${#hardlink_pairs[@]}" -gt 0 ] || [ "${#symlink_pairs[@]}" -gt 0 ]; then
            echo -e "${BLUE}Secondary PATH matches for '${WHITE}$file${BLUE}':${NC}"
            has_content=true
        fi

        # Show symlinks first (most concise)
        for pair in "${symlink_pairs[@]}"; do
            local link_path="${pair%%|*}"
            local target_path="${pair##*|}"
            # Show just the symlink chain without full details since target was already shown
            echo -e "${CYAN}'${WHITE}$link_path${CYAN}' → '${YELLOW}$target_path${CYAN}' (symlink, see above)${NC}"
        done

        # Show hardlinks (concise)
        for pair in "${hardlink_pairs[@]}"; do
            local link_path="${pair%%|*}"
            local target_path="${pair##*|}"
            # Show the hardlink relationship clearly
            echo -e "${YELLOW}'${WHITE}$link_path${YELLOW}' → '${WHITE}$target_path${YELLOW}' (hardlink, see above)${NC}"
        done

        # Show unique files (full details)
        for path in "${paths_to_show[@]}"; do
            inspect_file "$path" "true"
        done

        if [[ "$has_content" == "true" ]]; then
            echo
            found=1
        fi
    fi

    if [[ -e "$file" && ! "$file" =~ / ]]; then
        local local_file="./$file"
        echo -e "${MAGENTA}Local file '${YELLOW}${local_file}${MAGENTA}' in current directory:${NC}"
        inspect_file "$local_file" "false"
        echo
        found=1
    fi

    if [[ "$file" == */* && -e "$file" ]]; then
        inspect_file "$file" "false"
        echo
        found=1
    fi

    if [ $found -eq 0 ]; then
        echo -e "${RED}'${WHITE}$file${RED}' not found as file, alias, function, builtin, keyword, or executable.${NC}"
        return 1
    fi
}

# Enhanced tab completion for the investigate function
_investigate_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # Handle flags first
    if [[ "$cur" == --* ]]; then
        COMPREPLY=( $(compgen -W "--debug --help --functions --aliases --variables --builtins --files --commands --no-truncate" -- "$cur") )
        return
    elif [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "-f -a -v -b -c -n" -- "$cur") )
        return
    fi
    
    # Smart completion based on filter flags
    local completions=()
    
    # Check if previous word was a filter flag and complete accordingly
    if [[ "$prev" == "--functions" || "$prev" == "-f" ]]; then
        # Only complete functions
        if [[ -n "$cur" ]]; then
            mapfile -t funcs < <(compgen -A function -- "$cur" 2>/dev/null)
            completions+=("${funcs[@]}")
        fi
    elif [[ "$prev" == "--aliases" || "$prev" == "-a" ]]; then
        # Only complete aliases
        if [[ -n "$cur" ]]; then
            mapfile -t aliases < <(compgen -A alias -- "$cur" 2>/dev/null)
            completions+=("${aliases[@]}")
        fi
    elif [[ "$prev" == "--variables" || "$prev" == "-v" ]]; then
        # Only complete variables
        if [[ -n "$cur" ]]; then
            mapfile -t vars < <(compgen -A variable -- "$cur" 2>/dev/null | head -50)
            completions+=("${vars[@]}")
        fi
    elif [[ "$prev" == "--builtins" || "$prev" == "-b" ]]; then
        # Only complete builtins and keywords
        if [[ -n "$cur" ]]; then
            mapfile -t builtins < <(compgen -A builtin -- "$cur" 2>/dev/null)
            mapfile -t keywords < <(compgen -A keyword -- "$cur" 2>/dev/null)
            completions+=("${builtins[@]}" "${keywords[@]}")
        fi
    elif [[ "$prev" == "--files" ]]; then
        # Only complete files
        if [[ -n "$cur" ]]; then
            mapfile -t files < <(compgen -f -- "$cur" 2>/dev/null | head -50)
            completions+=("${files[@]}")
        fi
    elif [[ "$prev" == "--commands" || "$prev" == "-c" ]]; then
        # Only complete executable commands
        mapfile -t cmds < <(compgen -c -- "$cur" 2>/dev/null | head -50)
        completions+=("${cmds[@]}")
    elif [[ "$prev" == "--debug" || "$prev" == "--help" || "$prev" == "--no-truncate" || "$prev" == "-n" ]]; then
        # These flags don't take arguments, complete normally but limited
        if [[ -n "$cur" ]]; then
            mapfile -t files < <(compgen -f -- "$cur" 2>/dev/null | head -20)
            mapfile -t cmds < <(compgen -c -- "$cur" 2>/dev/null | head -20)
            mapfile -t funcs < <(compgen -A function -- "$cur" 2>/dev/null | head -20)
            completions+=("${files[@]}" "${cmds[@]}" "${funcs[@]}")
        else
            COMPREPLY=( $(compgen -W "ls grep echo cd bash python vim" -- "$cur") )
            return
        fi
    else
        # No filter flag or normal completion - comprehensive list
        
        # 1. Files (but limit to avoid performance issues)
        if [[ -n "$cur" ]]; then
            mapfile -t files < <(compgen -f -- "$cur" 2>/dev/null | head -30)
            completions+=("${files[@]}")
        fi
        
        # 2. Executable commands in PATH
        mapfile -t cmds < <(compgen -c -- "$cur" 2>/dev/null | head -40)
        completions+=("${cmds[@]}")
        
        # 3. Shell functions
        if [[ -n "$cur" ]]; then
            mapfile -t funcs < <(compgen -A function -- "$cur" 2>/dev/null)
            completions+=("${funcs[@]}")
        fi
        
        # 4. Aliases
        if [[ -n "$cur" ]]; then
            mapfile -t aliases < <(compgen -A alias -- "$cur" 2>/dev/null)
            completions+=("${aliases[@]}")
        fi
        
        # 5. Variables (limited)
        if [[ -n "$cur" ]]; then
            mapfile -t vars < <(compgen -A variable -- "$cur" 2>/dev/null | head -20)
            completions+=("${vars[@]}")
        fi
        
        # 6. Builtins and keywords
        if [[ -n "$cur" ]]; then
            mapfile -t builtins < <(compgen -A builtin -- "$cur" 2>/dev/null)
            mapfile -t keywords < <(compgen -A keyword -- "$cur" 2>/dev/null)
            completions+=("${builtins[@]}" "${keywords[@]}")
        fi
    fi
    
    # Remove duplicates and sort (but limit total results for performance)
    if [[ ${#completions[@]} -gt 0 ]]; then
        mapfile -t unique_completions < <(printf "%s\n" "${completions[@]}" | sort -u | head -100)
        COMPREPLY=("${unique_completions[@]}")
    else
        # If no current input, provide a few common examples to get started
        COMPREPLY=( $(compgen -W "ls grep echo cd bash python vim" -- "$cur") )
    fi
}

complete -F _investigate_completion i
