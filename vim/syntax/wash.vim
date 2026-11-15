" This file was created by an agent.
" Vim syntax file
" Language: wash (indentation-based WebAssembly text format for ./wash)

if exists("b:current_syntax")
  finish
endif

syn case match

" Comments
syn keyword washTodo     contained TODO FIXME XXX NOTE
syn match   washComment  "#.*$" contains=washTodo,@Spell

" Top-level declarations
syn keyword washDecl     import export nextgroup=washImportName,washFuncName skipwhite
syn match   washImportName "\<\w\+\.\w\+\ze\s*(" contained
syn match   washFuncName   "\<\w\+\ze\s*(" contained
" Unexported function definitions start at column 0
syn match   washFuncDef    "^\h\w*\ze\s*("

" Value types
syn match   washType     "\<\%(i32\|i64\|f32\|f64\|v128\|funcref\|externref\)\>\.\@!"

" Numbers
syn match   washNumber   "\<-\?\d[0-9_]*\>"
syn match   washNumber   "\<-\?0x[0-9a-fA-F_]\+\>"
syn match   washFloat    "\<-\?\d[0-9_]*\.\d[0-9_]*\%([eE][-+]\?\d\+\)\?\>"

" Punctuation
syn match   washArrow    "->"
syn match   washDelim    "[(),:]"

hi def link washTodo        Todo
hi def link washComment     Comment
hi def link washDecl        Keyword
hi def link washImportName  Function
hi def link washFuncName    Function
hi def link washFuncDef     Function
hi def link washType        Type
hi def link washNumber      Number
hi def link washFloat       Float
hi def link washArrow       Operator
hi def link washDelim       Delimiter

let b:current_syntax = "wash"
