local Opts = require("vstask.Opts")
local Parse = require("vstask.Parse")
local quickfix = require("vstask.Quickfix")
local M = {}

local background_jobs = {}
local live_output_buffers = {} -- Track buffers showing live job output
local preview_configured = {}
local job_last_selected = {}

local Term_opts = {}

M.LABEL_PRE = "Task: "

M.is_running = function(job_id)
	local job_status = vim.fn.jobwait({ job_id }, -1)[1]
	local is_running = job_status == -1
	return is_running
end

M.remove_live_output_buffer = function(job_id)
	live_output_buffers[job_id] = nil
end

M.split_to_direction = function(direction)
	local opt_direction = Opts.get_direction(direction, Term_opts)
	local size = Opts.get_size(direction, Term_opts)
	local command_map = {
		vertical = { size = "vertical resize", command = "vsplit" },
		horizontal = { size = "resize ", command = "split" },
		tab = { command = "tabnew" },
	}

	if command_map[opt_direction] ~= nil then
		vim.cmd(command_map[opt_direction].command)
		if command_map[opt_direction].size ~= nil and size ~= nil then
			vim.cmd(command_map[opt_direction].size .. size)
		end
	end
end

M.is_job_running = function(job_id)
	return job_id and background_jobs[job_id].completed ~= true
end

M.scroll_to_bottom = function(win_id)
	if win_id and win_id ~= -1 then
		local buf = vim.api.nvim_win_get_buf(win_id)
		local line_count = vim.api.nvim_buf_line_count(buf)
		if line_count > 0 then
			vim.api.nvim_win_set_cursor(win_id, { line_count, 0 })
		end
	end
end

M.clean_command = function(pre, options)
	local command = pre
	if type(options) == "table" then
		local cwd = options["cwd"]
		if type(cwd) == "string" then
			local cd_command = string.format("cd %s", cwd)
			command = string.format("%s && %s", cd_command, command)
		end
	end
	return command
end

-- Just trigger the update event, let preview system handle the display
local update_buffers = function()
	vim.schedule(function()
		vim.api.nvim_exec_autocmds("User", { pattern = "VsTaskJobOutput" })
	end)
end

-- Helper function to find a task by label
local function find_task_by_label(label, task_list)
	for _, task in ipairs(task_list) do
		if task.label == label then
			return task
		end
	end
	return nil
end

local function get_buf_counter(label)
	local base_name = M.LABEL_PRE .. label
	local max_counter = 1

	-- Find highest existing counter and check for base name
	for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf_id) then
			local buf_name = vim.api.nvim_buf_get_name(buf_id)
			if string.find(buf_name, base_name) then
				max_counter = max_counter + 1
			end
		end
	end

	if max_counter == 1 then
		return base_name
	else
		return base_name .. " (" .. max_counter .. ")"
	end
end

local get_unique_label = function(label)
	local counter = 1
	for _, job in pairs(M.get_background_jobs()) do
		if string.find(job.label, label) then
			counter = counter + 1
		end
	end
	if counter == 1 then
		return label
	else
		local unique_label = label .. " (" .. counter .. ")"
		return unique_label
	end
end

local function name_buffer(buf, label)
	local name = get_buf_counter(label)

	-- Check if any other buffer already has this name
	for _, existing_buf in ipairs(vim.api.nvim_list_bufs()) do
		if existing_buf ~= buf and vim.api.nvim_buf_is_valid(existing_buf) then
			local existing_name = vim.api.nvim_buf_get_name(existing_buf)
			if existing_name == name then
				-- If the buffer exists but is hidden/invalid, delete it
				pcall(vim.api.nvim_buf_delete, existing_buf, { force = true })
				break
			end
		end
	end

	-- Now safely set the buffer name
	pcall(vim.api.nvim_buf_set_name, buf, name)
	return name
end

