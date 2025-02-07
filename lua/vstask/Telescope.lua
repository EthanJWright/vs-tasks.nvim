local actions = require("telescope.actions")
local state = require("telescope.actions.state")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local sorters = require("telescope.sorters")
local previewers = require("telescope.previewers")
local Parse = require("vstask.Parse")
local Opts = require("vstask.Opts")
local quickfix = require("vstask.Quickfix")
local Command_handler = nil
local Mappings = {
	vertical = "<C-v>",
	split = "<C-p>",
	tab = "<C-t>",
	current = "<CR>",
	background_job = "<C-b>",
	watch_job = "<C-w>",
	kill_job = "<C-d>",
	run = "<C-r>",
}

local command_history = {}
local background_jobs = {}
local job_history = {}
local live_output_buffers = {} -- Track buffers showing live job output

local process_command_background = function(label, command, silent, watch, on_complete)
	local function notify(msg, level)
		if not silent then
			vim.notify(msg, level, { title = "vs-tasks" })
		end
	end

	if watch then
		Add_watch_autocmd()
	end

	notify("Running in background: " .. command, vim.log.levels.INFO)

	local output = {}
	local job_id
	job_id = vim.fn.jobstart(command, {
		on_stdout = function(_, data)
			if data then
				vim.list_extend(output, data)
				-- Update live output buffer if it exists
				if live_output_buffers[job_id] and vim.api.nvim_buf_is_valid(live_output_buffers[job_id]) then
					vim.schedule(function()
						vim.api.nvim_buf_set_lines(live_output_buffers[job_id], 0, -1, false, output)
						-- Always scroll to bottom for live updates
						local win = vim.fn.bufwinid(live_output_buffers[job_id])
						if win ~= -1 then
							local line_count = vim.api.nvim_buf_line_count(live_output_buffers[job_id])
							vim.api.nvim_win_set_cursor(win, { line_count, 0 })
						end
					end)
				end
				-- Trigger update for preview buffers
				vim.schedule(function()
					vim.api.nvim_exec_autocmds("User", { pattern = "VsTaskJobOutput" })
				end)
			end
		end,
		on_stderr = function(_, data)
			if data then
				vim.list_extend(output, data)
				-- Update live output buffer if it exists
				if live_output_buffers[job_id] and vim.api.nvim_buf_is_valid(live_output_buffers[job_id]) then
					vim.schedule(function()
						vim.api.nvim_buf_set_lines(live_output_buffers[job_id], 0, -1, false, output)
						-- Scroll to bottom if cursor was at bottom
						local win = vim.fn.bufwinid(live_output_buffers[job_id])
						if win ~= -1 then
							local curr_line = vim.api.nvim_win_get_cursor(win)[1]
							local line_count = vim.api.nvim_buf_line_count(live_output_buffers[job_id])
							if curr_line >= line_count - 5 then
								vim.api.nvim_win_set_cursor(win, { line_count, 0 })
							end
						end
					end)
				end
			end
		end,
		on_exit = function(_, exit_code)
			local job = background_jobs[job_id]

			if job == nil then
				return
			end

			if exit_code == 0 then
				notify("🟢 Background job completed successfully : " .. job.label, vim.log.levels.INFO)
			else
				notify("🔴 Background job failed." .. job.label, vim.log.levels.ERROR)
				quickfix.toquickfix(table.concat(output, "\n"))
			end

			-- Always record end time and exit code
			background_jobs[job_id].end_time = os.time()
			background_jobs[job_id].exit_code = exit_code

			-- Add to history unless it's a watch job
			if not job.watch then
				table.insert(job_history, {
					label = job.label,
					end_time = os.time(),
					start_time = job.start_time or os.time(), -- Ensure we always have a start_time
					exit_code = exit_code,
					output = job.output,
				})
				background_jobs[job_id] = nil
			end
			if on_complete ~= nil then
				on_complete()
			end
		end,
	})

	if job_id <= 0 then
		notify("Failed to start background job: " .. command, vim.log.levels.ERROR)
	else
		background_jobs[job_id] = {
			id = job_id,
			command = command,
			start_time = os.time(),
			output = output,
			watch = watch,
			label = label,
			end_time = 0,
			exit_code = -1,
		}
	end
end

local function clean_command(pre, options)
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

local function set_history(label, command, options)
	if not command_history[label] then
		command_history[label] = {
			command = command,
			options = options,
			label = label,
			hits = 1,
		}
	else
		command_history[label].hits = command_history[label].hits + 1
	end
	Parse.Used_task(label)
end

local last_cmd = nil
local Term_opts = {}

