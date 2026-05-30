local text = require("anki_review.text")
local config = require("anki_review.config")

local M = {}
local ns = vim.api.nvim_create_namespace("anki_review")
local augroup_name = "AnkiReviewUI"

local answer_labels = {
	[1] = "Again",
	[2] = "Hard",
	[3] = "Good",
	[4] = "Easy",
}

local function clamp(value, min, max)
	return math.min(math.max(value, min), max)
end

local function window_size()
	local columns = math.max(1, vim.o.columns)
	local lines = math.max(1, vim.o.lines - vim.o.cmdheight)
	local window = config.get().window or {}
	local max_width = math.max(1, columns - 2)
	local max_height = math.max(1, lines - 2)
	local min_width = clamp(window.min_width or 40, 1, max_width)
	local min_height = clamp(window.min_height or 12, 1, max_height)
	local width = clamp(math.floor(columns * (window.width or 0.7)), min_width, max_width)
	local height = clamp(math.floor(lines * (window.height or 0.7)), min_height, max_height)

	return {
		width = math.max(1, width),
		height = math.max(1, height),
		row = math.max(0, math.floor((lines - height) / 2)),
		col = math.max(0, math.floor((columns - width) / 2)),
	}
end

local function clear_autocmds(state)
	if state.augroup then
		pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
		state.augroup = nil
		state.autocmds = nil
		return
	end

	if not state.autocmds then
		return
	end

	for _, autocmd in ipairs(state.autocmds) do
		pcall(vim.api.nvim_del_autocmd, autocmd)
	end
	state.autocmds = nil
end

local function format_time(seconds)
	local mins = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%02d:%02d", mins, secs)
end

local function progress_line(progress)
	if not progress then
		return nil
	end

	return string.format("Due: %d    Learn: %d    New: %d", progress.due or 0, progress.learn or 0, progress.new or 0)
end

local function stats_lines(state)
	local stats = state.stats or { answered = 0, ease = {} }
	local total = os.time() - (state.session_started_at or os.time())
	local gamification_enabled = (config.get().gamification or {}).enabled ~= false
	local lines = {
		"Session",
		string.format("Answered: %d    Time: %s", stats.answered or 0, format_time(total)),
		string.format(
			"Again: %d    Hard: %d    Good: %d    Easy: %d",
			(stats.ease and stats.ease[1]) or 0,
			(stats.ease and stats.ease[2]) or 0,
			(stats.ease and stats.ease[3]) or 0,
			(stats.ease and stats.ease[4]) or 0
		),
	}
	if gamification_enabled then
		table.insert(lines, 3, string.format("XP gained: +%d", stats.xp or 0))
	else
		table.insert(lines, "Gamification disabled")
	end
	if gamification_enabled and state.gamification_streak then
		table.insert(lines, string.format("Streak: %d days", state.gamification_streak))
	end
	return lines
end

local function normalize(lines)
	local normalized = {}
	for _, line in ipairs(lines) do
		line = line == nil and "" or tostring(line)
		for _, split_line in ipairs(vim.split(line, "\n", { plain = true })) do
			table.insert(normalized, split_line)
		end
	end
	return normalized
end

local function answer_hints(card)
	local buttons = card and card.buttons or { 1, 2, 3, 4 }
	local reviews = card and card.nextReviews or {}
	local parts = {}

	for _, ease in ipairs(buttons) do
		local label = answer_labels[ease] or ("Ease " .. ease)
		local review = reviews[ease]
		if review and review ~= vim.NIL then
			label = label .. " " .. text.strip_html(review)
		end
		table.insert(parts, tostring(ease) .. " " .. label)
	end

	return table.concat(parts, "    ")
end

local question_hints = "<Space> Reveal answer    q Quit"

