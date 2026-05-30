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

local function status_label(status)
	if not status or status.state == "unknown" then
		return "unknown"
	end
	if status.state == "connected" then
		return "connected v" .. tostring(status.version or "?")
	end
	if status.state == "offline" then
		return "offline"
	end
	return status.state
end

local function due_summary(stats)
	if not stats then
		return "unavailable"
	end
	return string.format(
		"New %d \xc2\xb7 Learn %d \xc2\xb7 Review %d \xc2\xb7 Total %d",
		stats.new_count or 0,
		stats.learn_count or 0,
		stats.review_count or 0,
		stats.total_in_deck or 0
	)
end

-- dashboard compact due (no Total)
local function due_compact(stats)
	if not stats then
		return "unavailable"
	end
	return string.format(
		"New %d \xc2\xb7 Learn %d \xc2\xb7 Review %d",
		stats.new_count or 0,
		stats.learn_count or 0,
		stats.review_count or 0
	)
end

local function future_summary(future)
	if not future then
		return "unavailable"
	end
	return string.format(
		"Tomorrow %d \xc2\xb7 Future %d",
		future.tomorrow or 0,
		future.future or 0
	)
end

local function reviews_summary(reviews)
	if not reviews then
		return "unavailable"
	end
	return string.format(
		"Today %d \xc2\xb7 Week %d \xc2\xb7 Month %d",
		reviews.today or 0,
		reviews.week or 0,
		reviews.month or 0
	)
end

-- Dashboard view: compact overview
local function dashboard_lines(context)
	context = context or {}
	local opts = config.get()
	local game_enabled = (opts.gamification or {}).enabled ~= false
	local game = gamification._normalize_state(context.gamification or gamification.load())
	local today = context.today or os.date("%Y-%m-%d")
	local today_data = today_stats(game, today)
	local progress = gamification.level_progress(game.xp)
	local last_deck = context.last_deck
	local status = context.anki_status or { state = "unknown" }
	local stats = context.deck_stats
	local future = context.future_due
	local reviews = context.review_counts
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

	table.insert(lines, "Local progress")
	if game_enabled then
		table.insert(
			lines,
			string.format(
				"Level %d        XP %d / %d",
				progress.current_level,
				progress.xp_into_level,
				progress.xp_needed_for_next_level
			)
		)
		table.insert(lines, bar(progress.xp_into_level, progress.xp_needed_for_next_level, 28))
		table.insert(
			lines,
			string.format(
				"Streak %d       Today %d cards \xc2\xb7 %d XP",
				game.streak.current or 0,
				today_data.cards or 0,
				today_data.xp or 0
			)
		)
		table.insert(lines, "  " .. table.concat(day_labels, " "))
		table.insert(lines, "Activity " .. table.concat(symbols, " "))
	else
		table.insert(lines, "Gamification disabled")
		table.insert(lines, "Local XP, streaks, and activity tracking are off.")
	end

	table.insert(lines, "")
	table.insert(lines, "Anki collection")
	table.insert(lines, "Status " .. status_label(status))
	if last_deck then
		table.insert(lines, "Deck " .. last_deck)
	end
	table.insert(lines, "Due " .. due_compact(stats))
	table.insert(lines, "Future " .. future_summary(future))
	table.insert(lines, "Reviews " .. reviews_summary(reviews))
	table.insert(lines, "")
	table.insert(lines, "p pick deck    l last deck    s stats    R refresh    q quit")
	return fit_lines(lines, context.width or 78)
end

