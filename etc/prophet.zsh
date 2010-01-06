#compdef prophet sd

typeset -a prophet_completions
prophet_completions=($($words[1] _gencomp $words[2,-1]))
compadd $prophet_completions

