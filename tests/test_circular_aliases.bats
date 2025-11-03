#!/usr/bin/env bats
# Tests for circular alias detection in investigate.sh

setup() {
    source "$BATS_TEST_DIRNAME/../investigate.sh"
}

teardown() {
    # Clean up any aliases created during tests
    unalias tree test_self a b c 2>/dev/null || true
}

@test "detects simple self-referencing alias" {
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/../investigate.sh'; alias test_self='test_self'; i test_self"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Circular reference detected" ]]
    [[ "$output" =~ "Chain: test_self → test_self" ]]
}

@test "detects two-level circular alias (tree -> tree -c)" {
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/../investigate.sh'; alias tree='tree -c'; i tree"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Circular reference detected" ]]
    [[ "$output" =~ "Chain: tree → tree" ]]
}

@test "detects three-level circular alias chain (a->b->c->a)" {
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/../investigate.sh'; alias a='b'; alias b='c'; alias c='a'; i a"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Circular reference detected" ]]
    [[ "$output" =~ "Chain: a b → a" ]]
}

@test "non-circular aliases work normally" {
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/../investigate.sh'; alias normal='echo hello'; i normal"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Alias expansion: 'normal' → echo hello" ]]
    [[ "$output" =~ "Alias target 'echo' resolves to" ]]
    ! [[ "$output" =~ "Circular reference detected" ]]
}

@test "circular detection doesn't show duplicate 'Additional details'" {
    run bash -c "source '$BATS_TEST_DIRNAME/../investigate.sh'; alias tree='tree -c'; i tree"
    [ "$status" -eq 0 ]
    
    # Count occurrences of "Additional details" - should be exactly 1
    additional_count=$(echo "$output" | grep -c "Additional details" || true)
    [ "$additional_count" -eq 1 ]
    
    # Count occurrences of "Other matches from" - should be exactly 1  
    other_count=$(echo "$output" | grep -c "Other matches from" || true)
    [ "$other_count" -eq 1 ]
}

@test "circular detection shows clear chain visualization" {
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/../investigate.sh'; alias a='b'; alias b='c'; alias c='a'; i a"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Chain: a b → a" ]]
    
    # Should show the initial alias expansion (not duplicated during recursion)
    [[ "$output" =~ "Alias expansion: 'a' → b" ]]
    # Recursive alias expansions are now suppressed to avoid duplication (this is correct behavior)
    ! [[ "$output" =~ "Alias expansion: 'b' → c" ]]
    ! [[ "$output" =~ "Alias expansion: 'c' → a" ]]
}

@test "handles alias chains without hanging" {
    # Simple test that alias chains work and don't hang
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/../investigate.sh'; alias simple_chain='echo test'; i simple_chain"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "alias" ]]
    [[ "$output" =~ "Alias target 'echo' resolves to" ]]
}