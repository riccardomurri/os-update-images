Update OpenStack VM images
==========================

This repository hosts a set of Ansible scripts to make periodic updates of base
VM images (relatively) effortless.

The script has been developed (and has so far only been used) on the
[UZH Science Cloud][1], and on the [ETHZ][2] VIO and ["Leonhard"
OpenNebula][3] infrastructures.

[1]: https://www.s3it.uzh.ch/en/scienceit/infrastructure/sciencecloud.html
[2]: http://www.ethz.ch/
[3]: https://opennebula.org/eth-zurich/

Installation
------------

#. Make a Python virtualenv
#. Install Ansible and additional dependencies::

        pip install -r requirements.txt

Usage
-----

#. Edit file `conf.yml`: list the download URL and SSH connection username
   of all base VM images that you want to update.
#. Load OpenStack or OpenNebula credentials into the environment
#. Run the `main.yml` playbook::

        ansible-playbook main.yml

   You will be prompted for the key pair name to authorize on VMs, and for an
   optional prefix that will be prepended to all generated snapshot names. (This
   is useful for singling out the snapshots if your tenant has many.)

   Alternatively, example scripts `run_openstack.sh` and `run_one.sh`
   are provided to automate this pass.
