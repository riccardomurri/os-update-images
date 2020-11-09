#! /bin/sh
#
# This is an example script of how to semi-automate use of
# `sc-update-images`: first use the Ansible playbook to update images,
# then use the `openstack` command (together with some shell glue) to
# spawn new VMs from the newly-created images and check that they can
# run basic Linux commands.
#

# first, rename old images:
#
#     (sc admin; o image list --public | fgrep '***' | cut -d'|' -f2,3 | (while read uuid bar name; do o image set $uuid --name "$(echo $name | tr -d '*')"; done))

KEYNAME=$1
[ -z "$KEYNAME" ] && KEYNAME=$LOGNAME

[ $OS_PROJECT_NAME = 's3it.uzh' ] || { 
    echo "You have '$OS_PROJECT_NAME' credential loaded."
    echo "Please exit and load 's3it.uzh' project credentials."
    echo "Type 'sure' and hit enter to continue with current credentials"
    echo "or just enter to exit"
    read res
    [ "$res" = "sure" ] || exit 1
}

set -e
ansible-playbook main.yml -e keypair="${KEYNAME}" -e prefix=""'*** '""

openstack image list --private \
    | fgrep ' ***' \
    | tr -d '|' \
    | (while read uuid name _ ; do
           openstack server create \
                     --wait \
                     --image $uuid \
                     --flavor 1cpu-4ram-hpc \
                     --key-name $KEYNAME \
                     --nic net-id=uzh-only \
                     test-$uuid;
       done)

openstack server list \
    | fgrep ' test-' \
    | tr -d '|' \
    | tr -d '*' \
    | (while read uuid name _ net image; do
           set +e
           echo === $image ===;
           ip_addr=$(echo $net | cut -d= -f2);
           case "$image" in
               *Ubuntu*) u=ubuntu;;
               *Debian*) u=debian;;
               *CentOS*) u=centos;;
               
           esac;
           set -x;
           ssh -n \
               -o UserKnownHostsFile=/dev/null \
               -o StrictHostKeyChecking=no \
               $u@$ip_addr lsb_release -a;
           set +x;
           openstack server delete $uuid;
       done)

# at end, publish images::
#
#     openstack image set --public --project admin
#
