designageOS
==========

.. image:: https://github.com/Considerasrl/dsignageOS/blob/devel/media/FullPageOS.png
.. :scale: 50 %
.. :alt: designageOS logo

A `Raspberry Pi <http://www.raspberrypi.org/>`_ distribution to display one webpage in full screen. It includes `Chromium <https://www.chromium.org/>`_ out of the box and the scripts necessary to load it at boot.
This repository contains the source script to generate the distribution out of an existing `Raspbian <http://www.raspbian.org/>`_ distro image.

FullPageOS started as a fork from `OctoPi <https://github.com/guysoft/OctoPi>`_, but then joined the distros that use `CustomPiOS <https://github.com/guysoft/CustomPiOS>`_.

Features
--------

* Loads Chromium at boot in full screen
* Webpage can be changed from /boot/firmware/fullpageos.txt
    * You can use variable `{serial}` in the url to get device's serialnumber in the URL
* Ships with preconfigured `X11VNC <http://www.karlrunge.com/x11vnc/>`_, for remote connection (password 'raspberry')
* Specified a custom Splashscreen that gets displayed in the booting process instead of Kernel messages/text
* Python script at boot which runs every 5 minutes to get any changes in production database

Developing
----------

Requirements
~~~~~~~~~~~~

#. `qemu-arm-static <http://packages.debian.org/sid/qemu-user-static>`_
#. `CustomPiOS <https://github.com/guysoft/CustomPiOS>`_
#. Downloaded `Raspbian <http://www.raspbian.org/>`_ image.
#. root privileges for chroot
#. Bash
#. realpath
#. sudo (the script itself calls it, running as root without sudo won't work)
#. jq (part of CustomPiOS dependencies)

Build dsignageOS From within FullPageOS / Raspbian / Debian / Ubuntu
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

FullPageOS can be built from Debian, Ubuntu, Raspbian, or even FullPageOS.
Build requires about 2.5 GB of free space available.
You can build it by issuing the following commands::

    sudo apt install coreutils p7zip-full qemu-user-static
    
    git clone https://github.com/guysoft/CustomPiOS.git
    git clone https://github.com/dsignageOS/dsignageOS.git
    cd dsignageOS/src/image
    wget -c --trust-server-names 'https://downloads.raspberrypi.org/raspios_lite_armhf_latest'
    cd ..
    ../../CustomPiOS/src/update-custompios-paths
    sudo modprobe loop
    sudo bash -x ./build_dist
