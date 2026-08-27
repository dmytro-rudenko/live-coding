# live-coding — implementation plan

**Goal:** встановлюваний плагін Claude Code, у якому `/live` піднімає dev-інстанс
фронтенду (з bootstrap worktree), `/do-it` швидко застосовує список правок без
тестів і перевірок, правила live-режиму переживають `/clear`, а вихід із сесії
глушить dev-сервер по process-group.

**Spec:** `docs/sdd/specs/2026-08-27-live-coding-plugin.md`
**Prototype:** — (немає UI-поверхні)
**Verification:** `bash test.sh` → останній рядок `All checks passed.`

## Context

Кожна фронтенд-сесія починається з ручного ритуалу: попросити підняти dev-сервер,
з'ясувати package manager і скрипт, знайти порт. У linked worktree додається
копіювання `.env*` і встановлення залежностей. Далі `penny` будує викидний
прототип замість того, щоб правити код, який уже відкритий у браузері. На виході
dev-сервер лишається жити і тримати порт.

Плагін закриває всі три розриви й не редагує pasadena — правила режиму
доставляються через `SessionStart`-хук, тому вони переживають `/clear` і
компакцію.

## Global constraints

Ці значення однакові для всіх задач і повторюються в кожній, якій потрібні.

### Стек і стиль

- Уся механіка — **bash**, `set -uo pipefail`, без зовнішніх залежностей окрім
  `git`, `sed`, `grep`. `node` викликається **лише** для сканування
  `package.json` — репозиторій із `package.json` за визначенням має node.
  `jq` не використовується: у не-Node репозиторії його може не бути.
- Стан — **плоский JSON**, один ключ на рядок, пишеться `printf`, читається
  `sed`. Вкладених структур у файлах стану немає саме тому.
- Тести — plain bash у стилі pasadena: `assert_contains`/`ok`/`fail`, лічильник
  `fails`, вихід `All checks passed.` або `FAILED: N` з кодом 1.
- Коментарі в коді — тільки там, де фіксують неочевидне обмеження (group-kill,
  чому порт із лога). Ніяких переказів наступного рядка.

### Шляхи стану

```bash
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" && pwd)   # спільний для worktree
GIT_DIR=$(cd "$(git rev-parse --git-dir)" && pwd)             # свій у кожного worktree
CONFIG="$GIT_COMMON/live/config.json"    # {"dir":"apps/web","cmd":null}
SESSION="$GIT_DIR/live/session.json"     # pgid,url,port,dir,cmd,log,started
LOG="$GIT_DIR/live/dev.log"
```

Поза git-репозиторієм обидва шляхи згортаються в `./.live/`.
Linked worktree = `GIT_DIR != GIT_COMMON`.

### Контракт `bin/live.sh`

Задачі 3, 4 і 5 споживають цей контракт. Він зафіксований тут повністю, тому
вони не чекають на задачу 2 і йдуть із нею в одній хвилі.

| Підкоманда | Вивід |
|---|---|
| `detect` | `{"pm":"pnpm","root":"/abs","candidates":[{"dir":"apps/web","script":"dev","pm":"pnpm"}],"config":{"dir":"apps/web","cmd":null}}` |
| `bootstrap [--dry-run]` | `{"linked":true,"env_copied":["apps/web/.env"],"deps":"symlink"}` — `deps` ∈ `symlink`\|`install`\|`present` |
| `start --dir <rel> [--cmd <c>] [--open]` | вміст `session.json`, або `{"already":true,...}`, або `{"error":"...","log":"..."}` |
| `stop` | `{"stopped":true,"pgid":123}` \| `{"stopped":false,"reason":"no session"}` |
| `status` | `{"active":true,...}` \| `{"active":false}` |
| `session-start` | `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"…"}}`, або **порожньо** при неактивній сесії |
| `config-set --dir <rel> [--cmd <c>]` | новий вміст `config.json` |

Ненульовий код виходу — тільки `start`, коли сервер не піднявся.

### Текст правил live-режиму

`session-start` і скіл `live` друкують **дослівно** цей блок, підставляючи
`<url>`, `<dir>`, `<log>`:

```
LIVE CODING SESSION ACTIVE — <url>, застосунок <dir>, лог <log>.
Поки сесія активна:
- penny не будує прототип. Ні теки docs/sdd/proto/, ні proto-сервера, ні
  decision.md. Варіанти стають послідовними ітераціями по реальному коду:
  внести зміну -> сказати, куди дивитись -> чекати вердикт користувача.
- Backend-розрив не реалізується. Опис іде рядком у docs/live/deferred.md
  (що потрібно, чому не зроблено зараз, який фронтенд на це чекає), робота
  лишається фронтендною.
- sheldon, leonard, wolowitz, amy працюють без змін. Явний запит на повний
  SDD-цикл виконується як завжди.
```

