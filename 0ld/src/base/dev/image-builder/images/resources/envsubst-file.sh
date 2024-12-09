#!/bin/sh

envsubst_file() {
  target_file="$1"
  if [[ -f ${target_file} ]]; then
    tmp_file=$(mktemp)
    cp "${target_file}" "${tmp_file}"
    envsubst < "${tmp_file}" > "${target_file}"
    echo "info: ${target_file} updated with envsubst"
    return 0
  else
    echo "warning: ${target_file} not found"
    return 404
  fi
}

envsubst_file "$1"
