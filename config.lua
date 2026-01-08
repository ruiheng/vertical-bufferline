-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/config.lua
-- Configuration and constants for Buffer Nexus

local M = {}

-- UI Configuration
M.UI = {
    -- Sidebar dimensions
    DEFAULT_MIN_WIDTH = 15,  -- Minimum width for adaptive sizing
    DEFAULT_MAX_WIDTH = 60,  -- Maximum width for adaptive sizing


    -- Timing constants (in milliseconds)
    HIGHLIGHT_UPDATE_INTERVAL = 50,
    AUTO_SAVE_DELAY = 2000,
    STARTUP_DELAYS = {50, 200, 500},
    SESSION_LOAD_DELAY = 500,
    SESSION_ADDITIONAL_DELAY = 200,
    SESSION_FINAL_DELAY = 300,

    -- Tree display characters
    TREE_BRANCH = "├─ ",
    TREE_LAST = "└─ ",
    TREE_BRANCH_CURRENT = "├► ",  -- Current buffer tree branch
    TREE_LAST_CURRENT = "└► ",    -- Current buffer tree last
    TREE_EMPTY = "(empty)",
    CURRENT_BUFFER_MARKER = "► ",  -- Keep for backward compatibility
    PIN_MARKER = "📌 ",
    
    -- Active group tree characters (more prominent)
    ACTIVE_TREE_BRANCH = "┣━ ",      -- Thicker branch for active group
    ACTIVE_TREE_LAST = "┗━ ",        -- Thicker last for active group
    ACTIVE_TREE_BRANCH_CURRENT = "┣► ", -- Active group current buffer
    ACTIVE_TREE_LAST_CURRENT = "┗► ",   -- Active group current buffer last
    
    -- Path display formatting
    PATH_CONTINUATION = "│     ",  -- For tree visual continuity (inactive groups)
    ACTIVE_PATH_CONTINUATION = "┃     ",  -- For tree visual continuity (active group)
    PATH_PREFIX = "~/",
    PATH_MAX_LENGTH = 50,

    -- Group display
    ACTIVE_GROUP_MARKER = "••",        -- Double marker for more prominence
    INACTIVE_GROUP_MARKER = "◦",
    GROUP_SEPARATOR = "────────────────────────────────────",
    ACTIVE_GROUP_SEPARATOR = "════════════════════════════════════",  -- Different separator for active group
    UNNAMED_GROUP_DISPLAY = "(unnamed)",

    -- Horizontal layout labels
    HORIZONTAL_LABEL_HISTORY = "🕘",
    HORIZONTAL_LABEL_PINNED = "📌",
    HORIZONTAL_LABEL_FILES = "🗒",
    HORIZONTAL_LABEL_GROUPS = "🗂",
    VERTICAL_LABEL_RECENT = "🕘",
    VERTICAL_RECENT_TEXT = "Recent",
    VERTICAL_LABEL_PINNED = "📌",
    VERTICAL_PINNED_TEXT = "Pinned",
}

-- Color scheme (One Dark theme colors)
M.COLORS = {
    -- Primary colors
    BLUE = "#61afef",        -- Used for active groups, default group
    GREEN = "#98c379",       -- Used for group markers, default new group color
    YELLOW = "#e5c07b",      -- Used for modified buffers, warnings
    RED = "#e06c75",         -- Used for errors, pick highlights
    PURPLE = "#c678dd",      -- Used for group numbers
    GRAY = "#5c6370",        -- Used for inactive groups
    DARK_GRAY = "#3e4452",   -- Used for separators
    WHITE = "#abb2bf",       -- Used for active group text
    BLACK = "#282c34",       -- Used for Recent Files header text
    CYAN = "#56b6c2",        -- Used for Recent Files header background
}

