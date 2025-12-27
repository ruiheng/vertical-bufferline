" Vim syntax file for vertical-bufferline edit mode
" Language: vertical-bufferline-edit

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

let b:current_syntax = "vertical-bufferline-edit"
