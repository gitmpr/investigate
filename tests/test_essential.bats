#!/usr/bin/env bats
# Essential tests for investigate.sh new features - optimized for speed

setup() {
    source "$BATS_TEST_DIRNAME/../investigate.sh"
    
    # Enable alias expansion for tests
    shopt -s expand_aliases
}

teardown() {
    unalias test_alias loop_alias dangerous_alias 2>/dev/null || true
}

# ===== CORE NEW FEATURES =====

@test "combined flags work: -bvf" {
    test_func() { echo "test"; }
    run i test_func -bvf
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
    unset -f test_func
}

@test "combined flags reject correctly: -bf on alias" {
    alias test_alias='echo test'
    run i test_alias -bf
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not a builtin" ]]
    [[ "$output" =~ "not a function" ]]
}

@test "alias source search works" {
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/../investigate.sh'; alias test_alias='echo hello'; i test_alias"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Searching for alias 'test_alias' definition" ]]
    [[ "$output" =~ "Alias expansion: 'test_alias' → echo hello" ]]
}

@test "circular alias detection works" {
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/../investigate.sh'; alias loop_alias='loop_alias'; i loop_alias"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Circular reference detected" ]]
    [[ "$output" =~ "Chain: loop_alias → loop_alias" ]]
}

@test "warning message is clear about PATH files" {
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/../investigate.sh'; alias tree='tree -c'; i tree" 2>/dev/null || skip "tree command not available"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "executable file in PATH" ]]
}

@test "dangerous alias safety works" {
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/../investigate.sh'; alias dangerous_alias='rm -rf \$HOME && echo done'; i dangerous_alias"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "shell operators" ]]
    [[ "$output" =~ "Skipping target analysis" ]]
}

@test "multiple rejection messages work" {
    run i ls -bfv
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not a builtin" ]]
    [[ "$output" =~ "not a function" ]]
    [[ "$output" =~ "not a variable" ]]
}

@test "mixed flags work with combined syntax" {
    test_func() { echo "test"; }
    run i test_func --debug -bf
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
    unset -f test_func
}

# ===== PERFORMANCE TEST =====

@test "large function doesn't hang" {
    # Create large function
    large_func() { 
        for i in {1..50}; do echo "line $i"; done
    }
    
    # Test that it doesn't hang (our timeout protection should work)
    run i large_func -f
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
    
    # Clean up
    unset -f large_func
}

# ===== REGRESSION TESTS =====

@test "basic investigation still works" {
    run i cd
    [ "$status" -eq 0 ]
    [[ "$output" =~ "builtin" ]]
}

@test "terminal detection still works" {
    run bash -c "source '$BATS_TEST_DIRNAME/../investigate.sh'; i ls | cat"
    [ "$status" -eq 0 ]
    # Should not contain ANSI escape sequences
    ! [[ "$output" =~ $'\033\[' ]]
}

@test "help still works" {
    run i --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}