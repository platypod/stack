#!/bin/sh


PLATYPOD__HELM__DEFAULT_ARGS="--wait --wait-for-jobs"
PLATYPOD__PATH__OUT_DIR="${PLATYPOD__PATH__OUT_DIR:-out}"
PLATYPOD__PATH__SRC_DIR="${PLATYPOD__PATH__SRC_DIR:-src}"
PLATYPOD__PATH__VALUES_TO_SUBSTITUTE="${PLATYPOD__PATH__VALUES_TO_SUBSTITUTE:-values-to-substitute.env}"


create_out_dir_if_not_exists() {
  mkdir -p "${PLATYPOD__PATH__OUT_DIR}"
}


clean() {
  [ ${PLATYPOD__PATH__OUT_DIR} != "" ] && rm -rf "${PLATYPOD__PATH__OUT_DIR}"
}
