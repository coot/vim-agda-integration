# Agda integration for Vim-8.1

Simple agda integration with vim.  It runs a single agda process for your vim
session and communicates with it using pipes which are in vim-8.1.  It is also
using brand new popup windows which just landed in vim.  So you'd likely need
to compile vim from git.

The plugin includes:

* agda syntax script 
* literate agda syntax script
* filetype plugin with the following commands and maps (check `ftplugin/agda.vim`):
    - `:AgdaLoad`         - load current file, mapped to `<LocalLeader>l`
    - `:AgdaMetas`        - list goals
    - `:AgdaStart`        - start agda process (done automatically)
    - `:AgdaStop`         - stop agda process
    - `:AgdaRestart`      - restart agda process
    - `:AgdaVersion`      - report version of agda
    - `:AgdaRefine`       - refine a value, mapped to `<LocalLeader>r`
    - `:AgdaAuto`         - solve current goal by using Auto, mapped to `<LocalLeader>a`
    - `:AgdaInfer [expr]` - infer and normalise type of expression, if `expr`
                            not given use current goal, mapped to `<LocalLeader>t`
    - `:AgdaAbort`        - abort last operation
    - `<LocalLeader>c`    - map which opens a popup with current goal context
    - `<LocalLeader>s`    - reads current keyword and reporpts where it comes from

It supports both `{! !}` and `?` goals.  Some commands, e.g. `:AgdaAuto` will
pass the inner part of `{! !}`.
