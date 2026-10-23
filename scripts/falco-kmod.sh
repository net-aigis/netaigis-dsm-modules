#!/usr/bin/env bash
# Builds Falco's kernel module against a kernel tree that build.sh has
# already configured and prepared. The module is not part of Synology's
# sources. The result is scap.ko, which is the name Falco loads.
#
# Usage: scripts/falco-kmod.sh <kernel_src> <arch> <cross_compile> <out_dir>
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=scripts/lib.sh
source "$REPO_DIR/scripts/lib.sh"

kernel_src="${1:?Usage: scripts/falco-kmod.sh <kernel_src> <arch> <cross_compile> <out_dir>}"
arch="${2:?}"
cross_compile="${3:?}"
out_dir="${4:?}"

FALCO_LIBS_VERSION="0.26.1"
FALCO_LIBS_URL="https://github.com/falcosecurity/libs/archive/refs/tags/${FALCO_LIBS_VERSION}.tar.gz"
FALCO_LIBS_SHA256="4ded90e99fe0ecdd50d63395e8c9a2333cfe1d839dcf4fdbbcc2201cf44628f6"

command -v cmake >/dev/null || die "cmake not found"

archive="$(fetch "$FALCO_LIBS_URL" "$FALCO_LIBS_SHA256")"
src="$out_dir/libs"
build="$out_dir/cmake"
rm -rf "$src" "$build"
mkdir -p "$src"
tar -xzf "$archive" -C "$src" --strip-components=1

# Kernel 4.4 still defines a few legacy syscall numbers above 1023.
# Falco's table has 512 entries, so those initializers do not compile.
python3 - "$src/driver" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
entry_re = re.compile(r'^\s*\[(__NR_[A-Za-z0-9_]+) - SYSCALL_TABLE_ID0\] = ')
ifdef_re = re.compile(r'^#ifdef (__NR_[A-Za-z0-9_]+)\s*$')
guard = "#if defined(%s) && ((%s - SYSCALL_TABLE_ID0) < SYSCALL_TABLE_SIZE)\n"
for name in ("syscall_table.c", "syscall_table64.c"):
    path = root / name
    lines = path.read_text().splitlines(keepends=True)
    out = []
    i = 0
    while i < len(lines):
        ifdef = ifdef_re.match(lines[i])
        nxt = entry_re.match(lines[i + 1]) if i + 1 < len(lines) else None
        if ifdef and nxt and ifdef.group(1) == nxt.group(1):
            nr = ifdef.group(1)
            out.append(guard % (nr, nr))
            i += 1
            continue
        entry = entry_re.match(lines[i])
        if entry and not (out and out[-1].startswith("#if defined(")):
            nr = entry.group(1)
            out.append(guard % (nr, nr))
            out.append(lines[i])
            out.append("#endif\n")
            i += 1
            continue
        out.append(lines[i])
        i += 1
    path.write_text("".join(out))
PY

# The driver's own Makefiles call the kernel build without ARCH. On a
# cross build that uses the host architecture and the target compiler
# rejects the flags. Pass the target architecture through.
sed -i \
  's|KERNELDIR="$(KERNELDIR)"|ARCH="$(ARCH)" CROSS_COMPILE="$(CROSS_COMPILE)" KERNELDIR="$(KERNELDIR)"|' \
  "$src/driver/configure/Makefile.inc.in"
for makefile in "$src/driver/Makefile.in" "$src/driver/configure/Makefile"
do
  sed -i \
    -e 's|$(MAKE) -C $(KERNELDIR) M=$(TOP) modules|$(MAKE) -C $(KERNELDIR) M=$(TOP) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules|' \
    -e 's|$(MAKE) -C $(KERNELDIR) M=$(TOP) clean|$(MAKE) -C $(KERNELDIR) M=$(TOP) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) clean|' \
    "$makefile"
done

cmake -S "$src/driver" -B "$build" \
  -DDRIVER_VERSION="$FALCO_LIBS_VERSION" \
  -DGIT_COMMIT="$FALCO_LIBS_VERSION" \
  -DCMAKE_MODULE_PATH="$src/cmake/modules" \
  -DBUILD_DRIVER=OFF \
  -DENABLE_DKMS=OFF

# The generated Makefile has no "modules" target of its own. "all" calls
# the kernel build, which is what compiles scap.ko.
make -C "$build/src" -j"$(nproc)" \
  KERNELDIR="$kernel_src" \
  ARCH="$arch" \
  CROSS_COMPILE="$cross_compile"

[[ -f "$build/src/scap.ko" ]] || die "scap.ko was not built"
cp "$build/src/scap.ko" "$out_dir/scap.ko"