local function set_term_opts(new_opts)
	Term_opts = new_opts
end

local function get_last()
	return last_cmd
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

-- Run dependent tasks sequentially in background
local function run_dependent_tasks(task, task_list)
	local deps = type(task.dependsOn) == "string" and { task.dependsOn } or task.dependsOn
	local task_queue = {}

	-- Run each dependent task
	for _, dep_label in ipairs(deps) do
		local dep_task = find_task_by_label(dep_label, task_list)
		if dep_task then
			local command = clean_command(dep_task.command, dep_task.options)
			task_queue[#task_queue + 1] = { label = dep_task.label, command = command }
		else
			vim.notify("Dependent task not found: " .. dep_label, vim.log.levels.ERROR)
		end
	end
	-- add the original task to the queue
	if task.command ~= nil then
		task_queue[#task_queue + 1] = { label = task.label, command = clean_command(task.command, task.options) }
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
		process_command_background(next_task.label, next_task.command, false, false, run_next_task)
	end

	local function run_all_tasks()
		-- Run all tasks in parallel
		for _, parallel_task in ipairs(task_queue) do
			process_command_background(parallel_task.label, parallel_task.command, false, false)
		end
	end

	if task.dependsOrder ~= nil and task.dependsOrder == "sequence" then
		run_next_task()
	else
		run_all_tasks()
	end
end

local function set_mappings(new_mappings)
	for key, value in pairs(new_mappings) do
		Mappings[key] = value
	end
end

local function toggle_watch(id)
	background_jobs[id].watch = not background_jobs[id].watch
end

local function preview_job_output(output, bufnr, job_id)
	local max_lines = 1000 -- Show last 1000 lines
	local start_idx = #output > max_lines and #output - max_lines or 0
	local recent_output = vim.list_slice(output, start_idx + 1)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, recent_output)
	vim.api.nvim_set_option_value("filetype", "sh", { buf = bufnr })
	-- Scroll to bottom of preview
	vim.schedule(function()
		local win = vim.fn.bufwinid(bufnr)
		if win ~= -1 then
			vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(bufnr), 0 })
			vim.api.nvim_set_option_value("filetype", "sh", { buf = bufnr })
		end
	end)

	-- Set up live updates for preview if job is running
	if job_id then
		local job = background_jobs[job_id]
		if job then
			-- Create autocmd to update preview buffer
			vim.api.nvim_create_autocmd("User", {
				pattern = "VsTaskJobOutput",
				callback = function()
					if vim.api.nvim_buf_is_valid(bufnr) then
						preview_job_output(job.output, bufnr)
					end
				end,
			})
		end
	end
end
local function open_job_output(output, job_id, direction)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)

	if direction == "vertical" then
		vim.cmd("vsplit")
	end

	vim.api.nvim_win_set_buf(0, buf)
	vim.api.nvim_set_option_value("filetype", "sh", { buf = buf })

	-- Set buffer name to indicate live status
	if job_id then
		local job = background_jobs[job_id]
		if job then
			vim.api.nvim_buf_set_name(buf, string.format("Job Output - %s (Live)", job.label))
			live_output_buffers[job_id] = buf

			-- Set buffer local autocmd to clean up when buffer is closed
			vim.api.nvim_create_autocmd("BufWipeout", {
				buffer = buf,
				callback = function()
					live_output_buffers[job_id] = nil
				end,
			})
		end
	end
end

local process_command = function(command, direction, opts)
	last_cmd = command
	if Command_handler ~= nil then
		Command_handler(command, direction, opts)
	else
		local opt_direction = Opts.get_direction(direction, opts)
		local size = Opts.get_size(direction, opts)
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
		vim.cmd(string.format('terminal echo "%s" && %s', command, command))
	end
end

local function set_command_handler(handler)
	Command_handler = handler
end

local function inputs(opts)
	opts = opts or {}

	local input_list = Parse.Inputs()

	if input_list == nil or vim.tbl_isempty(input_list) then
		return
	end

	local inputs_formatted = {}
	local selection_list = {}

	for _, input_dict in pairs(input_list) do
		local description = "set input"
		if input_dict["command"] == "extension.commandvariable.pickStringRemember" then
			description = "pick input from set list"
		end

		if input_dict["description"] ~= nil then
			description = input_dict["description"]
		end

		local add_current = ""
		if input_dict["value"] ~= "" then
			add_current = " [" .. input_dict["value"] .. "] "
		end
		local current_task = input_dict["id"] .. add_current .. " => " .. description
		table.insert(inputs_formatted, current_task)
		table.insert(selection_list, input_dict)
	end

	pickers
		.new(opts, {
			prompt_title = "Inputs",
			finder = finders.new_table({
				results = inputs_formatted,
			}),
			sorter = sorters.get_generic_fuzzy_sorter(),
			attach_mappings = function(prompt_bufnr, map)
				local start_task = function()
					local selection = state.get_selected_entry(prompt_bufnr)
					actions.close(prompt_bufnr)

					local input = selection_list[selection.index]["id"]
					Parse.Set(input, opts)
				end

				map("i", "<CR>", start_task)
				map("n", "<CR>", start_task)

				return true
			end,
		})
		:find()
