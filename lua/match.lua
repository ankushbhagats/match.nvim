local M = {}

---@class MatchOpts
---@field prefix? string
---@field style? "minimal"
---@field border? string
---@field border_hl? string
---@field anchor? "NE"|"NW"|"SE"|"SW"
M.config = {
	prefix = "",
	style = "minimal",
	border = "rounded",
	border_hl = "Function",
	anchor = "NE",
}

local wins = {}

local parentWin = 0 ---@type integer
local parentPos = nil ---@type [integer, integer]|nil
local augroup = vim.api.nvim_create_augroup("Match", { clear = true })
local searchText = ""
local replaceText = ""
local historyCount = 0
local replaceCount = 0

local ns = vim.api.nvim_create_namespace("searchcount")

---@param title string
---@param row integer
---@return integer win
---@return integer buf
local function float(title, row)
	local width = 30
	local height = 1
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		anchor = M.config.anchor,
		title = title,
		width = width,
		height = height,
		row = row,
		col = vim.o.columns,
		relative = "editor",
		style = M.config.style,
		border = M.config.border,
	})

	vim.wo[win].winhl = ("NormalFloat:Normal,FloatBorder:%s,Search:None,IncSearch:None,CurSearch:None"):format(
		M.config.border_hl
	)
	vim.bo[buf].buftype = "prompt"
	vim.bo[buf].filetype = "match"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.fn.prompt_setprompt(buf, M.config.prefix)

	wins[title:lower()] = { win = win, buf = buf, row = row }

	return win, buf
end

vim.api.nvim_create_autocmd("VimResized", {
	group = augroup,
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

local function close()
	for _, item in pairs(wins) do
		pcall(vim.api.nvim_win_close, item.win, true)
	end
	vim.cmd.noh()
	if parentPos then
		vim.api.nvim_win_set_cursor(parentWin, parentPos)
	end
end

local function switch()
	local win = vim.api.nvim_get_current_win()

	for _, item in pairs(wins) do
		if vim.api.nvim_win_is_valid(item.win) and win ~= item.win then
			vim.api.nvim_set_current_win(item.win)
		end
	end
end

---@param winid integer
local function nvim_set_current_win(winid)
	pcall(vim.api.nvim_set_current_win, winid)
end

---@param win integer
---@param buf integer
local function searchcount(win, buf)
	nvim_set_current_win(parentWin)
	local sc = vim.fn.searchcount({ maxcount = 0 })
	nvim_set_current_win(win)

	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
		virt_text = { { ("[%d/%d]"):format(sc.current, sc.total), "Label" } },
		virt_text_pos = "right_align",
	})
end

