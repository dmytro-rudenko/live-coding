---
branch: sdd/live-coding-plugin
spec: docs/sdd/specs/2026-08-27-live-coding-plugin.md
plan: -
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
Shaping завершено. Специфікація написана й закомічена:
docs/sdd/specs/2026-08-27-live-coding-plugin.md. Чекаємо на затвердження
користувача, далі — leonard (план). Віддаленого репозиторію ще немає, тому
draft PR не створено.

## Timeline

### 2026-08-27
- 15:12 ● 9c9a675 chore(journal): start live-coding plugin

### 2026-08-27
- ✎ Спека узгоджена: самодостатній плагін, стан у .git/, перевизначення penny через контекст із SessionStart-хука.
- 15:36 ● 10ced87 docs(spec): live-coding plugin design
