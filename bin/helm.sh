#!/bin/sh


main() {
  local env='dev'
  local end_array="3ND-4RR4Y"

  set -- "$@" "${end_array}"

  while [ $1 != "${end_array}" ]; do
    case "$1" in
      "--env") env="$2"; shift;;
      *) set -- "$@" "$1" ;;
    esac
    shift
  done
  shift

  local cmd="$1"
  shift

  echo ">>> merge yaml files"
  . bin/merge-yaml.sh --env "${env}"

  echo ">>> helm ${cmd} -f ${PLATYPOD__OUT_DIR}/values.${env}.yaml $@"
  #eval "helm ${cmd} -f ${PLATYPOD__OUT_DIR}/values.${env}.yaml $@"
}


main $@
