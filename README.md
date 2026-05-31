# anki.nvim

flashcards without leaving Neovim.

AnkiConnect bridge for reviewing Anki decks in a floating window, with optional read-only Onigiri dashboard.

## features

| area | detail |
|---|---|
| review | `:AnkiReview` deck picker or direct deck start |
| scheduler | real Anki reviews through AnkiConnect |
| ui | centered review float, plain-text card rendering |
| dashboard | read-only Onigiri companion panel |
| state | last deck + Onigiri JSON path only |

## install

```lua
{
  "kovs713/anki.nvim",
  cmd = { "AnkiReview", "AnkiReviewHome", "AnkiReviewStats", "AnkiReviewOnigiriPath" },
  config = function()
    require("anki_review").setup()
  end,
}
```

```lua
vim.pack.add({
  "https://github.com/kovs713/anki.nvim",
})
```

requires Neovim 0.10+, `curl`, Anki, and AnkiConnect (`2055492159`).

Anki must be open for reviews. AnkiConnect must listen on `http://127.0.0.1:8765`.

## config

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

optional Onigiri setup:

```vim
:AnkiReviewFindOnigiri
:AnkiReviewOnigiriPath /path/to/gamification_User 1.json
```

disable gamification display:

```lua
require("anki_review").setup({
  gamification = { provider = "none" },
})
```

## commands

| command | action |
|---|---|
| `:AnkiReview` | open deck picker |
| `:AnkiReview <deck>` | review deck |
| `:AnkiReview!` | review last deck |
| `:AnkiReview home` | open dashboard |
| `:AnkiReview stats` | open dashboard stats |
| `:AnkiReview deck <deck>` | force deck name |
| `:AnkiReviewHome` | open dashboard |
| `:AnkiReviewStats` | open stats view |
| `:AnkiReviewFindOnigiri` | show candidate Onigiri JSON files |
| `:AnkiReviewOnigiriPath <path>` | save Onigiri JSON path |

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

dashboard keys: `s` stats, `h`/`<BS>` back, `R` refresh, `q`/`<Esc>` close.

completion keys: `r` review same deck, `h` dashboard, `q` close.

## state

Plugin state lives at:

```text
stdpath("state")/anki_review/state.json
```

it stores plugin-owned state only: last deck and cached Onigiri gamification JSON path.

## docs

- [Onigiri and external add-ons](docs/onigiri.md)
- [manual checks](docs/manual-checks.md)

## why

yes, Anki still has to be open.

no, you do not have to look at it.

Anki handles the scheduler.

Neovim handles the cave.

you handle the queue.

---

> terminal gremlin certified
