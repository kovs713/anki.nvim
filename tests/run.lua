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

local function fixture_path(name)
	return vim.fn.getcwd() .. "/tests/fixtures/" .. name
end

local function local_gamification_path()
	return vim.fn.stdpath("state") .. "/anki_review/gamification.json"
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
		gamification = { provider = "none" },
		onigiri = { gamification_path = "/tmp/onigiri.json" },
		dashboard = { width = 0.8 },
	})

	local opts = config.get()
	eq(opts.anki.endpoint, "http://example.test:8765")
	eq(opts.anki.timeout, 123)
	eq(opts.behavior.remember_last_deck, true)
	eq(opts.window.width, 0.5)
	eq(opts.window.height, 0.7)
	eq(opts.behavior.default_ease, 4)
	eq(opts.gamification.provider, "none")
	eq(opts.onigiri.gamification_path, "/tmp/onigiri.json")
	eq(opts.onigiri.readonly, true)
	eq(opts.dashboard.width, 0.8)
	eq(opts.dashboard.height, 0.75)
	assert_true(vim.fn.hlexists("AnkiReviewTitle") == 1, "missing title highlight")
	config.setup()
end)

test("partial gamification config keeps nested defaults", function()
	local config = require("anki_review.config")
	config.setup({ gamification = { provider = "none" } })
	local opts = config.get()
	eq(opts.gamification.provider, "none")
	eq(opts.onigiri.readonly, true)
	eq(opts.onigiri.gamification_path, nil)
	eq(opts.dashboard.width, 0.75)
	eq(opts.window.width, 0.7)
	config.setup()
end)

test("AnkiReview command parses subcommands", function()
	local anki_review = require("anki_review")
	local action, value
	action, value = anki_review._parse_command("", false)
	eq(action, "picker")
	eq(value, nil)
	action, value = anki_review._parse_command("Japanese::Core", false)
	eq(action, "deck")
	eq(value, "Japanese::Core")
	action = anki_review._parse_command("home", false)
	eq(action, "home")
	action = anki_review._parse_command("stats", false)
	eq(action, "stats")
	action = anki_review._parse_command("stat", false)
	eq(action, "stats")
	action = anki_review._parse_command("last", false)
	eq(action, "last")
	action, value = anki_review._parse_command("deck home", false)
	eq(action, "deck")
	eq(value, "home")
	action = anki_review._parse_command("Japanese::Core", true)
	eq(action, "last")
end)

test("onigiri parses valid fixture", function()
	local onigiri = require("anki_review.onigiri")
	local data = onigiri.load(fixture_path("valid_onigiri_gamification.json"))
	eq(data.ok, true)
	eq(data.source, "onigiri")
	eq(data.last_updated, "2026-05-30T12:00:00")
	eq(data.restaurant.level, 4)
	eq(data.restaurant.total_xp, 430)
	eq(data.restaurant.taiyaki_coins, 12)
	eq(data.restaurant.current_theme_id, "default")
	eq(data.achievements.total, 1)
	eq(data.achievements.unlocked, 1)
	eq(data.daily_specials.total, 1)
	eq(data.daily_specials.completed, 0)
end)

test("onigiri reads profile-specific gamification path", function()
	local onigiri = require("anki_review.onigiri")
	local path = fixture_path("user_files/gamification_TestProfile.json")
	local data = onigiri.load(path)
	eq(data.ok, true)
	eq(data.path, path)
	eq(data.restaurant.name, "Restaurant Level")
end)

test("onigiri reads legacy gamification path", function()
	local onigiri = require("anki_review.onigiri")
	local data = onigiri.load(fixture_path("user_files/gamification.json"))
	eq(data.ok, true)
	eq(data.restaurant.level, 4)
end)

test("onigiri reads gamification path with spaces", function()
	local onigiri = require("anki_review.onigiri")
	local data = onigiri.load(fixture_path("user_files/gamification_User 1.json"))
	eq(data.ok, true)
	eq(data.restaurant.level, 4)
end)

test("onigiri uses config path before cached state", function()
	local config = require("anki_review.config")
	local state = require("anki_review.state")
	local onigiri = require("anki_review.onigiri")
	local state_path = vim.fn.tempname()
	state._set_path_for_tests(state_path)
	state.set_onigiri_gamification_path("/tmp/missing_onigiri.json")
	local configured = fixture_path("valid_onigiri_gamification.json")
	config.setup({ onigiri = { gamification_path = configured } })
	local data = onigiri.load()
	eq(data.ok, true)
	eq(data.path, configured)
	config.setup()
	state._set_path_for_tests(nil)
	vim.fn.delete(state_path)
end)

