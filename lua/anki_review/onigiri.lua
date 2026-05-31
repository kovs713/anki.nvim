local config = require("anki_review.config")
local persisted = require("anki_review.state")

local M = {}

local addon_pattern = "**/addons21/1011095603/user_files/gamification*.json"

local function is_list(value)
	if type(value) ~= "table" then
		return false
	end
	if vim.islist then
		return vim.islist(value)
	end
	return vim.tbl_islist(value)
end

local function string_or_nil(value)
	if type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

local function number_or_nil(value)
	value = tonumber(value)
	if value == nil or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function bool_or_nil(value)
	if type(value) == "boolean" then
		return value
	end
	return nil
end

local function list_or_empty(value)
	if not is_list(value) then
		return {}
	end

	local output = {}
	for _, item in ipairs(value) do
		table.insert(output, item)
	end
	return output
end

local function normalize_restaurant(value)
	value = type(value) == "table" and value or {}
	return {
		level = number_or_nil(value.level),
		total_xp = number_or_nil(value.total_xp),
		taiyaki_coins = number_or_nil(value.taiyaki_coins),
		owned_items = list_or_empty(value.owned_items),
		current_theme_id = string_or_nil(value.current_theme_id),
		name = string_or_nil(value.name),
		daily_special = type(value.daily_special) == "table" and vim.deepcopy(value.daily_special) or nil,
		migrated = bool_or_nil(value.migrated),
		enabled = bool_or_nil(value.enabled),
		notifications_enabled = bool_or_nil(value.notifications_enabled),
		show_profile_bar_progress = bool_or_nil(value.show_profile_bar_progress),
		show_profile_page_progress = bool_or_nil(value.show_profile_page_progress),
		last_updated = string_or_nil(value.last_updated),
	}
end

local function normalize_achievement(item)
	if type(item) ~= "table" then
		return nil
	end

	return {
		id = string_or_nil(item.id),
		name = string_or_nil(item.name),
		description = string_or_nil(item.description),
		category = string_or_nil(item.category),
		unlocked = bool_or_nil(item.unlocked),
		unlocked_date = string_or_nil(item.unlocked_date),
		progress = number_or_nil(item.progress),
		threshold = number_or_nil(item.threshold),
		repeatable = bool_or_nil(item.repeatable),
		count = number_or_nil(item.count),
		icon = string_or_nil(item.icon),
	}
end

local function normalize_daily_special(item)
	if type(item) ~= "table" then
		return nil
	end

	return {
		id = string_or_nil(item.id),
		name = string_or_nil(item.name),
		difficulty = string_or_nil(item.difficulty),
		target_cards = number_or_nil(item.target_cards),
		completed = bool_or_nil(item.completed),
		description = string_or_nil(item.description),
		completed_date = string_or_nil(item.completed_date),
		cards_completed = number_or_nil(item.cards_completed),
		xp_earned = number_or_nil(item.xp_earned),
	}
end

local function normalize_items(value, normalize_item)
	local items = {}
	if not is_list(value) then
		return items
	end

	for _, item in ipairs(value) do
		local normalized = normalize_item(item)
		if normalized then
			table.insert(items, normalized)
		end
	end
	return items
end

local function normalize(data, path)
	if type(data) ~= "table" or is_list(data) then
		return {
			ok = false,
			source = "onigiri",
			path = path,
			error = "invalid data",
		}
	end

	local restaurant = normalize_restaurant(data.restaurant_level)
	local achievements = normalize_items(data.achievements, normalize_achievement)
	local daily_specials = normalize_items(data.daily_specials, normalize_daily_special)
	local unlocked = 0
	for _, achievement in ipairs(achievements) do
		if achievement.unlocked then
			unlocked = unlocked + 1
		end
	end
	local completed = 0
	for _, special in ipairs(daily_specials) do
		if special.completed then
			completed = completed + 1
		end
	end

	return {
		ok = true,
		source = "onigiri",
		path = path,
		last_updated = string_or_nil(data.last_updated) or restaurant.last_updated,
		restaurant = restaurant,
		achievements = {
			total = #achievements,
			unlocked = unlocked,
			items = achievements,
		},
		daily_specials = {
			total = #daily_specials,
			completed = completed,
			items = daily_specials,
		},
	}
end

function M.configured_path()
	local opts = config.get()
	local configured = opts.onigiri and opts.onigiri.gamification_path
	if type(configured) == "string" and configured ~= "" then
		return vim.fn.expand(configured)
	end

	local cached = persisted.onigiri_gamification_path()
	if type(cached) == "string" and cached ~= "" then
		return vim.fn.expand(cached)
	end
	return nil
end

function M.load(path)
	local provider = ((config.get().gamification or {}).provider or "onigiri")
	if provider == "none" then
		return {
			ok = false,
			source = "onigiri",
			error = "disabled",
		}
	end

	path = path or M.configured_path()
	if type(path) ~= "string" or path == "" then
		return {
			ok = false,
			source = "onigiri",
			error = "path not configured",
		}
	end

	path = vim.fn.expand(path)
	if vim.fn.filereadable(path) ~= 1 then
		return {
			ok = false,
			source = "onigiri",
			path = path,
			error = "file not found",
		}
	end

	local read_ok, lines = pcall(vim.fn.readfile, path)
	if not read_ok or not lines then
		return {
			ok = false,
			source = "onigiri",
			path = path,
			error = "file not found",
		}
	end

	local decode_ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not decode_ok then
		return {
			ok = false,
			source = "onigiri",
			path = path,
			error = "invalid json",
		}
	end

	return normalize(decoded, path)
end

function M.status_label(data)
	if data and data.ok then
		return "connected"
	end
	local err = data and data.error or nil
	if err == "path not configured" then
		return "path missing"
	elseif err == "file not found" then
		return "file missing"
	elseif err == "invalid json" then
		return "invalid json"
	elseif err == "disabled" then
		return "disabled"
	end
	return "unavailable"
end

function M._normalize(data, path)
	return normalize(data, path)
end

local function add_unique(output, seen, path)
	if type(path) ~= "string" or path == "" then
		return
	end
	local expanded = vim.fn.expand(path)
	if seen[expanded] then
		return
	end
	if vim.fn.filereadable(expanded) == 1 then
		seen[expanded] = true
		table.insert(output, expanded)
	end
end

function M.default_base_paths()
	local paths = {
		"~/.local/share/Anki2",
		"~/.var/app/net.ankiweb.Anki/data/Anki2",
		"~/Library/Application Support/Anki2",
	}
	local appdata = vim.env.APPDATA
	if type(appdata) == "string" and appdata ~= "" then
		table.insert(paths, appdata .. "/Anki2")
	end
	return paths
end

function M.find_candidates(base_paths)
	local candidates = {}
	local seen = {}
	for _, base in ipairs(base_paths or M.default_base_paths()) do
		local expanded = vim.fn.expand(base)
		if vim.fn.isdirectory(expanded) == 1 then
			local matches = vim.fn.globpath(expanded, addon_pattern, false, true)
			for _, match in ipairs(matches or {}) do
				add_unique(candidates, seen, match)
			end
		end
	end
	table.sort(candidates)
	return candidates
end

return M
