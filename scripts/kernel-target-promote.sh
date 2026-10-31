#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# == 2 ]] || exit 2
src="$1"; platform="$2"
[[ -f "$src" && ! -L "$src" ]] || { echo 'ABBRUCH: Generiertes Target fehlt' >&2; exit 2; }
line="$(grep -E '^KERNEL_RELEASE=' "$src" || true)"
[[ -n "$line" && "$line" != *$'\n'* ]] || { echo 'ABBRUCH: Kernelrelease im Ziel nicht eindeutig' >&2; exit 2; }
release="${line#*=}"
release="${release#\"}"; release="${release%\"}"
release="${release#\'}"; release="${release%\'}"
name="$(bash "$(dirname "${BASH_SOURCE[0]}")/kernel-target-name.sh" "$platform" "$release")" || exit 2
dest="$(dirname -- "$src")/$name.conf"
if [[ "$src" == "$dest" ]]; then exit 0; fi
if [[ -e "$dest" ]]; then
  if cmp -s -- "$src" "$dest"; then
    rm -- "$src"
  else
    printf 'ABBRUCH: Kernel-Target-Kollision: %s (andere Quellen/Konfiguration)\n' "$dest" >&2
    exit 2
  fi
else
  mv -- "$src" "$dest"
fi
printf 'Target aus Synology-Quellen erzeugt: %s\n' "$dest"