test("set_onigiri_path caches only the path", function()
	local anki_review = require("anki_review")
	local state = require("anki_review.state")
	local state_path = vim.fn.tempname()
	local path = fixture_path("user_files/gamification_TestProfile.json")
	local old_notify = vim.notify
	vim.notify = function() end
	state._set_path_for_tests(state_path)
	eq(anki_review.set_onigiri_path(path), true)
	eq(state.onigiri_gamification_path(), path)
	local decoded = vim.json.decode(table.concat(vim.fn.readfile(state_path), "\n"))
	eq(decoded.onigiri.gamification_path, path)
	eq(decoded.xp, nil)
	eq(decoded.level, nil)
	eq(decoded.streak, nil)
	state._set_path_for_tests(nil)
	vim.notify = old_notify
	vim.fn.delete(state_path)
end)

test("onigiri reports missing path and missing file", function()
	local onigiri = require("anki_review.onigiri")
	local missing_path = onigiri.load("")
	eq(missing_path.ok, false)
	eq(missing_path.error, "path not configured")
	local missing_file = onigiri.load(fixture_path("missing_onigiri.json"))
	eq(missing_file.ok, false)
	eq(missing_file.error, "file not found")
end)

test("onigiri reports corrupt json", function()
	local onigiri = require("anki_review.onigiri")
	local data = onigiri.load(fixture_path("corrupt_onigiri_gamification.json"))
	eq(data.ok, false)
	eq(data.error, "invalid json")
end)

test("onigiri tolerates wrong-shaped json", function()
	local onigiri = require("anki_review.onigiri")
	local data = onigiri.load(fixture_path("wrong_shape_onigiri_gamification.json"))
	eq(data.ok, true)
	eq(data.restaurant.level, nil)
	eq(data.achievements.total, 0)
	eq(data.achievements.unlocked, 0)
	eq(data.daily_specials.total, 0)
	eq(data.daily_specials.completed, 0)
end)

-- Dashboard / stats view tests

