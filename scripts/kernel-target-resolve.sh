#!/usr/bin/env bash
# Resolve a DSM compatibility alias to a platform+kernel build target.
# DSM versions are lookup metadata, never identifiers of compiled modules.
set -Eeuo pipefail
[[ $# -eq 1 && "$1" =~ ^dsm-[0-9][A-Za-z0-9._+-]*_[A-Za-z0-9._-]+$ ]] || {
  printf 'ABBRUCH: Ungueltiger DSM-Kompatibilitaetsbezeichner\n' >&2
  exit 2
}
resolver_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
map="$resolver_dir/../targets/kernel-compatibility.tsv"
[[ -f "$map" ]] || { printf 'ABBRUCH: Kernel-Kompatibilitaetsdatei fehlt\n' >&2; exit 2; }
resolved="$(awk -F '\t' -v id="$1" '$1 == id {print $2}' "$map")"
[[ -n "$resolved" && "$resolved" != *$'\n'* && "$resolved" =~ ^[A-Za-z0-9._-]+$ ]] || {
  printf 'ABBRUCH: Kein eindeutiges Kernel-Target fuer %s\n' "$1" >&2
  exit 2
}
[[ -f "$resolver_dir/../targets/$resolved.conf" ]] || {
  printf 'ABBRUCH: Kernel-Target nicht vorhanden: %s\n' "$resolved" >&2
  exit 2
}
printf '%s\n' "$resolved"
