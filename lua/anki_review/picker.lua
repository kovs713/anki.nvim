local M = {}

local function clamp(value, min, max)
	return math.min(math.max(value, min), max)
end

local function render(state)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	local lines = { state.prompt, "" }
	for i, item in ipairs(state.items) do
		local prefix = i == state.index and "> " or "  "
		table.insert(lines, prefix .. item)
	end

	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.bo[state.buf].modifiable = false
end

local function close(state)
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	state.win = nil
	state.buf = nil
end

function M.select(items, opts, callback)
	opts = opts or {}
	if not items or #items == 0 then
		callback(nil)
		return
	end

	local width = clamp(math.floor(vim.o.columns * 0.45), 30, 80)
	local height = clamp(#items + 2, 5, math.floor(vim.o.lines * 0.6))
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local state = {
		items = items,
		prompt = opts.prompt or "Select item",
		index = 1,
		buf = vim.api.nvim_create_buf(false, true),
		win = nil,
	}

	vim.bo[state.buf].bufhidden = "wipe"
	vim.bo[state.buf].filetype = "anki_review_picker"

	state.win = vim.api.nvim_open_win(state.buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		focusable = true,
		zindex = 110,
	})

	local function move(delta)
		state.index = clamp(state.index + delta, 1, #state.items)
		render(state)
	end

	local function choose()
		local item = state.items[state.index]
		close(state)
		callback(item)
	end

	local function cancel()
		close(state)
		callback(nil)
	end

	local keymap_opts = { buffer = state.buf, noremap = true, silent = true, nowait = true }
	vim.keymap.set("n", "j", function()
		move(1)
	end, keymap_opts)
	vim.keymap.set("n", "k", function()
		move(-1)
	end, keymap_opts)
	vim.keymap.set("n", "<Down>", function()
		move(1)
	end, keymap_opts)
	vim.keymap.set("n", "<Up>", function()
		move(-1)
	end, keymap_opts)
	vim.keymap.set("n", "<CR>", choose, keymap_opts)
	vim.keymap.set("n", "q", cancel, keymap_opts)
	vim.keymap.set("n", "<Esc>", cancel, keymap_opts)

	render(state)
end

return M