end

local function handle_direction(direction, prompt_bufnr, selection_list, is_launch, opts)
	local selection = state.get_selected_entry(prompt_bufnr)
	actions.close(prompt_bufnr)

	local command, options, label, args

	if selection == nil or direction == "run" then
		if direction == "run" then
			direction = "current"
		end
		local current_line = state.get_current_line()
		command = current_line
		options = nil
		label = "CMD: " .. current_line
		args = nil
		set_history(label, command, options)
	elseif is_launch then
		command = selection_list[selection.index]["program"]
		options = selection_list[selection.index]["options"]
		label = selection_list[selection.index]["name"]
		args = selection_list[selection.index]["args"]
		Parse.Used_launch(label)
	else
		command = selection_list[selection.index]["command"]
		options = selection_list[selection.index]["options"]
		label = selection_list[selection.index]["label"]
		args = selection_list[selection.index]["args"]
		set_history(label, command, options)
	end

	local cleaned = clean_command(command, options)

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

	if task and task.dependsOn then
		run_dependent_tasks(task, selection_list, function()
			process_command_background(label, cleaned, false, direction == "watch_job")
		end)
		return
	end

	if direction == "background_job" or direction == "watch_job" then
		-- If task has dependencies, run them first
		process_command_background(label, cleaned, false, direction == "watch_job")
	else
		local process = function(prepared_command)
			process_command(prepared_command, direction, Term_opts)
			if direction ~= "current" then
				vim.cmd("normal! G")
			end
		end
		Parse.replace_and_run(cleaned, process, opts)
	end
end

local function start_launch_direction(direction, prompt_bufnr, _, selection_list, opts)
	handle_direction(direction, prompt_bufnr, selection_list, true, opts)
end

local function start_task_direction(direction, prompt_bufnr, _, selection_list, opts)
	handle_direction(direction, prompt_bufnr, selection_list, false, opts)
end

local function history(opts)
	if vim.tbl_isempty(command_history) then
		return
	end
	-- sort command history by hits
	local sorted_history = {}
	for _, command in pairs(command_history) do
		table.insert(sorted_history, command)
	end
	table.sort(sorted_history, function(a, b)
		return a.hits > b.hits
	end)

	-- build label table
	local labels = {}
	for i = 1, #sorted_history do
		local current_task = sorted_history[i]["label"]
		table.insert(labels, current_task)
	end

	pickers
		.new(opts, {
			prompt_title = "Task History",
			finder = finders.new_table({
				results = labels,
			}),
			sorter = sorters.get_generic_fuzzy_sorter(),
			attach_mappings = function(prompt_bufnr, map)
				local function start_task()
					start_task_direction("current", prompt_bufnr, map, sorted_history, opts)
				end
				local function start_task_vertical()
					start_task_direction("vertical", prompt_bufnr, map, sorted_history, opts)
				end
				local function start_task_split()
					start_task_direction("horizontal", prompt_bufnr, map, sorted_history, opts)
				end
				local function start_task_tab()
					start_task_direction("tab", prompt_bufnr, map, sorted_history, opts)
				end
				map("i", Mappings.current, start_task)
				map("n", Mappings.current, start_task)
				map("i", Mappings.vertical, start_task_vertical)
				map("n", Mappings.vertical, start_task_vertical)
				map("i", Mappings.split, start_task_split)
				map("n", Mappings.split, start_task_split)
				map("i", Mappings.tab, start_task_tab)
				map("n", Mappings.tab, start_task_tab)
				return true
			end,
		})
		:find()
end

