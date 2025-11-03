# Test Suite

Comprehensive test suite for investigate.sh using BATS (Bash Automated Testing System).

## Requirements

- BATS 1.0+ installed
- Bash 4.0+

## Running Tests

Run tests from the repository root:

```bash
# Run all tests
bats tests/

# Run specific test file
bats tests/test_investigate.bats
bats tests/test_core.bats
bats tests/test_flags.bats

# Run with verbose output
bats tests/ -t
```

## Test Files

- `test_investigate.bats` - Main comprehensive test suite (30 tests)
- `test_core.bats` - Core functionality tests (15 tests)
- `test_flags.bats` - Flag combinations and edge cases (53 tests)
- `test_circular_aliases.bats` - Circular alias detection (7 tests, some edge cases WIP)
- `test_essential.bats` - Essential smoke tests (12 tests)

## Test Coverage

- Command analysis (builtins, executables, aliases, functions)
- Flag parsing and combinations
- Terminal detection and color handling
- Function source discovery
- Error handling and edge cases
- Performance with large inputs

## Known Issues

Some circular alias detection edge cases are still being refined. See `test_circular_aliases.bats` for details.
