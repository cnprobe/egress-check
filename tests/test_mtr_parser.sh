#!/usr/bin/env bash
# Offline regression tests for the mtr report parser in ip.sh.

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IP_SH="$ROOT_DIR/ip.sh"
MAWK_BIN="${MAWK_BIN:-$(command -v mawk || true)}"
JQ_BIN="$(command -v jq || true)"

if [[ -z "$MAWK_BIN" || -z "$JQ_BIN" ]]; then
    printf 'SKIP: mawk and jq are required for parser regression tests\n' >&2
    exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
MOCK_BIN="$TMP_DIR/bin"
CACHE_DIR="$TMP_DIR/cache"
mkdir -p "$MOCK_BIN" "$CACHE_DIR"

cat > "$MOCK_BIN/awk" <<'EOF'
#!/usr/bin/env bash
exec "$EGRESS_TEST_MAWK" -W traditional "$@"
EOF

cat > "$MOCK_BIN/mtr" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" -n "* && "${EGRESS_TEST_NUMERIC_EMPTY:-0}" == 1 ]]; then
    exit 0
fi
if [[ "$*" == *"google.com"* ]]; then
    if [[ "${EGRESS_TEST_NAMES_MODE:-0}" == 1 ]]; then
        cat "$EGRESS_TEST_BASE_NAMES"
    else
        cat "$EGRESS_TEST_BASE_MTR"
    fi
else
    if [[ "${EGRESS_TEST_NAMES_MODE:-0}" == 1 ]]; then
        cat "$EGRESS_TEST_TARGET_NAMES"
    else
        cat "$EGRESS_TEST_TARGET_MTR"
    fi
fi
EOF

cat > "$MOCK_BIN/curl" <<'EOF'
#!/usr/bin/env bash
family=4
for arg in "$@"; do
    [[ "$arg" == "-6" ]] && family=6
    [[ "$arg" == "-4" ]] && family=4
