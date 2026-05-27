local M = {}

local state = {
	deck = nil,
	buf = nil,
	win = nil,
	current_card = nil,
	showing_answer = false,
	started_at = nil,
	timer = nil,
	error = nil,
	complete = false,
}

local function strip_html(text)
	if not text then
		return ""
	end
	text = text:gsub("<br%s*/?>", "\n")
	text = text:gsub("</div>", "\n")
	text = text:gsub("</p>", "\n")
	text = text:gsub("<[^>]+>", "")
	text = text:gsub("&nbsp;", " ")
	text = text:gsub("&amp;", "&")
	text = text:gsub("&lt;", "<")
	text = text:gsub("&gt;", ">")
	text = text:gsub("&quot;", '"')
	text = text:gsub("&#39;", "'")
	text = text:gsub("\n%s*\n%s*\n", "\n\n")
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	return text
end

local function format_time(seconds)
	local mins = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%02d:%02d", mins, secs)
end

local function anki(action, params)
	local payload = vim.json.encode({
		action = action,
		version = 6,
		params = params or vim.empty_dict(),
	})

	local obj = vim.system({
		"curl",
		"-s",
		"-X",
		"POST",
		"http://127.0.0.1:8765",
		"-H",
		"Content-Type: application/json",
		"-d",
		payload,
	})
	local result = obj:wait(5000)

	if not result then
		return nil, "Request to AnkiConnect timed out."
	end

	if result.code ~= 0 then
		return nil, "AnkiConnect is not reachable. Make sure Anki is running with AnkiConnect enabled."
	end

	if not result.stdout or result.stdout == "" then
		return nil, "AnkiConnect returned an empty response."
	end

	local ok, decoded = pcall(vim.json.decode, result.stdout)
	if not ok or not decoded then
		return nil, "Failed to parse AnkiConnect response."
	end

	if decoded.error and decoded.error ~= vim.NIL then
		return nil, tostring(decoded.error)
	end

	if decoded.result == vim.NIL then
		return nil, nil
	end

	return decoded.result, nil
end

local render
local stop_timer
local close

local function get_card_text()
	if state.current_card and (state.current_card.question or state.current_card.answer) then
		return strip_html(state.current_card.question or ""), strip_html(state.current_card.answer or "")
	end

	if not state.current_card or not state.current_card.fields then
		return "", ""
	end

	local fields = state.current_card.fields
	local sorted = {}
	for name, data in pairs(fields) do
		table.insert(sorted, { name = name, value = data.value, order = data.order })
	end
	table.sort(sorted, function(a, b)
		return a.order < b.order
	end)

	local question = strip_html(sorted[1] and sorted[1].value or "")
	local answer_parts = {}
	for i = 2, #sorted do
		local val = strip_html(sorted[i].value)
		if val ~= "" then
			table.insert(answer_parts, val)
		end
	end
	local answer = table.concat(answer_parts, "\n")

	return question, answer
end

render = function()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	local lines = {}

	if state.error then
		lines = {
			"Error",
			"",
			tostring(state.error),
			"",
			"Press q to close.",
		}
	elseif state.complete then
		lines = {
			"Review complete!",
			"",
			'No more cards to review in "' .. (state.deck or "") .. '".',
			"",
			"Press q to close.",
		}
	else
		local elapsed = os.time() - (state.started_at or os.time())
		local time_str = format_time(elapsed)
		local state_str = state.showing_answer and "Answer" or "Question"

		local deck_label = "Deck: " .. (state.deck or "")
		local time_label = "Time: " .. time_str
		local padding = math.max(1, 60 - #deck_label - #time_label)
		table.insert(lines, deck_label .. string.rep(" ", padding) .. time_label)
		table.insert(lines, "State: " .. state_str)
		table.insert(lines, "")

		local question, answer = get_card_text()

		table.insert(lines, "QUESTION")
		table.insert(lines, "")
		for _, line in ipairs(vim.split(question, "\n")) do
			table.insert(lines, line)
		end

		if state.showing_answer then
			table.insert(lines, "")
			table.insert(lines, "ANSWER")
			table.insert(lines, "")
			for _, line in ipairs(vim.split(answer, "\n")) do
				table.insert(lines, line)
			end
		end

		table.insert(lines, "")
		local sep_width = state.win and vim.api.nvim_win_get_width(state.win) - 2 or 60
		table.insert(lines, string.rep("─", sep_width))

		if state.showing_answer then
			table.insert(lines, "<CR> Good / next   1 Again   2 Hard   3 Good   4 Easy   q Quit")
		else
			table.insert(lines, "<Space> Reveal answer                                          q Quit")
		end
	end

	local normalized = {}
	for _, line in ipairs(lines) do
		line = line == nil and "" or tostring(line)
		for _, split_line in ipairs(vim.split(line, "\n", { plain = true })) do
			table.insert(normalized, split_line)
		end
	end

	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, normalized)
	vim.bo[state.buf].modifiable = false
