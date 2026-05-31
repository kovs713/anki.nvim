local M = {}

local config = require("anki_review.config")

function M.endpoint()
	return config.get().anki.endpoint
end

function M.request(action, params)
	local opts = config.get().anki
	local payload = vim.json.encode({
		action = action,
		version = opts.version,
		params = params or vim.empty_dict(),
	})

	local result = vim.system({
		"curl",
		"-s",
		"-X",
		"POST",
		opts.endpoint,
		"-H",
		"Content-Type: application/json",
		"-d",
		payload,
	}):wait(opts.timeout)

	if not result then
		return nil, "AnkiConnect request timed out after " .. tostring(opts.timeout) .. "ms: " .. action
	end

	if result.code ~= 0 then
		return nil,
			"AnkiConnect is not reachable at "
				.. opts.endpoint
				.. ". Make sure Anki is running with AnkiConnect enabled."
	end

	if not result.stdout or result.stdout == "" then
		return nil, "AnkiConnect returned an empty response for " .. action .. "."
	end

	local ok, decoded = pcall(vim.json.decode, result.stdout)
	if not ok or not decoded then
		return nil, "Failed to parse AnkiConnect response for " .. action .. "."
	end

	if decoded.error and decoded.error ~= vim.NIL then
		return nil, tostring(decoded.error)
	end

	if decoded.result == vim.NIL then
		return nil, nil
	end

	return decoded.result, nil
end

function M.deck_names()
	return M.request("deckNames")
end

function M.deck_stats(deck)
	local result, err = M.request("getDeckStats", { decks = { deck } })
	if err then
		return nil, err
	end
	if type(result) ~= "table" then
		return nil, "invalid response shape"
	end
	for _, info in pairs(result) do
		if type(info) == "table" and info.name == deck then
			return {
				new_count = (info.new_count or 0),
				learn_count = (info.learn_count or 0),
				review_count = (info.review_count or 0),
				total_in_deck = (info.total_in_deck or 0),
			}, nil
		end
	end
	return nil, nil
end

function M.find_cards(query)
	return M.request("findCards", { query = query })
end

function M.future_due(deck_name)
	if not deck_name or deck_name == "" then
		return nil, "no deck"
	end
	local escaped = deck_name:gsub('\\', '\\\\'):gsub('"', '\\"')
	local tomorrow_query = string.format('deck:"%s" prop:due=1', escaped)
	local future_query = string.format('deck:"%s" prop:due>=1', escaped)

	local tomorrow_ids, tomorrow_err = M.find_cards(tomorrow_query)
	if tomorrow_err then
		return nil, tomorrow_err
	end
	local future_ids, future_err = M.find_cards(future_query)
	if future_err then
		return nil, future_err
	end
	return {
		tomorrow = type(tomorrow_ids) == "table" and #tomorrow_ids or 0,
		future = type(future_ids) == "table" and #future_ids or 0,
	}, nil
end

function M.review_counts(deck_name)
	local function rated_query(n)
		if deck_name then
			local escaped = deck_name:gsub('\\', '\\\\'):gsub('"', '\\"')
			return string.format('deck:"%s" rated:%d', escaped, n)
		end
		return string.format('rated:%d', n)
	end

	local today_ids, today_err = M.find_cards(rated_query(1))
	if today_err then
		return nil, today_err
	end
	local week_ids, week_err = M.find_cards(rated_query(7))
	if week_err then
		return nil, week_err
	end
	local month_ids, month_err = M.find_cards(rated_query(30))
	if month_err then
		return nil, month_err
	end
	return {
		today = type(today_ids) == "table" and #today_ids or 0,
		week = type(week_ids) == "table" and #week_ids or 0,
		month = type(month_ids) == "table" and #month_ids or 0,
	}, nil
end

function M.review_activity_by_day()
	local result, err = M.request("getNumCardsReviewedByDay")
	if err then
		return nil, err
	end
	if type(result) ~= "table" then
		return nil, "invalid response shape"
	end

	local items = {}
	for _, row in ipairs(result) do
		if type(row) == "table" then
			local date = row[1]
			local count = tonumber(row[2])
			if type(date) == "string" and count then
				table.insert(items, { date = date, count = count })
			end
		end
	end
	table.sort(items, function(a, b)
		return a.date < b.date
	end)
	return { items = items }, nil
end

function M.start_review(deck)
	return M.request("guiDeckReview", { name = deck })
end

function M.current_card()
	return M.request("guiCurrentCard")
end

function M.show_answer()
	return M.request("guiShowAnswer")
end

function M.answer_card(ease)
	return M.request("guiAnswerCard", { ease = ease })
end

function M.version()
	return M.request("version")
end

function M._escape_deck_name(name)
	return name:gsub('\\', '\\\\'):gsub('"', '\\"')
end

function M._future_query(deck_name, due_type)
	local escaped = M._escape_deck_name(deck_name)
	if due_type == "tomorrow" then
		return string.format('deck:"%s" prop:due=1', escaped)
	end
	return string.format('deck:"%s" prop:due>=1', escaped)
end

function M._review_query(deck_name, period)
	local escaped = deck_name and deck_name:gsub('\\', '\\\\'):gsub('"', '\\"')
	if period == "today" then
		if deck_name then
			return string.format('deck:"%s" rated:1', escaped)
		end
		return 'rated:1'
	elseif period == "week" then
		if deck_name then
			return string.format('deck:"%s" rated:7', escaped)
		end
		return 'rated:7'
	elseif period == "month" then
		if deck_name then
			return string.format('deck:"%s" rated:30', escaped)
		end
		return 'rated:30'
	end
	return 'rated:1'
end

return M
