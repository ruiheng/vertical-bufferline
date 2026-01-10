" Filetype detection for buffer-nexus
" This file is mainly for documentation - filetype is set programmatically

" Note: The buffer-nexus filetype is set directly in the plugin code
" when creating sidebar buffers. This file serves as a placeholder for
" proper plugin structure and could be used for additional detection logic
" if needed in the future.

au BufNewFile,BufRead *.bngroups setfiletype buffer-nexus-groups
