OctoPi
======
A Raspberry Pi distribution for 3d printers. It includes the Octoprint,  3d printer out of the box, and mjpg-streamer for live viewing of prints and stop motion video creation.

This repository contains the source script to generate the distribution out of an existing Raspbian distro image.


Requirements
-------------

#. qemu-arm-static
#. Downloaded Raspbian image.
#. root privileges for choot
#. Bash

Usage
-----

#. In the `src/octopi` script set the path of `ZIP_IMG` to the path of your Raspbian image.
#. Run `src/octopi` as root.
#. The final image will be created at the `src/workspace`



Code contribution would be appreciated!