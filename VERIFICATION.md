# Native ARM64 MySQL 5.7.32 verification

Completed on 2026-10-07 with native ARM64 Docker Desktop. The built image is available on the tested machine as **`mysql:5.7.32-arm64-local`**. Publishing this source repository does not publish the image to a registry.

| Identity | Value |
| --- | --- |
| Local image/index digest | `sha256:c392a0fc59087a41d0f9d56a11f190e549ddd485aded29be06053106e31d59f9` |
| ARM64 runtime manifest | `sha256:deee207f6ce107259946e9c5be3d1f1c05d54edd84bac5c53e064a1d9ee5d930` |
| Runtime config digest | `sha256:ae65e1916df649800e9330c5e4d9020f1c69059502b816d3b4c28a149cc573db` |
| Platform / reported image size | `linux/arm64` / 1,848,768,957 bytes |
| Retained builder image | `mysql-5.7.32-arm64-builder:local`, ID `sha256:1ee38955b3b6b3dbfe17d30de16728c5c1cba2ea70170c89f69d7900b97e193f` |
| Engine | Native ARM64 Docker Desktop, 10 CPUs, about 32 GB RAM; Linuxkit kernel |
| Build | Debian GCC 8.3.0, CMake 3.13.4, six parallel jobs |

Image metadata is in [verification/image-inspect.json](verification/image-inspect.json). The local digest is an identity for this build, not a publicly downloadable image. The repository tracks selected evidence under `verification/`; full build logs and newly generated test output remain in ignored local `artifacts/` and `tests/results/` directories.

## Validation outcomes

Executed:

```sh
./tests/validate.sh
./tests/compose-smoke.sh
```

Both finished with exit status **0**. The focused suite took **49 seconds**, or **50 seconds including cleanup**. The independent Compose smoke took **25 seconds including cleanup**. These are synthetic validation durations, not production restore benchmarks.

| Check | Result |
| --- | --- |
| Native binaries | `mysqld`, `mysql`, `mysqldump`: ELF machine 183 (AArch64), running on `aarch64`; all report exactly Oracle MySQL 5.7.32. |
| Release plugins | All 19 plugins are AArch64; `ldd` found no missing dependencies. |
| Initialization | Root and application TCP authentication, wrong-password rejection, `_FILE` passwords, database/user/root-host creation, SQL/gzip SQL and sourced/executable shell hooks passed. |
| Command/config | Command passthrough, leading server option, and both configuration include directories passed. |
| SQL behavior | Integer keys, utf8mb4 including emoji, exact decimals, binary values, NULLs, temporal conversion, views/routines/triggers, unique/FK constraints and expected strict-mode errors passed. |
| Persistence | SIGTERM exited 0 without OOM; recreating the container retained the same data and objects, skipped hooks, and ignored changed initialization credentials. |
| Logical backup/restore | Matching `mysqldump` streamed one application database, including views/triggers/routines/events, to a separate new volume. Before/after snapshots matched and restored triggers/views executed correctly. Local system users were preserved. |
| Defaults/options | Default scheduler `OFF`; isolated restore scheduler `DISABLED`; timezone import/skip, explicit empty-password opt-in, working generated root password and conflicting direct/file credential rejection passed. |
| Compose restoration | Resolved config inspected before startup; new named volume and actual `127.0.0.1` port binding verified. The exact README application-user import succeeded; attempted `mysql.user` update failed with error 1142 and preserved the local account. Graceful shutdown passed. |
| Runtime layout | All six recovered configuration files passed byte-for-byte SHA256 comparison. The alternative points to `/etc/mysql/mysql.cnf`; UID/GID are 999/999, data/run modes 1777, mysql-files mode 0770, all owned by mysql. |

Evidence:

- [Focused checks and timings](verification/focused-checks.tsv), [run status](verification/focused-run.tsv), [native binaries](verification/native-binaries.txt), [plugins](verification/native-plugins.txt).
- [Compose result](verification/compose-result.txt), [resolved configuration](verification/compose-resolved.json), [cleanup](verification/compose-cleanup.txt).
- [Runtime configuration/layout check](verification/runtime-layout-check.txt), [compiler/linkage evidence](verification/build-binaries.txt), [selected CMake settings](verification/cmake-settings.txt).

All validation containers, their disposable volumes and networks were removed. Existing application/database resources were not modified. Database files and compiler outputs remained in Docker-managed storage. No production backups or data directories were searched, mounted or imported.

