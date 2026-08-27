# live-coding

A Claude Code plugin for the sessions where you keep the frontend open in a
browser tab and want the edits to show up there, not in a test report.

`/live` finds the dev command, bootstraps the worktree if it needs it, starts
the server and hands you the URL. `/do-it` applies a list of fixes and gets out
of the way. Leaving the session kills the server.

## Install

    /plugin marketplace add dmytro-rudenko/live-coding
    /plugin install live-coding

The bundled hooks need to be trusted once through `/hooks` before the session
digest and the automatic teardown work.

## Commands

| Command | What it does |
|---|---|
| `/live` | starts the session, or prints the status of a running one |
| `/live-stop` | stops the dev server by hand |
| `/do-it` | applies a list of fixes — no tests, no browser, no commits |

## What `/live` does

1. **Detect.** Walks the repo three levels deep for a `package.json` with a
   `dev`, `start:dev` or `serve` script. The package manager comes from the
   lockfile — `pnpm-lock.yaml`, `yarn.lock`, `bun.lock*`, `package-lock.json` —
   then from `packageManager`, then npm.

   Several candidates get one question, and the answer is remembered. None gets
   one open question — "what command brings it up?" — and that answer is
   remembered too. That is why `python manage.py runserver`, `bin/rails s` and
   `make dev` work without any Node-specific support.

2. **Bootstrap, in a linked worktree only.** Copies the missing `.env*` files
   from the main worktree. If `node_modules` is absent and the lockfiles are
   byte-identical, symlinks the main worktree's; otherwise installs. If the
   symlink turns out to be wrong — `Cannot find module` in the log — it is torn
   down, a full install runs, and the server is restarted once.

3. **Start.** `setsid` puts the server in its own process group, and the port
   is read from the log rather than assumed from the framework's default: when
   5173 is taken, vite quietly takes another one and only the log knows.

4. **Open.** `xdg-open` on the URL, and the rules block below goes into the
   session.

## State

Two places, both inside `.git/`, so nothing is ever committed and your
`.gitignore` stays untouched.

| What | Where | Scope |
|---|---|---|
| The chosen app | `$(git rev-parse --git-common-dir)/live/config.json` | shared by every worktree of the repo |
| The running session | `$(git rev-parse --git-dir)/live/session.json` | one per worktree |
| The dev server log | `$(git rev-parse --git-dir)/live/dev.log` | one per worktree |

Outside a git repository both collapse into `./.live/`.

Two worktrees can therefore run their own dev servers on their own ports at the
same time, while a fresh worktree still remembers which app you start.

## Teardown

`SessionEnd` stops the server on `logout`, `prompt_input_exit` and `other`.
`clear` is deliberately absent: clearing the context is not finishing the work,
your browser tab is still open, and `SessionStart` puts the rules straight back.

The kill goes to the process group, not the pid. `pnpm run dev` is a wrapper —
killing it alone leaves vite orphaned and still holding the port.

## Overriding pasadena

This plugin does not edit [pasadena](https://github.com/dmytro-rudenko/pasadena).
The rules below are delivered through the `SessionStart` hook instead, which is
why they survive `/clear` and compaction — and why `penny/SKILL.md` says nothing
about them. This section is where that is written down.

While a live session is active:

> - **`penny` не будує прототип.** Ні теки `docs/sdd/proto/`, ні proto-сервера,
>   ні `decision.md`. Варіанти стають послідовними ітераціями по реальному коду:
>   внести зміну → сказати, куди дивитись → чекати вердикт користувача.
> - **Backend-розрив не реалізується.** Опис іде рядком у `docs/live/deferred.md`
>   (що потрібно, чому не зроблено зараз, який фронтенд на це чекає), робота
>   лишається фронтендною.
> - `sheldon`, `leonard`, `wolowitz`, `amy` працюють без змін. Явний запит на
>   повний SDD-цикл виконується як завжди.

`docs/live/deferred.md` is committed with your code. Turning it into a
specification is separate work through `/bazinga`.

## `bin/live.sh`

The skills are judgement; this script is the mechanics. It is usable on its own
and every subcommand prints one line of JSON.

    live.sh detect
    live.sh config-set --dir apps/web
    live.sh bootstrap [--dry-run]
    live.sh start --dir apps/web [--cmd "..."] [--open]
    live.sh status
    live.sh stop
    live.sh session-start

Only `git`, `sed` and `grep` are required. `node` is called for one thing —
reading `package.json` — and a repo that has one has node.

## Tests

    bash test.sh

Ends in `All checks passed.` The start/stop path is exercised end to end
against a fake dev server that prints a URL and sleeps, so the suite needs no
framework installed.

## License

MIT
