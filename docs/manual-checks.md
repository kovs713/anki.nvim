# Manual Checks

- `:AnkiReview` opens picker.
- `:AnkiReview SomeDeck` starts review.
- `:AnkiReview!` starts last deck or warns if none saved.
- `:AnkiReviewHome` opens without Anki running.
- `:AnkiReviewStats` opens stats view.
- `:AnkiReviewHome` with no Onigiri path shows path missing.
- `:AnkiReviewFindOnigiri` lists candidate Onigiri JSON files or shows guidance.
- `:AnkiReviewOnigiriPath /path/to/gamification_User 1.json` saves only the path.
- configured Onigiri JSON shows level, XP, coins, achievements, and daily specials.
- dashboard does not freeze when Anki is closed.
- dashboard `s`, `h`/`<BS>`, `R`, `q` work.
- review float survives terminal resize.
- answering cards does not create local XP/streak state.
- completion screen shows session stats and Onigiri current values or unavailable.
- corrupt or missing Onigiri JSON does not crash.
- `gamification.provider = "none"` disables gamification display.
- no Onigiri data appears in the plugin install directory.
- offline AnkiConnect shows a friendly error.
