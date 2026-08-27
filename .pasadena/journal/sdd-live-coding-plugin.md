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
Building. План затверджено: docs/sdd/plans/2026-08-27-live-coding-plugin.md.
Хвиля 1 — задачі 1-5 (маніфести, bin/live.sh+test.sh, скіл live, скіл do-it,
хуки), хвиля 2 — README. Виконую послідовно сам, без субагентів.
Перевірка: `bash test.sh` -> `All checks passed.`
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
