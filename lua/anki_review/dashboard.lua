local config = require("anki_review.config")
local onigiri = require("anki_review.onigiri")

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

local function value(raw)
	if raw == nil then
		return "unknown"
	end
	return tostring(raw)
end

local function setup_lines(data)
	local reason = data and data.error or "unavailable"
	local reason_text = ({
		["path not configured"] = "path not configured",
		["file not found"] = "file not found",
		["invalid json"] = "invalid json",
		["invalid data"] = "invalid data",
		["disabled"] = "provider disabled",
	})[reason] or reason

	return {
		"Onigiri dashboard unavailable",
		"",
		"Reason: " .. reason_text,
		"",
		"Configure:",
		":AnkiReviewOnigiriPath /path/to/gamification_PROFILE.json",
		"",
		"Expected file:",
		"Anki2/addons21/1011095603/user_files/gamification_<profile>.json",
		"",
		"q close",
	}
end

local function append_optional_dashboard(lines, data)
	local restaurant = data.restaurant or {}
	if type(restaurant.owned_items) == "table" and #restaurant.owned_items > 0 then
		table.insert(lines, "Owned items: " .. table.concat(restaurant.owned_items, ", "))
	end

	local flags = {}
	for _, key in ipairs({ "enabled", "migrated", "notifications_enabled" }) do
		if restaurant[key] ~= nil then
			table.insert(flags, key .. "=" .. tostring(restaurant[key]))
		end
	end
	if #flags > 0 then
		table.insert(lines, "Enabled flags: " .. table.concat(flags, " | "))
	end

	local progress = {}
	for _, key in ipairs({ "show_profile_bar_progress", "show_profile_page_progress" }) do
		if restaurant[key] ~= nil then
			table.insert(progress, key .. "=" .. tostring(restaurant[key]))
		end
	end
	if #progress > 0 then
		table.insert(lines, "Profile progress: " .. table.concat(progress, " | "))
	end

	if type(restaurant.daily_special) == "table" then
		local daily = restaurant.daily_special
		table.insert(lines, "Daily special details: " .. value(daily.name or daily.id or daily.description))
	end

	local first_achievement = data.achievements and data.achievements.items and data.achievements.items[1]
	if first_achievement then
		table.insert(lines, "Achievement details: " .. value(first_achievement.name or first_achievement.id))
	end
end

local function dashboard_lines(context)
	local data = context.onigiri or onigiri.load()
	if not data.ok then
		return setup_lines(data)
	end

	local restaurant = data.restaurant or {}
	local achievements = data.achievements or {}
	local daily_specials = data.daily_specials or {}
	local lines = {
		"Onigiri companion dashboard",
		"",
		"Onigiri status: connected",
		"Restaurant level: " .. value(restaurant.level),
		"Total XP: " .. value(restaurant.total_xp),
		"Taiyaki coins: " .. value(restaurant.taiyaki_coins),
		"Theme: " .. value(restaurant.current_theme_id),
		string.format("Daily specials: %d/%d", daily_specials.completed or 0, daily_specials.total or 0),
		string.format("Achievements: %d/%d", achievements.unlocked or 0, achievements.total or 0),
		"Last updated: " .. value(data.last_updated),
		"Source path: " .. value(data.path),
	}
	append_optional_dashboard(lines, data)
	table.insert(lines, "")
	table.insert(lines, "s stats    R refresh    q close")
	return lines
end

local function stats_lines(context)
	local data = context.onigiri or onigiri.load()
	if not data.ok then
		return setup_lines(data)
	end

	local restaurant = data.restaurant or {}
	local achievements = data.achievements or {}
	local daily_specials = data.daily_specials or {}
	local lines = {
		"Onigiri detailed stats",
		"",
		"Restaurant level",
		"level=" .. value(restaurant.level) .. " xp=" .. value(restaurant.total_xp) .. " coins=" .. value(restaurant.taiyaki_coins),
		"theme=" .. value(restaurant.current_theme_id),
		"",
		"Daily specials list",
	}

	for _, item in ipairs(daily_specials.items or {}) do
		table.insert(
			lines,
			string.format(
				"- %s completed=%s target=%s done=%s xp=%s",
				value(item.name or item.id),
				value(item.completed),
				value(item.target_cards),
				value(item.cards_completed),
				value(item.xp_earned)
			)
		)
	end
	if #(daily_specials.items or {}) == 0 then
		table.insert(lines, "- none")
	end

	table.insert(lines, "")
	table.insert(lines, "Achievements list")
	for _, item in ipairs(achievements.items or {}) do
		table.insert(lines, string.format("- %s unlocked=%s progress=%s/%s", value(item.name or item.id), value(item.unlocked), value(item.progress), value(item.threshold)))
	end
	if #(achievements.items or {}) == 0 then
		table.insert(lines, "- none")
	end

	table.insert(lines, "")
	table.insert(lines, "Source path: " .. value(data.path))
	table.insert(lines, "read-only")
	table.insert(lines, "Last updated: " .. value(data.last_updated))
	table.insert(lines, "")
	table.insert(lines, "h dashboard    R refresh    q close")
	return lines
end

local function render_lines(state)
	if state.view == "stats" then
		return stats_lines({ onigiri = state.onigiri })
	end
	return dashboard_lines({ onigiri = state.onigiri })
end

local function add_highlights(state, lines)
	vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
	for i, line in ipairs(lines) do
		local row = i - 1
		if i == 1 then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewDashboardTitle", row, 0, -1)
		elseif line:match("^Onigiri") or line:match("^Restaurant level$") or line:match("^Daily specials list$") or line:match("^Achievements list$") then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewWidgetTitle", row, 0, -1)
		elseif line:find("q close", 1, true) or line:find("R refresh", 1, true) then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewHint", row, 0, -1)
		end
	end
end

local function render(state)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
	state.onigiri = onigiri.load()
	local lines = render_lines(state)
	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	add_highlights(state, lines)
	vim.bo[state.buf].modifiable = false
end

local function close(state)
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	state.win = nil
	state.buf = nil
end

local function refresh_status(state)
	render(state)
end

function M.open(_, opts)
	opts = opts or {}
	require("anki_review.ui").setup_highlights()

	local dims = size()
	local state = {
		view = opts.view or "dashboard",
		onigiri = onigiri.load(),
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
		vim.notify("AnkiReview: editor too small", vim.log.levels.ERROR)
		return
	end
	state.win = win
	vim.wo[win].winhighlight = "FloatBorder:AnkiReviewDashboardBorder"

	local keymap_opts = { buffer = state.buf, noremap = true, silent = true, nowait = true }
	vim.keymap.set("n", "s", function()
		state.view = "stats"
		render(state)
	end, keymap_opts)
	vim.keymap.set("n", "h", function()
		state.view = "dashboard"
		render(state)
	end, keymap_opts)
	vim.keymap.set("n", "<BS>", function()
		state.view = "dashboard"
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
