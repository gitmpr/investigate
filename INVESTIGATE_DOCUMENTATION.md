# investigate.sh Documentation

## Overview
`investigate.sh` is a comprehensive bash inspection tool that provides detailed analysis of files, commands, aliases, functions, builtins, and keywords in a beautifully formatted output.

## Main Function: `i()`

### Usage
```bash
i <name> [--debug]
```

### Arguments
- `<name>`: Required. The target to investigate (file, command, alias, function, etc.)
- `--debug`: Optional. Shows verbose output when tracing function sources

### Examples
```bash
i grep                    # Inspect the grep command
i my_function            # Analyze a custom shell function
i script.sh --debug      # Debug function source tracing
i ./local_file           # Examine files in current directory
i cd                     # Inspect shell builtins
```

## Core Features

### 1. Box Drawing System
- **Functions**: `render_box()`, `build_horizontal_line()`, `build_content_line()`, `build_empty_line()`
- **Purpose**: Creates ASCII art frames for formatted output
- **Characters**: Uses Unicode box-drawing characters (╭, ╮, ╰, ╯, ─, │, ├, ┤)

### 2. Debug Logging System
- **Functions**: `debug_basic()`, `debug_detailed()`, `debug_full()`, `debug_internal()`
- **Levels**: 
  - Level 1: Basic debug output
  - Level 2: Detailed debug output
  - Level 3: Full debug output
  - Level 4: Internal debug output
- **Usage**: Set `DEBUG_LEVEL` environment variable (0-4)

### 3. Text Processing
- **Function**: `calculate_visible_length()`
- **Purpose**: Calculates string length excluding ANSI escape sequences
- **Implementation**: Pure bash character-by-character parsing

- **Function**: `word_wrap_line()`
- **Purpose**: Wraps text while preserving ANSI color codes
- **Features**: Respects word boundaries, maintains color formatting

### 4. Responsive Layout
- **Function**: `process_content_for_width()`
- **Purpose**: Adapts content to terminal width
- **Features**: Automatic terminal width detection, minimum width constraints

### 5. Investigation Capabilities

#### File Analysis
- File type detection using `file` command
- Smart line wrapping for long type descriptions
- Directory content listing (truncated for large directories)
- Binary file detection (skips preview for ELF files)
- ANSI escape sequence detection
- File preview with configurable line limits

#### Symlink Handling
- Automatic symlink detection and following
- Recursive target investigation
- Hardlink detection and reporting
- Prevents infinite loops with inode tracking

#### Function Analysis
- Function definition display with syntax highlighting (if `bat` available)
- Source file searching across common bash configuration files
- Timeout protection for long searches (3-second limit)
- Recursive source file parsing

#### Command Classification
- Aliases with expansion and target analysis
- Shell builtins with help integration
- Keywords with descriptions
- Executables with file analysis
- Name clash detection and warnings

### 6. Advanced Features

#### Source File Discovery
Searches for function definitions in:
- User config files: `~/.bashrc`, `~/.bash_profile`, etc.
- System files: `/etc/profile`, `/etc/bash.bashrc`
- Framework files: Oh My Bash, Bash-it
- Package manager files: Conda, Homebrew
- Custom locations: `~/.dotfiles/`, `~/.config/bash/`

#### Tab Completion
- Function: `_investigate_completion()`
- Completes both file names and command names
- Integrated with bash completion system

#### Error Handling
- Graceful handling of non-existent files
- Timeout protection for long operations
- Robust path resolution
- Safe command execution (prevents alias loops)

## Configuration

### Environment Variables
- `DEBUG_LEVEL`: Controls debug output verbosity (0-4)
- `COLUMNS`: Terminal width (auto-detected if not set)

### Customizable Settings
- `preview_lines`: Number of lines to show in previews (default: 15)
- `indent`: Indentation string for nested output (default: "    ")

## Function Reference

### Box Drawing Functions
- `render_box(title, content_array, min_width, show_separator, terminal_width)`
- `build_horizontal_line(line_type, box_width)`
- `build_content_line(content, box_width, padding_char)`
- `build_empty_line(box_width)`
- `calculate_box_width(content_array, min_width, max_width)`

### Text Processing Functions
- `calculate_visible_length(string)`
- `word_wrap_line(line, max_width, result_array_ref)`
- `process_content_for_width(input_array_ref, output_array_ref, terminal_width)`

### Debug Functions
- `debug_basic(message)` - Level 1 debug output
- `debug_detailed(message)` - Level 2 debug output  
- `debug_full(message)` - Level 3 debug output
- `debug_internal(message)` - Level 4 debug output

### Investigation Functions
- `i(name, --debug)` - Main investigation function
- `inspect_file(path)` - File analysis
- `show_file_preview(path)` - File content preview
- `show_function_definition(name, show_source_search)` - Function display
- `find_function_source(name)` - Function source location
- `find_function_definition(name, file, maxdepth)` - Recursive function search

### Completion Function
- `_investigate_completion()` - Tab completion for investigate function

## Technical Details

### Dependencies
- **Required**: bash 4.0+
- **Optional**: `bat` (syntax highlighting)
- **System tools**: `file`, `stat`, `realpath`, `find`, `grep`

### Performance Considerations
- 3-second timeout on function source searches
- Inode-based duplicate detection for hardlinks
- Efficient ANSI escape sequence removal
- Terminal width caching

### Security Features
- No execution of untrusted code
- Safe alias target analysis
- Path traversal protection
- Binary file detection

## Error Conditions

### Common Errors
1. **File not found**: Returns error code 1
2. **Too many arguments**: Shows usage and returns error code 1
3. **Permission denied**: Gracefully handles unreadable files
4. **Search timeout**: Reports timeout after 3 seconds

### Error Recovery
- Fallback mechanisms for missing tools
- Graceful degradation without optional dependencies
- Safe defaults for configuration values

## Installation and Usage

### Installation
```bash
# Source the script in your shell configuration
source /path/to/investigate.sh

# Or add to ~/.bashrc
echo "source /path/to/investigate.sh" >> ~/.bashrc
```

### Basic Usage
```bash
# Investigate a command
i ls

# Debug a function search
i my_custom_function --debug

# Analyze a local file
i ./script.sh

# Show help
i --help
```

## Fixes Applied

### Version 1.1 Improvements
1. **ANSI Escape Sequence Handling**: Pure bash implementation for cross-platform compatibility (no external dependencies)
2. **Timeout Mechanism**: Enhanced timeout handling to prevent hangs during function searches
3. **Path Resolution**: Added safety checks for empty path variables to prevent comparison errors
4. **Error Handling**: Improved error recovery and graceful degradation

### Testing
- Comprehensive test suite with 45 test cases
- Tests all major functionality and edge cases
- Validates error conditions and recovery mechanisms
- Performance and compatibility testing
