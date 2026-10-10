# NetAigis DSM kernel modules

Linux kernel modules for Synology DiskStations that NetAigis-DSM needs but
DSM does not ship, for example `ip_set_hash_net` (ipset type `hash:net`).

The modules are built exclusively by GitHub Actions from Synology's original
GPL kernel sources and toolchain. Modules built on customer devices are never
published.

## Targets

| Target | DSM | Platform | Kernel | Modules |
|---|---|---|---|---|
| `dsm-7.3-86009_v1000` | 7.3-86009 | v1000 (e.g. DS2422+) | 4.4.302+ | `ip_set_hash_net` |

Each target is described in `targets/<target>.conf`: download URLs and
SHA-256 checksums of the Synology sources, kernel configuration, expected
kernel release and the modules to publish.

## Build

The same script runs locally and in CI:

```bash
scripts/build.sh targets/dsm-7.3-86009_v1000.conf
```

Requirements: `bash`, `curl`, `make`, `gcc`, `bc`, `bison`, `flex`,
`libelf` development files, `xz`, `kmod` (`modinfo`).

The script downloads the sources into `~/.cache/netaigis-dsm-modules`,
verifies their checksums, uses Synology's kernel configuration unchanged,
aborts if a required kernel option or the kernel release does not match,
and writes the modules with `SHA256SUMS` and `build-info.txt` to
`dist/<target>/`.

## Verifying a published module

Builds are reproducible: the same target built in the fixed build directory
`/tmp/netaigis-dsm-build` yields bit-identical modules. To check a release,
build the target locally and compare `dist/<target>/SHA256SUMS` with the
`SHA256SUMS` in the release archive.

## Releases

A tag `v*` publishes a GitHub release with one archive per target and a
`SHA256SUMS` file over all archives. Archives and modules carry a signed
build provenance attestation from GitHub Actions:

```bash
gh attestation verify ip_set_hash_net.ko --repo <owner>/netaigis-dsm-modules
```

## License

GNU General Public License version 2 (see `LICENSE`). This covers the build
scripts in this repository and the published modules, which are built from
the Linux kernel sources released by Synology under the GPLv2.
