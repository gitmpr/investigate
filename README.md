# investigate.sh

A comprehensive bash inspection tool that provides detailed analysis of files, commands, aliases, functions, builtins, and keywords with beautifully formatted terminal output using Unicode box-drawing characters.

> **Note:** This is the **Bash version** (stable and feature-complete). Fish and Zsh versions are available in the [`fish/`](fish/) and [`zsh/`](zsh/) directories but are still **work in progress**. See their respective READMEs for current status.

## Features

- **Smart Command Analysis** - Automatically detects and analyzes files, commands, aliases, functions, builtins, and keywords
- **Beautiful Box Drawing** - Unicode box-drawing characters with ANSI color support for clean, organized output
- **Symlink Following** - Recursive investigation of symlinks with loop protection
- **Function Source Discovery** - Searches across config files to find where functions are defined
- **Syntax Highlighting** - Integration with `bat` for code syntax highlighting
- **Word Wrapping** - Intelligent text wrapping that preserves ANSI color codes
- **Tab Completion** - Built-in bash completion for files and commands
- **Flexible Display Options** - Filter by type (functions, aliases, variables, etc.) and control truncation

## Quick Start

```bash
# Source the script (creates 'i' function in your shell)
source investigate.sh

# Use 'i' to investigate anything
i grep                    # Inspect the grep command
i my_function            # Analyze a custom shell function
i script.sh --debug      # Debug function source tracing
i ./local_file           # Examine files in current directory
i cd                     # Inspect shell builtins
i cd -n                  # Show full builtin help without truncation
```

**Note:** The script creates a shell function named `i` (short for "investigate") as the main command interface. When sourced in your `.bashrc`, this makes investigation as quick as typing `i <target>`.

## Usage

```bash
i <name> [options]
```

**Arguments:**
- `<name>` - The target to investigate (file, command, alias, function, etc.)

**Options:**
- `--debug` - Shows verbose output when tracing function sources
- `--functions, -f` - Show only if target is a function
- `--aliases, -a` - Show only if target is an alias
- `--variables, -v` - Show only if target is a variable
- `--builtins, -b` - Show only if target is a builtin or keyword
- `--files` - Show only if target is a file
- `--commands, -c` - Show only if target is an executable command
- `--no-truncate, -n` - Show full content without truncating file previews or help output

## Installation

### Method 1: Source the Script

Add to your `~/.bashrc` or `~/.bash_profile`:

```bash
source /path/to/investigate.sh
```

Then reload your shell:

```bash
source ~/.bashrc
```

### Method 2: Install as Executable

Copy the script to a directory in your `PATH`:

```bash
# Make executable
chmod +x investigate.sh

# Copy to local bin directory
mkdir -p ~/.local/bin
cp investigate.sh ~/.local/bin/i

# Ensure ~/.local/bin is in your PATH (add to ~/.bashrc if needed)
export PATH="$HOME/.local/bin:$PATH"

# Use directly
i grep
i cd -n
```

### macOS Compatibility Note

macOS ships with Bash 3.2 by default (last GPLv2 version). This tool **requires Bash 4.0+** for associative arrays and other modern features.

**To install a newer Bash on macOS:**

```bash
# Using Homebrew
brew install bash

# Add to /etc/shells
echo /opt/homebrew/bin/bash | sudo tee -a /etc/shells

# Optional: change default shell
chsh -s /opt/homebrew/bin/bash
```

### Fish and Zsh Support

**Status:** In development

Fish and Zsh versions are planned. The current implementation is Bash-specific due to:
- Bash-specific syntax (arrays, parameter expansion, `declare -F`)
- Shell builtin inspection (`help`, `type -t`)
- Completion system integration

Contributions for fish/zsh ports are welcome!

## What It Can Investigate

### Files
- File type detection and metadata
- Content preview (with configurable line limits)
- Directory listings
- Binary file detection
- ANSI escape sequence detection

### Commands
- Executables with path and file analysis
- Aliases with expansion
- Shell builtins with help integration
- Keywords with descriptions
- Name clash detection and warnings

### Functions
- Function definition display with syntax highlighting (requires `bat`)
- Source file discovery across:
  - User config files (`~/.bashrc`, `~/.bash_profile`)
  - System files (`/etc/profile`, `/etc/bash.bashrc`)
  - Framework files (Oh My Bash, Bash-it)
  - Package managers (Conda, Homebrew)
  - Custom locations (`~/.dotfiles/`, `~/.config/bash/`)

### Symlinks
- Automatic symlink following
- Recursive target investigation
- Hardlink detection
- Infinite loop prevention with inode tracking

## Configuration

### Environment Variables

- `DEBUG_LEVEL` - Controls debug output verbosity (0-4)
- `COLUMNS` - Terminal width (auto-detected if not set)

### Customizable Settings

Edit these variables in [investigate.sh](investigate.sh):

- `preview_lines` - Number of lines in file previews (default: 15)
- `indent` - Indentation string for nested output (default: "    ")

## Technical Details

### Requirements

- **Bash**: 4.0 or higher
- **Optional**: `bat` for syntax highlighting
- **System tools**: `file`, `stat`, `realpath`, `find`, `grep`

### Performance

- 3-second timeout on function source searches
- Inode-based duplicate detection for hardlinks
- Efficient ANSI escape sequence handling
- Terminal width caching

### Security

- No execution of untrusted code
- Safe alias target analysis
- Path traversal protection
- Binary file detection

## Documentation

- [Full Documentation](INVESTIGATE_DOCUMENTATION.md) - Comprehensive function reference and technical details
- [BATS Testing Insights](BATS_BASH_TESTING_INSIGHTS.md) - Testing framework insights
- [Testing Documentation](BATS_INVESTIGATE_TESTING_INSIGHTS.md) - Test suite details

## Testing

The project includes a comprehensive test suite using BATS (Bash Automated Testing System):

```bash
# Run all tests
bats tests/

# Run specific test files
bats tests/test_investigate.bats
bats tests/test_core.bats
bats tests/test_flags.bats
```

See [`tests/`](tests/) directory for the full test suite with 117+ test cases covering:
- Core functionality and edge cases
- Error conditions and recovery
- Performance and compatibility
- Flag combinations and filtering

## Example Output

The tool uses Unicode box-drawing characters to present information in a clean, organized format with color coding for different types of information.

## Contributing

Contributions, bug reports, and feature requests are welcome! This tool was developed as part of a comprehensive bash debugging and investigation toolkit.

## License

MIT License
