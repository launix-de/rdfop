" Vim syntax file
" Language: Turtle (RDF .ttl)
" Description: Basic highlighting for RDF Turtle syntax

if exists("b:current_syntax")
  finish
endif

syntax case match

" Comments (# ... end of line)
syn match ttlComment "#.*$"

" Directives and SPARQL-style equivalents
syn match   ttlDirective "@\(prefix\|base\|keywords\)\>"
syn keyword ttlDirective PREFIX BASE

" Abbreviated predicate keyword
syn keyword ttlKeyword a

" Booleans
syn keyword ttlBoolean true false

" Escape sequences (for strings and IRIs)
syn match ttlEchar  "\\[tbnrf\"'\\]" contained
syn match ttlEscape "\\u\x\{4}\|\\U\x\{8}" contained
syn match ttlPctEsc "%\x\x" contained

" Strings: single, double, and triple quoted
syn region ttlString start=+"""+ end=+"""+ keepend contains=ttlEchar,ttlEscape,ttlPctEsc
syn region ttlString start=+'''+ end=+'''+ keepend contains=ttlEchar,ttlEscape,ttlPctEsc
syn region ttlString start=+"+  skip=+\\\"+ end=+"+  oneline contains=ttlEchar,ttlEscape,ttlPctEsc
syn region ttlString start=+'+  skip=+\\'+  end=+'+  oneline contains=ttlEchar,ttlEscape,ttlPctEsc

" Language tags following strings (e.g., @en, @en-US)
syn match ttlLangTag "@[A-Za-z]\{2,}\(-[A-Za-z0-9]\+\)*"

" IRIs: <...>
syn region ttlIri start="<" end=">" contains=ttlEscape,ttlPctEsc

" QNames / Prefixed names
syn match ttlQName "\<[A-Za-z][A-Za-z0-9_-]*:[A-Za-z0-9][A-Za-z0-9._-]*\>"
syn match ttlQName "\<:[A-Za-z0-9][A-Za-z0-9._-]*\>"

" Blank node identifiers
syn match ttlBlank "_:[A-Za-z][A-Za-z0-9._-]*"

" Numbers: integer, decimal, double
syn match ttlNumber "\<-\=\d\+\>"
syn match ttlNumber "\<-\=\d\+\.\d*\>"
syn match ttlNumber "\<-\=\d\+\(\.\d*\)\=[eE][+-]\=\d\+\>"

" Datatype operator (^^) and punctuation
syn match ttlOperator "\^\^"
syn match ttlPunct    "[;,.()\[\]{}]"

" Highlight links
hi def link ttlComment   Comment
hi def link ttlDirective PreProc
hi def link ttlKeyword   Statement
hi def link ttlBoolean   Boolean
hi def link ttlString    String
hi def link ttlEchar     SpecialChar
hi def link ttlEscape    SpecialChar
hi def link ttlPctEsc    SpecialChar
hi def link ttlIri       Type
hi def link ttlQName     Identifier
hi def link ttlBlank     Identifier
hi def link ttlNumber    Number
hi def link ttlLangTag   SpecialComment
hi def link ttlOperator  Operator
hi def link ttlPunct     Delimiter

let b:current_syntax = "ttl"

