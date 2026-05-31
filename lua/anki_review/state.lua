local M = {}

local state_path_override = nil

local function state_path()
	if state_path_override then
		return state_path_override
	end
	return vim.fn.stdpath("state") .. "/anki_review/state.json"
end

local function trim(value)
	return type(value) == "string" and value:match("^%s*(.-)%s*$") or nil
end

local function normalize_state(data)
	data = type(data) == "table" and data or {}
	local normalized = {}
	local last_deck = trim(data.last_deck)
	if last_deck and last_deck ~= "" then
		normalized.last_deck = last_deck
	end

	if type(data.onigiri) == "table" then
		local path = trim(data.onigiri.gamification_path)
		if path and path ~= "" then
			normalized.onigiri = { gamification_path = path }
		end
	end
	return normalized
end

local function read_state()
	local path = state_path()
	if vim.fn.filereadable(path) ~= 1 then
		return {}
	end

	local ok, data = pcall(vim.fn.readfile, path)
	if not ok or #data == 0 then
		return {}
	end

	local decode_ok, decoded = pcall(vim.json.decode, table.concat(data, "\n"))
	if not decode_ok or type(decoded) ~= "table" then
		return {}
	end

	return normalize_state(decoded)
end

local function write_state(data)
	data = normalize_state(data)
	local path = state_path()
	local ok = pcall(function()
		vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
		vim.fn.writefile({ vim.json.encode(data) }, path)
	end)
	return ok
end

function M.last_deck()
	return read_state().last_deck
end

function M.set_last_deck(deck)
	if not deck or deck == "" then
		return
	end

	local data = read_state()
	data.last_deck = deck
	return write_state(data)
end

function M.onigiri_gamification_path()
	local onigiri = read_state().onigiri
	if type(onigiri) == "table" then
		return onigiri.gamification_path
	end
	return nil
end

function M.set_onigiri_gamification_path(path)
	path = trim(path)
	if not path or path == "" then
		return false
	end

	local data = read_state()
	data.onigiri = data.onigiri or {}
	data.onigiri.gamification_path = path
	return write_state(data)
end

function M.clear_onigiri_gamification_path()
	local data = read_state()
	data.onigiri = nil
	return write_state(data)
end

function M._path()
	return state_path()
end

function M._set_path_for_tests(path)
	state_path_override = path
end

return M
