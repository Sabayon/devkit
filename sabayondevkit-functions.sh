#!/bin/bash

check_docker_requirements(){
  if [ "$(id -u)" != "0" ]; then
    groups | grep -q docker || echo "--> If you are not running the script as root, your user should be in the docker group to use it. (sudo gpasswd -a $USER docker)"
  fi
  ps aux | grep -q '[d]ocker' || echo "--> Be sure to have the docker daemon running (sudo systemctl start docker)"
}

build() {
local SEARCH=$1
local EMERGE_DEFAULT_ARGS=${2:---accept-properties=-interactive --verbose --oneshot --nospinner --quiet-build=y --quiet-fail --fail-clean=y --complete-graph --buildpkg}
for i in $(EIX_LIMIT=0 eix --only-names --pure-packages "$SEARCH/" | xargs echo | uniq);
  do
    emerge $EMERGE_DEFAULT_ARGS -o $i && \
    emerge $EMERGE_DEFAULT_ARGS $i
  done
}

build_installed() {
  local SEARCH=$1
  local EMERGE_DEFAULT_ARGS=${2:---accept-properties=-interactive --newuse --changed-use --update --verbose --oneshot --nospinner --quiet-build=y --quiet-fail --fail-clean=y --complete-graph --buildpkg}

  for i in $(EIX_LIMIT=0 eix -I --only-names --pure-packages "$SEARCH/" | xargs echo | uniq);
    do
      #emerge $EMERGE_DEFAULT_ARGS -o $i && \
      emerge $EMERGE_DEFAULT_ARGS $i
    done
}

build_all_availables() {
for i in $(cat /usr/portage/profiles/categories | xargs echo | uniq);
  do
    build "$i/"
  done
}

rebuild_all() {
for i in $(cat /usr/portage/profiles/categories | xargs echo | uniq);
  do
    build_installed "$i/"
  done
}

build_sync() {
  emerge-webrsync || exit 1
  emerge --sync
  layman -S
  eix-update || exit 1
  pushd /opt/sabayon-build/
    git stash
    git fetch --all
    git checkout master
    git reset --heard origin/master
  popd
}
