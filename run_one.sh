#! /bin/sh
#
# This is an example script of how to semi-automate use of
# `os-update-images`: first set up HTTP for the ONE server to
# download image files from the local directory, then use the
# Ansible playbook to update images.
#
me="$(basename $0)"

usage () {
cat <<EOF
Usage: $me [-c CONF_FILE] [-n NETWORK] [-k KEYPAIR]

Update VM images on an OpenNebula cloud.

Environment variables with the contact and authentication parameters
for OpenNebula should have already been loaded in the environment by
setting variables ONE_XMLRPC, ONE_USERNAME, and ONE_PASSWORD.

Options:

  --config, -c FILENAME
      Use this configuration file; default: 'conf.yml'

  --help, -h
      Print this help text.

  --keypair, -k NAME
      Authorize this ONE keypair to log into the auxiliary VMs.

  --no-http-forwarding, -n
      Do *not* set up HTTP forwarding to local directory.
      Use this if you have already arranged for files in the current
      working directory to be available at the URL given by option
      '--one-download-url'.

  --one-download-url, -u URL
      The ONE server will pull image files from this URL.
      Unless option '-n'/'--no-http-forwarding' is given, this script
      will log in via SSH to the server at this URL and set up forwarding
      of remote port 80 to a local http server; this requires that
      you can SSH to the remote machine as 'root'.
EOF
}


## helper functions

# see /usr/include/sysexit.h
EX_OK=0           # successful termination
EX_USAGE=1        # command line usage error
EX_DATAERR=65     # data format error
EX_NOINPUT=66     # cannot open input
EX_NOUSER=67      # addressee unknown
EX_NOHOST=68      # host name unknown
EX_UNAVAILABLE=69 # service unavailable
EX_SOFTWARE=70    # internal software error
EX_OSERR=71       # system error (e.g., can't fork)
EX_OSFILE=72      # critical OS file missing
EX_CANTCREAT=73   # can't create (user) output file
EX_IOERR=74       # input/output error
EX_TEMPFAIL=75    # temp failure; user is invited to retry
EX_PROTOCOL=76    # remote error in protocol
EX_NOPERM=77      # permission denied
EX_CONFIG=78      # configuration error


have_command () {
    command -v "$1" >/dev/null 2>/dev/null
}

if have_command tput; then

    TXT_NORMAL=$(tput sgr0)

    TXT_BOLD=$(tput bold)
    TXT_DIM=$(tput dim)
    TXT_STANDOUT=$(tput smso)

    TXT_BLACK=$(tput setaf 0)
    TXT_BLUE=$(tput setaf 4)
    TXT_CYAN=$(tput setaf 6)
    TXT_GREEN=$(tput setaf 2)
    TXT_MAGENTA=$(tput setaf 5)
    TXT_RED=$(tput setaf 1)
    TXT_WHITE=$(tput setaf 7)
    TXT_YELLOW=$(tput setaf 3)
    TXT_NOCOLOR=$(tput op)

    # usage: with_color COLOR TEXT...
    with_color () {
        local color="$1";
        shift;

        local pre="${TXT_NOCOLOR}";
        local post="${TXT_NOCOLOR}";

        case "$color" in
            bold*) pre="${TXT_BOLD}";;
            dim*) pre="${TXT_DIM}";;
            standout*) pre="${TXT_STANDOUT}";;
        esac

        case "$color" in
            *black)       pre="${pre}${TXT_BLACK}";;
            *blue)        pre="${pre}${TXT_BLUE}";;
            *cyan)        pre="${pre}${TXT_CYAN}";;
            *green)       pre="${pre}${TXT_GREEN}";;
            *magenta)     pre="${pre}${TXT_MAGENTA}";;
            *red)         pre="${pre}${TXT_RED}";;
            *white)       pre="${pre}${TXT_WHITE}";;
            *yellow)      pre="${pre}${TXT_YELLOW}";;
            none|nocolor) pre="${TXT_NOCOLOR}";;
        esac

        echo -n "${pre}"; echo -n "$@"; echo "${post}";
    }

else

    TXT_NORMAL=''

    TXT_BOLD=''
    TXT_DIM=''
    TXT_STANDOUT=''

    TXT_BLACK=''
    TXT_BLUE=''
    TXT_CYAN=''
    TXT_GREEN=''
    TXT_MAGENTA=''
    TXT_RED=''
    TXT_WHITE=''
    TXT_YELLOW=''
    TXT_NOCOLOR=''

    # ignore any color spec; just echo
    with_color() {
        shift; echo "$@";
    }

fi