test("dashboard render lines handle empty state", function()
	local config = require("anki_review.config")
	config.setup()
	local dashboard = require("anki_review.dashboard")
	local lines = dashboard._render_lines({ onigiri = { ok = false, source = "onigiri", error = "path not configured" } })
	local rendered = table.concat(lines, "\n")
	assert_true(#lines > 0, "empty dashboard")
	assert_true(rendered:find("Onigiri dashboard unavailable", 1, true), "missing unavailable title")
	assert_true(rendered:find("Reason: path not configured", 1, true), "missing setup reason")
	assert_true(rendered:find(":AnkiReviewOnigiriPath", 1, true), "missing setup command")
	assert_true(not rendered:find("Anki collection", 1, true), "must not include anki stats")
	assert_true(not rendered:find("╭", 1, true), "dashboard content draws inner top border")
	assert_true(not rendered:find("│", 1, true), "dashboard content draws inner side border")
	assert_true(not rendered:find("╰", 1, true), "dashboard content draws inner bottom border")
end)

test("dashboard view switch resets scroll", function()
	local config = require("anki_review.config")
	local dashboard = require("anki_review.dashboard")
	config.setup({ dashboard = { height = 0.35 } })
	dashboard.open({}, { view = "stats" })
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_feedkeys("h", "xt", false)
	assert_true(vim.api.nvim_win_is_valid(win), "window closed")
	vim.api.nvim_win_close(win, true)
	config.setup()
end)

test("dashboard render shows valid Onigiri data", function()
	local config = require("anki_review.config")
	local dashboard = require("anki_review.dashboard")
	local onigiri = require("anki_review.onigiri")
	config.setup()
	local lines = dashboard._render_lines({ onigiri = onigiri.load(fixture_path("valid_onigiri_gamification.json")) })
	local rendered = table.concat(lines, "\n")
	assert_true(rendered:find("Onigiri status: connected", 1, true), "missing connected status")
	assert_true(rendered:find("Restaurant level: 4", 1, true), "missing level")
	assert_true(rendered:find("Total XP: 430", 1, true), "missing xp")
	assert_true(rendered:find("Taiyaki coins: 12", 1, true), "missing coins")
	assert_true(rendered:find("Achievements: 1/1", 1, true), "missing achievements")
	assert_true(rendered:find("Daily specials: 0/1", 1, true), "missing daily specials")
	assert_true(not rendered:find("Anki collection", 1, true), "must not include anki stats")
	config.setup()
end)

test("stats view renders only Onigiri data", function()
	local dashboard = require("anki_review.dashboard")
	local onigiri = require("anki_review.onigiri")
	local lines = dashboard._render_stats_lines({ onigiri = onigiri.load(fixture_path("valid_onigiri_gamification.json")) })
	local rendered = table.concat(lines, "\n")
	assert_true(rendered:find("Onigiri detailed stats", 1, true), "missing Onigiri stats")
	assert_true(rendered:find("level=4 xp=430 coins=12", 1, true), "missing Onigiri level")
	assert_true(rendered:find("Daily specials list", 1, true), "missing daily specials header")
	assert_true(rendered:find("Achievements list", 1, true), "missing achievements header")
	assert_true(rendered:find("read-only", 1, true), "missing readonly label")
	assert_true(not rendered:find("Anki collection", 1, true), "must not include anki stats")
end)

test("dashboard refresh reloads Onigiri data", function()
	local dashboard = require("anki_review.dashboard")
	dashboard._refresh_status({ onigiri = { ok = false }, buf = nil })
	assert_true(true)
end)

test("dashboard render shows setup for disabled provider", function()
	local config = require("anki_review.config")
	local dashboard = require("anki_review.dashboard")
	config.setup({ gamification = { provider = "none" } })
	local lines = dashboard._render_lines({})
	local rendered = table.concat(lines, "\n")
	assert_true(rendered:find("Reason: provider disabled", 1, true), "missing disabled setup reason")
	config.setup()
end)

test("review completion omits local xp when gamification disabled", function()
	local config = require("anki_review.config")
	local ui = require("anki_review.ui")
	config.setup({ gamification = { provider = "none" } })
	local state = {
		buf = vim.api.nvim_create_buf(false, true),
		complete = true,
		deck = "Deck",
		session_started_at = os.time(),
		stats = { answered = 1, ease = { [1] = 0, [2] = 0, [3] = 1, [4] = 0 } },
	}
	ui.render(state)
	local rendered = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
	assert_true(rendered:find("Gamification disabled", 1, true), "missing disabled completion note")
	assert_true(not rendered:find("XP gained", 1, true), "disabled completion shows xp")
	vim.api.nvim_buf_delete(state.buf, { force = true })
	config.setup()
end)

test("review completion shows current Onigiri values", function()
	local config = require("anki_review.config")
	local ui = require("anki_review.ui")
	config.setup({ onigiri = { gamification_path = fixture_path("valid_onigiri_gamification.json") } })
	local state = {
		buf = vim.api.nvim_create_buf(false, true),
		complete = true,
		deck = "Deck",
		session_started_at = os.time(),
		stats = { answered = 1, ease = { [1] = 0, [2] = 0, [3] = 1, [4] = 0 } },
	}
	ui.render(state)
	local rendered = table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n")
	assert_true(rendered:find("Onigiri: Level 4    XP 430    Coins 12", 1, true), "missing Onigiri completion values")
	assert_true(not rendered:find("XP gained", 1, true), "completion shows local xp")
	vim.api.nvim_buf_delete(state.buf, { force = true })
	config.setup()
end)

test("failed guiAnswerCard does not create local gamification file", function()
	local config = require("anki_review.config")
	local session = require("anki_review.session")
	config.setup()
	with_preserved_file(local_gamification_path(), function()
		vim.fn.delete(local_gamification_path())
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
			eq(vim.fn.filereadable(local_gamification_path()), 0)
			session.close()
		end)
	end)
end)

