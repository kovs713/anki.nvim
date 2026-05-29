local anki = require("anki_review.anki")
local config = require("anki_review.config")
local picker = require("anki_review.picker")
local session = require("anki_review.session")
local persisted = require("anki_review.state")
local ui = require("anki_review.ui")

local M = {}

local function pick_deck()
	local decks, err = anki.deck_names()
	if err then
		vim.notify("AnkiReview: " .. err, vim.log.levels.ERROR)
		return
	end

	if not decks or #decks == 0 then
		vim.notify("AnkiReview: no decks found", vim.log.levels.WARN)
		return
	end

	picker.select(decks, { prompt = "Anki deck" }, function(deck)
		if deck then
			M.start(deck)
		end
	end)
end

function M.setup(opts)
	local options = config.setup(opts)
	ui.setup_highlights()
	return options
end

function M.start(deck)
	if not deck or deck == "" then
		if config.get().remember_last_deck then
			local last_deck = persisted.last_deck()
			if last_deck and last_deck ~= "" then
				session.start(last_deck)
				return
			end
		end

		pick_deck()
		return
	end

	if config.get().remember_last_deck then
		persisted.set_last_deck(deck)
	end

	session.start(deck)
end

return M
