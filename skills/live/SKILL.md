---
name: live
description: Use when the user asks to start a live coding session, bring the frontend up in dev mode, run the app locally with hot reload, or check a running live session. Detects the dev command, bootstraps a worktree, starts the server and opens the browser
allowed-tools:
  - Read
  - Grep
  - Glob
  - AskUserQuestion
  - TodoWrite
  - Bash(live.sh *)
  - Bash(git worktree *)
  - Bash(tail *)
  - Bash(ls *)
disallowed-tools:
  - Agent
  - NotebookEdit
---

# Live session

Bring this project's frontend up in dev mode, hand the user a URL, and put the
live-mode rules into the session.

Every mechanical step belongs to `live.sh`. This skill only decides *what* to
start and reports the result.

The plugin's `bin/` is on `PATH`, so `live.sh` is called by name — never
through a plugin-root variable. That variable is set for hooks and nowhere else;
in a skill body it expands to nothing, and the path built from it resolves to
`/bin/live.sh`. If `command -v live.sh` comes back empty the plugin is not
installed: say so and stop.

## 1. Already running?

    live.sh status

`"active":true` means the work is done. Print the URL, the app directory and
the log path, reprint the rules block from step 4, and stop. Never start a
second server.

## 2. What to start

    live.sh detect

The output carries `candidates` (each `{dir, script, pm}`) and the remembered
`config`.

| Situation | What to do |
|---|---|
| `config.dir` is set and still among the candidates | start it, ask nothing |
| exactly one candidate | start it, ask nothing |
| several candidates | one `AskUserQuestion` listing the directories, then `config-set --dir <dir>` |
| no candidates | one open question: "якою командою підняти застосунок?", then `config-set --cmd "<command>"` |

The last row is what makes this work outside Node. `python manage.py runserver`,
`bin/rails s`, `hugo server` and `make dev` need no special support — the
remembered command is run verbatim, and the port still comes out of the log.

## 3. Start it

    live.sh start --dir <dir> --open

In a linked worktree this first copies the missing `.env*` files from the main
worktree and links or installs `node_modules`. That runs without asking: a
worktree without dependencies cannot serve anything, so there is no other
branch to choose.

On `"error"`, print the last 20 lines of the log it names and stop. Do not try
to repair someone else's project — report what the dev server said and let the
user decide.

## 4. Report

Print the URL, the app directory and the log path. Then print this block
verbatim, substituting the three values:

> LIVE CODING SESSION ACTIVE — `<url>`, застосунок `<dir>`, лог `<log>`.
> Поки сесія активна:
> - **`penny` не будує прототип.** Ні теки `docs/sdd/proto/`, ні proto-сервера,
>   ні `decision.md`. Варіанти стають послідовними ітераціями по реальному коду:
>   внести зміну → сказати, куди дивитись → чекати вердикт користувача.
> - **Backend-розрив не реалізується.** Опис іде рядком у `docs/live/deferred.md`
>   (що потрібно, чому не зроблено зараз, який фронтенд на це чекає), робота
>   лишається фронтендною.
> - `sheldon`, `leonard`, `wolowitz`, `amy` працюють без змін. Явний запит на
>   повний SDD-цикл виконується як завжди.

The same block is re-injected by the `SessionStart` hook, so it survives
`/clear` and compaction for as long as the session is alive.

## Ending it

`/live-stop`, or leaving Claude Code — the `SessionEnd` hook stops the server.
`/clear` deliberately does not: clearing the context is not finishing the work,
and the browser tab stays open.
