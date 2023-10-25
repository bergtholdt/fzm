set -o magicequalsubst

# Todo:
# comment
# any command 
# short cut name or path hierarchy

# Define a regular expression for matching URLs
__url_regex='^(http|https):\/\/[a-zA-Z0-9\-\.]+(\.[a-zA-Z]{2,})?(:[0-9]{1,5})?(\/.*)?$'
__cmd_regex='^!.*$'


function __fzm_select_multi()
{
    setopt localoptions pipefail no_aliases 2> /dev/null
    local opts="--reverse --exact --no-sort --cycle --height ${FZF_TMUX_HEIGHT:-80%} $FZF_DEFAULT_OPTS"
    __fzm_decorate | FZF_DEFAULT_OPTS="$@ ${opts}" fzf | awk '{$(NF--)=""; print}' | awk '{$(NF--)=""; print}'
}

function __fzm_select_directories()
{
    setopt localoptions pipefail no_aliases 2> /dev/null
    local opts="--reverse --exact --no-sort --cycle --height ${FZF_TMUX_HEIGHT:-80%} --preview-window='right,50%,border-left' --preview 'lsd --tree --depth 3 --color=always {1}' $FZF_DEFAULT_OPTS"
    __fzm_decorate | FZF_DEFAULT_OPTS="$@ ${opts}" fzf | awk '{ print $1 }'
}

function __fzm_select_files()
{
    setopt localoptions pipefail no_aliases 2> /dev/null
    local opts="--reverse --exact --no-sort --cycle --height ${FZF_TMUX_HEIGHT:-80%} --preview 'bat --theme=gruvbox-dark --color=always --tabs=2 --wrap=auto --style=full --decorations=always {1}' $FZF_DEFAULT_OPTS"
    __fzm_decorate | FZF_DEFAULT_OPTS="$@ ${opts}" fzf | awk '{ print $1 }'
}

function __fzm_select_with_query()
{
    setopt localoptions pipefail no_aliases 2> /dev/null
    local opts="--reverse --exact --no-sort --cycle --height ${FZF_TMUX_HEIGHT:-80%} $FZF_DEFAULT_OPTS"
    __fzm_decorate | FZF_DEFAULT_OPTS="${opts}" fzf -q "$@" -1 -0 | awk '{ print $1 }'
}

function __fzm_filter_urls()
{
    while read line
    do
        if  [[ $line =~ $__url_regex ]]; then
            echo $line
        fi
    done
}

function __fzm_filter_commands()
{
    while read line
    do
        if  [[ $line =~ $__cmd_regex ]]; then
            echo ${line}
        fi
    done
}

