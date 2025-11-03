# BATS Testing Insights for investigate.sh

This document captures specific lessons learned from testing the investigate.sh tool with BATS.

## Project-Specific Challenges

### The Infinite Loop Problem
**Issue**: Tests would hang for 2+ minutes during alias and function source searches
**Root Cause**: Test-defined functions/aliases don't exist in config files, causing exhaustive filesystem searches

#### Solution Implementation
Added timeout protection to both search functions:

```bash
# Function source search timeout
if command -v timeout >/dev/null 2>&1; then
    src_file=$(timeout 3s bash -c "source '$BATS_TEST_DIRNAME/investigate.sh' 2>/dev/null || source investigate.sh 2>/dev/null; find_function_source '$funcname'" 2>/dev/null || echo "TIMEOUT")
else
    src_file=$(find_function_source "$funcname")
fi

# Alias source search timeout  
if command -v timeout >/dev/null 2>&1; then
    alias_src_file=$(timeout 3s bash -c "source '$BATS_TEST_DIRNAME/investigate.sh' 2>/dev/null || source investigate.sh 2>/dev/null; find_alias_source '$file'" 2>/dev/null || echo "TIMEOUT")
else
    alias_src_file=$(find_alias_source "$file" 2>/dev/null || echo "")
fi
```

### Alias Testing Architecture

#### The Three-Layer Alias Problem
1. **Setup aliases** - defined in `setup()` function
2. **Bash -c aliases** - defined in subprocess commands  
3. **Circular detection** - aliases that reference themselves

#### Complete Solution Pattern
```bash
setup() {
    source "$BATS_TEST_DIRNAME/investigate.sh"
    # CRITICAL: Enable alias expansion
    shopt -s expand_aliases
    
    # Define common test aliases
    alias test_alias='echo "test alias"'
}

@test "alias functionality" {
    # For tests using setup aliases - works directly
    run i test_alias
    
    # For tests needing custom aliases - need full expansion setup
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/investigate.sh'; alias custom='echo custom'; i custom"
}
```

### Circular Alias Detection Testing

#### The Challenge
Testing circular aliases without triggering infinite loops in the test framework itself.

#### Working Pattern
```bash
@test "circular alias detection" {
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/investigate.sh'; alias loop='loop'; i loop"
    [ "$status" -eq 0 ]  # Should complete successfully
    [[ "$output" =~ "Circular reference detected" ]]
    [[ "$output" =~ "Chain: loop → loop" ]]
}
```

Key insights:
- Circular detection must happen in the investigate script, not the test
- Tests verify detection output, not prevention of infinite loops
- Always use `shopt -s expand_aliases` before alias definitions

### Combined Flag Testing

#### Complex Flag Parsing
The investigate script supports combined flags like `-bvf` (equivalent to `-b -v -f`).

#### Test Strategy
```bash
@test "combined flags work" {
    # Test successful combination
    run i test_function -bvf
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "combined flags reject correctly" {
    # Test rejection when filters don't match
    run i test_alias -bf  # alias doesn't match builtin or function filters
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not a builtin" ]]
    [[ "$output" =~ "not a function" ]]
}
```

### Filter Type Testing Patterns

#### Command vs File Classification
Commands are technically files, which created test confusion:

```bash
# investigate classifies 'ls' as 'file' (correct)
# but --commands filter accepts files that are executable (also correct)
@test "--commands flag filters correctly" {
    run i ls --commands
    [ "$status" -eq 0 ]
    # Accept either classification since commands are executable files
    [[ "$output" =~ command|file ]]  # NOTE: unquoted regex!
}
```

#### Builtin vs Keyword Confusion
Some tests incorrectly assumed commands weren't builtins:

```bash
# ❌ WRONG - 'echo' IS a builtin
@test "rejection test" {
    run i echo -b
    [ "$status" -eq 1 ]  # This fails because echo IS a builtin
}

# ✅ CORRECT - use non-builtin command
@test "rejection test" {
    run i grep -b  
    [ "$status" -eq 1 ]  # This works because grep is NOT a builtin
}
```

