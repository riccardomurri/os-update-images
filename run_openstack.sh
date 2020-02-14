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

net_id="$1"
if [ -z "$net_id" ]; then
    net_id='private'
    echo 1>&2 "NOTICE: No network name or ID was specified, using network name 'private' for building images."
fi

keypair="$2"
if [ -z "$keypair" ]; then
    keypair=$LOGNAME
fi

set -e
ansible-playbook -vv main.yml \
                 -e conf=one.conf.yml \
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
