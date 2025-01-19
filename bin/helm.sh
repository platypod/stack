#!/bin/sh


. bin/env.sh
. bin/yaml.sh


helm_env() {
  local cmd="$1"; shift
  local env="$1"; shift
  local name="$1"; shift
  local src="$1"; shift

  echo ">>> merge yaml files"
  merge_yaml --env "${env}"

  echo ">>> replace variables in yaml file"
  replace_variables_in_yaml "${PLATYPOD__PATH__OUT_DIR}/values.${env}.yaml"

  local namespace="$(
    yq e ".k8s.namespace" ${PLATYPOD__PATH__OUT_DIR}/values.${env}.yaml
  )"

  local call="helm ${cmd}"
  call="${call} -f ${PLATYPOD__PATH__OUT_DIR}/values.${env}.yaml"
  call="${call} ${name} ${src}"
  call="${call} --namespace ${namespace} --create-namespace"
  call="${call} $@"
  echo ">>> ${call}"
  eval "${call}"
  echo ""
}


install_or_upgrade_one() {
  local env="${PLATYPOD__HELM__DEFAULT_ENV}"
  local end_array="3ND-4RR4Y"
  local src=""

  set -- "$@" "${end_array}"

  while [ "$1" != "${end_array}" ]; do
    case "$1" in
      "--env") env="$2"; shift;;
      "--src") src="$2"; shift;;
      *) set -- "$@" "$1" ;;
    esac
    shift
  done
  shift

  if [ $# -eq 0 ]; then
    set -- "${PLATYPOD__HELM__DEFAULT_ARGS}" "$@"
  fi

  local name="${env}--platypod--${src:$((${#PLATYPOD__PATH__SRC_DIR} + 4))}"

  echo "apiVersion: ${PLATYPOD__HELM__CHART__API_VERSION}" > "${src}/Chart.yaml"
  echo "name: ${name}"                                    >> "${src}/Chart.yaml"
  echo "version: ${PLATYPOD__HELM__CHART__VERSION}"       >> "${src}/Chart.yaml"
  echo "appVersion: ${PLATYPOD__HELM__CHART__VERSION}"    >> "${src}/Chart.yaml"

  local cmd="install"
  if helm list --all-namespaces --short | grep -E "^${name}\$"; then
    cmd="upgrade"
  fi

  helm_env "${cmd}" "${env}" "${name}" "${src}" "$@"

  rm "${src}/Chart.yaml"
}


install_or_upgrade() {
  local env="${PLATYPOD__HELM__DEFAULT_ENV}"
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

  find "${PLATYPOD__PATH__SRC_DIR}" -type d -depth 1 | sort |
    while read -r module_path; do
      # only process non-empty dirs
      [ "$(ls -A "./${module_path}")" ] &&
        install_or_upgrade_one --src "${module_path}" --env "${env}" "$@"
    done
  clean
}
