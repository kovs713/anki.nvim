local config = require("anki_review.config")

local M = {}

local ease_names = {
	[1] = "again",
	[2] = "hard",
	[3] = "good",
	[4] = "easy",
}

local activity_symbols = {
	empty = "·",
	low = "░",
	medium = "▒",
	high = "▓",
	max = "█",
}

local state_dir_override = nil
local last_recorded_event = nil

local function default_day()
	return {
		cards = 0,
		again = 0,
		hard = 0,
		good = 0,
		easy = 0,
		xp = 0,
		review_seconds = 0,
	}
end

local function default_state()
	return {
		version = 1,
		xp = 0,
		level = 1,
		streak = {
			current = 0,
			best = 0,
			last_review_date = nil,
		},
		totals = {
			cards_answered = 0,
			again = 0,
			hard = 0,
			good = 0,
			easy = 0,
			sessions = 0,
			review_seconds = 0,
		},
		daily = {},
		achievements = {},
		imports = {},
	}
end

local function state_dir()
	if state_dir_override then
		return state_dir_override
	end
	return vim.fn.stdpath("state") .. "/anki_review"
end

local function state_path()
	return state_dir() .. "/gamification.json"
end

local function is_array(value)
	if type(value) ~= "table" then
		return false
	end
	if vim.islist then
		return vim.islist(value)
	end
	return vim.tbl_islist(value)
end

local function number_or(value, fallback)
	value = tonumber(value)
	if value == nil or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

local function valid_date(value)
	return type(value) == "string" and value:match("^%d%d%d%d%-%d%d%-%d%d$") ~= nil
end

local function normalize_day(day)
	local normalized = default_day()
	if type(day) ~= "table" then
		return normalized
	end

	for key in pairs(normalized) do
		normalized[key] = math.max(0, math.floor(number_or(day[key], normalized[key])))
	end
	return normalized
end

local function normalize_state(data)
	local state = default_state()
	if type(data) ~= "table" then
		return state
	end

	state.version = math.floor(number_or(data.version, 1))
	if state.version < 1 then
		state.version = 1
	end

	state.xp = math.max(0, math.floor(number_or(data.xp, 0)))
	state.level = M.level_for_xp(state.xp)

	if type(data.streak) == "table" then
		state.streak.current = math.max(0, math.floor(number_or(data.streak.current, 0)))
		state.streak.best = math.max(0, math.floor(number_or(data.streak.best, 0)))
		if type(data.streak.last_review_date) == "string" then
			state.streak.last_review_date = data.streak.last_review_date
		end
	end

	if type(data.totals) == "table" then
		for key in pairs(state.totals) do
			state.totals[key] = math.max(0, math.floor(number_or(data.totals[key], state.totals[key])))
		end
	end

	if type(data.daily) == "table" then
		for date, day in pairs(data.daily) do
			if valid_date(date) then
				state.daily[date] = normalize_day(day)
			end
		end
	end

	if is_array(data.achievements) then
		state.achievements = data.achievements
	end
	if is_array(data.imports) then
		state.imports = data.imports
	end

	return state
end

local function encode_state(state)
	local encoded = normalize_state(state)
	if encoded.streak.last_review_date == nil then
		encoded.streak.last_review_date = vim.NIL
	end
	return encoded
end

local function yesterday(date)
	if type(date) ~= "string" then
		return nil
	end
	local year, month, day = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not year then
		return nil
	end

	local time = os.time({
		year = tonumber(year),
		month = tonumber(month),
		day = tonumber(day),
		hour = 12,
	})
	if not time then
		return nil
	end
	return os.date("%Y-%m-%d", time - 86400)
end

local function xp_for_ease(ease)
	local name = ease_names[ease]
	if not name then
		return 0
	end

	local xp = ((config.get().gamification or {}).xp or {})[name]
	return math.max(0, math.floor(number_or(xp, 0)))
end

function M.path()
	return state_path()
end

function M.default_state()
	return default_state()
end

function M.load()
	local path = state_path()
	if vim.fn.filereadable(path) ~= 1 then
		return default_state()
	end

	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok or not lines or #lines == 0 then
		return default_state()
	end

	local decode_ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not decode_ok then
		return default_state()
	end

	return normalize_state(decoded)
end

function M.save(state)
	local normalized = normalize_state(state)
	local encoded = encode_state(normalized)
	local path = state_path()
	local tmp = path .. ".tmp"
	local ok = pcall(function()
		vim.fn.mkdir(state_dir(), "p")
		if vim.fn.writefile({ vim.json.encode(encoded) }, tmp) ~= 0 then
			error("failed to write gamification state")
		end
		if vim.fn.rename(tmp, path) ~= 0 then
			error("failed to replace gamification state")
		end
	end)
	if not ok then
		pcall(vim.fn.delete, tmp)
	end
	return ok, normalized
end

function M.level_for_xp(total_xp)
	total_xp = math.max(0, number_or(total_xp, 0))
	return math.floor(math.sqrt(total_xp / 100)) + 1
end

function M.level_progress(total_xp)
	total_xp = math.max(0, math.floor(number_or(total_xp, 0)))
	local current_level = M.level_for_xp(total_xp)
	local current_level_start_xp = ((current_level - 1) ^ 2) * 100
	local next_level_start_xp = (current_level ^ 2) * 100
	return {
		current_level = current_level,
		current_level_start_xp = current_level_start_xp,
		next_level_start_xp = next_level_start_xp,
		xp_into_level = total_xp - current_level_start_xp,
		xp_needed_for_next_level = next_level_start_xp - current_level_start_xp,
	}
