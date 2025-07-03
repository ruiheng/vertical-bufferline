# Vertical Bufferline 项目进展

## 项目目标

本插件旨在 `bufferline.nvim` 的功能基础上，创建一个以竖直方式显示当前打开的 buffer 列表的独立窗口。目标是尽可能地复刻（clone）`bufferline.nvim` 的核心功能和用户体验，为用户提供一个竖直排列的、可交互的 buffer 列表视图。

## 当前状态 (截至 2025-07-03)

- [x] **基本窗口创建**: 成功创建了一个独立的浮动或分割窗口。
- [x] **Buffer 列表显示**: 能够获取并显示 `bufferline.nvim` 的 buffer 列表。
- [x] **光标行切换**: 支持通过在侧边栏移动光标并按 `<CR>` 来切换 buffer。
- [x] **完美镜像 Picking 模式**: ✨ **完全实现** - 当用户使用 `<leader>p` 触发 bufferline 的 picking 模式时，侧边栏完美镜像显示相同的 hint 字符，具有与原生 bufferline 完全一致的视觉效果。
- [x] **安全的 Buffer 切换**: 解决了 E325 错误，通过安全检查和 pcall 包装来处理 buffer 切换。
- [x] **高亮同步**: 完美同步 bufferline 的高亮样式，包括不同状态的 buffer（当前、可见、修改过的）。
- [x] **Buffer 关闭功能**: 通过 `d` 键关闭光标下的 buffer。
- [x] **文件类型图标**: 显示文件类型图标，包括 emoji 后备方案。

## 核心挑战与解决方案：与 `bufferline.nvim` Picking 模式的同步问题

**问题背景：**

最初的目标是实时"镜像" `bufferline.nvim` 的 picking 模式。然而，`bufferline.nvim` 的 `pick` 命令是一个**阻塞性**操作，它会调用 `vim.fn.getchar()` 来暂停 Neovim 的事件循环。这给我们带来了巨大的挑战。

**已尝试的失败方案：**

1.  **异步刷新 (`vim.schedule`)**: 我们最初尝试 hook `bufferline.ui.refresh` 函数，并在 hook 中使用 `vim.schedule` 来异步刷新我们的侧边栏。**结果**：失败。因为 `getchar()` 会阻塞事件循环，我们的刷新操作总是在 `bufferline` 退出 picking 模式后才执行，导致我们永远无法捕获到 `is_picking = true` 的状态。

2.  **同步刷新**：为了解决时序问题，我们尝试在 hook 中直接同步调用刷新函数。**结果**：失败。这导致了 `bufferline.nvim` 在尝试切换 buffer 时发生崩溃 (`E325: ATTENTION`)。原因是我们的 UI 更新操作干扰了 `bufferline` 尚未完成的、敏感的内部状态变更。这是一个典型的"重入"（re-entrancy）问题。

3.  **捕获后异步刷新**：我们尝试了一种混合方案：在 hook 中立即用 `vim.deepcopy` 捕获 `bufferline.state` 的状态，然后用 `vim.schedule` 异步地使用这个捕获到的状态来渲染侧边栏。**结果**：失败。这依然无法避免在 `getchar()` 的阻塞上下文中执行 UI 操作，最终还是导致了崩溃。

4.  **寻找内部事件/回调**：我们深入研究了 `bufferline.nvim` 的源代码，希望能找到可供利用的事件回调（如 `on_pick_start`）。**结果**：失败。`bufferline.nvim` 并未提供此类用于安全注入逻辑的事件接口。

**最终解决方案：高频高亮应用 + 完全镜像**

经过深入研究和调试，我们发现了根本问题并找到了完美的解决方案：

### 核心问题
在 `bufferline.nvim` 的 picking 模式期间，`getchar()` 函数会阻塞事件循环，同时 bufferline 会高频率地刷新 UI，不断覆盖我们应用的高亮效果。

### 解决方案的关键技术
1. **保留 UI Hook**：继续使用 `bufferline.ui.refresh` 钩子来检测状态变化。
2. **高亮组完全同步**：动态复制 bufferline 的 `BufferLinePick*` 高亮组到我们的 `VBufferLinePick*` 高亮组。
3. **高频高亮应用**：在 picking 模式期间，启动 50ms 间隔的定时器，持续重新应用高亮以对抗 bufferline 的覆盖。
4. **双重高亮保险**：同时使用带 namespace 和不带 namespace 的高亮应用，确保效果持久。
5. **强制重绘**：每次高亮应用后强制执行 `redraw!` 确保视觉更新。

### 技术细节
```lua
-- 检测 picking 模式并启动高频高亮应用
if is_picking and not state.was_picking then
    local highlight_timer = vim.loop.new_timer()
    highlight_timer:start(0, 50, vim.schedule_wrap(function()
        if current_state.is_picking and state.is_sidebar_open then
            M.apply_picking_highlights()  -- 持续重新应用高亮
        else
            highlight_timer:stop()
            highlight_timer:close()
        end
    end))
end
```

## 当前状态

-   **✨ 完美高亮效果**：在 picking 模式期间，hint 字符显示与 bufferline 原生完全一致的红色高亮效果。
-   **零延迟响应**：高亮效果实时响应 picking 模式的进入和退出。
-   **稳定可靠**：通过高频重新应用，确保高亮效果不被覆盖。

## 下一步计划 (To-Do)

- [x] **解决遗留的 `E325` 错误**：已通过重新设计解决。
- [x] **同步高亮**: 已同步 `bufferline.nvim` 的高亮状态，包括当前 buffer、可见 buffer、修改过的 buffer 等。
- [x] **复刻核心操作**:
    - [x] Buffer 关闭 (通过 `d` 键关闭光标下的 buffer)。
    - [x] 显示文件类型图标。
    - [ ] 显示 LSP 诊断信息 (errors, warnings)。
- [ ] **窗口管理**:
    - [x] 实现了方便的命令来打开/关闭/切换 (toggle) 这个竖直列表窗口。
- [ ] **用户配置**: 添加可配置选项，例如窗口位置、宽度、按键映射等。
- [ ] **代码优化**: 审阅并重构现有代码，确保其稳定性和可维护性。

## 使用方法

1. **打开/关闭侧边栏**: `<leader>vb`
2. **在侧边栏中**:
   - `j/k`: 上下移动
   - `<CR>`: 切换到光标所在的 buffer
   - `d`: 关闭光标所在的 buffer
   - `q` 或 `<Esc>`: 关闭侧边栏
3. **Picking 模式**: 使用 bufferline 的原生命令 `<leader>p`，侧边栏会自动镜像显示 hints

## 关键设计原则

1. **完全依赖 bufferline.nvim**：不重复实现任何 bufferline 已有的功能
2. **被动镜像**：只显示状态，不主动干预 bufferline 的操作
3. **安全第一**：避免任何可能导致崩溃或不稳定的钩子或干预
4. **用户体验一致**：确保与 bufferline 的交互体验完全一致