## Waves

| Wave | Tasks | Why together |
|---|---|---|
| 1 | 1, 2, 3, 4, 5 | write-сети не перетинаються: `.claude-plugin/` vs `bin/`+`test.sh` vs `skills/live/`+`commands/live*` vs `skills/do-it/`+`commands/do-it.md` vs `hooks/` |
| 2 | 6 | `README.md` документує все вище і запускає повний `test.sh` |

Задачі 3–5 споживають контракт `bin/live.sh`, який задача 2 реалізує. Вони не
серіалізуються за ним, бо контракт зафіксовано дослівно в Global constraints —
жодна з них не читає код задачі 2.

Нічого серіалізувати не довелося, крім задачі 6: вона єдина, що читає результат
усіх інших.

## Виконання

Хвилі описані так, як їх читає `wolowitz`, але виконувати я планую **сам,
послідовно**, без субагентів: обсяг — один bash-скрипт і шість дрібних файлів,
на такому паралелізм коштує більше, ніж економить. Якщо хочете саме `wolowitz`
із паралельними агентами — скажіть при затвердженні, декомпозиція для нього вже
готова.

---

### Task 1: маніфести плагіна

**Writes:** `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.gitignore`, `LICENSE`
**Reads:** —
**Depends on:** —
**Interfaces:**
- Produces: `plugin.json` із `"hooks": "./hooks/hooks.json"` — шлях, який задача 5 матеріалізує.

- [ ] **Крок 1: `.claude-plugin/plugin.json`**

```json
{
  "name": "live-coding",
  "description": "Live frontend coding sessions: one command brings the dev server up with worktree bootstrap, edits land straight in the running app, and the session tears it down on exit",
  "version": "0.1.0",
  "hooks": "./hooks/hooks.json",
  "author": { "name": "dmytro-rudenko", "email": "ph.dmitry.rudenko@gmail.com" },
  "license": "MIT",
  "keywords": ["claude-code", "frontend", "dev-server", "hot-reload", "worktree", "hooks", "live-coding"]
}
```

- [ ] **Крок 2: `.claude-plugin/marketplace.json`** — `name: live-coding`, той самий
      owner, масив `plugins` з одним записом: `name: live-coding`, `source: "./"`,
      `version: "0.1.0"`, `license: "MIT"`, `category: "Development"`, той самий
      `description` і `keywords`.
- [ ] **Крок 3: `.gitignore`** — рівно два рядки: `.live/` та `node_modules/`.
- [ ] **Крок 4: `LICENSE`** — MIT, `Copyright (c) 2026 Dmytro Rudenko`.
- [ ] **Крок 5: перевірка** — `node -e 'require("./.claude-plugin/plugin.json");require("./.claude-plugin/marketplace.json");console.log("ok")'`, очікується `ok`.

---

### Task 2: `bin/live.sh` і `test.sh`

**Writes:** `bin/live.sh`, `test.sh`
**Reads:** `docs/sdd/specs/2026-08-27-live-coding-plugin.md`
**Depends on:** —
**Interfaces:**
- Produces: усі підкоманди з таблиці контракту в Global constraints.

Порядок кроків — за `amy`: тест, падіння, мінімум, проходження. `test.sh`
пишеться один раз повністю (крок 1), далі скрипт нарощується до нього.

- [ ] **Крок 1: написати `test.sh`** — хелпери `ok`/`fail`/`assert_contains`
      (як у `pasadena/hooks/journal.test.sh`), `setup_repo()` створює тимчасовий
      репозиторій із коммітом, і такі перевірки:
   1. `detect` у репо з `pnpm-lock.yaml` і `apps/web/package.json` (`scripts.dev`)
      → вивід містить `"dir":"apps/web"`, `"script":"dev"`, `"pm":"pnpm"`.
   2. `detect` у репо з `package-lock.json` → `"pm":"npm"`.
   3. `detect` у репо без жодного dev-скрипта → `"candidates":[]`.
   4. `config-set --dir apps/web` → наступний `detect` містить
      `"config":{"dir":"apps/web"`.
   5. `status` без сесії → `{"active":false}`.
   6. `stop` без сесії → `"stopped":false`, код виходу 0.
   7. `session-start` без сесії → вивід порожній.
   8. `bootstrap --dry-run` у **головному** worktree → `"linked":false`.
   9. `bootstrap --dry-run` у linked worktree (`git worktree add`) без `.env` і
      без `node_modules`, lock-файли однакові → `"env_copied":["`.env`"]` і
      `"deps":"symlink"`.
   10. те саме, але lock-файл у worktree змінено → `"deps":"install"`.
   11. **end-to-end без фреймворку:** `start --dir . --cmd 'printf "  Local:
       http://localhost:4321/\n"; sleep 30'` → вивід містить
       `"url":"http://localhost:4321"` і `"port":4321`; далі `status` →
       `"active":true`; далі `session-start` → вивід містить
       `LIVE CODING SESSION ACTIVE`; далі `stop` → `"stopped":true`, і
       `kill -0 -- -<pgid>` більше не проходить.
   12. `start` при живій сесії → `"already":true`, другого процесу немає.
   13. фронтматер скілів: для кожного `skills/*/SKILL.md` перший рядок `---`,
       є закривний `---`, `name:` збігається з іменем теки, є `description:`.
       Порожня тека `skills/` проходить перевірку вакуумно.