The first focused run stopped because Docker Desktop's macOS bind mount returned `test -x` true for a mode-0644 shell hook. A [minimal probe](verification/bind-mount-mode-probe.txt) confirmed this. The hooks now use a disposable Linux volume, and both hook modes passed without changing the official entrypoint. The full first-run log remains local; ignored macOS provenance tar headers in the passing run do not affect its Linux file modes or contents.

A later [targeted builder-selection check](verification/builder-selection-verification.txt) used real Docker inspection while intercepting build/container mutations. Local selection and context pinning passed; the real `docker-container` builder and host override were rejected. Remote-endpoint and non-ARM64 responses were simulated. No MySQL rebuild or global selection change occurred. A separate [read-only restore configuration check](verification/restore-compose-resolution.txt) verified the documented distinct project/volume, available localhost port, and runtime event isolation without starting containers.

## Measured defaults

The [unmodified effective settings](verification/default-settings.tsv) agree with the recovered source/build/configuration evidence:

| Setting | Native observed value |
| --- | --- |
| Version / engine | `5.7.32` / `InnoDB` |
| Server charset / collation | `latin1` / `latin1_swedish_ci` |
| Timezone | `SYSTEM`, system timezone `UTC`; seasonal Paris conversions passed after timezone-table import |
| Event scheduler / table-name case | `OFF` / `lower_case_table_names=0` |
| Explicit timestamp defaults | `OFF` |
| InnoDB page / buffer pool | 16 KiB / 128 MiB |
| InnoDB file format / large prefix / file per table / strict mode | `Barracuda` / `ON` / `ON` / `ON` |
| InnoDB commit flush / redo files / doublewrite | `1` / two 48 MiB files / `ON` |
| Server max packet / connections / group concat | 4 MiB / 151 / 1024 |

Measured SQL mode:

```text
ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION
```

[Source default evidence](research/default-settings-evidence.md) maps every measured variable to the verified source and reference configuration. This supports an **inferred reference match**: the AMD64 reference was inspected statically and never executed. UTC describes this container environment, not the unavailable production server. The synthetic schema explicitly uses utf8mb4 while preserving the server's historical default charset.

## Build evidence and deviations

The successful native MySQL compilation/install stage took **704.1 seconds**, packaging **81.4 seconds**, and builder export/load **146.6 seconds**. The [selected build timing evidence](verification/build-timing.txt) records those stage observations; the full logs remain in ignored local `artifacts/`. Dependency preparation was cached in that run. Final runtime assembly took approximately **52 seconds** with its base cached, using the retained builder; this measurement uses the build-log completion timestamp. These are separate stage observations, not a fresh end-to-end build benchmark. The updated wrapper performs the same two successful stages and records full duration on future runs; it was not rerun solely to obtain a cold timing.

Verified matches include exact unchanged Oracle MySQL source, the Debian 10.7 ARM64 counterpart of the original base, byte-identical official entrypoint/configuration, recovered release build features, all release tools/plugins, pinned public dependency inputs, and static OpenSSL 1.1.1g inclusion in all three required binaries. The native OpenSSL shared-link probe passed.

Necessary differences are documented in [README.md](README.md) and [reference provenance](reference/PROVENANCE.md): ARM64 architecture and Debian architecture-specific libraries; replacement of private dependency paths; accepted upstream OpenSSL ARM assembly visibility fix; local package suffix `+arm64.1`; omitted separate debug server/debug plugin copies; retained release debug symbols and larger image; omitted service/database package maintainer scripts. Runtime package configuration explicitly keeps the recovered official conffiles.

The original Oracle compiler and production kernel/configuration remain unknown. Oracle's complete unit/integration suites, replication clusters, LDAP, memcached plugin workflows, and every optional initialization switch were not exercised. **Real production-dump and Rails integration compatibility remain unverified.** Physical backup restoration was not attempted. No AMD64 benchmark or unmeasured speedup claim is included.

## Publication checks

The published source excludes downloaded archives/binaries, extracted upstream trees, full build logs, temporary files, credentials and database data. A [fresh input-recovery check](verification/input-recovery.json) downloaded all seven required inputs into an empty temporary directory with the publication `fetch-inputs.sh`; every pinned hash passed. The downloads were removed after recording the receipt. This checks recovery, not a second image build.

Publication checks also covered shell syntax, documented Compose resolution, selected files and Markdown links. Third-party notices and exact upstream license texts are retained under [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and `reference/licenses/`. Only source and concise verification evidence are published; the container image remains local.
