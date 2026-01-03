-- Benchmark: bufferline sync performance under typical toggling/switching
local function add_rtp_root()
    local cwd = vim.fn.getcwd()
    local rtp_root = vim.fn.fnamemodify(cwd, ":h:h")
    vim.opt.rtp:append(rtp_root)
end

local function add_bufferline_rtp()
    local cwd = vim.fn.getcwd()
    local bufferline_path = cwd .. "/vendor/bufferline.nvim"
    if vim.fn.isdirectory(bufferline_path) == 0 then
        print("SKIP: vendor/bufferline.nvim not found")
        vim.cmd("qa")
        return false
    end
    vim.opt.rtp:append(bufferline_path)
    return true
end

local function write_temp_file(idx)
    local name = vim.fn.tempname()
    vim.fn.writefile({ "buffer " .. tostring(idx) }, name)
    return name
end

local function sleep(ms)
    vim.wait(ms)
end

local function format_stats(stats)
    local entries = {}
    for label, stat in pairs(stats) do
        local avg = stat.total_ms / stat.count
        table.insert(entries, {
            label = label,
            count = stat.count,
            total_ms = stat.total_ms,
            avg_ms = avg,
            max_ms = stat.max_ms
        })
    end
    table.sort(entries, function(a, b)
        return a.total_ms > b.total_ms
    end)
    print("VBL sync profile summary (total_ms desc):")
    for _, entry in ipairs(entries) do
        print(string.format("  %-30s count=%4d total=%.2fms avg=%.2fms max=%.2fms",
            entry.label, entry.count, entry.total_ms, entry.avg_ms, entry.max_ms))
    end
end

vim.g.vbl_sync_profile = true

add_rtp_root()
if not add_bufferline_rtp() then
    return
end

require('bufferline').setup({})

local vbl = require('vertical-bufferline')
vbl.setup({
    auto_create_groups = true,
    auto_add_new_buffers = false,
    group_scope = "global",
})

local groups = require('vertical-bufferline.groups')
local bl_integration = require('vertical-bufferline.bufferline-integration')

local buffer_count = 20
local group_count = 10
local iterations = 100

local buffer_ids = {}
for i = 1, buffer_count do
    local file = write_temp_file(i)
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    local buf_id = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_option(buf_id, "buflisted", true)
    table.insert(buffer_ids, buf_id)
end

local group_ids = {}
for i = 1, group_count do
    table.insert(group_ids, groups.create_group("Bench " .. tostring(i)))
end

for i, buf_id in ipairs(buffer_ids) do
    local group_id = group_ids[((i - 1) % #group_ids) + 1]
    groups.add_buffer_to_group(buf_id, group_id)
end

groups.set_active_group(group_ids[1])
bl_integration.reset_profile_stats()

vbl.toggle()
sleep(150)

for i = 1, iterations do
    local buf_id = buffer_ids[((i - 1) % #buffer_ids) + 1]
    pcall(vim.api.nvim_set_current_buf, buf_id)

    local group_id = group_ids[((i - 1) % #group_ids) + 1]
    groups.set_active_group(group_id)

    if i % 10 == 0 then
        vbl.toggle()
    end

    sleep(5)
end

sleep(300)

local stats = bl_integration.get_profile_stats()
if not stats or vim.tbl_isempty(stats) then
    print("No profile stats collected (sync disabled or no activity).")
else
    format_stats(stats)
end

vim.cmd("qa")