-- Function to get terminal buffer content
M.get_buffer_content = function(buf_job_id)
	-- Check if job exists
	if not buf_job_id then
		return {}
	end

	-- First try to find the job directly
	local job = background_jobs[buf_job_id]

	-- If not found directly, try to find by id field
	if not job then
		for job_id, j in pairs(background_jobs) do
			if j.id == buf_job_id then
				job = j
				-- Update the job reference to use job_id as key
				background_jobs[buf_job_id] = j
				background_jobs[job_id] = nil
				break
			end
		end
	end

	if not job then
		return {}
	end

	-- Find the terminal buffer for this job
	for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf_id) then
			local buf_name = vim.api.nvim_buf_get_name(buf_id)
			if buf_name:match(vim.pesc(M.LABEL_PRE .. job.label)) then
				return vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
			end
		end
	end
	return {}
end

M.start_job = function(opts)
	-- Default options
	local options = {
		label = get_unique_label(opts.label),
		command = opts.command,
		silent = opts.silent or false,
		watch = opts.watch or false,
		on_complete = opts.on_complete,
		terminal = opts.terminal == nil and true or opts.terminal,
		direction = opts.direction or "current",
	}

	local function notify(msg, level)
		if not options.silent then
			vim.notify(msg, level, { title = "vs-tasks" })
		end
	end

	if options.watch then
		Add_watch_autocmd()
	end

	local job_id
	local open_terminal = options.terminal

	-- Create a new buffer for the terminal
	local current_buf = vim.api.nvim_get_current_buf()
	local buf = vim.api.nvim_create_buf(open_terminal, true)
	if open_terminal == true then
		M.split_to_direction(options.direction)
	else
		notify("Starting backgrounded task... " .. options.label, vim.log.levels.INFO)
	end

	-- show the buffer
	vim.api.nvim_win_set_buf(0, buf)

	-- Enable terminal scrolling and set buffer options
	vim.api.nvim_create_autocmd("TermOpen", {
		buffer = buf,
		callback = function()
			-- Set terminal options
			vim.opt_local.scrolloff = 0

			-- Apply buffer options from Parse if they exist
			local buffer_options = Parse.buffer_options
			if buffer_options then
				local win = vim.api.nvim_get_current_win()
				for _, option in ipairs(buffer_options) do
					-- Set window-local options directly on the window
					vim.wo[win][option] = true
				end
			end

			-- Start in terminal mode
			vim.cmd("startinsert")
			-- Scroll to bottom
			M.scroll_to_bottom(vim.api.nvim_get_current_win())
		end,
	})

	-- Set buffer name after terminal creation
	vim.schedule(function()
		name_buffer(buf, options.label)
	end)
	job_id = vim.fn.jobstart(options.command, {
		term = true,
		pty = true,
		on_stdout = function(_, data)
			if data then
				update_buffers()
			end
		end,
		on_stderr = function(_, data)
			if data then
				update_buffers()
			end
		end,
		on_exit = function(_, exit_code)
			local job = background_jobs[job_id]

			if job == nil then
				return
			end

			update_buffers()

			if exit_code == 0 then
				notify("🟢 Job completed successfully : " .. job.label, vim.log.levels.INFO)
				quickfix.close()
			else
				notify("🔴 Job failed." .. job.label, vim.log.levels.ERROR)
				local content = M.get_buffer_content(job_id)
				quickfix.toquickfix(content)
			end

			-- Always record end time and exit code
			background_jobs[job_id].end_time = os.time()
			background_jobs[job_id].exit_code = exit_code

			-- Keep completed job in background_jobs unless it's a watch job
			if not job.watch then
				-- Get final output from terminal buffer
				local content = M.get_buffer_content(job_id)
				-- Update the job with final state
				background_jobs[job_id] = {
					id = job_id,
					label = job.label,
					end_time = os.time(),
					start_time = job.start_time or os.time(),
					exit_code = exit_code,
					output = vim.deepcopy(content),
					command = job.command,
					completed = true, -- Mark as completed
				}
			end
			if options.on_complete ~= nil then
				options.on_complete()
			end
		end,
	})

	if options.terminal ~= true then
		-- return to current buf if it's still valid
		if vim.api.nvim_buf_is_valid(current_buf) then
			vim.api.nvim_set_current_buf(current_buf)
		end
	end

	if job_id <= 0 then
		notify("Failed to start background job: " .. options.command, vim.log.levels.ERROR)
	else
		background_jobs[job_id] = {
			id = job_id,
			command = options.command,
			start_time = os.time(),
			output = M.get_buffer_content(job_id),
			watch = options.watch,
			label = options.label,
			end_time = 0,
			exit_code = -1,
		}
	end