-- Highlight group names
M.HIGHLIGHTS = {
    -- Buffer highlights
    CURRENT = "BufferNexusCurrent",
    VISIBLE = "BufferNexusVisible",
    MODIFIED = "BufferNexusModified",
    MODIFIED_CURRENT = "BufferNexusModifiedCurrent",
    PIN = "BufferNexusPin",
    PIN_CURRENT = "BufferNexusPinCurrent",
    INACTIVE = "BufferNexusInactive",
    ERROR = "BufferNexusError",
    WARNING = "BufferNexusWarning",
    BAR = "BufferNexusBar",
    PLACEHOLDER = "BufferNexusPlaceholder",

    -- Group highlights
    GROUP_ACTIVE = "BufferNexusGroupActive",
    GROUP_INACTIVE = "BufferNexusGroupInactive",
    GROUP_NUMBER = "BufferNexusGroupNumber",
    GROUP_SEPARATOR = "BufferNexusGroupSeparator",
    GROUP_MARKER = "BufferNexusGroupMarker",
    GROUP_TAB_ACTIVE = "BufferNexusGroupTabActive",
    GROUP_TAB_INACTIVE = "BufferNexusGroupTabInactive",
    SECTION_LABEL_ACTIVE = "BufferNexusSectionLabelActive",
    SECTION_LABEL_INACTIVE = "BufferNexusSectionLabelInactive",

    -- Recent Files highlights
    RECENT_FILES_HEADER = "BufferNexusRecentFilesHeader",

    -- Pick mode highlights
    PICK = "BufferNexusPick",
    PICK_VISIBLE = "BufferNexusPickVisible",
    PICK_SELECTED = "BufferNexusPickSelected",

    -- Path display highlights
    PATH = "BufferNexusPath",
    PATH_CURRENT = "BufferNexusPathCurrent",
    PATH_VISIBLE = "BufferNexusPathVisible",

    -- Filename-specific highlights for better distinction
    FILENAME = "BufferNexusFilename",
    FILENAME_CURRENT = "BufferNexusFilenameCurrent",
    FILENAME_VISIBLE = "BufferNexusFilenameVisible",
    FILENAME_FLASH = "BufferNexusFilenameFlash",

    -- Buffer numbering highlights (numbers shown before filenames)
    BUFFER_NUMBER = "BufferNexusBufferNumber",
    BUFFER_NUMBER_CURRENT = "BufferNexusBufferNumberCurrent",
    BUFFER_NUMBER_VISIBLE = "BufferNexusBufferNumberVisible",

    -- Prefix highlights for first-line minimal prefixes (different from full path)
    PREFIX = "BufferNexusPrefix",
    PREFIX_CURRENT = "BufferNexusPrefixCurrent",
    PREFIX_VISIBLE = "BufferNexusPrefixVisible",

    -- Dual numbering highlights for local|global format
    NUMBER_LOCAL = "BufferNexusNumberLocal",    -- Local position (for <leader>1 style)
    NUMBER_GLOBAL = "BufferNexusNumberGlobal",  -- Global position (for <leader>b1 style)
    NUMBER_SEPARATOR = "BufferNexusNumberSep",  -- The "|" separator
    NUMBER_SEPARATOR_CURRENT = "BufferNexusNumberSepCurrent",  -- "|" separator for current buffer line
    NUMBER_HIDDEN = "BufferNexusNumberHidden",  -- The "-" when not visible

    HORIZONTAL_NUMBER = "BufferNexusHorizontalNumber",
    HORIZONTAL_NUMBER_CURRENT = "BufferNexusHorizontalNumberCurrent",
    HORIZONTAL_CURRENT = "BufferNexusHorizontalCurrent",

    MENU_INPUT_PREFIX = "BufferNexusMenuInputPrefix",
}

-- Event names for autocmds
M.EVENTS = {
    GROUP_CREATED = "BufferNexusGroupCreated",
    GROUP_DELETED = "BufferNexusGroupDeleted",
    GROUP_RENAMED = "BufferNexusGroupRenamed",
    GROUP_CHANGED = "BufferNexusGroupChanged",
    GROUP_REORDERED = "BufferNexusGroupReordered",
    BUFFER_ADDED_TO_GROUP = "BufferNexusBufferAddedToGroup",
    BUFFER_REMOVED_FROM_GROUP = "BufferNexusBufferRemovedFromGroup",
    GROUP_BUFFERS_UPDATED = "BufferNexusGroupBuffersUpdated",
}

