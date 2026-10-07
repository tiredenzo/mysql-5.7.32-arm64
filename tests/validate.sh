#!/usr/bin/env bash
# Fresh disposable Docker storage only. No production paths or data are used.
set -Eeuo pipefail

IMAGE=${IMAGE:-mysql:5.7.32-arm64-local}
TEST_DIR=$(cd "$(dirname "$0")" && pwd)
RUN_ID="mysql5732-test-$(date -u +%Y%m%dT%H%M%SZ)-$$"
RESULTS="$TEST_DIR/results/$RUN_ID"
SCRATCH="$RESULTS/.scratch"
NETWORK="$RUN_ID"
MAIN="$RUN_ID-main"
RESTORE="$RUN_ID-restore"
EMPTY="$RUN_ID-empty"
RANDOM_SERVER="$RUN_ID-random"
INVALID="$RUN_ID-invalid"
CONTAINERS=("$MAIN" "$RESTORE" "$EMPTY" "$RANDOM_SERVER" "$INVALID")
VOLUMES=("$RUN_ID-main-data" "$RUN_ID-restore-data" "$RUN_ID-empty-data" "$RUN_ID-random-data" "$RUN_ID-invalid-data" "$RUN_ID-init")
START_SECONDS=$SECONDS
STAGE_START=$SECONDS
mkdir -p "$SCRATCH/init" "$SCRATCH/config" "$SCRATCH/secrets"
chmod 700 "$SCRATCH" "$SCRATCH/secrets"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() {
  printf '%s\tPASS\t%s\n' "$((SECONDS - STAGE_START))" "$*" | tee -a "$RESULTS/checks.tsv"
  STAGE_START=$SECONDS
}
assert_equal() { [[ "$1" == "$2" ]] || fail "$3 (expected '$2', received '$1')"; }
logs() {
  docker logs "$1" 2>&1 | sed -E 's/(GENERATED ROOT PASSWORD:).*/\1 [REDACTED]/' > "$2" || true
}
cleanup() {
  local status=$1 container volume
  set +e
  for container in "${CONTAINERS[@]}"; do
    if docker container inspect "$container" >/dev/null 2>&1; then
      logs "$container" "$RESULTS/${container##$RUN_ID-}.log"
      docker rm -f "$container" >/dev/null 2>&1
    fi
  done
  for volume in "${VOLUMES[@]}"; do docker volume rm "$volume" >/dev/null 2>&1; done
  docker network rm "$NETWORK" >/dev/null 2>&1
  rm -rf "$SCRATCH"
  printf 'exit_status\t%s\ntotal_seconds\t%s\nimage\t%s\n' "$status" "$((SECONDS - START_SECONDS))" "$IMAGE" > "$RESULTS/run.tsv"
  printf 'Validation artifacts: %s\n' "$RESULTS"
}
trap 'cleanup "$?"' EXIT

query() {
  local container=$1 password=$2
  shift 2
  docker exec -i --env MYSQL_PWD="$password" "$container" mysql \
    --protocol=TCP --host=127.0.0.1 --user=root --default-character-set=utf8mb4 \
    --batch --skip-column-names "$@"
}
wait_ready() {
  local container=$1 password=$2 elapsed=0
  while (( elapsed < 240 )); do
    if query "$container" "$password" --execute='SELECT 1' >/dev/null 2>&1; then return; fi
    if [[ "$(docker inspect --format '{{.State.Running}}' "$container")" != true ]]; then
      fail "$container exited before authenticated readiness"
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  fail "$container did not become ready in 240 seconds"
}
expect_sql_error() {
  local container=$1 password=$2 code=$3 sql=$4
  if query "$container" "$password" --database=validation --execute="$sql" > "$SCRATCH/error.out" 2>&1; then
    fail "SQL expected to fail with MySQL error $code succeeded"
  fi
  grep -q "ERROR $code " "$SCRATCH/error.out" || fail "SQL did not fail with expected MySQL error $code"
  cat "$SCRATCH/error.out" >> "$RESULTS/expected-sql-errors.txt"
}

