local M = {}

M.config = {
	prefix = "",
	style = "minimal",
	border = "rounded",
	border_hl = "Function",
}

local wins = {}

local historyCount = 0
local replaceCount = 0
local ns = vim.api.nvim_create_namespace("searchcount")

local function float(title, row, parent)
	local opts = M.config
	local width = 30
	local height = 1

	local buf = vim.api.nvim_create_buf(false, true)

	local win = vim.api.nvim_open_win(buf, true, {
		anchor = "NE",
		title = title,
		width = width,
		height = height,
		row = row,
		col = vim.o.columns,
		relative = "editor",
		style = opts.style,
		border = opts.border,
	})

	vim.wo[win].winhl =
		string.format("NormalFloat:Normal,FloatBorder:%s,Search:None,IncSearch:None,CurSearch:None", opts.border_hl)
	vim.bo[buf].buftype = "prompt"
	vim.bo[buf].filetype = "match"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.fn.prompt_setprompt(buf, opts.prefix)

	wins[string.lower(title)] = { win = win, buf = buf, row = row, parent = parent }

	return win, buf
end

vim.api.nvim_create_autocmd("VimResized", {
	callback = function()
		for _, item in pairs(wins) do
			if vim.api.nvim_win_is_valid(item.win) then
				vim.api.nvim_win_set_config(item.win, {
					relative = "editor",
					col = vim.o.columns,
					row = item.row,
				})
			end
		end
	end,
})

local searchText = ""
local replaceText = ""

local function close()
	for _, item in pairs(wins) do
		if vim.api.nvim_win_is_valid(item.win) then
			vim.api.nvim_win_close(item.win, true)
		end
	end
end

local function switch()
	local win = vim.api.nvim_get_current_win()

	for _, item in pairs(wins) do
		if vim.api.nvim_win_is_valid(item.win) then
			if win ~= item.win then
				vim.api.nvim_set_current_win(item.win)
			end
		end
	end
end

local function searchcount(parent, win, buf)
	vim.api.nvim_set_current_win(parent)
	local sc = vim.fn.searchcount({ maxcount = 0 })
	vim.api.nvim_set_current_win(win)

	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

	vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
		virt_text = { { string.format("[%d/%d]", sc.current, sc.total), "Label" } },
		virt_text_pos = "right_align",
	})
end

