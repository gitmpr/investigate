#!/usr/bin/env bats
# BATS tests specifically for flag combinations and order

setup() {
    source "$BATS_TEST_DIRNAME/../investigate.sh"
    
    # Enable alias expansion for tests
    shopt -s expand_aliases
    
    # Create test function for consistent testing
    test_function() { echo "test function content"; }
    
    # Create test alias
    alias test_alias='echo "test alias"'
    
    # Create test variable
    TEST_VAR="test variable value"
}

teardown() {
    unset -f test_function 2>/dev/null || true
    unalias test_alias 2>/dev/null || true
    unset TEST_VAR 2>/dev/null || true
}

# ===== INDIVIDUAL FLAG TESTS =====

@test "--functions flag filters correctly" {
    run i test_function --functions
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
    
    run i ls --functions  
    [[ "$output" =~ "not.*function" ]] || [[ "$status" -eq 1 ]]
}

@test "-f short flag works same as --functions" {
    run i test_function -f
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "--variables flag filters correctly" {
    run i TEST_VAR --variables
    [ "$status" -eq 0 ]
    [[ "$output" =~ "variable" ]]
    
    run i ls --variables
    [[ "$output" =~ "not.*variable" ]] || [[ "$status" -eq 1 ]]
}

@test "-v short flag works same as --variables" {
    run i TEST_VAR -v
    [ "$status" -eq 0 ]
    [[ "$output" =~ "variable" ]]
}

@test "--aliases flag filters correctly" {
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/../investigate.sh'; alias test_alias='echo \"test alias\"'; i test_alias --aliases"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "alias" ]]
    
    run bash -c "source '$BATS_TEST_DIRNAME/../investigate.sh'; i ls --aliases"
    [[ "$output" =~ "not.*alias" ]] || [[ "$status" -eq 1 ]]
}

@test "-a short flag works same as --aliases" {
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/../investigate.sh'; alias test_alias='echo \"test alias\"'; i test_alias -a"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "alias" ]]
}

@test "--builtins flag filters correctly" {
    run i cd --builtins
    [ "$status" -eq 0 ]
    [[ "$output" =~ "builtin" ]]
    
    run i test_function --builtins
    [[ "$output" =~ "not.*builtin" ]] || [[ "$status" -eq 1 ]]
}

@test "-b short flag works same as --builtins" {
    run i cd -b
    [ "$status" -eq 0 ]
    [[ "$output" =~ "builtin" ]]
}

@test "--commands flag filters correctly" {
    run i ls --commands
    [ "$status" -eq 0 ]
    [[ "$output" =~ command|file ]]
    
    run i test_function --commands
    [[ "$output" =~ "not.*command" ]] || [[ "$status" -eq 1 ]]
}

@test "-c short flag works same as --commands" {
    run i ls -c
    [ "$status" -eq 0 ]
    [[ "$output" =~ command|file ]]
}

@test "--files flag filters correctly" {
    if [ -f "/bin/ls" ]; then
        run i /bin/ls --files
        [ "$status" -eq 0 ]
        [[ "$output" =~ "file" ]]
    fi
    
    run i test_function --files
    [[ "$output" =~ "not.*file" ]] || [[ "$status" -eq 1 ]]
}

@test "--debug flag shows verbose output" {
    run i test_function --debug
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Shell classification" ]]
}

@test "--no-truncate flag shows full content" {
    # Create function with many lines
    long_func() { 
        echo "line 1"; echo "line 2"; echo "line 3"; echo "line 4"; echo "line 5"
        echo "line 6"; echo "line 7"; echo "line 8"; echo "line 9"; echo "line 10"
        echo "line 11"; echo "line 12"; echo "line 13"; echo "line 14"; echo "line 15"
        echo "line 16"; echo "line 17"; echo "line 18"; echo "line 19"; echo "line 20"
    }
    
    run i long_func --no-truncate
    [ "$status" -eq 0 ]
    # Should show all lines, not truncated
    [[ "$output" =~ "line 20" ]]
}

@test "-n short flag works same as --no-truncate" {
    long_func() { 
        echo "line 1"; echo "line 2"; echo "line 3"; echo "line 4"; echo "line 5"
        echo "line 16"; echo "line 17"; echo "line 18"; echo "line 19"; echo "line 20"
    }
    
    run i long_func -n
    [ "$status" -eq 0 ]
    [[ "$output" =~ "line 20" ]]
}

# ===== FLAG ORDER COMBINATION TESTS =====

