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

test("strip_html removes markup and entities", function()
	local text = require("anki_review.text")
	local cleaned = text.strip_html("<div>Hello&nbsp;&amp;<br>world</div><script>x()</script>")
	eq(cleaned, "Hello &\nworld")
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
	assert_true(size.width <= vim.o.columns - 4, "width exceeds editor")
	assert_true(size.height <= vim.o.lines - vim.o.cmdheight - 4, "height exceeds editor")
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
	assert_true(state.autocmds and #state.autocmds == 2, "autocmds not tracked")

	vim.api.nvim_exec_autocmds("VimResized", {})
	assert_true(vim.api.nvim_win_is_valid(state.win), "resize closed window")
	ui.close(state)
	eq(state.win, nil)
	eq(state.buf, nil)
	eq(state.autocmds, nil)
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
	})

	local opts = config.get()
	eq(opts.endpoint, "http://example.test:8765")
	eq(opts.timeout, 123)
	eq(opts.window.width, 0.5)
	eq(opts.window.height, 0.72)
	eq(opts.default_ease, 4)
	config.setup()
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

if #failures > 0 then
	for _, failure in ipairs(failures) do
		io.stderr:write(failure .. "\n")
	end
	os.exit(1)
end

print("tests passed")
