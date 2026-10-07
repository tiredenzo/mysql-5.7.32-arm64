# Oracle MySQL 5.7.32 on native ARM64

Standalone image project for local database restoration and exploration on Apple Silicon. The server, `mysql`, and `mysqldump` are built from the verified Oracle **5.7.32** source, using native ARM64 execution throughout. The runtime is the pinned ARM64 Debian **10.7** base corresponding to the historical official image.

## Build

Requires a native ARM64 Docker engine, Docker Buildx/Compose, Bash, Python 3, `curl`, and the GitHub CLI (`gh`). `fetch-inputs.sh` downloads and verifies the pinned Oracle/dependency archives and ARM64 gosu binary into `inputs/`; archive/patch hashes are tracked in [inputs/SHA256SUMS](inputs/SHA256SUMS), and the gosu hash is pinned in `fetch-inputs.sh` and the Dockerfile. Downloaded archives, binaries, extracted source trees, and local build/test output are excluded from Git. Compiler output stays in Docker BuildKit storage.

The selected Buildx builder must use the `docker` driver with one node attached to a Docker context using a local Unix socket. `build.sh` verifies that context's daemon is native ARM64, pins both `--context` and `--builder` for both build stages, and uses the same context for all image operations. It rejects remote and `docker-container` builders, non-ARM64 daemons, and `DOCKER_HOST` overrides. It does not change global Docker or Buildx selections.

```sh
gh repo clone tiredenzo/mysql-5.7.32-arm64
cd mysql-5.7.32-arm64
./fetch-inputs.sh
BUILD_JOBS=6 ./build.sh
```

For Docker Desktop's local ARM64 `desktop-linux` context and builder, select them for this invocation after removing any host override:

```sh
unset DOCKER_HOST
DOCKER_CONTEXT=desktop-linux BUILDX_BUILDER=desktop-linux BUILD_JOBS=6 ./build.sh
```

`build.sh` pins `linux/arm64` and produces `mysql:5.7.32-arm64-local`. The Dockerfile also asserts ARM64 inside the build and verifies SHA256 inputs. Six jobs were selected for the tested Docker engine with 10 CPUs and about 32 GB RAM; lower `BUILD_JOBS` for smaller engines. Source downloads are public. Recovery of GitHub inputs uses `gh`; if authentication fails, run `gh auth login -h github.com`, then retry.

Debian packages come from the immutable `20210111T000000Z` Debian/security snapshots. APT verifies signed repository metadata and package hashes. Only historical metadata expiry checking is disabled (`check-valid-until=no`); authentication/integrity checks remain enabled. The snapshot's HTTP transport bootstraps the old base without adding a modern CA bundle.

Each build generates ignored local output under `artifacts/`: logs, measured duration, image identity and `/usr/share/mysql/arm64-build/` provenance copied out of the image. That provenance records the compiler, complete build package versions, CMake cache, package inventory, omissions and native binary/linkage evidence. Selected evidence from the tested build is tracked under `verification/` and summarized in [VERIFICATION.md](VERIFICATION.md). The recipe pins inputs and build settings; it does not claim bit-for-bit reproducible image bytes.

The script first completes and retains `mysql-5.7.32-arm64-builder:local`, then generates `artifacts/Dockerfile.runtime` from the base/runtime sections of the main recipe and assembles directly from those retained packages. This keeps a successful compiler/package result in Docker storage if a later runtime layer fails, without depending on intermediate cache retention. `artifacts/build-compile.log` records that stage. Packaging restores the original published Debian manifests after CMake's template generation, then the runtime applies the recovered reference configuration before registering its configuration alternative.