---@param text? string
---@param win integer
---@param buf integer
local function search(text, win, buf)
	if not text or text == "" then
		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
		vim.cmd.noh()
		searchText = ""
		return
	end

	searchText = vim.fn.escape(text, [[\/.*$^~[]])
	vim.o.hlsearch = true
	vim.fn.setreg("/", searchText)

	nvim_set_current_win(parentWin)

	vim.fn.cursor(1, 1)
	vim.fn.search(searchText, "W")
	searchcount(win, buf)

	nvim_set_current_win(win)
end

---@param win integer
local function replace(win)
	if searchText == "" then
		vim.notify("Please enter a search term.", vim.log.levels.WARN)
		return
	end

	nvim_set_current_win(parentWin)

	if vim.fn.searchcount().current < 1 then
		nvim_set_current_win(win)
		vim.notify(("Pattern not found: %s"):format(searchText), vim.log.levels.ERROR)
		return
	end

	vim.cmd.noh()
	vim.cmd(("%%s/%s/%s/g"):format(searchText, replaceText))
	close()
end

---@param key string
---@param win integer
---@param buf integer
local function jump(key, win, buf)
	if not vim.api.nvim_win_is_valid(parentWin) or searchText == "" then
		return
	end

	nvim_set_current_win(parentWin)
	vim.cmd("silent! normal! " .. key)
	searchcount(win, buf)
	nvim_set_current_win(win)
end

---@param key string
local function replaceJump(key)
	local searchWin = wins.search.win
	local searchBuf = wins.search.buf
	local replaceWin = wins.replace.win

	if not vim.api.nvim_win_is_valid(parentWin) or searchText == "" then
		return
	end

	nvim_set_current_win(parentWin)
	-- vim.fn.search(searchText, key)
	vim.cmd('silent! normal! "_cg' .. key .. replaceText .. "\27")
	vim.cmd("silent! normal! " .. key)
	searchcount(searchWin, searchBuf)
	nvim_set_current_win(replaceWin)
	replaceCount = replaceCount + 1
end

---@param key string
---@param win integer
local function history(key, win)
	key = vim.api.nvim_replace_termcodes(key, true, false, true)

	local nextCount = historyCount + (key == "u" and 1 or -1)
	if nextCount > replaceCount or nextCount < 0 then
		return
	end

	historyCount = nextCount

	nvim_set_current_win(parentWin)
	vim.cmd("silent! normal! " .. key)
	searchcount(wins.search.win, wins.search.buf)
	nvim_set_current_win(win)
end

vim.api.nvim_create_autocmd("WinEnter", {
	group = augroup,
	callback = function()
		for _, item in pairs(wins) do
			if vim.api.nvim_get_current_buf() == item.buf then
				vim.cmd.startinsert()
			end
		end
	end,
})

---@param win integer
---@param buf integer
---@param callback fun(text?: string, win: integer, buf: integer)
local function onChange(win, buf, callback)
	vim.api.nvim_buf_attach(buf, false, {
		on_lines = function()
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(buf) then
					return
				end

				local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
				local prefix = vim.fn.prompt_getprompt(buf)
				local text = line:sub(#prefix + 1) -- remove the prefix
				callback(text, win, buf)
			end)
		end,
	})
end

---@param args string
local function open(args)
	parentWin = vim.api.nvim_get_current_win()
	parentPos = vim.api.nvim_win_get_cursor(parentWin)
	local searchWin, searchBuf = float("Search", 1)
	local replaceWin, replaceBuf = float("Replace", 4)

	onChange(searchWin, searchBuf, search)
	onChange(replaceWin, replaceBuf, function(text)
		replaceText = text
	end)

	nvim_set_current_win(searchWin)
	vim.api.nvim_buf_set_lines(searchBuf, 0, -1, false, { args })
	vim.api.nvim_win_set_cursor(searchWin, { 1, args:len() })

	for name, item in pairs(wins) do
		vim.keymap.set({ "n", "i" }, "<Esc>", close, { buffer = item.buf })
		vim.keymap.set({ "n", "i" }, "<C-q>", close, { buffer = item.buf })
		vim.keymap.set({ "n", "i" }, "<Tab>", switch, { buffer = item.buf })
		vim.keymap.set({ "n", "i" }, "<S-Tab>", switch, { buffer = item.buf })

		if name == "search" then
			vim.keymap.set({ "n", "i" }, "<C-r>", function() end, { buffer = item.buf })
			vim.keymap.set({ "n", "i" }, "<CR>", switch, { buffer = item.buf })

			vim.keymap.set({ "n", "i" }, "<Up>", function()
				jump("N", item.win, item.buf)
			end, { buffer = item.buf })

			vim.keymap.set({ "n", "i" }, "<Down>", function()
				jump("n", item.win, item.buf)
			end, { buffer = item.buf })
		elseif name == "replace" then
			vim.keymap.set({ "n", "i" }, "<CR>", function()
				replace(item.win)
			end, { buffer = item.buf })

			vim.keymap.set({ "n", "i" }, "<Up>", function()
				replaceJump("N")
			end, { buffer = item.buf })

			vim.keymap.set({ "n", "i" }, "<Down>", function()
				replaceJump("n")
			end, { buffer = item.buf })

			vim.keymap.set({ "n", "i" }, "<C-u>", function()
				history("u", item.win)
			end, { buffer = item.buf })

			vim.keymap.set({ "n", "i" }, "<C-r>", function()
				history("<C-r>", item.win)
			end, { buffer = item.buf })
		end
	end
end

vim.api.nvim_create_user_command("Match", function(opts)
	open(opts.args)
end, { nargs = "*", desc = "Search and Replace" })

vim.api.nvim_create_user_command("MatchWord", function()
	open(vim.fn.expand("<cword>"))
end, { nargs = 0, desc = "Match using word under cursor" })

vim.api.nvim_create_user_command("MatchLine", function()
	open(vim.fn.getline("."))
end, { range = true, nargs = 0, desc = "Match using current line" })

---@param opts? MatchOpts
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

return M
