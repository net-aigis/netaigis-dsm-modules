#!/usr/bin/env bash
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'ABBRUCH: kernel_src argument fehlt' >&2; exit 2; }
source_dir="$1"
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_file="$repo_dir/vendor/xt_u32/xt_u32.c"
header_file="$repo_dir/vendor/xt_u32/xt_u32.h"
[[ -f "$source_dir/Makefile" ]] || { echo 'ABBRUCH: vorbereiteter Kernelquellbaum fehlt' >&2; exit 1; }
[[ -f "$source_dir/net/netfilter/Makefile" ]] || { echo 'ABBRUCH: netfilter-Makefile fehlt' >&2; exit 1; }
[[ -d "$source_dir/include/uapi/linux/netfilter" ]] || { echo 'ABBRUCH: Kernel-UAPI fehlt' >&2; exit 1; }
printf "%s  %s\n" "dc018c7dff2fdb2f8235b33d2eb23326670b0a5d0fc6afafe2cee612c1ed4d92"  "$source_file" | sha256sum -c -
printf "%s  %s\n" "292177099c1a56ff43770bfbb0e0bd3a798cbde4c7101404bb384d313542b4bd"  "$header_file" | sha256sum -c -

kernel_c="$source_dir/net/netfilter/xt_u32.c"
kernel_h="$source_dir/include/uapi/linux/netfilter/xt_u32.h"
if [[ -e "$kernel_c" ]]; then
  cmp -s "$source_file" "$kernel_c" || { echo 'ABBRUCH: Kernelsource xt_u32.c bereits vorhanden, aber abweichend' >&2; exit 1; }
else
  cp "$source_file" "$kernel_c"
fi
if [[ -e "$kernel_h" ]]; then
  cmp -s "$header_file" "$kernel_h" || { echo 'ABBRUCH: vorhandener UAPI-Header weicht ab' >&2; exit 1; }
else
  cp "$header_file" "$kernel_h"
fi

makefile="$source_dir/net/netfilter/Makefile"
rule='obj-$(CONFIG_NETFILTER_XT_MATCH_U32) += xt_u32.o'
if ! grep -Fxq "$rule" "$makefile"; then
  if grep -Eq '^obj-\$\(CONFIG_NETFILTER_XT_MATCH_U32\)' "$makefile"; then
    echo 'ABBRUCH: vorhandene xt_u32-Kbuildregel weicht ab' >&2
    exit 1
  fi
  printf '\n%s\n' "$rule" >> "$makefile"
fi
printf 'xt_u32: Quellcode, Header und Kbuild im temporären Kernelbaum vorbereitet\n'
