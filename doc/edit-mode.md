# Edit Mode (Design Notes)

This document describes a proposed "edit mode" that lets users batch-edit
buffer groups by editing a temporary text buffer and applying the result.

## Goals

- Allow bulk reordering of groups and buffers.
- Allow moving buffers between groups by reordering lines.
- Allow copying buffers to multiple groups by listing them multiple times.
- Support creating new groups by writing new group headers.
- Be forgiving: apply what can be parsed and report errors for the rest.

## User Flow

1. User runs a command (TBD) to open an editable buffer.
2. BN opens a new buffer (e.g. filetype `buffer-nexus-edit`).
3. The buffer contains a minimal, editable representation of groups plus brief
   header comments (e.g. current cwd and a short hint).
4. User edits the text using any Vim commands.
5. User applies with `:w`/`:wq`, or discards with `:q!`.
6. BN parses the buffer and updates group state.

## Format (Editable Buffer)

- Group header line:
  - `[Group] <name>`
  - Empty names are allowed: `[Group]`
  - Only a line starting with `[Group]` is treated as a header; paths containing `[` are fine.
  - Leading/trailing whitespace is trimmed from the group name (warn on trim).
- Buffer entry line:
  - A file path on its own line.
  - Absolute paths are the default.
  - Relative paths are allowed and are resolved against the current working directory.
- Optional flags can be appended in a bracket list: `path/to/file.lua [pin]` or `path/to/file.lua [pin=a]`
- Comment line:
  - Lines starting with `#` are comments and ignored.
  - If a real file path starts with `#`, use a relative path like `./#file` to avoid comment parsing.
- Blank lines are ignored.
- Lines outside any group are ignored but should be reported as warnings.

Example:
```
[Group] Frontend
/home/user/proj/src/App.tsx
/home/user/proj/src/Button.tsx

[Group] Backend
src/api/server.lua
```

## Semantics

- The edited buffer is the new source of truth.
- Reordering group headers changes group order.
- Reordering lines within a group changes buffer order in that group.
- A file listed in multiple groups is intentionally duplicated (copied) across groups.
- Omitting a file from a group removes it from that group.
- Unknown or missing files are skipped with warnings; other changes still apply.
- History is not shown or edited in this mode (it is derived state).
- If a buffer is modified and has no file on disk, it must still belong to some group.
- Any group entries not present in the edited buffer are removed from groups.
- Future extension: per-buffer flags (e.g. pin) can be stored in-line.

## Parsing Rules (Forgiving)

- Accept any amount of whitespace; trim leading/trailing whitespace.
- A group header must start with `[Group]` (exact match at line start).
- If a line looks like a group header but is malformed, report a warning and ignore it.
- If a buffer line cannot be resolved to a file, report a warning and skip it.
- Comment lines starting with `#` are ignored.
- Apply all valid groups and entries; do not abort the whole operation.
- Group names are trimmed; if trimming changes the name, warn and use the trimmed name.
- Flags in `[...]` are parsed; unknown flags are ignored with a warning.

## Edge Cases and Resolution Rules

- **Unlisted modified buffers**: Buffers with unsaved changes must be kept. If missing from the edit buffer, assign them to the first group.
- **Buffers without file paths**: Represent them using a buffer-number syntax (see below). If modified and missing, they are reassigned to the first group.
- **Terminal/help/quickfix**: Normally excluded, but if they appear in edit mode, treat them as buffer-number entries.
- **Duplicate entries within the same group**: Keep the first occurrence only.
- **Duplicate entries warning**: Warn when dropping duplicates in the same group.
- **Duplicate group names**: Auto-rename later groups by appending ` (2)`, ` (3)`, etc., and warn.
- **Empty groups**: Preserve empty groups.
- **Relative paths**: Resolve against the current working directory at apply time (if user `:cd` during edit).
- **Realpath normalization**: Canonicalize file paths (resolve symlinks) before matching.
- **History preservation**: Keep history where possible; drop entries that no longer belong to their group.
- **Apply focus**: Return focus to the buffer that was current before entering edit mode. If it exists in a group, set that group active. If it is a special buffer, just focus it.
- **Group membership vs buffer lifetime**: Removing a buffer from all groups does not close it; it just disappears from BN.

### Buffer-Number Entries

When a buffer has no file path, use a buffer-number entry:

```
[Group] Scratch
buf:12 [pin]  # quickfix
buf:13 [pin=a]  # stable pick char for pinned buffer
```

Rules:
- `buf:<number>` refers to a buffer by number.
- These entries are required for modified, no-file buffers and must not be dropped.
- If `buf:<number>` is missing from the edit buffer, it is reassigned to the first group.
- When generating the edit buffer, prefer file paths; only use `buf:<number>` for special/no-file buffers.

## Error Reporting

- Collect warnings with line numbers, show them after applying changes via simple messages (`:messages`).
- Examples:
  - "Line 12: buffer path not found: foo/bar.lua"
  - "Line 8: buffer entry outside any group"

## Edit Buffer Settings (Suggested)

- `buftype=acwrite` so `:w` triggers apply without writing a file.
- `swapfile=false`, `undofile=false` (ephemeral buffer).
- `bufhidden=wipe` so closing discards the temp buffer.
- `modifiable=true` during edit.
- `filetype=buffer-nexus-edit` for optional syntax highlighting.

## Proposed Command Name

- `:BNEdit` (opens the editable buffer)

## Group Definitions (Save/Load)

Add a way to persist group definitions and load them later.

Goals:
- Save the current grouping into a named file.
- Load a saved definition and apply it to the current session.
- Reuse the same editable format as edit mode.

Notes:
- Save should write only the grouping definition (not history).
- Load should follow the same parsing rules and error handling as edit mode.
- A simple start could be:
  - `:BNSaveGroups <path>`
  - `:BNLoadGroups <path>`