end

-- Run dependent tasks sequentially in background
M.run_dependent_tasks = function(task, task_list)
	local deps = type(task.dependsOn) == "string" and { task.dependsOn } or task.dependsOn
	local task_queue = {}

	-- Run each dependent task
	for _, dep_label in ipairs(deps) do
		local dep_task = find_task_by_label(dep_label, task_list)
		if dep_task then
			local command = M.clean_command(dep_task.command, dep_task.options)
			task_queue[#task_queue + 1] = { label = dep_task.label, command = command }
		else
			vim.notify("Dependent task not found: " .. dep_label, vim.log.levels.ERROR)
		end
	end
	-- add the original task to the queue
	if task.command ~= nil then
		task_queue[#task_queue + 1] = { label = task.label, command = M.clean_command(task.command, task.options) }
	end

	local function report_done()
		vim.notify("All dependent tasks completed", vim.log.levels.INFO)
	end

	local function run_next_task()
		if #task_queue == 0 then
			report_done()
			return
		end
		local next_task = table.remove(task_queue, 1)
		M.start_job({
			label = next_task.label,
			command = next_task.command,
			silent = false,
			watch = false,
			on_complete = run_next_task,
		})
	end

	local function run_all_tasks()
		-- Run all tasks in parallel
		for _, parallel_task in ipairs(task_queue) do
			M.start_job({
				label = parallel_task.label,
				command = parallel_task.command,
				silent = false,
				watch = false,
			})
		end
	end

	if task.dependsOrder ~= nil and task.dependsOrder == "sequence" then
		run_next_task()
	else
		run_all_tasks()
	end
end

M.toggle_watch = function(job_id)
	background_jobs[job_id].watch = not background_jobs[job_id].watch
end

M.preview_job_output = function(output, bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	-- Ensure output is a table
	local lines = type(output) == "table" and output or {}

	-- Get last 1000 lines
	local max_lines = 1000
	local start_idx = #lines > max_lines and #lines - max_lines or 0
	local recent_output = vim.list_slice(lines, start_idx + 1)

	-- Filter out empty lines and trim whitespace
	local filtered_output = {}
	local last_non_empty = 0
	for i, line in ipairs(recent_output) do
		-- Trim whitespace from both ends
		line = vim.trim(line)
		if line ~= "" and line ~= nil and not line:match("^%s*$") then
			filtered_output[#filtered_output + 1] = line
			last_non_empty = #filtered_output
		elseif i < #recent_output then
			-- Keep at most one empty line between content
			filtered_output[#filtered_output + 1] = line
		end
	end

	-- Trim trailing empty lines
	if last_non_empty > 0 then
		filtered_output = vim.list_slice(filtered_output, 1, last_non_empty)
	end

	-- Actually update the buffer content
	pcall(function()
		vim.bo[bufnr].modifiable = true
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, filtered_output)
		vim.bo[bufnr].modifiable = false
	end)

	-- Scroll to bottom of the preview window
	vim.schedule(function()
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return
		end

		local preview_win = vim.fn.bufwinid(bufnr)
		if preview_win ~= -1 then
			local line_count = vim.api.nvim_buf_line_count(bufnr)
			if line_count > 0 then
				-- Set cursor to last line
				pcall(function()
					vim.api.nvim_win_set_cursor(preview_win, { line_count, 0 })
					-- Make sure the last few lines are visible
					vim.api.nvim_win_call(preview_win, function()
						vim.cmd("normal! zb")
					end)
				end)
			end
		end
	end)
end

M.remove_preview = function(job_id)
	-- Clean up any existing autocmd group
	local group_name = string.format("VsTaskPreview_%d", job_id)
	pcall(vim.api.nvim_del_augroup_by_name, group_name)

	-- Get the preview buffer if it exists
	local preview_buf = live_output_buffers[job_id]
	if preview_buf then
		-- Remove from live_output_buffers
		live_output_buffers[job_id] = nil

		-- Clean up preview configuration state for all combinations with this job_id
		for key in pairs(preview_configured) do
			if key:match("_" .. job_id .. "$") then
				preview_configured[key] = nil
			end
		end

		-- If the buffer is still valid, clean it up
		if vim.api.nvim_buf_is_valid(preview_buf) then
			pcall(vim.api.nvim_buf_delete, preview_buf, { force = true })
		end
	end
end

-- Track preview configuration state per buffer+job combination
M.get_preview_key = function(bufnr, job_id)
	return string.format("%d_%d", bufnr, job_id)
end

-- Helper function to set up job output preview updates
local function setup_preview_updates(bufnr, job_id)
	if not (bufnr and job_id and M.is_job_running(job_id)) then
		return
	end

	-- Clean up any existing autocmd group first
	local group_name = string.format("VsTaskPreview_%d", job_id)
	pcall(vim.api.nvim_del_augroup_by_name, group_name)

	-- Create new augroup and autocmd
	local group = vim.api.nvim_create_augroup(group_name, { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "VsTaskJobOutput",
		callback = function()
			if not vim.api.nvim_buf_is_valid(bufnr) then
				pcall(vim.api.nvim_del_augroup_by_name, group_name)
				live_output_buffers[job_id] = nil
				return
			end
			local content = M.get_buffer_content(job_id)
			if content then
				M.preview_job_output(content, bufnr)
			end
		end,
	})

	-- Store the preview buffer in live_output_buffers
	live_output_buffers[job_id] = bufnr

	-- Set up cleanup when buffer is deleted
	vim.api.nvim_buf_attach(bufnr, false, {
		on_detach = function()
			pcall(vim.api.nvim_del_augroup_by_name, group_name)
			live_output_buffers[job_id] = nil
			-- Clean up preview configuration state
			preview_configured[M.get_preview_key(bufnr, job_id)] = nil
		end,
	})
end

M.get_background_jobs = function()
	return background_jobs
end

M.get_background_job = function(job_id)
	return background_jobs[job_id]
end

M.set_background_job = function(job_id, job)
	background_jobs[job_id] = job
end

M.remove_background_job = function(job_id)
	M.set_background_job(job_id, nil)
end

M.remove_background_jobs = function(jobs_to_remove)
	for _, job_id in ipairs(jobs_to_remove) do
		M.remove_background_job(job_id)
	end
end

M.job_selected = function(job_id)
	job_last_selected[job_id] = os.time()
end

local compare_last_selected = function(job_a, job_b)
	local background_a = background_jobs[job_a]
	local background_b = background_jobs[job_b]

	-- First prioritize running jobs over completed ones
	if background_a.completed ~= background_b.completed then
		return not background_a.completed -- Running jobs (not completed) come first
	end

	-- If both are running or both are completed, use last selected time
	local last_a = job_last_selected[job_a]
	local last_b = job_last_selected[job_b]

	if last_a and last_b then
		return last_a > last_b
	elseif last_a then
		return true
	elseif last_b then
		return false
	end

	-- If neither has been selected, sort by start time
	return background_a.start_time > background_b.start_time
end

M.is_preview_configured = function(preview_key)
	return preview_configured[preview_key]
end

M.configure_preview = function(preview_key, job_id, preview_buffer)
	-- First time seeing this job
	preview_configured[preview_key] = true
	-- Set up live updates for this preview buffer
	setup_preview_updates(preview_buffer, job_id)
	-- Set initial message
	vim.schedule(function()
		if vim.api.nvim_buf_is_valid(preview_buffer) then
			vim.bo[preview_buffer].modifiable = true
		end
		update_buffers()
	end)
end

-- Build a sorted list of jobs
M.build_jobs_list = function()
	local jobs_list = {}
	for _, job_info in pairs(M.get_background_jobs()) do
		table.insert(jobs_list, job_info)
	end

	-- Sort jobs by last selected time, falling back to start time
	table.sort(jobs_list, function(a, b)
		return compare_last_selected(a.id, b.id)
	end)

	return jobs_list
end

M.fully_clear_job = function(job_id)
	-- clear and delete the buffer
	local job = M.get_background_job(job_id)
	if not job then
		return
	end

	if M.is_running(job.id) then
		vim.fn.jobstop(job.id)
		vim.notify(string.format("Killed running job: %s", job.label), vim.log.levels.INFO)
	end

	M.remove_preview(job_id)

	-- Track which buffers we're going to delete
	local buffers_to_delete = {}

	-- Find all related buffers
	for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf_id) then
			local buf_name = vim.api.nvim_buf_get_name(buf_id)
			-- Match for the buffer name including any counter suffix
			if buf_name:match(vim.pesc(M.LABEL_PRE .. job.label)) then
				table.insert(buffers_to_delete, buf_id)
			end
		end
	end

	-- Delete all identified buffers
	for _, buf_id in ipairs(buffers_to_delete) do
		pcall(vim.api.nvim_buf_delete, buf_id, { force = true })
		pcall(vim.api.nvim_command, "bwipeout! " .. buf_id)
	end

	-- Remove from tracking tables
	if live_output_buffers[job_id] then
		live_output_buffers[job_id] = nil
	end
	if background_jobs[job_id] then
		background_jobs[job_id] = nil
	end
	if job_last_selected[job_id] then
		job_last_selected[job_id] = nil
	end

	-- Force a garbage collection to ensure everything is cleaned up
	collectgarbage("collect")

	-- Schedule a check to verify buffers are gone
	vim.schedule(function()
		local remaining_buffers = {}
		local job_label_pattern = vim.pesc(M.LABEL_PRE .. job.label)

		for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(buf_id) then
				local buf_name = vim.api.nvim_buf_get_name(buf_id)
				if buf_name:match(job_label_pattern) then
					table.insert(remaining_buffers, buf_name)
				end
			end
		end

		if #remaining_buffers > 0 then
			vim.notify(
				"Warning: Some job buffers could not be removed: " .. table.concat(remaining_buffers, ", "),
				vim.log.levels.WARN
			)
		end
	end)
end

M.open_buffer = function(label)
	local found_buf = nil
	-- First try to find an existing buffer
	for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf_id) then
			local buf_name = vim.api.nvim_buf_get_name(buf_id)
			if buf_name:match(vim.pesc(M.LABEL_PRE .. label)) then
				found_buf = buf_id
				break
			end
		end
	end

	-- If no existing buffer found for completed job, create a new one
	if not found_buf then
		found_buf = vim.api.nvim_create_buf(true, true)
		name_buffer(found_buf, label)

		-- If this is a completed job, populate with stored output
		for _, job in pairs(background_jobs) do
			if job.label == label and job.completed and job.output then
				local output = job.output
				if type(output) == "string" then
					output = vim.split(output, "\n")
				end
				vim.api.nvim_buf_set_lines(found_buf, 0, -1, false, output)
				break
			end
		end
	end

	if found_buf then
		vim.api.nvim_win_set_buf(0, found_buf)
		-- Schedule scrolling to bottom to ensure buffer is loaded
		vim.schedule(function()
			M.scroll_to_bottom(vim.api.nvim_get_current_win())
		end)
	end
end

-- Function to clean up completed jobs and their buffers
M.cleanup_completed_jobs = function()
	for _, job in pairs(M.get_background_jobs()) do
		if job.completed then
			M.fully_clear_job(job.id)
		end
	end
	vim.notify("Cleared all completed background jobs.")
end

return M
