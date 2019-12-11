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

keypair=$1
if [ -z "$keypair" ]; then
    keypair=$LOGNAME
fi

set -e
ansible-playbook main.yml -e keypair="${keypair}" -e prefix=""'*** '""

#openstack image list --private \
openstack image list \
    | fgrep ' ***' \
    | tr -d '|' \
    | (while read uuid name _ ; do
           openstack server create \
                     --wait \
                     --image $uuid \
                     --flavor m1.small \
                     --key-name $keypair \
                     --nic net-id=DC_2519 \
                     test-$uuid;
       done)

# `openstack` always lists fields in some internally-specified order,
# instead of the one used in the command line
openstack server list -c ID -c Name -c Networks -c Image \
    | fgrep ' test-' \
    | (while IFS=' | ' read _ uuid name nets image; do
             ipv4_addr=$(echo "$nets"| egrep -o '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+');
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
                 $u@$ipv4_addr lsb_release -a;
             set +x;
             openstack server delete $uuid;
       done)

echo "All images updated."

# at end, publish images::
#
#     openstack image set --public --project admin
#
