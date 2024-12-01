#!/bin/sh


PLATYPOD__OUT_DIR="${PLATYPOD__OUT_DIR:-out}"


create_out_dir_if_not_exists() {
  mkdir -p "${PLATYPOD__OUT_DIR}"
}


merge_yaml_files() {
  yq eval-all '. as $item ireduce ({}; . * $item )' $@
}


main() {
  local env='dev'

  for arg; do
    case "$arg" in
      "--env") env="$2"; shift;;
      *) break
    esac
  done

  create_out_dir_if_not_exists
  merge_yaml_files "values/default/*.y*ml" "values/${env}/*.y*ml" \
    > "${PLATYPOD__OUT_DIR}/values.${env}.yaml"
}


main $@
