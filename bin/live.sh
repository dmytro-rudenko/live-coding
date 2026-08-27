#!/usr/bin/env bash
# live-coding: bring the frontend dev server up, report it, tear it down.
# Usage: live.sh detect | config-set | bootstrap | start | stop | status | session-start
set -uo pipefail

URL_RE='https?://(localhost|127\.0\.0\.1|\[::1\]):[0-9]+'
DEPS_BROKEN_RE='Cannot find (module|package)|command not found|ERR_MODULE_NOT_FOUND|UNSAFE_MODULES_DIR'

state_paths() {
  if git rev-parse --git-dir >/dev/null 2>&1; then
    ROOT="$(git rev-parse --show-toplevel)"
    GIT_DIR="$(cd "$(git rev-parse --git-dir)" && pwd)"
    GIT_COMMON="$(cd "$(git rev-parse --git-common-dir)" && pwd)"
    CONFIG_DIR="$GIT_COMMON/live"
    STATE_DIR="$GIT_DIR/live"
  else
    ROOT="$PWD"
    GIT_DIR=""
    GIT_COMMON=""
    CONFIG_DIR="$PWD/.live"
    STATE_DIR="$PWD/.live"
  fi
  CONFIG="$CONFIG_DIR/config.json"
  CONFIG_CMD="$CONFIG_DIR/config.cmd"
  SESSION="$STATE_DIR/session.json"
  SESSION_CMD="$STATE_DIR/session.cmd"
  PGID_FILE="$STATE_DIR/pgid"
  LOG="$STATE_DIR/dev.log"
  mkdir -p "$CONFIG_DIR" "$STATE_DIR" 2>/dev/null
}

linked_worktree() { [ -n "$GIT_DIR" ] && [ "$GIT_DIR" != "$GIT_COMMON" ]; }

jget() {
  [ -f "$1" ] || return 0
  sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",}]*\)\"\{0,1\}.*/\1/p" "$1" | head -1
}

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' |
    awk 'BEGIN { ORS = "" } { print sep $0; sep = "\\n" }'
}

session_alive() {
  [ -f "$SESSION" ] || return 1
  local pgid
  pgid="$(jget "$SESSION" pgid)"
  if [ -n "$pgid" ] && kill -0 -- -"$pgid" 2>/dev/null; then
    return 0
  fi
  rm -f "$SESSION" "$SESSION_CMD"
  return 1
}

detect_pm() {
  if [ -f "$ROOT/pnpm-lock.yaml" ]; then printf pnpm
  elif [ -f "$ROOT/yarn.lock" ]; then printf yarn
  elif [ -f "$ROOT/bun.lock" ] || [ -f "$ROOT/bun.lockb" ]; then printf bun
  elif [ -f "$ROOT/package-lock.json" ]; then printf npm
  else
    local pm
    pm="$(sed -n 's/.*"packageManager"[[:space:]]*:[[:space:]]*"\([^"@]*\).*/\1/p' \
      "$ROOT/package.json" 2>/dev/null | head -1)"
    printf '%s' "${pm:-npm}"
  fi
}

lockfile_name() {
  case "$1" in
    pnpm) printf pnpm-lock.yaml ;;
    yarn) printf yarn.lock ;;
    bun) [ -f "$ROOT/bun.lockb" ] && printf bun.lockb || printf bun.lock ;;
    *) printf package-lock.json ;;
  esac
}

script_of() {
  node -e '
const fs = require("fs");
let s = {};
try { s = JSON.parse(fs.readFileSync(process.argv[1] + "/package.json", "utf8")).scripts || {}; }
catch { }
const k = ["dev", "start:dev", "serve"].find((k) => s[k]);
if (k) process.stdout.write(k);
' "$1" 2>/dev/null
}

config_json() {
  if [ -f "$CONFIG" ]; then cat "$CONFIG"; else printf '{"dir":null,"cmd":null}'; fi
}

config_cmd() { [ -f "$CONFIG_CMD" ] && cat "$CONFIG_CMD"; }

