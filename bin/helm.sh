#!/bin/sh


. bin/env.sh
. bin/yaml.sh


helm_env() {
  local env='dev'
  local end_array="3ND-4RR4Y"

  set -- "$@" "${end_array}"

  while [ "$1" != "${end_array}" ]; do
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
  merge_yaml --env "${env}"

  echo ">>> replace variables in yaml file"
  replace_variables_in_yaml "${PLATYPOD__PATH__OUT_DIR}/values.${env}.yaml"

  echo ">>> helm ${cmd} -f ${PLATYPOD__PATH__OUT_DIR}/values.${env}.yaml $@"
  eval "helm ${cmd} -f ${PLATYPOD__PATH__OUT_DIR}/values.${env}.yaml $@"
}


install_or_upgrade_one() {
  workdir="$1"
  shift

  if [ $# -eq 0 ]; then
    set -- "${PLATYPOD__HELM__DEFAULT_ARGS}" "$@"
  fi

  if [ ! -f "${workdir}/Chart.yaml" ]; then return; fi
  name="$(yq e ".name" "${workdir}/Chart.yaml")"

  if helm list | awk '{if ($1 ~ /'"${name}"'/) {exit 1} else {next}}'; then
    helm_env install "${name}" "${workdir}" "$@"
  else
    helm_env upgrade "${name}" "${workdir}" "$@"
  fi
}


install_or_upgrade() {
  find "${PLATYPOD__PATH__SRC_DIR}" -type d -depth 1|
    while read -r module_path; do
      install_or_upgrade_one "${module_path}" "$@"
    done
  clean
}


dry_run_one() {
  workdir="$1"
  if [ ! -f "${workdir}/Chart.yaml" ]; then return; fi
  name="$(yq e ".name" "${workdir}/Chart.yaml")"

}


dry_run() {
  helm_env
}
