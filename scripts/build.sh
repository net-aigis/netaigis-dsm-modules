#!/usr/bin/env bash
# Builds the kernel modules of one target from Synology's original GPL
# sources and toolchain. Used unchanged locally and in GitHub Actions.
#
# Usage: scripts/build.sh targets/<target>.conf
#
# Environment:
#   CACHE_DIR  downloaded archives  (default: ~/.cache/netaigis-dsm-modules)
#   BUILD_DIR  extracted sources    (default: /tmp/netaigis-dsm-build)
#   DIST_DIR   build results        (default: <repo>/dist)
#
# BUILD_DIR is a fixed path on purpose: kernel modules embed the build path,
# so identical paths are needed to compare local and CI results.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_FILE="${1:?Usage: scripts/build.sh targets/<target>.conf}"

CACHE_DIR="${CACHE_DIR:-$HOME/.cache/netaigis-dsm-modules}"
BUILD_DIR="${BUILD_DIR:-/tmp/netaigis-dsm-build}"
DIST_DIR="${DIST_DIR:-$REPO_DIR/dist}"

[[ -f "$TARGET_FILE" ]] || { echo "Target not found: $TARGET_FILE" >&2; exit 1; }

TARGET="$(basename "$TARGET_FILE" .conf)"

# /usr/sbin is often not in PATH for regular users.
MODINFO="$(command -v modinfo || echo /usr/sbin/modinfo)"
[[ -x "$MODINFO" ]] || { echo "modinfo not found (package kmod)" >&2; exit 1; }

# shellcheck source=/dev/null
source "$TARGET_FILE"

log() {
  printf '\n==> %s\n' "$*"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# Downloads once into the cache and always verifies the checksum.
fetch() {
  local url="$1"
  local sha256="$2"
  local file
  file="$CACHE_DIR/$(basename "${url//%20/_}")"

  mkdir -p "$CACHE_DIR"

  if [[ ! -f "$file" ]]
  then
    log "Download $(basename "$file")" >&2
    curl -fL --retry 3 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi

  echo "$sha256  $file" | sha256sum -c - >&2 ||
    die "Checksum mismatch: $file"

  echo "$file"
}

kernel_archive="$(fetch "$KERNEL_URL" "$KERNEL_SHA256")"
toolchain_archive="$(fetch "$TOOLCHAIN_URL" "$TOOLCHAIN_SHA256")"

target_build="$BUILD_DIR/$TARGET"
kernel_src="$target_build/$KERNEL_DIR"

log "Extract sources to $target_build"

# The toolchain archive contains read-only directories.
if [[ -d "$target_build" ]]
then
  chmod -R u+w "$target_build"
  rm -rf "$target_build"
fi

mkdir -p "$target_build"
tar -xJf "$kernel_archive" -C "$target_build"
tar -xJf "$toolchain_archive" -C "$target_build"

cross_compile="$target_build/$TOOLCHAIN_PREFIX"
[[ -x "${cross_compile}gcc" ]] || die "Toolchain compiler missing: ${cross_compile}gcc"

make_args=(
  -C "$kernel_src"
  ARCH="$ARCH"
  CROSS_COMPILE="$cross_compile"
  LOCALVERSION="$LOCALVERSION"
)

log "Configure kernel ($SYNOCONFIG)"
[[ -f "$kernel_src/$SYNOCONFIG" ]] || die "Kernel config missing: $SYNOCONFIG"
cp "$kernel_src/$SYNOCONFIG" "$kernel_src/.config"
make "${make_args[@]}" olddefconfig

for option in $REQUIRED_CONFIG
do
  grep -qx "$option" "$kernel_src/.config" ||
    die "Kernel option not set as required: $option"
done

release="$(make -s "${make_args[@]}" kernelrelease)"
[[ "$release" == "$KERNEL_RELEASE" ]] ||
  die "Kernel release is $release, expected $KERNEL_RELEASE"

log "Build modules in $MODULE_DIR"
make -j"$(nproc)" "${make_args[@]}" modules_prepare
make -j"$(nproc)" "${make_args[@]}" M="$MODULE_DIR" modules

out="$DIST_DIR/$TARGET"
rm -rf "$out"
mkdir -p "$out"

log "Verify and collect modules"
for module in $MODULES
do
  ko="$kernel_src/$MODULE_DIR/$module.ko"
  [[ -f "$ko" ]] || die "Module not built: $module.ko"

  vermagic="$("$MODINFO" -F vermagic "$ko")"
  [[ "$vermagic" == "$KERNEL_RELEASE "* ]] ||
    die "$module.ko has vermagic '$vermagic', expected $KERNEL_RELEASE"

  cp "$ko" "$out/"
done

(
  cd "$out"
  sha256sum ./*.ko | sed 's| \./| |' > SHA256SUMS
)

{
  echo "target=$TARGET"
  echo "dsm_version=$DSM_VERSION"
  echo "platform=$PLATFORM"
  echo "kernel_release=$KERNEL_RELEASE"
  echo "kernel_sha256=$KERNEL_SHA256"
  echo "toolchain_sha256=$TOOLCHAIN_SHA256"
  echo "repo_commit=$(git -C "$REPO_DIR" rev-parse --verify -q HEAD || echo unknown)"
  echo "build_dir=$BUILD_DIR"
  for module in $MODULES
  do
    echo "vermagic_$module=$("$MODINFO" -F vermagic "$out/$module.ko")"
  done
} > "$out/build-info.txt"

log "Done: $out"
cat "$out/SHA256SUMS"
