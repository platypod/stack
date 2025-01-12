#!/bin/sh


. bin/env.sh


merge_yaml_files() {
  yq eval-all '. as $item ireduce ({}; . * $item )' $@
}


merge_yaml() {
  local env='dev'

  for arg; do
    case "$arg" in
      "--env") env="$2"; shift;;
      *) break
    esac
  done

  create_out_dir_if_not_exists
  merge_yaml_files "values/default/*/*.y*ml" "values/${env}/*.y*ml" \
    > "${PLATYPOD__PATH__OUT_DIR}/values.${env}.yaml"
}



extract_variables_to_replace_from_yaml() {
  local dst="${PLATYPOD__PATH__OUT_DIR}/${PLATYPOD__PATH__VALUES_TO_SUBSTITUTE}"
  rm -f "${dst}"

  for key in $(grep -o '\${[^}]*\}' "$1" | sort | uniq | tr -d '${}'); do
    value="$(yq e ".${key}" "$1")"
    [ "${value}" == "null" ] && value=""
    echo "$key=$value" >> "${dst}"
  done

  local stop_looping
  while [ -z "${stop_looping}" ]; do
    stop_looping="true"
    local sed_cmd=""
    sed_cmd="$(for key in $(
        grep -o '\${[^}]*\}' "${dst}" | sort | uniq | tr -d '${}'
    ); do
      unset stop_looping
      value="$(yq e ".${key}" "$1")"
      key="$(echo "${key}" | sed -r 's/([\$\.\*\/\[\{\}\^\\])/\\\1/g')"
      value="$(echo "${value}" | sed -r 's/([\$\.\*\/\[\{\}\^\\])/\\\1/g')"
      [ $(echo "${value}" | grep --silent '\${[^}]*\}') ] ||
        echo "s/\\\${${key}}/${value}/g"
    done | tr "\n" ";")"

    rm -f "${dst}.ongoing-substitution"
    sed "${sed_cmd}" < "${dst}" > "${dst}.ongoing-substitution" &&
      mv "${dst}.ongoing-substitution" "${dst}"
  done
}


build_replace_command() {
  cat "${PLATYPOD__PATH__OUT_DIR}/${PLATYPOD__PATH__VALUES_TO_SUBSTITUTE}" |
    while read -r var; do
      key="$(echo "${var%%=*}" | sed -r 's/([\$\.\*\/\[\{\}\^\\])/\\\1/g')"
      value="$(echo "${var#*=}" | sed -r 's/([\$\.\*\/\[\{\}\^\\])/\\\1/g')"
      echo "s/\\\${${key}}/${value}/g"
    done | tr "\n" ";"
}


replace_variables_in_file() {
  local sed_args="$1"
  local file="$2"
  sed "${sed_args}" < "${file}" > "${file}.ongoing-substitution" &&
    mv "${file}.ongoing-substitution" "${file}"
}


replace_variables_in_yaml() {
  extract_variables_to_replace_from_yaml "$1"
  replace_variables_in_file "$(build_replace_command)" "$1"
}
