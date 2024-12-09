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
  merge_yaml_files "values/default/*.y*ml" "values/${env}/*.y*ml" \
    > "${PLATYPOD__PATH__OUT_DIR}/values.${env}.yaml"
}



extract_variables_to_replace_from_yaml() {
  rm -rf "${PLATYPOD__PATH__OUT_DIR}/${PLATYPOD__PATH__VALUES_TO_SUBSTITUTE}"
  for key in $(grep -o '\${[^}]*\}' "$1" | sort | uniq | tr -d '${}'); do
    value=$(yq e ".${key}" "$1")
    echo "$key=$value" >> "${PLATYPOD__PATH__OUT_DIR}/${PLATYPOD__PATH__VALUES_TO_SUBSTITUTE}"
  done
}


build_replace_command() {
  cat "${PLATYPOD__PATH__OUT_DIR}/${PLATYPOD__PATH__VALUES_TO_SUBSTITUTE}" |
    while read -r var; do
      key="$(echo "${var%%=*}" | sed -r 's/([\$\.\*\/\[\\\{\}^])/\\\1/g')"
      value="$(echo "${var#*=}" | sed -r 's/([\$\.\*\/\[\\\{\}^])/\\\1/g')"
      echo "s/\\\${${key}}/${value}/g"
    done | tr "\n" ";"
}


replace_variables_in_file() {
  local sed_args="$(build_replace_command)"
  sed "${sed_args}" < "$1" > "$1.tmp" && mv "$1.tmp" "$1"
  rm "${PLATYPOD__PATH__OUT_DIR}/${PLATYPOD__PATH__VALUES_TO_SUBSTITUTE}"
}


replace_variables_in_yaml() {
  extract_variables_to_replace_from_yaml "$1"
  replace_variables_in_file "$1"
}