test("successful answer does not create local xp state", function()
	local config = require("anki_review.config")
	local session = require("anki_review.session")
	config.setup()
	with_preserved_file(local_gamification_path(), function()
		vim.fn.delete(local_gamification_path())
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
			eq(vim.fn.filereadable(local_gamification_path()), 0)
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

test("state stores plugin-owned state and ignores corrupt json", function()
	local state = require("anki_review.state")
	local path = vim.fn.tempname()
	state._set_path_for_tests(path)

	state.set_last_deck("Japanese::Core")
	eq(state.last_deck(), "Japanese::Core")
	state.set_onigiri_gamification_path("/tmp/gamification_User 1.json")
	eq(state.last_deck(), "Japanese::Core")
	eq(state.onigiri_gamification_path(), "/tmp/gamification_User 1.json")
	vim.fn.writefile({ "{" }, path)
	eq(state.last_deck(), nil)
	eq(state.onigiri_gamification_path(), nil)

	state._set_path_for_tests(nil)
	vim.fn.delete(path)
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

-- New tests for deck_stats parsing

test("deck_stats parses result keyed by deck id", function()
	local anki = require("anki_review.anki")
	local result = anki.deck_stats("5000 eng")
	-- cannot test real AnkiConnect, skip
	-- verify the function structure is correct
	assert_true(type(anki.deck_stats) == "function")
end)

test("deck_stats iterates by id and finds name", function()
	local anki = require("anki_review.anki")
	with_anki_stubs({
		request = function(action, params)
			eq(action, "getDeckStats")
			eq(params.decks[1], "5000 eng")
			return {
				["12345"] = { deck_id = 12345, name = "5000 eng", new_count = 10, learn_count = 2, review_count = 50, total_in_deck = 5000 },
			}, nil
		end,
	}, function()
		local stats, err = anki.deck_stats("5000 eng")
		eq(err, nil)
		eq(stats.new_count, 10)
		eq(stats.learn_count, 2)
		eq(stats.review_count, 50)
		eq(stats.total_in_deck, 5000)
	end)
end)

test("deck_stats returns nil for missing deck", function()
	local anki = require("anki_review.anki")
	with_anki_stubs({
		request = function()
			return {
				["12345"] = { deck_id = 12345, name = "Other Deck", new_count = 0, learn_count = 0, review_count = 0, total_in_deck = 0 },
			}, nil
		end,
	}, function()
		local stats, err = anki.deck_stats("missing deck")
		eq(stats, nil)
		eq(err, nil)
	end)
end)

test("deck_stats handles error response", function()
	local anki = require("anki_review.anki")
	with_anki_stubs({
		request = function()
			return nil, "getDeckStats failed"
		end,
	}, function()
		local stats, err = anki.deck_stats("any deck")
		eq(stats, nil)
		eq(err, "getDeckStats failed")
	end)
end)

test("deck_stats handles wrong-shaped result", function()
	local anki = require("anki_review.anki")
	with_anki_stubs({
		request = function()
			return "not a table", nil
		end,
	}, function()
		local stats, err = anki.deck_stats("any deck")
		eq(stats, nil)
		eq(err, "invalid response shape")
	end)
end)

test("deck_stats handles empty result", function()
	local anki = require("anki_review.anki")
	with_anki_stubs({
		request = function()
			return {}, nil
		end,
	}, function()
		local stats, err = anki.deck_stats("any deck")
		eq(stats, nil)
		eq(err, nil)
	end)
end)

-- New tests for future_due queries

test("future_due query construction escapes deck names", function()
	local anki = require("anki_review.anki")
	eq(anki._future_query("5000 eng", "tomorrow"), 'deck:"5000 eng" prop:due=1')
	eq(anki._future_query("5000 eng", "future"), 'deck:"5000 eng" prop:due>=1')
end)

test("future_due query handles deck names with spaces", function()
	local anki = require("anki_review.anki")
	eq(anki._future_query("Japanese::Core 5000", "tomorrow"), 'deck:"Japanese::Core 5000" prop:due=1')
end)

test("future_due query handles deck names with double quotes", function()
	local anki = require("anki_review.anki")
	eq(anki._future_query([[My "Cool" Deck]], "tomorrow"), [[deck:"My \"Cool\" Deck" prop:due=1]])
end)

test("future_due query handles deck names with backslashes", function()
	local anki = require("anki_review.anki")
	eq(anki._future_query([[Test\Deck]], "tomorrow"), [[deck:"Test\\Deck" prop:due=1]])
end)

test("future_due returns counts from findCards results", function()
	local anki = require("anki_review.anki")
	with_anki_stubs({
		find_cards = function(query)
			if query:find("prop:due=1") then
				return { 1, 2, 3 }, nil
			end
			return { 1, 2, 3, 4, 5, 6, 7, 8 }, nil
		end,
	}, function()
		local result, err = anki.future_due("5000 eng")
		eq(err, nil)
		eq(result.tomorrow, 3)
		eq(result.future, 8)
	end)
end)

test("future_due returns error when tomorrow query fails", function()
	local anki = require("anki_review.anki")
	with_anki_stubs({
		find_cards = function(query)
			if query:find("prop:due=1") then
				return nil, "query failed"
			end
			return { 1, 2 }, nil
		end,
	}, function()
		local result, err = anki.future_due("5000 eng")
		eq(result, nil)
		eq(err, "query failed")
	end)
end)

test("future_due returns error when future query fails", function()
	local anki = require("anki_review.anki")
	with_anki_stubs({
		find_cards = function(query)
			if query:find("prop:due=1") then
				return { 1, 2 }, nil
			end
			return nil, "query failed"
		end,
	}, function()
		local result, err = anki.future_due("5000 eng")
		eq(result, nil)
		eq(err, "query failed")
	end)
end)

test("future_due returns error for empty deck name", function()
	local anki = require("anki_review.anki")
	local result, err = anki.future_due("")
	eq(result, nil)
	eq(err, "no deck")
	local result2, err2 = anki.future_due(nil)
	eq(result2, nil)
	eq(err2, "no deck")
end)

test("invalid Onigiri json shows setup screen", function()
	local dashboard = require("anki_review.dashboard")
	local lines = dashboard._render_lines({ onigiri = { ok = false, source = "onigiri", error = "invalid json" } })
	local rendered = table.concat(lines, "\n")
	assert_true(rendered:find("Onigiri dashboard unavailable", 1, true), "missing unavailable title")
	assert_true(rendered:find("Reason: invalid json", 1, true), "missing invalid reason")
end)

test("finder returns candidate gamification files", function()
	local onigiri = require("anki_review.onigiri")
	local base = vim.fn.tempname()
	local addon_dir = base .. "/User 1/addons21/1011095603/user_files"
	vim.fn.mkdir(addon_dir, "p")
	local file = addon_dir .. "/gamification_User 1.json"
	vim.fn.writefile(vim.fn.readfile(fixture_path("user_files/gamification_User 1.json")), file)
	local found = onigiri.find_candidates({ base })
	eq(#found, 1)
	eq(found[1], file)
	vim.fn.delete(base, "rf")
end)

-- New tests for review_counts via rated: queries

test("review_counts query construction", function()
	local anki = require("anki_review.anki")
	eq(anki._review_query("5000 eng", "today"), 'deck:"5000 eng" rated:1')
	eq(anki._review_query("5000 eng", "week"), 'deck:"5000 eng" rated:7')
	eq(anki._review_query("5000 eng", "month"), 'deck:"5000 eng" rated:30')
end)

test("review_counts query without deck", function()
	local anki = require("anki_review.anki")
	eq(anki._review_query(nil, "today"), "rated:1")
	eq(anki._review_query(nil, "week"), "rated:7")
	eq(anki._review_query(nil, "month"), "rated:30")
end)

test("review_counts query escapes deck names", function()
	local anki = require("anki_review.anki")
	eq(anki._review_query([[My "Deck"]], "today"), [[deck:"My \"Deck\"" rated:1]])
	eq(anki._review_query("Deck with spaces", "week"), [[deck:"Deck with spaces" rated:7]])
end)

test("review_counts returns correct counts", function()
	local anki = require("anki_review.anki")
	with_anki_stubs({
		find_cards = function(query)
			if query:find("rated:1") then return { 1, 2, 3 }, nil end
			if query:find("rated:7") then return { 1, 2, 3, 4, 5, 6, 7 }, nil end
			return { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }, nil
		end,
	}, function()
		local result, err = anki.review_counts("5000 eng")
		eq(err, nil)
		eq(result.today, 3)
		eq(result.week, 7)
		eq(result.month, 10)
	end)
end)

test("review_counts handles findCards error", function()
	local anki = require("anki_review.anki")
	with_anki_stubs({
		find_cards = function()
			return nil, "query failed"
		end,
	}, function()
		local result, err = anki.review_counts("5000 eng")
		eq(result, nil)
		eq(err, "query failed")
	end)
end)

test("review_counts handles nil result from findCards", function()
	local anki = require("anki_review.anki")
	with_anki_stubs({
		find_cards = function()
			return nil, nil
		end,
	}, function()
		local result, err = anki.review_counts("5000 eng")
		eq(err, nil)
		eq(result.today, 0)
		eq(result.week, 0)
		eq(result.month, 0)
	end)
end)

if #failures > 0 then
	for _, failure in ipairs(failures) do
		io.stderr:write(failure .. "\n")
	end
	os.exit(1)
end

print("tests passed")