function __fzm_filter_files()
{
    local home=~
    while read line
    do
        local lline=${line/#\~/$home}
        if [ -f $lline ]; then
            echo $lline
        fi
    done
}

function __fzm_filter_dirs()
{
    local home=~
    while read line
    do
        local lline=${line/#\~/$home}
        if [ -d $lline ]; then
            echo $lline
        fi
    done
}

function __fzm_decorate()
{
    local home=~
    while read line
    do
        local arg="${line/( ##\#?##)}"
        local comment="${line/(?##\# ##)}"
        if [[ $comment == $arg ]]; then
            comment=" "
        fi
        if [ ! -z "$arg" ];then
            lline=${arg/#\~/$home}
            if [ -d "$lline" ]; then
                echo "$arg" "	" "[d]" "	" "$comment"
            elif [ -f "$lline" ]; then
                echo "$arg" "	" "[f]" "	" "$comment"
            elif  [[ $arg =~ $__url_regex ]]; then
                echo "$arg" "	" "[u]" "	" "$comment"
            elif  [[ $arg =~ $__cmd_regex ]]; then
                echo "${arg[2,-1]}" "	" "[c]" "	" "$comment"
            fi
        fi
    done | column -t -s "$(printf '\t')"
}

function __fzm_filter_non_existent()
{
    local home=~
    while read line
    do
        local lline=$(echo $line | __fzm_decorate)
        if [ -n "${lline}" ];then
            echo "$line"
        fi
    done
}

function __fzm_check_regex()
{
    local command="$1"
    local regex="$2"
    shift 2
    for arg in "$@"
    do
        if ! [[ "$arg" =~ "$regex" ]]; then
            echo "Invalid Argument for command ${command}: '${arg}'"
            return 1
        fi
    done
}

function __fzm_add_items_to_file()
{
    for var in "${@:2}"
    do
        local item=${var:A}
        if [ ! -e "$item" ] && [ ! -d "$item" ]; then
            echo "$item" does not exist!
            return 1
        fi
        echo "$item" >> "$1"
        echo "$item" added!
    done
    local contents=$(cat "$1")
    echo "$contents" | awk '!a[$0]++' > "$1"
}

function __fzm_cleanup()
{
    local old_length=$(wc -l "$1" | cut -d\  -f 1)
    local contents=$(cat "$1")
    echo "$contents" | awk '!a[$0]++' | __fzm_filter_non_existent > $1
    local new_length=$(wc -l "$1" | cut -d\  -f 1)
    echo "removed" $(( $old_length - $new_length)) "entries"
}

usage="$(basename "$0") [-h] <command> [opts] -- fuzzy marks

commands:

list [--files] [--dirs] [--urls] [--cmd]   list bookmarks
add <path> [paths...]                      bookmark items
select [--files] [--dirs] 
       [--urls] [--cmd] [--multi]          select bookmark(s) and print selection to sdtout
query <pattern>                            Query bookmark matching <pattern> and print match to stdout. Selection menu will open if match is ambiguous.
edit                                       edit bookmarks file
open                                       select bookmark(s) and open
exec                                       select command(s) and execute
fix                                        remove bookmarked that no longer exist (do not use if you use the same bookmarks on other machines)
clear                                      clear all bookmarks

options:

-h,--help                                  show help
--files                                    restrict to files only
--dirs                                     restrict to dirs only
--urls                                     restrict to urls only
--cmd                                      restrict to commands only
--multi                                    allow multiple selection of items

keybindings:

Ctrl+P                                     Select a bookmarked directory and jump to it
Ctrl+O                                     Select one or multiple bookmarks and insert them into the current command line

ENV configuration:

FZM_NO_BINDINGS                            Disabled creation of bindings
FZM_BOOKMARKS_FILE                         Bookmarks file. Defaults to '~/.fzm.txt'
"

function set_bookmarks_file()
{
    [[ -n "${FZM_BOOKMARKS_FILE+x}" ]] && local bookmarks_file="$FZM_BOOKMARKS_FILE" || local bookmarks_file="${HOME}/.fzm.txt"

    if [ ! -e "$bookmarks_file" ]; then
        touch "$bookmarks_file" &> /dev/null
    fi

    if [ ! -f "$bookmarks_file" ]; then
        printf "FZM failed to create a bookmarks file.\n\n FZM_BOOKMARKS_FILE is currently set to '${FZM_BOOKMARKS_FILE}' if the FZM_BOOKMARKS_FILE is variable has been set it has likely not been done correctly, the path does not exists, the variable is not exported, or the fzm cannot access the set directory. See fzm --help for more information.\n"
        return 1
    fi

    echo $bookmarks_file
}

function fzm()
{
    bookmarks_file=$(set_bookmarks_file)
    case "$1" in
        'list')
            __fzm_check_regex "$1" '(--files|--dirs|--urls|--cmd)' "${@:2}" || return 1
            if [[ $* == *--files* ]]; then
                cat "$bookmarks_file" | __fzm_filter_files | __fzm_decorate
            elif [[ $* == *--dirs* ]]; then
                cat "$bookmarks_file" | __fzm_filter_dirs | __fzm_decorate
            elif [[ $* == *--urls* ]]; then
                cat "$bookmarks_file" | __fzm_filter_urls | __fzm_decorate
            elif [[ $* == *--cmd* ]]; then
                cat "$bookmarks_file" | __fzm_filter_commands | __fzm_decorate
            else
                cat "$bookmarks_file" | __fzm_decorate
            fi
            ;;
        'select')
            __fzm_check_regex "$1" '(--multi|--files|--dirs|--urls|--cmd)' "${@:2}" || return 1
            [[ $* == *--multi* ]] && local multi="-m"
            if [[ $* == *--files* ]]; then
                cat "$bookmarks_file" | __fzm_filter_files | __fzm_select_files "${multi}"
            elif [[ $* == *--dirs* ]]; then
                cat "$bookmarks_file" | __fzm_filter_dirs | __fzm_select_directories "${multi}"
            elif [[ $* == *--urls* ]]; then
                cat "$bookmarks_file" | __fzm_filter_urls | __fzm_select_multi "${multi}"
            elif [[ $* == *--cmd* ]]; then
                cat "$bookmarks_file" | __fzm_filter_commands | __fzm_select_multi "${multi}"
            else
                cat "$bookmarks_file" | __fzm_select_multi "${multi}"
            fi
            ;;
        'add')
            echo "Added to: $bookmarks_file"
            __fzm_add_items_to_file "$bookmarks_file" "${@:2}" || return 1
            ;;
        'query')
            if [[ "$2" == "--files" ]]; then
                cat "$bookmarks_file" | __fzm_filter_files | __fzm_select_with_query "${@:3}"
            elif [[ "$2" == "--dirs" ]]; then
                cat "$bookmarks_file" | __fzm_filter_dirs | __fzm_select_with_query "${@:3}"
            elif [[ "$2" == "--urls" ]]; then
                cat "$bookmarks_file" | __fzm_filter_urls | __fzm_select_with_query "${@:3}"
            elif [[ "$2" == "--cmd" ]]; then
                cat "$bookmarks_file" | __fzm_filter_commands | __fzm_select_with_query "${@:3}"
            else
                cat "$bookmarks_file" | __fzm_select_with_query "$2"
            fi
            ;;
        'open')
            __fzm_check_regex "$1" '(--multi|--files|--dirs|--urls)' "${@:2}" || return 1
            [[ $* == *--multi* ]] && local multi="-m"
            if [[ $* == *--files* ]]; then
                opener $(cat "$bookmarks_file" | __fzm_filter_files | __fzm_select_files "${multi}")
            elif [[ $* == *--dirs* ]]; then
                opener $(cat "$bookmarks_file" | __fzm_filter_dirs | __fzm_select_directories "${multi}")
            elif [[ $* == *--urls* ]]; then
                opener $(cat "$bookmarks_file" | __fzm_filter_urls | __fzm_select_multi "${multi}")
            else
                opener $(cat "$bookmarks_file" | __fzm_select_multi "${multi}")
            fi
            ;;
        'exec')
            cmd=$(cat "$bookmarks_file" | __fzm_filter_commands | __fzm_select_multi) && eval "$cmd"
            ;;
        'fix')
            ! [[  -z "${@:2}" ]] && echo "Invalid option '${@:2}' for '$1'" && return 1
            __fzm_cleanup "$bookmarks_file"
            ;;
        'clear')
            ! [[  -z "${@:2}" ]] && echo "Invalid option '${@:2}' for '$1'" && return 1
            echo "" > "$bookmarks_file"
            echo "bookmarks deleted!"
            ;;
        'edit')
            ! [[  -z "${@:2}" ]] && echo "Invalid option '${@:2}' for '$1'" && return 1
            ${EDITOR:-vim} "$bookmarks_file"
            ;;
        'help')
            echo "$usage" >&2
            ;;
        *)
            echo "$usage" >&2
            echo "Unknown command $1"
            ;;
    esac
}

