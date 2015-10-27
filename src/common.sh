#!/usr/bin/env bash

function die () {
    echo >&2 "$@"
    exit 1
}

function fixLd(){
  sed -i 's@/usr/lib/arm-linux-gnueabihf/libcofi_rpi.so@\#/usr/lib/arm-linux-gnueabihf/libcofi_rpi.so@' etc/ld.so.preload
  sed -i 's@/usr/lib/arm-linux-gnueabihf/libarmmem.so@\#/usr/lib/arm-linux-gnueabihf/libarmmem.so@' etc/ld.so.preload
}

function restoreLd(){
  sed -i 's@\#/usr/lib/arm-linux-gnueabihf/libcofi_rpi.so@/usr/lib/arm-linux-gnueabihf/libcofi_rpi.so@' etc/ld.so.preload
  sed -i 's@\#/usr/lib/arm-linux-gnueabihf/libarmmem.so@/usr/lib/arm-linux-gnueabihf/libarmmem.so@' etc/ld.so.preload
}

function pause() {
  # little debug helper, will pause until enter is pressed and display provided
  # message
  read -p "$*"
}

function gitclone(){
  # call like this: gitclone OCTOPI_OCTOPRINT_REPO someDirectory -- this will do:
  #
  #   sudo -u pi git clone -b $OCTOPI_OCTOPRINT_REPO_BRANCH $OCTOPI_OCTOPRINT_REPO_BUILD someDirectory
  # 
  # and if $OCTOPI_OCTOPRINT_REPO_BUILD != $OCTOPI_OCTOPRINT_REPO_SHIP also:
  #
  #   pushd someDirectory
  #     sudo -u pi git remote set-url origin $OCTOPI_OCTOPRINT_REPO_SHIP
  #   popd
  # 
  # if second parameter is not provided last URL segment of the BUILD repo URL
  # minus the optional .git postfix will be used

  repo_build_var=$1_BUILD
  repo_ship_var=$1_SHIP
  repo_branch_var=$1_BRANCH
  
  repo_dir=$2
  if [ ! -n "$repo_dir" ]
  then
    repo_dir=$(echo ${REPO} | sed 's%^.*/\([^/]*\)\(\.git\)?$%\1%g')
  fi

  build_repo=${!repo_build_var}
  ship_repo=${!repo_ship_var}
  branch=${!repo_branch_var}

  if [ ! -n "$build_repo" ]
  then
    build_repo=$ship_repo
  fi

  if [ -n "$branch" ]
  then
    sudo -u pi git clone -b $branch "$build_repo" "$repo_dir"
  else
    sudo -u pi git clone "$build_repo" "$repo_dir"
  fi

  if [ "$build_repo" != "$ship_repo" ]
  then
    pushd "$repo_dir"
      sudo -u pi git remote set-url origin "$ship_repo"
    popd
  fi
}

function unpack() {
  # call like this: unpack /path/to/source /target user -- this will copy
  # all files & folders from source to target, preserving mode and timestamps
  # and chown to user. If user is not provided, no chown will be performed

  from=$1
  to=$2
  owner=
  if [ "$#" -gt 2 ]
  then
    owner=$3
  fi

  # $from/. may look funny, but does exactly what we want, copy _contents_
  # from $from to $to, but not $from itself, without the need to glob -- see 
  # http://stackoverflow.com/a/4645159/2028598
  cp -v -r --preserve=mode,timestamps $from/. $to
  if [ -n "$owner" ]
  then
    chown -hR $owner:$owner $to
  fi
}

function mount_image() {
  image_path=$1
  mount_path=$2

  # mount root and boot partition
  sudo mount -o loop,offset=$((512*122880)) $image_path $mount_path
  sudo mount -o loop,offset=$((512*8192)) $image_path $mount_path/boot
  sudo mount -o bind /dev $mount_path/dev
}

function unmount_image() {
  mount_path=$1

  # unmount first boot, then root partition
  sudo umount $mount_path/boot
  sudo umount $mount_path/dev
  sudo umount $mount_path
}

function install_fail_on_error_trap() {
  set -e
  trap 'previous_command=$this_command; this_command=$BASH_COMMAND' DEBUG
  trap 'if [ $? -ne 0 ]; then echo -e "\nexit $? due to $previous_command \nBUILD FAILED!" && echo "unmounting image..." && ( unmount_image $OCTOPI_MOUNT_PATH || true ); fi;' EXIT
}

function install_chroot_fail_on_error_trap() {
  set -e
  trap 'previous_command=$this_command; this_command=$BASH_COMMAND' DEBUG
  trap 'if [ $? -ne 0 ]; then echo -e "\nexit $? due to $previous_command \nBUILD FAILED!"; fi;' EXIT
}
