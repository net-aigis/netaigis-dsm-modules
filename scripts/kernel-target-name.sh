#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# == 2 ]] || exit 2
platform="$1"; release="$2"
[[ "$platform" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo 'ABBRUCH: Plattform ungueltig' >&2; exit 2; }
[[ "$release" =~ ^[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9.+_-]*$ ]] || { echo 'ABBRUCH: Kernelrelease ungueltig' >&2; exit 2; }
slug="${release//+/_plus}"
printf '%s-k%s\n' "$platform" "$slug"