local function setup_highlights()
	vim.api.nvim_set_hl(0, "AnkiReviewTitle", { link = "Title", default = true })
	vim.api.nvim_set_hl(0, "AnkiReviewSection", { link = "Statement", default = true })
	vim.api.nvim_set_hl(0, "AnkiReviewProgress", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "AnkiReviewHint", { link = "Special", default = true })
	vim.api.nvim_set_hl(0, "AnkiReviewError", { link = "ErrorMsg", default = true })
	vim.api.nvim_set_hl(0, "AnkiReviewDashboardTitle", { link = "Title", default = true })
	vim.api.nvim_set_hl(0, "AnkiReviewDashboardSubtitle", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "AnkiReviewDashboardBorder", { link = "FloatBorder", default = true })
	vim.api.nvim_set_hl(0, "AnkiReviewWidgetTitle", { link = "Statement", default = true })
	vim.api.nvim_set_hl(0, "AnkiReviewWidgetValue", { link = "Identifier", default = true })
	vim.api.nvim_set_hl(0, "AnkiReviewXPBar", { link = "String", default = true })
	vim.api.nvim_set_hl(0, "AnkiReviewXPBarEmpty", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "AnkiReviewStreak", { link = "Special", default = true })
	vim.api.nvim_set_hl(0, "AnkiReviewActivityEmpty", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "AnkiReviewActivityLow", { link = "Identifier", default = true })
	vim.api.nvim_set_hl(0, "AnkiReviewActivityMedium", { link = "String", default = true })
	vim.api.nvim_set_hl(0, "AnkiReviewActivityHigh", { link = "Type", default = true })
	vim.api.nvim_set_hl(0, "AnkiReviewActivityMax", { link = "Title", default = true })
	vim.api.nvim_set_hl(0, "AnkiReviewGamificationPopup", { link = "Special", default = true })
end

local function add_highlights(state, lines)
	vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)

	for i, line in ipairs(lines) do
		local row = i - 1
		if line == "Error" then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewError", row, 0, -1)
		elseif line == "QUESTION" or line == "ANSWER" or line == "Session" then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewSection", row, 0, -1)
		elseif line:match("^Deck:") or line:match("^Review complete") then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewTitle", row, 0, -1)
		elseif
			line:match("^Due:")
			or line:match("^Answered:")
			or line:match("^Again:")
			or line:match("^XP gained:")
			or line:match("^Gamification disabled")
		then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewProgress", row, 0, -1)
		elseif line:match("^%+") then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewGamificationPopup", row, 0, -1)
		elseif line:match("Reveal answer") or line:match("Keys:") or line:match("Aliases:") or line:match("Nav:") then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewHint", row, 0, -1)
		end
	end
end

local function compact_hints(state)
	if state.showing_answer then
		return answer_hints(state.current_card) .. "    ? Toggle help    q Quit"
	end

	return question_hints .. "    ? Toggle help"
end

local function full_hints(state)
	if state.showing_answer then
		return {
			answer_hints(state.current_card) .. "    q Quit",
			"Aliases: <S-BS>/<S-Del>=Again    <BS>/<Del>=Hard    <CR>=Good    <S-CR>=Easy",
			"Nav: gq question    ga answer    gb buttons    Tab blocks    ? hide",
		}
	end

	return {
		question_hints,
		"Nav: gq question    gb keys    Tab blocks    ? hide",
	}
end

local function focus_line(state, line)
	if not line or not state.win or not vim.api.nvim_win_is_valid(state.win) then
		return false
	end

	local line_count = state.buf and vim.api.nvim_buf_is_valid(state.buf) and vim.api.nvim_buf_line_count(state.buf)
		or 1
	local target = math.min(line, line_count)
	vim.api.nvim_win_set_cursor(state.win, { target, 0 })
	vim.api.nvim_win_call(state.win, function()
		vim.cmd("normal! zt")
	end)
	return true
end

local function current_section_index(state)
	if not state.sections or not state.section_order or not state.win or not vim.api.nvim_win_is_valid(state.win) then
		return nil
	end

	local cursor_line = vim.api.nvim_win_get_cursor(state.win)[1]
	local current = 1
	for i, section in ipairs(state.section_order) do
		if (state.sections[section] or 0) <= cursor_line then
			current = i
		end
	end
	return current
