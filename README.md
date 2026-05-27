# anki.nvim 🃏

Flashcards without leaving the cave.  
Tiny Neovim bridge for reviewing Anki decks in a clean floating window.

---

< gif demo soon >

---

## what's inside

| | |
|---|---|
| UI | centered floating review window |
| Backend | AnkiConnect over localhost |
| Command | `:AnkiReview` |
| Decks | picker when no deck is passed |
| Answers | `1` Again · `2` Hard · `3` Good · `4` Easy |
| Default | `<CR>` answers Good |
| Timer | per-card session clock |

---

## setup

### lazy.nvim

```lua
{
  "kovs713/anki.nvim",
  cmd = "AnkiReview",
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

Install AnkiConnect from AnkiWeb: `2055492159`.

Anki must be open. AnkiConnect must listen on `http://127.0.0.1:8765`.

---

## usage

```vim
:AnkiReview
```

opens a deck picker.

```vim
:AnkiReview Japanese::Core
```

starts that deck directly.

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

## why

Because context switching is where reviews go to die.  
Run `:AnkiReview`, clear the queue, return to code.

---

> study gremlin approved
