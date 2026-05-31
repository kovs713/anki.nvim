# anki.nvim 🃏

flashcards without leaving the cave.

tiny Neovim bridge for reviewing Anki decks in a clean floating window.

---

< gif demo soon >

---

## what's inside

| | |
|---|---|
| ui | centered floating review window |
| dashboard | terminal-native home, Anki stats, read-only Onigiri gamification |
| backend | AnkiConnect over localhost |
| command | `:AnkiReview`, `:AnkiReview!`, `:AnkiReviewHome`, `:AnkiReviewStats`, `:AnkiReviewOnigiriPath` |
| decks | picker when no deck is passed |
| answers | `1` Again · `2` Hard · `3` Good · `4` Easy |
| default | `<CR>` answers Good |
| timer | per-card session clock |

---

## setup

### lazy.nvim

```lua
{
  "kovs713/anki.nvim",
  cmd = { "AnkiReview", "AnkiReviewHome", "AnkiReviewStats", "AnkiReviewOnigiriPath" },
  config = function()
    require("anki_review").setup()
  end,
}
```

### vim.pack

```lua
vim.pack.add({
  "https://github.com/kovs713/anki.nvim",
})
```

### requirements

```text
neovim 0.10+, curl, Anki, AnkiConnect
```

install AnkiConnect from AnkiWeb: `2055492159`.

Anki must be open for reviewing. AnkiConnect must listen on `http://127.0.0.1:8765`.

### config

```lua
require("anki_review").setup({
  anki = {
    endpoint = "http://127.0.0.1:8765",
    version = 6,
    timeout = 5000,
  },
  window = {
    width = 0.7,
    height = 0.7,
    min_width = 40,
    min_height = 12,
    border = "rounded",
  },
  picker = {
    width = 0.5,
    height = 0.6,
  },
  behavior = {
    remember_last_deck = true,
    default_ease = 3,
  },
  gamification = {
    provider = "onigiri", -- "onigiri" | "none"
  },
  onigiri = {
    gamification_path = nil,
    readonly = true,
  },
  dashboard = {
    enabled = true,
    width = 0.75,
    height = 0.75,
  },
})
```

Disable gamification display:

```lua
require("anki_review").setup({
  gamification = {
    provider = "none",
  },
})
```

Set Onigiri path in config:

```lua
require("anki_review").setup({
  onigiri = {
    gamification_path = "/path/to/gamification_User 1.json",
  },
})
```

Or save only the path from Neovim:

```vim
:AnkiReviewOnigiriPath /path/to/gamification_User 1.json
```

state files:

```text
stdpath("state")/anki_review/state.json
```

`state.json` stores plugin-owned state only: last deck and cached Onigiri gamification JSON path.

highlight groups:

```text
AnkiReviewTitle
AnkiReviewSection
AnkiReviewProgress
AnkiReviewHint
AnkiReviewError
AnkiReviewDashboardTitle
AnkiReviewDashboardSubtitle
AnkiReviewDashboardBorder
AnkiReviewWidgetTitle
AnkiReviewWidgetValue
```

---

## usage

```vim
:AnkiReview
```

opens a deck picker.

```vim
:AnkiReview <anki deck name>
```

starts that deck directly.

```vim
:AnkiReview!
```

starts the last saved deck.

```vim
:AnkiReview home
:AnkiReview stats
:AnkiReview last
:AnkiReview deck <anki deck name>
```

single-command aliases. Use `deck` when a deck name collides with a built-in alias.

```vim
:AnkiReviewHome
```

opens the cave dashboard: last deck, Anki status, due counts, review counts, and read-only Onigiri gamification data.

```vim
:AnkiReviewStats
```

opens the dashboard directly in stats view.

---

## dashboard

`:AnkiReviewHome` is a Neovim-native dashboard made from text, Unicode, floating windows, and highlight groups.

Two views:

**Dashboard view** — compact overview with two sections:

- **Onigiri** — level, XP, coins, theme, achievements, daily specials, and last updated from Onigiri JSON.
- **Anki collection** — AnkiConnect status, last deck, due summary (New/Learn/Review), future due counts.

