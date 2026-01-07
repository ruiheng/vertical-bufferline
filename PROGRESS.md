# Vertical Bufferline 项目进展

## 项目目标

本插件旨在 `bufferline.nvim` 的功能基础上，创建一个以竖直方式显示当前打开的 buffer 列表的独立窗口。目标是尽可能地复刻（clone）`bufferline.nvim` 的核心功能和用户体验，为用户提供一个竖直排列的、可交互的 buffer 列表视图。

## 当前状态 (截至 2025-07-08)

- [x] **基本窗口创建**: 成功创建了一个独立的浮动或分割窗口。
- [x] **Buffer 列表显示**: 能够获取并显示 `bufferline.nvim` 的 buffer 列表。
- [x] **光标行切换**: 支持通过在侧边栏移动光标并按 `<CR>` 来切换 buffer。
- [x] **完美镜像 Picking 模式**: ✨ **完全实现** - 当用户使用 `<leader>p` 触发 bufferline 的 picking 模式时，侧边栏完美镜像显示相同的 hint 字符，具有与原生 bufferline 完全一致的视觉效果。
- [x] **安全的 Buffer 切换**: 解决了 E325 错误，通过安全检查和 pcall 包装来处理 buffer 切换。
- [x] **高亮同步**: 完美同步 bufferline 的高亮样式，包括不同状态的 buffer（当前、可见、修改过的）。
- [x] **Buffer 关闭功能**: 通过 `d` 键关闭光标下的 buffer。
- [x] **文件类型图标**: 显示文件类型图标，包括 emoji 后备方案。
- [x] **🎉 动态分组功能**: ✨ **全新特性** - 实现了完整的动态 buffer 分组管理系统，突破了原生 bufferline 的限制。
- [x] **📂 路径显示一致性**: ✨ **重大修复** - 解决了非活跃分组内路径高亮不一致的问题，确保所有路径行都能正确应用高亮。

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

## 📂 路径高亮一致性问题解决 (2025-07-08)

### 问题背景
在实现多分组显示功能后，发现非活跃分组内的路径行存在高亮不一致的问题：
- 同一分组内某些路径行有高亮，某些没有
- 路径行的颜色效果不统一
- 影响用户的视觉体验和信息清晰度

### 根本原因分析
通过系统性调试发现了问题的根本原因：

1. **组件数据不匹配**: `components` 数组只包含活跃分组的组件信息（来自 bufferline），但 `new_line_map` 和 `line_types` 却包含所有分组的行信息。

2. **组件查找失败**: 在高亮应用循环中，非活跃分组的缓冲区ID在 `components` 数组中找不到对应的组件，导致 `apply_path_highlighting` 函数未被调用。

3. **数据结构不一致**: 
   - 活跃分组：使用原始的 bufferline 组件（功能完整）
   - 非活跃分组：手动构造简化组件（仅用于显示）
   - 但高亮查找只在原始组件数组中进行

### 解决方案技术细节

#### 1. 引入组件收集机制
```lua
local all_components = {}  -- 收集所有分组的组件信息

-- 在渲染每个分组后收集组件
for _, comp in ipairs(group_components) do
    all_components[comp.id] = comp
end
```

#### 2. 改进组件查找效率
**修改前**（线性搜索，且数据不完整）：
```lua
local component = nil
for _, comp in ipairs(components) do  -- 只包含活跃分组
    if comp.id == buffer_id then
        component = comp
        break
    end
end
```

**修改后**（哈希表查找，且数据完整）：
```lua
local component = all_components[buffer_id]  -- 包含所有分组
```

#### 3. 确保数据完整性
- `render_all_groups` 函数修改为接收 `all_components` 参数
- 每个分组渲染完成后，其组件信息都被添加到 `all_components` 哈希表中
- 高亮应用时使用完整的组件信息，确保所有分组的路径行都能找到对应组件

### 修复效果验证
修复后的行为：
- ✅ 所有路径行都能正确识别为 "path" 类型
- ✅ 非活跃分组的组件查找成功，不再出现 `{NO_COMPONENT_ID}` 
- ✅ 路径高亮逻辑正确执行：
  - 非当前缓冲区路径：使用 `VBufferLinePath` 高亮组
  - 当前缓冲区路径（活跃分组中）：使用 `VBufferLinePathCurrent` 高亮组
- ✅ 同一分组内路径高亮完全一致

