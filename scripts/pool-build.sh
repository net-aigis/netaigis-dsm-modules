#!/usr/bin/env bash
# Builds and signs the pool entry for one device fingerprint.
#
# Usage: scripts/pool-build.sh fingerprints/<id>.txt
#
# Environment:
#   MODULE_SIGNING_KEY  Ed25519 private key (PEM), required
#   POOL_DIR            output (default: <repo>/pool)
#   plus the variables of scripts/build.sh
#
# Output in POOL_DIR/<id>/: the modules, manifest and manifest.sig.
# The manifest is the fingerprint followed by one line per module:
#   module <name> <sha256>
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FP_FILE="${1:?Usage: scripts/pool-build.sh fingerprints/<id>.txt}"
POOL_DIR="${POOL_DIR:-$REPO_DIR/pool}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ -n "${MODULE_SIGNING_KEY:-}" ]] || die "MODULE_SIGNING_KEY is not set"

id="$("$REPO_DIR/scripts/fingerprint.sh" "$FP_FILE")"

fp() {
  sed -n "s/^$1=//p" "$FP_FILE"
}

trim() {
  sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

target="dsm-$(fp dsm_version)-$(fp dsm_build)_$(fp platform)"
target_file="$REPO_DIR/targets/$target.conf"
[[ -f "$target_file" ]] || die "No target $target for fingerprint $id"

# shellcheck source=/dev/null
source "$target_file"

[[ "$KERNEL_RELEASE" == "$(fp kernel_release)" ]] ||
  die "Target $target has kernel $KERNEL_RELEASE, device has $(fp kernel_release)"
[[ "$ARCH" == "$(fp arch)" ]] ||
  die "Target $target is $ARCH, device is $(fp arch)"

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

for module in $(fp modules)
do
  ko="$REPO_DIR/dist/$target/$module.ko"
  vermagic="$("$MODINFO" -F vermagic "$ko" | trim)"
  [[ "$vermagic" == "$(fp vermagic | trim)" ]] ||
    die "$module.ko has vermagic '$vermagic', device has '$(fp vermagic)'"

  cp "$ko" "$out/"
  echo "module $module $(sha256sum "$ko" | cut -d' ' -f1)" >> "$out/manifest"
done

key_file="$(mktemp)"
trap 'rm -f "$key_file"' EXIT
printf '%s\n' "$MODULE_SIGNING_KEY" > "$key_file"

openssl pkeyutl -sign -inkey "$key_file" -rawin \
  -in "$out/manifest" -out "$out/manifest.sig"
openssl pkeyutl -verify -pubin -inkey "$REPO_DIR/module-signing.pub" -rawin \
  -in "$out/manifest" -sigfile "$out/manifest.sig" > /dev/null ||
  die "Signature does not verify with module-signing.pub"

echo "Pool entry fp-$id:"
cat "$out/manifest"
