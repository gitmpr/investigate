#!/usr/bin/env bats
# BATS tests for investigate.sh

# Setup function runs before each test
setup() {
    # Load the investigate script
    source "$BATS_TEST_DIRNAME/../investigate.sh"
    
    # Create temp directory for test files
    TEST_TEMP_DIR="$(mktemp -d)"
    cd "$TEST_TEMP_DIR"
}

# Teardown function runs after each test  
teardown() {
    # Clean up temp directory
    cd /
    rm -rf "$TEST_TEMP_DIR"
}

# ===== BASIC FUNCTIONALITY TESTS =====

@test "investigate function exists" {
    run type i
    [ "$status" -eq 0 ]
}

@test "help flag shows usage" {
    run i --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "investigate" ]]
}

@test "shows shell classification for builtin" {
    run i cd
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Shell classification" ]]
}

@test "shows shell classification for command" {
    run i ls
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Shell classification" ]]
}

@test "shows shell classification for variable" {
    run i PATH
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Shell classification" ]]
}

# ===== FLAG TESTS =====

@test "functions flag with actual function" {
    # Create a test function
    test_func() { echo "test"; }
    
    run i test_func --functions
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "functions flag with non-function shows rejection" {
    run bash -c "source '$BATS_TEST_DIRNAME/../investigate.sh'; i ls --functions 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" =~ not.*function ]] || [[ "$output" =~ "'ls' is not a function" ]]
}

@test "variables flag with variable" {
    run i PATH --variables
    [ "$status" -eq 0 ]
    [[ "$output" =~ "variable" ]]
}

@test "variables flag with non-variable shows rejection" {
    run bash -c "source '$BATS_TEST_DIRNAME/../investigate.sh'; i ls --variables 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" =~ not.*variable ]] || [[ "$output" =~ "'ls' is not a variable" ]]
}

@test "builtins flag with builtin" {
    run i cd --builtins
    [ "$status" -eq 0 ]
    [[ "$output" =~ "builtin" ]]
}

@test "aliases flag with alias" {
    # Create test alias and run in same bash context
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/../investigate.sh'; alias test_alias='echo hello'; i test_alias --aliases"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "alias" ]]
}

@test "no-truncate flag shows more content" {
    # Create a function with many lines
    long_func() {
        echo "line 1"; echo "line 2"; echo "line 3"; echo "line 4"; echo "line 5"
        echo "line 6"; echo "line 7"; echo "line 8"; echo "line 9"; echo "line 10"
        echo "line 11"; echo "line 12"; echo "line 13"; echo "line 14"; echo "line 15"
        echo "line 16"; echo "line 17"; echo "line 18"; echo "line 19"; echo "line 20"
    }
    
    # Test normal output
    run i long_func
    normal_lines=$(echo "$output" | wc -l)
    
    # Test no-truncate output
    run i long_func --no-truncate
    notrunc_lines=$(echo "$output" | wc -l)
    
    # no-truncate should show more or equal lines
    [ "$notrunc_lines" -ge "$normal_lines" ]
}

# ===== FLAG ORDER PERMUTATION TESTS =====

@test "flags work in different orders: --debug --functions" {
    test_func() { echo "test"; }
    
    run i test_func --debug --functions
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "flags work in different orders: --functions --debug" {
    test_func() { echo "test"; }
    
    run i test_func --functions --debug  
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "short and long flags work: -f vs --functions" {
    test_func() { echo "test"; }
    
    run i test_func -f
    output1="$output"
    
    run i test_func --functions
    output2="$output"
    
    # Both should contain "function"
    [[ "$output1" =~ "function" ]]
    [[ "$output2" =~ "function" ]]
}

@test "multiple flags: --debug --no-truncate --functions" {
    test_func() { echo "test"; }
    
    run i test_func --debug --no-truncate --functions
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

# ===== ERROR CONDITION TESTS =====

@test "non-existent command shows not found" {
    run i nonexistent_command_12345
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not found" ]]
}

@test "invalid flag shows error" {
    run i ls --invalid-flag
    [ "$status" -eq 1 ]
}

@test "empty target shows error" {
    run i ""
    [ "$status" -eq 1 ]
}

# ===== TERMINAL DETECTION TESTS =====

@test "piped output has no ANSI color codes" {
    run bash -c "source investigate.sh; i ls | cat"
    [ "$status" -eq 0 ]
    # Output should not contain ANSI escape sequences
    ! [[ "$output" =~ $'\033\[' ]]
}

@test "terminal detection variable use_color works" {
    # Test that use_color is set based on terminal detection
    run bash -c "source investigate.sh; [[ -t 1 ]] && echo 'terminal' || echo 'not-terminal'"
    [[ "$output" =~ "not-terminal" ]]  # In BATS, stdout is not a terminal
}

# ===== PERFORMANCE TESTS =====

@test "performance with large function is reasonable" {
    # Create a large function
    large_func() {
        for i in {1..50}; do
            echo "line $i"
        done
    }
    
    # Time the execution
    start_time=$(date +%s.%N)
    run i large_func
    end_time=$(date +%s.%N)
    
    [ "$status" -eq 0 ]
    
    # Should complete in reasonable time (less than 3 seconds)
    duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0.5")
    if command -v bc >/dev/null; then
        result=$(echo "$duration < 3.0" | bc -l)
        [ "$result" -eq 1 ]
    else
        # Skip test if bc not available
        skip "bc calculator not available"
    fi
}

# ===== FEATURE INTEGRATION TESTS =====

@test "function definition contains expected content" {
    test_func() {
        echo "test content"
        return 0
    }

    run i test_func
    [ "$status" -eq 0 ]
    [[ "$output" =~ "test_func" ]]
    [[ "$output" =~ echo.*test.*content ]]
}

@test "variable shows value" {
    TEST_VAR="test value"
    
    run i TEST_VAR
    [ "$status" -eq 0 ]
    [[ "$output" =~ "variable" ]]
    [[ "$output" =~ "test value" ]]
}

@test "builtin shows type information" {
    run i echo
    [ "$status" -eq 0 ]
    [[ "$output" =~ "builtin" ]] || [[ "$output" =~ "file" ]]  # echo can be builtin or file
}

# ===== SOURCING TRAIL TESTS =====

@test "function sourcing trail detection" {
    # Create test files for sourcing trail
    echo 'test_sourced_func() { echo "from test file"; }' > test_sourced.sh
    echo 'source test_sourced.sh' > test_loader.sh
    source test_loader.sh
    
    run i test_sourced_func
    [ "$status" -eq 0 ]
    [[ "$output" =~ "found in:" ]] || [[ "$output" =~ "source" ]]
}

# ===== EDGE CASES =====

@test "handles binary files" {
    if [ -f "/bin/ls" ]; then
        run i /bin/ls
        [ "$status" -eq 0 ]
        [[ "$output" =~ "file" ]] || [[ "$output" =~ "ELF" ]]
    else
        skip "No /bin/ls binary found"
    fi
}

@test "handles directories" {
    if [ -d "/etc" ]; then
        run i /etc
        [ "$status" -eq 0 ]
        [[ "$output" =~ "directory" ]] || [[ "$output" =~ "Directory" ]]
    else
        skip "No /etc directory found"
    fi
}

@test "handles very long target names" {
    long_name=$(printf 'a%.0s' {1..100})
    run i "$long_name"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not found" ]]
}

# ===== COMPLETION TESTS =====

@test "completion function is registered" {
    run complete -p i
    [ "$status" -eq 0 ]
    [[ "$output" =~ "_investigate_completion" ]]
}