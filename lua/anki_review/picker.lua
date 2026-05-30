local M = {}
local config = require("anki_review.config")

local function clamp(value, min, max)
	return math.min(math.max(value, min), max)
end

local function render(state)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	local visible_count = math.max(1, state.height - 3)
	if state.index < state.offset then
		state.offset = state.index
	elseif state.index >= state.offset + visible_count then
		state.offset = state.index - visible_count + 1
	end

	local max_offset = math.max(1, #state.items - visible_count + 1)
	state.offset = clamp(state.offset, 1, max_offset)

	local prompt = string.format("%s (%d/%d)", state.prompt, state.index, #state.items)
	local lines = { prompt, "" }
	for i = state.offset, math.min(#state.items, state.offset + visible_count - 1) do
		local item = state.items[i]
		local prefix = i == state.index and "> " or "  "
		table.insert(lines, prefix .. item)
	end

	if state.offset + visible_count - 1 < #state.items then
		table.insert(lines, "  ...")
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

	local picker = config.get().picker or {}
	local columns = math.max(1, vim.o.columns)
	local lines = math.max(1, vim.o.lines - vim.o.cmdheight)
	local width = clamp(math.floor(columns * (picker.width or 0.5)), 1, math.max(1, columns - 2))
	local height = clamp(#items + 2, 1, math.max(1, math.floor(lines * (picker.height or 0.6))))
	local row = math.max(0, math.floor((lines - height) / 2))
	local col = math.max(0, math.floor((columns - width) / 2))
	local index = 1
	if opts.selected then
		for i, item in ipairs(items) do
			if item == opts.selected then
				index = i
				break
			end
		end
	end

	local state = {
		items = items,
		prompt = opts.prompt or "Select item",
		index = index,
		offset = 1,
		height = height,
		buf = vim.api.nvim_create_buf(false, true),
		win = nil,
	}

	vim.bo[state.buf].bufhidden = "wipe"
	vim.bo[state.buf].filetype = "anki_review_picker"

	local ok, win = pcall(vim.api.nvim_open_win, state.buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = config.get().window.border,
		focusable = true,
		zindex = 110,
	})
	if not ok then
		vim.api.nvim_buf_delete(state.buf, { force = true })
		vim.notify("AnkiReview: editor is too small for deck picker", vim.log.levels.ERROR)
		callback(nil)
		return
	end
	state.win = win

	local function move(delta)
		state.index = clamp(state.index + delta, 1, #state.items)
		render(state)
	end

	local function page(delta)
		state.index = clamp(state.index + delta * math.max(1, state.height - 4), 1, #state.items)
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
	vim.keymap.set("n", "<C-d>", function()
		page(1)
	end, keymap_opts)
	vim.keymap.set("n", "<C-u>", function()
		page(-1)
	end, keymap_opts)
	vim.keymap.set("n", "G", function()
		state.index = #state.items
		render(state)
	end, keymap_opts)
	vim.keymap.set("n", "gg", function()
		state.index = 1
		render(state)
	end, keymap_opts)
	vim.keymap.set("n", "<CR>", choose, keymap_opts)
	vim.keymap.set("n", "q", cancel, keymap_opts)
	vim.keymap.set("n", "<Esc>", cancel, keymap_opts)

	render(state)
end

return M