end

function M.open(state, callbacks)
	setup_highlights()
	local size = window_size()

	state.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[state.buf].bufhidden = "wipe"
	vim.bo[state.buf].filetype = "anki_review"

	local ok, win = pcall(vim.api.nvim_open_win, state.buf, true, {
		relative = "editor",
		width = size.width,
		height = size.height,
		row = size.row,
		col = size.col,
		style = "minimal",
		border = config.get().window.border,
		focusable = true,
		zindex = 100,
	})
	if not ok then
		vim.api.nvim_buf_delete(state.buf, { force = true })
		state.buf = nil
		vim.notify("AnkiReview: editor is too small for review window", vim.log.levels.ERROR)
		return false
	end
	state.win = win

	local opts = { buffer = state.buf, noremap = true, silent = true, nowait = true }
	vim.keymap.set("n", "<Space>", callbacks.show_answer, opts)
	vim.keymap.set("n", "gq", function()
		callbacks.focus_section("question")
	end, opts)
	vim.keymap.set("n", "ga", function()
		callbacks.focus_section("answer")
	end, opts)
	vim.keymap.set("n", "gb", function()
		callbacks.focus_section("buttons")
	end, opts)
	vim.keymap.set("n", "]]", callbacks.next_section, opts)
	vim.keymap.set("n", "[[", callbacks.prev_section, opts)
	vim.keymap.set("n", "<Tab>", callbacks.next_section, opts)
	vim.keymap.set("n", "<S-Tab>", callbacks.prev_section, opts)
	vim.keymap.set("n", "?", callbacks.toggle_help, opts)
	vim.keymap.set("n", "<CR>", function()
		callbacks.answer(config.get().behavior.default_ease)
	end, opts)
	vim.keymap.set("n", "<S-CR>", function()
		callbacks.answer(4)
	end, opts)
	vim.keymap.set("n", "<BS>", function()
		callbacks.answer(2)
	end, opts)
	vim.keymap.set("n", "<Del>", function()
		callbacks.answer(2)
	end, opts)
	vim.keymap.set("n", "<S-BS>", function()
		callbacks.answer(1)
	end, opts)
	vim.keymap.set("n", "<S-Del>", function()
		callbacks.answer(1)
	end, opts)
	for _, ease in ipairs({ 1, 2, 3, 4 }) do
		local answer_ease = ease
		vim.keymap.set("n", tostring(ease), function()
			callbacks.answer(answer_ease)
		end, opts)
	end
	vim.keymap.set("n", "q", callbacks.close, opts)
	vim.keymap.set("n", "r", function()
		if state.complete and callbacks.review_again then
			callbacks.review_again()
		end
	end, opts)
	vim.keymap.set("n", "h", function()
		if state.complete and callbacks.home then
			callbacks.home()
		end
	end, opts)

	state.augroup = vim.api.nvim_create_augroup(augroup_name, { clear = true })
	state.autocmds = {}
	table.insert(
		state.autocmds,
		vim.api.nvim_create_autocmd("WinClosed", {
			group = state.augroup,
			pattern = tostring(state.win),
			once = true,
			callback = function()
				clear_autocmds(state)
				callbacks.closed()
			end,
		})
	)

	table.insert(
		state.autocmds,
		vim.api.nvim_create_autocmd("VimResized", {
			group = state.augroup,
			callback = function()
				if not state.win or not vim.api.nvim_win_is_valid(state.win) then
					clear_autocmds(state)
					return
				end

				local resized = window_size()
				local resize_ok = pcall(vim.api.nvim_win_set_config, state.win, {
					relative = "editor",
					width = resized.width,
					height = resized.height,
					row = resized.row,
					col = resized.col,
				})
				if not resize_ok then
					return
				end
				M.render(state)
			end,
		})
	)
	return true
