" Vim syntax file for buffer-nexus
" Language: buffer-nexus
" Maintainer: Claude Code Assistant

if exists("b:current_syntax")
    finish
endif

" Define syntax groups that match our highlight groups from config.lua
syn match VBlGroupHeader /^=.*=\s*$/
syn match VBlTreePrefix /^\s*[├└│]/
syn match VBlCurrentBuffer /^\s*[├└│].*\*$/
syn match VBlModifiedBuffer /^\s*[├└│].*●/
syn match VBlNumbering /\s\+\d\+\|\d\+|\d\+/
syn match VBlPath /\s\+\~.*$/

" Link to our actual highlight groups
highlight default link VBlGroupHeader BufferNexusGroupActive
highlight default link VBlTreePrefix BufferNexusPrefix
highlight default link VBlCurrentBuffer BufferNexusFilenameCurrent
highlight default link VBlModifiedBuffer BufferNexusModified
highlight default link VBlNumbering BufferNexusNumberLocal
highlight default link VBlPath BufferNexusPath

let b:current_syntax = "buffer-nexus"