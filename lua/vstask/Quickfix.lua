local M = {}

function M.toquickfix(output)
	vim.schedule(function()
		local lines = vim.split(output, "\n")
		local qf_entries = {}

		for _, line in ipairs(lines) do
			-- Match TypeScript error format: file(line,col): error TS1234: message
			local file, lnum, col, msg = line:match("([^%(]+)%((%d+),(%d+)%): (.+)")
			if file then
				table.insert(qf_entries, {
					filename = file,
					lnum = tonumber(lnum),
					col = tonumber(col),
					text = msg,
					type = "E",
				})
			end
		end

		vim.fn.setqflist(qf_entries)
		local quickFixCount = #qf_entries

		if quickFixCount > 0 then
			vim.notify("TypeScript errors found.", vim.log.levels.WARN, { title = "Build" })
			vim.cmd("copen")
		else
			vim.notify("No errors found", vim.log.levels.INFO, { title = "Build" })
		end
	end)
end

return M
