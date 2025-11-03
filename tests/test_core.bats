#!/usr/bin/env bats
# Core BATS tests for investigate.sh focusing on essential functionality

setup() {
    source "$BATS_TEST_DIRNAME/../investigate.sh"
}

# ===== CORE FUNCTIONALITY TESTS =====

@test "investigate function exists and is callable" {
    run i --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
}

@test "basic investigation works for builtin command" {
    run i cd
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Shell classification" ]]
    [[ "$output" =~ "builtin" ]]
}

@test "basic investigation works for external command" {
    run i ls
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Shell classification" ]]
}

@test "terminal detection prevents colors when piped" {
    run bash -c "source '$BATS_TEST_DIRNAME/../investigate.sh'; i ls | cat"
    [ "$status" -eq 0 ]
    # Should not contain ANSI escape sequences when piped
    ! [[ "$output" =~ $'\033\[' ]]
}

# ===== FLAG TESTS =====

@test "functions flag works with actual function" {
    run bash -c "source '$BATS_TEST_DIRNAME/../investigate.sh'; test_func() { echo test; }; i test_func --functions"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "functions flag rejects non-function" {
    run bash -c "source '$BATS_TEST_DIRNAME/../investigate.sh'; i ls --functions 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not a function" ]]
}

@test "variables flag works with variable" {
    run i PATH --variables
    [ "$status" -eq 0 ]
    [[ "$output" =~ "variable" ]]
}

@test "builtins flag works with builtin" {
    run i cd --builtins
    [ "$status" -eq 0 ]
    [[ "$output" =~ "builtin" ]]
}

@test "debug flag shows extra information" {
    run i ls --debug
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Shell classification" ]]
}

# ===== FLAG COMBINATIONS =====

@test "flags work in different orders: --debug --functions" {
    run bash -c "source '$BATS_TEST_DIRNAME/../investigate.sh'; test_func() { echo test; }; i test_func --debug --functions"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "flags work in different orders: --functions --debug" {
    run bash -c "source '$BATS_TEST_DIRNAME/../investigate.sh'; test_func() { echo test; }; i test_func --functions --debug"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "short and long flags are equivalent: -f vs --functions" {
    run bash -c "source '$BATS_TEST_DIRNAME/../investigate.sh'; test_func() { echo test; }; i test_func -f"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

# ===== ERROR HANDLING =====

@test "non-existent command shows error" {
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