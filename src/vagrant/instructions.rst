How to use vagrant image build system
=====================================

Make sure you uave all the requirements
::
    sudo apt-get install vagrant nfs-kernel-server
    sudo  vagrant plugin install vagrant-nfs_guest
    sudo modprobe nfs
    sudo vagrant up