local function tasks(opts)
	opts = opts or {}

	local task_list = Parse.Tasks()

	if opts.run_empty then
		task_list = {}
	end

	if task_list == nil then
		vim.notify("No tasks found", vim.log.levels.INFO)
		return
	end

	if vim.tbl_isempty(task_list) and opts.run_empty ~= true then
		return
	end

	local tasks_formatted = {}

	for i = 1, #task_list do
		local current_task = task_list[i]["label"]
		table.insert(tasks_formatted, current_task)
	end

	pickers
		.new(opts, {
			prompt_title = "Tasks",
			finder = finders.new_table({
				results = tasks_formatted,
			}),
			sorter = sorters.get_generic_fuzzy_sorter(),
			attach_mappings = function(prompt_bufnr, map)
				local function setup_direction_mappings(direction_handler)
					local directions = {
						current = Mappings.current,
						vertical = Mappings.vertical,
						horizontal = Mappings.split,
						tab = Mappings.tab,
						background_job = Mappings.background_job,
						watch_job = Mappings.watch_job,
						run = Mappings.run,
					}

					for direction, mapping in pairs(directions) do
						local handler = function()
							direction_handler(direction, prompt_bufnr, map, task_list, opts)
						end
						map("i", mapping, handler)
						map("n", mapping, handler)
					end
				end

				setup_direction_mappings(start_task_direction)
				return true
			end,
		})
		:find()
end

local function tasks_empty(opts)
	opts = opts or {}
	opts.run_empty = true
	tasks(opts)
end

local function launches(opts)
	opts = opts or {}

	local launch_list = Parse.Launches()

	if vim.tbl_isempty(launch_list) then
		return
	end

	local launch_formatted = {}

	for i = 1, #launch_list do
		local current_launch = launch_list[i]["name"]
		table.insert(launch_formatted, current_launch)
	end

	pickers
		.new(opts, {
			prompt_title = "Launches",
			finder = finders.new_table({
				results = launch_formatted,
			}),
			sorter = sorters.get_generic_fuzzy_sorter(),
			attach_mappings = function(prompt_bufnr, map)
				local function setup_direction_mappings(direction_handler)
					local directions = {
						current = Mappings.current,
						vertical = Mappings.vertical,
						horizontal = Mappings.split,
						tab = Mappings.tab,
					}

					for direction, mapping in pairs(directions) do
						local handler = function()
							direction_handler(direction, prompt_bufnr, map, launch_list)
						end
						map("i", mapping, handler)
						map("n", mapping, handler)
					end
				end

				setup_direction_mappings(start_launch_direction)
				return true
			end,
		})
		:find()
end

local function restart_watched_jobs()
	for _, job_info in pairs(background_jobs) do
		if job_info.watch then
			local command = job_info.command
			local job_id = job_info.id
			-- Stop the job and wait for confirmation before starting new one
			vim.fn.jobstop(job_id)

			-- Use timer to ensure job is fully stopped before restarting
			local job_status = vim.fn.jobwait({ job_id }, -1)[1]
			local is_running = job_status == -1
			if not is_running then
				-- Remove from background_jobs to prevent duplicate entries
				background_jobs[job_id] = nil

				-- Job is confirmed stopped, start new one
				process_command_background(job_info.label, command, false, true)
			else
				vim.notify(string.format("Job %d is still running, skipping restart", job_id), vim.log.levels.INFO)
			end
		end
	end
end

function Add_watch_autocmd()
	-- Check if autocmd already exists
	local autocmds = vim.api.nvim_get_autocmds({
		event = "BufWritePost",
		pattern = "*",
	})

	local existing = vim.tbl_filter(function(autocmd)
		return autocmd.desc == "Restart watched background tasks on file save"
	end, autocmds)

	if #existing == 0 then
		vim.api.nvim_create_autocmd("BufWritePost", {
			pattern = "*",
			callback = restart_watched_jobs,
			desc = "Restart watched background tasks on file save",
		})
	end
end

local function format_job_entry(job_info, is_running)
	local runtime
	if is_running then
		runtime = os.time() - job_info.start_time - (job_info.end_time or 0)
	else
		runtime = job_info.end_time - job_info.start_time
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

