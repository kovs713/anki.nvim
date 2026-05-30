local M = {}

local function state_path()
	return vim.fn.stdpath("state") .. "/anki_review/state.json"
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

	return decoded
end

local function write_state(data)
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
	return write_state({ last_deck = data.last_deck })
end

function M._path()
	return state_path()
end

return M