-- Stats view: detailed
local function stats_lines(context)
	context = context or {}
	local game = gamification._normalize_state(context.gamification or gamification.load())
	local today = context.today or os.date("%Y-%m-%d")
	local days = gamification.last_days(7, today)
	local status = context.anki_status or { state = "unknown" }
	local stats = context.deck_stats
	local future = context.future_due
	local reviews = context.review_counts
	local last_deck = context.last_deck or "none"
	local lines = {
		"Session / Progress Stats",
		"",
		"Local progress",
		string.format(
			"XP: %d        Level: %d",
			game.xp or 0,
			game.level or gamification.level_for_xp(game.xp or 0)
		),
		string.format(
			"Streak: %d    Best: %d",
			(game.streak and game.streak.current) or 0,
			(game.streak and game.streak.best) or 0
		),
		string.format(
			"Cards: %d     Time: %s",
			game.totals.cards_answered or 0,
			format_time((game.totals and game.totals.review_seconds) or 0)
		),
		"",
		"Answer breakdown",
		string.format(
			"Again %d   Hard %d   Good %d   Easy %d",
			game.totals.again or 0,
			game.totals.hard or 0,
			game.totals.good or 0,
			game.totals.easy or 0
		),
		"",
		"Local activity  (* anki.nvim reviews only)",
	}

	for _, date in ipairs(days) do
		local day = game.daily[date] or {}
		local sym = gamification.activity_symbol(day.cards or 0)
		table.insert(lines, string.format("%s  %s  %d cards   %d XP", date, sym, day.cards or 0, day.xp or 0))
	end

	table.insert(lines, "")
	table.insert(lines, "Anki collection")
	table.insert(lines, "Status: " .. status_label(status))
	table.insert(lines, "Last deck: " .. last_deck)
	table.insert(lines, "Due: " .. due_summary(stats))
	table.insert(lines, "Future: " .. future_summary(future))
	table.insert(lines, "Reviews: " .. reviews_summary(reviews))
	table.insert(lines, "")
	table.insert(lines, "h dashboard    R refresh    q close")
	return fit_lines(lines, context.width or 78)
end

local function render_lines(state)
	local context = {
		gamification = state.gamification,
		show_help = state.show_help,
		anki_status = state.anki_status,
		deck_stats = state.deck_stats,
		future_due = state.future_due,
		review_counts = state.review_counts,
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
			line:match("^Local progress$")
			or line:match("^Anki collection$")
			or line:match("^Answer breakdown$")
			or line:match("^Local activity")
		then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewWidgetTitle", row, 0, -1)
		elseif line:find("Level", 1, true) or line:find("Streak", 1, true) or line:find("XP:", 1, true) then
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
	if state.last_deck == nil then
		state.last_deck = persisted.last_deck()
	end
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
	state.anki_status = {
		state = "checking",
		version = nil,
		error = nil,
		queried_at = os.time(),
	}
	state.deck_stats = nil
	state.future_due = nil
	state.review_counts = nil
	render(state)

	if state.last_deck == nil then
		state.last_deck = persisted.last_deck()
	end

	local ok, version, err = pcall(anki.version)
	if not ok or err then
		state.anki_status = {
			state = "offline",
			version = nil,
			error = err,
			queried_at = os.time(),
		}
		render(state)
		return
	end

	state.anki_status = {
		state = "connected",
		version = version,
		error = nil,
		queried_at = os.time(),
	}

	if state.last_deck then
		local stats_ok, stats, stats_err = pcall(anki.deck_stats, state.last_deck)
		if stats_ok and not stats_err and stats then
			state.deck_stats = stats
		else
			state.deck_stats = nil
		end

		local future_ok, future, future_err = pcall(anki.future_due, state.last_deck)
		if future_ok and not future_err and future then
			state.future_due = future
		else
			state.future_due = nil
		end

		local rev_ok, rev, rev_err = pcall(anki.review_counts, state.last_deck)
		if rev_ok and not rev_err and rev then
			state.review_counts = rev
		else
			state.review_counts = nil
		end
	end

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
		anki_status = { state = "unknown", version = nil, error = nil, queried_at = nil },
		deck_stats = nil,
		future_due = nil,
		review_counts = nil,
		reset_view = true,
		render_width = dims.width,
		gamification = gamification.load(),
		last_deck = persisted.last_deck(),
		buf = vim.api.nvim_create_buf(false, true),
		win = nil,
	}

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

	vim.keymap.set("n", "p", pick, keymap_opts)
	local function review_last()
		close(state)
		if actions.start_last then
			actions.start_last()
		end
	end
	vim.keymap.set("n", "r", review_last, keymap_opts)
	vim.keymap.set("n", "l", review_last, keymap_opts)
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
