#!/bin/sh

envsubst_dir() {
  dir="$1"

  script_dir=$(dirname "$(readlink -f "$0")" | sed 's/\/$//')
  envsubst_file_script="${script_dir}/envsubst-file.sh"

  find ${dir} -type f -print0 |
    xargs -0 -I {} "${envsubst_file_script}" {}
}

envsubst_dir "$1"