**Stats view** — detailed Onigiri gamification data and Anki collection data (status, due, future, review history).

Future due uses Anki search `findCards` when refreshed via `R`. Full Anki review history chart is not implemented yet.

Dashboard keys:

| key | action |
|---|---|
| `r` / `p` | open deck picker |
| `l` | review last deck |
| `s` | stats view |
| `h` / `<BS>` | return from stats |
| `?` | toggle help |
| `R` | refresh status |
| `q` / `<Esc>` | close |

Opening the dashboard does not require Anki to be running. Status starts as `unknown`; press `R` for a short status check.

---

## gamification

`anki.nvim` does not invent XP, levels, streaks, achievements, or restaurant stats.

It can display existing Onigiri Anki add-on gamification data in read-only mode. Onigiri remains the source of truth.

Configure the Onigiri JSON path. Current Onigiri profile files are usually under the add-on `user_files` directory:

```text
user_files/gamification_<profile_name>.json
user_files/gamification.json
```

Profile names can contain spaces, for example `gamification_User 1.json`.

`anki.nvim` only reads this file. It does not copy, modify, normalize, repair, or write Onigiri data. It does not ship Onigiri code, assets, images, icons, CSS, or UI.

Answering cards through `anki.nvim` sends normal AnkiConnect review actions. It does not create local XP/streak state and does not claim XP gained.

---

## keys

| key | action |
|---|---|
| `<Space>` | reveal answer |
| `<CR>` | answer Good / next card |
| `1` | Again |
| `2` | Hard |
| `3` | Good |
| `4` | Easy |
| `q` | quit |

Completion keys:

| key | action |
|---|---|
| `q` | close |
| `r` | review same deck again |
| `h` | dashboard |

---

## what it does

**review** - opens Anki's current review flow from inside Neovim.

**read** - strips noisy card HTML into plain text that does not fight your buffer.

**answer** - sends real Anki ease buttons through AnkiConnect, no fake scheduler.

**show** - displays configured Onigiri gamification JSON read-only.

**respect** - only shows answer choices available for the current card.

**finish** - detects empty decks / completed reviews and shows session answer summary plus current Onigiri values when available.

---

## external add-ons

`anki.nvim` answers cards through AnkiConnect, so reviews are still recorded by Anki itself. Stats/history add-ons may see those normal Anki reviews.

Anki, Onigiri, Review Heatmap, or other tools may show data that `anki.nvim` only reads or does not render.

Visual add-ons that modify Anki's reviewer UI, card webview, buttons, colors, or keyboard shortcuts are not rendered inside the Neovim floating window.

`anki.nvim` can display Onigiri gamification data from a configured JSON path. It does not auto-discover, import, copy, or migrate Onigiri data into local plugin state.

No gamification data is written to Anki add-on directories, the Anki collection/database, or the Anki media folder.

---

## manual checks

- `:AnkiReview` opens picker.
- `:AnkiReview SomeDeck` starts review.
- `:AnkiReview!` starts last deck or warns if none saved.
- `:AnkiReviewHome` opens without Anki running.
- `:AnkiReviewStats` opens stats view.
- `:AnkiReviewHome` with no Onigiri path shows path missing.
- `:AnkiReviewOnigiriPath /path/to/gamification_User 1.json` saves only the path.
- configured Onigiri JSON shows level, XP, coins, achievements, and daily specials.
- dashboard does not freeze when Anki is closed.
- dashboard `l`, `p`/`r`, `s`, `q` work.
- review float survives terminal resize.
- answering cards does not create local XP/streak state.
- completion screen shows session stats and Onigiri current values or unavailable.
- corrupt or missing Onigiri JSON does not crash.
- `gamification.provider = "none"` disables gamification display.
- no Onigiri data appears in the plugin install directory.
- offline AnkiConnect shows a friendly error.

---

## why

yes, Anki still has to be open.

no, you do not have to look at it.

Anki handles the scheduler.

Neovim handles the cave.

you handle the queue.

---

> terminal gremlin certified
