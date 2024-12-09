#!/bin/sh

script_dir=$(dirname "$(readlink -f "$0")" | sed 's/\/$//')
envsubst_file_script="${script_dir}/envsubst-file.sh"
envsubst_dir_script="${script_dir}/envsubst-dir.sh"

main() {
  for target_file in ${ENVSUBST_TARGET_FILES}; do
    ${envsubst_file_script} "${target_file}"
  done

  for target_dir in ${ENVSUBST_TARGET_FOLDERS}; do
    ${envsubst_dir_script} "${target_dir}"
  done
}

main