local function search(text, parent, win, buf)
	if not text or text == "" then
		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
		vim.opt.hlsearch = false
		return
	end

	searchText = vim.fn.escape(text, [[\/.*$^~[]])
	vim.opt.hlsearch = true
	vim.fn.setreg("/", searchText)

	vim.api.nvim_set_current_win(parent)

	vim.fn.cursor(1, 1)
	vim.fn.search(searchText, "W")
	searchcount(parent, win, buf)

	vim.api.nvim_set_current_win(win)
end

local function replace()
	if #searchText < 1 then
		return
	end
	close()
	vim.opt.hlsearch = false
	vim.cmd(string.format("%%s/%s/%s/g", searchText, replaceText))
end

local function jump(key, parent, win, buf)
	if not vim.api.nvim_win_is_valid(parent) or searchText == "" then
		return
	end

	vim.api.nvim_set_current_win(parent)
	vim.cmd("silent! normal! " .. key)
	searchcount(parent, win, buf)
	vim.api.nvim_set_current_win(win)
end

local function replaceJump(key, parent)
	local searchWin = wins.search.win
	local searchBuf = wins.search.buf
	local replaceWin = wins.replace.win
	if not vim.api.nvim_win_is_valid(parent) or searchText == "" then
		return
	end

	vim.api.nvim_set_current_win(parent)
	-- vim.fn.search(searchText, key)
	vim.cmd('silent! normal! "_cg' .. key .. replaceText .. "\27")
	vim.cmd("silent! normal! " .. key)
	searchcount(parent, searchWin, searchBuf)
	vim.api.nvim_set_current_win(replaceWin)
	replaceCount = replaceCount + 1
end

local function history(key, parent, win)
	key = vim.api.nvim_replace_termcodes(key, true, false, true)

	local nextCount = historyCount

	if key == "u" then
		nextCount = nextCount + 1
	else
		nextCount = nextCount - 1
	end

	if nextCount > replaceCount or nextCount < 0 then
		return
	end

	historyCount = nextCount

	vim.api.nvim_set_current_win(parent)
	vim.cmd("silent! normal! " .. key)
	searchcount(parent, wins.search.win, wins.search.buf)
	vim.api.nvim_set_current_win(win)
end

vim.api.nvim_create_autocmd("WinEnter", {
	callback = function()
		for _, item in pairs(wins) do
			if vim.api.nvim_get_current_buf() == item.buf then
				vim.cmd("startinsert")
			end
		end
	end,
})

local function onChange(parent, win, buf, callback)
	vim.api.nvim_buf_attach(buf, false, {
		on_lines = function()
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(buf) then
					return
				end

				local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
				local prefix = vim.fn.prompt_getprompt(buf)
				local text = line:sub(#prefix + 1) -- remove the prefix
				callback(text, parent, win, buf)
			end)
		end,
	})
end

local function open(args)
	local parent = vim.api.nvim_get_current_win()

	local searchWin, searchBuf = float("Search", 1, parent)
	local replaceWin, replaceBuf = float("Replace", 4, parent)

	onChange(parent, searchWin, searchBuf, search)
	onChange(parent, replaceWin, replaceBuf, function(text)
		replaceText = text
	end)

	vim.api.nvim_set_current_win(searchWin)
	vim.api.nvim_buf_set_lines(searchBuf, 0, -1, false, { args })
	vim.api.nvim_win_set_cursor(searchWin, { 1, #args })

	for name, item in pairs(wins) do
		vim.keymap.set({ "n", "i" }, "<Esc>", close, { buffer = item.buf })
		vim.keymap.set({ "n", "i" }, "<C-q>", close, { buffer = item.buf })
		vim.keymap.set({ "n", "i" }, "<Tab>", switch, { buffer = item.buf })

		if name == "search" then
			vim.keymap.set({ "n", "i" }, "<C-r>", function() end, { buffer = item.buf })
			vim.keymap.set({ "n", "i" }, "<CR>", switch, { buffer = item.buf })

			vim.keymap.set({ "n", "i" }, "<Up>", function()
				jump("N", parent, item.win, item.buf)
			end, { buffer = item.buf })

			vim.keymap.set({ "n", "i" }, "<Down>", function()
				jump("n", parent, item.win, item.buf)
			end, { buffer = item.buf })
		elseif name == "replace" then
			vim.keymap.set({ "n", "i" }, "<CR>", replace, { buffer = item.buf })

			vim.keymap.set({ "n", "i" }, "<Up>", function()
				replaceJump("N", parent)
			end, { buffer = item.buf })

			vim.keymap.set({ "n", "i" }, "<Down>", function()
				replaceJump("n", parent)
			end, { buffer = item.buf })

			vim.keymap.set({ "n", "i" }, "<C-u>", function()
				history("u", parent, item.win)
			end, { buffer = item.buf })

			vim.keymap.set({ "n", "i" }, "<C-r>", function()
				history("<C-r>", parent, item.win)
			end, { buffer = item.buf })
		end
	end
end

vim.api.nvim_create_user_command("Match", function(opts)
	open(opts.args)
end, { nargs = "*", desc = "Search and Replace" })

vim.api.nvim_create_user_command("MatchWord", function()
	local word = vim.fn.expand("<cword>")
	open(word)
end, { nargs = 0, desc = "Match using word under cursor" })

vim.api.nvim_create_user_command("MatchLine", function(opts)
  local line = vim.fn.getline(".")
	open(line)
end, { range = true, nargs = 0, desc = "Match using selected range" })

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts)
end

return M
