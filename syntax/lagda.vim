if version < 600
  syn clear
elseif exists("b:current_syntax")
  finish
endif

syn include @lagdaRegion syntax/agda.vim
syn match lagdaBeginCode /\\begin{code}/ contained
syn match lagdaEndCode /\\end{code}/ contained
syn region lagdaCode start=+\\begin{code}+ end=+\\end{code}+ contains=lagdaBeginCode,lagdaEndCode,@lagdaRegion,endCode nextgroup=@agdaRegion keepend
syn match lagdaInlineCode /`.*`/ contains=@lagdaRegion
syn region lagdaTitle start="^#"      end="$" keepend oneline

hi default link lagdaBeginCode  Statement
hi default link lagdaEndCode    Statement
hi default link lagdaTitle      Title

let b:current_syntax="lagda"
syntax sync minlines=250