end

function M.update_streak(streak, today)
	streak = type(streak) == "table" and vim.deepcopy(streak) or {}
	today = today or os.date("%Y-%m-%d")
	if not valid_date(today) then
		today = os.date("%Y-%m-%d")
	end

	local current = math.max(0, math.floor(number_or(streak.current, 0)))
	local best = math.max(0, math.floor(number_or(streak.best, 0)))
	local last = type(streak.last_review_date) == "string" and streak.last_review_date or nil

	if last == today then
		return {
			current = current,
			best = math.max(best, current),
			last_review_date = today,
		}
	end

	if last and last == yesterday(today) then
		current = current + 1
	else
		current = 1
	end

	return {
		current = current,
		best = math.max(best, current),
		last_review_date = today,
	}
end

function M.activity_symbol(cards)
	cards = math.max(0, math.floor(number_or(cards, 0)))
	if cards == 0 then
		return activity_symbols.empty, "AnkiReviewActivityEmpty"
	elseif cards <= 4 then
		return activity_symbols.low, "AnkiReviewActivityLow"
	elseif cards <= 14 then
		return activity_symbols.medium, "AnkiReviewActivityMedium"
	elseif cards <= 29 then
		return activity_symbols.high, "AnkiReviewActivityHigh"
	end
	return activity_symbols.max, "AnkiReviewActivityMax"
end

function M.day_offset(date, offset)
	if type(date) ~= "string" then
		return os.date("%Y-%m-%d")
	end
	local year, month, day = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not year then
		return date
	end

	local time = os.time({
		year = tonumber(year),
		month = tonumber(month),
		day = tonumber(day) + offset,
		hour = 12,
	})
	if not time then
		return date
	end
	return os.date("%Y-%m-%d", time)
end

function M.last_days(days, today)
	days = math.max(1, math.floor(number_or(days, 7)))
	today = today or os.date("%Y-%m-%d")
	local dates = {}
	for offset = days - 1, 0, -1 do
		table.insert(dates, M.day_offset(today, -offset))
	end
	return dates
end

function M.activity_strip(state, days, today)
	state = normalize_state(state)
	local strip = {}
	for _, date in ipairs(M.last_days(days, today)) do
		local day = state.daily[date] or default_day()
		local symbol, group = M.activity_symbol(day.cards)
		table.insert(strip, {
			date = date,
			cards = day.cards,
			symbol = symbol,
			hl = group,
		})
	end
	return strip
end

function M.record_answer(event)
	if (config.get().gamification or {}).enabled == false then
		return { recorded = false, disabled = true }
	end

	event = event or {}
	local ease = tonumber(event.ease)
	local name = ease_names[ease]
	if not name then
		return { recorded = false, invalid_ease = true }
	end

	local timestamp = math.floor(number_or(event.timestamp, os.time()))
	local card_id = event.card_id
	if card_id ~= nil then
		card_id = tostring(card_id)
		if
			last_recorded_event
			and last_recorded_event.card_id == card_id
			and last_recorded_event.ease == ease
			and last_recorded_event.timestamp == timestamp
		then
			return { recorded = false, duplicate = true }
		end
	end

	local date = valid_date(event.date) and event.date or os.date("%Y-%m-%d", timestamp)
	local elapsed = math.max(0, math.floor(number_or(event.elapsed, 0)))
	local gained = xp_for_ease(ease)
	local state = M.load()
	local day = normalize_day(state.daily[date])

	state.xp = state.xp + gained
	state.level = M.level_for_xp(state.xp)
	state.totals.cards_answered = state.totals.cards_answered + 1
	state.totals[name] = state.totals[name] + 1
	state.totals.review_seconds = state.totals.review_seconds + elapsed

	day.cards = day.cards + 1
	day[name] = day[name] + 1
	day.xp = day.xp + gained
	day.review_seconds = day.review_seconds + elapsed
	state.daily[date] = day

	if ((config.get().gamification or {}).streak or {}).enabled ~= false then
		state.streak = M.update_streak(state.streak, date)
	end

	local ok, saved = M.save(state)
	if card_id ~= nil and ok then
		last_recorded_event = {
			card_id = card_id,
			ease = ease,
			timestamp = timestamp,
		}
	end

	return {
		recorded = ok,
		xp = gained,
		ease = ease,
		streak = saved.streak.current,
		level = saved.level,
		state = saved,
	}
end

function M.record_session(seconds)
	if (config.get().gamification or {}).enabled == false then
		return { recorded = false, disabled = true }
	end

	local state = M.load()
	state.totals.sessions = state.totals.sessions + 1
	if seconds then
		state.totals.review_seconds = state.totals.review_seconds + math.max(0, math.floor(number_or(seconds, 0)))
	end
	local ok, saved = M.save(state)
	return { recorded = ok, state = saved }
end

function M.reset_duplicate_guard()
	last_recorded_event = nil
end

function M._normalize_state(state)
	return normalize_state(state)
end

function M._xp_for_ease(ease)
	return xp_for_ease(ease)
end

function M._set_state_dir_for_tests(path)
	state_dir_override = path
	M.reset_duplicate_guard()
end

function M._state_dir()
	return state_dir()
end

return M
