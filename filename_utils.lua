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
local function find_minimal_distinguishing_prefix(current_dir, conflicting_dirs)
    if current_dir == "" or current_dir == "." then
        return ""
    end
    
    local current_parts = split_path(current_dir)
    if #current_parts == 0 then
        return ""
    end

    -- Simple approach: just use the last directory component and find minimal distinguishing prefix
    local target_part = current_parts[#current_parts]
    
    -- Collect all conflicting last parts that we need to distinguish from
    local conflicting_parts = {}
    for _, conflict_dir in ipairs(conflicting_dirs) do
        local conflict_parts = split_path(conflict_dir)
        if #conflict_parts > 0 then
            table.insert(conflicting_parts, conflict_parts[#conflict_parts])
        end
    end
    
    -- Find minimal prefix that makes target_part unique
    for prefix_len = 1, #target_part do
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
    
    -- Fallback: use full directory name
    return target_part
end

-- Generate minimal distinguishing prefixes for files with same names
-- Returns: { {prefix = "s/", filename = "config.lua"}, {prefix = "t/", filename = "config.lua"} }
function M.generate_minimal_prefixes(buffer_list)
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

                local minimal_prefix = find_minimal_distinguishing_prefix(current_dir, conflicting_dirs)
                results[i] = { 
                    prefix = minimal_prefix ~= "" and (minimal_prefix .. "/") or "",
                    filename = filename 
                }
            end
        end
    end

    return results
end

return M