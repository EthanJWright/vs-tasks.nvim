local M = {}

function M.toquickfix(output)
	vim.schedule(function()
		local lines = type(output) == "table" and output or vim.split(output, "\n")
		local qf_entries = {}

		for _, line in ipairs(lines) do
			-- Match TypeScript compiler error format (tsc)
			-- Example: packages/service-graph-api/src/graphql.ts:28:3 - error TS2304: Cannot find name 'lol'.
			local file, lnum, col, err_type, err_code, msg =
				line:match("([^:]+):(%d+):(%d+)%s*%-%s*(%w+)%s*TS(%d+):%s*(.+)")

			if file and msg then
				msg = string.format("[TS%s] %s", err_code, msg)
			end

			-- If no match, try other formats
			if not file then
				-- Try TypeScript format with parentheses
				file, lnum, col, msg = line:match("([^%(]+)%((%d+),(%d+)%): (.+)")
			end

			-- Fall back to ESLint format
			if not file then
				file, lnum, col, msg = line:match("([^:]+):(%d+):(%d+):%s*(.+)")
			end

			if file then
				file = vim.trim(file)
				-- Convert relative paths to absolute
				if not vim.fn.filereadable(file) and vim.fn.getcwd() then
					local abs_path = vim.fn.getcwd() .. "/" .. file
					if vim.fn.filereadable(abs_path) then
						file = abs_path
					end
				end

				table.insert(qf_entries, {
					filename = file,
					lnum = tonumber(lnum),
					col = tonumber(col),
					text = msg,
					type = "E",
				})
			end
		end

		if #qf_entries > 0 then
			vim.fn.setqflist(qf_entries)
			vim.cmd("copen")
			local qf_height = math.min(10, #qf_entries)
			vim.cmd("resize " .. qf_height)
		end
	end)
end

function M.close()
	vim.cmd("cclose")
end

return M
