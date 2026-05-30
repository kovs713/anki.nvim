local M = {}

local defaults = {
	endpoint = "http://127.0.0.1:8765",
	timeout = 5000,
	window = {
		width = 0.72,
		height = 0.72,
		min_width = 60,
		max_width = 110,
		min_height = 18,
		max_height = 34,
	},
	remember_last_deck = false,
	default_ease = 3,
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	return M.options
end

function M.get()
	return M.options
end

return M
