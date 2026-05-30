vim.api.nvim_create_user_command("AnkiReview", function(opts)
	local anki_review = require("anki_review")
	if opts.bang then
		anki_review.start_last()
		return
	end

	anki_review.start(opts.args)
end, { nargs = "*", bang = true })

vim.api.nvim_create_user_command("AnkiReviewHome", function()
	require("anki_review").home()
end, {})

vim.api.nvim_create_user_command("AnkiReviewStats", function()
	require("anki_review").stats()
end, {})
