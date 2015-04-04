#!/usr/bin/env bash

function die () {
    echo >&2 "$@"
    exit 1
}

function fixLd(){
  sed -i 's@/usr/lib/arm-linux-gnueabihf/libcofi_rpi.so@\#/usr/lib/arm-linux-gnueabihf/libcofi_rpi.so@' etc/ld.so.preload
}

function restoreLd(){
  sed -i 's@\#/usr/lib/arm-linux-gnueabihf/libcofi_rpi.so@/usr/lib/arm-linux-gnueabihf/libcofi_rpi.so@' etc/ld.so.preload
}

function gitclone(){
if [ "$GIT_REPO_OVERRIDE" != "" ] ; then
    REPO=$GIT_REPO_OVERRIDE`echo $1 | awk -F '/' '{print $(NF)}'`
    sudo -u pi git clone $REPO
    REPO_DIR_NAME=$(echo ${REPO} | 's%^.*/\([^/]*\)\.git$%\1%g')
    pushd ${REPO_DIR_NAME}
        sudo -u pi git remote set-url $1
    popd
else
    sudo -u pi git clone $1
fi
}

function unpackHome(){
  shopt -s dotglob
  cp -v -r --preserve=mode,timestamps /filesystem/home/* /home/pi
  shopt -u dotglob
  chown -hR pi:pi /home/pi
}

function unpackRoot(){
  shopt -s dotglob
  cp -v -r --preserve=mode,timestamps /filesystem/root/* /
  shopt -u dotglob
}

function unpackBoot(){
  shopt -s dotglob
  cp -v -r --preserve=mode,timestamps /filesystem/boot/* /boot
  shopt -u dotglob
}

function install_fail_on_error_trap() {
  set -e
  trap 'previous_command=$this_command; this_command=$BASH_COMMAND' DEBUG
  trap 'if [ $? -ne 0 ]; then echo -e "\nexit $? due to $previous_command \nBUILD FAILED!"; fi' EXIT
}
