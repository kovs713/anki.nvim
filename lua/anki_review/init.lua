local anki = require("anki_review.anki")
local config = require("anki_review.config")
local picker = require("anki_review.picker")
local session = require("anki_review.session")

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
	return config.setup(opts)
end

function M.start(deck)
	if not deck or deck == "" then
		pick_deck()
		return
	end

	session.start(deck)
end

return M
