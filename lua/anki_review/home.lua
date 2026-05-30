local config = require("anki_review.config")
local persisted = require("anki_review.state")

local M = {}
local ns = vim.api.nvim_create_namespace("anki_review_home")

local function clamp(value, min, max)
	return math.min(math.max(value, min), max)
end

local function size()
	local columns = math.max(1, vim.o.columns)
	local lines = math.max(1, vim.o.lines - vim.o.cmdheight)
	local width = clamp(math.floor(columns * 0.58), 1, math.max(1, columns - 2))
	local height = clamp(18, 1, math.max(1, lines - 2))
	return {
		width = width,
		height = height,
		row = math.max(0, math.floor((lines - height) / 2)),
		col = math.max(0, math.floor((columns - width) / 2)),
	}
end

local function lines(show_help, show_health)
	local last_deck = persisted.last_deck()
	local opts = config.get()
	local output = {
		"anki.nvim 🃏",
		"Flashcards without leaving the cave",
		"",
		"r  review deck",
		"l  review last deck",
		"p  pick deck",
		"h  health info",
		"?  help",
		"q  quit",
		"",
		"Status",
		"AnkiConnect      unknown",
		"Endpoint         " .. opts.anki.endpoint,
		"Last deck        " .. (last_deck or "none"),
		"",
		"Integrations",
		"Review Heatmap   compatible via real Anki reviews",
	}

	if show_health then
		table.insert(output, "")
		table.insert(output, "Health")
		table.insert(output, "Run :checkhealth anki_review for live AnkiConnect checks.")
	end

	if show_help then
		table.insert(output, "")
		table.insert(output, "Help")
		table.insert(output, ":AnkiReview opens picker. :AnkiReview! starts last deck.")
		table.insert(output, "Anki must be open when reviewing through AnkiConnect.")
		table.insert(output, "Visual Anki add-ons do not render inside Neovim.")
	end

	return output
end

local function render(state)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	local output = lines(state.show_help, state.show_health)
	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, output)
	vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
	for i, line in ipairs(output) do
		if i == 1 then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewTitle", i - 1, 0, -1)
		elseif line == "Status" or line == "Integrations" or line == "Health" or line == "Help" then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewSection", i - 1, 0, -1)
		elseif line:match("^%w%s%s") or line:match("^%?") then
			vim.api.nvim_buf_add_highlight(state.buf, ns, "AnkiReviewHint", i - 1, 0, -1)
		end
	end
	vim.bo[state.buf].modifiable = false
end

local function close(state)
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
end

function M.open(actions)
	actions = actions or {}
	require("anki_review.ui").setup_highlights()

	local state = { show_help = false, show_health = false }
	local dims = size()
	state.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[state.buf].bufhidden = "wipe"
	vim.bo[state.buf].filetype = "anki_review_home"

	local ok, win = pcall(vim.api.nvim_open_win, state.buf, true, {
		relative = "editor",
		width = dims.width,
		height = dims.height,
		row = dims.row,
		col = dims.col,
		style = "minimal",
		border = config.get().window.border,
		focusable = true,
		zindex = 120,
	})
	if not ok then
		vim.api.nvim_buf_delete(state.buf, { force = true })
		vim.notify("AnkiReview: editor is too small for home window", vim.log.levels.ERROR)
		return
	end
	state.win = win

	local opts = { buffer = state.buf, noremap = true, silent = true, nowait = true }
	local function pick()
		close(state)
		if actions.pick_deck then
			actions.pick_deck()
		end
	end
	vim.keymap.set("n", "r", pick, opts)
	vim.keymap.set("n", "p", pick, opts)
	vim.keymap.set("n", "l", function()
		close(state)
		if actions.start_last then
			actions.start_last()
		end
	end, opts)
	vim.keymap.set("n", "h", function()
		state.show_health = not state.show_health
		render(state)
	end, opts)
	vim.keymap.set("n", "?", function()
		state.show_help = not state.show_help
		render(state)
	end, opts)
	vim.keymap.set("n", "q", function()
		close(state)
	end, opts)
	vim.keymap.set("n", "<Esc>", function()
		close(state)
	end, opts)

	render(state)
end

return M
