local anki = require("anki_review.anki")
local config = require("anki_review.config")
local gamification = require("anki_review.gamification")
local persisted = require("anki_review.state")

local M = {}
local ns = vim.api.nvim_create_namespace("anki_review_dashboard")

local function clamp(value, min, max)
	return math.min(math.max(value, min), max)
end

local function size()
	local dashboard = config.get().dashboard or {}
	local columns = math.max(1, vim.o.columns)
	local lines = math.max(1, vim.o.lines - vim.o.cmdheight)
	local width = clamp(math.floor(columns * (dashboard.width or 0.75)), 1, math.max(1, columns - 2))
	local height = clamp(math.floor(lines * (dashboard.height or 0.75)), 1, math.max(1, lines - 2))
	return {
		width = width,
		height = height,
		row = math.max(0, math.floor((lines - height) / 2)),
		col = math.max(0, math.floor((columns - width) / 2)),
	}
end

local function format_time(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours = math.floor(seconds / 3600)
	local mins = math.floor((seconds % 3600) / 60)
	if hours > 0 then
		return string.format("%dh %dm", hours, mins)
	end
	if mins > 0 then
		return string.format("%dm", mins)
	end
	return string.format("%ds", seconds)
end

local function display_width(text)
	return vim.fn.strdisplaywidth(text or "")
end

local function truncate(text, max_width)
	text = text or ""
	if display_width(text) <= max_width then
		return text
	end

	local clipped = vim.fn.strcharpart(text, 0, math.max(0, max_width - 3))
	while clipped ~= "" and display_width(clipped) > max_width - 3 do
		clipped = vim.fn.strcharpart(clipped, 0, vim.fn.strchars(clipped) - 1)
	end
	return clipped .. "..."
end

local function bar(current, total, width)
	width = math.max(1, width or 28)
	if total <= 0 then
		return string.rep("░", width)
	end
	local filled = clamp(math.floor((current / total) * width + 0.5), 0, width)
	return string.rep("█", filled) .. string.rep("░", width - filled)
end

local function with_reason(value, reason)
	value = tostring(value or "unknown")
	if value == "unknown" and reason and reason ~= "" then
		return value .. " (" .. reason .. ")"
	end
	return value
end

local function day_name(date)
	local year, month, day = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not year then
		return date
	end
	local time = os.time({
		year = tonumber(year),
		month = tonumber(month),
		day = tonumber(day),
		hour = 12,
	})
	if not time then
		return date
	end
	return os.date("%a", time)
end

local function today_stats(game, today)
	return game.daily[today] or {
		cards = 0,
		again = 0,
		hard = 0,
		good = 0,
		easy = 0,
		xp = 0,
		review_seconds = 0,
	}
end

local function fit_lines(lines, width)
	width = math.max(1, width or 72)
	local output = {}
	for _, line in ipairs(lines) do
		table.insert(output, truncate(line, width))
	end
	return output
end

local function dashboard_lines(context)
	context = context or {}
	local opts = config.get()
	local game_enabled = (opts.gamification or {}).enabled ~= false
	local game = gamification._normalize_state(context.gamification or gamification.load())
	local today = context.today or os.date("%Y-%m-%d")
	local today_data = today_stats(game, today)
	local progress = gamification.level_progress(game.xp)
	local last_deck = context.last_deck
	if last_deck == nil then
		last_deck = persisted.last_deck()
	end
	local status = with_reason(context.status or "unknown", context.status_reason)
	local due = with_reason(context.due or "unknown", context.due_reason)
	local activity_days = math.max(1, tonumber((opts.dashboard or {}).activity_days) or 7)
	local activity = gamification.activity_strip(game, activity_days, today)
	local day_labels = {}
	local symbols = {}
	for _, day in ipairs(activity) do
		table.insert(day_labels, day_name(day.date))
		table.insert(symbols, day.symbol)
	end

	local lines = {
		"Flashcards without leaving the cave",
		"────────────────────────────────────────────────────────────────────",
		"",
	}

	if game_enabled then
		table.insert(
			lines,
			string.format(
				"Local Level %d        XP %d / %d        Streak %d days        Best %d",
				progress.current_level,
				progress.xp_into_level,
				progress.xp_needed_for_next_level,
				game.streak.current or 0,
				game.streak.best or 0
			)
		)
		table.insert(lines, bar(progress.xp_into_level, progress.xp_needed_for_next_level, 32))
	else
		table.insert(lines, "Gamification disabled")
		table.insert(lines, "Local XP, streaks, and activity tracking are off.")
	end

	table.insert(lines, "")
	table.insert(lines, "Today (local)")
	table.insert(
		lines,
		string.format(
			"Cards %d       Good %d       Again %d       Time %s       XP +%d",
			today_data.cards or 0,
			today_data.good or 0,
			today_data.again or 0,
			format_time(today_data.review_seconds or 0),
			today_data.xp or 0
		)
	)
	table.insert(lines, "")
	table.insert(lines, "Local activity")
	table.insert(lines, "local plugin stats, not full Anki history")
	table.insert(lines, table.concat(day_labels, "  "))
	table.insert(lines, " " .. table.concat(symbols, "    "))
	table.insert(lines, "")
	table.insert(lines, "Anki")
	table.insert(lines, "Status " .. status)
	table.insert(lines, "Last deck " .. (last_deck or "none"))
	table.insert(lines, "Due " .. due)
	table.insert(lines, "")
	table.insert(lines, "Actions")
	table.insert(lines, "r/p deck picker    l last deck    s stats    ? help    R refresh    q quit")

	if context.show_help then
		table.insert(lines, "")
		table.insert(lines, "Help")
		table.insert(lines, "Anki owns scheduling through AnkiConnect; this dashboard tracks local motivation only.")
		table.insert(lines, "No browser UI, add-on state, images, or Anki database writes are used.")
	end

	return fit_lines(lines, context.width or 78)
end

local function stats_lines(context)
	context = context or {}
	local game = gamification._normalize_state(context.gamification or gamification.load())
	local today = context.today or os.date("%Y-%m-%d")
	local days = gamification.last_days(7, today)
	local status = with_reason(context.status or "unknown", context.status_reason)
	local due = with_reason(context.due or "unknown", context.due_reason)
	local last_deck = context.last_deck or "none"
	local lines = {
		"Session / Progress Stats",
		"local plugin stats, not full Anki history",
		"",
		"Total cards answered: " .. tostring(game.totals.cards_answered or 0),
		"Total XP: " .. tostring(game.xp or 0),
		"Level: " .. tostring(game.level or gamification.level_for_xp(game.xp or 0)),
		"Current streak: " .. tostring((game.streak and game.streak.current) or 0),
		"Best streak: " .. tostring((game.streak and game.streak.best) or 0),
		"Total review time: " .. format_time((game.totals and game.totals.review_seconds) or 0),
		"",
		"Answer breakdown:",
		"Again " .. tostring(game.totals.again or 0),
		"Hard  " .. tostring(game.totals.hard or 0),
		"Good  " .. tostring(game.totals.good or 0),
		"Easy  " .. tostring(game.totals.easy or 0),
		"",
		"Local activity:",
	}

	for _, date in ipairs(days) do
		local day = game.daily[date] or {}
		table.insert(lines, string.format("%s  %d cards  %d XP", date, day.cards or 0, day.xp or 0))
	end

	table.insert(lines, "")
	table.insert(lines, "Anki stats")
	table.insert(lines, "Status: " .. status)
	table.insert(lines, "Last deck: " .. last_deck)
	table.insert(lines, "Due summary: " .. tostring(due))
	table.insert(lines, "Future due: not implemented yet")
	table.insert(lines, "Review history: not implemented yet")
	table.insert(lines, "")
	table.insert(lines, "h/<BS> dashboard    R refresh    q close")
	return fit_lines(lines, context.width or 78)
end

local function render_lines(state)
	local context = {
		gamification = state.gamification,
		show_help = state.show_help,
		status = state.status,
		status_reason = state.status_reason,
		due = state.due,
		due_reason = state.due_reason,
		last_deck = state.last_deck,
		width = state.render_width,
	}
	if state.view == "stats" then
		return stats_lines(context)
	end
	return dashboard_lines(context)
end

local function add_highlights(state, lines)
	vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
	for i, line in ipairs(lines) do
		local row = i - 1
		if i == 1 then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewDashboardTitle", row, 0, -1)
		elseif line:find("Flashcards without leaving the cave", 1, true) then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewDashboardSubtitle", row, 0, -1)
		elseif
			line:match("Today")
			or line:match("Anki stats")
			or line:match("Local activity")
			or line:match("Actions")
		then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewWidgetTitle", row, 0, -1)
		elseif line:find("XP", 1, true) or line:find("Streak", 1, true) then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewWidgetValue", row, 0, -1)
		elseif line:find("█", 1, true) or line:find("░", 1, true) then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewXPBar", row, 0, -1)
		elseif line:find(" q ", 1, true) or line:find("q close", 1, true) then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewHint", row, 0, -1)
		end
	end
end

local function render(state)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
	state.gamification = gamification.load()
	state.last_deck = persisted.last_deck()
	local lines = render_lines(state)
	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	add_highlights(state, lines)
	vim.bo[state.buf].modifiable = false

	if state.reset_view and state.win and vim.api.nvim_win_is_valid(state.win) then
		state.reset_view = false
		pcall(vim.api.nvim_win_set_cursor, state.win, { 1, 0 })
		pcall(vim.api.nvim_win_call, state.win, function()
			vim.cmd("normal! zt")
		end)
	end
end

local function close(state)
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	state.win = nil
	state.buf = nil
end

local function refresh_status(state)
	state.status = "checking"
	state.status_reason = nil
	state.due = "unknown"
	state.due_reason = "waiting for Anki status"
	render(state)
	local old_timeout = config.get().anki.timeout
	config.get().anki.timeout = math.min(old_timeout or 5000, 500)
	local ok, version, err = pcall(anki.version)
	if not ok or err then
		state.status = "offline"
		state.due = "unknown"
		state.due_reason = "AnkiConnect offline"
	elseif not state.last_deck then
		state.status = "connected v" .. tostring(version)
		state.due = "unknown"
		state.due_reason = "no last deck"
	else
		state.status = "connected v" .. tostring(version)
		local stats_ok, stats, stats_err = pcall(anki.deck_stats, state.last_deck)
		if stats_ok and not stats_err and stats then
			state.due = tostring(stats.review_count or 0)
			state.due_reason = nil
		else
			state.due = "unknown"
			state.due_reason = "getDeckStats failed"
		end
	end
	config.get().anki.timeout = old_timeout
	render(state)
end

function M.open(actions, opts)
	actions = actions or {}
	opts = opts or {}
	require("anki_review.ui").setup_highlights()

	local dims = size()
	local state = {
		view = opts.view or "dashboard",
		show_help = false,
		status = "unknown",
		status_reason = "not queried yet",
		due = "unknown",
		due_reason = nil,
		reset_view = true,
		render_width = dims.width,
		gamification = gamification.load(),
		last_deck = persisted.last_deck(),
		buf = vim.api.nvim_create_buf(false, true),
		win = nil,
	}
	state.due_reason = state.last_deck and "press R to query Anki" or "no last deck"

	vim.bo[state.buf].bufhidden = "wipe"
	vim.bo[state.buf].filetype = "anki_review_dashboard"

	local ok, win = pcall(vim.api.nvim_open_win, state.buf, true, {
		relative = "editor",
		width = dims.width,
		height = dims.height,
		row = dims.row,
		col = dims.col,
		style = "minimal",
		border = config.get().window.border,
		title = " anki.nvim 🃏 ",
		title_pos = "center",
		focusable = true,
		zindex = 120,
	})
	if not ok then
		vim.api.nvim_buf_delete(state.buf, { force = true })
		vim.notify("AnkiReview: editor is too small for dashboard", vim.log.levels.ERROR)
		return
	end
	state.win = win
	vim.wo[win].winhighlight = "FloatBorder:AnkiReviewDashboardBorder"

	local keymap_opts = { buffer = state.buf, noremap = true, silent = true, nowait = true }
	local function pick()
		close(state)
		if actions.pick_deck then
			actions.pick_deck()
		end
	end

	vim.keymap.set("n", "r", pick, keymap_opts)
	vim.keymap.set("n", "p", pick, keymap_opts)
	vim.keymap.set("n", "l", function()
		close(state)
		if actions.start_last then
			actions.start_last()
		end
	end, keymap_opts)
	vim.keymap.set("n", "s", function()
		state.view = "stats"
		state.reset_view = true
		render(state)
	end, keymap_opts)
	vim.keymap.set("n", "h", function()
		state.view = "dashboard"
		state.reset_view = true
		render(state)
	end, keymap_opts)
	vim.keymap.set("n", "<BS>", function()
		state.view = "dashboard"
		state.reset_view = true
		render(state)
	end, keymap_opts)
	vim.keymap.set("n", "?", function()
		state.show_help = not state.show_help
		render(state)
	end, keymap_opts)
	vim.keymap.set("n", "R", function()
		refresh_status(state)
	end, keymap_opts)
	vim.keymap.set("n", "q", function()
		close(state)
	end, keymap_opts)
	vim.keymap.set("n", "<Esc>", function()
		close(state)
	end, keymap_opts)

	render(state)
end

function M._render_lines(context)
	return dashboard_lines(context or {})
end

function M._render_stats_lines(context)
	return stats_lines(context or {})
end

function M._refresh_status(state)
	return refresh_status(state)
end

return M