write_config() {
  local dir="$1" cmd="$2"
  if [ -n "$cmd" ]; then
    printf '%s' "$cmd" >"$CONFIG_CMD"
    printf '{"dir":%s,"cmd":"%s"}\n' \
      "$([ -n "$dir" ] && printf '"%s"' "$dir" || printf null)" "$(json_escape "$cmd")" >"$CONFIG"
  else
    rm -f "$CONFIG_CMD"
    printf '{"dir":%s,"cmd":null}\n' \
      "$([ -n "$dir" ] && printf '"%s"' "$dir" || printf null)" >"$CONFIG"
  fi
}

cmd_detect() {
  state_paths
  local pm cands
  pm="$(detect_pm)"
  cands="$(node -e '
const fs = require("fs"), path = require("path");
const root = process.argv[1], pm = process.argv[2];
const skip = new Set(["node_modules", "dist", "build", "coverage", "vendor", "tmp"]);
const order = ["dev", "start:dev", "serve"];
const out = [];
function walk(dir, depth) {
  let ents;
  try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
  if (ents.some((e) => e.isFile() && e.name === "package.json")) {
    try {
      const s = JSON.parse(fs.readFileSync(path.join(dir, "package.json"), "utf8")).scripts || {};
      const hit = order.find((k) => s[k]);
      if (hit) out.push({ dir: path.relative(root, dir) || ".", script: hit, pm });
    } catch { }
  }
  if (depth >= 3) return;
  for (const e of ents)
    if (e.isDirectory() && !e.name.startsWith(".") && !skip.has(e.name))
      walk(path.join(dir, e.name), depth + 1);
}
walk(root, 0);
process.stdout.write(JSON.stringify(out));
' "$ROOT" "$pm" 2>/dev/null)"
  printf '{"pm":"%s","root":"%s","candidates":%s,"config":%s}\n' \
    "$pm" "$ROOT" "${cands:-[]}" "$(config_json)"
}

cmd_config_set() {
  state_paths
  local dir cmd
  dir="$(jget "$CONFIG" dir)"
  [ "$dir" = null ] && dir=""
  cmd="$(config_cmd)"
  while [ $# -gt 0 ]; do
    case "$1" in
      --dir) dir="$2"; shift 2 ;;
      --cmd) cmd="$2"; shift 2 ;;
      *) printf '{"error":"unknown argument: %s"}\n' "$1"; exit 1 ;;
    esac
  done
  write_config "$dir" "$cmd"
  cat "$CONFIG"
}

main_worktree() { git worktree list --porcelain | sed -n '1s/^worktree //p'; }

link_node_modules() {
  local main="$1" nm rel
  ln -s "$main/node_modules" "$ROOT/node_modules"
  while IFS= read -r nm; do
    rel="${nm#"$main"/}"
    [ "$rel" = node_modules ] && continue
    [ -e "$ROOT/$rel" ] && continue
    mkdir -p "$(dirname "$ROOT/$rel")"
    ln -s "$nm" "$ROOT/$rel"
  done < <(find "$main" -maxdepth 3 -name node_modules -type d \
    -not -path "$main/node_modules/*" 2>/dev/null)
}

unlink_node_modules() {
  local nm
  while IFS= read -r nm; do
    [ -L "$nm" ] && rm -f "$nm"
  done < <(find "$ROOT" -maxdepth 3 -name node_modules -type l 2>/dev/null)
}

