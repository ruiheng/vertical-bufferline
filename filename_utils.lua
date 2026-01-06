-- /home/ruiheng/config_files/nvim/lua/vertical-bufferline/filename_utils.lua
-- Smart filename disambiguation utilities

local M = {}

-- Split path into components
local function split_path(path)
    local parts = {}
    for part in string.gmatch(path, "[^/\\]+") do
        table.insert(parts, part)
    end
    return parts
end

-- Get the minimal unique suffix for a set of paths
local function get_unique_suffix(paths)
    if #paths <= 1 then
        return paths
    end

    local path_parts = {}
    local max_depth = 0

    -- Split all paths into components
    for i, path in ipairs(paths) do
        local parts = split_path(path)
        path_parts[i] = parts
        max_depth = math.max(max_depth, #parts)
    end

    local unique_names = {}

    for i = 1, #paths do
        local parts = path_parts[i]
        local filename = parts[#parts] or ""

        -- Start with just the filename
        local suffix_parts = {filename}
        local depth = 1

        -- Check if this name conflicts with others
        local is_unique = false
        while not is_unique and depth < #parts do
            local current_name = table.concat(suffix_parts, "/")
            is_unique = true

            -- Check against all other paths
            for j = 1, #paths do
                if i ~= j then
                    local other_parts = path_parts[j]
                    local other_suffix = {}

                    -- Build the same depth suffix for comparison
                    for k = math.max(1, #other_parts - depth + 1), #other_parts do
                        table.insert(other_suffix, other_parts[k])
                    end

                    local other_name = table.concat(other_suffix, "/")

                    if current_name == other_name then
                        is_unique = false
                        break
                    end
                end
            end

            -- If not unique, add more parent directory context
            if not is_unique and depth < #parts then
                depth = depth + 1
                local parent_idx = #parts - depth + 1
                if parent_idx > 0 then
                    table.insert(suffix_parts, 1, parts[parent_idx])
                end
            end
        end

        unique_names[i] = table.concat(suffix_parts, "/")
    end

    return unique_names
end

-- Generate unique display names for a group of buffers
function M.generate_unique_names(buffer_list)
    if not buffer_list or #buffer_list == 0 then
        return {}
    end

    -- Add error handling for invalid input
    if type(buffer_list) ~= "table" then
        vim.notify("generate_unique_names: buffer_list must be a table", vim.log.levels.ERROR)
        return {}
    end

    -- Group buffers by their base filename
    local filename_groups = {}
    local buffer_paths = {}

    for _, buffer_info in ipairs(buffer_list) do
        local buffer_id = nil
        local path = ""

        -- Handle different input types with error protection
        if type(buffer_info) == "number" then
            -- Direct buffer ID
            buffer_id = buffer_info
            local success, is_valid = pcall(vim.api.nvim_buf_is_valid, buffer_id)
            if success and is_valid then
                local name_success, name = pcall(vim.api.nvim_buf_get_name, buffer_id)
                if name_success then
                    path = name
                end
            end
        elseif type(buffer_info) == "table" then
            -- Buffer info object
            buffer_id = buffer_info.id
            if buffer_info.name and type(buffer_info.name) == "string" then
                -- Use provided name
                path = buffer_info.name
            elseif buffer_id then
                local success, is_valid = pcall(vim.api.nvim_buf_is_valid, buffer_id)
                if success and is_valid then
                    local name_success, name = pcall(vim.api.nvim_buf_get_name, buffer_id)
                    if name_success then
                        path = name
                    end
                end
            end
        end

        if path ~= "" then
            local filename = vim.fn.fnamemodify(path, ":t")

            if not filename_groups[filename] then
                filename_groups[filename] = {}
            end

            table.insert(filename_groups[filename], {
                index = #buffer_paths + 1,
                path = path,
                buffer_info = buffer_info
            })

            table.insert(buffer_paths, path)
        else
            -- For buffers without valid paths, use a fallback
            table.insert(buffer_paths, "[No Name]")
        end
    end

    local unique_names = {}

    -- Process each filename group
    for filename, group in pairs(filename_groups) do
        if #group == 1 then
            -- No conflict, use simple filename
            local item = group[1]
            unique_names[item.index] = filename
        else
            -- Multiple files with same name, need disambiguation
            local paths_in_group = {}
            local indices = {}

            for _, item in ipairs(group) do
                table.insert(paths_in_group, item.path)
                table.insert(indices, item.index)
            end

            local disambiguated = get_unique_suffix(paths_in_group)

            for i, unique_name in ipairs(disambiguated) do
                unique_names[indices[i]] = unique_name
            end
        end
    end

    -- Fill in any missing entries (for buffers without valid paths)
    for i = 1, #buffer_paths do
        if not unique_names[i] then
            if buffer_paths[i] == "[No Name]" then
                unique_names[i] = "[No Name]"
            else
                unique_names[i] = vim.fn.fnamemodify(buffer_paths[i], ":t")
            end
        end
    end

    return unique_names
end

-- Get unique name for a single buffer in context of other buffers
function M.get_unique_name_for_buffer(target_buffer_id, context_buffers)
    -- Input validation
    if type(target_buffer_id) ~= "number" then
        return "[Invalid Buffer ID]"
    end

    local buffer_list = {}
    local target_index = nil

    -- Add target buffer to list
    table.insert(buffer_list, target_buffer_id)
    target_index = 1

    -- Add context buffers with validation
    if context_buffers and type(context_buffers) == "table" then
        for _, buf_id in ipairs(context_buffers) do
            if type(buf_id) == "number" and buf_id ~= target_buffer_id then
                table.insert(buffer_list, buf_id)
            end
        end
    end

    local unique_names = M.generate_unique_names(buffer_list)
    if unique_names and unique_names[target_index] then
        return unique_names[target_index]
    else
        -- Fallback with error protection
        local success, is_valid = pcall(vim.api.nvim_buf_is_valid, target_buffer_id)
        if success and is_valid then
            local name_success, path = pcall(vim.api.nvim_buf_get_name, target_buffer_id)
            if name_success and path ~= "" then
                return vim.fn.fnamemodify(path, ":t")
            end
        end
        return "[No Name]"
    end
end

-- Helper function to get smart display name for buffer
function M.get_smart_buffer_name(buffer_id, all_group_buffers)
    -- Add error checking for input parameters
    if type(buffer_id) ~= "number" then
        return "[Invalid Buffer ID]"
    end

    local success, is_valid = pcall(vim.api.nvim_buf_is_valid, buffer_id)
    if not success or not is_valid then
        return "[Invalid]"
    end

    local name_success, path = pcall(vim.api.nvim_buf_get_name, buffer_id)
    if not name_success or path == "" then
        return "[No Name]"
    end

    -- If we have context of other buffers, use smart disambiguation
    if all_group_buffers and type(all_group_buffers) == "table" and #all_group_buffers > 1 then
        local unique_name = M.get_unique_name_for_buffer(buffer_id, all_group_buffers)
        return unique_name or vim.fn.fnamemodify(path, ":t")
    else
        -- Fallback to simple filename
        return vim.fn.fnamemodify(path, ":t")
    end
end

-- Find the minimal prefix that distinguishes current_dir from all conflicting_dirs
local function find_minimal_distinguishing_prefix(current_dir, conflicting_dirs, available_width)
    if current_dir == "" or current_dir == "." then
        return ""
    end

    local current_parts = split_path(current_dir)
    if #current_parts == 0 then
        return ""
    end

    -- Get the last directory component
    local target_part = current_parts[#current_parts]

    -- If we have enough space for the full name, use it (unless there are true conflicts)
    available_width = available_width or 20  -- default fallback
    if #target_part + 1 <= available_width then  -- +1 for the "/"
        -- Check if there are actual conflicts that require abbreviation
        local has_real_conflicts = false
        for _, conflict_dir in ipairs(conflicting_dirs) do
            local conflict_parts = split_path(conflict_dir)
            if #conflict_parts > 0 then
                local conflict_part = conflict_parts[#conflict_parts]
                if conflict_part == target_part then
                    has_real_conflicts = true
                    break
                end
            end
        end

        -- If no real conflicts (different directory names), use full name
        if not has_real_conflicts then
            return target_part
        end
    end

    -- Collect all conflicting last parts
    local conflicting_parts = {}
    for _, conflict_dir in ipairs(conflicting_dirs) do
        local conflict_parts = split_path(conflict_dir)
        if #conflict_parts > 0 then
            table.insert(conflicting_parts, conflict_parts[#conflict_parts])
        end
    end


    -- Try progressive abbreviation lengths (3, 2, then 1 character)
    local max_attempts = {3, 2, 1}

    for _, prefix_len in ipairs(max_attempts) do
        if prefix_len <= #target_part then
            local candidate = string.sub(target_part, 1, prefix_len)

            local is_unique = true
            for _, conflict_part in ipairs(conflicting_parts) do
                if #conflict_part >= prefix_len then
                    local conflict_prefix = string.sub(conflict_part, 1, prefix_len)
                    if candidate == conflict_prefix then
                        is_unique = false
                        break
                    end
                end
            end

            if is_unique then
                return candidate
            end
        end
    end

    -- Fallback: use full directory name
    return target_part
end

-- Generate minimal distinguishing prefixes for files with same names
-- Returns: { {prefix = "s/", filename = "config.lua"}, {prefix = "t/", filename = "config.lua"} }
function M.generate_minimal_prefixes(buffer_list, window_width)
    if not buffer_list or #buffer_list == 0 then
        return {}
    end

    local results = {}
    local buffer_paths = {}
    local filename_groups = {}

    -- First pass: collect all paths and group by filename
    for i, buffer_info in ipairs(buffer_list) do
        local buffer_id = nil
        local path = ""

        -- Handle different input types
        if type(buffer_info) == "number" then
            buffer_id = buffer_info
            local success, is_valid = pcall(vim.api.nvim_buf_is_valid, buffer_id)
            if success and is_valid then
                local name_success, name = pcall(vim.api.nvim_buf_get_name, buffer_id)
                if name_success then
                    path = name
                end
            end
        elseif type(buffer_info) == "table" then
            buffer_id = buffer_info.id
            if buffer_info.name and type(buffer_info.name) == "string" then
                path = buffer_info.name
            elseif buffer_id then
                local success, is_valid = pcall(vim.api.nvim_buf_is_valid, buffer_id)
                if success and is_valid then
                    local name_success, name = pcall(vim.api.nvim_buf_get_name, buffer_id)
                    if name_success then
                        path = name
                    end
                end
            end
        end

        if path ~= "" then
            local filename = vim.fn.fnamemodify(path, ":t")
            local directory = vim.fn.fnamemodify(path, ":h")
            
            -- Convert to relative path
            local cwd = vim.fn.getcwd()
            local relative_dir = directory
            if directory:sub(1, #cwd) == cwd then
                relative_dir = directory:sub(#cwd + 2)
                if relative_dir == "" then
                    relative_dir = "."
                end
            end

            buffer_paths[i] = {
                path = path,
                filename = filename,
                directory = relative_dir,
                full_path = path
            }

            if not filename_groups[filename] then
                filename_groups[filename] = {}
            end
            table.insert(filename_groups[filename], {
                index = i,
                directory = relative_dir,
                filename = filename
            })
        else
            buffer_paths[i] = {
                path = "[No Name]",
                filename = "[No Name]",
                directory = "",
                full_path = ""
            }
        end
    end

    -- Process each buffer
    for i = 1, #buffer_list do
        if not buffer_paths[i] then
            results[i] = { prefix = "", filename = "[No Name]" }
        else
            local buffer_info = buffer_paths[i]
            local filename = buffer_info.filename
            local directory = buffer_info.directory

            -- Check if this filename has conflicts
            local conflicts = filename_groups[filename]
            if not conflicts or #conflicts <= 1 then
                -- No conflicts, no prefix needed
                results[i] = { prefix = "", filename = filename }
            else
                -- Has conflicts, need to generate minimal prefix
                local current_dir = directory
                local conflicting_dirs = {}
                
                for _, conflict in ipairs(conflicts) do
                    if conflict.index ~= i then
                        table.insert(conflicting_dirs, conflict.directory)
                    end
                end

                -- Calculate available width based on window size
                window_width = window_width or 40  -- fallback
                local base_indent = 4  -- approximate indent
                local tree_chars = 2   -- tree symbols
                local numbering_width = 4  -- [N] format
                local filename_space = 15  -- reserve space for filename
                local available_width = math.max(8, window_width - base_indent - tree_chars - numbering_width - filename_space)

                local minimal_prefix = find_minimal_distinguishing_prefix(current_dir, conflicting_dirs, available_width)
                results[i] = { 
                    prefix = minimal_prefix ~= "" and (minimal_prefix .. "/") or "",
                    filename = filename 
                }
            end
        end
    end

    return results
end

-- Smart path compression with dynamic width and intelligent abbreviation
-- Gradually compresses path components to fit available space
function M.compress_path_smart(path, max_width, preserve_segments)
    if not path or path == "" or path == "." then
        return path or ""
    end

    if #path <= max_width then
        return path
    end

    preserve_segments = preserve_segments or 1
    local parts = split_path(path)

    if #parts <= preserve_segments then
        return path
    end

    -- Strategy 1: Try abbreviating with progressive length (2-3 chars)
    local function abbreviate_progressive(segments, keep_first, keep_last, max_abbrev_len)
        max_abbrev_len = max_abbrev_len or 3
        local result = {}
        for i = 1, #segments do
            if i <= keep_first or i > (#segments - keep_last) then
                table.insert(result, segments[i])
            else
                local abbrev_len = math.min(max_abbrev_len, #segments[i])
                table.insert(result, string.sub(segments[i], 1, abbrev_len))
            end
        end
        return table.concat(result, "/")
    end

    -- Strategy 2: Try abbreviating all but preserved segments with variable length
    local function abbreviate_with_length(segments, preserve_count, abbrev_len)
        abbrev_len = abbrev_len or 2
        local result = {}
        local preserve_start = #segments - preserve_count + 1
        for i = 1, #segments do
            if i >= preserve_start then
                table.insert(result, segments[i])
            else
                local actual_len = math.min(abbrev_len, #segments[i])
                table.insert(result, string.sub(segments[i], 1, actual_len))
            end
        end
        return table.concat(result, "/")
    end

    -- Strategy 3: Ellipsis with preserved segments
    local function ellipsis_compress(segments, preserve_count)
        if #segments <= preserve_count + 1 then
            return table.concat(segments, "/")
        end

        local preserved = {}
        for i = #segments - preserve_count + 1, #segments do
            table.insert(preserved, segments[i])
        end

        return ".../" .. table.concat(preserved, "/")
    end

    -- Try strategies in order of preference with progressive abbreviation lengths
    local strategies = {
        -- Try 3-char abbreviations first (most readable)
        function() return abbreviate_progressive(parts, 1, preserve_segments, 3) end,
        function() return abbreviate_with_length(parts, preserve_segments, 3) end,

        -- Fall back to 2-char abbreviations
        function() return abbreviate_progressive(parts, 1, preserve_segments, 2) end,
        function() return abbreviate_with_length(parts, preserve_segments, 2) end,

        -- Single character as last resort before ellipsis
        function() return abbreviate_progressive(parts, 1, preserve_segments, 1) end,
        function() return abbreviate_with_length(parts, preserve_segments, 1) end,

        -- Ellipsis strategies
        function() return ellipsis_compress(parts, preserve_segments) end,
        function() return ellipsis_compress(parts, math.max(1, preserve_segments - 1)) end,
    }

    for _, strategy in ipairs(strategies) do
        local compressed = strategy()
        if #compressed <= max_width then
            return compressed
        end
    end

    -- Last resort: just take the end
    if preserve_segments > 0 then
        local end_parts = {}
        for i = math.max(1, #parts - preserve_segments + 1), #parts do
            table.insert(end_parts, parts[i])
        end
        local result = table.concat(end_parts, "/")
        if #result <= max_width then
            return result
        end
    end

    -- Ultimate fallback: truncate with ellipsis
    if max_width > 3 then
        return "..." .. string.sub(path, -(max_width - 3))
    else
        return string.sub(path, -max_width)
    end
end

-- Calculate available width for path display based on window and UI elements
function M.calculate_available_path_width(window_width, base_indent, tree_chars, numbering_width)
    window_width = window_width or 40  -- default fallback
    base_indent = base_indent or 0
    tree_chars = tree_chars or 0  -- space for tree characters like ├─
    numbering_width = numbering_width or 0  -- space for [1] etc.

    -- Reserve space for: indent + tree + numbering + filename + some padding
    local reserved_space = base_indent + tree_chars + numbering_width + 4  -- 4 for padding/margins
    local available = window_width - reserved_space

    -- Ensure minimum usable width
    return math.max(10, available)
end

-- Enhanced path compression that considers UI context
function M.compress_path_contextual(path, window_width, ui_context)
    ui_context = ui_context or {}

    local available_width = M.calculate_available_path_width(
        window_width,
        ui_context.base_indent or 0,
        ui_context.tree_chars or 0,
        ui_context.numbering_width or 0
    )

    -- Use larger proportion of available width for paths
    local max_path_width = math.floor(available_width * 0.6)  -- 60% of available space

    return M.compress_path_smart(path, max_path_width, ui_context.preserve_segments or 1)
end

-- Truncate filename with middle ellipsis to preserve start/end segments
function M.truncate_filename_middle(name, max_length, ellipsis)
    if not name or name == "" or type(max_length) ~= "number" then
        return name or ""
    end

    if max_length <= 0 then
        return name
    end

    if #name <= max_length then
        return name
    end

    ellipsis = (type(ellipsis) == "string" and ellipsis ~= "") and ellipsis or "…"
    local ellipsis_len = #ellipsis

    if max_length <= ellipsis_len then
        return string.sub(name, 1, max_length)
    end

    local keep_total = max_length - ellipsis_len
    local keep_start = math.ceil(keep_total / 2)
    local keep_end = keep_total - keep_start

    if keep_end <= 0 then
        return string.sub(name, 1, keep_start) .. ellipsis
    end

    return string.sub(name, 1, keep_start) .. ellipsis .. string.sub(name, -keep_end)
end

return M