die () {
  rc="$1"
  shift
  (
      echo -n "${TXT_BOLD}$me: ${TXT_RED}ERROR:${TXT_NOCOLOR} ";
      if [ $# -gt 0 ]; then echo "$@"; else cat; fi
      echo -n "${TXT_NORMAL}"
  ) 1>&2
  exit $rc
}

warn () {
    (
        echo -n "$me: ${TXT_YELLOW}WARNING:${TXT_NOCOLOR} ";
        if [ $# -gt 0 ]; then echo "$@"; else cat; fi
    ) 1>&2
}

require_command () {
  if ! have_command "$1"; then
    die 1 "Could not find required command '$1' in system PATH. Aborting."
  fi
}

is_absolute_path () {
    expr match "$1" '/' >/dev/null 2>/dev/null
}


## parse command-line

short_opts='c:hk:nu:'
long_opts='config:,help,keypair:,no-http-forwarding,one-download-url:'

# test which \`getopt\` version is available:
# - GNU \`getopt\` will generate no output and exit with status 4
# - POSIX \`getopt\` will output \`--\` and exit with status 0
getopt -T > /dev/null
rc=$?
if [ "$rc" -eq 4 ]; then
    # GNU getopt
    args=$(getopt --name "$me" --shell sh -l "$long_opts" -o "$short_opts" -- "$@")
    if [ $? -ne 0 ]; then
        die 1 "Type '$me --help' to get usage information."
    fi
    # use 'eval' to remove getopt quoting
    eval set -- $args
else
    # old-style getopt, use compatibility syntax
    args=$(getopt "$short_opts" "$@")
    if [ $? -ne 0 ]; then
        die 1 "Type '$me --help' to get usage information."
    fi
    set -- $args
fi

http_forwarding='yes'
while [ $# -gt 0 ]; do
    case "$1" in
        -c|--config) shift; conf="$1";;
        -h|--help) usage; exit 0 ;;
        -k|--keypair) shift; keypair="$1";;
        -n|--no-http-forwarding) http_forwarding='no';;
        -u|--one-download-url) shift; one_download_url="$1";;
        --) shift; break ;;
    esac
    shift
done


## main

require_command ansible-playbook
require_command oneimage
require_command onetemplate
require_command onevm
require_command python3
require_command ssh

if [ -z "$conf" ]; then
    conf='conf.yml'
fi
if ! [ -r "$conf" ]; then
    die 1 "Cannot read configuration file '$conf'."
fi

if [ -z "$keypair" ]; then
    keypair=$LOGNAME
    warn "No keypair name was specified, using '$keypair'."
fi

if [ -z "$ONE_URL" ]; then
    die $EX_USAGE "Environment variable ONE_URL should be set to the URL of ONE's XML-RPC server; e.g., ONE_URL='http://localhost:2633/RPC2'"
fi

if [ -z "$ONE_USERNAME" ]; then
    if [ -r "${ONE_AUTH:-$HOME/.one/one_auth}" ]; then
        warn "Env var ONE_USERNAME is not set; reading ONE user name from file '${ONE_AUTH:-$HOME/.one/one_auth}'"
        export ONE_USERNAME=$(cat "${ONE_AUTH:-$HOME/.one/one_auth}" | cut -d: -f1)
    else
        die $EX_USAGE "Environment variable ONE_USERNAME should be set to the user name to authenticate to ONE server with."
    fi
fi

if [ -z "$ONE_PASSWORD" ]; then
    if [ -r "${ONE_AUTH:-$HOME/.one/one_auth}" ]; then
        warn "Env var ONE_PASSWORD is not set; reading ONE password from file '${ONE_AUTH:-$HOME/.one/one_auth}'"
        export ONE_PASSWORD=$(cat "${ONE_AUTH:-$HOME/.one/one_auth}" | cut -d: -f2)
    else
        die $EX_USAGE "Environment variable ONE_PASSWORD should be set to the password for ONE user '$ONE_USERNAME'."
    fi
fi

set -e

if [ $http_forwarding = 'yes' ]; then
    if [ -z "$one_download_url" ]; then
        die 1 "No download URL specified; please re-run this script adding option '-u'."
    fi

    # we know python is available, use it to parse URL
    host=$(python3 -c "from urllib.parse import urlsplit; print(urlsplit('${one_download_url}').netloc.split(':')[0])")
    port=$(python3 -c "from urllib.parse import urlsplit; print(urlsplit('${one_download_url}').port or 80)")

    if [ "$host" = $(hostname -f) ] || [ "$host" = $(hostname -s) ]; then
        # start http server to serve contents of local directory
        python3 -m http.server --bind 0.0.0.0 $port &
        children="$!"
    else
        # start http server to serve contents of local directory
        python3 -m http.server --bind localhost 8000 &
        children="$!"

        # forward remote HTTP traffic to local server
        ssh -n -N -R :$port:localhost:8000 "root@$host" &
        children="$! $children"
    fi

    trap 'kill $children;' EXIT INT ABRT QUIT TERM
fi

# run playbook
ansible-playbook -v main.yml \
                 -e conf="$conf" \
                 -e keypair="${keypair}" \
                 -e prefix="" \
                 -e one_download_url="$one_download_url"


cat <<__EOF__
All images have been updated.
__EOF__
