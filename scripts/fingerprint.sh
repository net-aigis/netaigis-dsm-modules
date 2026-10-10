#!/usr/bin/env bash
# Validates a device fingerprint and prints its id.
#
# Usage: scripts/fingerprint.sh fingerprints/<id>.txt
#
# A fingerprint has exactly these lines in this order. Values are checked
# strictly because fingerprints come from customer devices via the
# Cloudflare Worker.
#
#   netaigis-kmod-fingerprint=1
#   arch=x86_64
#   platform=v1000
#   dsm_version=7.3
#   dsm_build=86009
#   dsm_smallfix=4
#   kernel_release=4.4.302+
#   kernel_version=#86009 SMP Wed Nov 26 18:19:20 CST 2025
#   vermagic=4.4.302+ SMP mod_unload
#   modules=ip_set_hash_net
#
# The id is the first 16 hex characters of the SHA-256 of the file.
set -euo pipefail

file="${1:?Usage: scripts/fingerprint.sh <fingerprint file>}"

die() {
  echo "Invalid fingerprint $file: $*" >&2
  exit 1
}

keys=(netaigis-kmod-fingerprint arch platform dsm_version dsm_build dsm_smallfix
      kernel_release kernel_version vermagic modules)
patterns=(
  '^1$'
  '^[a-z0-9_]{1,16}$'
  '^[a-z0-9]{1,32}$'
  '^[0-9]{1,2}\.[0-9]{1,2}$'
  '^[0-9]{1,6}$'
  '^[0-9]{1,3}$'
  '^[0-9][0-9a-z.+_-]{0,63}$'
  '^#[0-9A-Za-z :+._-]{1,127}$'
  '^[0-9A-Za-z .+_-]{1,127}$'
  '^[a-z0-9_]{1,32}( [a-z0-9_]{1,32}){0,15}$'
)

[[ -f "$file" ]] || die "file not found"
[[ "$(tail -c 1 "$file" | od -An -c | tr -d ' ')" == '\n' ]] || die "missing final newline"
[[ "$(wc -l < "$file")" -eq "${#keys[@]}" ]] || die "expected ${#keys[@]} lines"

i=0
while IFS= read -r line
do
  key="${line%%=*}"
  value="${line#*=}"
  [[ "$key" == "${keys[$i]}" ]] || die "line $((i + 1)) must be ${keys[$i]}="
  [[ "$value" =~ ${patterns[$i]} ]] || die "invalid value for ${keys[$i]}: $value"
  i=$((i + 1))
done < "$file"

sha256sum "$file" | cut -c1-16
