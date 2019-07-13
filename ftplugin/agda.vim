" Author: Marcin Szamotulski
"
" Agda filetype plugin
"
" This is a simple integration with 'agda --interaction-json' server.
" You can set goald in your agda file with '?' or '{! !}'.  Unlike agda-mode
" (emacs) this plugin will not rename them with unique identifiers, but rather
" put corresponding values in a quickfix list.  To find the line positions the
" plugin is inefficiently scanning source file.
"
" It runs a single 'agda' process and communicates with it.
"
" TODO
" large agda files make vim unresponsive.  Use a queue, and track
" update in callbacks.

setl expandtab

" Nah, global reference
if !exists("s:agda")
  let s:agda = v:null
endif
let s:qf_open   = v:false
let s:qf_append = v:false

let g:AgdaVimDebug = v:false
let b:AgdaInteractionPoints = []

if !exists("g:AgdaArgs")
  " the list of arguments passed to agda
  " the plugin will add `--interaction-json` as the first argument.
  let g:AgdaArgs = []
endif

fun! s:GetKeyword()
  " expand("<cword>") does not work with unicode characters
  let [_, start] = searchpos('[[:space:](){}\[\]|]', 'bnW', line("."))
  let [_, end]   = searchpos('[[:space:](){}\[\]|]', 'nW', line("."))
  if end > 0
    return getline(".")[start:end-2]
  else
    return getline(".")[start:]
  endif
endfun

fun! s:StartAgdaInteraction(args)
  if type(a:args) == v:t_string
    let args = split(a:args, '\s\+')
  elseif type(a:args) == v:t_list
    let args = copy(a:args)
  else
    echoerr "Wrong a:args type passed to s:StartAgdaInteraction"
    return
  endif
  let cmd = extend(["agda", "--interaction-json"], args)
  if s:agda == v:null
    let s:agda = job_start(
          \ cmd,
          \ { "out_cb": function("<SID>HandleAgdaMsg")
	  \ , "err_cb": function("<SID>HandleAgdaErrMsg")
          \ , "stoponexit": "term"
          \ })
  endif
  return s:agda
endfun

fun! s:StopAgdaInteraction()
  if s:agda == v:null
    return
  endif
  call job_stop(s:agda)
  let s:agda = v:null
endfun

fun! s:AgdaRestart(args)
  call s:StopAgdaInteraction()
  call s:StartAgdaInteraction(a:args)
endfun

fun! s:HandleAgdaErrMsg(chan, msg)
  echohl ErrorMsg
  echom msg
  echohl Normal
endfun

fun! s:HandleAgdaMsg(chan, msg)
  " This is only called when messages are not read from the corresponding
  " channel.
  if a:msg =~# '^JSON> '
    let msg = strpart(a:msg, 6)
  else
    let msg = a:msg
  endif
  try
    silent let output = json_decode(msg)
  catch /.*/
    echohl ErrorMsg
    echom msg
    echohl Normal
    return
  endtry
  if type(output) == 4
    if output["kind"] == "DisplayInfo"
      call s:HandleDisplayInfo(output)
    elseif output["kind"] == "GiveAction"
      call s:HandleGiveAction(output)
    elseif output["kind"] == "Status"
      let b:AgdaChecked = output["status"]["checked"]
    elseif output["kind"] == "RunningInfo"
      echohl WarningMsg
      for msg in split(output["message"], "\n")
	echom msg
      endfor
      echohl Normal
    elseif output["kind"] == "InteractionPoints"
      let b:AgdaInteractionPoints = output["interactionPoints"]
    elseif g:AgdaVimDebug
      echom "s:HandleAgdaMsg <" . string(msg) . ">"
    endif
  else
    if g:AgdaVimDebug
      echom "s:HandleAgdaMsg <" . string(msg) . ">"
    endif
  endif
endfun

fun! s:AgdaCommand(file, cmd)
  " TODO: process busy state
  if s:agda == v:null
    echoerr "agda is not running"
    return
  endif
  let chan = job_getchannel(s:agda)
  call ch_sendraw(
        \   chan
        \ , "IOTCM \""
            \ . fnameescape(a:file)
            \ . "\" None Direct "
            \ . a:cmd
            \ . "\n")
endfunc

fun! s:IsLiterateAgda()
  return expand("%:e") == "lagda"
endfun

" goals
let b:goals = []

