# Third-party notices

This repository contains upstream reference files and provenance for a recovered dependency patch. Their licenses remain applicable to those materials and any code derived from them. This notice does not select a blanket license for newly authored project files.

| Material | Upstream source and terms | Retained notice |
| --- | --- | --- |
| Historical MySQL Docker entrypoint and recipe; configuration created by that recipe | [docker-library/mysql at b0a0e546712534b30ac13e8b2829f23654facbc5](https://github.com/docker-library/mysql/tree/b0a0e546712534b30ac13e8b2829f23654facbc5), GNU GPL version 2 | [GPLv2](reference/licenses/docker-library-mysql.GPL-2.0.txt) |
| Oracle MySQL server configuration and original packaging used by the build | Oracle MySQL 5.7.32, copyright Oracle and/or its affiliates; GNU GPL version 2 with the additional permissions stated by Oracle | [Complete MySQL licensing information](reference/licenses/MySQL-5.7.32.LICENSE), [Oracle Debian packaging notice](reference/licenses/MySQL-5.7.32.Debian-copyright) |
| Configuration recovered from Debian's `mysql-common` package, including `my.cnf.fallback` and client configuration | Debian `mysql-defaults` 1.0.5 / `mysql-common` 5.8+1.0.5; GNU GPL version 2 or later; individual contributor copyrights are retained in the package notice | [Debian attribution and terms](reference/licenses/MySQL-common.Debian-copyright), [GPLv2](reference/licenses/docker-library-mysql.GPL-2.0.txt) |
| ARM64 static-linking patch for OpenSSL | [OpenSSL commit d741debb320bf54e8575d35603a44d4eb40fa1f9](https://github.com/openssl/openssl/commit/d741debb320bf54e8575d35603a44d4eb40fa1f9), by Romain Geissler; applied to OpenSSL 1.1.1g under its original OpenSSL and SSLeay licenses | [OpenSSL 1.1.1g license texts](reference/licenses/OpenSSL-1.1.1g.LICENSE) |
| gosu binary fetched for the image build | [gosu 1.12](https://github.com/tianon/gosu/tree/1.12), GNU GPL version 3 | [GPLv3](reference/licenses/gosu-1.12.GPL-3.0.txt) |
| Go runtime included in the fetched gosu binary | [Go 1.13.10](https://github.com/golang/go/tree/go1.13.10), Go Authors, BSD-style license | [Go license](reference/licenses/Go-1.13.10.LICENSE) |
| libcontainer code used by gosu | [runc v1.0.0-rc10](https://github.com/opencontainers/runc/tree/v1.0.0-rc10), Apache License 2.0 | [Apache License 2.0](reference/licenses/runc-v1.0.0-rc10.Apache-2.0.txt), [runc NOTICE](reference/licenses/runc-v1.0.0-rc10.NOTICE) |

The copied entrypoint, configuration files and historical Dockerfile retain their original contents and any embedded copyright notices. The local image recipe adapts the historical setup for a native ARM64 source build. The OpenSSL patch is recovered verbatim by `fetch-inputs.sh`; its application is documented in the build recipe and provenance. It changes ARM assembly symbol visibility for static linking, with no changes to cryptographic instructions or MySQL source. The source archives, dependency archives and downloaded executable are recovered separately by `fetch-inputs.sh`; they are not repository source files.

The complete MySQL license file includes Oracle's additional permission for separately licensed dependencies, its client-library exception, and component notices. Those permissions do not replace the separately applicable OpenSSL terms or the terms of other dependencies.

Required OpenSSL acknowledgments:

> This product includes software developed by the OpenSSL Project for use in the OpenSSL Toolkit. (http://www.openssl.org/)
>
> This product includes cryptographic software written by Eric Young (eay@cryptsoft.com).
>
> This product includes software written by Tim Hudson (tjh@cryptsoft.com).

Keep the upstream copyrights, license texts, attribution, disclaimers and notices with copies of the covered materials. For redistribution of a built container image, also preserve the notices for the included binaries and Debian packages and meet the applicable corresponding-source requirements of their licenses. GPL-covered binaries require complete corresponding source and the relevant build/install material through an allowed license mechanism; a statement that a binary is open source is insufficient. The original source locations, pinned input hashes, applied patch and build scripts in this project provide provenance and build material. They do not constitute a separately prepared binary-distribution source bundle.

License recovery provenance:

- Docker-library MySQL license: exact historical commit listed above, fetched through `gh api`.
- MySQL license and Oracle packaging notice: copied from the verified Oracle 5.7.32 source and Debian packaging archives.
- Debian mysql-common notice: extracted without executing any AMD64 process from the pinned reference image `mysql@sha256:860f4bcc18607de9f40a7453c7dc160313ecc3a5a46be3b060569b6216d348f6`.
- OpenSSL, gosu, Go and runc licenses/notices: fetched through `gh api` at the versions listed above. The gosu binary embeds `go1.13.10`; its upstream 1.12 build recipe pins runc `v1.0.0-rc10`.
