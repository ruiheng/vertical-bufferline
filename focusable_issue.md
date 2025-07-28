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
    if config_module.DEFAULTS.position == "left" then
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

## 关键疑问

1. **API 版本问题**：是否 `focusable = false` 在某些 Neovim 版本中行为不一致？
2. **窗口创建方式**：使用 `vim.cmd("vsplit")` 创建的窗口是否影响 focusable 设置？
3. **设置时机**：是否需要在特定时机设置 focusable 才能生效？
4. **其他配置冲突**：是否有其他窗口配置或全局设置影响了 focusable 的行为？

## 相关文档引用

根据 Neovim 官方文档：
> "Focusable windows are part of the navigation stack and can be accessed by commands like :windo and CTRL-W. Non-focusable windows are skipped by navigation commands but can still be explicitly focused."

这表明 `focusable = false` 应该让导航命令跳过该窗口，但我们的实际体验不符合这个描述。

## 完整代码上下文

如果需要更多上下文，可以查看完整的窗口创建和配置代码。我们已经排除了以下可能的干扰因素：
- WinEnter autocmd 重定向
- 多余的 `nvim_set_current_win` 调用  
- 错误的 API 使用（如使用不存在的 `winfocusable` 选项）

希望能得到关于为什么 `focusable = false` 在我们的场景下不起作用的指导。