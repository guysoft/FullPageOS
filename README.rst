OctoPi
======
A `Raspberry Pi <http://www.raspberrypi.org/>`_ distribution for 3d printers. It includes the `Octoprint <http://octoprint.org>`_
,  3d printer out of the box, and `mjpg-streamer with rapicam support <https://github.com/jacksonliam/mjpg-streamer>`_ for live viewing of prints and stop motion video creation.

This repository contains the source script to generate the distribution out of an existing `Raspbian <http://www.raspbian.org/>`_ distro image.

Where to get it?
----------------

Official mirror is `here <http://docstech.net/OctoPiMirror/>`_

How to use it?
--------------

#. unzip the image and dd it to an sd card like any other Raspberry Pi image
#. boot the pi and connect it to a lan or wifi network, like any other Rasbpian installation.
#. Octoprint port is 80 located at `http://octopi.local <http://octopi.local>`_.
#. If a webcam was plugged in, MJPG-streamer is on port 8080. You can reach it at: `http://octopi.local:8080/?action=stream <octopi.local:8080/?action=stream>`_.

Developing
----------

Requirements
~~~~~~~~~~~~

#. `qemu-arm-static <http://packages.debian.org/sid/qemu-user-static>`_
#. Downloaded `Raspbian <http://www.raspbian.org/>`_ image.
#. root privileges for choot
#. Bash
#. realpath

Build OctoPi From within OctoPi / Raspbian / Debian / Ubuntu
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

OctoPi can be built from Debian, Ubuntu, Raspbian, or even OctoPi.
Build requires about 2.5 GB of free space avilable.
You can build it by issuing the following commands::

    sudo apt-get install realpath qemu-user-static
    git clone https://github.com/guysoft/OctoPi.git
    cd OctoPi/src
    wget http://files.velocix.com/c1410/images/raspbian/2013-07-26-wheezy-raspbian/2013-07-26-wheezy-raspbian.zip
    sudo bash -x ./build

Usage
~~~~~

#. In the ``src/config`` script set the path of ``ZIP_IMG`` to the path of your Raspbian image.
#. Run ``src/build`` as root.
#. The final image will be created at the ``src/workspace``



Code contribution would be appreciated!
