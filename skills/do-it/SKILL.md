---
name: do-it
description: Use when the user hands over a list of small fixes to apply right now, says "just do it", or is watching the result in a browser with hot reload. Applies each item and reports one line per item, without tests, browser checks or commits
allowed-tools:
  - Read
  - Grep
  - Glob
  - Edit
  - Write
  - TodoWrite
  - AskUserQuestion
  - Bash(ls *)
  - Bash(rg *)
disallowed-tools:
  - Agent
  - NotebookEdit
---

# Do it

The user is looking at the running app. They named what is wrong. Change it and
get out of the way — hot reload is the feedback loop, and every second spent
verifying is a second they spend staring at an unchanged screen.

## Do not

- **No tests.** Not the suite, not one file, not a new one.
- **No browser.** No Playwright, no Chrome MCP, no screenshots.
- **No typecheck, no lint, no build.**
- **No commits.**

These are not deferred to the end of the list. They do not happen.

## The loop

Split the input into items and put them in `TodoWrite` — the list is what the
user watches while the edits land. Then, per item: find the code, change it,
report one line.

    src/components/Toolbar.tsx:42 — кнопку "Export" прибрано
    src/pages/Orders.tsx:118 — селект статусу тепер контрольований

The line names the file and the line so the user can jump there. It does not
explain the reasoning.

Read enough to change the right thing. A one-line report is not a licence to
guess which file: grep for the string the user quoted, follow the shared
component to its callers, fix it where all of them route through. The speed
comes from skipping verification, not from skipping comprehension.

## Two ways an item does not get done

**It is ambiguous.** Do not guess. Set it aside, finish everything else, and
only at the very end ask **one** `AskUserQuestion` that covers every set-aside
item together. One question at the end costs the user one interruption; one
question per item costs them the session.

**It needs backend work.** Append it to `docs/live/deferred.md` and say so in
the report. Do not build the endpoint, do not stub it, do not mock it.

    # Відкладено з live-сесій

    ## 2026-08-27 — фільтр за статусом у списку замовлень
    **Потрібно:** `GET /api/orders` має приймати `?status=`.
    **Чому не зараз:** live-сесія фронтендна, ендпоінт фільтра не має.
    **Хто чекає:** `apps/web/src/pages/Orders.tsx` — селект уже є, фільтрує
    локально завантажену сторінку замість усього набору.

Create the file with that heading on the first write; append after that.
Turning the file into a specification is separate work through `/bazinga`, and
it is outside this skill.

## Outside a live session

The skill works the same. There is simply nobody watching a browser, so say in
one line what the user should look at.
