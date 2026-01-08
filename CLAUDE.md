# Claude Code Assistant Notes

## Important Directory Information

- **Working Directory**: `/home/ruiheng/config_files/nvim/lua/buffer-nexus`
- **Git Repository**: `/home/ruiheng/config_files/nvim/lua/buffer-nexus` (THIS is the git repo)
- **Plugin Code Location**: `/home/ruiheng/config_files/nvim/lua/buffer-nexus/`

**IMPORTANT**: Git operations should be performed directly in `/home/ruiheng/config_files/nvim/lua/buffer-nexus/` - this is NOT a submodule, it's the actual git repository.

## Git Operations

Git repository is directly at: `/home/ruiheng/config_files/nvim/lua/buffer-nexus/`

```bash
# Work directly in the buffer-nexus directory
git add .
git commit -m "message"
```

**DO NOT** manage other directories like `/home/ruiheng/config_files/` - only manage the buffer-nexus plugin directory.

## Key Files

- `init.lua` - Main plugin file
- `bufferline-integration.lua` - Integration with bufferline.nvim
- `config.lua` - Configuration and constants
- `logger.lua` - Debug logging system (NEW)
- `commands.lua` - User commands including debug commands

## Current Status

### Recently Implemented: Adaptive Width Feature (2025-11-29)

Added adaptive sidebar width that automatically adjusts based on content:

#### New Configuration Options
- `width` - Minimum sidebar width (default: 25, was 40)
- `max_width` - Maximum sidebar width (default: 60)
- `adaptive_width` - Enable/disable adaptive sizing (default: true)

#### New Command
```vim
:BNToggleAdaptiveWidth  # Toggle adaptive width on/off
```

#### Implementation Details
- `calculate_content_width()` - Calculates max display width of all lines
- `apply_adaptive_width()` - Applies calculated width within min/max bounds
- Integrated into `finalize_buffer_display()` for automatic updates
- Supports both split and floating window modes
- Preserves width state across sidebar open/close cycles

See `ADAPTIVE_WIDTH.md` for detailed documentation.

### Previously Implemented: Debug Logging System

Added comprehensive debug logging system to help troubleshoot buffer state synchronization issues:

#### New Files
- `logger.lua` - Full-featured logging module with file output, memory buffer, and multiple log levels

#### Debug Commands Added
```vim
:BNDebugEnable [log_file] [log_level]  # Enable logging
:BNDebugDisable                        # Disable logging  
:BNDebugStatus                         # Show status
:BNDebugLogs [count]                   # Show recent logs
```

#### Key Monitoring Points
- Timer-based synchronization in bufferline-integration.lua
- Current buffer detection logic in get_main_window_current_buffer()
- Buffer state changes and highlighting decisions
- Refresh trigger reasons and validation

#### Usage Example
```vim
:BNDebugEnable ~/vbl-debug.log DEBUG
# Reproduce the issue
:BNDebugLogs 50
:BNDebugDisable
```

#### Auto-Logging Feature
为了方便调试session恢复问题，日志系统现在会在以下情况自动启用：
- Session恢复时 → `~/vbl-session-debug.log` (DEBUG级别)
- Buffer同步时 → `~/vbl-sync-debug.log` (DEBUG级别)  
- 刷新操作时 → `~/vbl-refresh-debug.log` (INFO级别)

### Known Issue Being Debugged
BN侧边栏有时无法跟随bufferline更新当前buffer状态 - 高亮显示错误的文件或无高亮。

#### 问题分析进展
通过Session.vim分析发现根本原因：**路径格式不匹配导致session恢复失败**
- BN保存相对路径：`"lyceum/page/chat_utils.py"`
- Vim实际路径：`~/lyceum/lyceum/page/chat_utils.py`
- 当前工作目录变化导致路径无法匹配，current buffer状态丢失

#### 已实施修复
1. 增强路径匹配算法 - 支持相对/绝对路径混合匹配
2. 详细日志追踪 - 自动记录session恢复和同步过程
3. 智能buffer查找 - 文件名+路径后缀匹配算法

## BN Synchronization Logic

**CORE PRINCIPLE**: bufferline ↔ BN bidirectional sync
- **Primary**: bufferline → BN (timer every 100ms)
- **Secondary**: BN → bufferline (when switching groups)

### Current Unnamed Buffer Issue
**Problem**: Unnamed buffer disappears when opening new files
- Works fine with bufferline only
- Breaks when BN is added
- Our code incorrectly unlists the unnamed buffer somewhere

# important-instruction-reminders
**LANGUAGE REQUIREMENT**: ALWAYS use English for responses and code. Never use Chinese or other languages unless explicitly requested.
