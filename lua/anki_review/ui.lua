local text = require("anki_review.text")

local M = {}

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
	local columns = vim.o.columns
	local lines = vim.o.lines - vim.o.cmdheight
	local width = clamp(math.floor(columns * 0.72), math.min(60, columns - 4), math.min(110, columns - 4))
	local height = clamp(math.floor(lines * 0.72), math.min(18, lines - 4), math.min(34, lines - 4))

	return {
		width = math.max(20, width),
		height = math.max(8, height),
		row = math.max(0, math.floor((lines - height) / 2)),
		col = math.max(0, math.floor((columns - width) / 2)),
	}
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
	return {
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

local function answer_hints(card, opts)
	opts = opts or {}
	local buttons = card and card.buttons or { 1, 2, 3, 4 }
	local reviews = card and card.nextReviews or {}
	local parts = { "<CR> Good" }

	for _, ease in ipairs(buttons) do
		local label = answer_labels[ease] or ("Ease " .. ease)
		local review = reviews[ease]
		if review and review ~= vim.NIL then
			label = label .. " " .. text.strip_html(review)
		end
		if opts.aliases and opts.aliases[ease] then
			label = label .. " (" .. opts.aliases[ease] .. ")"
		end
		table.insert(parts, tostring(ease) .. " " .. label)
	end

	table.insert(parts, "q Quit")
	return table.concat(parts, "    ")
end

local question_hints = "<Space> Reveal answer    q Quit"

local function compact_hints(state)
	if state.showing_answer then
		return answer_hints(state.current_card, { aliases = { [1] = "S-BS/S-Del", [2] = "BS/Del", [4] = "S-CR" } })
			.. "    ? Nav"
	end

	return question_hints .. "    ? Nav"
end

local function full_hints(state)
	if state.showing_answer then
		return {
			answer_hints(state.current_card, { aliases = { [1] = "S-BS/S-Del", [2] = "BS/Del", [4] = "S-CR" } }),
			"gq Question    ga Answer    gb Buttons    [[/]] or <Tab> Blocks    ? Hide nav",
		}
	end

	return {
		question_hints,
		"gq Question    gb Keys    [[/]] or <Tab> Blocks    ? Hide nav",
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
	local size = window_size()

	state.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[state.buf].bufhidden = "wipe"
	vim.bo[state.buf].filetype = "anki_review"

	state.win = vim.api.nvim_open_win(state.buf, true, {
		relative = "editor",
		width = size.width,
		height = size.height,
		row = size.row,
		col = size.col,
		style = "minimal",
		border = "rounded",
		focusable = true,
		zindex = 100,
	})

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
		callbacks.answer(3)
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

	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(state.win),
		once = true,
		callback = callbacks.closed,
	})

	vim.api.nvim_create_autocmd("VimResized", {
		buffer = state.buf,
		callback = function()
			if not state.win or not vim.api.nvim_win_is_valid(state.win) then
				return
			end

			local resized = window_size()
			vim.api.nvim_win_set_config(state.win, {
				relative = "editor",
				width = resized.width,
				height = resized.height,
				row = resized.row,
				col = resized.col,
			})
			M.render(state)
		end,
	})
end

function M.close(state)
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
		lines = {
			"Review complete!",
			"",
			'No more cards to review in "' .. (state.deck or "") .. '".',
			"",
		}
		local progress = progress_line(state.progress)
		if progress then
			table.insert(lines, progress)
			table.insert(lines, "")
		end
		for _, line in ipairs(stats_lines(state)) do
			table.insert(lines, line)
		end
		table.insert(lines, "")
		table.insert(lines, "Press q to close.")
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
		table.insert(lines, string.rep("─", state.win and vim.api.nvim_win_get_width(state.win) - 2 or 60))
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

return M
