vim.opt.runtimepath:prepend(vim.fn.getcwd())
package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local failures = {}

local function test(name, fn)
	local ok, err = pcall(fn)
	if not ok then
		table.insert(failures, name .. ": " .. tostring(err))
	end
end

local function eq(actual, expected)
	if actual ~= expected then
		error(string.format("expected %s, got %s", vim.inspect(expected), vim.inspect(actual)), 2)
	end
end

local function assert_true(value, message)
	if not value then
		error(message or "expected truthy value", 2)
	end
end

local function with_preserved_file(path, fn)
	local existed = vim.fn.filereadable(path) == 1
	local old = existed and vim.fn.readfile(path) or nil
	local ok, err = pcall(fn)
	if existed then
		vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
		vim.fn.writefile(old, path)
	else
		vim.fn.delete(path)
	end
	if not ok then
		error(err, 2)
	end
end

local function with_temp_gamification_state(fn)
	local gamification = require("anki_review.gamification")
	local dir = vim.fn.tempname()
	vim.fn.delete(dir, "rf")
	gamification._set_state_dir_for_tests(dir)
	local ok, err = pcall(fn, gamification, dir)
	gamification._set_state_dir_for_tests(nil)
	vim.fn.delete(dir, "rf")
	if not ok then
		error(err, 2)
	end
end

local function with_anki_stubs(stubs, fn)
	local anki = require("anki_review.anki")
	local old = {}
	for name, stub in pairs(stubs) do
		old[name] = anki[name]
		anki[name] = stub
	end
	local ok, err = pcall(fn)
	for name, value in pairs(old) do
		anki[name] = value
	end
	if not ok then
		error(err, 2)
	end
end

test("strip_html removes markup and entities", function()
	local text = require("anki_review.text")
	local cleaned = text.strip_html("<div>Hello&nbsp;&amp;<br>world</div><script>x()</script>&hellip;&mdash;&ndash;")
	eq(cleaned, "Hello &\nworld\n...--")
end)

test("strip_html keeps media references", function()
	local text = require("anki_review.text")
	local cleaned = text.strip_html([[<p>[sound:voice.mp3]<br><img alt="x" src="pic.png"></p>]])
	eq(cleaned, "[audio: voice.mp3]\n[image: pic.png]")
end)

test("card_text sorts fields and strips html", function()
	local text = require("anki_review.text")
	local question, answer = text.card_text({
		fields = {
			Back = { value = "<b>Answer</b>", order = 1 },
			Front = { value = "<i>Question</i>", order = 0 },
			Extra = { value = "&lt;hint&gt;", order = 2 },
		},
	})
	eq(question, "Question")
	eq(answer, "Answer\n<hint>")
end)

test("window_size fits tiny editor", function()
	local ui = require("anki_review.ui")
	local old_columns = vim.o.columns
	local old_lines = vim.o.lines
	local old_cmdheight = vim.o.cmdheight
	vim.o.columns = 20
	vim.o.lines = 8
	vim.o.cmdheight = 1

	local size = ui._window_size()
	assert_true(size.width <= vim.o.columns, "width exceeds editor")
	assert_true(size.height <= vim.o.lines - vim.o.cmdheight, "height exceeds editor")
	assert_true(size.width >= 1, "width too small")
	assert_true(size.height >= 1, "height too small")

	vim.o.columns = old_columns
	vim.o.lines = old_lines
	vim.o.cmdheight = old_cmdheight
end)

test("open creates working resize autocmd and close clears it", function()
	local ui = require("anki_review.ui")
	local state = {
		current_card = { question = "q", answer = "a" },
		showing_answer = false,
		started_at = os.time(),
		session_started_at = os.time(),
		stats = { answered = 0, ease = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 } },
	}
	local closed = false
	ui.open(state, {
		show_answer = function() end,
		answer = function() end,
		focus_section = function() end,
		next_section = function() end,
		prev_section = function() end,
		toggle_help = function() end,
		close = function() end,
		closed = function()
			closed = true
		end,
	})
	ui.render(state)
	assert_true(state.win and vim.api.nvim_win_is_valid(state.win), "window not opened")
	assert_true(state.augroup, "augroup not tracked")
	assert_true(state.autocmds and #state.autocmds == 2, "autocmds not tracked")

	vim.api.nvim_exec_autocmds("VimResized", {})
	assert_true(vim.api.nvim_win_is_valid(state.win), "resize closed window")
	ui.close(state)
	eq(state.win, nil)
	eq(state.buf, nil)
	eq(state.autocmds, nil)
	local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "AnkiReviewUI" })
	assert_true(not ok or #autocmds == 0, "resize autocmd leaked")
	eq(closed, false)
end)