#######################################################################
# CTRL-O - insert bookmark
function __fzm_append_to_prompt()
{
    if [[ -z "$1" ]]; then
        zle reset-prompt
        return 0
    fi
    LBUFFER="${LBUFFER}$(echo "$1" | tr '\r\n' ' '| sed -e 's/\s$//')"
    local ret=$?
    zle reset-prompt
    return $ret
}
function fzm-insert-bookmark()
{
    __fzm_append_to_prompt "$(fzm select --multi)"
}
zle     -N    fzm-insert-bookmark
if [[ -z $FZM_NO_BINDINGS ]]; then
    bindkey '^o' fzm-insert-bookmark
    bindkey -M vicmd '^o' fzm-insert-bookmark
fi

#######################################################################
# CTRL-B - cd into bookmarked directory
function fzm-cd-to-bookmark() {
local dir=$(fzm select --dirs)
if [[ -z "$dir" ]]; then
    zle redisplay
    return 0
fi
local ret=$?
zle reset-prompt
BUFFER="cd $dir"
zle accept-line
return $ret
}
zle     -N    fzm-cd-to-bookmark
if [[ -z $FZM_NO_BINDINGS ]]; then
    bindkey '^b' fzm-cd-to-bookmark
    bindkey -M vicmd '^b' fzm-cd-to-bookmark
fi

#######################################################################
# f - jump to directory with query
function f()
{
    home=~
    if [ -z "$@" ]; then
        local dir=$(fzm select --dirs)
    else
        local dir=$(fzm query --dirs "$@")
    fi
    if [[ -z "$dir" ]]; then
        return 0
    fi
    dir=${dir/#\~/$home}
    cd "$dir"
}

"$@"
