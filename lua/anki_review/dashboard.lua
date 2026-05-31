local config = require("anki_review.config")
local anki = require("anki_review.anki")
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

local function display_width(text)
	return vim.fn.strdisplaywidth(text or "")
end

local function value(raw)
	if raw == nil then
		return "unknown"
	end
	return tostring(raw)
end

local function clip_text(text, max_width)
	text = tostring(text or "")
	if max_width <= 0 then
		return ""
	end
	if display_width(text) <= max_width then
		return text
	end
	if max_width == 1 then
		return "…"
	end
	local out = ""
	for _, ch in ipairs(vim.fn.split(text, "\\zs")) do
		if display_width(out .. ch) >= max_width then
			break
		end
		out = out .. ch
	end
	return out .. "…"
end

local function pad_right(text, width)
	text = clip_text(text or "", width)
	local pad = math.max(0, width - display_width(text))
	return text .. string.rep(" ", pad)
end

local function header_line(left, right, inner)
	local gap = math.max(1, inner - display_width(left) - display_width(right))
	return "│" .. left .. string.rep(" ", gap) .. right .. "│"
end

local function layout_width(width, max_width)
	local available = math.max(30, tonumber(width) or 78)
	local inner = math.max(28, available - 2)
	if max_width then
		inner = math.min(max_width, inner)
	end
	local prefix = string.rep(" ", math.max(0, math.floor((available - inner - 2) / 2)))
	return inner, prefix
end

local function fmt_num(n)
	n = tonumber(n)
	if not n then
		return "?"
	end
	local s = tostring(math.floor(n))
	local rev = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if rev:sub(1, 1) == "," then
		rev = rev:sub(2)
	end
	return rev
end

local function progress_bar(current, total, width)
	width = math.max(1, tonumber(width) or 1)
	local c = tonumber(current) or 0
	local t = tonumber(total) or 0
	if t <= 0 then
		return string.rep("░", width)
	end
	local filled = math.floor(math.max(0, math.min(1, c / t)) * width + 0.5)
	return string.rep("█", filled) .. string.rep("░", math.max(0, width - filled))
end

local function short_time(iso)
	if type(iso) ~= "string" then
		return "synced --:--"
	end
	local h, m = iso:match("T(%d%d):(%d%d)")
	if h and m then
		return "synced " .. h .. ":" .. m
	end
	return "synced " .. iso
end

local function short_time_full(iso)
	if type(iso) ~= "string" then
		return "synced unknown"
	end
	local d, h, m = iso:match("^(%d%d%d%d%-%d%d%-%d%d)T(%d%d):(%d%d)")
	if d and h and m then
		return "synced " .. d .. " " .. h .. ":" .. m
	end
	return "synced " .. iso
end

local function condense_flags(restaurant)
	local flags = {}
	if restaurant.current_theme_id then
		table.insert(flags, "theme " .. restaurant.current_theme_id)
	end
	if restaurant.notifications_enabled == true then
		table.insert(flags, "notifs on")
	end
	if restaurant.migrated == true then
		table.insert(flags, "migrated")
	end
	if restaurant.show_profile_bar_progress == true or restaurant.show_profile_page_progress == true then
		table.insert(flags, "progress on")
	end
	if restaurant.show_profile_bar_progress == true and restaurant.show_profile_page_progress == true then
		table.insert(flags, "profile page+bar")
	end
	if #flags == 0 then
		return "default settings"
	end
	return table.concat(flags, " · ")
end

local function abbreviate_path(path, max_width)
	path = tostring(path or "unknown")
	if display_width(path) <= max_width then
		return path
	end
	local file = path:match("([^/]+)$") or path
	if path:find("1011095603", 1, true) then
		local short = "…/1011095603/…/" .. file
		if display_width(short) <= max_width then
			return short
		end
	end
	return clip_text(path, max_width)
end

local function wrap_text(text, width)
	local out = {}
	local line = ""
	for _, part in ipairs(vim.split(tostring(text or ""), "/", { plain = true })) do
		local seg = (line == "" and part) or (line .. "/" .. part)
		if display_width(seg) <= width then
			line = seg
		else
			if line ~= "" then
				table.insert(out, line)
			end
			line = part
		end
	end
	if line ~= "" then
		table.insert(out, line)
	end
	if #out == 0 then
		return { "" }
	end
	return out
end