### Performance Testing Challenges

#### Large Function Timeout Testing
Original problematic approach:
```bash
# ❌ PROBLEMATIC - timeout in wrong context
run bash -c "source script.sh; large_func() { ...; }; timeout 10s i large_func -f"
```

Working approach:
```bash
# ✅ WORKING - function defined in test scope, rely on built-in timeout
@test "large function doesn't hang" {
    large_func() { 
        for i in {1..50}; do echo "line $i"; done
    }
    
    run i large_func -f  # Built-in timeout protection handles this
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
    
    unset -f large_func
}
```

### Test File Organization

#### Strategic Test Separation
- **test_flags.bats**: Flag combinations and parsing logic (53 tests)
- **test_circular_aliases.bats**: Circular reference detection (7 tests) 
- **test_essential.bats**: Core functionality regression tests (12 tests)

#### Benefits
- Easier debugging of specific failures
- Parallel execution without conflicts
- Focused development testing

```bash
# During development - test just new features
bats test_essential.bats

# Full validation
bats test_*.bats
```

### Source Path Handling

#### BATS Test Directory Resolution
The investigate script needs to find itself for timeout subprocess calls:

```bash
# Handles both BATS and normal execution contexts
timeout 3s bash -c "source '$BATS_TEST_DIRNAME/investigate.sh' 2>/dev/null || source investigate.sh 2>/dev/null; find_function_source '$funcname'"
```

This pattern:
1. Tries BATS-specific path first (`$BATS_TEST_DIRNAME/investigate.sh`)
2. Falls back to current directory (`investigate.sh`)
3. Suppresses errors from failed source attempts

### Debugging Strategies Specific to investigate.sh

#### Function Source Search Debug
```bash
@test "debug function search" {
    test_func() { echo "test"; }
    run i test_func --functions --debug
    echo "Status: $status" >&3
    echo "Output: $output" >&3
    # Should show timeout message, not hang
    [[ "$output" =~ "Search.*timed out|function" ]]
}
```

#### Alias Expansion Debug
```bash
@test "debug alias expansion" {
    run bash -c "shopt -s expand_aliases; alias; source investigate.sh; alias test='echo hi'; type test; i test"
    echo "Alias list and test output: $output" >&3
}
```

#### Shell Classification Debug
```bash
@test "debug classification" {
    run i some_command --debug
    echo "Classification details: $output" >&3
    # Look for "Shell classification for 'some_command': type"
}
```

## Lessons Specific to investigate.sh

1. **Search timeouts are essential** for test environments where test functions/aliases don't exist in config files

2. **Alias expansion must be explicit** at every level - setup(), bash -c commands, and subprocess calls

3. **Filter logic testing requires understanding** of how bash classifies different command types

4. **Circular detection should complete successfully** - we test the detection mechanism, not prevention of infinite loops

5. **Combined flag parsing** benefits from both positive (should work) and negative (should fail) test cases

6. **Performance tests in BATS** should rely on built-in timeouts rather than external timeout commands

7. **Subprocess source calls** need fallback patterns for both BATS and normal execution contexts

8. **Test command selection matters** - use commands that actually match the expected classification (builtin vs file vs function)

## Migration from Failed to Passing Tests

### Timeline of Fixes
1. **Timeout implementation** - Fixed hanging issues (51/72 → 51/72 but no hangs)
2. **Regex quote removal** - Fixed command filter tests (51/72 → 53/72)  
3. **Alias expansion addition** - Fixed alias tests (53/72 → 70/72)
4. **Test logic corrections** - Fixed edge cases (70/72 → 72/72)

### Final Test Success Pattern
All 72 tests now pass consistently with:
- Parallel execution (`-j 4`)
- Comprehensive coverage of all features
- No hanging or timeout issues
- Fast execution (under 30 seconds total)

The key insight: test environment isolation in BATS requires explicit setup of shell features (alias expansion) and careful handling of subprocess contexts that don't inherit the test environment.
