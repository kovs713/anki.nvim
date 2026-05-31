local M = {}

local defaults = {
	anki = {
		endpoint = "http://127.0.0.1:8765",
		version = 6,
		timeout = 5000,
	},
	window = {
		width = 0.7,
		height = 0.7,
		min_width = 40,
		min_height = 12,
		border = "rounded",
	},
	picker = {
		width = 0.5,
		height = 0.6,
	},
	behavior = {
		remember_last_deck = true,
		default_ease = 3,
	},
	gamification = {
		provider = "onigiri",
	},
	onigiri = {
		gamification_path = nil,
		readonly = true,
	},
	dashboard = {
		enabled = true,
		width = 0.75,
		height = 0.75,
	},
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
	opts = opts or {}
	if opts.endpoint or opts.timeout or opts.version then
		opts.anki = vim.tbl_deep_extend("force", opts.anki or {}, {
			endpoint = opts.endpoint,
			version = opts.version,
			timeout = opts.timeout,
		})
		opts.endpoint = nil
		opts.version = nil
		opts.timeout = nil
	end
	if opts.remember_last_deck ~= nil or opts.default_ease ~= nil then
		opts.behavior = vim.tbl_deep_extend("force", opts.behavior or {}, {
			remember_last_deck = opts.remember_last_deck,
			default_ease = opts.default_ease,
		})
		opts.remember_last_deck = nil
		opts.default_ease = nil
	end
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	return M.options
end

function M.get()
	return M.options
end

return M
