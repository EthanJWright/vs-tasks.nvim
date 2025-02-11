local actions = require("telescope.actions")
local state = require("telescope.actions.state")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local sorters = require("telescope.sorters")
local previewers = require("telescope.previewers")
local Parse = require("vstask.Parse")
local Opts = require("vstask.Opts")
local quickfix = require("vstask.Quickfix")
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
local live_output_buffers = {} -- Track buffers showing live job output
local Term_opts = {}

local function scroll_to_bottom(win_id)
	if win_id and win_id ~= -1 then
		local buf = vim.api.nvim_win_get_buf(win_id)
		local line_count = vim.api.nvim_buf_line_count(buf)
		if line_count > 0 then
			vim.api.nvim_win_set_cursor(win_id, { line_count, 0 })
		end
	end
end

local split_to_direction = function(direction)
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

local LABEL_PRE = "Task: "

local function get_buf_counter(label)
	local base_name = LABEL_PRE .. label
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

local function name_buffer(buf, label)
	local name = get_buf_counter(label)
	vim.api.nvim_buf_set_name(buf, name)
end

-- Function to get terminal buffer content
local function get_buffer_content(buf_job_id)
	-- Check if job exists
	if not buf_job_id or not background_jobs[buf_job_id] then
		return {}
	end

	-- Find the terminal buffer for this job
	for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf_id) then
			local buf_name = vim.api.nvim_buf_get_name(buf_id)
			local job_label = background_jobs[buf_job_id].label
			if buf_name:match(vim.pesc(LABEL_PRE .. job_label)) then
				return vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
			end
		end
	end
	return {}
end

