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
  yq --inplace 'sort_keys(..)' "${PLATYPOD__PATH__OUT_DIR}/values.${env}.yaml"
  cp "${PLATYPOD__PATH__OUT_DIR}/values.${env}.yaml" "${PLATYPOD__PATH__OUT_DIR}/values.${env}.yaml.before-substitution"
}



extract_variables_to_replace_from_yaml() {
  local dst="${PLATYPOD__PATH__OUT_DIR}/${PLATYPOD__PATH__VALUES_TO_SUBSTITUTE}"
  rm -f "${dst}"

  for key in $(grep -o '\${[^}]*\}' "$1" | sort | uniq | tr -d '${}'); do
    value="$(yq e ".${key}" "$1")"
    [ "${value}" == "null" ] && value=""
    echo "$key=$value" >> "${dst}"
  done

  local loop="true"
  while [ -n "${loop}" ]; do
    unset loop
    local sed_cmd=""
    sed_cmd="$(for key in $(
        grep -o '\${[^}]*\}' "${dst}" | sort | uniq | tr -d '${}'
      ); do
        loop="loop_once_more_since_we_are_still_updating_values"
        value="$(yq e ".${key}" "$1")"
        key="$(echo "${key}" | sed -r 's/([\$\.\*\/\[\{\}\^\\])/\\\1/g')"
        value="$(echo "${value}" | sed -r 's/([\$\.\*\/\[\{\}\^\\])/\\\1/g')"
        [ $(echo "${value}" | grep --silent '\${[^}]*\}') ] ||
          echo "s/\\\${${key}}/${value}/g"
      done | tr "\n" ";"
    )"
    rm -f "${dst}.ongoing-substitution"
    if sed "${sed_cmd}" < "${dst}" > "${dst}.ongoing-substitution"; then
      mv "${dst}.ongoing-substitution" "${dst}"
    else
      echo "${sed_cmd}" | sed 's/;/;\n/g' > "${PLATYPOD__PATH__OUT_DIR}/failed.sed"
      exit 500
    fi
  done
}


build_replace_command() {
  local dst="${PLATYPOD__PATH__OUT_DIR}/${PLATYPOD__PATH__SED_COMMAND}"
  rm -f "${dst}"
  cat "${PLATYPOD__PATH__OUT_DIR}/${PLATYPOD__PATH__VALUES_TO_SUBSTITUTE}" |
    while read -r var; do
      key="$(echo "${var%%=*}" | sed -r 's/([\$\.\*\/\[\{\}\^\\])/\\\1/g')"
      value="$(echo "${var#*=}" | sed -r 's/([\$\.\*\/\[\{\}\^\\])/\\\1/g')"
      echo "s/\\\${${key}}/${value}/g;" >> "${dst}"
    done
}


replace_variables_in_file() {
  local sed_file="${PLATYPOD__PATH__OUT_DIR}/${PLATYPOD__PATH__SED_COMMAND}"
  local src="$1"
  if sed -f "${sed_file}" < "${src}" > "${src}.ongoing-substitution"; then
    mv "${src}.ongoing-substitution" "${src}"
  else
    exit 500
  fi
}


replace_variables_in_yaml() {
  extract_variables_to_replace_from_yaml "$1"
  build_replace_command
  replace_variables_in_file "$1"
}