cmd_bootstrap() {
  state_paths
  local dry=0
  [ "${1:-}" = "--dry-run" ] && dry=1

  if ! linked_worktree; then
    printf '{"linked":false}\n'
    return 0
  fi

  local main pm lock deps copied="" f rel
  main="$(main_worktree)"
  pm="$(detect_pm)"

  while IFS= read -r f; do
    rel="${f#"$main"/}"
    [ -e "$ROOT/$rel" ] && continue
    copied="$copied${copied:+,}\"$rel\""
    if [ "$dry" = 0 ]; then
      mkdir -p "$(dirname "$ROOT/$rel")"
      cp "$f" "$ROOT/$rel"
    fi
  done < <(find "$main" -maxdepth 3 -name '.env*' -type f \
    -not -path '*/node_modules/*' 2>/dev/null)

  lock="$(lockfile_name "$pm")"
  if [ -e "$ROOT/node_modules" ]; then
    deps=present
  elif [[ "$pm" == npm || "$pm" == yarn ]] &&
    [ -d "$main/node_modules" ] && cmp -s "$main/$lock" "$ROOT/$lock"; then
    deps=symlink
    [ "$dry" = 0 ] && link_node_modules "$main"
  else
    deps=install
    [ "$dry" = 0 ] && (cd "$ROOT" && "$pm" install >>"$LOG" 2>&1)
  fi

  printf '{"linked":true,"env_copied":[%s],"deps":"%s","dry_run":%s}\n' \
    "$copied" "$deps" "$([ "$dry" = 1 ] && printf true || printf false)"
}

launch() {
  rm -f "$PGID_FILE"
  : >"$LOG"
  setsid nohup bash -c 'printf %s "$$" >"$0"; cd "$1" || exit 1; eval "$2"' \
    "$PGID_FILE" "$APPDIR" "$CMD" >"$LOG" 2>&1 &
  local i
  for i in $(seq 1 50); do
    [ -s "$PGID_FILE" ] && break
    sleep 0.1
  done
  PGID="$(cat "$PGID_FILE" 2>/dev/null)"
}

cmd_start() {
  state_paths
  local dir="" cmd="" open=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dir) dir="$2"; shift 2 ;;
      --cmd) cmd="$2"; shift 2 ;;
      --open) open=1; shift ;;
      *) printf '{"error":"unknown argument: %s"}\n' "$1"; exit 1 ;;
    esac
  done

  if session_alive; then
    sed 's/^{/{"already":true,/' "$SESSION"
    return 0
  fi

  [ -n "$dir" ] || dir="$(jget "$CONFIG" dir)"
  [ "$dir" = null ] && dir=""
  [ -n "$dir" ] || dir="."
  APPDIR="$ROOT"
  [ "$dir" = "." ] || APPDIR="$ROOT/$dir"
  if [ ! -d "$APPDIR" ]; then
    printf '{"error":"no such directory: %s"}\n' "$dir"
    return 1
  fi

  [ -n "$cmd" ] || cmd="$(config_cmd)"
  local pm script
  pm="$(detect_pm)"
  if [ -z "$cmd" ]; then
    script="$(script_of "$APPDIR")"
    if [ -z "$script" ]; then
      printf '{"error":"no dev script in %s, pass --cmd"}\n' "$dir"
      return 1
    fi
    cmd="$pm run $script"
  fi
  CMD="$cmd"

  cmd_bootstrap >/dev/null

  local retried=0 url="" port="" i
  launch
  if [ -z "${PGID:-}" ]; then
    printf '{"error":"process did not start","log":"%s"}\n' "$LOG"
    return 1
  fi

  for i in $(seq 1 300); do
    url="$(grep -aoEm1 "$URL_RE" "$LOG" 2>/dev/null)"
    [ -n "$url" ] && break
    if grep -qaE "$DEPS_BROKEN_RE" "$LOG" 2>/dev/null; then
      if [ "$retried" = 0 ] && [ -L "$ROOT/node_modules" ]; then
        kill -- -"$PGID" 2>/dev/null
        unlink_node_modules
        (cd "$ROOT" && "$pm" install >>"$LOG" 2>&1)
        retried=1
        launch
        continue
      fi
      printf '{"error":"dependencies are missing","log":"%s"}\n' "$LOG"
      kill -- -"$PGID" 2>/dev/null
      return 1
    fi
    if ! kill -0 -- -"$PGID" 2>/dev/null; then
      printf '{"error":"process exited before serving","log":"%s"}\n' "$LOG"
      return 1
    fi
    sleep 0.1
  done

  if [ -z "$url" ]; then
    port="$(ss -ltnp 2>/dev/null | sed -n "s/.*:\([0-9]*\) .*pid=$PGID,.*/\1/p" | head -1)"
    if [ -z "$port" ]; then
      printf '{"error":"no url in the log within 30s","log":"%s"}\n' "$LOG"
      kill -- -"$PGID" 2>/dev/null
      return 1
    fi
    url="http://localhost:$port"
  fi
  port="${url##*:}"

  printf '%s' "$CMD" >"$SESSION_CMD"
  printf '{"pgid":%s,"url":"%s","port":%s,"dir":"%s","cmd":"%s","log":"%s","started":"%s"}\n' \
    "$PGID" "$url" "$port" "$dir" "$(json_escape "$CMD")" "$LOG" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$SESSION"

  if [ "$open" = 1 ]; then
    local opener
    for opener in xdg-open open start; do
      command -v "$opener" >/dev/null 2>&1 && { "$opener" "$url" >/dev/null 2>&1 & break; }
    done
  fi
  cat "$SESSION"
}

