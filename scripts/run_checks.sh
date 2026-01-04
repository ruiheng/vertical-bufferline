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
run_check "scripts/position_switch_cmdheight_check.lua"
run_check "scripts/basic_lifecycle_check.lua"
run_check "scripts/group_ops_check.lua"
run_check "scripts/history_behavior_check.lua"
run_check "scripts/global_scope_check.lua"
run_check "scripts/inherit_on_new_window_check.lua"
run_check "scripts/buffer_cleanup_check.lua"
run_check "scripts/align_with_cursor_check.lua"
run_check "scripts/path_display_check.lua"
run_check "scripts/floating_mode_check.lua"
run_check "scripts/edit_mode_roundtrip_check.lua"
run_check "scripts/edit_mode_unopened_file_test.lua"
run_check "scripts/edit_mode_new_file_flag_test.lua"
run_check "scripts/edit_mode_removed_buffer_focus_test.lua"
run_check "scripts/edit_mode_insert_keymap_test.lua"
run_check "scripts/edit_mode_picker_backends_test.lua"
run_check "scripts/pick_highlight_smoke_check.lua"
run_check "scripts/menu_pick_overflow_test.lua"
run_check "scripts/pick_char_variable_length_test.lua"
run_check "scripts/pick_extended_variable_length_test.lua"
run_check "scripts/pick_input_visual_feedback_test.lua"
run_check "scripts/pinned_session_test.lua"
run_check "scripts/pinned_edit_mode_test.lua"
run_check "scripts/pinned_pick_char_test.lua"

printf "All automated checks completed.\n"
