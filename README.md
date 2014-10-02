migrate_ovz_to_vmware
=====================

A script that creates a VMware .vmdk image from an OpenVZ host

The OpenVZ container must be running to extract some needed information
form it. Intended way of use is:
- Container running
- Run script
- Copy generated vmdk file to Virtualbox/VMware
- Create VM and use file as hard disk
- Stop OpenVZ container
- Start new VM
