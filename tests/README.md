Run from this standalone image project after building the image:

```sh
IMAGE=mysql:5.7.32-arm64-local ./tests/validate.sh
./tests/compose-smoke.sh
```

`validate.sh` requires an ARM64 Docker host, uses `--platform=linux/arm64` with `--pull=never`, and checks the actual ELF machine fields for `mysqld`, `mysql`, and `mysqldump`. It never starts an AMD64 image. It uses `docker run`, so it does not resolve or start Compose services. Resolve the example Compose configuration before using those examples separately.

Each run creates uniquely named containers, Docker volumes, and a private Docker network. The exit trap removes only those resources and temporary synthetic credential files. It never mounts an existing database directory, opens production backups, or uses production records. No database files or logical dump are written to the host: the dump streams from the source container to the restore container. Ignored local artifacts are generated in `tests/results/<run-id>/` and include check durations in seconds, image identity, native binary evidence, sanitized container logs, effective settings, expected SQL errors, synthetic schema definitions, and snapshots before restart and after restore. Generated root credentials are redacted from retained logs. Selected evidence from the completed run is tracked in `verification/` and summarized in [VERIFICATION.md](../VERIFICATION.md).

Initialization hooks are copied into a disposable Linux volume to preserve their executable bits. On the tested Docker Desktop macOS bind mount, `test -x` returned true for a mode-0644 script, causing the unchanged official entrypoint to attempt execution. The volume-based test verifies both sourced and executable hooks with actual Linux permissions; the [mount observation](../verification/bind-mount-mode-probe.txt) is tracked with the published evidence.

`compose-smoke.sh` separately resolves and inspects the example configuration before startup, creates its own project/volume and localhost port, and executes the README's application-user import. It checks protected system users, runtime event disabling and graceful shutdown, then removes its Compose resources. Resolved passwords remain only in removed temporary scratch files.

The synthetic fixture reflects the types present in the read-only Teezily `db/schema.rb`: integer keys, UTF-8 strings and medium text, decimals `(15,2)` and `(28,25)`, binary values, booleans, dates, datetimes, floating point values, NULLs, BTREE unique/composite indexes, and foreign keys. It adds a timestamp, view, update trigger, stored procedure, and future event to exercise logical dump preservation. These extra objects do not establish that the application uses them. The schema declares foreign keys but no views, routines, or events; a migration mentions LHM trigger handling.

The suite verifies:

- Exact 5.7.32 server and client versions, ARM64 execution and command passthrough.
- Fresh initialization with `MYSQL_ROOT_HOST`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_ROOT_PASSWORD_FILE`, and `MYSQL_PASSWORD_FILE`; root and application-user authentication over network TCP.
- Plain and compressed SQL plus sourced and executable shell init hooks; both configuration include directories and a leading-option server command.
- Named timezone initialization and seasonal offsets; timestamp timezone conversion while datetime wall time stays unchanged.
- Known synthetic values, view/procedure/trigger execution, unique and foreign-key enforcement, and strict-mode rejection of decimal overflow and zero datetime values.
- SIGTERM shutdown with exit status zero, persisted restart, original credentials, and init-hook/environment-variable skipping on existing data.
- An application-database-only `mysqldump` stream including routines/triggers/events; an independent restore with unchanged local user accounts, exact synthetic snapshots, and executable restored triggers and views.
- The reusable server's default event scheduler is `OFF`; the restore server accepts runtime `--event-scheduler=DISABLED`. Its scheduled fixture starts in 2030, within [MySQL 5.7's supported event time range](https://dev.mysql.com/doc/mysql-reslimits-excerpt/5.7/en/stored-program-restrictions.html).
- Explicit empty-password initialization, `MYSQL_INITDB_SKIP_TZINFO`, working generated root credentials, and rejection of conflicting direct/file credentials.

`default-settings.tsv` records defaults without validation configuration overrides. `configured-settings.tsv` adds three deliberate test settings. `restore-settings.tsv` records the isolated restore settings. These report SQL modes, server character set/collation, timezone, and relevant InnoDB variables. Their equivalence to the pinned reference must be assessed against separately recovered reference evidence; ARM64 native tests alone cannot establish production configuration equivalence.

A passing run demonstrates synthetic logical backup/restore on this image. Real production dumps, physical backup conversion, the unavailable production kernel/configuration, and Rails integration remain unverified.
