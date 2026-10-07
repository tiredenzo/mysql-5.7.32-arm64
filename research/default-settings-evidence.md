# MySQL 5.7.32 default-setting evidence

This maps every variable in `tests/settings.sql` to the verified Oracle source (`mysql-community_5.7.32.orig.tar.gz`, SHA256 `1f4b59b43f82de4ccf4ba9cfce087318a192012a752aee8f66ca16f73bb082c9`), recovered Debian build recipe, and statically extracted reference configuration. Source paths below are relative to the extracted `mysql-5.7.32/` tree.

The values are expected native defaults, **not measured values from the AMD64 reference**. That image was never executed. Matching exact source defaults and the recovered configuration supports an inferred reference comparison; native observations must come from the validation result files. No unavailable production configuration is inferred.

`sql_mode` is expected to contain exactly:

```text
ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION
```

| Variable | Expected unmodified native value | Source/build evidence |
| --- | --- | --- |
| `version` | `5.7.32` | `VERSION:1` fixes major/minor/patch to 5/7/32 and has an empty extra suffix; `sql/sys_vars.cc:4353` exposes the server version. |
| `version_comment` | `MySQL Community Server (GPL)` | Both recovered `debian/rules` and `build/compile.sh` explicitly set `COMPILATION_COMMENT`; exposed by `sql/sys_vars.cc:4359`. |
| `version_compile_machine` | `aarch64` | `CMakeLists.txt:183` uses `CMAKE_SYSTEM_PROCESSOR`; `config.h.cmake:223` defines `MACHINE_TYPE`. This intentionally differs from the reference's x86-64 architecture. |
| `version_compile_os` | `Linux` | `configure.cmake:64` defaults `SYSTEM_TYPE` to `CMAKE_SYSTEM_NAME` unless `PLATFORM` is set; the recovered and native recipes do not set it. `sql/sys_vars.cc:4371` exposes it. |
| `sql_mode` | Explicit list above | `sql/sys_vars.cc:3900` supplies exactly those seven default bits; `sql_mode_names` at line 3876 supplies their displayed names/order. |
| `character_set_server` | `latin1` | `cmake/character_sets.cmake:24` sets the unspecified default charset to `latin1`; neither recipe overrides it. `sql/mysqld.cc:3025` sets the server charset/collation from the compiled default. |
| `collation_server` | `latin1_swedish_ci` | `cmake/character_sets.cmake:28` sets the unspecified default collation; neither recipe overrides it. |
| `default_storage_engine` | `InnoDB` | `sql/mysqld.cc:2783` assigns InnoDB for the standalone server. The embedded-server branch uses MyISAM and does not apply to `mysqld`. |
| `time_zone` | `SYSTEM` | `sql/mysqld.cc:2704` initializes SYSTEM; `sql/tztime.cc:1815` keeps it absent `--default-time-zone`. |
| `system_time_zone` | Expected `UTC`; environment-dependent | `sql/mysqld.cc:2672` calls `tzset()`, then line 2699 takes the current OS timezone abbreviation. The pinned Debian base is left at its container timezone; reference/native image environment contains no `TZ` override and the validation does not mount host timezone files. UTC is an environmental expectation, **not a MySQL compiled default**; saved reference evidence does not independently establish `/etc/localtime` or a measured AMD64 value. The user's Europe/Paris host timezone does not set this container variable. |
| `event_scheduler` | `OFF` | `sql/sys_vars.cc:1629` declares `DEFAULT(Events::EVENTS_OFF)`; `sql/events.cc:89` agrees. No recovered configuration overrides it. Restore validation deliberately passes `--event-scheduler=DISABLED`. |
| `lower_case_table_names` | `0` on the Linux Docker volume | `sql/sys_vars.cc:2219` defaults to 0 unless `FN_NO_CASE_SENSE` is defined. `sql/mysqld.cc:3153` can adjust it for an actually case-insensitive data filesystem. This expectation relies on the Docker-managed Linux volume, not a macOS database-directory bind mount. |
| `explicit_defaults_for_timestamp` | `OFF` | `sql/sys_vars.cc:1075` declares `DEFAULT(FALSE)`. |
| `innodb_version` | `5.7.32` | `storage/innobase/include/univ.i:53` takes the MySQL version components; line 66 builds the string; `ha_innodb.cc:20080` exposes it. |
| `innodb_page_size` | `16384` bytes (16 KiB) | `storage/innobase/include/univ.i:340` defines the default shift as 14; `ha_innodb.cc:19930` uses `UNIV_PAGE_SIZE_DEF`. |
| `innodb_buffer_pool_size` | `134217728` bytes (128 MiB) | `storage/innobase/srv/srv0srv.cc:258` declares `srv_buf_pool_def_size`; `ha_innodb.cc:19730` uses it. |
| `innodb_file_format` | `Barracuda` | `ha_innodb.cc:179` declares `innodb_file_format_default`; `MYSQL_SYSVAR_STR(file_format)` at line 19497 uses it. |
| `innodb_large_prefix` | `ON` | `ha_innodb.cc:19547` registers the variable with default `TRUE`. Its backing C++ initializer at line 200 is `FALSE`, but that is not the registered/effective default. |
| `innodb_file_per_table` | `ON` | `ha_innodb.cc:19492` registers default `TRUE`. |
| `innodb_strict_mode` | `ON` | `ha_innodb.cc:786` registers the session/global default `TRUE`. |
| `innodb_flush_log_at_trx_commit` | `1` | `ha_innodb.cc:19536` registers default 1. |
| `innodb_log_file_size` | `50331648` bytes (48 MiB) | `ha_innodb.cc:19941` registers `48*1024*1024L`. |
| `innodb_log_files_in_group` | `2` | `ha_innodb.cc:19946` registers default 2. |
| `innodb_doublewrite` | `ON` | `ha_innodb.cc:19396` registers default `TRUE`. |
| `max_allowed_packet` | `4194304` bytes (4 MiB), server | `sql/sys_vars.cc:2261` declares `4096*1024`. The reference's `[mysqldump] max_allowed_packet=16M` is a client setting and does not change the server default. |
| `max_connections` | `151` | `sql/sys_vars.cc:2330` uses `MAX_CONNECTIONS_DEFAULT`; `sql/sql_const.h:132` defines 151. Startup may reduce the effective limit if OS file-descriptor limits require it. |
| `group_concat_max_len` | `1024` bytes | `sql/sys_vars.cc:4853` declares default 1024. |

All `ha_innodb.cc` references are under `storage/innobase/handler/`. The requested source defaults agree with the table; no contradictory effective source default was found. UTC remains conditional on the container environment, and ARM64 compile-machine metadata intentionally differs.

The copied reference `etc-mysql/mysql.cnf` includes both configuration directories. Its server file sets data/PID/socket paths and `symbolic-links=0`; `conf.d/docker.cnf` sets `skip-host-cache` and `skip-name-resolve`. None overrides the SQL/InnoDB defaults above. Test `configured-settings.tsv` deliberately changes `max_connections` to 71, server `max_allowed_packet` to 67108864, and `group_concat_max_len` to 10240; use `default-settings.tsv` for the default comparison. `restore-settings.tsv` deliberately has `event_scheduler=DISABLED`.

The original entrypoint normally imports timezone tables; `MYSQL_INITDB_SKIP_TZINFO=1` suppresses that import. This affects named-zone lookup availability, not the initial SYSTEM timezone. Fixture sessions explicitly set `+00:00`; validation checks that TIMESTAMP converts with session timezone while DATETIME retains its stored wall-clock value. These checks do not establish the timezone or other configuration of the unavailable production server.
