vim.api.nvim_create_user_command("AnkiReview", function(opts)
	require("anki_review").start(opts.args)
end, { nargs = "*" })
