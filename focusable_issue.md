# Neovim focusable=false 不能阻止键盘导航的问题

## 问题描述

在 Neovim 插件开发中，我们创建了一个侧边栏窗口，并设置了 `focusable = false` 来阻止用户通过键盘导航（如 `<C-w>w`）进入该窗口。但实际测试发现，`<C-w>w` 仍然可以进入侧边栏。

## 环境信息

- **Neovim 版本**: `NVIM v0.12.0-dev-745+g09f9d72c24`
- **使用的 API**: `nvim_win_set_config(win_id, {focusable = false})`

## 代码实现

```lua
-- 创建侧边栏窗口
local function open_sidebar()
    local buf_id = api.nvim_create_buf(false, true)
    local current_win = api.nvim_get_current_win()
    
    -- 创建窗口 (会自动切换到新窗口)
    if config_module.settings.position == "left" then
        vim.cmd("topleft vsplit")
    else
        vim.cmd("botright vsplit")
    end
    
    local new_win_id = api.nvim_get_current_win()
    api.nvim_win_set_buf(new_win_id, buf_id)
    api.nvim_win_set_width(new_win_id, 40)
    
    -- 设置 focusable = false
    pcall(function()
        api.nvim_win_set_config(new_win_id, {focusable = false})
    end)
    
    -- 切换回原窗口
    api.nvim_set_current_win(current_win)
end
```

## 验证方法

我们添加了调试函数来确认设置已生效：

```lua
function M.debug_focusable()
    local sidebar_win = state_module.get_win_id()
    local config = api.nvim_win_get_config(sidebar_win)
    print("Sidebar window " .. sidebar_win .. " config:")
    print(vim.inspect(config))
end
```

**输出结果**：
```
Sidebar window 1002 config:
{
  external = false,
  focusable = false,    -- ✓ 设置已生效
  height = 94,
  hide = false,
  mouse = false,
  relative = "",
  split = "left",
  width = 40
}
```

## 预期行为 vs 实际行为

**预期行为**：
- `<C-w>w` 应该跳过 focusable=false 的窗口
- 根据 Neovim 文档，非 focusable 窗口应该被导航命令跳过

**实际行为**：
- `<C-w>w` 仍然可以进入侧边栏
- 设置确实已生效（通过 `nvim_win_get_config` 验证）

## 相关尝试

1. **API 调用测试**：程序化调用 `nvim_set_current_win(sidebar_win)` 可以成功切换到 focusable=false 的窗口
2. **清理其他代码**：移除了所有可能影响的 autocmd 和窗口切换逻辑
3. **使用 pcall**：确保 API 调用没有失败

## 关键发现：focusable 仅对浮动窗口有效

**重要更新**：经过进一步调研，发现了问题的根本原因。

根据 Neovim 的 GitHub issue [#29365](https://github.com/neovim/neovim/issues/29365)，**`focusable` 属性对非浮动窗口（分割窗口）是被明确忽略的**。

> The "focusable" attribute is explicitly ignored for non-floating windows. For example, here is the code for going to the next/previous window, which ignores focusable==false unless the window is also floating.

这意味着我们的分割窗口（split window）sidebar 无法通过 `focusable = false` 来阻止键盘导航，这是 Neovim 的设计限制，不是 bug。

## 尝试过的解决方案

1. **改进窗口创建方式**：
   - 从 `vim.cmd("vsplit")` 改为 `nvim_open_win` 原子性创建
   - 在创建时就设置 `focusable = false`
   - **结果**：仍然无效，因为 focusable 对分割窗口不起作用

## 可能的替代方案

既然 `focusable = false` 对分割窗口无效，可能需要考虑以下替代方案：

1. **使用浮动窗口**：
   - 改为创建浮动窗口形式的 sidebar
   - 浮动窗口支持 `focusable = false`
   - 但可能影响现有的布局逻辑

2. **WinEnter autocmd 重定向**：
   - 监听 WinEnter 事件，检测到进入 sidebar 时自动跳转
   - 我们之前尝试过，但可能需要更精细的实现

3. **修改键盘映射**：
   - 重新映射 `<C-w>w` 等导航键
   - 让它们跳过 sidebar 窗口

4. **接受现状**：
   - 文档说明用户可以进入 sidebar，但建议使用鼠标或特定键退出

## 结论

这个问题的根本原因是 Neovim 的设计限制：**`focusable = false` 只对浮动窗口有效，对分割窗口无效**。

这不是我们的代码问题，而是需要寻找其他技术方案来实现"阻止键盘导航进入侧边栏"的需求。