end

function M.close(state)
	clear_autocmds(state)
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	state.win = nil
	state.buf = nil
end

function M.render(state)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	local lines = {}
	local sections = {}
	local section_order = {}
	local function mark_section(name)
		sections[name] = #normalize(lines) + 1
		table.insert(section_order, name)
	end

	if state.error then
		lines = { "Error", "", tostring(state.error), "", "Press q to close." }
	elseif state.complete then
		lines = { "Review complete", "", 'No more cards to review in "' .. (state.deck or "") .. '".', "" }
		local progress = progress_line(state.progress)
		if progress then
			table.insert(lines, progress)
			table.insert(lines, "")
		end
		for _, line in ipairs(stats_lines(state)) do
			table.insert(lines, line)
		end
		table.insert(lines, "")
		table.insert(lines, "q close · r review again · h dashboard")
	else
		local elapsed = os.time() - (state.started_at or os.time())
		local deck_label = "Deck: " .. (state.deck or "")
		local time_label = "Time: " .. format_time(elapsed)
		local padding = math.max(1, 60 - #deck_label - #time_label)
		local question, answer = text.card_text(state.current_card)

		table.insert(lines, deck_label .. string.rep(" ", padding) .. time_label)
		local progress = progress_line(state.progress)
		if progress then
			table.insert(lines, progress)
		end
		table.insert(lines, "State: " .. (state.showing_answer and "Answer" or "Question"))
		if state.gamification_feedback and (not state.gamification_feedback_until or os.time() <= state.gamification_feedback_until) then
			table.insert(lines, state.gamification_feedback)
		else
			state.gamification_feedback = nil
			state.gamification_feedback_until = nil
		end
		table.insert(lines, "")
		mark_section("question")
		table.insert(lines, "QUESTION")
		table.insert(lines, "")
		table.insert(lines, question)

		if state.showing_answer then
			table.insert(lines, "")
			mark_section("answer")
			table.insert(lines, "ANSWER")
			table.insert(lines, "")
			table.insert(lines, answer)
		end

		table.insert(lines, "")
		local separator_width = math.max(1, state.win and vim.api.nvim_win_get_width(state.win) - 2 or 60)
		table.insert(lines, string.rep("─", separator_width))
		mark_section("buttons")
		if state.show_help then
			for _, hint in ipairs(full_hints(state)) do
				table.insert(lines, hint)
			end
		else
			table.insert(lines, compact_hints(state))
		end
	end

	local normalized = normalize(lines)
	state.sections = sections
	state.section_order = section_order

	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, normalized)
	add_highlights(state, normalized)
	vim.bo[state.buf].modifiable = false

	local pending_focus = state.pending_focus
	if state.focus_answer then
		state.focus_answer = false
		pending_focus = "answer"
	end

	if pending_focus then
		state.pending_focus = nil
		M.focus_section(state, pending_focus)
	end
end

function M.focus_section(state, section)
	if not state.sections or not state.sections[section] then
		return false
	end

	state.active_section = section
	return focus_line(state, state.sections[section])
end

function M.next_section(state)
	local idx = current_section_index(state)
	if not idx or not state.section_order or #state.section_order == 0 then
		return false
	end

	idx = idx == #state.section_order and 1 or idx + 1
	return M.focus_section(state, state.section_order[idx])
end

function M.prev_section(state)
	local idx = current_section_index(state)
	if not idx or not state.section_order or #state.section_order == 0 then
		return false
	end

	idx = idx == 1 and #state.section_order or idx - 1
	return M.focus_section(state, state.section_order[idx])
end

function M.valid_answer(card, ease)
	if not card or not card.buttons then
		return ease >= 1 and ease <= 4
	end

	for _, button in ipairs(card.buttons) do
		if button == ease then
			return true
		end
	end

	return false
end

function M._window_size()
	return window_size()
end

function M.setup_highlights()
	setup_highlights()
end

return M
