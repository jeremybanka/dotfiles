#!/bin/bash

SCRUBS_PRIMARY_SHELL="bash"

SCRUBS_HELPER_COMMANDS=(
  awk
  basename
  cat
  chmod
  cp
  cut
  dirname
  env
  find
  git
  grep
  head
  id
  ln
  ls
  mkdir
  mktemp
  pwd
  readlink
  rm
  sed
  sh
  sort
  tail
  tar
  tee
  touch
  tr
  uname
  uniq
  which
  xargs
  xz
  gzip
  unzip
  mise
)

SCRUBS_HELPER_COPY_FILES=(
  /etc/passwd
  /etc/group
  /etc/nsswitch.conf
)

SCRUBS_HELPER_LINK_FILES=(
  /etc/ssl/certs/ca-bundle.crt
)

SCRUBS_DIR_PATHS=(
  /usr
  /etc
  /home
  /run
  /tmp
  /sys
)

SCRUBS_RO_BIND_PATHS=(
  /etc/hosts
  /etc/resolv.conf
  /etc/localtime
  /sys
)

SCRUBS_ENABLE_PROC=1