local start_job = function(opts)
	-- Default options
	local options = {
		label = opts.label,
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
		split_to_direction(options.direction)
	else
		notify("Starting backgrounded task... " .. options.label, vim.log.levels.INFO)
	end

	-- show the buffer
	vim.api.nvim_win_set_buf(0, buf)

	-- Enable terminal scrolling
	vim.api.nvim_create_autocmd("TermOpen", {
		buffer = buf,
		callback = function()
			-- Set terminal options
			vim.opt_local.scrolloff = 0
			-- Start in terminal mode
			vim.cmd("startinsert")
			-- Scroll to bottom
			scroll_to_bottom(vim.api.nvim_get_current_win())
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
			if data and live_output_buffers[job_id] and vim.api.nvim_buf_is_valid(live_output_buffers[job_id]) then
				vim.schedule(function()
					-- Copy terminal buffer content to live output buffer
					local content = get_buffer_content(job_id)
					vim.api.nvim_buf_set_lines(live_output_buffers[job_id], 0, -1, false, content)

					-- Always scroll to bottom for live updates
					local win = vim.fn.bufwinid(live_output_buffers[job_id])
					scroll_to_bottom(win)
				end)

				-- Trigger update for preview buffers
				vim.schedule(function()
					vim.api.nvim_exec_autocmds("User", { pattern = "VsTaskJobOutput" })
				end)
			end
		end,
		on_stderr = function(_, data)
			if data and live_output_buffers[job_id] and vim.api.nvim_buf_is_valid(live_output_buffers[job_id]) then
				vim.schedule(function()
					-- Copy terminal buffer content to live output buffer
					local content = get_buffer_content(job_id)
					vim.api.nvim_buf_set_lines(live_output_buffers[job_id], 0, -1, false, content)

					-- Scroll to bottom if cursor was at bottom
					local win = vim.fn.bufwinid(live_output_buffers[job_id])
					if win ~= -1 then
						local curr_line = vim.api.nvim_win_get_cursor(win)[1]
						local line_count = vim.api.nvim_buf_line_count(live_output_buffers[job_id])
						if curr_line >= line_count - 5 then
							scroll_to_bottom(win)
						end
					end
				end)
			end
		end,
		on_exit = function(_, exit_code)
			local job = background_jobs[job_id]

			if job == nil then
				return
			end

			if exit_code == 0 then
				notify("🟢 Job completed successfully : " .. job.label, vim.log.levels.INFO)
				quickfix.close()
			else
				notify("🔴 Job failed." .. job.label, vim.log.levels.ERROR)
				local content = get_buffer_content(job_id)
				quickfix.toquickfix(content)
			end

			-- Always record end time and exit code
			background_jobs[job_id].end_time = os.time()
			background_jobs[job_id].exit_code = exit_code

			-- Keep completed job in background_jobs unless it's a watch job
			if not job.watch then
				-- Get final output from terminal buffer
				local content = get_buffer_content(job_id)
				-- Update the job with final state
				background_jobs[job_id] = {
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
			output = get_buffer_content(job_id),
			watch = options.watch,
			label = options.label,
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
		start_job({
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
			start_job({
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

local function set_mappings(new_mappings)
	for key, value in pairs(new_mappings) do
		Mappings[key] = value
	end
end

local function toggle_watch(id)
	background_jobs[id].watch = not background_jobs[id].watch
end

local function preview_job_output(output, bufnr, job_id)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	-- Ensure output is a table
	local lines = type(output) == "table" and output or {}

	-- Get last 1000 lines
	local max_lines = 1000
	local start_idx = #lines > max_lines and #lines - max_lines or 0
	local recent_output = vim.list_slice(lines, start_idx + 1)

	-- Set the lines in the preview buffer
	vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, recent_output)
	vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
	vim.api.nvim_set_option_value("filetype", "sh", { buf = bufnr })

	-- Scroll to bottom of preview
	vim.schedule(function()
		local win = vim.fn.bufwinid(bufnr)
		if win ~= -1 then
			local line_count = vim.api.nvim_buf_line_count(bufnr)
			if line_count > 0 then
				vim.api.nvim_win_set_cursor(win, { line_count, 0 })
			end
		end
	end)

	-- Set up live updates for preview if job is running
	if job_id and background_jobs[job_id] then
		-- Remove any existing autocmds for this buffer
		vim.api.nvim_create_autocmd("User", {
			pattern = "VsTaskJobOutput",
			callback = function()
				if vim.api.nvim_buf_is_valid(bufnr) then
					-- Get fresh content from terminal buffer
					local content = get_buffer_content(job_id)
					preview_job_output(content, bufnr)
				end
			end,
		})
	end
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
		run_dependent_tasks(task, selection_list)
		return
	end

	if direction == "background_job" or direction == "watch_job" then
		-- If task has dependencies, run them first
		start_job({
			label = label,
			command = cleaned,
			silent = false,
			watch = direction == "watch_job",
			terminal = false,
		})
	else
		local process = function(prepared_command)
			start_job({
				label = label,
				command = prepared_command,
				silent = false,
				watch = false,
				terminal = true,
				direction = direction,
			})
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
	-- Store current window, cursor position, and mode
	local current_win = vim.api.nvim_get_current_win()
	local current_pos = vim.api.nvim_win_get_cursor(current_win)
	local current_buf = vim.api.nvim_get_current_buf()
	local current_mode = vim.api.nvim_get_mode().mode

	for _, job_info in pairs(background_jobs) do
		if job_info.watch then
			local command = job_info.command
			local job_id = job_info.id
			local job_label = job_info.label

			-- Find and delete the buffer associated with this job
			for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_valid(buf_id) then
					local buf_name = vim.api.nvim_buf_get_name(buf_id)
					if buf_name:match(vim.pesc(LABEL_PRE .. job_label)) then
						-- Force delete the buffer
						vim.api.nvim_buf_delete(buf_id, { force = true })
						break
					end
				end
			end

			-- Stop the job
			vim.fn.jobstop(job_id)

			-- Use timer to ensure job is fully stopped before restarting
			local job_status = vim.fn.jobwait({ job_id }, -1)[1]
			local is_running = job_status == -1
			if not is_running then
				-- Remove from background_jobs to prevent duplicate entries
				background_jobs[job_id] = nil

				-- Remove from live_output_buffers if present
				if live_output_buffers[job_id] then
					live_output_buffers[job_id] = nil
				end

				-- Job is confirmed stopped, start new one
				vim.schedule(function()
					start_job({
						label = job_label,
						command = command,
						silent = false,
						watch = true,
						terminal = false, -- Start in background
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

local function open_buffer(label)
	-- Find the terminal buffer for this job
	for _, buf_id in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf_id) then
			local buf_name = vim.api.nvim_buf_get_name(buf_id)
			if buf_name:match(vim.pesc(LABEL_PRE .. label)) then
				vim.api.nvim_win_set_buf(0, buf_id)
				-- Schedule scrolling to bottom to ensure buffer is loaded
				vim.schedule(function()
					scroll_to_bottom(vim.api.nvim_get_current_win())
				end)
				return
			end
		end
	end
end

local function background_jobs_list(opts)
	opts = opts or {}

	local jobs_list = {}
	local jobs_formatted = {}

	-- Add all jobs (both running and completed)
	for job_id, job_info in pairs(background_jobs) do
		local is_running = not job_info.completed and vim.fn.jobwait({ job_id }, 0)[1] == -1
		table.insert(jobs_list, job_info)
		table.insert(jobs_formatted, format_job_entry(job_info, is_running))
	end

	if vim.tbl_isempty(jobs_formatted) then
		vim.notify("No jobs available", vim.log.levels.INFO)
		return
	end

	-- Sort all jobs by start_time (most recent first)
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
					if not job then
						return
					end

					local output
					if job.id and background_jobs[job.id] then
						-- For running jobs, get fresh content from terminal
						output = get_buffer_content(job.id)
						preview_job_output(output, self.state.bufnr, job.id)
					else
						-- For completed jobs, use stored output
						output = job.output or {}
						if type(output) == "string" then
							output = vim.split(output, "\n")
						end
						preview_job_output(output, self.state.bufnr)
					end
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
					open_buffer(job.label)
				end

				local open_vertical = function()
					local selection = state.get_selected_entry(prompt_bufnr)
					actions.close(prompt_bufnr)
					local job = jobs_list[selection.index]
					split_to_direction("vertical")
					open_buffer(job.label)
				end

				local open_horizontal = function()
					local selection = state.get_selected_entry(prompt_bufnr)
					actions.close(prompt_bufnr)
					local job = jobs_list[selection.index]
					split_to_direction("horizontal")
					open_buffer(job.label)
				end

				map("i", Mappings.kill_job, kill_job)
				map("n", Mappings.kill_job, kill_job)
				map("i", Mappings.current, open_history)
				map("n", Mappings.current, open_history)
				map("i", Mappings.split, open_horizontal)
				map("n", Mappings.split, open_horizontal)
				map("i", Mappings.vertical, open_vertical)
				map("n", Mappings.vertical, open_vertical)
				map("i", Mappings.watch_job, toggle_watch_binding)
				map("n", Mappings.watch_job, toggle_watch_binding)

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
	Set_mappings = set_mappings,
	Set_term_opts = set_term_opts,
	Get_last = get_last,
}
