#!/usr/bin/env sh
set -eu

run_check() {
    printf "Running %s...\n" "$1"
    nvim --headless -u NONE -i NONE -n "+lua dofile('$1')"
}

run_check "scripts/window_scope_check.lua"
run_check "scripts/window_scope_session_check.lua"
run_check "scripts/bufferline_integration_check.lua"
run_check "scripts/edit_mode_fold_check.lua"
run_check "scripts/pinned_session_test.lua"
run_check "scripts/pinned_edit_mode_test.lua"
run_check "scripts/pinned_pick_char_test.lua"

printf "All automated checks completed.\n"