- [ ] **Крок 2: подивитись, як воно падає** — `bash test.sh`, очікується
      `FAILED:` із ненульовим числом (скрипта ще немає).
- [ ] **Крок 3: реалізувати `bin/live.sh`.** Ключові місця, які треба зробити
      саме так:

  **Шляхи і читання стану.** Хелпери `state_paths()` (виставляє `GIT_COMMON`,
  `GIT_DIR`, `CONFIG`, `SESSION`, `LOG`, `ROOT` за схемою з Global constraints)
  і `jget <file> <key>`:

  ```bash
  jget() { sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",}]*\)\"\{0,1\}.*/\1/p" "$1" | head -1; }
  ```

  **Живість сесії.** `session_alive()` — файл існує **і** `kill -0 -- -"$pgid"`
  успішний; інакше `rm -f "$SESSION"` і повернути 1.

  **Package manager** — по lock-файлу в `$ROOT`: `pnpm-lock.yaml`→`pnpm`,
  `yarn.lock`→`yarn`, `bun.lock`/`bun.lockb`→`bun`,
  `package-lock.json`→`npm`; інакше поле `packageManager` кореневого
  `package.json` (до першого `@`); інакше `npm`.

  **`detect`** — обхід через `node -e`: рекурсія від `$ROOT` на глибину ≤3,
  пропуск `node_modules`, `.git`, `dist`, `build`, `.next`, `coverage`; у
  кожному `package.json` перший наявний зі `scripts`: `dev`, `start:dev`,
  `serve` — саме в цьому порядку; вивід — JSON-масив `{dir,script}`, `dir`
  відносний, для кореня `"."`. `pm` дописує bash.

  **`bootstrap [--dry-run]`** — виходить одразу з `"linked":false`, якщо
  `GIT_DIR = GIT_COMMON`. Головний worktree — перший `worktree ` у
  `git worktree list --porcelain`. Далі:
   - `.env*` — `find "$MAIN" -maxdepth 3 -name '.env*' -not -path '*/node_modules/*'`,
     копія у відповідний відносний шлях, наявні файли не чіпаються;
   - `node_modules` у корені є → `"deps":"present"`;
   - інакше `cmp -s "$MAIN/<lock>" "$ROOT/<lock>"` успішний **і**
     `$MAIN/node_modules` існує → `ln -s` на кореневий `node_modules` і на
     кожен `<pkg>/node_modules`, що існує в `$MAIN` → `"deps":"symlink"`;
   - інакше `<pm> install` → `"deps":"install"`.
   При `--dry-run` рішення обчислюються і друкуються, але нічого не
   виконується.

  **`start`** — при живій сесії друкує стан із `"already":true` і виходить 0.
  Інакше `bootstrap`, потім запуск із теки застосунку:

  ```bash
  cd "$APPDIR" || exit 1
  : >"$LOG"
  setsid nohup bash -c "$CMD" >"$LOG" 2>&1 &
  pgid=$!          # setsid робить процес лідером групи, тож pgid == pid
  ```

  Далі до 30 с (`for _ in $(seq 1 300)`, `sleep 0.1`):
   - URL: `grep -om1 -E 'https?://(localhost|127\.0\.0\.1|\[::1\]):[0-9]+' "$LOG"`.
     Лог, а не дефолт фреймворку, бо при зайнятому порту vite мовчки бере інший
     і тільки лог про це знає;
   - сигнатура зламаних symlink'ів:
     `grep -qE 'Cannot find (module|package)|command not found' "$LOG"` — якщо
     `$ROOT/node_modules` є symlink'ом, зняти всі створені symlink'и, виконати
     `<pm> install` і зробити **рівно один** перезапуск (прапорець
     `retried=1`); удруге — помилка зі шляхом до лога;
   - процес помер (`kill -0 -- -$pgid` не проходить) → помилка зі шляхом до лога.

  Фолбек після 30 с без URL: `ss -ltnp 2>/dev/null | grep "pid=$pgid"` → порт.
  Потім `printf` у `$SESSION`, і за `--open` — `xdg-open`, з фолбеком на
  `open`, потім `start` (як у `pasadena/proto/start.sh`).

  **`stop`** — `kill -- -"$pgid"`, до 5 с очікування, потім `kill -9 -- -"$pgid"`,
  `rm -f "$SESSION"`. Group-kill обов'язковий: `pnpm run dev` — обгортка, і
  вбивство самого pnpm лишає vite живою сиротою на порту.

  **`session-start`** — мовчить при неактивній сесії; інакше друкує
  `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"…"}}`,
  де контекст — дайджест плюс дослівний блок правил із Global constraints.
  Екранування — хелпер `json_escape()`: `\` → `\\`, `"` → `\"`, переводи рядка → `\n`.

