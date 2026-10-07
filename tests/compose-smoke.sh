#!/usr/bin/env bash
# Smoke the documented Compose application-user restoration on disposable storage.
set -Eeuo pipefail
TEST_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$TEST_DIR/.." && pwd)
PROJECT="mysql5732-compose-test-$(date -u +%Y%m%dT%H%M%SZ | tr '[:upper:]' '[:lower:]')-$$"
RESULTS="$TEST_DIR/results/$PROJECT"
SCRATCH="$RESULTS/.scratch"
COMPOSE=(docker compose --env-file /dev/null -p "$PROJECT" -f "$ROOT_DIR/compose.yaml" -f "$ROOT_DIR/compose.restore.yaml")
START_SECONDS=$SECONDS
STARTED=0
mkdir -p "$SCRATCH"
chmod 700 "$SCRATCH"
export MYSQL_ROOT_PASSWORD="root-$PROJECT" MYSQL_PASSWORD="app-$PROJECT"
export MYSQL_DATABASE=compose_validation MYSQL_USER=compose_user
# Ask the host for an unused localhost port, without assuming 3307 is available.
MYSQL_PORT=$(python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(('127.0.0.1', 0))
    print(sock.getsockname()[1])
PY
)
export MYSQL_PORT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
cleanup() {
  local status=$?
  local cleanup_status=0
  set +e
  if [[ "$STARTED" == 1 ]]; then
    "${COMPOSE[@]}" logs --no-color mysql > "$RESULTS/mysql.log" 2>&1
    "${COMPOSE[@]}" down --volumes > "$RESULTS/cleanup.log" 2>&1 || cleanup_status=$?
    if docker volume inspect "${PROJECT}_mysql-data" >/dev/null 2>&1; then cleanup_status=1; fi
    if [[ -n "${CONTAINER:-}" ]] && docker container inspect "$CONTAINER" >/dev/null 2>&1; then cleanup_status=1; fi
  fi
  if [[ "$status" == 0 && "$cleanup_status" != 0 ]]; then status=$cleanup_status; fi
  rm -rf "$SCRATCH"
  printf 'exit_status\t%s\ntotal_seconds\t%s\n' "$status" "$((SECONDS - START_SECONDS))" > "$RESULTS/run.tsv"
  printf 'Compose smoke artifacts: %s\n' "$RESULTS"
  exit "$status"
}
trap cleanup EXIT

docker image inspect mysql:5.7.32-arm64-local >/dev/null || fail 'Build the local ARM64 image before running this smoke test'
# Inspect the fully resolved configuration before any container startup. Keep
# synthetic resolved passwords only in the temporary, removed scratch directory.
"${COMPOSE[@]}" config --quiet
"${COMPOSE[@]}" config --format json > "$SCRATCH/compose.json"
python3 - "$SCRATCH/compose.json" "$PROJECT" "$MYSQL_PORT" > "$RESULTS/resolved-configuration.json" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    config = json.load(stream)
service = config['services']['mysql']
assert service['image'] == 'mysql:5.7.32-arm64-local'
assert service['platform'] == 'linux/arm64'
assert service['command'] == ['mysqld', '--event-scheduler=DISABLED']
assert len(service['ports']) == 1
port = service['ports'][0]
assert port['host_ip'] == '127.0.0.1' and str(port['published']) == sys.argv[3] and port['target'] == 3306
assert len(service['volumes']) == 1
volume = service['volumes'][0]
assert volume['type'] == 'volume' and volume['source'] == 'mysql-data' and volume['target'] == '/var/lib/mysql'
assert config['volumes']['mysql-data']['name'] == sys.argv[2] + '_mysql-data'
print(json.dumps({k: service[k] for k in ('image', 'platform', 'command', 'ports', 'volumes', 'stop_grace_period')}, indent=2))
PY
STARTED=1
"${COMPOSE[@]}" up -d --wait --pull never
CONTAINER=$("${COMPOSE[@]}" ps --quiet mysql)
docker inspect --format '{{json .NetworkSettings.Ports}}' "$CONTAINER" > "$SCRATCH/ports.json"
python3 - "$SCRATCH/ports.json" "$MYSQL_PORT" <<'PY'
import json, sys
with open(sys.argv[1]) as stream:
    ports = json.load(stream)
assert ports['3306/tcp'] == [{'HostIp': '127.0.0.1', 'HostPort': sys.argv[2]}], ports
PY
root_query() {
  "${COMPOSE[@]}" exec -T mysql sh -c \
    'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysql --user=root --default-character-set=utf8mb4 --batch --skip-column-names --execute="$1"' _ "$1"
}
app_import() {
  # Exactly the README application-user import command; only project selection differs.
  "${COMPOSE[@]}" exec -T mysql sh -c \
    'MYSQL_PWD="$MYSQL_PASSWORD" exec mysql --user="$MYSQL_USER" --binary-mode=1 --default-character-set=utf8mb4 "$MYSQL_DATABASE"'
}
root_query "CREATE USER 'local_only'@'%' IDENTIFIED BY 'synthetic-local-only';" >/dev/null
app_import <<'SQL'
CREATE TABLE compose_fixture (
  id INT PRIMARY KEY,
  label VARCHAR(255) NOT NULL,
  amount DECIMAL(15,2) NOT NULL,
  optional_text TEXT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO compose_fixture VALUES (1, 'café 東京 🌍', 12.34, NULL), (2, 'Synthetic', -0.01, 'present');
SQL
[[ "$(root_query "SELECT COUNT(*) FROM compose_validation.compose_fixture WHERE id=1 AND label='café 東京 🌍' AND amount=12.34 AND optional_text IS NULL; SELECT COUNT(*) FROM compose_validation.compose_fixture; SELECT @@event_scheduler; SELECT COUNT(*) FROM mysql.user WHERE User='local_only' AND authentication_string<>'';")" == $'1\n2\nDISABLED\n1' ]] || fail 'application SQL data, event isolation or preservation of local users failed'
if printf "UPDATE mysql.user SET authentication_string='' WHERE User='local_only';\n" | app_import > "$SCRATCH/denied.txt" 2>&1; then
  fail 'application user was permitted to modify mysql.user'
fi
grep -q 'ERROR 1142 ' "$SCRATCH/denied.txt" || fail 'expected system-table permission error missing'
cp "$SCRATCH/denied.txt" "$RESULTS/expected-system-table-denial.txt"
[[ "$(root_query "SELECT COUNT(*) FROM mysql.user WHERE User='local_only' AND authentication_string<>'';")" == 1 ]] || fail 'local-only system account changed'
"${COMPOSE[@]}" stop --timeout 60
[[ "$(docker inspect --format '{{.State.ExitCode}}/{{.State.OOMKilled}}' "$CONTAINER")" == 0/false ]] || fail 'Compose server did not stop gracefully'
printf 'PASS: resolved Compose restore configuration, localhost binding, application-user SQL import, local users preserved, system-table writes denied, events DISABLED and graceful shutdown (%s seconds).\n' "$((SECONDS - START_SECONDS))" | tee "$RESULTS/result.txt"
