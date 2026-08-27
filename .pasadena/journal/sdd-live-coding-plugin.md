---
branch: sdd/live-coding-plugin
spec: docs/sdd/specs/2026-08-27-live-coding-plugin.md
plan: docs/sdd/plans/2026-08-27-live-coding-plugin.md
status: in-progress
started: 2026-08-27
---

## Goal
Плагін для Claude Code, що обслуговує live coding сесії з фронтендом: підняти
dev-інстанс однією командою (зі скануванням package manager, .env і залежностей
у worktree), швидко застосовувати правки без тестів і прототипування, змінювати
поведінку скілів pasadena на «правити код одразу», і глушити застосунок на
завершенні сесії.

## Now
Код готовий, `bash test.sh` зелений (29 перевірок). Три раунди дефектів
виправлено: dot-теки в detect, відмова pnpm від symlink'нутого node_modules,
і виклик скрипта через змінну кореня плагіна (вона порожня поза хуками —
кожен задокументований виклик вів у /bin/live.sh). Далі лишається тільки те,
що автотестом не візьмеш: /plugin install, /hooks, рестарт сесії, перевірка
SessionStart-дайджесту і SessionEnd-teardown на живому фронтенді.
Draft PR #1: https://github.com/dmytro-rudenko/live-coding/pull/1

## Timeline

### 2026-08-27
- 15:12 ● 9c9a675 chore(journal): start live-coding plugin

### 2026-08-27
- ✎ Спека узгоджена: самодостатній плагін, стан у .git/, перевизначення penny через контекст із SessionStart-хука.
- 15:36 ● 10ced87 docs(spec): live-coding plugin design
- 15:45 ● 006f1f6 chore: init
- 15:45 ● 2d08cb4 chore(journal): start live-coding plugin
- 15:45 ● 0aa8b78 docs(spec): live-coding plugin design
- 15:45 ● e36f5f2 chore(journal): record spec commit
- ✎ План затверджено: 6 задач у 2 хвилі, контракт bin/live.sh зафіксовано в Global constraints, тому скіли й хуки не чекають на скрипт.
- 16:49 ● 511d33d docs(plan): live-coding implementation plan
- 16:55 ● 41598c8 feat(live-coding): plugin skeleton, live.sh, skills, hooks
- ✎ Реальна перевірка знайшла два дефекти: detect збирав .claude/worktrees/*, а pnpm відхиляє symlink'нутий node_modules (ERR_PNPM_UNSAFE_MODULES_DIR) — symlink лишився тільки для npm/yarn, сигнатуру відкату розширено.
- 16:58 ● 78fce8b fix(live.sh): skip dot-directories in detect, never symlink node_modules for pnpm
- 16:59 ● bf07ae3 docs(plan): tick off the executed tasks
- 17:15 ● d3ff1d2 chore(journal): record the plan commit
- 17:19 ● 61837ab fix(live-coding): call live.sh by name, not through the plugin-root variable
- ✎ CLAUDE_PLUGIN_ROOT порожній у Bash-інструменті — перевірено в цій сесії; PATH натомість містить bin/ кожного плагіна, тож live.sh кличеться голим іменем. test.sh тепер стереже це в обидва боки.
- 17:20 ● fb561e4 chore(journal): record the plugin wiring fix
