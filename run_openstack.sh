#! /bin/sh
#
# This is an example script of how to semi-automate use of
# `os-update-images`: first use the Ansible playbook to update images,
# then use the `openstack` command (together with some shell glue) to
# spawn new VMs from the newly-created images and check that they can
# run basic Linux commands.
#
me="$(basename $0)"

# first, rename old images:
#
#     (sc admin; o image list --public | fgrep '***' | cut -d'|' -f2,3 | (while read uuid bar name; do o image set $uuid --name "$(echo $name | tr -d '*')"; done))


usage () {
cat <<EOF
Usage: $me [-c CONFIG_FILE] [-n NETWORK] [-k KEYPAIR]

Update VM images on an OpenStack cloud.

Environment variables with the contact and authentication parameters
for OpenStack should have already been loaded in the environment by
sourcing the "openrc" file.

Options:

  --help, -h             Print this help text.
  --config, -c FILENAME  Use this configuration file; default: 'conf.yml'
  --network, -n NETNAME  Attach auxiliary VMs to this OpenStack network
                         (name or ID).  If omitted, try to read network
                         name from config file.
  --keypair, -k NAME     Authorize this OpenStack keypair to log into
                         the auxiliary VMs.
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

short_opts='c:hk:n:'
long_opts='config:,help,keypair:,network:'

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

while [ $# -gt 0 ]; do
    case "$1" in
        -c|--config) shift; conf="$1";;
        -h|--help) usage; exit 0 ;;
        -k|--keypair) shift; keypair="$1";;
        -n|--network) shift; net_id="$1";;
        --) shift; break ;;
    esac
    shift
done


## main

require_command ansible-playbook
require_command openstack

if [ -z "$conf" ]; then
    conf='conf.yml'
fi
if ! [ -r "$conf" ]; then
    die $EX_NOINPUT "Cannot read configuration file '$conf'."
fi

if [ -z "$net_id" ]; then
    net_id=$(egrep '^network:' "$conf" | cut -d: -f2- | sed -e 's/^ *//')
    warn "No network name or ID was specified, using network name '$net_id'."
fi

if [ -z "$keypair" ]; then
    keypair=$LOGNAME
    warn "No keypair name was specified, using '$keypair'."
fi

set -e
ansible-playbook -v main.yml \
                 -e conf="$conf" \
                 -e keypair="${keypair}" \
                 -e prefix=""'*** '""

#openstack image list --private \
openstack image list \
    | fgrep ' ***' \
    | tr -d '|' \
    | (while read uuid name _ ; do
           openstack server create \
                     --wait \
                     --image $uuid \
                     --flavor m1.small \
                     --key-name "$keypair" \
                     --nic net-id="$net_id" \
                     test-$uuid;
       done)

# this is necessary since `IFS='|' read ...`
# won't strip leading and trailing spaces
trim () { echo "$@" | sed -e 's/^ *//;s/ *$//;'; }

# `openstack` always lists fields in some internally-specified order,
# instead of the one used in the command line
openstack server list -c ID -c Name -c Networks -c Image \
    | fgrep ' test-' \
    | (while IFS='|' read _ uuid name nets image; do
           image=$(trim "$image");
           ipv4_addr=$(echo "$nets"| egrep -o '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+');
           name=$(trim "$name");
           uuid=$(trim "$uuid");
           set +e
           echo "=== $image ===";
           case "$image" in
               *Ubuntu*) u=ubuntu;;
               *Debian*) u=debian;;
               *CentOS*) u=centos;;
           esac;
           set -x;
           ssh -n \
               -o UserKnownHostsFile=/dev/null \
               -o StrictHostKeyChecking=no \
               "$u@$ipv4_addr" lsb_release -a;
           set +x;
           openstack server delete $uuid;
       done)

cat <<__EOF__
All images have been updated.

Remember to publish the updated images by running

    openstack image set --public --project admin

on all the newly-created images.

__EOF__