done
url="${!#}"
case "$url" in
    *ipinfo.io/*/json)
        printf '%s\n' '{"country":"US","org":"AS64500 Example Network"}'
        ;;
    *api.ip.sb/geoip/*)
        printf '%s\n' '{"country_code":"US","asn":64500,"asn_organization":"Example Network"}'
        ;;
    *ipwho.is/*)
        printf '%s\n' '{"success":true,"country_code":"US","connection":{"asn":64500,"isp":"Example Network"}}'
        ;;
    *)
        if [[ "$family" == 6 ]]; then
            printf '%s\n' '2001:db8:1::10'
        else
            printf '%s\n' '198.51.100.10'
        fi
        ;;
esac
EOF

cat > "$MOCK_BIN/getent" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"ahostsv6"* ]]; then
    printf '%s\n' '2001:db8:1::10 STREAM example.test'
else
    printf '%s\n' '203.0.113.10 STREAM example.test'
fi
EOF
chmod +x "$MOCK_BIN/awk" "$MOCK_BIN/mtr" "$MOCK_BIN/curl" "$MOCK_BIN/getent"

cat > "$TMP_DIR/base.mtr" <<'EOF'
HOST: test                         Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- 192.168.1.1               0.0%     1    1.0   1.0   1.0   1.0   0.0
  2.|-- 198.51.100.20             0.0%     1    2.0   2.0   2.0   2.0   0.0
  3.|-- 203.0.113.10              0.0%     1    3.0   3.0   3.0   3.0   0.0
EOF

cat > "$TMP_DIR/route.mtr" <<'EOF'
HOST: test                         Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- 192.168.1.1               0.0%     1    1.0   1.0   1.0   1.0   0.0
  2.|-- ???                       100.0     1    0.0   0.0   0.0   0.0   0.0
  3.|-- 198.51.100.20             0.0%     1    2.0   2.0   2.0   2.0   0.0
  4.|-- 203.0.113.10              0.0%     1    9.0   9.0   9.0   9.0   0.0
EOF

cat > "$TMP_DIR/base6.mtr" <<'EOF'
HOST: test                         Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- fe80::1                   0.0%     1    1.0   1.0   1.0   1.0   0.0
  2.|-- 2001:db8:1::20            0.0%     1    2.0   2.0   2.0   2.0   0.0
  3.|-- 2001:db8:1::10            0.0%     1    3.0   3.0   3.0   3.0   0.0
EOF

cat > "$TMP_DIR/route6.mtr" <<'EOF'
HOST: test                         Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- fe80::1                   0.0%     1    1.0   1.0   1.0   1.0   0.0
  2.|-- 2001:db8:1::20            0.0%     1    2.0   2.0   2.0   2.0   0.0
  3.|-- 2001:0db8:0001:0000:0000:0000:0000:0010  0.0%     1    9.0   9.0   9.0   9.0   0.0
EOF

cat > "$TMP_DIR/base-names.mtr" <<'EOF'
HOST: test                         Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- local (192.168.1.1)       0.0%     1    1.0   1.0   1.0   1.0   0.0
  2.|-- hop (198.51.100.20)       0.0%     1    2.0   2.0   2.0   2.0   0.0
  3.|-- target (203.0.113.10)     0.0%     1    3.0   3.0   3.0   3.0   0.0
EOF

cat > "$TMP_DIR/names.mtr" <<'EOF'
HOST: test                         Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- local (192.168.1.1)       0.0%     1    1.0   1.0   1.0   1.0   0.0
  2.|-- hop (198.51.100.20)       0.0%     1    2.0   2.0   2.0   2.0   0.0
  3.|-- target (203.0.113.10)     0.0%     1    9.0   9.0   9.0   9.0   0.0
EOF

cat > "$TMP_DIR/hidden.mtr" <<'EOF'
HOST: test                         Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- 203.0.113.10              0.0%     1    9.0   9.0   9.0   9.0   0.0
EOF

cat > "$TMP_DIR/unconfirmed.mtr" <<'EOF'
HOST: test                         Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- 198.51.100.20             0.0%     1    2.0   2.0   2.0   2.0   0.0
  2.|-- ???                       100.0     1    0.0   0.0   0.0   0.0   0.0
EOF

cat > "$TMP_DIR/unconfirmed-target.mtr" <<'EOF'
HOST: test                         Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- 198.51.100.20             0.0%     1    2.0   2.0   2.0   2.0   0.0
  2.|-- 203.0.113.10              100.0     1    0.0   0.0   0.0   0.0   0.0
EOF

cat > "$TMP_DIR/unconfirmed-target-percent.mtr" <<'EOF'
HOST: test                         Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- 198.51.100.20             0.0%     1    2.0   2.0   2.0   2.0   0.0
  2.|-- 203.0.113.10              100.0%    1    0.0   0.0   0.0   0.0   0.0
EOF

cat > "$TMP_DIR/truncated.mtr" <<'EOF'
HOST: test                         Loss%   Snt   Last   Avg  Best  Wrst StDev
  1.|-- 192.168.1.1               0.0%     1    1.0   1.0   1.0   1.0   0.0
  2.|-- 198.51.100.20             0.0%     1    2.0   2.0   2.0   2.0   0.0
EOF

printf 'Test|example.test|||Test target\n' > "$TMP_DIR/rules.conf"

run_case() {
    local family="$1"
    shift
    local name="$1" target_fixture="$2" expected_status="$3" expected_result="$4" expected_first="$5" expected_latency="$6" variant="${7:-numeric}"
    local output="$TMP_DIR/$name.json" status result first latency ip_flag json_key base_fixture names_mode numeric_empty
    ip_flag="-4"
    json_key=".ipv4"
    base_fixture="$TMP_DIR/base.mtr"
    names_mode=0
    numeric_empty=0
    if [[ "$family" == 6 ]]; then
        ip_flag="-6"
        json_key=".ipv6"
        base_fixture="$TMP_DIR/base6.mtr"
    fi
    if [[ "$variant" == names ]]; then
        names_mode=1
        numeric_empty=1
        target_fixture="$TMP_DIR/names.mtr"
        base_fixture="$TMP_DIR/base-names.mtr"
    fi

    if EGRESS_TEST_MAWK="$MAWK_BIN" \
       EGRESS_TEST_BASE_MTR="$base_fixture" \
       EGRESS_TEST_TARGET_MTR="$target_fixture" \
       EGRESS_TEST_BASE_NAMES="$TMP_DIR/base-names.mtr" \
       EGRESS_TEST_TARGET_NAMES="$TMP_DIR/names.mtr" \
       EGRESS_TEST_NAMES_MODE="$names_mode" \
       EGRESS_TEST_NUMERIC_EMPTY="$numeric_empty" \
       PATH="$MOCK_BIN:$PATH" \
       EGRESS_RULES="$TMP_DIR/rules.conf" \
       EGRESS_CACHE="$CACHE_DIR/$name" \
       MTR_COUNT=1 MTR_ATTEMPTS=1 MTR_TIMEOUT=2 \
       "$IP_SH" "$ip_flag" --only Test --json > "$output"; then
        status=0
    else
        status=$?
    fi

    [[ "$status" -eq "$expected_status" ]] || {
        printf 'FAIL %s: exit %s, expected %s\n' "$name" "$status" "$expected_status" >&2
        cat "$output" >&2
        return 1
    }

    result="$($JQ_BIN -r "${json_key}.results[0].status" "$output")"
    first="$($JQ_BIN -r "${json_key}.results[0].first_hop // \"null\"" "$output")"
    latency="$($JQ_BIN -r "${json_key}.results[0].latency_ms // \"null\"" "$output")"
    [[ "$result" == "$expected_result" && "$first" == "$expected_first" && "$latency" == "$expected_latency" ]] || {
        printf 'FAIL %s: got status=%s first_hop=%s latency=%s, expected status=%s first_hop=%s latency=%s\n' \
            "$name" "$result" "$first" "$latency" "$expected_result" "$expected_first" "$expected_latency" >&2
        cat "$output" >&2
        return 1
    }
    printf 'PASS %s\n' "$name"
}

run_case 4 route "$TMP_DIR/route.mtr" 0 ok 198.51.100.20 9.0
run_case 4 hidden "$TMP_DIR/hidden.mtr" 0 hidden null 9.0
run_case 4 unconfirmed "$TMP_DIR/unconfirmed.mtr" 2 down null null
run_case 4 unconfirmed-target "$TMP_DIR/unconfirmed-target.mtr" 2 down null null
run_case 4 unconfirmed-target-percent "$TMP_DIR/unconfirmed-target-percent.mtr" 2 down null null
run_case 4 truncated "$TMP_DIR/truncated.mtr" 2 down null null
run_case 4 names "$TMP_DIR/names.mtr" 0 ok 198.51.100.20 9.0 names
run_case 6 route6 "$TMP_DIR/route6.mtr" 0 ok 2001:db8:1::20 9.0
