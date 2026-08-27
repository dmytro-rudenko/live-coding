#!/usr/bin/env bash
# Self-check for the live-coding plugin. Run: bash test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
LIVE="$ROOT/bin/live.sh"
fails=0
tmpdirs=()

cleanup() {
  for d in "${tmpdirs[@]:-}"; do
    [ -n "$d" ] || continue
    [ -f "$d/.git/live/session.json" ] && (cd "$d" && bash "$LIVE" stop >/dev/null 2>&1)
    rm -rf "$d"
  done
}
trap cleanup EXIT

ok() { echo "  ok  — $1"; }

fail() {
  echo "  FAIL — $1"
  fails=$((fails + 1))
}

assert_contains() {
  if [[ "$1" == *"$2"* ]]; then
    ok "$3"
  else
    fail "$3"
    echo "        expected substring: $2"
    echo "        got: $1"
  fi
}

assert_empty() {
  if [ -z "$1" ]; then
    ok "$2"
  else
    fail "$2"
    echo "        expected empty output, got: $1"
  fi
}

mk() {
  local d
  d="$(mktemp -d)"
  tmpdirs+=("$d")
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name tester
  printf '{"name":"root","private":true}\n' >"$d/package.json"
  git -C "$d" add -A
  git -C "$d" commit -qm init
  printf '%s' "$d"
}

# Repo with a lockfile and one app that has a dev script.
setup_repo() {
  local d lock="${1:-pnpm-lock.yaml}"
  d="$(mk)"
  printf 'lockfile\n' >"$d/$lock"
  mkdir -p "$d/apps/web"
  printf '{"name":"web","scripts":{"dev":"vite"}}\n' >"$d/apps/web/package.json"
  git -C "$d" add -A
  git -C "$d" commit -qm app
  printf '%s' "$d"
}

echo "detect"

d="$(setup_repo pnpm-lock.yaml)"
out="$(cd "$d" && bash "$LIVE" detect)"
assert_contains "$out" '"dir":"apps/web"' "finds the app directory"
assert_contains "$out" '"script":"dev"' "finds the dev script"
assert_contains "$out" '"pm":"pnpm"' "pnpm-lock.yaml means pnpm"

d="$(setup_repo package-lock.json)"
out="$(cd "$d" && bash "$LIVE" detect)"
assert_contains "$out" '"pm":"npm"' "package-lock.json means npm"

d="$(mk)"
out="$(cd "$d" && bash "$LIVE" detect)"
assert_contains "$out" '"candidates":[]' "no dev script, no candidates"

d="$(setup_repo)"
mkdir -p "$d/.claude/worktrees/other"
printf '{"name":"other","scripts":{"dev":"vite"}}\n' >"$d/.claude/worktrees/other/package.json"
out="$(cd "$d" && bash "$LIVE" detect)"
if [[ "$out" == *".claude/worktrees"* ]]; then
  fail "dot-directories are scanned; a repo full of worktrees drowns the list"
else
  ok "dot-directories are skipped, worktrees included"
fi

echo
echo "config"

d="$(setup_repo)"
(cd "$d" && bash "$LIVE" config-set --dir apps/web >/dev/null)
out="$(cd "$d" && bash "$LIVE" detect)"
assert_contains "$out" '"config":{"dir":"apps/web"' "the remembered choice comes back"

echo
echo "no session"

d="$(setup_repo)"
out="$(cd "$d" && bash "$LIVE" status)"
assert_contains "$out" '{"active":false}' "status without a session"
out="$(cd "$d" && bash "$LIVE" stop)"
code=$?
assert_contains "$out" '"stopped":false' "stop without a session says so"
[ "$code" = 0 ] && ok "stop without a session still exits 0" ||
  fail "stop without a session exited $code"
out="$(cd "$d" && bash "$LIVE" session-start)"
assert_empty "$out" "session-start is silent without a session"

echo
echo "bootstrap"

