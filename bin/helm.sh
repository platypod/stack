#!/bin/sh
# Thin wrappers around helmfile.
# Requires: helmfile (https://helmfile.readthedocs.io/en/latest/#installation)
#
# Usage:
#   . bin/helm.sh          # source to get functions
#
#   deploy --env dev       # deploy full stack
#   deploy --env dev --dry-run
#   deploy_one --env dev --module core
#   destroy --env dev
#   destroy_one --env dev --module core

. bin/env.sh

_helmfile() {
  local env="$1"; shift
  local module="$1"; shift
  local selector=""
  [ -n "${module}" ] && selector="--selector name=${env}--platypod--${module}"
  helmfile --environment "${env}" ${selector} "$@"
}

deploy() {
  local env="${PLATYPOD__HELM__DEFAULT_ENV}"
  local dry_run=""

  while [ $# -gt 0 ]; do
    case "$1" in
      "--env") env="$2"; shift 2 ;;
      "--dry-run") dry_run="--dry-run"; shift ;;
      *) shift ;;
    esac
  done

  _helmfile "${env}" "" sync ${dry_run}
}

deploy_one() {
  local env="${PLATYPOD__HELM__DEFAULT_ENV}"
  local module=""

  while [ $# -gt 0 ]; do
    case "$1" in
      "--env") env="$2"; shift 2 ;;
      "--module") module="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  _helmfile "${env}" "${module}" sync
}

destroy() {
  local env="${PLATYPOD__HELM__DEFAULT_ENV}"

  while [ $# -gt 0 ]; do
    case "$1" in
      "--env") env="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  _helmfile "${env}" "" destroy
}

destroy_one() {
  local env="${PLATYPOD__HELM__DEFAULT_ENV}"
  local module=""

  while [ $# -gt 0 ]; do
    case "$1" in
      "--env") env="$2"; shift 2 ;;
      "--module") module="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  _helmfile "${env}" "${module}" destroy
}
