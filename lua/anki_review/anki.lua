local M = {}

local config = require("anki_review.config")

function M.endpoint()
	return config.get().endpoint
end

function M.request(action, params)
	local opts = config.get()
	local payload = vim.json.encode({
		action = action,
		version = 6,
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

function M.deck_names()
	return M.request("deckNames")
end

function M.deck_stats(deck)
	local result, err = M.request("getDeckStats", { decks = { deck } })
	if err then
		return nil, err
	end

	return result and result[deck] or nil, nil
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

return M
