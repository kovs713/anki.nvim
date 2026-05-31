local anki = require("anki_review.anki")
local config = require("anki_review.config")
local onigiri = require("anki_review.onigiri")
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
		"New %d · Learn %d · Review %d · Total %d",
		stats.new_count or 0,
		stats.learn_count or 0,
		stats.review_count or 0,
		stats.total_in_deck or 0
	)
end

local function due_compact(stats)
	if not stats then
		return "unavailable"
	end
	return string.format("New %d · Learn %d · Review %d", stats.new_count or 0, stats.learn_count or 0, stats.review_count or 0)
end

local function future_summary(future)
	if not future then
		return "unavailable"
	end
	return string.format("Tomorrow %d · Future %d", future.tomorrow or 0, future.future or 0)
end

local function reviews_summary(reviews)
	if not reviews then
		return "unavailable"
	end
	return string.format("Today %d · Week %d · Month %d", reviews.today or 0, reviews.week or 0, reviews.month or 0)
end

local function value(raw)
	if raw == nil then
		return "unknown"
	end
	return tostring(raw)
end

local function append_onigiri_dashboard(lines, data, provider)
	table.insert(lines, "Onigiri")
	if provider == "none" then
		table.insert(lines, "Status: disabled")
		table.insert(lines, "Gamification disabled")
		return
	end

	data = data or onigiri.load()
	table.insert(lines, "Status: " .. onigiri.status_label(data))
	if not data.ok then
		if data.error == "path not configured" then
			table.insert(lines, "Onigiri: path not configured")
		end
		table.insert(lines, "Onigiri gamification data unavailable")
		return
	end

	local restaurant = data.restaurant or {}
	local achievements = data.achievements or {}
	local daily_specials = data.daily_specials or {}
	table.insert(lines, "Level: " .. value(restaurant.level))
	table.insert(lines, "XP: " .. value(restaurant.total_xp))
	table.insert(lines, "Coins: " .. value(restaurant.taiyaki_coins))
	table.insert(lines, "Theme: " .. value(restaurant.current_theme_id))
	table.insert(lines, string.format("Achievements: %d/%d", achievements.unlocked or 0, achievements.total or 0))
	table.insert(lines, string.format("Daily specials: %d/%d", daily_specials.completed or 0, daily_specials.total or 0))
	table.insert(lines, "Last updated: " .. value(data.last_updated))
end

local function append_onigiri_stats(lines, data, provider)
	table.insert(lines, "Onigiri gamification")
	if provider == "none" then
		table.insert(lines, "Status: disabled")
		table.insert(lines, "")
		return
	end

	data = data or onigiri.load()
	if not data.ok then
		table.insert(lines, "Status: " .. onigiri.status_label(data))
		table.insert(lines, "Onigiri gamification data unavailable")
		table.insert(lines, "")
		table.insert(lines, "Source")
		table.insert(lines, data.path or "not configured")
		table.insert(lines, "read-only")
		table.insert(lines, "")
		return
	end

	local restaurant = data.restaurant or {}
	local achievements = data.achievements or {}
	local daily_specials = data.daily_specials or {}
	table.insert(lines, "")
	table.insert(lines, "Level: " .. value(restaurant.level))
	table.insert(lines, "Total XP: " .. value(restaurant.total_xp))
	table.insert(lines, "Taiyaki coins: " .. value(restaurant.taiyaki_coins))
	table.insert(lines, "Theme: " .. value(restaurant.current_theme_id))
	table.insert(lines, "Last updated: " .. value(data.last_updated))
	table.insert(lines, "")
	table.insert(lines, "Achievements")
	table.insert(lines, string.format("Unlocked: %d / %d", achievements.unlocked or 0, achievements.total or 0))
	table.insert(lines, "")
	table.insert(lines, "Daily specials")
	table.insert(lines, string.format("Completed: %d / %d", daily_specials.completed or 0, daily_specials.total or 0))
	table.insert(lines, "")
	table.insert(lines, "Source")
	table.insert(lines, data.path or "not configured")
	table.insert(lines, "read-only")
	table.insert(lines, "")
end

local function dashboard_lines(context)
	context = context or {}
	local opts = config.get()
	local provider = ((opts.gamification or {}).provider or "onigiri")
	local last_deck = context.last_deck
	local status = context.anki_status or { state = "unknown" }
	local stats = context.deck_stats
	local future = context.future_due
	local reviews = context.review_counts

	local lines = {
		"Flashcards without leaving the cave",
		"────────────────────────────────────────────────────────────────────",
		"",
	}

	append_onigiri_dashboard(lines, context.onigiri, provider)

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

local function stats_lines(context)
	context = context or {}
	local provider = ((config.get().gamification or {}).provider or "onigiri")
	local status = context.anki_status or { state = "unknown" }
	local stats = context.deck_stats
	local future = context.future_due
	local reviews = context.review_counts
	local last_deck = context.last_deck or "none"
	local lines = {
		"Session / Progress Stats",
		"",
	}

	append_onigiri_stats(lines, context.onigiri, provider)
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
		onigiri = state.onigiri,
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
			line:match("^Onigiri$")
			or line:match("^Onigiri gamification$")
			or line:match("^Anki collection$")
			or line:match("^Achievements$")
			or line:match("^Daily specials$")
			or line:match("^Source$")
		then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewWidgetTitle", row, 0, -1)
		elseif line:find("Level", 1, true) or line:find("XP", 1, true) or line:find("Coins", 1, true) then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewWidgetValue", row, 0, -1)
		elseif line:find(" q ", 1, true) or line:find("q close", 1, true) then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewHint", row, 0, -1)
		end
	end
end

local function render(state)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
	state.onigiri = onigiri.load()
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
		local stats_ok, deck_stats, stats_err = pcall(anki.deck_stats, state.last_deck)
		if stats_ok and not stats_err and deck_stats then
			state.deck_stats = deck_stats
		else
			state.deck_stats = nil
		end

		local future_ok, future, future_err = pcall(anki.future_due, state.last_deck)
		if future_ok and not future_err and future then
			state.future_due = future
		else
			state.future_due = nil
		end

		local review_ok, reviews, review_err = pcall(anki.review_counts, state.last_deck)
		if review_ok and not review_err and reviews then
			state.review_counts = reviews
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
		onigiri = onigiri.load(),
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