command -v docker >/dev/null || fail 'Docker CLI is required'
docker image inspect "$IMAGE" > "$SCRATCH/image.json" || fail "Build $IMAGE before running validation"
assert_equal "$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$IMAGE")" linux/arm64 'image platform'
case "$(docker info --format '{{.Architecture}}')" in aarch64|arm64) ;; *) fail 'Docker must run on an ARM64 host for native execution validation' ;; esac
docker image inspect --format '{{.Id}}' "$IMAGE" > "$RESULTS/image-id.txt"
docker run --rm --pull=never --platform=linux/arm64 --entrypoint sh "$IMAGE" -ec '
  test "$(uname -m)" = aarch64
  printf "kernel_arch\t%s\n" "$(uname -m)"
  printf "debian_version\t%s\n" "$(cat /etc/debian_version)"
  for program in mysqld mysql mysqldump; do
    path=$(command -v "$program")
    magic=$(od -An -tx1 -N4 "$path" | tr -d "[:space:]")
    machine=$(od -An -tu2 -j18 -N2 "$path" | tr -d "[:space:]")
    test "$magic" = 7f454c46
    test "$machine" = 183
    printf "%s\t%s\tELF_EM_AARCH64=%s\n" "$program" "$path" "$machine"
    "$program" --version
    ldd "$path"
  done
