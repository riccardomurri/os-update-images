Update OpenStack VM images
==========================

This repository hosts a set of Ansible scripts to make periodic updates of base
VM images (relatively) effortless.

The script has been developed (and has so far only been used) 
on the [UZH Science Cloud][1].

[1]: https://www.s3it.uzh.ch/en/scienceit/infrastructure/sciencecloud.html


Installation
------------

#. Make a Python virtualenv
#. Install Ansible and additional dependencies::

        pip install -r requirements.txt

Usage
-----

#. Edit file `conf.yml`: list the UUID and the SSH connection username 
   of all base VM images that you want to update.
#. Load OpenStack credentials into the environment
#. Run the `main.yml` playbook::

        ansible-playbook main.yml
        
   You will be prompted for the key pair name to authorize on VMs, and for an
   optional prefix that will be prepended to all generated snapshot names. (This
   is useful for singling out the snapshots if your tenant has many.)