local function background_jobs_list(opts)
	opts = opts or {}

	local jobs_list = {}
	local jobs_formatted = {}

	for job_id, job_info in pairs(background_jobs) do
		table.insert(jobs_list, job_info)
		local job_status = vim.fn.jobwait({ job_id }, 0)[1]
		local is_running = job_status == -1
		table.insert(jobs_formatted, format_job_entry(job_info, is_running))
	end

	if vim.tbl_isempty(jobs_formatted) then
		vim.notify("No background jobs running", vim.log.levels.INFO)
		return
	end

	-- Sort jobs_list by start_time (most recent first)
	table.sort(jobs_list, function(a, b)
		return a.start_time > b.start_time
	end)

	pickers
		.new(opts, {
			prompt_title = "Background Jobs",
			finder = finders.new_table({
				results = jobs_formatted,
			}),
			sorter = sorters.get_generic_fuzzy_sorter(),
			previewer = previewers.new_buffer_previewer({
				title = "Job Output",
				define_preview = function(self, entry)
					local job = jobs_list[entry.index]
					local output = job.output or {}
					preview_job_output(output, self.state.bufnr, job.id)
				end,
			}),
			attach_mappings = function(prompt_bufnr, map)
				local kill_job = function()
					local selection = state.get_selected_entry(prompt_bufnr)
					actions.close(prompt_bufnr)

					local job = jobs_list[selection.index]
					vim.fn.jobstop(job.id)
					vim.notify(string.format("Killed job %d: %s", job.id, job.command), vim.log.levels.INFO)
					background_jobs[job.id] = nil
				end

				local toggle_watch_binding = function()
					local selection = state.get_selected_entry(prompt_bufnr)
					actions.close(prompt_bufnr)
					local job = jobs_list[selection.index]
					toggle_watch(job.id)
				end

				local open_history = function()
					local selection = state.get_selected_entry(prompt_bufnr)
					actions.close(prompt_bufnr)
					local job = jobs_list[selection.index]
					local output = job.output or {}
					open_job_output(output, job.id)
				end

				local open_in_temp_buffer_vertical = function()
					local selection = state.get_selected_entry(prompt_bufnr)
					actions.close(prompt_bufnr)
					local job = jobs_list[selection.index]
					local output = job.output or {}
					open_job_output(output, job.id, "vertical")
				end

				map("i", Mappings.kill_job, kill_job)
				map("n", Mappings.kill_job, kill_job)
				map("i", Mappings.current, open_history)
				map("n", Mappings.current, open_history)
				map("i", Mappings.split, open_in_temp_buffer_vertical)
				map("n", Mappings.split, open_in_temp_buffer_vertical)
				map("i", Mappings.watch_job, toggle_watch_binding)
				map("n", Mappings.watch_job, toggle_watch_binding)

				return true
			end,
		})
		:find()
end

local function job_history_list(opts)
	opts = opts or {}

	if vim.tbl_isempty(job_history) then
		vim.notify("No job history available", vim.log.levels.INFO)
		return
	end

	-- Create a copy of job_history to avoid modifying the original
	local sorted_history = vim.deepcopy(job_history)

	-- Sort by start_time (most recent first)
	table.sort(sorted_history, function(a, b)
		return a.start_time > b.start_time
	end)

	local jobs_formatted = {}
	for _, job_info in ipairs(sorted_history) do
		table.insert(jobs_formatted, format_job_entry(job_info, false))
	end

	pickers
		.new(opts, {
			prompt_title = "Job History",
			finder = finders.new_table({
				results = jobs_formatted,
			}),
			sorter = sorters.get_generic_fuzzy_sorter(),
			previewer = previewers.new_buffer_previewer({
				title = "Job Info",
				define_preview = function(self, entry)
					local job = job_history[entry.index]
					local output = job.output or {}
					preview_job_output(output, self.state.bufnr)
				end,
			}),
			attach_mappings = function(prompt_bufnr, map)
				local function open_in_temp_buffer()
					local selection = state.get_selected_entry(prompt_bufnr)
					actions.close(prompt_bufnr)
					local job = job_history[selection.index]
					local output = job.output or {}
					local buf = vim.api.nvim_create_buf(false, true)
					vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)
					vim.api.nvim_set_option_value("filetype", "sh", { buf = buf })
					vim.api.nvim_win_set_buf(0, buf)
				end

				local function open_in_temp_buffer_vertical()
					local selection = state.get_selected_entry(prompt_bufnr)
					actions.close(prompt_bufnr)
					local job = job_history[selection.index]
					vim.cmd("vsplit")
					local output = job.output or {}
					local buf = vim.api.nvim_create_buf(false, true)
					vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)
					vim.api.nvim_set_option_value("filetype", "sh", { buf = buf })
					vim.api.nvim_win_set_buf(0, buf)
				end

				map("i", Mappings.current, open_in_temp_buffer)
				map("n", Mappings.current, open_in_temp_buffer)
				map("i", Mappings.vertical, open_in_temp_buffer_vertical)
				map("n", Mappings.vertical, open_in_temp_buffer_vertical)

				return true
			end,
		})
		:find()
end

return {
	Launch = launches,
	Tasks = tasks,
	Tasks_empty = tasks_empty,
	Inputs = inputs,
	History = history,
	Jobs = background_jobs_list,
	JobHistory = job_history_list,
	Set_command_handler = set_command_handler,
	Set_mappings = set_mappings,
	Set_term_opts = set_term_opts,
	Get_last = get_last,
}
