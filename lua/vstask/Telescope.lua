local actions = require("telescope.actions")
local state = require("telescope.actions.state")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local sorters = require("telescope.sorters")
local previewers = require("telescope.previewers")
local Parse = require("vstask.Parse")
local Job = require("vstask.Job")
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

local last_cmd = nil
Picker = nil
local function set_term_opts(new_opts)
	Term_opts = new_opts
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

-- Format the jobs list for display
local function format_jobs_list(jobs_list)
	local jobs_formatted = {}
	for _, job_info in ipairs(jobs_list) do
		local is_running = not job_info.completed and vim.fn.jobwait({ job_info.id }, 0)[1] == -1
		table.insert(jobs_formatted, format_job_entry(job_info, is_running))
	end
	return jobs_formatted
end

local refresh_picker = function()
	local jobs_list = Job.build_jobs_list()
	local jobs_formatted = format_jobs_list(jobs_list)
	if Picker then
		Picker:refresh(
			finders.new_table({
				results = jobs_formatted,
			}),
			{ reset_prompt = false }
		)
	end
end

local function get_last()
	return last_cmd
end

local function command_input(opts)
	opts = opts or {}

	-- Create an input dialog
	local selected_key = nil
	local input_opts = {
		prompt = "Enter command: ",
		callback = function(command)
			if command and command ~= "" then
				-- Store the command
				last_cmd = command

				-- Get the key that was used to submit
				local key = selected_key or Mappings.current
				local direction
				for k, v in pairs(Mappings) do
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

	vim.keymap.set("i", Mappings.background_job, create_key_handler(Mappings.background_job), map_opts)
	vim.keymap.set("i", Mappings.vertical, create_key_handler(Mappings.vertical), map_opts)
	vim.keymap.set("i", Mappings.split, create_key_handler(Mappings.split), map_opts)
	vim.keymap.set("i", Mappings.tab, create_key_handler(Mappings.tab), map_opts)
	vim.keymap.set("i", Mappings.watch_job, create_key_handler(Mappings.watch_job), map_opts)

	-- Show the input dialog
	vim.ui.input(input_opts, input_opts.callback)
end

local function set_mappings(new_mappings)
	for key, value in pairs(new_mappings) do
		Mappings[key] = value
	end
end

local function inputs_picker(opts)
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
					local selection = state.get_selected_entry()
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
	local selection = state.get_selected_entry()
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
			terminal = direction ~= "background_job",
			direction = direction,
			on_complete = function()
				refresh_picker()
			end,
		})
	end
	Parse.replace_and_run(cleaned, process, opts)
end

local function start_launch_direction(direction, prompt_bufnr, _, selection_list, opts)
	handle_direction(direction, prompt_bufnr, selection_list, true, opts)
end

local function start_task_direction(direction, prompt_bufnr, _, selection_list, opts)
	handle_direction(direction, prompt_bufnr, selection_list, false, opts)
end

local function tasks_picker(opts)
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

local function launches_picker(opts)
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
				Job.set_background_jobs(job_id, nil)

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
						on_complete = function()
							refresh_picker()
						end,
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

local function jobs_picker(opts)
	opts = opts or {}

	local jobs_list = Job.build_jobs_list()
	local jobs_formatted = format_jobs_list(jobs_list)

	if vim.tbl_isempty(jobs_formatted) then
		vim.notify("No jobs available", vim.log.levels.INFO)
		return
	end

	Picker = pickers.new(opts, {
		prompt_title = "Jobs",
		finder = finders.new_table({
			results = jobs_formatted,
		}),
		sorter = sorters.get_generic_fuzzy_sorter(),
		previewer = previewers.new_buffer_previewer({
			title = "Jobs",
			define_preview = function(self, entry)
				local job = jobs_list[entry.index]
				if not job then
					return
				end

				if Job.is_job_running(job.id) then
					-- For running jobs
					local preview_key = Job.get_preview_key(self.state.bufnr, job.id)
					if not Job.is_preview_configured(preview_key) then
						Job.configure_preview(preview_key, job.id, self.state.bufnr)
					else
						-- Subsequent updates
						local output = Job.get_buffer_content(job.id)
						if output and #output > 0 then
							Job.preview_job_output(output, self.state.bufnr)
						else
						end
					end
				else
					-- For completed jobs, use stored output
					local background_job = Job.get_background_job(job.id)
					local output = background_job.output or {}
					if type(output) == "string" then
						output = vim.split(output, "\n")
					end
					vim.bo[self.state.bufnr].filetype = "sh"
					Job.preview_job_output(output, self.state.bufnr)
				end
			end,
		}),
		attach_mappings = function(prompt_bufnr, map)
			local kill_job = function()
				local selection = state.get_selected_entry()
				local selected_job = jobs_list[selection.index]
				if not selected_job or not selected_job.id then
					return
				end

				local job = Job.get_background_job(selected_job.id)

				Job.fully_clear_job(job.id)

				-- Update the picker's job list
				local current_picker = state.get_current_picker(prompt_bufnr)

				-- Rebuild and format jobs list
				local updated_jobs_list = Job.build_jobs_list()
				local updated_jobs_formatted = format_jobs_list(updated_jobs_list)

				-- Update the finder with new results
				current_picker:refresh(
					finders.new_table({
						results = updated_jobs_formatted,
					}),
					{ reset_prompt = false }
				)

				-- Update the reference to jobs_list for the picker
				jobs_list = updated_jobs_list
			end
			local toggle_watch_binding = function()
				local selection = state.get_selected_entry()
				local job = jobs_list[selection.index]
				Job.toggle_watch(job.id)
			end

			local open_job = function()
				local selection = state.get_selected_entry()
				actions.close(prompt_bufnr)
				local job = jobs_list[selection.index]
				-- Update last selected time
				Job.job_selected(job.id)
				Job.open_buffer(job.label)
			end

			local open_vertical = function()
				local selection = state.get_selected_entry()
				actions.close(prompt_bufnr)
				local job = jobs_list[selection.index]
				-- Update last selected time
				Job.job_selected(job.id)
				Job.split_to_direction("vertical")
				Job.open_buffer(job.label)
			end

			local open_horizontal = function()
				local selection = state.get_selected_entry()
				actions.close(prompt_bufnr)
				local job = jobs_list[selection.index]
				-- Update last selected time
				Job.job_selected(job.id)
				vim.notify("selecting job: " .. job.label)
				Job.split_to_direction("horizontal")
				Job.open_buffer(job.label)
			end

			map("i", Mappings.kill_job, kill_job)
			map("n", Mappings.kill_job, kill_job)
			map("i", Mappings.current, open_job)
			map("n", Mappings.current, open_job)
			map("i", Mappings.split, open_horizontal)
			map("n", Mappings.split, open_horizontal)
			map("i", Mappings.vertical, open_vertical)
			map("n", Mappings.vertical, open_vertical)
			map("i", Mappings.watch_job, toggle_watch_binding)
			map("n", Mappings.watch_job, toggle_watch_binding)

			return true
		end,
	})
	if Picker then
		Picker:find()
	end
end

return {
	Launch = launches_picker,
	Tasks = tasks_picker,
	Inputs = inputs_picker,
	Jobs = jobs_picker,
	Set_mappings = set_mappings,
	Set_term_opts = set_term_opts,
	Get_last = get_last,
	Command = command_input,
}