- [ ] **Крок 4: перевірити** — `bash test.sh`, очікується `All checks passed.`

---

### Task 3: скіл `live` і його команди

**Writes:** `skills/live/SKILL.md`, `commands/live.md`, `commands/live-stop.md`
**Reads:** `docs/sdd/specs/2026-08-27-live-coding-plugin.md`
**Depends on:** —
**Interfaces:**
- Consumes: `detect`, `config-set`, `start`, `status`, `stop` — контракт у Global constraints.

- [ ] **Крок 1: `skills/live/SKILL.md`.** Фронтматер: `name: live`,
      `description: Use when the user asks to start a live coding session, bring
      the frontend up in dev mode, run the app locally with hot reload, or check
      a running live session. Detects the dev command, bootstraps a worktree,
      starts the server and opens the browser`.
      `allowed-tools`: `Read`, `Grep`, `Glob`, `AskUserQuestion`, `TodoWrite`,
      `Bash(bash ${CLAUDE_PLUGIN_ROOT}/bin/live.sh *)`, `Bash(git worktree *)`,
      `Bash(ls *)`. `disallowed-tools`: `Agent`, `NotebookEdit`.

      Тіло:
   - активна сесія → `status`, надрукувати URL/теку/лог і зупинитись;
   - інакше `detect`; один кандидат — старт мовчки; кілька — одне
     `AskUserQuestion` зі списком тек, потім `config-set --dir`; жодного —
     одне відкрите питання «якою командою підняти застосунок?», відповідь у
     `config-set --cmd`. Саме це і є підтримка не-Node стеків: `python manage.py
     runserver`, `bin/rails s`, `make dev` працюють без окремого коду;
   - `start --dir <dir> --open`; при помилці — показати останні 20 рядків лога
     і зупинитись, не намагаючись лагодити чужий проєкт;
   - надрукувати URL, теку, шлях до лога і **дослівно** блок правил
     live-режиму з Global constraints;
   - `bootstrap` виконується без підтвердження — тека worktree без залежностей
     усе одно непрацездатна.
- [ ] **Крок 2: `commands/live.md`** — фронтматер
      `description: Підняти dev-інстанс фронтенду і почати live coding сесію`,
      `argument-hint: [тека застосунку]`; тіло: `Use the \`live\` skill. $ARGUMENTS`.
- [ ] **Крок 3: `commands/live-stop.md`** — `description: Зупинити dev-сервер
      поточної live-сесії`; тіло: одна інструкція виконати
      `bash "${CLAUDE_PLUGIN_ROOT}/bin/live.sh" stop` і надрукувати результат.
      Без скіла — там нема чого вирішувати.
- [ ] **Крок 4: перевірити** — `bash test.sh` (перевірка фронтматера, п.13),
      очікується `All checks passed.`

---

### Task 4: скіл `do-it` і його команда

**Writes:** `skills/do-it/SKILL.md`, `commands/do-it.md`
**Reads:** `docs/sdd/specs/2026-08-27-live-coding-plugin.md`
**Depends on:** —
**Interfaces:**
- Produces: формат `docs/live/deferred.md`, який споживають правила live-режиму.