end

stop_timer = function()
	if state.timer then
		state.timer:stop()
		if not state.timer:is_closing() then
			state.timer:close()
		end
		state.timer = nil
	end
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

local function open_window()
	local width = math.floor(vim.o.columns * 0.7)
	local height = math.floor(vim.o.lines * 0.7)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	state.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[state.buf].bufhidden = "wipe"
	vim.bo[state.buf].filetype = "anki_review"

	state.win = vim.api.nvim_open_win(state.buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		focusable = true,
		zindex = 100,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(state.win),
		once = true,
		callback = function()
			stop_timer()
			state.win = nil
			state.buf = nil
		end,
	})
end

close = function()
	stop_timer()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	state.win = nil
	state.buf = nil
end

local function load_current_card()
	local result, err = anki("guiCurrentCard")
	if err then
		if err:lower():find("review is not currently active", 1, true) then
			state.complete = true
			state.current_card = nil
			render()
			return
		end

		state.error = err
		state.current_card = nil
		render()
		return
	end

	if not result or (not result.cardId and (not result.cards or #result.cards == 0)) then
		state.complete = true
		state.current_card = nil
		render()
		return
	end

	state.current_card = result
	state.error = nil
	state.complete = false
	render()
end

local function show_answer()
	local _, err = anki("guiShowAnswer")
	if err then
		state.error = err
		render()
		return
	end

	state.showing_answer = true
	load_current_card()
end

local function answer_card(ease)
	if not state.showing_answer then
		return
	end

	local _, err = anki("guiAnswerCard", { ease = ease })
	if err then
		state.error = err
		render()
		return
	end

	state.showing_answer = false
	state.started_at = os.time()
	load_current_card()
end

local function setup_keymaps()
	local opts = { buffer = state.buf, noremap = true, silent = true, nowait = true }

	vim.keymap.set("n", "<Space>", function()
		if not state.showing_answer and state.current_card then
			show_answer()
		end
	end, opts)

	vim.keymap.set("n", "<CR>", function()
		if state.showing_answer then
			answer_card(3)
		end
	end, opts)

	for _, mapping in ipairs({
		{ key = "1", ease = 1 },
		{ key = "2", ease = 2 },
		{ key = "3", ease = 3 },
		{ key = "4", ease = 4 },
	}) do
		local ease = mapping.ease
		vim.keymap.set("n", mapping.key, function()
			if state.showing_answer then
				answer_card(ease)
			end
		end, opts)
	end

	vim.keymap.set("n", "q", function()
		close()
	end, opts)
end

function M.start(deck_name)
	if not deck_name or deck_name == "" then
		vim.notify("AnkiReview: deck name required", vim.log.levels.ERROR)
		return
	end

	if state.win and vim.api.nvim_win_is_valid(state.win) then
		close()
	end

	state = {
		deck = deck_name,
		buf = nil,
		win = nil,
		current_card = nil,
		showing_answer = false,
		started_at = nil,
		timer = nil,
		error = nil,
		complete = false,
	}

	open_window()
	setup_keymaps()

	local _, err = anki("guiDeckReview", { name = deck_name })
	if err then
		state.error = err
		render()
		return
	end

	state.started_at = os.time()
	start_timer()
	load_current_card()
end

vim.api.nvim_create_user_command("AnkiReview", function(opts)
	M.start(opts.args)
end, { nargs = 1 })

return M