@test "flags work in order: --debug --functions" {
    run i test_function --debug --functions
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "flags work in order: --functions --debug" {
    run i test_function --functions --debug
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "flags work in order: -f --debug" {
    run i test_function -f --debug
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "flags work in order: --debug -f" {
    run i test_function --debug -f
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "flags work in order: --no-truncate --functions" {
    run i test_function --no-truncate --functions
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "flags work in order: --functions --no-truncate" {
    run i test_function --functions --no-truncate
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "flags work in order: -n -f" {
    run i test_function -n -f
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "flags work in order: -f -n" {
    run i test_function -f -n
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "three flags work: --debug --no-truncate --functions" {
    run i test_function --debug --no-truncate --functions
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "three flags work: --functions --debug --no-truncate" {
    run i test_function --functions --debug --no-truncate
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "three flags work: -f --debug -n" {
    run i test_function -f --debug -n
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "three flags work: -n -f --debug" {
    run i test_function -n -f --debug
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

# ===== MIXED FLAG TYPE TESTS =====

@test "mixed short and long flags: -v --debug" {
    run i TEST_VAR -v --debug
    [ "$status" -eq 0 ]
    [[ "$output" =~ "variable" ]]
}

@test "mixed short and long flags: --variables -n" {
    run i TEST_VAR --variables -n
    [ "$status" -eq 0 ]
    [[ "$output" =~ "variable" ]]
}

@test "all short flags: -f -v -a -b -c -n" {
    # Test with function (should only match -f)
    run i test_function -f -n
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

# ===== CONFLICTING FLAGS TESTS =====

@test "conflicting filters: --functions --variables (function wins)" {
    run i test_function --functions --variables
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "conflicting filters: --variables --functions (variable target)" {
    run i TEST_VAR --variables --functions
    [ "$status" -eq 0 ]
    [[ "$output" =~ "variable" ]]
}

# ===== ERROR HANDLING WITH FLAGS =====

@test "invalid flag shows error" {
    run i test_function --invalid-flag
    [ "$status" -ne 0 ]
}

@test "flag without target shows usage" {
    run i --functions
    [ "$status" -ne 0 ]
}

@test "empty target with flags shows error" {
    run i "" --functions
    [ "$status" -ne 0 ]
}

# ===== COMBINED FLAG SYNTAX TESTS =====

@test "combined flags -bvf works" {
    run i test_function -bvf
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "combined flags -av works for aliases" {
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/../investigate.sh'; alias test_alias='echo \"test alias\"'; i test_alias -av"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "alias" ]]
}

@test "combined flags -bf rejects non-matching types" {
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/../investigate.sh'; alias test_alias='echo \"test alias\"'; i test_alias -bf"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not a builtin" ]]
    [[ "$output" =~ "not a function" ]]
}

@test "combined flags -bv rejects files" {
    run i ls -bv
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not a builtin" ]]
    [[ "$output" =~ "not a variable" ]]
}

@test "combined flags -fv matches functions" {
    run i test_function -fv
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "combined flags -abc expands correctly" {
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/../investigate.sh'; alias test_alias='echo \"test alias\"'; i test_alias -ac"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "alias" ]]
}

@test "long combined flags -abcfv work" {
    run bash -c "shopt -s expand_aliases; source '$BATS_TEST_DIRNAME/../investigate.sh'; alias test_alias='echo \"test alias\"'; i test_alias -abcfv"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "alias" ]]
}

@test "combined flags preserve individual behavior" {
    run i ls -f
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not a function" ]]
    
    run i grep -b
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not a builtin" ]]
}

@test "multiple filters show all rejection messages" {
    run i ls -bfv
    [ "$status" -eq 1 ]
    [[ "$output" =~ "not a builtin" ]]
    [[ "$output" =~ "not a function" ]]
    [[ "$output" =~ "not a variable" ]]
}

@test "combined flags with one match succeeds" {
    run i cd -bf  # cd is a builtin
    [ "$status" -eq 0 ]
    [[ "$output" =~ "builtin" ]]
}

@test "keyword matches builtin filter in combined flags" {
    run i if -b
    [ "$status" -eq 0 ]
    [[ "$output" =~ "keyword" ]]
}

@test "mixed long and short flags work with combined" {
    run i test_function --debug -bf
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "combined flags work with variables" {
    run i TEST_VAR -vf
    [ "$status" -eq 0 ]
    [[ "$output" =~ "variable" ]]
}

@test "combined flags work with no-truncate" {
    run i test_function -fn
    [ "$status" -eq 0 ]
    [[ "$output" =~ "function" ]]
}

@test "invalid combined flag characters show error" {
    run i test_function -xyz
    [ "$status" -ne 0 ]
}

# ===== ALIAS SOURCE SEARCHING TESTS =====

@test "alias shows source search attempt" {
    run i test_alias
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Searching for alias 'test_alias' definition source file" ]]
    [[ "$output" =~ "Alias expansion: 'test_alias' → echo \"test alias\"" ]]
}

@test "alias with shell operators shows safety message" {
    alias dangerous='rm -rf $HOME && echo done'
    run i dangerous
    [ "$status" -eq 0 ]
    [[ "$output" =~ "shell operators" ]]
    [[ "$output" =~ "Skipping target analysis" ]]
    unalias dangerous
}

@test "circular alias shows source search" {
    alias loop_test='loop_test'
    run i loop_test
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Searching for alias 'loop_test' definition source file" ]]
    [[ "$output" =~ "Circular reference detected" ]]
    unalias loop_test
}

@test "combined flags handle circular aliases correctly" {
    alias loop_test2='loop_test2'
    run i loop_test2 -af
    [ "$status" -eq 0 ]
    [[ "$output" =~ "alias" ]]
    [[ "$output" =~ "Circular reference detected" ]]
    unalias loop_test2
}
