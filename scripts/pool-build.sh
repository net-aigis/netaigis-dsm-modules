#!/usr/bin/env bash
# Builds and signs the pool entry for one device fingerprint.
#
# Usage: scripts/pool-build.sh [--unsigned] fingerprints/<id>.txt
#
#   --unsigned  build without signature, for a device building its own
#               modules; such entries are never published
#
# Environment:
#   MODULE_SIGNING_KEY  Ed25519 private key (PEM), required unless --unsigned
#   POOL_DIR            output (default: <repo>/pool)
#   plus the variables of scripts/build.sh
#
# The target is targets/dsm-<version>-<build>_<platform>.conf if present,
# otherwise it is derived from Synology's archive (scripts/target-gen.sh).
#
# Output in POOL_DIR/<id>/: the modules, manifest, manifest.sig and the
# target used (target.conf). The manifest is the fingerprint followed by one
# line per module:
#   module <name> <sha256>
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

signed=1
if [[ "${1:-}" == "--unsigned" ]]
then
  signed=0
  shift
fi

FP_FILE="${1:?Usage: scripts/pool-build.sh [--unsigned] fingerprints/<id>.txt}"
POOL_DIR="${POOL_DIR:-$REPO_DIR/pool}"

# shellcheck source=scripts/lib.sh
source "$REPO_DIR/scripts/lib.sh"

(( signed == 0 )) || [[ -n "${MODULE_SIGNING_KEY:-}" ]] ||
  die "MODULE_SIGNING_KEY is not set"

id="$("$REPO_DIR/scripts/fingerprint.sh" "$FP_FILE")"

fp() {
  sed -n "s/^$1=//p" "$FP_FILE"
}

trim() {
  sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

work_dir="$(mktemp -d)"
key_file="$work_dir/signing.key"
trap 'rm -rf "$work_dir"' EXIT

target_file="$REPO_DIR/targets/dsm-$(fp dsm_version)-$(fp dsm_build)_$(fp platform).conf"

if [[ ! -f "$target_file" ]]
then
  log "No fixed target for fingerprint $id, deriving it from Synology's archive"
  target_file="$("$REPO_DIR/scripts/target-gen.sh" "$FP_FILE" "$work_dir")"
fi

target="$(basename "$target_file" .conf)"

# shellcheck source=/dev/null
source "$target_file"

[[ "$KERNEL_RELEASE" == "$(fp kernel_release)" ]] ||
  die "Target $target has kernel $KERNEL_RELEASE, device has $(fp kernel_release)"
[[ "${MACHINE:-$ARCH}" == "$(fp arch)" ]] ||
  die "Target $target is ${MACHINE:-$ARCH}, device is $(fp arch)"

for module in $(fp modules)
do
  [[ " $MODULES " == *" $module "* ]] ||
    die "Target $target does not provide $module"
done

DIST_DIR="$REPO_DIR/dist" "$REPO_DIR/scripts/build.sh" "$target_file"

MODINFO="$(command -v modinfo || echo /usr/sbin/modinfo)"
out="$POOL_DIR/$id"
rm -rf "$out"
mkdir -p "$out"

cp "$FP_FILE" "$out/manifest"
cp "$target_file" "$out/target.conf"

for module in $(fp modules)
do
  ko="$REPO_DIR/dist/$target/$module.ko"
  vermagic="$("$MODINFO" -F vermagic "$ko" | trim)"
  [[ "$vermagic" == "$(fp vermagic | trim)" ]] ||
    die "$module.ko has vermagic '$vermagic', device has '$(fp vermagic)'"

  cp "$ko" "$out/"
  echo "module $module $(sha256sum "$ko" | cut -d' ' -f1)" >> "$out/manifest"
done

if (( signed == 1 ))
then
  printf '%s\n' "$MODULE_SIGNING_KEY" > "$key_file"

  openssl pkeyutl -sign -inkey "$key_file" -rawin \
    -in "$out/manifest" -out "$out/manifest.sig"
  openssl pkeyutl -verify -pubin -inkey "$REPO_DIR/module-signing.pub" -rawin \
    -in "$out/manifest" -sigfile "$out/manifest.sig" > /dev/null ||
    die "Signature does not verify with module-signing.pub"

  echo "Pool entry fp-$id:"
else
  echo "Unsigned local entry $id:"
fi

cat "$out/manifest"