fun! s:FindGoals()
  " Find all lines in which there is at least one goal
  let view = winsaveview()
  let ps   = [] " list of lines
  silent global /\v^(\s*--|\s*\{-|\s*-)@!.*(^\?|\s\?|\{\!.{-}\!\})/ :call add(ps, getpos(".")[1])
  if s:IsLiterateAgda()
    " filter out lines which are not indside code LaTeX environment
    let ps_ = []
    for l in ps
      call setpos(".", [0, l, 0, 0])
      if searchpair('\\begin{code}', '', '\\end{code}', 'bnW') == 0
	" not inside
	continue
      else
	call add(ps_, l)
      endif
    endfor
    let ps = ps_
  endif
  call winrestview(view)
  return ps
endfun

fun! EnumGoals(ps)
  " ps list of linue numbers with goals
  let ps_ = []
  for lnum in a:ps
    " todo: support for multiple goals in a single line
    let col = 0
    let subs = split(getline(lnum), '\ze\v((\s|^)\?(\s|$)|\{\!)')
    for sub in subs
      if col == 0 && sub =~ '^\v(\?|\{\!)'
	call add(ps_, [lnum, col + 1])
      endif
      let col += len(sub)
      if col >= len(getline(lnum))
	break
      endif
      call add(ps_, [lnum, col + 1])
    endfor
  endfor
  let b:goals = ps_
  return ps_
endfun

fun! s:FindAllGoals()
  " Find all goals and return their positions.
  return EnumGoals(s:FindGoals())
endfun

let s:efm_warning = '%f:%l%.%c-%m,%m'
let s:efm_error   = '%f:%l%.%c-%m,Failed%m,%m'

let b:AgdaChecked = v:false

let s:popup_options =
	  \ { "line": "cursor+1"
	  \ , "col":  "cursor"
	  \ , "pos": "topleft" 
	  \ , "close": "button"
	  \ , "border": [1,1,1,1]
	  \ , "padding": [0,1,0,1]
	  \ , "borderchars": ['─', '│', '─', '│', '┌', '┐', '┘', '└']
	  \ , "moved": "word"
	  \ }

" DisplayInfo message callback, invoked asyncronously by s:HandleAgdaMsg
fun! s:HandleDisplayInfo(info)
  let info = a:info["info"]
  let kind = info["kind"]
  let qflist = []
  if kind == "AllGoalsWarnings"
    let ps = s:FindAllGoals()
    let goals = split(get(info, "goals", ""), "\n")
    let n = 0
    for goal in goals
      let [lnum, col] = get(ps, n, [0, 0]) " this is terrible!
      call add(qflist,
	    \ { "bufnr": bufnr("")
	    \ , "filename": expand("%")
	    \ , "lnum": lnum
	    \ , "col":  col
	    \ , "text": goal
	    \ , "type": "G"
	    \ })
      let n+=1
    endfor
    " TODO
    " if the user changed buffers, the errors might end up in the wrong
    " quickfix list
    call setqflist(qflist, s:qf_append ? 'a' : 'r')
    call setqflist([], 'a',
	  \ { 'lines': split(get(info, "warnings", ""), "\n")
	  \ , 'efm': s:efm_warning
	  \ })
    call setqflist([], 'a',
	  \ { 'lines': split(get(info, "errors", ""), "\n")
	  \ , 'efm': s:efm_error
	  \ })
  elseif kind == "Error"
    call setqflist([], s:qf_append ? 'a' : 'r',
	  \ { 'lines': split(info["payload"], "\n")
	  \ , 'efm': s:efm_error
	  \ })
  elseif kind == "Auto"
    echohl WarningMsg
    echo info["payload"]
    echohl Normal
  elseif kind == "CurrentGoal" || kind == "Intro"
    echohl WarningMsg
    " remove new lines from s:AgdaGoalType output
    echom substitute(info["payload"], '\n', ' ', 'g')
    echohl Normal
  elseif kind == "Version"
    echohl WarningMsg
    echom info["version"]
    echohl Normal
  elseif kind == "WhyInScope"
    let opts = copy(s:popup_options)
    let opts["title"] = "Why in scope?"
    call popup_create(split(info["payload"], "\n"), opts)
  elseif kind == "Context"
    let opts = copy(s:popup_options)
    let opts["title"] = "Context"
    call popup_create(split(info["payload"], "\n"), opts)
  elseif kind == "InferredType"
    echohl WarningMsg
    echo info["payload"]
    echohl Normal
  elseif kind == "HighlightingInfo"
    echohl WarningMsg
    echo get(get(info, "info", {"payload": "NO INFO"}), "payload", "NO PAYLOAD")
    echohl Normal
  else
    if g:AgdaVimDebug
      echom "DisplayInfo " . json_encode(info)
    endif
  endif

  let s:qf_append = v:true

  " TODO
  " this is called by various commands, it's not always makes sense to re-open
  " quickfix list
  if s:qf_open
    if len(getqflist()) > 0
      copen
      wincmd p
      let s:qf_open = v:false
    else
      cclose
    endif
  endif
endfun

fun! s:HandleGiveAction(action)
  " Cmd_refine_or_intro
  " Assuming we are on the right interaction point
  echom a:action
  let result = a:action["giveResult"]
  if strpart(getline(line(".")), col(".") - 1)[0] == "?"
    exe "normal s" . result
  else
    exe "normal ca{" . result
  endif
endfun

fun! s:GoalContent()
  " guard that we are inside {! !}
  if searchpair('{!', '', '!}', 'bWn') == 0
    return ""
  endif
  let view = winsaveview()
  let x = @x
  silent normal "xya{
  call winrestview(view)
  let g = @x
  let @x = x
  return matchstr(g, '^{!\zs.*\ze!}$')
endfun

fun! s:AgdaLoad(bang, file)
  if a:bang == "!"
    update
  endif
  let s:qf_open   = v:true
  let s:qf_append = v:false

  if s:agda == v:null
    echoerr "agda is not running"
    return
  endif
  call s:AgdaCommand(a:file, "(Cmd_load \"" . fnameescape(a:file) . "\" [])")
endfun

fun! s:AgdaAbort(file)
  call s:AgdaCommand(a:file, "Cmd_abort")
endfun

fun! AgdaCompile(file, backend)
  " agda2-mode.el:840
  call s:AgdaCommand(a:file, "(Cmd_compile " . a:backend . " \"" . fnameescape(a:file) . "\" [])")
endfun

fun! s:AgdaAutoOne(file, args)
  let n = s:GetCurrentGoal()
  if n >= 0
    let goal = s:GoalContent()
    call s:AgdaCommand(a:file, "(Cmd_autoOne ".n." noRange \"".a:args." ".goal."\")")
  endif
endfun

fun! AgdaAutoAll(file)
  " agda2-mode.el:917
  " busy
  call s:AgdaCommand(a:file, "Cmd_autoAll")
endfun

fun! s:AgdaMetas(file)
  " agda2-mode.el:1096
  " busy
  call s:AgdaCommand(a:file, "Cmd_metas")
endfun

fun! s:AgdaConstraints(file)
  " agda2-mode.el:1096
  " busy
  call s:AgdaCommand(a:file, "Cmd_constraints")
endfun

fun! s:AtGoal()
  let [_, lnum, col, _] = getpos(".")
  let line = getline(".")
  if line[col - 1] == "?"
    return v:true
  else
    return searchpair('{!', '', '!}', 'bnW') != 0
  endif
endfun

fun! s:GetCurrentGoal()
  " Find current goal, this finds default to the previous goal.
  if !s:AtGoal()
    return -1
  endif
  let lnum = line(".")
  let col  = col(".")
  return len(filter(s:FindAllGoals(), {idx, val -> val[0] < lnum || val[0] == lnum && val[1] <= col })) - 1
endfun

fun! s:AgdaGoal(file)
  " agda2-mode.el:748
  " CMD <goal number> <goal range> <user input> args
  let n = s:GetCurrentGoal()
  if n >= 0
    " testing commands
    " https://github.com/banacorn/agda-mode/blob/master/src/Command.re
    let cmd = "(Cmd_solveOne " . n . " noRange)"
    echom cmd
    call s:AgdaCommand(a:file, cmd)
    let chan = job_getchannel(s:agda)
    let msg = ch_read(chan)
    echom msg
  endif
endfun

fun! s:AgdaGoalType(file)
  let n = s:GetCurrentGoal()
  if n >= 0
    let goal = s:GoalContent()
    let cmd = "(Cmd_goal_type Normalised " . n . " noRange \"".goal."\")"
    call s:AgdaCommand(a:file, cmd)
  endif
endfun

fun! s:AgdaInferToplevel(file, expr)
  let cmd = "(Cmd_infer_toplevel Normalised \"" . a:expr . "\")"
  call s:AgdaCommand(a:file, cmd)
endfun

fun! s:AgdaInfer(file)
  let n = s:GetCurrentGoal()
  if n >= 0
    let goal = s:GoalContent()
    let cmd = "(Cmd_goal_type Normalised " . n . " noRange \"".goal."\")"
    call s:AgdaCommand(a:file, cmd)
  else
    call s:AgdaInferToplevel(a:file, s:GetKeyword())
  endif
endfun

" fun! AgdaShowModuleContentsToplevel(file)
  " let cmd = "(Cmd_show_module_contents_toplevel Normalised \"\")"
  " call s:AgdaCommand(a:file, cmd)
" endfun

fun! s:AgdaShowVersion(file)
  let cmd = "Cmd_show_version"
  call s:AgdaCommand(a:file, cmd)
endfun

fun! s:AgdaWhyInScopeToplevel(file, str)
  let cmd = "(Cmd_why_in_scope_toplevel \"" . a:str . "\")"
  call s:AgdaCommand(a:file, cmd)
endfun

fun! s:AgdaWhyInScope(file, ...)
  if a:0 == 0
    echoerr "no arguments given"
    return
  elseif a:0 == 1
    let str = a:1
    let n   = s:GetCurrentGoal()
    if n < 0
      echoerr "not at a goal"
      return
    endif
  else
    let n   = a:1
    let str = a:2
  endif
  let cmd = "(Cmd_why_in_scope " . n . " noRange \""  . str . "\")"
  call s:AgdaCommand(a:file, cmd)
endfun

fun! s:AgdaRefine(file) 
  let n = s:GetCurrentGoal()
  if n >= 0
    let goal = s:GoalContent()
    let cmd = "(Cmd_refine " . n . " noRange \"".goal."\")"
    call s:AgdaCommand(a:file, cmd)
  endif
endfun

fun! s:AgdaContext(file)
  let n = s:GetCurrentGoal()
  if n >= 0
    let goal = s:GoalContent()
    let cmd = "(Cmd_context Normalised " . n . " noRange \"".goal."\")"
    call s:AgdaCommand(a:file, cmd)
  endif
endfun

fun! s:AgdaRefineOrIntro(file) 
  let n = s:GetCurrentGoal()
  if n >= 0
    let goal = s:GoalContent()
    let cmd = "(Cmd_refine_or_intro True " . n . " noRange \"".goal."\")"
    call s:AgdaCommand(a:file, cmd)
  endif
endfun

fun! AgdaCmdMakeCase(file)
  let n = s:GetCurrentGoal()
  if n >= 0
    let goal = s:GoalContent()
    let cmd = "(Cmd_make_case " . n . " noRange \"\")"
    call s:AgdaCommand(a:file, cmd)
  endif
endfun

" Cmd_why_in_scope index noRange content
" Cmd_why_in_scope_toplevel content

com! -buffer -bang    AgdaLoad     :call <SID>AgdaLoad("<bang>", expand("%:p"))
com! -buffer          AgdaMetas    :call <SID>AgdaMetas(expand("%:p"))
com! -buffer          AgdaAbort    :call <SID>AgdaAbort(expand("%:p"))
com! -buffer -nargs=? AgdaRestart  :call <SID>AgdaRestart(expand(<q-args>))
com! -buffer          AgdaVersion  :call <SID>AgdaShowVersion(expand("%:p"))
com! -buffer          AgdaGoalType :call <SID>AgdaGoalType(expand("%:p"))
com! -buffer          AgdaRefine   :call <SID>AgdaRefineOrIntro(expand("%:p"))
com! -buffer -nargs=* AgdaAuto     :call <SID>AgdaAutoOne(expand("%:p"), expand(<q-args>))
com! -buffer -nargs=? AgdaInfer    :call <SID>AgdaInferToplevel(expand("%:p"), expand(<q-args>))
" com! -buffer          AgdaToggleImplicitArgs
"      \ :call s:AgdaCommand(expand("%:p"), "ToggleImplicitArgs")
com! -buffer          AgdaStart    :call <SID>StartAgdaInteraction(g:AgdaArgs)
com! -buffer          AgdaStop     :call <SID>StopAgdaInteraction()
com! -buffer -nargs=? AgdaWhyInScope :call <SID>AgdaWhyInScope(expand("%:p"), expand(<q-args>))

" maps
nm <buffer> <silent> <LocalLeader>l :<c-u>AgdaLoad!<cr>
nm <buffer> <silent> <localLeader>t :<c-u>call <SID>AgdaInfer(expand("%:p"))<cr>
nm <buffer> <silent> <LocalLeader>r :<c-u>AgdaRefine<cr>
nm <buffer> <silent> <LocalLeader>a :<c-u>AgdaAuto<cr>
nm <buffer> <silent> <LocalLeader>s :<c-u>call <SID>AgdaWhyInScopeToplevel(expand("%:p"), <SID>GetKeyword())<cr>
nm <buffer> <silent> <LocalLeader>c :<c-u>call <SID>AgdaContext(expand("%:p"))<cr>

" start `agda --interaction-json`; if you need to start with different
" arguments you can use, or set g:AgdaArgs
" ```
" s:AgdaRestart --termination-depth=2
" ```
call s:StartAgdaInteraction(g:AgdaArgs)
