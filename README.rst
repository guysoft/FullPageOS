OctoPi
======
A `Raspberry Pi <http://www.raspberrypi.org/>`_ distribution for 3d printers. It includes the `Octoprint <http://octoprint.org>`_
,  3d printer out of the box, and `mjpg-streamer <http://sourceforge.net/projects/mjpg-streamer/>`_ for live viewing of prints and stop motion video creation.

This repository contains the source script to generate the distribution out of an existing `Raspbian <http://www.raspbian.org/>`_ distro image.


Requirements
-------------

#. `qemu-arm-static <http://packages.debian.org/sid/qemu-user-static>`_
#. Downloaded `Raspbian <http://www.raspbian.org/>`_ image.
#. root privileges for choot
#. Bash

Usage
-----

#. In the `src/octopi` script set the path of `ZIP_IMG` to the path of your Raspbian image.
#. Run `src/octopi` as root.
#. The final image will be created at the `src/workspace`



Code contribution would be appreciated!