test("answer help follows displayed answer order", function()
	local ui = require("anki_review.ui")
	local state = {
		buf = vim.api.nvim_create_buf(false, true),
		current_card = {
			question = "q",
			answer = "a",
			buttons = { 1, 2, 3, 4 },
		},
		deck = "d",
		showing_answer = true,
		show_help = true,
		started_at = os.time(),
		session_started_at = os.time(),
		stats = { answered = 0, ease = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 } },
	}

	ui.render(state)
	local rendered = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
	local again = rendered:find("1 Again", 1, true)
	local hard = rendered:find("2 Hard", 1, true)
	local good = rendered:find("3 Good", 1, true)
	local easy = rendered:find("4 Easy", 1, true)
	local alias_again = rendered:find("<S%-BS>/<S%-Del>=Again")
	local alias_hard = rendered:find("<BS>/<Del>=Hard", 1, true)
	local alias_good = rendered:find("<CR>=Good", 1, true)
	local alias_easy = rendered:find("<S%-CR>=Easy")

	assert_true(again and hard and good and easy and again < hard and hard < good and good < easy)
	assert_true(alias_again and alias_hard and alias_good and alias_easy, "missing alias help")
	assert_true(
		alias_again < alias_hard and alias_hard < alias_good and alias_good < alias_easy,
		"alias order mismatch"
	)
	assert_true(not rendered:find("1=Again", 1, true), "duplicated answer labels")
	vim.api.nvim_buf_delete(state.buf, { force = true })
end)

test("setup merges config", function()
	local anki_review = require("anki_review")
	local config = require("anki_review.config")
	anki_review.setup({
		endpoint = "http://example.test:8765",
		timeout = 123,
		window = { width = 0.5 },
		default_ease = 4,
		gamification = { xp = { good = 15 } },
		dashboard = { activity_days = 9 },
	})

	local opts = config.get()
	eq(opts.anki.endpoint, "http://example.test:8765")
	eq(opts.anki.timeout, 123)
	eq(opts.behavior.remember_last_deck, true)
	eq(opts.window.width, 0.5)
	eq(opts.window.height, 0.7)
	eq(opts.behavior.default_ease, 4)
	eq(opts.gamification.enabled, true)
	eq(opts.gamification.xp.good, 15)
	eq(opts.gamification.xp.easy, 12)
	eq(opts.dashboard.activity_days, 9)
	eq(opts.dashboard.width, 0.75)
	assert_true(vim.fn.hlexists("AnkiReviewTitle") == 1, "missing title highlight")
	config.setup()
end)

test("partial gamification config keeps nested defaults", function()
	local config = require("anki_review.config")
	config.setup({ gamification = { enabled = false } })
	local opts = config.get()
	eq(opts.gamification.enabled, false)
	eq(opts.gamification.xp.again, 3)
	eq(opts.gamification.xp.good, 10)
	eq(opts.gamification.streak.enabled, true)
	eq(opts.dashboard.width, 0.75)
	eq(opts.window.width, 0.7)
	config.setup()
end)

test("gamification loads missing state", function()
	with_temp_gamification_state(function(gamification)
		local state = gamification.load()
		eq(state.version, 1)
		eq(state.xp, 0)
		eq(state.level, 1)
		eq(state.totals.cards_answered, 0)
		eq(state.streak.last_review_date, nil)
	end)
end)

test("gamification ignores corrupt state", function()
	with_temp_gamification_state(function(gamification)
		vim.fn.mkdir(vim.fn.fnamemodify(gamification.path(), ":h"), "p")
		vim.fn.writefile({ "{" }, gamification.path())
		local state = gamification.load()
		eq(state.xp, 0)
		eq(state.level, 1)
		eq(state.streak.last_review_date, nil)
	end)
end)

test("gamification save after corrupt restores valid schema", function()
	local config = require("anki_review.config")
	config.setup()
	with_temp_gamification_state(function(gamification)
		vim.fn.mkdir(vim.fn.fnamemodify(gamification.path(), ":h"), "p")
		vim.fn.writefile({ "{" }, gamification.path())
		local result = gamification.record_answer({ ease = 3, date = "2026-05-30", card_id = 1, timestamp = 100 })
		eq(result.recorded, true)
		local decoded = vim.json.decode(table.concat(vim.fn.readfile(gamification.path()), "\n"))
		eq(decoded.version, 1)
		eq(decoded.xp, 10)
		eq(decoded.streak.last_review_date, "2026-05-30")
	end)
end)

