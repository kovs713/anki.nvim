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
| command | `:AnkiReview` |
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

install AnkiConnect from AnkiWeb: `2055492159`.

anki must be open. AnkiConnect must listen on `http://127.0.0.1:8765`.

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

yes, anki still has to be open.  
no, you do not have to look at it.

anki handles the scheduler.  
Neovim handles the cave.  
you handle the queue.

---

> terminal gremlin certified 
