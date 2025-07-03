# Vertical Bufferline 动态分组功能

## 功能概述

动态分组功能允许你将 buffer 组织到不同的分组中，建议每个分组保持 10 个左右的 buffer，这样你就可以使用 `<leader>1` 到 `<leader>9` 快捷键快速切换每个分组中的前9个 buffer。同一个 buffer 可以同时存在于多个分组中，提供最大的灵活性。

### 主要特性

- **动态创建分组**：随时创建新分组，无需预先配置
- **自动 buffer 管理**：新打开的 buffer 自动添加到当前分组
- **bufferline 集成**：bufferline 只显示当前分组的 buffer
- **flexible buffer 分配**：同一个 buffer 可以同时存在于多个分组中
- **智能提示**：建议每个分组保持 10 个以内的 buffer 以配合快捷键使用
- **完美兼容**：与现有的 picking 模式和高亮功能完全兼容

## 快捷键

### 分组管理
- `<leader>gn` - 切换到下一个分组
- `<leader>gp` - 切换到上一个分组  
- `<leader>gl` - 列出所有分组
- `<leader>gc` - 创建新分组
- `<leader>ga` - 将当前 buffer 添加到指定分组
- `<leader>g1` 到 `<leader>g9` - 直接切换到分组 1-9

### Buffer 操作（在每个分组内）
- `<leader>1` 到 `<leader>9` - 快速切换到当前分组的第 1-9 个 buffer
- `<leader>p` - bufferline picking 模式（只显示当前分组的 buffer）

## 用户命令

### 分组操作
- `:VBufferLineCreateGroup [名称]` - 创建新分组
- `:VBufferLineDeleteGroup <分组名或ID>` - 删除分组  
- `:VBufferLineRenameGroup <当前名称> <新名称>` - 重命名分组
- `:VBufferLineSwitchGroup [分组名或ID]` - 切换到指定分组
- `:VBufferLineListGroups` - 列出所有分组

### Buffer 操作
- `:VBufferLineAddToGroup <分组名或ID>` - 将当前 buffer 添加到指定分组
- `:VBufferLineRemoveFromGroup` - 从当前分组移除当前 buffer
- `:VBufferLineNextGroup` - 切换到下一个分组
- `:VBufferLinePrevGroup` - 切换到上一个分组

## 使用场景

### 1. 项目分组
```
Group 1: "Frontend" - React 组件文件
Group 2: "Backend" - API 和数据库文件  
Group 3: "Config" - 配置文件
```

### 2. 功能分组
```
Group 1: "Main" - 主要开发文件
Group 2: "Tests" - 测试文件
Group 3: "Docs" - 文档文件
```

### 3. 语言分组
```
Group 1: "TypeScript" - .ts/.tsx 文件
Group 2: "Python" - .py 文件
Group 3: "Lua" - .lua 文件
```

## 工作流示例

1. **开始新项目**：
   ```
   <leader>gc → 输入 "Frontend" → 创建前端分组
   <leader>gc → 输入 "Backend" → 创建后端分组
   ```

2. **组织现有 buffer**：
   ```
   打开 React 组件文件
   <leader>ga → 选择 "Frontend" → 添加到前端分组
   
   打开 API 文件  
   <leader>ga → 选择 "Backend" → 添加到后端分组
   ```

3. **在分组间切换**：
   ```
   <leader>g1 → 切换到第一个分组
   <leader>g2 → 切换到第二个分组
   <leader>gn → 切换到下一个分组
   ```

4. **在分组内快速切换**：
   ```
   <leader>1 → 切换到当前分组第1个 buffer
   <leader>2 → 切换到当前分组第2个 buffer
   <leader>p → 使用 picking 模式快速选择
   ```

## 界面说明

在 vertical bufferline 中，分组信息显示在顶部：

```
┌─ Frontend (3/10 buffers)
│ Use <leader>gn/<leader>gp to switch groups  
└─

  🌙 App.tsx
  📄 Button.jsx
  📝 README.md
```

- 第一行显示当前分组名称和 buffer 数量
- 第二行显示分组切换提示（当有多个分组时）
- 下面显示当前分组的所有 buffer

## 自动功能

1. **自动添加 buffer**：新打开的文件自动添加到当前活跃分组
2. **自动清理**：删除的 buffer 自动从分组中移除
3. **智能提示**：当分组满（10个 buffer）时提示创建新分组
4. **空分组清理**：移除最后一个 buffer 时提示是否删除空分组

## 配置选项

分组功能在首次使用时自动启用，默认配置：

```lua
{
    max_buffers_per_group = 10,    -- 每个分组最大 buffer 数量
    auto_create_groups = true,      -- 自动创建分组
    auto_add_new_buffers = true,    -- 自动添加新 buffer
    group_name_prefix = "Group",    -- 默认分组名前缀
}
```

## 技术特性

- **bufferline 集成**：无缝集成 bufferline.nvim，自动过滤显示
- **事件驱动**：基于 Neovim 事件系统，响应 buffer 变化
- **高性能**：只在需要时进行过滤，对性能影响最小
- **兼容性**：完全兼容现有的 picking 模式和高亮功能

这个功能让你可以更好地组织大量的 buffer，并通过熟悉的快捷键快速访问它们，大幅提升开发效率。