OpenSSL 1.1.1g requires the accepted upstream [ARM64 static-linking fix d741debb](https://github.com/openssl/openssl/commit/d741debb320bf54e8575d35603a44d4eb40fa1f9) to link its optimized assembly into the replication plugin. The pinned patch only changes internal symbol visibility/common declarations; it preserves the crypto algorithms, assembly acceleration and version. A native shared-library link probe verifies this failure path. Oracle MySQL source is unchanged. MySQL object files use a Docker-managed BuildKit cache; compilation can resume when the engine retains that cache. The retained builder image protects runtime assembly from intermediate cache loss.

## Run

The Compose example binds TCP to localhost port 3307 and uses the Docker-managed volume `mysql5732-arm64_mysql-data`. Its first use creates that volume; later uses of the same project reuse its existing data. It never mounts an existing database directory.

```sh
cp .env.example .env
# Edit .env: set two distinct passwords; choose database/user names if desired.
docker compose config --quiet
docker compose up -d --wait
docker compose logs mysql
```

`.env` is ignored by Git. `docker compose config` without `--quiet` prints resolved passwords; avoid saving that output. To stop and retain the volume:

```sh
docker compose down
```

Start again with `docker compose up -d --wait`. Initialization variables and `/docker-entrypoint-initdb.d` hooks run only on a fresh data directory. Changing passwords in `.env` does not change existing MySQL accounts.

The original entrypoint is unchanged. It supports `MYSQL_ROOT_PASSWORD`, `MYSQL_ALLOW_EMPTY_PASSWORD`, `MYSQL_RANDOM_ROOT_PASSWORD`, `MYSQL_ROOT_HOST`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_ONETIME_PASSWORD`, and `MYSQL_INITDB_SKIP_TZINFO`; its password/database/user/root-host options also support the corresponding `_FILE` form. It supports `.sql`, `.sql.gz`, `.sql.xz`, and sourced/executable `.sh` initialization hooks. Mount custom configuration files into `/etc/mysql/conf.d/` or `/etc/mysql/mysql.conf.d/`. Server arguments and other commands pass through:

```sh
docker run --rm mysql:5.7.32-arm64-local mysql --version
docker run --rm mysql:5.7.32-arm64-local mysqldump --version
```

The reusable image retains the reference's event scheduler default (`OFF`). It has no application-specific Rails settings.

## Later application-only logical restoration

`compose.restore.yaml` disables scheduled events at runtime; it keeps the same Compose project and data volume. Adding this override alone therefore reuses the normal project's `mysql5732-arm64_mysql-data` volume.

For a separate fresh restore, choose an unused project name and an available localhost port. This example uses `mysql5732-restore-review` and port 3308:

```sh
export RESTORE_PROJECT=mysql5732-restore-review
export MYSQL_PORT=3308
docker volume ls --filter "name=^${RESTORE_PROJECT}_mysql-data$" --format '{{.Name}}'
python3 -c 'import os,socket; s=socket.socket(); s.bind(("127.0.0.1",int(os.environ["MYSQL_PORT"]))); s.close()'
```

If the volume check prints a name, that project has existing data: choose another unused `RESTORE_PROJECT` for a fresh restore, or reuse it intentionally for subsequent access. If the port check fails, choose another available `MYSQL_PORT`. Keep the same `.env` credentials and record both values for later shells. Inspect the resolved configuration before starting:

```sh
docker compose -p "$RESTORE_PROJECT" -f compose.yaml -f compose.restore.yaml config --quiet
docker compose -p "$RESTORE_PROJECT" -f compose.yaml -f compose.restore.yaml up -d --wait
```

The following command restores an **application-only SQL dump** into the database named by `MYSQL_DATABASE`, authenticating as the application user whose grants are limited to that database. This preserves local users and system tables. It deliberately fails on operations needing global privileges.

```sh
docker compose -p "$RESTORE_PROJECT" -f compose.yaml -f compose.restore.yaml exec -T mysql sh -c \
  'MYSQL_PWD="$MYSQL_PASSWORD" exec mysql --user="$MYSQL_USER" --binary-mode=1 --default-character-set=utf8mb4 "$MYSQL_DATABASE"' \
  < /absolute/path/application-only.sql
```

For a gzip SQL dump, pipe `gzip -dc /absolute/path/application-only.sql.gz` into the same command. Import into a fresh application database; restoration changes its contents and DDL does not roll back atomically. The dump must contain only the intended application schema, with no `mysql`, `sys`, `performance_schema`, `information_schema`, global account/grant statements, or unrelated `CREATE DATABASE`/`USE` statements. A default schema argument does not sanitize SQL. Do not use `--force`; inspect any errors before proceeding.

If the dump has production `DEFINER` clauses, resolve their ownership explicitly for the local application user in a reviewed copy before importing. An unavailable production user or a privileged definer can cause views, triggers, routines or events to fail. Avoid global grants or importing system tables to work around that error. Events stay disabled even when imported; to preserve this isolation, continue using the restore override when recreating the container.

Use that same project name and override for subsequent access, shutdown, and restart. In a later shell, first export the recorded `RESTORE_PROJECT` and `MYSQL_PORT` values:

```sh
# Open the application database as its restricted user.
docker compose -p "$RESTORE_PROJECT" -f compose.yaml -f compose.restore.yaml exec mysql sh -c \
  'MYSQL_PWD="$MYSQL_PASSWORD" exec mysql --user="$MYSQL_USER" --default-character-set=utf8mb4 "$MYSQL_DATABASE"'
# Stop while retaining the project's data volume.
docker compose -p "$RESTORE_PROJECT" -f compose.yaml -f compose.restore.yaml down
# Later, inspect and start the same instance with events still disabled.
docker compose -p "$RESTORE_PROJECT" -f compose.yaml -f compose.restore.yaml config --quiet
docker compose -p "$RESTORE_PROJECT" -f compose.yaml -f compose.restore.yaml up -d --wait
```

Reusing a previously used project name reuses its volume; it does not create a fresh database or rerun initialization. These commands retain existing volumes and data.

If a source server later becomes available, an application-only logical export can be created with the matching client:

```sh
mysqldump --host=SOURCE_HOST --user=SOURCE_USER --password \
  --single-transaction --routines --triggers --events --hex-blob \
  --default-character-set=utf8mb4 --set-gtid-purged=OFF --no-tablespaces \
  APPLICATION_DATABASE > application-only.sql
```

Use an account allowed to read those objects. `--single-transaction` provides a consistent snapshot for transactional tables; concurrent DDL or nontransactional tables need separate handling. Export a single application database without `--all-databases` or `--databases`. The password prompt avoids putting the source password in the command line.

A physical backup or copied data directory is **not** a logical SQL dump and cannot be fed to this command. Do not reuse a production data directory directly. Physical recovery requires a separate assessment of backup format, architecture, configuration, consistency, encryption, and recovery tooling.

## Validate

```sh
IMAGE=mysql:5.7.32-arm64-local ./tests/validate.sh
./tests/compose-smoke.sh
```

The focused suite uses fresh disposable named Docker volumes and synthetic records. It checks exact versions and ELF ARM64, initialization/authentication/options/hooks/includes, persistent graceful restart, representative SQL behavior, and a logical dump/restore with views, triggers, routines and events. Each run generates ignored local results and effective settings under `tests/results/`; test resources are cleaned up. Published evidence from the completed run is tracked under `verification/`. See [tests/README.md](tests/README.md).

[Source default evidence](research/default-settings-evidence.md) maps those settings to the verified source and recovered build/configuration inputs. UTC is a container timezone observation, not an assumption about the unavailable production server.

The completed build, measured settings, validation results, and image identity are recorded in [VERIFICATION.md](VERIFICATION.md).

## Reference fidelity and limits

The official index is `mysql@sha256:e08834258fcc0efd01df358222333919df53d4a0d9b2a54da05b204b822e3b7b`. Its AMD64 child `sha256:860f4bcc18607de9f40a7453c7dc160313ecc3a5a46be3b060569b6216d348f6` was inspected statically; none of its binaries was executed. Provenance and configuration evidence are in [reference/PROVENANCE.md](reference/PROVENANCE.md).

| Area | Match or deviation |
| --- | --- |
| Source/behavior | Exact Oracle 5.7.32 source and original Debian packaging inputs, verified against [Oracle source metadata](https://repo.mysql.com/apt/debian/pool/mysql-5.7/m/mysql-community/mysql-community_5.7.32-1debian10.dsc). No SQL/storage-policy patches. |
| Native execution | ARM64 compiler and runtime, with ELF AArch64 checks; no AMD64 emulation. |
| Userspace | Pinned Debian 10.7 ARM64 base; dated Debian repositories closely match the reference's runtime package versions. Architecture-specific packages necessarily differ. |
| Build | Recovered `mysql_release`, DEB layout, full character sets/engines, MeCab system, NUMA ON, InnoDB Memcached enabled. Public pinned Boost 1.59.0 and Google Test/Mock 1.8.0 replace private dependency directories. |
| TLS | OpenSSL 1.1.1g statically included in the server and both clients, matching reference binary evidence; the official ARM64 internal-symbol link fix described above is applied. Debian's separate `openssl` CLI remains 1.1.1d as in the reference. |
| Startup/config | Byte-identical entrypoint (SHA256 `d17f477f0476783cb6014dd0d0fee23d8817df1e9a5e7168861940a6ca36339f`); recovered config files, include directories, socket/data paths, UID/GID 999, ownership/modes, ports, command handling and shutdown. |
| Packaging | Six local Debian packages use original release file manifests with version `5.7.32-1debian10+arm64.1`. Original package was `5.7.32-1debian10`. Database/service maintainer scripts are omitted; the container entrypoint initializes data. Separate `mysqld-debug` and debug plugin copies are omitted; all release plugins/tools are retained. Release binaries retain compiler symbols, increasing image size without changing SQL/storage behavior. |
| Toolchain | Debian GCC 8.3.0 and CMake 3.13.4. Original compiler is unknown; unavailable Oracle build infrastructure is not reproduced. |
| Runtime comparison | Exact configuration plus source/build-default evidence supports comparison. Effective settings are measured natively; the AMD64 reference defaults were not executed/measured. |
| Production | Original kernel/configuration and data are unavailable. Matching Debian userspace does not reproduce them. Real production-dump and Rails integration compatibility remain unverified. |

No AMD64 benchmark was required or performed. Durations refer only to the work actually measured; no speedup ratio is claimed. This historical version is intended for the requested isolated local exploration.