- [ ] **Крок 1: `skills/do-it/SKILL.md`.** Фронтматер: `name: do-it`,
      `description: Use when the user hands over a list of small fixes to apply
      right now, says "just do it", or is watching the result in a browser with
      hot reload. Applies each item and reports one line per item, without tests,
      browser checks or commits`.
      `allowed-tools`: `Read`, `Grep`, `Glob`, `Edit`, `Write`, `TodoWrite`,
      `AskUserQuestion`, `Bash(ls *)`, `Bash(rg *)`.
      `disallowed-tools`: `Agent`, `NotebookEdit`.

      Тіло — жорсткі межі:
   - розібрати вхід на пункти, `TodoWrite` на список, застосувати кожен;
   - **не запускати** тести, Playwright, typecheck, лінтер; **не комітити**;
   - один рядок звіту на пункт: `<файл>:<рядок> — <що змінено>`;
   - неоднозначний пункт — **не вгадувати**: відкласти, доробити решту, і аж
     наприкінці поставити одне `AskUserQuestion`, що покриває всі відкладені
     пункти разом;
   - пункт вимагає backend — дописати в кінець `docs/live/deferred.md` і
     згадати у звіті. Формат запису:

     ```markdown
     ## 2026-08-27 — фільтр за статусом у списку замовлень
     **Потрібно:** `GET /api/orders` має приймати `?status=`.
     **Чому не зараз:** live-сесія фронтендна, ендпоінт фільтра не має.
     **Хто чекає:** `apps/web/src/pages/Orders.tsx` — селект уже є, фільтрує
     локально завантажену сторінку замість усього набору.
     ```

     Файл створюється при першому записі із заголовком
     `# Відкладено з live-сесій`. Перетворення його на специфікацію — окрема
     робота через `/bazinga`, і вона поза межами цього скіла;
   - скіл працює і поза live-сесією.
- [ ] **Крок 2: `commands/do-it.md`** — `description: Застосувати список правок
      без тестів і перевірок`, `argument-hint: [список правок]`; тіло:
      `Use the \`do-it\` skill. $ARGUMENTS`.
- [ ] **Крок 3: перевірити** — `bash test.sh`, очікується `All checks passed.`

---

### Task 5: хуки

**Writes:** `hooks/hooks.json`
**Reads:** —
**Depends on:** —
**Interfaces:**
- Consumes: `live.sh session-start` і `live.sh stop` — контракт у Global constraints.

- [ ] **Крок 1: `hooks/hooks.json`**

```json
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|resume|clear|compact",
        "hooks": [ { "type": "command",
          "command": "bash \"${CLAUDE_PLUGIN_ROOT}/bin/live.sh\" session-start",
          "shell": "bash", "timeout": 5 } ] }
    ],
    "SessionEnd": [
      { "matcher": "logout|prompt_input_exit|other",
        "hooks": [ { "type": "command",
          "command": "bash \"${CLAUDE_PLUGIN_ROOT}/bin/live.sh\" stop",
          "shell": "bash", "timeout": 10 } ] }
    ]
  }
}
```

  `clear` свідомо відсутній у `SessionEnd`: очищення контексту не є завершенням
  роботи, вкладка в браузері лишається відкритою, а `SessionStart` із тим самим
  `clear` одразу повертає правила режиму в контекст.

- [ ] **Крок 2: перевірити** — `node -e 'require("./hooks/hooks.json");console.log("ok")'`, очікується `ok`.

---

### Task 6: README

**Writes:** `README.md`
**Reads:** усі файли, створені задачами 1–5
**Depends on:** Tasks 1, 2, 3, 4, 5
**Interfaces:** —

- [ ] **Крок 1: `README.md`** — встановлення
      (`/plugin marketplace add dmytro-rudenko/live-coding`, далі
      `/plugin install live-coding`), таблиця трьох команд, розділ «Що робить
      `/live`» (детект → bootstrap → старт → порт із лога → браузер), розділ
      «Стан» із таблицею двох шляхів, і — обов'язково — розділ **«Перевизначення
      pasadena»** з дослівним блоком правил. Це компенсація за те, що в
      `penny/SKILL.md` про live-режим не написано нічого.
- [ ] **Крок 2: перевірити** — `bash test.sh`, очікується `All checks passed.`

---

## Ручна перевірка після хвилі 2

Автотести не покривають реальний фреймворк і реальний браузер. Після зеленого
`test.sh` — на справжньому фронтенд-репозиторії:

1. `/plugin marketplace add /home/pc/projects/live-coding`, `/plugin install live-coding`.
2. `/live` → vite піднявся, вкладка відкрилась, порт у виводі збігається з `ss -ltnp`.
3. Зайняти дефолтний порт стороннім процесом, `/live` → у виводі порт, який vite
   обрав насправді.
4. `git worktree add` без `.env` і `node_modules`, `/live` → `.env` на місці,
   `node_modules` — symlink, сервер живий.
5. `/clear` → dev-сервер живий, блок правил знову в контексті.
6. Вихід із Claude Code → `pgrep -f vite` порожньо, `session.json` видалено.
