OctoPi
======

.. image:: https://raw.githubusercontent.com/guysoft/OctoPi/devel/media/OctoPi.png
.. :scale: 50 %
.. :alt: OctoPi logo

A `Raspberry Pi <http://www.raspberrypi.org/>`_ distribution for 3d printers. It includes the `OctoPrint <http://octoprint.org>`_ host software for 3d printers out of the box and `mjpg-streamer with RaspiCam support <https://github.com/jacksonliam/mjpg-streamer>`_ for live viewing of prints and timelapse video creation. OctoPi also includes `OctoPiPanel <https://github.com/jonaslorander/OctoPiPanel>`_, which is an LCD display app that works with OctoPrint, and scripts to configure supported display.s
This repository contains the source script to generate the distribution out of an existing `Raspbian <http://www.raspbian.org/>`_ distro image.

Where to get it?
----------------

Official mirror is `here <http://docstech.net/OctoPiMirror/>`_

Alternative mirror is `here <http://mariogrip.com/OctoPiMirror/>`_


There is also a torrent for 0.10.0 `here <http://dns3.snuletek.org/share/2014-06-20-wheezy-octopi-0.10.0.zip.torrent>`_ .

Nightly builds are avilable `here <http://docstech.net/OctoPiMirror/nightly/>`_

How to use it?
--------------

#. unzip the image and dd it to an sd card like any other Raspberry Pi image
#. boot the pi and connect it to a lan or wifi network, like any other Rasbpian installation.
#. OctoPrint is located at `http://octopi.local <http://octopi.local>`_ and also at `https://octopi.local <https://octopi.local>`_. Since the SSL certificate is self signed (and generated upon first boot), you will get a certificate warning at the latter location, please ignore it.
#. If a webcam was plugged in, MJPG-streamer is on port 8080. You can reach it at: `http://octopi.local:8080/?action=stream <octopi.local:8080/?action=stream>`_. It is also setup so that you can reach it under `http://octopi.local/webcam/?action=stream <octopi.local/webcam/?action=stream>`_ and SSL respectively.

Features
--------
* `OctoPrint <http://octoprint.org>`_ host software for 3d printers out of the box
* `Raspbian <http://www.raspbian.org/>`_ tweaked for maximum preformance for printing out of the box
* `mjpg-streamer with RaspiCam support <https://github.com/jacksonliam/mjpg-streamer>`_ for live viewing of prints and timelapse video creation.
* `OctoPiPanel <https://github.com/jonaslorander/OctoPiPanel>`_, which is an LCD display app that works with OctoPrint
* Configuration scripts for verious LCD displays

Developing
----------

Requirements
~~~~~~~~~~~~

#. `qemu-arm-static <http://packages.debian.org/sid/qemu-user-static>`_
#. Downloaded `Raspbian <http://www.raspbian.org/>`_ image.
#. root privileges for chroot
#. Bash
#. realpath
#. sudo (the script itself calls it, running as root without sudo won't work)

Build OctoPi From within OctoPi / Raspbian / Debian / Ubuntu
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

OctoPi can be built from Debian, Ubuntu, Raspbian, or even OctoPi.
Build requires about 2.5 GB of free space available.
You can build it by issuing the following commands::

    sudo apt-get install realpath qemu-user-static
    
    git clone https://github.com/guysoft/OctoPi.git
    cd OctoPi/src/image
    curl -J -O -L  http://downloads.raspberrypi.org/raspbian_latest
    cd ..
    sudo modprobe loop
    sudo bash -x ./build

Usage
~~~~~

#. If needed, override existing config settings by creating a new file ``src/config.local``. You can override all settings found in ``src/config``. If you need to override the path to the Raspbian image to use for building OctoPi, override the path to be used in ``ZIP_IMG``. By default the most recent file matching ``*-raspbian.zip`` found in ``src/image`` will be used.
#. Run ``src/build`` as root.
#. The final image will be created at the ``src/workspace``

Code contribution would be appreciated!
