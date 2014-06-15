OctoPi
======

.. image:: https://raw2.github.com/guysoft/OctoPi/master/media/OctoPi.png
.. :scale: 50 %
.. :alt: OctoPi logo

A `Raspberry Pi <http://www.raspberrypi.org/>`_ distribution for 3d printers. It includes the `OctoPrint <http://octoprint.org>`_ host software for 3d printers out of the box and `mjpg-streamer with rapicam support <https://github.com/jacksonliam/mjpg-streamer>`_ for live viewing of prints and timelapse video creation.

This repository contains the source script to generate the distribution out of an existing `Raspbian <http://www.raspbian.org/>`_ distro image.

Where to get it?
----------------

Official mirror is `here <http://docstech.net/OctoPiMirror/>`_

Alternatively, there's a torrent active `here <http://dns3.snuletek.org/share/2014-01-07-wheezy-octopi-0.8.0.torrent>`_ which could have higher download speed, if theres sufficient seeders (so seed :))

How to use it?
--------------

#. unzip the image and dd it to an sd card like any other Raspberry Pi image
#. boot the pi and connect it to a lan or wifi network, like any other Rasbpian installation.
#. OctoPrint is located at `http://octopi.local <http://octopi.local>`_ and also at `https://octopi.local <https://octopi.local>`_. Since the SSL certificate is self signed (and generated upon first boot), you will get a certificate warning at the latter location, please ignore it.
#. If a webcam was plugged in, MJPG-streamer is on port 8080. You can reach it at: `http://octopi.local:8080/?action=stream <octopi.local:8080/?action=stream>`_. It is also setup so that you can reach it under `http://octopi.local/webcam/?action=stream <octopi.local/webcam/?action=stream>`_ and SSL respectively.

Developing
----------

Requirements
~~~~~~~~~~~~

#. `qemu-arm-static <http://packages.debian.org/sid/qemu-user-static>`_
#. Downloaded `Raspbian <http://www.raspbian.org/>`_ image.
#. root privileges for chroot
#. Bash
#. realpath

Build OctoPi From within OctoPi / Raspbian / Debian / Ubuntu
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

OctoPi can be built from Debian, Ubuntu, Raspbian, or even OctoPi.
Build requires about 2.5 GB of free space available.
You can build it by issuing the following commands::

    sudo apt-get install realpath qemu-user-static
    git clone https://github.com/guysoft/OctoPi.git
    cd OctoPi/src/image
    wget http://files.velocix.com/c1410/images/raspbian/2013-07-26-wheezy-raspbian/2013-07-26-wheezy-raspbian.zip
    cd ..
    sudo bash -x ./build

Usage
~~~~~

#. If needed, override existing config settings by creating a new file ``src/config.local``. You can override all settings found in ``src/config``. If you need to override the path to the Raspbian image to use for building OctoPi, override the path to be used in ``ZIP_IMG``. By default the most recent file matching ``*-raspbian.zip`` found in ``src/image`` will be used.
#. Run ``src/build`` as root.
#. The final image will be created at the ``src/workspace``

Code contribution would be appreciated!