-- Default settings
M.DEFAULTS = {
    -- Group management
    auto_create_groups = true,
    auto_add_new_buffers = true,
    group_scope = "global",  -- "global" or "window" (window-scope disabled when bufferline is active)
    inherit_on_new_window = false,  -- Copy groups from previous window when creating a new window context
    buffer_filter = {
        filetypes = { "netrw" },
    },

    -- UI settings
    min_width = M.UI.DEFAULT_MIN_WIDTH,  -- Minimum width (adaptive sizing will use this as base)
    max_width = M.UI.DEFAULT_MAX_WIDTH,  -- Maximum width for adaptive sizing
    adaptive_width = true,  -- Enable adaptive width based on content
    min_height = 3,  -- Legacy: retained for compatibility (not used for top/bottom)
    max_height = 10,  -- Legacy: retained for compatibility (not used for top/bottom)
    show_inactive_group_buffers = false,  -- Show buffer list for inactive groups (default: only show active group)
    show_icons = false,  -- Show file type icons (emoji)
    pick_chars = "asdfjklghqwertyuiopzxcvbnmASDFJKLGHQWERTYUIOPZXCVBNM",  -- Pick hint characters (first char never numeric)
    position = "left",  -- Sidebar position: "left", "right", "top", "bottom"
    show_tree_lines = false,  -- Show tree-style connection lines
    floating = false,  -- Use floating window (right side, focusable=false) instead of split window
    
    -- History settings
    show_history = "auto",  -- "yes", "no", "auto" - show recent files history as unified group
    history_size = 10,      -- Maximum number of recent files to track per group
    history_auto_threshold = 6,  -- Minimum files needed for auto mode to show history
    history_auto_threshold_horizontal = 10,  -- Minimum files needed for auto mode (top/bottom)
    history_display_count = 7,  -- Maximum number of history items to display
    
    -- Path display settings
    show_path = "auto", -- "yes", "no", "auto"
    path_style = "relative", -- "relative", "absolute", "smart"
    path_max_length = M.UI.PATH_MAX_LENGTH,
    filename_max_length = 20,
    filename_ellipsis = "…",

    -- Cursor alignment settings
    align_with_cursor = true,  -- Align BN content with main window cursor position
    buffer_switch_flash_ms = 500,  -- Flash current filename on buffer switches (0 to disable)
    
    -- Session integration settings
    session = {
        -- mini.sessions integration
        mini_sessions_integration = true,
        
        -- Native mksession support
        auto_serialize = true,              -- Enable auto-serialization to global variable
        serialize_interval = 3000,          -- Serialization interval in milliseconds (3 seconds)
        optimize_serialize = true,          -- Only serialize when state actually changes
        auto_restore_prompt = true,         -- Show restore prompt when session data changes during source
        confirm_restore = true,             -- Ask for confirmation before restoring
        global_variable = "BufferNexusSession"  -- Global variable name for session data
    },

    -- Edit-mode settings
    edit_mode = {
        insert_path_key = "<C-p>",
        picker = "auto",
    },
}

-- Runtime settings (mutable)
M.settings = vim.deepcopy(M.DEFAULTS)

-- File extensions and icons mapping
M.ICONS = {
    lua = "🌙",
    js = "📝",
    py = "🐍",
    go = "🟢",
    rs = "🦀",
    md = "📝",
    txt = "📝",
    json = "📝",
    yaml = "📝",
    yml = "📝",
    -- Fallback
    default = "📝",
}

-- System constants
M.SYSTEM = {
    -- Buffer validation
    EMPTY_BUFTYPE = '',

    -- Position constants
    FIRST_INDEX = 1,
    ZERO_BASED_OFFSET = 1,

    -- Session version
    SESSION_VERSION = "1.0",
    SESSION_HASH_LENGTH = 16,

    -- Highlight constants
    HIGHLIGHT_START_COL = 0,
    HIGHLIGHT_END_COL = -1,
    GROUP_NUMBER_START = 1,
    GROUP_NUMBER_END = 4,
}

-- Validation functions
function M.validate_min_width(min_width)
    return type(min_width) == "number" and min_width > 0 and min_width <= 200
end

function M.validate_max_width(max_width)
    return type(max_width) == "number" and max_width > 0 and max_width <= 200
end

function M.validate_adaptive_width(adaptive_width)
    return type(adaptive_width) == "boolean"
end

function M.validate_min_height(min_height)
    return type(min_height) == "number" and min_height > 0 and min_height <= 50
end

function M.validate_max_height(max_height)
    return type(max_height) == "number" and max_height > 0 and max_height <= 50
end


function M.validate_color(color)
    return type(color) == "string" and color:match("^#%x%x%x%x%x%x$")
end

function M.validate_delay(delay)
    return type(delay) == "number" and delay >= 0 and delay <= 10000
end

function M.validate_show_path(show_path)
    return show_path == "yes" or show_path == "no" or show_path == "auto"
end

function M.validate_position(position)
    return position == "left" or position == "right" or position == "top" or position == "bottom"
end

function M.validate_show_history(show_history)
    return show_history == "yes" or show_history == "no" or show_history == "auto"
end

function M.validate_history_size(size)
    return type(size) == "number" and size > 0 and size <= 50
end

function M.validate_history_display_count(count)
    return type(count) == "number" and count > 0 and count <= 20
end

function M.validate_show_tree_lines(show_tree_lines)
    return type(show_tree_lines) == "boolean"
end

return M
