" Load agda file type plugin on lagda (literate agda) files
au FileType lagda
      \ exe "source "
      \ . fnamemodify(expand("<sfile>"), ":h:h")
      \ . "/ftplugin/agda.vim"
