# Shared helpers of the build scripts.
# shellcheck shell=bash

CACHE_DIR="${CACHE_DIR:-$HOME/.cache/netaigis-dsm-modules}"

log() {
  printf '\n==> %s\n' "$*" >&2
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# Downloads once into CACHE_DIR and prints the local path. With a SHA-256
# the file is verified on every call. The cache name includes the parent
# directory: several platforms publish a different linux-4.4.x.txz.
fetch() {
  local url="$1"
  local sha256="${2:-}"
  local path="${url//%20/_}"
  local file
  file="$CACHE_DIR/$(basename "$(dirname "$path")")_$(basename "$path")"

  mkdir -p "$CACHE_DIR"

  if [[ ! -f "$file" ]]
  then
    log "Download $(basename "$file")"
    curl -fL --retry 3 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi

  if [[ -n "$sha256" ]]
  then
    echo "$sha256  $file" | sha256sum -c - >&2 ||
      die "Checksum mismatch: $file"
  fi

  echo "$file"
}
