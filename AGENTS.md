# AGENTS.md

## Project shape

- `ip.sh` is the sole runtime entrypoint: a Bash network-diagnostic CLI. There is no package manager, build step, general test framework, linter, typechecker, CI, or code generation in this repository; `tests/test_mtr_parser.sh` is a self-contained mock-based regression check.
- `README.md` documents user-facing commands and runtime limitations; `rules.conf.example` is the checked-in fallback rule data; `assets/` contains screenshots only.
- Target Linux/WSL with a modern Bash (the script uses associative arrays and `wait -n`), not native Windows `cmd`/PowerShell.

## Checks and execution

- Static check: `bash -n ip.sh`.
- Offline regression check: `bash tests/test_mtr_parser.sh` (requires `mawk` and `jq`; mocks `mtr`, `curl`, `getent`, and `awk`; no network).
- Offline smoke check: `./ip.sh --help`; help exits before dependency installation and network probes.
- A real check is network-dependent and can be slow. Prefer a focused run such as `./ip.sh -4 --only AI --low-resource`; use `--only Social`, `-6`, or `--json` for other focused runs. Plain `./ip.sh` probes both IP families and every configured domain.
- Exit `0` means at least one pass ran with no `down` results, `1` covers configuration/dependency failure, and `2` means no pass ran (for example, the requested family is unavailable) or one or more domain probes are down. A `hidden` mtr path is distinct and does not count as `down`.
- `--json` is still a live probe; it is not an offline test mode.

## Runtime gotchas

- A normal run may auto-install missing `mtr` and `jq` through the detected Linux package manager, using root or `sudo`; it explicitly checks `curl`, `timeout`, `awk`, `grep`, and `getent` but does not auto-install them. Avoid invoking a full run for static validation when system changes are not intended.
- The script calls public IP/ASN services and `mtr`. It writes temporary data and `last.json` under `$HOME/.cache/egress-check` by default; `EGRESS_CACHE` changes the cache root, and `EGRESS_DEBUG_MTR=1` preserves raw mtr output under `mtr-debug/`.
- The script uses `set -euo pipefail`; when editing it, preserve strict-mode behavior and the cleanup/signal traps.

## Rules and routing invariants

- Rule lines are `Category | Domain | reserved | reserved | Note`; blank lines and `#` comments are ignored, only the first two fields are required, and `--only` matches the category exactly.
- Keep the embedded `DEFAULT_RULES` in `ip.sh` synchronized with `rules.conf.example` when changing targets. A clone uses `rules.conf` if present, then the example; the remote `bash <(curl ...)` path has no sibling rules file and falls back to the embedded list.
- `first_public_hop` deliberately excludes private hops and the resolved target, retries mtr, and falls back from numeric to hostname report parsing. IP validation intentionally avoids awk interval expressions; `getent` target hints must match a responding final hop before `__HIDDEN__` or a normal result is emitted, while parser failures return no result so fallback/retry continues.
- The first public hop and target average latency are separate values; display the target's final-hop average, not the first hop's latency.
- In the default `EGRESS_BASE_MODE=auto`, a mismatch between the HTTP egress ASN and the MTR path baseline is treated as NAT/tunnel topology and the MTR baseline is used for split comparisons. `EGRESS_BASE_MODE=echo` and `mtr` explicitly select the HTTP or MTR baseline; `hidden` means the path is not visible enough to classify.