' > "$RESULTS/native-binaries.txt"
docker run --rm --pull=never --platform=linux/arm64 --entrypoint sh "$IMAGE" -ec '
  count=0
  for plugin in /usr/lib/mysql/plugin/*.so; do
    machine=$(od -An -tu2 -j18 -N2 "$plugin" | tr -d "[:space:]")
    test "$machine" = 183
    dependencies=$(ldd "$plugin")
    printf "%s\tELF_EM_AARCH64=%s\n%s\n" "$plugin" "$machine" "$dependencies"
    if printf "%s\n" "$dependencies" | grep -q "not found"; then exit 1; fi
    count=$((count+1))
  done
  test "$count" = 19
' > "$RESULTS/native-plugins.txt"
for program in mysqld mysql mysqldump; do
  version=$(docker run --rm --pull=never --platform=linux/arm64 "$IMAGE" "$program" --version)
  printf '%s\n' "$version" >> "$RESULTS/versions.txt"
  [[ "$version" =~ 5\.7\.32([^0-9.]|$) ]] || fail "$program must be exactly version 5.7.32"
  [[ "$version" != *MariaDB* ]] || fail "$program must be Oracle MySQL"
done
assert_equal "$(docker run --rm --pull=never --platform=linux/arm64 "$IMAGE" sh -c 'printf command-passthrough')" command-passthrough 'entrypoint command passthrough'
pass 'ARM64 Docker host, image and ELF binaries; exact mysqld/mysql/mysqldump 5.7.32; command passthrough'

# Synthetic credentials are temporary and never written to retained artifacts.
ROOT_PASSWORD="root-$RUN_ID"
APP_PASSWORD="app-$RUN_ID"
RESTORE_PASSWORD="restore-$RUN_ID"
printf '%s' "$ROOT_PASSWORD" > "$SCRATCH/secrets/root-password"
printf '%s' "$APP_PASSWORD" > "$SCRATCH/secrets/app-password"
chmod 600 "$SCRATCH/secrets/"*
cp "$TEST_DIR/fixture.sql" "$SCRATCH/init/01-fixture.sql"
printf "INSERT INTO init_markers VALUES ('gzip', 1);\n" | gzip > "$SCRATCH/init/02-gzip.sql.gz"
cat > "$SCRATCH/init/03-sourced.sh" <<'SOURCED'
export VALIDATION_SOURCE_VALUE='sourced-shell'
docker_process_sql --database="$MYSQL_DATABASE" <<'SQL'
INSERT INTO init_markers VALUES ('sourced-shell', 1);
SQL
SOURCED
cat > "$SCRATCH/init/04-executable.sh" <<'EXECUTABLE'
#!/bin/sh
set -eu
test "$VALIDATION_SOURCE_VALUE" = sourced-shell
MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql --protocol=socket --user=root "$MYSQL_DATABASE" \
  --execute="INSERT INTO init_markers VALUES ('exec-sees-sourced-shell', 1)"
EXECUTABLE
chmod 644 "$SCRATCH/init/03-sourced.sh"
chmod 755 "$SCRATCH/init/04-executable.sh"
printf '[mysqld]\nmax_allowed_packet=67108864\n' > "$SCRATCH/config/conf-d.cnf"
printf '[mysqld]\ngroup_concat_max_len=10240\n' > "$SCRATCH/config/mysql-conf-d.cnf"
for volume in "${VOLUMES[@]}"; do docker volume create --label mysql5732.validation="$RUN_ID" "$volume" >/dev/null; done
docker network create --label mysql5732.validation="$RUN_ID" "$NETWORK" >/dev/null
# Docker Desktop's shared macOS mount reports test -x true even for mode 0644.
# Copy hooks into Linux volume storage so sourced/executable checks use real modes.
COPYFILE_DISABLE=1 tar -C "$SCRATCH/init" -cf - . | \
  docker run --rm -i --pull=never --platform=linux/arm64 --entrypoint sh \
    --mount "type=volume,source=${VOLUMES[5]},target=/fixtures" "$IMAGE" -ec \
    'tar --no-same-owner -xf - -C /fixtures; chmod 755 /fixtures; test ! -x /fixtures/03-sourced.sh; test -x /fixtures/04-executable.sh'

# Docker run is used; no Compose containers are started by this suite.
run_main() {
  local initialize=$1
  local env_args=()
  if [[ "$initialize" == yes ]]; then
    env_args=(--env MYSQL_ROOT_PASSWORD_FILE=/run/secrets/root-password --env MYSQL_ROOT_HOST=%
      --env MYSQL_DATABASE=validation --env MYSQL_USER=fixture_user --env MYSQL_PASSWORD_FILE=/run/secrets/app-password)
  else
    env_args=(--env MYSQL_ROOT_PASSWORD=ignored-on-existing-datadir
      --env MYSQL_DATABASE=should_not_exist --env MYSQL_USER=should_not_exist --env MYSQL_PASSWORD=ignored-on-existing-datadir)
  fi
  docker run -d --pull=never --platform=linux/arm64 --name "$MAIN" --network "$NETWORK" \
    --mount "type=volume,source=${VOLUMES[0]},target=/var/lib/mysql" \
    --mount "type=bind,source=$SCRATCH/secrets,target=/run/secrets,readonly" \
    --mount "type=volume,source=${VOLUMES[5]},target=/docker-entrypoint-initdb.d,readonly" \
    --mount "type=bind,source=$SCRATCH/config/conf-d.cnf,target=/etc/mysql/conf.d/99-validation.cnf,readonly" \
    --mount "type=bind,source=$SCRATCH/config/mysql-conf-d.cnf,target=/etc/mysql/mysql.conf.d/99-validation.cnf,readonly" \
    "${env_args[@]}" "$IMAGE" --max-connections=71 >/dev/null
}
run_main yes
wait_ready "$MAIN" "$ROOT_PASSWORD"
assert_equal "$(query "$MAIN" "$ROOT_PASSWORD" --execute="SELECT COUNT(*) FROM mysql.user WHERE User='root' AND Host='%'")" 1 'MYSQL_ROOT_HOST'
assert_equal "$(query "$MAIN" "$ROOT_PASSWORD" --execute='SELECT @@max_connections, @@max_allowed_packet, @@group_concat_max_len')" $'71\t67108864\t10240' 'leading-option command and both config include directories'
assert_equal "$(query "$MAIN" "$ROOT_PASSWORD" --database=validation --execute='SELECT COUNT(*), SUM(executions) FROM init_markers')" $'4\t4' 'SQL, gzip SQL, sourced and executable shell init scripts'
assert_equal "$(docker run --rm --pull=never --platform=linux/arm64 --network "$NETWORK" --env MYSQL_PWD="$ROOT_PASSWORD" "$IMAGE" mysql --protocol=TCP --host="$MAIN" --user=root --batch --skip-column-names --execute='SELECT 1')" 1 'root authentication over network TCP'
if query "$MAIN" deliberately-incorrect-password --execute='SELECT 1' > "$SCRATCH/root-denied.txt" 2>&1; then
  fail 'root authentication accepted an incorrect password'
fi
assert_equal "$(docker run --rm --pull=never --platform=linux/arm64 --network "$NETWORK" --env MYSQL_PWD="$APP_PASSWORD" "$IMAGE" mysql --protocol=TCP --host="$MAIN" --user=fixture_user --database=validation --batch --skip-column-names --execute='SELECT COUNT(*) FROM orders')" 2 'MYSQL_DATABASE/USER/PASSWORD_FILE and application-user TCP authentication'
if docker exec --env MYSQL_PWD="$APP_PASSWORD" "$MAIN" mysql --protocol=TCP --host=127.0.0.1 --user=fixture_user --execute='SELECT * FROM mysql.user' > "$SCRATCH/app-denied.txt" 2>&1; then
  fail 'initialization user unexpectedly has access to system users'
fi
assert_equal "$(query "$MAIN" "$ROOT_PASSWORD" --execute="SELECT CONVERT_TZ('2024-07-01 12:00:00','UTC','Europe/Paris'), CONVERT_TZ('2024-01-01 12:00:00','UTC','Europe/Paris')")" $'2024-07-01 14:00:00\t2024-01-01 13:00:00' 'initialized named timezone tables and seasonal offsets'
assert_equal "$(query "$MAIN" "$ROOT_PASSWORD" --execute='SELECT @@event_scheduler')" OFF 'reusable image event scheduler default'
query "$MAIN" "$ROOT_PASSWORD" < "$TEST_DIR/settings.sql" > "$RESULTS/configured-settings.tsv"
pass 'fresh initialization, file-based credentials, root/application TCP authentication, init hooks, timezone tables and config includes'

assert_equal "$(query "$MAIN" "$ROOT_PASSWORD" --database=validation --execute="SELECT COUNT(*) FROM orders WHERE id=1 AND amount=1234.57 AND exchange_rate=0.1234567890123456789012345 AND HEX(payload)='0001FF7F' AND enabled=1 AND observed_at='2024-01-15 12:34:56'")" 1 'exact decimal/binary/boolean/timestamp data'
assert_equal "$(query "$MAIN" "$ROOT_PASSWORD" --database=validation --execute="SELECT COUNT(*) FROM orders WHERE id=2 AND amount=-0.01 AND exchange_rate IS NULL AND note IS NULL AND payload IS NULL AND ordered_on IS NULL AND observed_at IS NULL")" 1 'negative decimal and NULL values'
assert_equal "$(query "$MAIN" "$ROOT_PASSWORD" --database=validation --execute="SELECT label FROM customers WHERE id=1")" 'Élodie 東京 🌍' 'UTF-8 text including supplementary characters'
assert_equal "$(query "$MAIN" "$ROOT_PASSWORD" --database=validation --execute="SET time_zone='+02:00'; SELECT observed_at, created_at FROM orders WHERE id=1")" $'2024-01-15 14:34:56\t2024-01-15 12:34:56' 'TIMESTAMP conversion vs DATETIME wall time'
assert_equal "$(query "$MAIN" "$ROOT_PASSWORD" --database=validation --execute='CALL synthetic_count(@total); SELECT @total; SELECT COUNT(*) FROM order_summary; SELECT COUNT(*) FROM audit')" $'2\n2\n1' 'view, procedure and trigger execution'
expect_sql_error "$MAIN" "$ROOT_PASSWORD" 1062 "INSERT INTO customers(label,email) VALUES('Duplicate','synthetic@example.invalid')"
expect_sql_error "$MAIN" "$ROOT_PASSWORD" 1452 "INSERT INTO orders(customer_id,reference,amount,created_at) VALUES(999,'FK-FAIL',1,'2024-01-01')"
expect_sql_error "$MAIN" "$ROOT_PASSWORD" 1264 "INSERT INTO orders(customer_id,reference,amount,created_at) VALUES(1,'RANGE-FAIL',999999999999999.99,'2024-01-01')"
expect_sql_error "$MAIN" "$ROOT_PASSWORD" 1292 "INSERT INTO orders(customer_id,reference,amount,created_at) VALUES(1,'DATE-FAIL',1,'0000-00-00 00:00:00')"
query "$MAIN" "$ROOT_PASSWORD" --database=validation < "$TEST_DIR/snapshot.sql" > "$RESULTS/before-restart.tsv"
query "$MAIN" "$ROOT_PASSWORD" --database=validation --execute='SHOW CREATE TABLE orders; SHOW CREATE VIEW order_summary' > "$RESULTS/synthetic-definition.tsv"
pass 'representative SQL data, UTF-8, temporal semantics, views/routines/triggers, unique/FK constraints and strict-mode failures'

# Graceful SIGTERM, recreate container with the same managed volume, changed init env.
docker stop --time 60 "$MAIN" >/dev/null
assert_equal "$(docker inspect --format '{{.State.ExitCode}}/{{.State.OOMKilled}}' "$MAIN")" 0/false 'graceful server shutdown'
logs "$MAIN" "$RESULTS/main-first-start.log"
docker rm "$MAIN" >/dev/null
run_main no
wait_ready "$MAIN" "$ROOT_PASSWORD"
query "$MAIN" "$ROOT_PASSWORD" --database=validation < "$TEST_DIR/snapshot.sql" > "$RESULTS/after-restart.tsv"
cmp "$RESULTS/before-restart.tsv" "$RESULTS/after-restart.tsv" || fail 'data or objects changed across persisted restart'
assert_equal "$(query "$MAIN" "$ROOT_PASSWORD" --execute="SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='should_not_exist'; SELECT COUNT(*) FROM mysql.user WHERE User='should_not_exist'")" $'0\n0' 'initialization variables ignored for an existing database'
pass 'graceful shutdown and volume persistence; restart skips init scripts and does not change users/passwords'

# The isolated restore target disables scheduled events only at runtime.
docker run -d --pull=never --platform=linux/arm64 --name "$RESTORE" --network "$NETWORK" \
  --mount "type=volume,source=${VOLUMES[1]},target=/var/lib/mysql" \
  --env MYSQL_ROOT_PASSWORD="$RESTORE_PASSWORD" --env MYSQL_DATABASE=validation \
  --env MYSQL_INITDB_SKIP_TZINFO=1 "$IMAGE" --event-scheduler=DISABLED >/dev/null
wait_ready "$RESTORE" "$RESTORE_PASSWORD"
query "$RESTORE" "$RESTORE_PASSWORD" --execute="CREATE USER 'local_only'@'%' IDENTIFIED BY 'synthetic-local-user';" >/dev/null
docker exec --env MYSQL_PWD="$ROOT_PASSWORD" "$MAIN" mysqldump --user=root \
  --single-transaction --routines --triggers --events --hex-blob --default-character-set=utf8mb4 \
  --set-gtid-purged=OFF --no-tablespaces validation | \
  query "$RESTORE" "$RESTORE_PASSWORD" --database=validation
query "$RESTORE" "$RESTORE_PASSWORD" --database=validation < "$TEST_DIR/snapshot.sql" > "$RESULTS/after-restore.tsv"
cmp "$RESULTS/before-restart.tsv" "$RESULTS/after-restore.tsv" || fail 'logical dump/restore changed data or schema objects'
assert_equal "$(query "$RESTORE" "$RESTORE_PASSWORD" --execute="SELECT @@event_scheduler; SELECT COUNT(*) FROM mysql.user WHERE User='local_only'")" $'DISABLED\n1' 'runtime event isolation and preservation of local users/system tables'
query "$RESTORE" "$RESTORE_PASSWORD" --database=validation --execute="UPDATE orders SET amount=1.23 WHERE id=2" >/dev/null
assert_equal "$(query "$RESTORE" "$RESTORE_PASSWORD" --database=validation --execute='SELECT new_amount FROM audit WHERE order_id=2; SELECT amount FROM order_summary WHERE id=2')" $'1.23\n1.23' 'restored trigger and view execute correctly'
expect_sql_error "$RESTORE" "$RESTORE_PASSWORD" 1062 "INSERT INTO customers(label,email) VALUES('Duplicate','synthetic@example.invalid')"
expect_sql_error "$RESTORE" "$RESTORE_PASSWORD" 1452 "INSERT INTO orders(customer_id,reference,amount,created_at) VALUES(999,'RESTORED-FK-FAIL',1,'2024-01-01')"
query "$RESTORE" "$RESTORE_PASSWORD" < "$TEST_DIR/settings.sql" > "$RESULTS/restore-settings.tsv"
docker stop --time 60 "$RESTORE" >/dev/null
assert_equal "$(docker inspect --format '{{.State.ExitCode}}' "$RESTORE")" 0 'restored server graceful shutdown'
pass 'application-database-only mysqldump/restore round trip with views/triggers/routines/events; local users preserved; events DISABLED at runtime'

# Default settings, empty-password opt-in and skipping timezone import.
docker run -d --pull=never --platform=linux/arm64 --name "$EMPTY" \
  --mount "type=volume,source=${VOLUMES[2]},target=/var/lib/mysql" \
  --env MYSQL_ALLOW_EMPTY_PASSWORD=1 --env MYSQL_DATABASE=empty_init --env MYSQL_INITDB_SKIP_TZINFO=1 "$IMAGE" >/dev/null
wait_ready "$EMPTY" ''
assert_equal "$(query "$EMPTY" '' --execute="SELECT COUNT(*) FROM mysql.time_zone_name; SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='empty_init'; SELECT @@event_scheduler")" $'0\n1\nOFF' 'empty-password opt-in, MYSQL_DATABASE and MYSQL_INITDB_SKIP_TZINFO'
query "$EMPTY" '' < "$TEST_DIR/settings.sql" > "$RESULTS/default-settings.tsv"
docker stop --time 60 "$EMPTY" >/dev/null
pass 'explicit empty-password initialization, skip timezone import and unmodified effective default settings'

# Generated credentials are used transiently and removed from retained logs.
docker run -d --pull=never --platform=linux/arm64 --name "$RANDOM_SERVER" \
  --mount "type=volume,source=${VOLUMES[3]},target=/var/lib/mysql" \
  --env MYSQL_RANDOM_ROOT_PASSWORD=1 --env MYSQL_INITDB_SKIP_TZINFO=1 "$IMAGE" >/dev/null
RANDOM_PASSWORD=''
for ((attempt=0; attempt<240; attempt++)); do
  RANDOM_PASSWORD=$(docker logs "$RANDOM_SERVER" 2>&1 | sed -n 's/^.*GENERATED ROOT PASSWORD: //p' | head -n 1 | tr -d '\r')
  [[ -z "$RANDOM_PASSWORD" ]] || break
  [[ "$(docker inspect --format '{{.State.Running}}' "$RANDOM_SERVER")" == true ]] || fail 'random-password server exited'
  sleep 1
done
[[ -n "$RANDOM_PASSWORD" ]] || fail 'MYSQL_RANDOM_ROOT_PASSWORD did not generate a credential'
wait_ready "$RANDOM_SERVER" "$RANDOM_PASSWORD"
assert_equal "$(query "$RANDOM_SERVER" "$RANDOM_PASSWORD" --execute="SELECT COUNT(*) FROM mysql.user WHERE User='root' AND Host='localhost' AND authentication_string<>''")" 1 'generated root credential'
docker stop --time 60 "$RANDOM_SERVER" >/dev/null
unset RANDOM_PASSWORD
pass 'MYSQL_RANDOM_ROOT_PASSWORD generates a working protected root account'

if docker run --pull=never --platform=linux/arm64 --name "$INVALID" \
  --mount "type=volume,source=${VOLUMES[4]},target=/var/lib/mysql" \
  --mount "type=bind,source=$SCRATCH/secrets,target=/run/secrets,readonly" \
  --env MYSQL_ROOT_PASSWORD=conflicting-synthetic-value --env MYSQL_ROOT_PASSWORD_FILE=/run/secrets/root-password \
  "$IMAGE" > "$SCRATCH/invalid.log" 2>&1; then
  fail 'conflicting direct and file credentials must be rejected'
fi
grep -q 'Both MYSQL_ROOT_PASSWORD and MYSQL_ROOT_PASSWORD_FILE are set' "$SCRATCH/invalid.log" || fail 'conflicting credential error missing'
pass 'conflicting MYSQL_ROOT_PASSWORD and MYSQL_ROOT_PASSWORD_FILE rejected'
printf 'All focused validations passed in %s seconds.\n' "$((SECONDS - START_SECONDS))"
