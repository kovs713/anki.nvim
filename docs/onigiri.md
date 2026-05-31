# Onigiri and External Add-ons

`anki.nvim` reviews cards through AnkiConnect. Reviews are recorded by Anki itself, so stats/history add-ons may see normal Anki review data.

## Dashboard Contract

`:AnkiReviewHome` and `:AnkiReviewStats` are Onigiri-only dashboard views.

- dashboard renders configured Onigiri JSON fields only.
- no local anki.nvim XP, streak, level, achievement, or restaurant state exists.
- no Anki collection stats are mixed into dashboard or stats views.
- missing, invalid, or unconfigured Onigiri data shows setup guidance.

## Onigiri Source

`anki.nvim` can display existing Onigiri Anki add-on gamification data in read-only mode. Onigiri remains source of truth.

Common Onigiri profile files live under the add-on `user_files` directory:

```text
user_files/gamification_<profile_name>.json
user_files/gamification.json
```

Profile names can contain spaces, for example `gamification_User 1.json`.

Set the path from Neovim:

```vim
:AnkiReviewFindOnigiri
:AnkiReviewOnigiriPath /path/to/gamification_User 1.json
```

Or set it in config:

```lua
require("anki_review").setup({
  onigiri = {
    gamification_path = "/path/to/gamification_User 1.json",
  },
})
```

## Data Boundaries

`anki.nvim` only reads configured Onigiri JSON.

- does not copy, modify, normalize, repair, or write Onigiri data.
- does not auto-discover, import, copy, or migrate Onigiri data into plugin state.
- does not write gamification data to Anki add-on directories, the Anki collection/database, or the Anki media folder.
- does not claim XP gained from answers.
- answering cards sends normal AnkiConnect review actions only.

Visual add-ons that modify Anki's reviewer UI, card webview, buttons, colors, or keyboard shortcuts are not rendered inside the Neovim floating window.

Anki, Onigiri, review heatmap, or other tools may show data that `anki.nvim` only reads or does not render.

## Highlights

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
