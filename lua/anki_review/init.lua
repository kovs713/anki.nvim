local anki = require("anki_review.anki")
local config = require("anki_review.config")
local picker = require("anki_review.picker")
local session = require("anki_review.session")
local persisted = require("anki_review.state")
local ui = require("anki_review.ui")

local M = {}

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

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

	picker.select(decks, { prompt = "Anki deck", selected = persisted.last_deck() }, function(deck)
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
		pick_deck()
		return
	end

	local started = session.start(deck)
	if started and config.get().behavior.remember_last_deck then
		persisted.set_last_deck(deck)
	end
end

function M.start_last()
	local deck = persisted.last_deck()
	if not deck or deck == "" then
		vim.notify("AnkiReview: no last deck saved", vim.log.levels.WARN)
		return
	end

	M.start(deck)
end

function M.home()
	require("anki_review.home").open({
		pick_deck = pick_deck,
		start_last = M.start_last,
	})
end

function M.stats()
	require("anki_review.dashboard").open({
		pick_deck = pick_deck,
		start_last = M.start_last,
	}, { view = "stats" })
end

function M._parse_command(args, bang)
	args = trim(args)
	if bang then
		return "last"
	end
	if args == "" then
		return "picker"
	end

	local head, rest = args:match("^(%S+)%s*(.*)$")
	head = head and head:lower() or args:lower()
	rest = trim(rest)

	if head == "home" then
		return "home"
	elseif head == "stats" or head == "stat" then
		return "stats"
	elseif head == "last" then
		return "last"
	elseif head == "deck" and rest ~= "" then
		return "deck", rest
	end

	return "deck", args
end

function M.command(args, bang)
	local action, value = M._parse_command(args, bang)
	if action == "home" then
		M.home()
	elseif action == "stats" then
		M.stats()
	elseif action == "last" then
		M.start_last()
	elseif action == "picker" then
		M.start()
	else
		M.start(value)
	end
end

return M