d="$(setup_repo)"
out="$(cd "$d" && bash "$LIVE" bootstrap --dry-run)"
assert_contains "$out" '"linked":false' "the main worktree needs no bootstrap"

mkwt() {
  local d="$1" wt
  wt="$(mktemp -d)/wt"
  tmpdirs+=("$(dirname "$wt")")
  git -C "$d" worktree add -q -b "feat-$RANDOM" "$wt" 2>/dev/null
  printf '%s' "$wt"
}

d="$(setup_repo package-lock.json)"
printf 'A=1\n' >"$d/.env"
mkdir -p "$d/node_modules"
wt="$(mkwt "$d")"
out="$(cd "$wt" && bash "$LIVE" bootstrap --dry-run)"
assert_contains "$out" '"linked":true' "a linked worktree is detected"
assert_contains "$out" '".env"' "the missing .env is listed for copying"
assert_contains "$out" '"deps":"symlink"' "npm with identical lockfiles allows the symlink"

printf 'changed\n' >"$wt/package-lock.json"
out="$(cd "$wt" && bash "$LIVE" bootstrap --dry-run)"
assert_contains "$out" '"deps":"install"' "a diverged lockfile forces a full install"

# pnpm refuses a modules dir whose target is outside the project root
# (ERR_PNPM_UNSAFE_MODULES_DIR), so it never gets a symlink.
d="$(setup_repo pnpm-lock.yaml)"
mkdir -p "$d/node_modules"
wt="$(mkwt "$d")"
out="$(cd "$wt" && bash "$LIVE" bootstrap --dry-run)"
assert_contains "$out" '"deps":"install"' "pnpm installs instead of symlinking"

echo
echo "start and stop"

d="$(setup_repo)"
out="$(cd "$d" && bash "$LIVE" start --dir . \
  --cmd 'printf "  Local: http://localhost:4321/\n"; sleep 30')"
assert_contains "$out" '"url":"http://localhost:4321"' "the url comes out of the log"
assert_contains "$out" '"port":4321' "the port comes out of the log"

pgid="$(sed -n 's/.*"pgid":\([0-9]*\).*/\1/p' <<<"$out")"

out="$(cd "$d" && bash "$LIVE" status)"
assert_contains "$out" '"active":true' "the running session reports active"

out="$(cd "$d" && bash "$LIVE" session-start)"
assert_contains "$out" 'LIVE CODING SESSION ACTIVE' "session-start injects the rules"
assert_contains "$out" 'additionalContext' "session-start speaks the hook protocol"

out="$(cd "$d" && bash "$LIVE" start --dir . --cmd 'sleep 30')"
assert_contains "$out" '"already":true' "a second start does not spawn a second server"

out="$(cd "$d" && bash "$LIVE" stop)"
assert_contains "$out" '"stopped":true' "stop reports success"
sleep 0.3
if kill -0 -- -"$pgid" 2>/dev/null; then
  fail "the process group survived stop"
else
  ok "the whole process group is gone"
fi

echo
echo "skills"

shopt -s nullglob
for dir in "$ROOT"/skills/*/; do
  name="$(basename "$dir")"
  file="$dir/SKILL.md"
  [ -f "$file" ] || { fail "$name: no SKILL.md"; continue; }

  if [ "$(sed -n '1p' "$file")" != "---" ]; then
    fail "$name: frontmatter does not open with ---"
    continue
  fi
  end="$(awk 'NR > 1 && /^---$/ { print NR; exit }' "$file")"
  if [ -z "$end" ]; then
    fail "$name: frontmatter has no closing ---"
    continue
  fi
  fm="$(sed -n "2,$((end - 1))p" "$file")"

  grep -q "^name: $name$" <<<"$fm" ||
    fail "$name: frontmatter name does not match the directory"
  grep -q "^description: ." <<<"$fm" ||
    fail "$name: frontmatter has no description"
  ok "$name: frontmatter"
done

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