cmd_stop() {
  state_paths
  if [ ! -f "$SESSION" ]; then
    printf '{"stopped":false,"reason":"no session"}\n'
    return 0
  fi
  local pgid i
  pgid="$(jget "$SESSION" pgid)"
  rm -f "$SESSION" "$SESSION_CMD" "$PGID_FILE"
  if [ -z "$pgid" ] || ! kill -0 -- -"$pgid" 2>/dev/null; then
    printf '{"stopped":false,"reason":"process group %s not running"}\n' "${pgid:-unknown}"
    return 0
  fi
  # The whole group, not just the pid: `pnpm run dev` is a wrapper, and killing
  # it alone leaves vite orphaned and still holding the port.
  kill -- -"$pgid" 2>/dev/null
  for i in $(seq 1 50); do
    kill -0 -- -"$pgid" 2>/dev/null || break
    sleep 0.1
  done
  kill -0 -- -"$pgid" 2>/dev/null && kill -9 -- -"$pgid" 2>/dev/null
  printf '{"stopped":true,"pgid":%s}\n' "$pgid"
}

cmd_status() {
  state_paths
  if session_alive; then
    sed 's/^{/{"active":true,/' "$SESSION"
  else
    printf '{"active":false}\n'
  fi
}

rules_block() {
  cat <<EOF
LIVE CODING SESSION ACTIVE — $1, застосунок $2, лог $3.
Скрипт сесії: $4
Поки сесія активна:
- penny не будує прототип. Ні теки docs/sdd/proto/, ні proto-сервера, ні
  decision.md. Варіанти стають послідовними ітераціями по реальному коду:
  внести зміну -> сказати, куди дивитись -> чекати вердикт користувача.
- Backend-розрив не реалізується. Опис іде рядком у docs/live/deferred.md
  (що потрібно, чому не зроблено зараз, який фронтенд на це чекає), робота
  лишається фронтендною.
- sheldon, leonard, wolowitz, amy працюють без змін. Явний запит на повний
  SDD-цикл виконується як завжди.
EOF
}

cmd_session_start() {
  state_paths
  session_alive || return 0
  local text
  text="$(rules_block "$(jget "$SESSION" url)" "$(jget "$SESSION" dir)" \
    "$(jget "$SESSION" log)" "$(cd "$(dirname "$0")" && pwd)/live.sh")"
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
    "$(json_escape "$text")"
}

case "${1:-}" in
  detect) shift; cmd_detect "$@" ;;
  config-set) shift; cmd_config_set "$@" ;;
  bootstrap) shift; cmd_bootstrap "$@" ;;
  start) shift; cmd_start "$@" ;;
  stop) shift; cmd_stop "$@" ;;
  status) shift; cmd_status "$@" ;;
  session-start) shift; cmd_session_start "$@" ;;
  *) printf '{"error":"usage: live.sh detect|config-set|bootstrap|start|stop|status|session-start"}\n'; exit 1 ;;
esac
