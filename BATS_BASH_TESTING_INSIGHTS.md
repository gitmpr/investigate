# BATS Bash Testing Insights: Lessons Learned

This document captures hard-won lessons from debugging complex BATS test failures in bash environments.

## Core BATS Environment Understanding

### The Subprocess Problem
BATS runs each test in isolated subprocesses, which creates several gotchas:

- **Functions defined in tests don't persist** across `run` commands
- **Aliases require explicit expansion** with `shopt -s expand_aliases`
- **Environment variables** may not propagate as expected
- **Working directory** can change between setup/test/teardown

### Critical Setup Patterns

```bash
setup() {
    source "$BATS_TEST_DIRNAME/script.sh"
    
    # ALWAYS enable alias expansion for any alias testing
    shopt -s expand_aliases
    
    # Define test functions here, not in individual tests
    test_function() { echo "test content"; }
    
    # Define test aliases here
    alias test_alias='echo "test alias"'
}
```

## Alias Testing Challenges

### The Alias Expansion Problem
**Symptom**: Tests fail with "'alias_name' not found" even though alias is defined
**Root Cause**: Non-interactive shells don't expand aliases by default

**Solution**: Add `shopt -s expand_aliases` to:
1. `setup()` function for tests using direct `run` commands
2. Every `bash -c "..."` command that uses aliases

```bash
# ❌ WRONG - alias won't work
run bash -c "source script.sh; alias test='echo hi'; command_using_test"

# ✅ CORRECT - alias expansion enabled
run bash -c "shopt -s expand_aliases; source script.sh; alias test='echo hi'; command_using_test"
```

### Alias Persistence
Aliases defined in `setup()` are available to direct `run` commands but NOT to `bash -c` subshells.

```bash
setup() {
    shopt -s expand_aliases
    alias myalias='echo test'
}

@test "alias usage" {
    # ✅ This works - uses setup's alias
    run mycommand_that_uses myalias
    
    # ❌ This fails - new bash subprocess doesn't have alias
    run bash -c "mycommand_that_uses myalias"
    
    # ✅ This works - alias redefined in subshell
    run bash -c "shopt -s expand_aliases; alias myalias='echo test'; mycommand_that_uses myalias"
}
```

## Regex Pattern Matching Pitfalls

### Quoted vs Unquoted Patterns
**Critical**: Bash regex patterns in `[[ ]]` should NOT be quoted

```bash
# ❌ WRONG - quotes prevent regex interpretation
[[ "$output" =~ "pattern|alternative" ]]

# ✅ CORRECT - unquoted allows regex
[[ "$output" =~ pattern|alternative ]]

# ✅ ALSO CORRECT - parentheses for grouping
[[ "$output" =~ (pattern|alternative) ]]
```

### Complex Pattern Debugging
When regex fails mysteriously:

```bash
@test "debug regex" {
    run some_command
    echo "Status: $status" >&3      # Debug to stderr
    echo "Output: $output" >&3      # See actual output
    echo "Length: ${#output}" >&3   # Check for empty output
    [[ "$output" =~ expected_pattern ]]
}
```

## Timeout and Hanging Issues

### The Subprocess Timeout Problem
**Symptom**: Tests hang indefinitely during file searches or complex operations
**Root Cause**: BATS can't interrupt hung subprocesses easily

**Solutions**:
1. **Built-in timeouts** in the script itself (preferred)
2. **External timeout** with careful process management
3. **Avoid complex operations** in test environment

```bash
# ❌ PROBLEMATIC - timeout runs in different process context
run timeout 10s complex_bash_function

# ✅ BETTER - timeout built into the function
complex_bash_function() {
    if command -v timeout >/dev/null; then
        timeout 3s actual_work || echo "TIMEOUT"
    else
        actual_work
    fi
}
```

### Function Source Search Hangs
Test-defined functions won't be found in config files, causing long searches:

```bash
# ❌ PROBLEMATIC - will search entire filesystem
@test "test function behavior" {
    test_func() { echo "test"; }
    run investigate_script test_func  # Will hang searching for source
}

# ✅ SOLUTION - add timeout protection to investigate script
find_function_source() {
    if command -v timeout >/dev/null; then
        timeout 3s actual_search || echo "TIMEOUT"
    else
        actual_search
    fi
}
```

## Exit Status Patterns

### Multiple Command Testing
When testing commands that should fail:

```bash
@test "command rejection" {
    run command_with_filters
    
    # Test for specific failure conditions
    [ "$status" -eq 1 ]  # Should fail
    [[ "$output" =~ "not a function" ]]
    
    # Alternative pattern for flexible status
    [[ "$output" =~ "not a function" ]] || [[ "$status" -eq 1 ]]
}
```

### Command Classification Issues
Ensure test expectations match reality:

```bash
# ❌ WRONG - 'echo' IS a builtin, test expects failure
run investigate echo --builtins
[ "$status" -eq 1 ]  # This will fail because echo IS a builtin

# ✅ CORRECT - use command that's NOT a builtin
run investigate grep --builtins  
[ "$status" -eq 1 ]  # This succeeds because grep is NOT a builtin
```

## Parallel Execution Considerations

### BATS Parallel Flags
```bash
# Faster test execution
bats -j 4 test_file.bats

# But beware of shared resource conflicts
# - Temporary files with same names
# - Shared environment variables
# - Process conflicts
```

### Resource Isolation
```bash
setup() {
    # Use test-specific temp directories
    export TEST_TEMP_DIR="$(mktemp -d)"
    export TEST_PID="$$"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}
```

## Debug Strategies

### BATS Debug Output
```bash
@test "debug failing test" {
    run problem_command
    echo "Status: $status" >&3
    echo "Output: $output" >&3
    echo "Expected pattern: expected_text" >&3
    
    # Your actual test
    [ "$status" -eq 0 ]
    [[ "$output" =~ expected_text ]]
}
```

### Incremental Test Development
1. **Start simple** - test basic functionality first
2. **Add complexity gradually** - one feature per test
3. **Isolate failures** - create minimal reproduction tests
4. **Test the test** - manually verify expected behavior

### Common Debugging Commands
```bash
# Check what's actually in output
echo "$output" | cat -A  # Show hidden characters

# Test regex patterns manually
echo "test string" | grep -E "pattern|alternative"

# Verify command availability
command -v timeout >/dev/null && echo "available"

# Check alias expansion
bash -c "shopt -s expand_aliases; alias; type aliasname"
```

## Performance Optimization

### Test Organization
- **Group related tests** in the same file
- **Use focused test suites** for development
- **Separate slow tests** from fast ones

```bash
# Fast tests for development
bats test_essential.bats

# Full suite for CI
bats test_*.bats
```

### Avoid Expensive Operations
- **Don't test actual file searches** in unit tests
- **Mock expensive operations** when possible
- **Use smaller test data** sets

## Key Takeaways

1. **Alias expansion is not automatic** in non-interactive shells
2. **Regex patterns must be unquoted** in bash conditionals  
3. **Timeouts are tricky** in subprocess environments
4. **Test what you expect** - verify commands behave as assumed
5. **Debug incrementally** - start simple, add complexity
6. **Use parallel execution** but watch for resource conflicts
7. **Subprocess isolation** means functions/aliases don't persist across `run` commands

The most common cause of mysterious test failures is the subprocess isolation that BATS provides for safety - understanding this is key to successful bash testing.
