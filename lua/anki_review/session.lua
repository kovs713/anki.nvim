local anki = require("anki_review.anki")
local ui = require("anki_review.ui")

local M = {}

local state = {
	deck = nil,
	buf = nil,
	win = nil,
	current_card = nil,
	showing_answer = false,
	focus_answer = false,
	pending_focus = nil,
	sections = {},
	section_order = {},
	progress = nil,
	stats = nil,
	show_help = false,
	started_at = nil,
	session_started_at = nil,
	timer = nil,
	closed = false,
	error = nil,
	complete = false,
}

local function stop_timer()
	if state.timer then
		state.timer:stop()
		if not state.timer:is_closing() then
			state.timer:close()
		end
		state.timer = nil
	end
end

local function render()
	ui.render(state)
end

local function refresh_progress()
	if not state.deck then
		return
	end

	local stats = anki.deck_stats(state.deck)
	if not stats then
		return
	end

	state.progress = {
		new = stats.new_count or 0,
		learn = stats.learn_count or 0,
		due = stats.review_count or 0,
	}
end

local function start_timer()
	stop_timer()
	state.timer = vim.uv.new_timer()
	state.timer:start(
		1000,
		1000,
		vim.schedule_wrap(function()
			if state.win and vim.api.nvim_win_is_valid(state.win) then
				render()
			else
				stop_timer()
			end
		end)
	)
end

function M.close()
	state.closed = true
	stop_timer()
	ui.close(state)
end

local function mark_complete()
	state.complete = true
	state.error = nil
	state.current_card = nil
	render()
end

function M.load_current_card()
	local card, err = anki.current_card()
	if err then
		if err:lower():find("review is not currently active", 1, true) then
			mark_complete()
			return
		end

		state.error = err
		state.current_card = nil
		render()
		return
	end

	if not card or (not card.cardId and (not card.cards or #card.cards == 0)) then
		mark_complete()
		return
	end

	state.current_card = card
	state.error = nil
	state.complete = false
	render()
end

function M.show_answer()
	if state.showing_answer or not state.current_card then
		return
	end

	local _, err = anki.show_answer()
	if err then
		state.error = err
		render()
		return
	end

	state.showing_answer = true
	state.focus_answer = true
	M.load_current_card()
end

function M.answer(ease)
	if not state.showing_answer or not state.current_card then
		return
	end

	if not ui.valid_answer(state.current_card, ease) then
		vim.notify("AnkiReview: answer option " .. ease .. " is not available", vim.log.levels.WARN)
		return
	end

	local _, err = anki.answer_card(ease)
	if err then
		state.error = err
		render()
		return
	end

	state.showing_answer = false
	state.focus_answer = false
	state.stats.answered = state.stats.answered + 1
	state.stats.ease[ease] = state.stats.ease[ease] + 1
	state.started_at = os.time()
	refresh_progress()
	M.load_current_card()
end

function M.focus_section(section)
	if not ui.focus_section(state, section) then
		vim.notify("AnkiReview: section not available", vim.log.levels.WARN)
	end
end

function M.next_section()
	ui.next_section(state)
end

function M.prev_section()
	ui.prev_section(state)
end

function M.toggle_help()
	state.show_help = not state.show_help
	render()
end

function M.start(deck)
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		M.close()
	end

	state = {
		deck = deck,
		buf = nil,
		win = nil,
		current_card = nil,
		showing_answer = false,
		focus_answer = false,
		pending_focus = nil,
		sections = {},
		section_order = {},
		progress = nil,
		stats = {
			answered = 0,
			ease = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 },
		},
		show_help = false,
		started_at = nil,
		session_started_at = os.time(),
		timer = nil,
		closed = false,
		error = nil,
		complete = false,
	}

	local opened = ui.open(state, {
		show_answer = M.show_answer,
		answer = M.answer,
		focus_section = M.focus_section,
		next_section = M.next_section,
		prev_section = M.prev_section,
		toggle_help = M.toggle_help,
		close = M.close,
		review_again = function()
			local current_deck = state.deck
			M.close()
			M.start(current_deck)
		end,
		home = function()
			M.close()
			require("anki_review").home()
		end,
		closed = function()
			state.closed = true
			stop_timer()
			state.win = nil
			state.buf = nil
		end,
	})
	if not opened then
		return false
	end

	local _, err = anki.start_review(deck)
	if err then
		state.error = err
		render()
		return false
	end

	state.started_at = os.time()
	refresh_progress()
	start_timer()
	M.load_current_card()
	return true
end

return M
