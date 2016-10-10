#!/bin/bash

check_docker_requirements(){
  if [ "$(id -u)" != "0" ]; then
    groups | grep -q docker || echo "--> If you are not running the script as root, your user should be in the docker group to use it. (sudo gpasswd -a $USER docker)"
  fi
  ps aux | grep -q '[d]ocker' || echo "--> Be sure to have the docker daemon running (sudo systemctl start docker) of configure it to run on boot (sudo systemctl enable docker). Trying to start it anyway" && sudo systemctl start docker || true
}

die() { echo "$@" 1>&2 ; exit 1; }

build_sync() {
  layman -S
  emerge --sync
  eix-update || exit 1
  pushd /opt/sabayon-build/
    git stash
    git fetch --all
    git checkout master
    git reset --heard origin/master
  popd
}

build_category() {
  local SEARCH=$1
  build_sync
  for i in $(EIX_LIMIT=0 eix --only-names --pure-packages "$SEARCH/" | xargs echo | uniq);
    do
      echo "Building $i"
      emerge ${EMERGE_DEFAULT_ARGS:---accept-properties=-interactive --verbose --oneshot --nospinner --noreplace --quiet-build=y --quiet-fail --fail-clean=y --complete-graph --buildpkg} $i
    done
}

build_obsolete() {
  build_sync
  for i in $(EIX_LIMIT=0 eix-test-obsolete | grep '\[U\]' | awk '{ print $2 }' | xargs echo | uniq);
    do
     echo "Build $i"
     emerge ${EMERGE_DEFAULT_ARGS:---accept-properties=-interactive --verbose --oneshot --nospinner --quiet-build=y --quiet-fail --fail-clean=y --complete-graph --buildpkg --noreplace} $i
    done
}

build_category_installed() {
  local SEARCH=$1
  build_sync
  for i in $(EIX_LIMIT=0 eix -I --only-names --pure-packages "$SEARCH/" | xargs echo | uniq);
    do
      echo "Building $i"
      emerge ${EMERGE_DEFAULT_ARGS:---accept-properties=-interactive --newuse --noreplace --changed-use --update --verbose --oneshot --nospinner --quiet-build=y --quiet-fail --fail-clean=y --complete-graph --buildpkg} $i
    done
}

build_all_availables() {
  for i in $(cat /usr/portage/profiles/categories | xargs echo | uniq);
    do
      build_category "$i/"
    done
}

rebuild_all() {
for i in $(cat /usr/portage/profiles/categories | xargs echo | uniq);
  do
    build_category_installed "$i/"
  done
}

get_category() {
  local CATEGORY=$1
  local PACKS
  for i in $(EIX_LIMIT=0 eix --only-names --pure-packages "$CATEGORY/" | xargs echo | uniq);
    do
      PACKS+="$i "
    done
    echo $PACKS
}

get_all_availables() {
  local RES
  for i in $(cat /usr/portage/profiles/categories | xargs echo | uniq);
    do
        RES+="$(get_category $i) "
    done
  echo $RES
}
