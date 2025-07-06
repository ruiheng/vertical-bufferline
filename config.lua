-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/config.lua
-- Configuration and constants for vertical-bufferline

local M = {}

-- UI Configuration
M.UI = {
    -- Sidebar dimensions
    DEFAULT_WIDTH = 40,

    -- Display limits
    MAX_BUFFERS_PER_GROUP = 10,
    MAX_DISPLAY_NUMBER = 10,

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
    TREE_EMPTY = "(empty)",
    NUMBER_OVERFLOW_CHAR = "·",
    CURRENT_BUFFER_MARKER = "► ",
    
    -- Path display formatting
    PATH_CONTINUATION = "│     ",  -- For tree visual continuity
    PATH_PREFIX = "~/",
    PATH_MAX_LENGTH = 50,

    -- Group display
    ACTIVE_GROUP_MARKER = "●",
    INACTIVE_GROUP_MARKER = "○",
    GROUP_SEPARATOR = "────────────────────────────────────",
    UNNAMED_GROUP_DISPLAY = "(unnamed)",
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
}

-- Highlight group names
M.HIGHLIGHTS = {
    -- Buffer highlights
    CURRENT = "VBufferLineCurrent",
    VISIBLE = "VBufferLineVisible",
    MODIFIED = "VBufferLineModified",
    INACTIVE = "VBufferLineInactive",
    ERROR = "VBufferLineError",
    WARNING = "VBufferLineWarning",

    -- Group highlights
    GROUP_ACTIVE = "VBufferLineGroupActive",
    GROUP_INACTIVE = "VBufferLineGroupInactive",
    GROUP_NUMBER = "VBufferLineGroupNumber",
    GROUP_SEPARATOR = "VBufferLineGroupSeparator",
    GROUP_MARKER = "VBufferLineGroupMarker",

    -- Pick mode highlights
    PICK = "VBufferLinePick",
    PICK_VISIBLE = "VBufferLinePickVisible",
    PICK_SELECTED = "VBufferLinePickSelected",
    
    -- Path display highlights
    PATH = "VBufferLinePath",
    PATH_CURRENT = "VBufferLinePathCurrent",
    PATH_VISIBLE = "VBufferLinePathVisible",
    
    -- Filename-specific highlights for better distinction
    FILENAME = "VBufferLineFilename",
    FILENAME_CURRENT = "VBufferLineFilenameCurrent",
    FILENAME_VISIBLE = "VBufferLineFilenameVisible",
}

-- Event names for autocmds
M.EVENTS = {
    GROUP_CREATED = "VBufferLineGroupCreated",
    GROUP_DELETED = "VBufferLineGroupDeleted",
    GROUP_RENAMED = "VBufferLineGroupRenamed",
    GROUP_CHANGED = "VBufferLineGroupChanged",
    GROUP_REORDERED = "VBufferLineGroupReordered",
    BUFFER_ADDED_TO_GROUP = "VBufferLineBufferAddedToGroup",
    BUFFER_REMOVED_FROM_GROUP = "VBufferLineBufferRemovedFromGroup",
    GROUP_BUFFERS_UPDATED = "VBufferLineGroupBuffersUpdated",
}

-- Default settings
M.DEFAULTS = {
    -- Group management
    max_buffers_per_group = M.UI.MAX_BUFFERS_PER_GROUP,
    auto_create_groups = true,
    auto_add_new_buffers = true,

    -- Session management
    auto_save = false,
    auto_load = false,
    session_name_strategy = "cwd_hash", -- "cwd_hash" or "cwd_path" or "manual"

    -- UI settings
    width = M.UI.DEFAULT_WIDTH,
    expand_all_groups = true,
    
    -- Path display settings
    show_path = true,
    path_style = "relative", -- "relative", "absolute", "smart"
    path_max_length = M.UI.PATH_MAX_LENGTH,
}

-- File extensions and icons mapping
M.ICONS = {
    lua = "🌙",
    js = "📄",
    py = "🐍",
    go = "🟢",
    rs = "🦀",
    md = "📝",
    txt = "📄",
    json = "📋",
    yaml = "📋",
    yml = "📋",
    -- Fallback
    default = "📄",
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
function M.validate_width(width)
    return type(width) == "number" and width > 0 and width <= 200
end

function M.validate_color(color)
    return type(color) == "string" and color:match("^#%x%x%x%x%x%x$")
end

function M.validate_delay(delay)
    return type(delay) == "number" and delay >= 0 and delay <= 10000
end

return M