test("gamification save creates missing state dir", function()
	local config = require("anki_review.config")
	config.setup()
	with_temp_gamification_state(function(gamification, dir)
		eq(vim.fn.isdirectory(dir), 0)
		local ok = gamification.save(gamification.default_state())
		eq(ok, true)
		eq(vim.fn.isdirectory(dir), 1)
		eq(vim.fn.filereadable(gamification.path()), 1)
	end)
end)

test("gamification normalizes partial wrong state", function()
	local gamification = require("anki_review.gamification")
	local state = gamification._normalize_state({
		version = "bad",
		xp = "400.9",
		level = "999",
		streak = { current = "2", best = false, last_review_date = 123 },
		totals = { cards_answered = "7", good = "nope", review_seconds = -5 },
		daily = { ["2026-05-30"] = { cards = "15", good = "9", xp = "90" }, bad = "value" },
		achievements = "bad",
		imports = { "manual-future" },
	})
	eq(state.version, 1)
	eq(state.xp, 400)
	eq(state.level, 3)
	eq(state.streak.current, 2)
	eq(state.streak.best, 0)
	eq(state.streak.last_review_date, nil)
	eq(state.totals.cards_answered, 7)
	eq(state.totals.good, 0)
	eq(state.totals.review_seconds, 0)
	eq(state.daily["2026-05-30"].cards, 15)
	eq(state.daily["2026-05-30"].good, 9)
	eq(state.daily["2026-05-30"].xp, 90)
	eq(state.daily.bad, nil)
	eq(#state.achievements, 0)
	eq(state.imports[1], "manual-future")
end)

test("gamification writes only under state path", function()
	local gamification = require("anki_review.gamification")
	gamification._set_state_dir_for_tests(nil)
	local path = gamification.path()
	assert_true(path:find(vim.fn.stdpath("state"), 1, true) == 1, "not under stdpath state")
	assert_true(not path:find(vim.fn.getcwd(), 1, true), "path is under plugin root")
end)

test("gamification records xp by ease", function()
	local config = require("anki_review.config")
	config.setup()
	with_temp_gamification_state(function(gamification)
		gamification.reset_duplicate_guard()
		eq(gamification.record_answer({ ease = 1, date = "2026-05-30", card_id = 1, timestamp = 1 }).xp, 3)
		eq(gamification.record_answer({ ease = 2, date = "2026-05-30", card_id = 2, timestamp = 2 }).xp, 6)
		eq(gamification.record_answer({ ease = 3, date = "2026-05-30", card_id = 3, timestamp = 3 }).xp, 10)
		eq(gamification.record_answer({ ease = 4, date = "2026-05-30", card_id = 4, timestamp = 4 }).xp, 12)
		local state = gamification.load()
		eq(state.xp, 31)
		eq(state.totals.again, 1)
		eq(state.totals.hard, 1)
		eq(state.totals.good, 1)
		eq(state.totals.easy, 1)
		eq(state.daily["2026-05-30"].cards, 4)
	end)
end)

test("disabled gamification records nothing", function()
	local config = require("anki_review.config")
	config.setup({ gamification = { enabled = false } })
	with_temp_gamification_state(function(gamification)
		local result = gamification.record_answer({ ease = 3, date = "2026-05-30", card_id = 1, timestamp = 100 })
		eq(result.recorded, false)
		eq(result.disabled, true)
		local session_result = gamification.record_session()
		eq(session_result.recorded, false)
		eq(session_result.disabled, true)
		eq(vim.fn.filereadable(gamification.path()), 0)
	end)
	config.setup()
end)

test("streak increments for yesterday and resets older", function()
	local gamification = require("anki_review.gamification")
	local first = gamification.update_streak({ current = 0, best = 0 }, "2026-05-30")
	eq(first.current, 1)
	eq(first.best, 1)
	local second = gamification.update_streak(first, "2026-05-31")
	eq(second.current, 2)
	eq(second.best, 2)
	local reset = gamification.update_streak(second, "2026-06-03")
	eq(reset.current, 1)
	eq(reset.best, 2)
end)

test("streak does not increment twice in one day", function()
	local gamification = require("anki_review.gamification")
	local first = gamification.update_streak({ current = 2, best = 3, last_review_date = "2026-05-30" }, "2026-05-30")
	eq(first.current, 2)
	eq(first.best, 3)
	eq(first.last_review_date, "2026-05-30")
end)

test("level calculation works", function()
	local gamification = require("anki_review.gamification")
	eq(gamification.level_for_xp(0), 1)
	eq(gamification.level_for_xp(99), 1)
	eq(gamification.level_for_xp(100), 2)
	eq(gamification.level_for_xp(400), 3)
	eq(gamification.level_for_xp(900), 4)
end)

test("xp progress calculation works", function()
	local gamification = require("anki_review.gamification")
	local progress = gamification.level_progress(430)
	eq(progress.current_level, 3)
	eq(progress.current_level_start_xp, 400)
	eq(progress.next_level_start_xp, 900)
	eq(progress.xp_into_level, 30)
	eq(progress.xp_needed_for_next_level, 500)
end)

test("activity symbol maps card counts", function()
	local gamification = require("anki_review.gamification")
	local symbol
	symbol = gamification.activity_symbol(0)
	eq(symbol, "·")
	symbol = gamification.activity_symbol(1)
	eq(symbol, "░")
	symbol = gamification.activity_symbol(5)
	eq(symbol, "▒")
	symbol = gamification.activity_symbol(15)
	eq(symbol, "▓")
	symbol = gamification.activity_symbol(30)
	eq(symbol, "█")
end)

test("dashboard render lines handle empty state", function()
	local config = require("anki_review.config")
	config.setup()
	local dashboard = require("anki_review.dashboard")
	local lines = dashboard._render_lines({ gamification = require("anki_review.gamification").default_state() })
	assert_true(#lines > 0, "empty dashboard")
	assert_true(table.concat(lines, "\n"):find("Level", 1, true), "missing level")
end)

test("dashboard render handles disabled gamification", function()
	local config = require("anki_review.config")
	local dashboard = require("anki_review.dashboard")
	config.setup({ gamification = { enabled = false } })
	local lines = dashboard._render_lines({ gamification = require("anki_review.gamification").default_state() })
	local rendered = table.concat(lines, "\n")
	assert_true(rendered:find("Gamification disabled", 1, true), "missing disabled message")
	assert_true(not rendered:find("Level 1", 1, true), "disabled dashboard still shows level")
	config.setup()
end)

test("review completion omits xp when gamification disabled", function()
	local config = require("anki_review.config")
	local ui = require("anki_review.ui")
	config.setup({ gamification = { enabled = false } })
	local state = {
		buf = vim.api.nvim_create_buf(false, true),
		complete = true,
		deck = "Deck",
		session_started_at = os.time(),
		stats = { answered = 1, xp = 10, ease = { [1] = 0, [2] = 0, [3] = 1, [4] = 0 } },
	}
	ui.render(state)
	local rendered = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
	assert_true(rendered:find("Gamification disabled", 1, true), "missing disabled completion note")
	assert_true(not rendered:find("XP gained", 1, true), "disabled completion shows xp")
	vim.api.nvim_buf_delete(state.buf, { force = true })
	config.setup()
end)

test("duplicate guard only blocks immediate same event", function()
	local config = require("anki_review.config")
	config.setup()
	with_temp_gamification_state(function(gamification)
		gamification.reset_duplicate_guard()
		local first = gamification.record_answer({ ease = 3, date = "2026-05-30", card_id = 42, timestamp = 100 })
		local second = gamification.record_answer({ ease = 3, date = "2026-05-30", card_id = 42, timestamp = 100 })
		local later = gamification.record_answer({ ease = 3, date = "2026-05-30", card_id = 42, timestamp = 101 })
		local different = gamification.record_answer({ ease = 3, date = "2026-05-30", card_id = 43, timestamp = 102 })
		local missing_id = gamification.record_answer({ ease = 3, date = "2026-05-30", timestamp = 102 })
		local missing_id_again = gamification.record_answer({ ease = 3, date = "2026-05-30", timestamp = 102 })
		eq(first.recorded, true)
		eq(second.recorded, false)
		eq(second.duplicate, true)
		eq(later.recorded, true)
		eq(different.recorded, true)
		eq(missing_id.recorded, true)
		eq(missing_id_again.recorded, true)
		eq(gamification.load().xp, 50)
	end)
end)

test("duplicate guard resets between sessions", function()
	local config = require("anki_review.config")
	config.setup()
	with_temp_gamification_state(function(gamification)
		gamification.reset_duplicate_guard()
		eq(gamification.record_answer({ ease = 3, date = "2026-05-30", card_id = 42, timestamp = 100 }).recorded, true)
		gamification.reset_duplicate_guard()
		eq(gamification.record_answer({ ease = 3, date = "2026-05-30", card_id = 42, timestamp = 100 }).recorded, true)
		eq(gamification.load().xp, 20)
	end)
end)

test("failed guiAnswerCard does not record xp", function()
	local config = require("anki_review.config")
	local session = require("anki_review.session")
	config.setup()
	with_temp_gamification_state(function(gamification)
		with_anki_stubs({
			start_review = function()
				return true, nil
			end,
			deck_stats = function()
				return { new_count = 0, learn_count = 0, review_count = 1 }, nil
			end,
			current_card = function()
				return { cardId = 99, buttons = { 1, 2, 3, 4 }, fields = { Front = { value = "q", order = 0 } } }, nil
			end,
			show_answer = function()
				return true, nil
			end,
			answer_card = function()
				return nil, "answer failed"
			end,
		}, function()
			assert_true(session.start("Deck"), "session did not start")
			session.show_answer()
			session.answer(3)
			eq(vim.fn.filereadable(gamification.path()), 0)
			session.close()
		end)
	end)
end)

test("successful answer records xp before next-card failure", function()
	local config = require("anki_review.config")
	local session = require("anki_review.session")
	config.setup()
	with_temp_gamification_state(function(gamification)
		local current_calls = 0
		with_anki_stubs({
			start_review = function()
				return true, nil
			end,
			deck_stats = function()
				return { new_count = 0, learn_count = 0, review_count = 1 }, nil
			end,
			current_card = function()
				current_calls = current_calls + 1
				if current_calls <= 2 then
					return { cardId = 100, buttons = { 1, 2, 3, 4 }, fields = { Front = { value = "q", order = 0 } } }, nil
				end
				return nil, "next card failed"
			end,
			show_answer = function()
				return true, nil
			end,
			answer_card = function()
				return true, nil
			end,
		}, function()
			assert_true(session.start("Deck"), "session did not start")
			session.show_answer()
			session.answer(3)
			eq(gamification.load().xp, 10)
			session.close()
		end)
	end)
end)

test("anki request uses configured endpoint and timeout", function()
	local config = require("anki_review.config")
	local anki = require("anki_review.anki")
	local old_system = vim.system
	local command
	local timeout

	config.setup({ endpoint = "http://anki.test", timeout = 42 })
	vim.system = function(cmd)
		command = cmd
		return {
			wait = function(_, value)
				timeout = value
				return { code = 0, stdout = vim.json.encode({ result = 6 }) }
			end,
		}
	end

	local result, err = anki.version()
	eq(result, 6)
	eq(err, nil)
	eq(command[5], "http://anki.test")
	eq(timeout, 42)
	eq(anki.endpoint(), "http://anki.test")

	vim.system = old_system
	config.setup()
end)

test("state stores last deck and ignores corrupt json", function()
	local state = require("anki_review.state")
	local path = state._path()
	local existed = vim.fn.filereadable(path) == 1
	local old = existed and vim.fn.readfile(path) or nil

	state.set_last_deck("Japanese::Core")
	eq(state.last_deck(), "Japanese::Core")
	vim.fn.writefile({ "{" }, path)
	eq(state.last_deck(), nil)

	if existed then
		vim.fn.writefile(old, path)
	else
		vim.fn.delete(path)
	end
end)

test("picker selects last deck by default", function()
	local picker = require("anki_review.picker")
	local chosen
	picker.select(
		{ "Default", "Japanese::Core", "Other" },
		{ prompt = "Anki deck", selected = "Japanese::Core" },
		function(item)
			chosen = item
		end
	)

	local buf = vim.api.nvim_get_current_buf()
	local rendered = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
	assert_true(rendered:find("> Japanese::Core", 1, true), "selected deck not highlighted")
	vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
	eq(chosen, nil)
end)

if #failures > 0 then
	for _, failure in ipairs(failures) do
		io.stderr:write(failure .. "\n")
	end
	os.exit(1)
end

print("tests passed")
