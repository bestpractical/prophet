function _prophet_()
{
    COMPREPLY=($($1 _gencomp ${COMP_WORDS[COMP_CWORD]}))
}

complete -F _prophet_ myprophetapp
