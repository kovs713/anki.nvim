local M = {}

function M.strip_html(text)
	if not text or text == vim.NIL then
		return ""
	end

	text = tostring(text)
	text = text:gsub("<style.->.-</style>", "")
	text = text:gsub("<script.->.-</script>", "")
	text = text:gsub("<br%s*/?>", "\n")
	text = text:gsub("</div>", "\n")
	text = text:gsub("</p>", "\n")
	text = text:gsub("<[^>]+>", "")
	text = text:gsub("&nbsp;", " ")
	text = text:gsub("&amp;", "&")
	text = text:gsub("&lt;", "<")
	text = text:gsub("&gt;", ">")
	text = text:gsub("&quot;", '"')
	text = text:gsub("&#39;", "'")
	text = text:gsub("⁨", "")
	text = text:gsub("⁩", "")
	text = text:gsub("\n%s*\n%s*\n", "\n\n")
	text = text:gsub("^%s+", ""):gsub("%s+$", "")

	return text
end

function M.card_text(card)
	if not card then
		return "", ""
	end

	if card.question or card.answer then
		return M.strip_html(card.question), M.strip_html(card.answer)
	end

	if not card.fields then
		return "", ""
	end

	local sorted = {}
	for name, data in pairs(card.fields) do
		table.insert(sorted, { name = name, value = data.value, order = data.order or 0 })
	end
	table.sort(sorted, function(a, b)
		return a.order < b.order
	end)

	local question = M.strip_html(sorted[1] and sorted[1].value or "")
	local answer_parts = {}
	for i = 2, #sorted do
		local value = M.strip_html(sorted[i].value)
		if value ~= "" then
			table.insert(answer_parts, value)
		end
	end

	return question, table.concat(answer_parts, "\n")
end

return M
