# MySQL 5.7.32 official reference evidence

Recovered on 2026-10-07 using `gh` for GitHub operations and Docker filesystem inspection. No AMD64 process was executed. The inspection container was created but never started.

## Pinned inputs

- Official index: `mysql@sha256:e08834258fcc0efd01df358222333919df53d4a0d9b2a54da05b204b822e3b7b` (provided by prior research).
- Inspected AMD64 child: `mysql@sha256:860f4bcc18607de9f40a7453c7dc160313ecc3a5a46be3b060569b6216d348f6`.
- Historical recipe: [docker-library/mysql commit b0a0e546712534b30ac13e8b2829f23654facbc5](https://github.com/docker-library/mysql/tree/b0a0e546712534b30ac13e8b2829f23654facbc5/5.7).
- `Dockerfile.official` is the historical `5.7/Dockerfile.debian`, SHA256 `87d7041e9bdcb32e76ec8a5b6380e0dcb99c2ecc118c01ca4f9ec5f8c9a1322f`.
- `docker-entrypoint.sh`: SHA256 `d17f477f0476783cb6014dd0d0fee23d8817df1e9a5e7168861940a6ca36339f`. The copy extracted from the reference image has the same SHA256.
- Native `gosu-arm64` 1.12: downloaded with `gh release download 1.12 --repo tianon/gosu`; SHA256 `ff6f0b36315d2013d4fcc442cded0e0403d6bb29abc4cd6f94f2bde90bf97a38`. ELF reports aarch64, statically linked.
- `gosu-arm64.asc`: SHA256 `7e36f516d5dc310799348f052714887f330a54590d68010a9d65e502f478925a`. GPG verified it with RSA fingerprint `B42F6819007F00F88E364FD4036A9C25BF357DD4`, obtained from `hkps://keys.openpgp.org`; verification transcript and public key are retained. The expected fingerprint, rather than an independently established Web of Trust, supplies the identity check.

## Recovered image evidence

`image-inspect.json` preserves Docker's configuration. `installed-packages.tsv` is extracted from the image's `/var/lib/dpkg/status`. The full status and image history were retained locally during inspection and are omitted from Git; the published excerpts contain the relevant package and configuration evidence. `/etc/debian_version` is `10.7`; `/usr/lib/os-release` identifies Debian 10 buster. The reference MySQL packages are `5.7.32-1debian10`.

`etc-mysql/` contains the exact configuration files. The reference `/etc/mysql/my.cnf` points to `/etc/alternatives/my.cnf`, which points to `/etc/mysql/mysql.cnf`. That file includes both `/etc/mysql/conf.d/` and `/etc/mysql/mysql.conf.d/`. The server config sets datadir `/var/lib/mysql`, PID `/var/run/mysqld/mysqld.pid`, socket `/var/run/mysqld/mysqld.sock`, and `symbolic-links=0`. `bind-address` and `log-error` are commented by the historical image recipe; `docker.cnf` adds `skip-host-cache` and `skip-name-resolve`. No `event_scheduler` override is present.

The mysql account is UID/GID 999:999. The recipe sets data/run directories to mode 1777 and owns them as mysql. `filesystem-layout.json` confirms this statically and additionally records `/var/lib/mysql-files` as mode 0770, mysql-owned. The image exposes 3306 and 33060, declares `/var/lib/mysql` as a volume, uses `docker-entrypoint.sh`, and defaults to `mysqld`. Its client/tool filenames are also recorded in that layout file.

`static-binary-inspection.json` records the three reference ELF machines (x86-64), SHA256s and `DT_NEEDED` entries without loading them. Each of `mysqld`, `mysql` and `mysqldump` contains the string `OpenSSL 1.1.1g  21 Apr 2020`, and none has `libssl` or `libcrypto` in `DT_NEEDED`, supporting static inclusion. Debian's separately installed command-line `openssl` and `libssl1.1` are `1.1.1d-0+deb10u4`; this is not the library version embedded in those executables. Compiler `.comment` sections are absent, so this inspection does not establish the compiler version.

Runtime dependencies recorded include libaio, libnuma and libatomic for mysqld, ncurses6/tinfo6 for the mysql client, and libmecab2 for the MeCab plugin. The reference plugins include MySQL X, group replication, MeCab, InnoDB memcached, authentication LDAP SASL client, socket authentication, keyring, rewrite/connection control, semisync and password validation. Their names are retained in `static-binary-inspection.json`.

## ARM64 static OpenSSL relocation investigation

The native build exposed unsupported ARM64 relocations when linking the static OpenSSL 1.1.1g archive into `group_replication.so`: externally bindable `OPENSSL_armcap_P`, `poly1305_blocks`, and `poly1305_emit` assembly references. This is the failure described by [OpenSSL issue 10842](https://github.com/openssl/openssl/issues/10842).

`group-replication-ssl-static.json` records static inspection of the pinned AMD64 reference plugin, SHA256 `796b393d6b1d63c7f3877e48dd15c765ad8738b9dcffe08bc1ac07fab8d92671`. Its `DT_NEEDED` entries exclude libssl/libcrypto. It has no DT_SYMBOLIC or DF_SYMBOLIC flags; 1,037 dynamic symbols with the inspected OpenSSL-family prefixes are present, with sampled public SSL/EVP functions and `OPENSSL_ia32cap_P` retaining DEFAULT visibility. This evidence argues against adding a broad `-Bsymbolic` or hiding the entire static crypto archive solely to get a successful ARM64 link.

The accepted stable-branch [OpenSSL commit d741debb320bf54e8575d35603a44d4eb40fa1f9](https://github.com/openssl/openssl/commit/d741debb320bf54e8575d35603a44d4eb40fa1f9), reviewed by Tomas Mraz and Paul Dale and merged from [PR 13218](https://github.com/openssl/openssl/pull/13218), provides the focused fix. `openssl-aarch64-static-pic.d741debb.patch` was retrieved with `gh api` and the patch media type; SHA256 `c6babf75ab3899db410749bc530f392c8da24b1e6099170b540ca7e5993225f0`. The patch is recovered into `inputs/` by `fetch-inputs.sh`, rather than included in Git. A `patch --dry-run -p1` check on all four scripts extracted from the verified 1.1.1g archive succeeded without offsets or fuzz. The patch only adds hidden visibility to ARM CPU-capability and Poly1305 assembly helper symbols and removes redundant common declarations. It changes no cryptographic instructions, algorithms, MySQL source, or SQL/storage settings. The native link probe and focused validation subsequently passed; see [verification results](../VERIFICATION.md).

## Limits

The reference was inspected statically, so this evidence does not provide measured reference runtime SQL variables or an AMD64 benchmark. Compare native runtime defaults against the verified exact source and recovered configuration. Matching this Debian userspace does not reproduce the original production kernel or unavailable production configuration. Extracted AMD64 executables/plugin files were discarded after inspection; the unstarted inspection container and its anonymous volume were removed. The pulled reference image remains available for reproducible static inspection.

The gosu executable itself is omitted from Git and recovered into `inputs/` by `fetch-inputs.sh`; its public signature, signing key and verification transcript are included. Copied upstream files retain their notices, with full license texts and source locations described in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
