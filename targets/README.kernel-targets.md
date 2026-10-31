# NetAigis kernel targets

All kernel module builds (not just xt_u32) are identified by platform and
kernel-release extracted from the last successful built kernel modules.
The `kernel-index.tsv` records every resulting module and its observed
`vermagic`. The `kernel-compatibility.tsv` is a legacy DSM release-to-kernel
lookup only and is NOT a build target matrix.

Keep the exact kernel sources, synoconfig, toolchain, ABI and module list
inside each `.conf` target. Do not treat equal `uname -r` alone as proof of
binary compatibility after a toolchain, kernel config, or ABI change.

To associate a new DSM release with an existing target, first verify the
unchanged kernel/ABI; update the compatibility map only, not the build target.
New kernels or platforms require a separate canonical target.
