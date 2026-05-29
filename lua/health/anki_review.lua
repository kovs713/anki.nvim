local M = {}

local function health()
	local h = vim.health
	return {
		start = h.start or h.report_start,
		ok = h.ok or h.report_ok,
		warn = h.warn or h.report_warn,
		error = h.error or h.report_error,
		info = h.info or h.report_info,
	}
end

function M.check()
	local h = health()
	h.start("anki_review.nvim")

	if vim.system then
		h.ok("vim.system available")
	else
		h.error("vim.system missing", { "Use modern Neovim" })
	end

	if vim.fn.executable("curl") == 1 then
		h.ok("curl executable found")
	else
		h.error("curl executable missing", { "Install curl" })
		return
	end

	local ok, anki = pcall(require, "anki_review.anki")
	if not ok then
		h.error("Failed to load anki_review.anki", { tostring(anki) })
		return
	end

	h.info("AnkiConnect endpoint: " .. anki.endpoint())

	local version, err = anki.version()
	if err then
		h.error("AnkiConnect unreachable", {
			err,
			"Open Anki desktop app",
			"Install/enable AnkiConnect add-on 2055492159",
		})
		return
	end

	h.ok("AnkiConnect reachable")
	h.ok("AnkiConnect version: " .. tostring(version))
end

return M
