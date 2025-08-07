local Parse = require("vstask.Parse")
local Job = require("vstask.Job")

local M = {}

-- Default mappings that any picker can use
M.default_mappings = {
	vertical = "<C-v>",
	split = "<C-p>",
	tab = "<C-t>",
	current = "<CR>",
	background_job = "<C-b>",
	watch_job = "<C-w>",
	kill_job = "<C-d>",
	run = "<C-r>",
}

-- Global state
M.last_cmd = nil
M.current_picker = nil
M.term_opts = nil

-- Format job entry for display
function M.format_job_entry(job_info, is_running)
	local runtime
	if is_running then
		runtime = os.time() - job_info.start_time
	else
		runtime = (job_info.end_time or os.time()) - job_info.start_time
	end

	local formatted = string.format("%s - (runtime %ds)", job_info.label, runtime)
	if job_info.watch then
		formatted = "👀 " .. formatted
	end

	if is_running then
		formatted = "🟠 " .. formatted
	else
		if job_info.exit_code == 0 then
			formatted = "🟢 " .. formatted
		else
			formatted = string.format("🔴 [exit code - (%d)] ", job_info.exit_code) .. formatted
		end
	end

	return formatted
end

-- Format the jobs list for display
function M.format_jobs_list(jobs_list)
	local jobs_formatted = {}
	for _, job_info in ipairs(jobs_list) do
		local is_running = not job_info.completed and vim.fn.jobwait({ job_info.id }, 0)[1] == -1
		table.insert(jobs_formatted, M.format_job_entry(job_info, is_running))
	end
	return jobs_formatted
end

-- Find task by label in task list
function M.find_task_by_label(task_list, label)
	for _, task in ipairs(task_list) do
		if task.label == label then
			return task
		end
	end
	return nil
end

-- Execute pre launch task
function M.execute_pre_launch_task(pre_launch_task, main_launch_config, direction, opts, on_refresh)
	local pre_task_command = Job.clean_command(pre_launch_task.command, pre_launch_task.options)
	if pre_launch_task.args then
		pre_task_command = Parse.replace(pre_task_command)
		pre_task_command = Parse.Build_launch(pre_task_command, pre_launch_task.args)
	end

	local execute_main_launch = function()
		local cleaned = Job.clean_command(main_launch_config.program, main_launch_config.options)
		if main_launch_config.args then
			cleaned = Parse.replace(cleaned)
			cleaned = Parse.Build_launch(cleaned, main_launch_config.args)
		end

		local execute_launch = function(prepared_command)
			Job.start_job({
				label = main_launch_config.name,
				command = prepared_command,
				silent = false,
				watch = direction == "watch_job",
				terminal = direction ~= "background_job" and direction ~= "watch_job",
				direction = direction,
				on_complete = on_refresh,
			})
		end

		Parse.replace_and_run(cleaned, execute_launch, opts)
	end

	local execute_pre_task = function(prepared_pre_command)
		Job.start_job({
			label = "PreLaunch: " .. pre_launch_task.label,
			command = prepared_pre_command,
			silent = false,
			watch = false,
			terminal = true,
			direction = "current",
			on_complete = execute_main_launch,
		})
	end

	Parse.replace_and_run(pre_task_command, execute_pre_task, opts)
end

-- Handle pre launch task
function M.handle_pre_launch_task(launch_config, direction, opts, on_refresh)
	if not launch_config.preLaunchTask then
		return false
	end

	local pre_launch_task_name = launch_config.preLaunchTask
	local task_list = Parse.Tasks()
	local pre_launch_task = M.find_task_by_label(task_list, pre_launch_task_name)

	if pre_launch_task then
		vim.notify("Running preLaunchTask: " .. pre_launch_task_name, vim.log.levels.INFO)
		M.execute_pre_launch_task(pre_launch_task, launch_config, direction, opts, on_refresh)
		return true
	else
		vim.notify("preLaunchTask '" .. pre_launch_task_name .. "' not found in tasks", vim.log.levels.WARN)
		return false
	end
end

-- Handle direction for task execution
function M.handle_direction(direction, selection, selection_list, is_launch, opts, on_refresh)
	local command, options, label, args

	if selection == nil or direction == "run" then
		if direction == "run" then
			direction = "current"
		end
		-- Handle case where selection is provided but we want to run a command
		-- This should be handled by specific picker implementations
		if selection and selection_list and selection_list[selection.index] then
			command = selection_list[selection.index].command
			options = selection_list[selection.index].options
			label = selection_list[selection.index].label
			args = selection_list[selection.index].args
		else
			error("Run command handling needs current line from picker implementation")
		end
	elseif is_launch then
		local launch_config = selection_list[selection.index]
		command = launch_config["program"]
		options = launch_config["options"]
		label = launch_config["name"]
		args = launch_config["args"]
		Parse.Used_launch(label)

		-- Handle preLaunchTask
		if M.handle_pre_launch_task(launch_config, direction, opts, on_refresh) then
			return
		end
	else
		command = selection_list[selection.index]["command"]
		options = selection_list[selection.index]["options"]
		label = selection_list[selection.index]["label"]
		args = selection_list[selection.index]["args"]
	end

	local cleaned = Job.clean_command(command, options)

	if args ~= nil then
		cleaned = Parse.replace(cleaned)
		cleaned = Parse.Build_launch(cleaned, args)
	end

	-- Find the full task object
	local task = nil
	for _, t in ipairs(selection_list) do
		if t.label == label then
			task = t
			break
		end
	end

	-- Update task usage tracking before running
	if task then
		Parse.Used_task(task.label)
	end

	if task and task.dependsOn then
		Job.run_dependent_tasks(task, selection_list)
		return
	end

	local process = function(prepared_command)
		Job.start_job({
			label = label,
			command = prepared_command,
			silent = false,
			watch = direction == "watch_job",
			terminal = direction ~= "background_job" and direction ~= "watch_job",
			direction = direction,
			on_complete = on_refresh,
		})
	end
	Parse.replace_and_run(cleaned, process, opts)
