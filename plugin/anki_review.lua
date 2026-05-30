vim.api.nvim_create_user_command("AnkiReview", function(opts)
	require("anki_review").command(opts.args, opts.bang)
end, { nargs = "*", bang = true })

vim.api.nvim_create_user_command("AnkiReviewHome", function()
	require("anki_review").home()
end, {})

vim.api.nvim_create_user_command("AnkiReviewStats", function()
	require("anki_review").stats()
end, {})