### 技术亮点
1. **性能优化**: 将线性搜索 O(n) 改为哈希表查找 O(1)
2. **数据一致性**: 确保渲染数据和高亮数据使用相同的组件源
3. **可维护性**: 统一了活跃分组和非活跃分组的组件处理逻辑
4. **鲁棒性**: 解决了组件数据不匹配导致的高亮失效问题

这个修复不仅解决了路径高亮问题，还改进了整体的代码架构和性能。

## 🎉 动态分组功能详述

### 功能特性
- **动态创建分组**: 无需预先配置，随时创建新的 buffer 分组
- **智能 Buffer 过滤**: bufferline 只显示当前分组的 buffer，减少视觉干扰
- **快捷键保持**: 用户的 `<leader>1-9` 快捷键在每个分组内工作，最多可快速访问前9个 buffer
- **完整的分组管理**: 创建、删除、重命名、切换分组，以及 buffer 在分组间的移动
- **bufferline 无缝集成**: 通过函数钩子技术，让原生 bufferline 显示当前分组的 buffer

### 解决的核心痛点
1. **Buffer 过多问题**: 开发时经常有几十个打开的 buffer，tabline 无法全部显示
2. **快捷键限制**: 原来只能快速访问前9个 buffer，现在每个分组都可以有9个快捷访问
3. **项目组织**: 可以按项目、文件类型、功能等维度组织 buffer
4. **动态性**: 不像原生分组需要预先配置，可以随时根据工作需要创建分组

### 技术实现亮点
- **函数钩子**: 通过钩入 `bufferline.utils.get_updated_buffers` 实现透明过滤
- **事件驱动**: 使用 Neovim 的事件系统响应分组变化，自动刷新界面
- **兼容性**: 完全兼容现有的 picking 模式和高亮功能
- **智能提示**: 当分组 buffer 数量达到推荐值时给出友好提示，但不强制限制

## 下一步计划 (To-Do)

- [x] **解决遗留的 `E325` 错误**：已通过重新设计解决。
- [x] **同步高亮**: 已同步 `bufferline.nvim` 的高亮状态，包括当前 buffer、可见 buffer、修改过的 buffer 等。
- [x] **复刻核心操作**:
    - [x] Buffer 关闭 (通过 `d` 键关闭光标下的 buffer)。
    - [x] 显示文件类型图标。
    - [ ] 显示 LSP 诊断信息 (errors, warnings)。
- [x] **动态分组功能**:
    - [x] 分组创建、删除、重命名
    - [x] Buffer 在分组间的移动和管理
    - [x] bufferline 集成和过滤
    - [x] 分组切换快捷键
    - [x] 用户界面和提示信息
- [ ] **窗口管理**:
    - [x] 实现了方便的命令来打开/关闭/切换 (toggle) 这个竖直列表窗口。
- [ ] **用户配置**: 添加可配置选项，例如窗口位置、宽度、按键映射等。
- [ ] **分组数据持久化**: 保存分组配置到文件，下次启动时恢复
- [ ] **代码优化**: 审阅并重构现有代码，确保其稳定性和可维护性。

## 使用方法

1. **打开/关闭侧边栏**: `<leader>bs`
2. **在侧边栏中**:
   - `j/k`: 上下移动
   - `<CR>`: 切换到光标所在的 buffer
   - `d`: 关闭光标所在的 buffer
   - `q` 或 `<Esc>`: 关闭侧边栏
3. **Picking 模式**: 使用 bufferline 的原生命令 `<leader>p`，侧边栏会自动镜像显示 hints
4. **分组管理**: 
   - `<leader>gc`: 创建新分组
   - `<leader>gn/gp`: 切换到下一个/上一个分组  
   - `<leader>g1-g9`: 直接切换到分组1-9
   - `<leader>ga`: 将当前 buffer 添加到指定分组
   - `<leader>gl`: 列出所有分组
5. **快速访问**: 在每个分组内使用 `<leader>1-9` 快速切换到对应位置的 buffer

## 关键设计原则

1. **完全依赖 bufferline.nvim**：不重复实现任何 bufferline 已有的功能
2. **被动镜像**：只显示状态，不主动干预 bufferline 的操作
3. **安全第一**：避免任何可能导致崩溃或不稳定的钩子或干预
4. **用户体验一致**：确保与 bufferline 的交互体验完全一致