end

-- Restart watched jobs
function M.restart_watched_jobs(on_refresh)
	-- Store current window, cursor position, and mode
	local current_win = vim.api.nvim_get_current_win()
	local current_pos = vim.api.nvim_win_get_cursor(current_win)
	local current_buf = vim.api.nvim_get_current_buf()
	local current_mode = vim.api.nvim_get_mode().mode

	for _, job_info in pairs(Job.get_background_jobs()) do
		if job_info.watch then
			local command = job_info.command
			local job_id = job_info.id
			local job_label = job_info.label

			-- Find and delete the buffer associated with this job
			for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_valid(buf_id) then
					local buf_name = vim.api.nvim_buf_get_name(buf_id)
					if buf_name:match(vim.pesc(Job.LABEL_PRE .. job_label)) then
						-- Force delete the buffer
						vim.api.nvim_buf_delete(buf_id, { force = true })
						break
					end
				end
			end

			-- Stop the job
			vim.fn.jobstop(job_id)

			-- Use timer to ensure job is fully stopped before restarting
			if not Job.is_running(job_id) then
				-- Remove from background_jobs to prevent duplicate entries
				Job.set_background_job(job_id, nil)

				-- Remove from live_output_buffers if present
				Job.remove_live_output_buffer(job_id)

				-- Job is confirmed stopped, start new one
				vim.schedule(function()
					Job.start_job({
						label = job_label,
						command = command,
						silent = false,
						watch = true,
						terminal = false, -- Start in background
						on_complete = on_refresh,
					})
				end)
			else
				vim.notify(string.format("Job %d is still running, skipping restart", job_id), vim.log.levels.INFO)
			end
		end
	end

	-- Restore cursor position and mode if we're still in the same buffer
	vim.schedule(function()
		if
			vim.api.nvim_win_is_valid(current_win)
			and vim.api.nvim_buf_is_valid(current_buf)
			and vim.api.nvim_win_get_buf(current_win) == current_buf
		then
			vim.api.nvim_win_set_cursor(current_win, current_pos)
			-- If we were in normal mode, ensure we return to it
			if current_mode == "n" then
				vim.cmd("stopinsert")
			end
		end
	end)
end

-- Command input helper
function M.create_command_input_handler(mappings, on_refresh)
	return function(opts)
		opts = opts or {}

		-- Create an input dialog
		local selected_key = nil
		local input_opts = {
			prompt = "Enter command: ",
			callback = function(command)
				if command and command ~= "" then
					-- Store the command
					M.last_cmd = command

					-- Get the key that was used to submit
					local key = selected_key or mappings.current
					local direction
					for k, v in pairs(mappings) do
						if v == key then
							direction = k
							break
						end
					end

					Job.start_job({
						label = "Command: " .. command,
						command = command,
						silent = false,
						watch = direction == "watch_job",
						terminal = direction ~= "background_job",
						direction = direction,
						on_complete = on_refresh,
					})

					-- Schedule the mode change to happen after the input is processed
					vim.schedule(function()
						vim.cmd("stopinsert")
					end)
				end
			end,
		}

		-- Create custom mappings for the input buffer
		local map_opts = { noremap = true, silent = true }
		local function create_key_handler(key)
			return function()
				selected_key = key
				vim.fn.feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, true, true), "n")
			end
		end

		vim.keymap.set("i", mappings.background_job, create_key_handler(mappings.background_job), map_opts)
		vim.keymap.set("i", mappings.vertical, create_key_handler(mappings.vertical), map_opts)
		vim.keymap.set("i", mappings.split, create_key_handler(mappings.split), map_opts)
		vim.keymap.set("i", mappings.tab, create_key_handler(mappings.tab), map_opts)
		vim.keymap.set("i", mappings.watch_job, create_key_handler(mappings.watch_job), map_opts)

		-- Show the input dialog
		vim.ui.input(input_opts, input_opts.callback)
	end
end

-- Job previewer helper
function M.create_job_previewer(jobs_list, preview_bufnr)
	return function(entry_index)
		local job = jobs_list[entry_index]
		if not job then
			return
		end

		if Job.is_job_running(job.id) then
			-- For running jobs
			local preview_key = Job.get_preview_key(preview_bufnr, job.id)
			if not Job.is_preview_configured(preview_key) then
				Job.configure_preview(preview_key, job.id, preview_bufnr)
			else
				-- Subsequent updates
				local output = Job.get_buffer_content(job.id)
				if output and #output > 0 then
					Job.preview_job_output(output, preview_bufnr)
				end
			end
		else
			-- For completed jobs, use stored output
			local background_job = Job.get_background_job(job.id)
			local output = background_job.output or {}
			if type(output) == "string" then
				output = vim.split(output, "\n")
			end
			vim.bo[preview_bufnr].filetype = "sh"
			Job.preview_job_output(output, preview_bufnr)
		end
	end
end

return M