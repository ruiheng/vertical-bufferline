" Vim syntax file for buffer-nexus edit mode
" Language: buffer-nexus-edit

if exists("b:current_syntax")
    finish
endif

syn match VBlEditComment /^#.*$/
syn match VBlEditGroupHeader /^\[Group\].*$/
syn match VBlEditBufId /^\s*buf:\d\+/
syn match VBlEditFlags /\s\+\[[^]]\+\]\s*$/

highlight default link VBlEditComment Comment
highlight default link VBlEditGroupHeader Title
highlight default link VBlEditBufId Identifier
highlight default link VBlEditFlags Type

let b:current_syntax = "buffer-nexus-edit"