local function parse_date(date)
	local y, m, d = tostring(date or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
	if not y then
		return nil
	end
	return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
end

local function date_key(time)
	return os.date("%Y-%m-%d", time)
end

local function month_label(time)
	return os.date("%b", time)
end

local function activity_heatmap(activity, width)
	local items = activity and activity.items or {}
	if type(items) ~= "table" or #items == 0 then
		return { "   Activity data unavailable in Onigiri JSON." }
	end

	local by_date = {}
	local max_count = 0
	local end_time = 0
	for _, item in ipairs(items) do
		local time = parse_date(item.date)
		local count = tonumber(item.count) or 0
		if time then
			local key = date_key(time)
			by_date[key] = count
			max_count = math.max(max_count, count)
			end_time = math.max(end_time, time)
		end
	end
	if end_time == 0 then
		return { "   Activity data unavailable in Onigiri JSON." }
	end

	local weeks = math.max(4, math.min(13, math.floor((width - 10) / 2)))
	local start_time = end_time - ((weeks * 7) - 1) * 86400
	local rows = {}
	local month_line = string.rep(" ", weeks * 2 - 1)
	local last_month = nil
	for week = 0, weeks - 1 do
		local label = month_label(start_time + (week * 7 * 86400))
		if label ~= last_month then
			local col = week * 2 + 1
			if col + #label - 1 <= #month_line then
				month_line = month_line:sub(1, col - 1) .. label .. month_line:sub(col + #label)
			end
			last_month = label
		end
	end
	table.insert(rows, "      " .. month_line)
	local labels = { "M", "T", "W", "T", "F", "S", "S" }
	for day = 0, 6 do
		local cells = {}
		for week = 0, weeks - 1 do
			local count = by_date[date_key(start_time + ((week * 7 + day) * 86400))] or 0
			local cell = "·"
			if max_count > 0 and count > 0 then
				local level = math.ceil((count / max_count) * 4)
				cell = ({ "░", "▒", "▓", "█" })[math.max(1, math.min(4, level))]
			end
			table.insert(cells, cell)
		end
		table.insert(rows, "   " .. labels[day + 1] .. "  " .. table.concat(cells, " "))
	end
	return rows
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
		"╭──────────────────────────────────────────────╮",
		"│  Onigiri dashboard unavailable              │",
		"╰──────────────────────────────────────────────╯",
		"",
		"Reason: " .. reason_text,
		"",
		"Configure:",
		":AnkiReviewOnigiriPath /path/to/gamification_PROFILE.json",
		"",
		"Expected file:",
		"Anki2/addons21/1011095603/user_files/gamification_<profile>.json",
		"",
		"[q] close",
	}
end

local function dashboard_lines(context)
	context = context or {}
	local data = context.onigiri or onigiri.load()
	if not data.ok then
		return setup_lines(data)
	end

	local inner, prefix = layout_width(context.width, 72)
	local hero_inner = math.max(24, math.min(58, inner - 2))
	local bar_width = math.max(8, math.min(24, hero_inner - 24))
	local restaurant = data.restaurant or {}

	local top = prefix .. "╭" .. string.rep("─", inner) .. "╮"
	local head = prefix .. header_line("  🍙 Onigiri Companion", "Lv. " .. value(restaurant.level) .. "  ● Live ", inner)
	local bot = prefix .. "╰" .. string.rep("─", inner) .. "╯"

	local lines = {
		top,
		head,
		bot,
		"",
		prefix .. "── Activity " .. string.rep("─", math.max(2, inner - 13)),
	}

	for _, line in ipairs(activity_heatmap(context.activity or data.activity, inner)) do
		table.insert(lines, prefix .. line)
	end
	table.insert(lines, "")
	table.insert(lines, prefix .. "   ↻ " .. short_time(data.last_updated) .. "  󰉋 " .. abbreviate_path(data.path, inner - 20))
	table.insert(lines, "")
	table.insert(lines, prefix .. "   [s] stats    [r] refresh    [q] close")
	return lines
end

local function stats_lines(context)
	context = context or {}
	local data = context.onigiri or onigiri.load()
	if not data.ok then
		return setup_lines(data)
	end

	local inner, prefix = layout_width(context.width, 72)
	local card_inner = math.max(24, inner - 4)
	local bar_width = math.max(10, math.min(30, card_inner - 24))
	local restaurant = data.restaurant or {}
	local achievements = data.achievements or {}
	local daily_specials = data.daily_specials or {}
	local xp = tonumber(restaurant.total_xp) or 0

	local top = prefix .. "╭" .. string.rep("─", inner) .. "╮"
	local head = prefix .. header_line("  🍙 Onigiri · Stats", "● Live ", inner)
	local bot = prefix .. "╰" .. string.rep("─", inner) .. "╯"
	local function thin_top()
		return prefix .. "  ┌" .. string.rep("─", card_inner) .. "┐"
	end
	local function thin_bot()
		return prefix .. "  └" .. string.rep("─", card_inner) .. "┘"
	end
	local function thin_line(text)
		return prefix .. "  │ " .. pad_right(text, card_inner - 2) .. " │"
	end

	local lines = {
		top,
		head,
		bot,
		"",
		thin_top(),
		thin_line("RESTAURANT  Lv. " .. value(restaurant.level) .. "                     " .. fmt_num(xp) .. " XP"),
		thin_line(""),
		thin_line("XP  " .. progress_bar(xp, xp, bar_width) .. "  " .. fmt_num(xp) .. " / " .. fmt_num(xp)),
		thin_line(""),
		thin_line("🪙 " .. value(restaurant.taiyaki_coins) .. " taiyaki                 theme: " .. value(restaurant.current_theme_id)),
		thin_bot(),
		"",
		prefix .. "  ── Daily Specials " .. string.rep("─", math.max(2, inner - 20)),
		"",
	}

	for _, item in ipairs(daily_specials.items or {}) do
		local target = tonumber(item.target_cards) or 0
		local done = tonumber(item.cards_completed) or 0
		table.insert(lines, thin_top())
		table.insert(lines, thin_line("✦ " .. clip_text(value(item.name or item.id), math.max(10, card_inner - 8)) .. "   " .. (item.completed and "✔" or "·")))
		table.insert(lines, thin_line(""))
		table.insert(lines, thin_line("progress  " .. progress_bar(done, math.max(target, 1), math.max(8, math.min(30, card_inner - 20))) .. "  " .. done .. "/" .. target))
		table.insert(lines, thin_line("target " .. target .. "    done " .. done .. "    +" .. value(item.xp_earned) .. " XP"))
		table.insert(lines, thin_bot())
		table.insert(lines, "")
	end
	if #(daily_specials.items or {}) == 0 then
		table.insert(lines, prefix .. "   No specials yet today. Keep studying to reveal one! 🎌")
	end

	table.insert(lines, "")
	table.insert(lines, prefix .. "  ── Achievements " .. string.rep("─", math.max(2, inner - 19)))
	table.insert(lines, "")
	local unlocked = {}
	for _, item in ipairs(achievements.items or {}) do
		if item.unlocked then
			table.insert(unlocked, item)
		end
	end
	if #unlocked > 0 then
		for _, item in ipairs(unlocked) do
			table.insert(lines, prefix .. "   ✔ " .. clip_text(value(item.name or item.id) .. "  " .. value(item.description), inner - 3))
		end
	else
		table.insert(lines, prefix .. "   No achievements unlocked yet.")
		table.insert(lines, prefix .. "   Keep studying to earn your first! 🎌")
	end

	table.insert(lines, "")
	table.insert(lines, prefix .. "  ── Source " .. string.rep("─", math.max(2, inner - 12)))
	table.insert(lines, "")
	for _, p in ipairs(wrap_text(value(data.path), math.max(12, inner - 5))) do
		table.insert(lines, prefix .. "   " .. p)
	end
	table.insert(lines, prefix .. "   read-only · " .. short_time_full(data.last_updated))
	table.insert(lines, "")
	table.insert(lines, prefix .. "  " .. string.rep("─", math.max(2, inner - 2)))
	table.insert(lines, "")
	table.insert(lines, prefix .. "   [h] dashboard    [r] refresh    [q] close")
	return lines
end

local function render_lines(state)
	if state.view == "stats" then
		return stats_lines({ onigiri = state.onigiri, width = state.render_width })
	end
	return dashboard_lines({ onigiri = state.onigiri, activity = state.activity, width = state.render_width })
end

local function load_activity(data)
	if not data or not data.ok then
		return nil
	end
	if data.activity and type(data.activity.items) == "table" and #data.activity.items > 0 then
		return data.activity
	end
	local ok, activity = pcall(anki.review_activity_by_day)
	if ok and activity and type(activity.items) == "table" and #activity.items > 0 then
		return activity
	end
	return nil
end

local function add_highlights(state, lines)
	vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
	for i, line in ipairs(lines) do
		local row = i - 1
		if i == 1 then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewDashboardTitle", row, 0, -1)
		elseif line:find("🍙", 1, true) or line:find("── ", 1, true) then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewWidgetTitle", row, 0, -1)
		elseif line:find("[q]", 1, true) or line:find("[r]", 1, true) then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewHint", row, 0, -1)
		end
	end
end

local function render(state)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
	state.onigiri = onigiri.load()
	state.activity = load_activity(state.onigiri)
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
		render_width = dims.width,
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
	vim.keymap.set("n", "r", function()
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
