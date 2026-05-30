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
| dashboard | terminal-native home, stats, XP, streak, activity strip |
| backend | AnkiConnect over localhost |
| command | `:AnkiReview`, `:AnkiReview!`, `:AnkiReviewHome`, `:AnkiReviewStats` |
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
  cmd = { "AnkiReview", "AnkiReviewHome", "AnkiReviewStats" },
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
    enabled = true,
    xp = {
      again = 3,
      hard = 6,
      good = 10,
      easy = 12,
    },
    streak = {
      enabled = true,
    },
  },
  dashboard = {
    enabled = true,
    activity_days = 7,
    width = 0.75,
    height = 0.75,
  },
})
```

Disable local gamification:

```lua
require("anki_review").setup({
  gamification = {
    enabled = false,
  },
})
```

state files:

```text
stdpath("state")/anki_review/state.json
stdpath("state")/anki_review/gamification.json
```

User progress is stored under `stdpath("state")`, not the plugin install directory.

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
AnkiReviewXPBar
AnkiReviewXPBarEmpty
AnkiReviewStreak
AnkiReviewActivityEmpty
AnkiReviewActivityLow
AnkiReviewActivityMedium
AnkiReviewActivityHigh
AnkiReviewActivityMax
AnkiReviewGamificationPopup
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

opens the cave dashboard: last deck, Anki status, today's reviews, XP, streak, and a tiny activity strip.

```vim
:AnkiReviewStats
```

opens the dashboard directly in stats view.

---

## dashboard

`:AnkiReviewHome` is a Neovim-native dashboard made from text, Unicode, floating windows, and highlight groups.

It shows:

- level and XP progress
- current and best streak
- today's cards, answer mix, review time, and XP
- last deck
- AnkiConnect status
- due summary when known
- 7-day local activity strip
- actions for picker, last deck, stats, refresh, help, quit

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

`anki.nvim` keeps lightweight local progress stats in Neovim's state directory:

```text
stdpath("state")/anki_review/gamification.json
```

Anki still owns scheduling. The plugin only tracks local XP, streaks, and dashboard stats for motivation.

XP defaults:

| answer | XP |
|---|---:|
| Again | 3 |
| Hard | 6 |
| Good | 10 |
| Easy | 12 |

Reveal answer alone gives `0` XP. XP is recorded only after `guiAnswerCard` succeeds through AnkiConnect.

Level formula:

```text
level = floor(sqrt(total_xp / 100)) + 1
```

Streaks count local days where at least one card was answered. Multiple cards on the same day do not increment the streak multiple times.

This data is not stored in the plugin install directory, so plugin updates should not wipe your progress.

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

**track** - stores local XP, streaks, answer totals, and daily activity under `stdpath("state")`.

**respect** - only shows answer choices available for the current card.

**finish** - detects empty decks / completed reviews and shows session XP/streak summary.

---

## external add-ons

`anki.nvim` answers cards through AnkiConnect, so reviews are still recorded by Anki itself. Stats/history add-ons may see those normal Anki reviews.

Visual add-ons that modify Anki's reviewer UI, card webview, buttons, colors, or keyboard shortcuts are not rendered inside the Neovim floating window.

`anki.nvim` does not automatically import gamification data from Anki add-ons. Future versions may add a manual importer, but the plugin does not read or write third-party add-on state.

No gamification data is written to Anki add-on directories, the Anki collection/database, or the Anki media folder.

---

## manual checks

- `:AnkiReview` opens picker.
- `:AnkiReview SomeDeck` starts review.
- `:AnkiReview!` starts last deck or warns if none saved.
- `:AnkiReviewHome` opens without Anki running.
- `:AnkiReviewStats` opens stats view.
- dashboard does not freeze when Anki is closed.
- dashboard `l`, `p`/`r`, `s`, `q` work.
- review float survives terminal resize.
- answering increments local XP after successful AnkiConnect answer.
- reveal alone gives no XP.
- completion screen shows XP gained and streak.
- corrupt or missing gamification state file does not crash.
- `gamification.enabled = false` disables recording.
- no gamification data appears in the plugin install directory.
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
