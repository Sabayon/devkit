#!/bin/bash

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
