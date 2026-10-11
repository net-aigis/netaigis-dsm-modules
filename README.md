# NetAigis DSM kernel modules

Linux kernel modules for Synology DiskStations that NetAigis-DSM needs but
DSM does not ship, for example `ip_set_hash_net` (ipset type `hash:net`).

The modules are built exclusively by GitHub Actions from Synology's original
GPL kernel sources and toolchain. Modules built on customer devices are never
published.

## Targets

| Target | DSM | Platform | Kernel | Modules | Tested on a device |
|---|---|---|---|---|---|
| `dsm-7.3-86009_v1000` | 7.3-86009 | v1000 (e.g. DS2422+) | 4.4.302+ | `ip_set_hash_net` | yes |
| `dsm-7.3-86009_rtd1619b` | 7.3-86009 | rtd1619b (e.g. DS124, DS223, DS423) | 5.10.55+ | all ipset modules | no |
| `dsm-7.3-86009_armada37xx` | 7.3-86009 | armada37xx (e.g. DS120j, DS220j) | 4.4.302+ | all ipset modules | no |

Each target is described in `targets/<target>.conf`: download URLs and
SHA-256 checksums of the Synology sources, kernel configuration, expected
kernel release and the modules to publish.

`HARDWARE_TESTED="yes"` marks targets whose modules have been loaded on a
real device. The ARM targets only prove that Synology's sources build; their
kernel release is assumed. Pool releases for untested targets are published
as pre-releases with a note; devices load them all the same. Once a device
confirms a platform, set `HARDWARE_TESTED="yes"` and clear the pre-release
flag of its pool releases. A fixed target whose kernel release does not
match a reported fingerprint is ignored, and the target is derived from
Synology's archive instead.

## Build

The same script runs locally and in CI:

```bash
scripts/build.sh targets/dsm-7.3-86009_v1000.conf
```

Requirements: `bash`, `curl`, `make`, `gcc`, `bc`, `bison`, `flex`,
`libelf` and `libssl` development files, `xz`, `kmod` (`modinfo`).

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

A version tag `MAJOR.MINOR.PATCH` (for example `1.0.0`) publishes a GitHub release with one archive per target and a
`SHA256SUMS` file over all archives. Archives and modules carry a signed
build provenance attestation from GitHub Actions:

```bash
gh attestation verify ip_set_hash_net.ko --repo <owner>/netaigis-dsm-modules
```

## Module pool

Devices look up their modules by fingerprint. A fingerprint describes only
technical properties, never hostname, serial number or model:

```text
netaigis-kmod-fingerprint=1
arch=x86_64
platform=v1000
dsm_version=7.3
dsm_build=86009
dsm_smallfix=4
kernel_release=4.4.302+
kernel_version=#86009 SMP Wed Nov 26 18:19:20 CST 2025
vermagic=4.4.302+ SMP mod_unload
modules=ip_set_hash_net
```

Its id is the first 16 hex characters of the file's SHA-256. Each known
fingerprint is stored as `fingerprints/<id>.txt` (format and validation in
`scripts/fingerprint.sh`). For every fingerprint without a release, the
`Module pool` workflow builds the matching target, checks kernel release,
architecture and `vermagic` against the fingerprint, signs a manifest and
publishes the release `fp-<id>` with:

- `manifest`: the fingerprint followed by `module <name> <sha256>` lines
- `manifest.sig`: Ed25519 signature of the manifest (`module-signing.pub`)
- `target.conf`: the Synology sources used, with their SHA-256
- the modules

The target is `targets/dsm-<version>-<build>_<platform>.conf` if present.
Otherwise `scripts/target-gen.sh` derives it from Synology's archive: the
GPL kernel source and toolchain of the fingerprint's DSM build, platform and
architecture (`x86_64`, `aarch64`). Kernel directory, toolchain prefix,
local version suffix, module directories and required kernel options
(`modules.conf`) are then taken from the sources.

### Building on the device

A device whose fingerprint has no release yet builds its modules itself
with the same script:

```bash
scripts/pool-build.sh --unsigned fingerprint.txt
```

Unsigned entries are only used on the device that built them and are never
published. The public module always comes from the independent CI build.

### Fingerprint reports

Devices report a fingerprint without a release to a Cloudflare Worker
(`worker/`), without login or token:

```bash
curl -X POST --data-binary @fingerprint.txt https://<worker>/v1/fingerprint
```

The worker validates it with the same rules as `scripts/fingerprint.sh`,
limits requests per client IP and commits `fingerprints/<id>.txt` to the
separate repository `net-aigis/netaigis-dsm-fingerprints`. The worker
stores nothing else. Its GitHub token (secret `GITHUB_TOKEN`, fine-grained,
contents read/write on the fingerprint repository only) can never change
the build scripts in this repository.

The `Module pool` workflow runs every 30 minutes, reads the fingerprint
repository as data, skips invalid files and publishes `fp-<id>` for at most
5 new fingerprints per run.

Tests and deployment, in `worker/`:

```bash
node --test
npx wrangler secret put GITHUB_TOKEN
npx wrangler deploy
```

Devices verify the signature, that the manifest starts with their own
fingerprint, and every module checksum before loading anything:

```bash
openssl pkeyutl -verify -pubin -inkey module-signing.pub -rawin \
  -in manifest -sigfile manifest.sig
```

The private key exists only as the repository secret `MODULE_SIGNING_KEY`.

## License

GNU General Public License version 2 (see `LICENSE`). This covers the build
scripts in this repository and the published modules, which are built from
the Linux kernel sources released by Synology under the GPLv2.
