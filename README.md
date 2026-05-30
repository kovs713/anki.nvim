# anki.nvim 🃏

flashcards without leaving the cave.  
tiny Neovim bridge for reviewing anki decks in a clean floating window.

---

< gif demo soon >

---

## what's inside

| | |
|---|---|
| ui | centered floating review window |
| backend | AnkiConnect over localhost |
| command | `:AnkiReview`, `:AnkiReview!`, `:AnkiReviewHome` |
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
  cmd = { "AnkiReview", "AnkiReviewHome" },
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

anki must be open. AnkiConnect must listen on `http://127.0.0.1:8765`.

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
})
```

last deck is stored at `stdpath("state")/anki_review/state.json`.

highlight groups:

```text
AnkiReviewTitle
AnkiReviewSection
AnkiReviewProgress
AnkiReviewHint
AnkiReviewError
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
:AnkiReviewHome
```

opens the small cave menu: pick deck, review last deck, health notes, help.

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

---

## what it does

**review** — opens Anki's current review flow from inside Neovim.

**read** — strips noisy card HTML into plain text that does not fight your buffer.

**answer** — sends real Anki ease buttons through AnkiConnect, no fake local state.

**respect** — only shows answer choices available for the current card.

**finish** — detects empty decks / completed reviews and gets out of the way.

---

## integrations

### Review Heatmap

`anki.nvim` answers cards through AnkiConnect, so reviews are still recorded by
Anki itself. Stats/history add-ons like Review Heatmap should pick them up as
normal Anki reviews.

Visual add-ons that modify Anki's reviewer UI, card webview, buttons, colors,
or keyboard shortcuts are not rendered inside the Neovim floating window.

If local TSV/offline mode exists later, it will not be compatible with Anki
add-ons unless it syncs review data back to Anki.

---

## manual checks

- `:AnkiReview` opens picker.
- `:AnkiReview SomeDeck` starts review.
- `:AnkiReview!` starts last deck or warns if none saved.
- `:AnkiReviewHome` opens without Anki running.
- review float survives terminal resize.
- closing review clears timer and resize autocmd.
- tiny terminal does not crash.
- bad or missing state file does not crash.
- offline AnkiConnect shows a friendly error.

---

## why

yes, anki still has to be open.  
no, you do not have to look at it.

anki handles the scheduler.  
Neovim handles the cave.  
you handle the queue.

---

> terminal gremlin certified 
