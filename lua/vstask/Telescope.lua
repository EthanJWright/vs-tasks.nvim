local actions = require("telescope.actions")
local state = require("telescope.actions.state")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local sorters = require("telescope.sorters")
local previewers = require("telescope.previewers")
local Parse = require("vstask.Parse")
local Opts = require("vstask.Opts")
local Command_handler = nil
local Mappings = {
	vertical = "<C-v>",
	split = "<C-p>",
	tab = "<C-t>",
	current = "<CR>",
	background = "<C-b>",
	watch = "<C-w>",
}

local command_history = {}
local background_jobs = {}
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

local function format_command(pre, options)
	local command = pre
	if type(options) == "table" then
		local cwd = options["cwd"]
		if type(cwd) == "string" then
			local cd_command = string.format("cd %s", cwd)
			command = string.format("%s && %s", cd_command, command)
		end
	end
	command = Parse.replace(command)
	return {
		pre = pre,
		command = command,
		options = options,
	}
end

local function set_mappings(new_mappings)
	if new_mappings.vertical ~= nil then
		Mappings.vertical = new_mappings.vertical
	end
	if new_mappings.split ~= nil then
		Mappings.split = new_mappings.split
	end
	if new_mappings.tab ~= nil then
		Mappings.tab = new_mappings.tab
	end
	if new_mappings.current ~= nil then
		Mappings.current = new_mappings.current
	end
end

local function toggle_watch(id)
	background_jobs[id].watch = not background_jobs[id].watch
end

local process_command_background = function(label, command, silent, watch)
	local function notify(msg, level)
		if not silent then
			vim.notify(msg, level)
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
			end
		end,
		on_stderr = function(_, data)
			if data then
				vim.list_extend(output, data)
			end
		end,
		on_exit = function(_, exit_code)
			if background_jobs[job_id].watch == true then
				return
			end

			if exit_code == 0 then
				notify("Background job completed: " .. command, vim.log.levels.INFO)
			else
				local error_msg = table.concat(output, "\n")
				notify("Background job failed: " .. command .. "\nOutput:\n" .. error_msg, vim.log.levels.ERROR)
			end
			background_jobs[job_id] = nil
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
		}
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
		local add_current = ""
		if input_dict["value"] ~= "" then
			add_current = " [" .. input_dict["value"] .. "] "
		end
		local current_task = input_dict["id"] .. add_current .. " => " .. input_dict["description"]
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
					Parse.Set(input)
				end

				map("i", "<CR>", start_task)
				map("n", "<CR>", start_task)

				return true
			end,
		})
		:find()
end

local function handle_direction(direction, prompt_bufnr, selection_list, is_launch)
	local selection = state.get_selected_entry(prompt_bufnr)
	actions.close(prompt_bufnr)

	local command, options, label, args
	if is_launch then
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

	local formatted_command = format_command(command, options)
	if args ~= nil then
		formatted_command.command = Parse.Build_launch(formatted_command.command, args)
	end

	if direction == "background" or direction == "watch" then
		process_command_background(label, formatted_command.command, false, direction == "watch")
	else
		process_command(formatted_command.command, direction, Term_opts)
		if direction ~= "current" then
			vim.cmd("normal! G")
		end
	end
end

local function start_launch_direction(direction, prompt_bufnr, _, selection_list)
	handle_direction(direction, prompt_bufnr, selection_list, true)
end

local function start_task_direction(direction, prompt_bufnr, _, selection_list)
	handle_direction(direction, prompt_bufnr, selection_list, false)
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
					start_task_direction("current", prompt_bufnr, map, sorted_history)
				end
				local function start_task_vertical()
					start_task_direction("vertical", prompt_bufnr, map, sorted_history)
				end
				local function start_task_split()
					start_task_direction("horizontal", prompt_bufnr, map, sorted_history)
				end
				local function start_task_tab()
					start_task_direction("tab", prompt_bufnr, map, sorted_history)
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

	if vim.tbl_isempty(task_list) then
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
						background = Mappings.background,
						watch = Mappings.watch,
					}

					for direction, mapping in pairs(directions) do
						local handler = function()
							direction_handler(direction, prompt_bufnr, map, task_list)
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
				process_command_background(job_info.label, command, true, true)
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

local function background_jobs_list(opts)
	opts = opts or {}

	local jobs_list = {}
	local jobs_formatted = {}

	for _, job_info in pairs(background_jobs) do
		table.insert(jobs_list, job_info)
		local runtime = os.time() - job_info.start_time
		local formatted = string.format("%s - (runtime %ds)", job_info.label, runtime)
		if job_info.watch then
			formatted = "󱥼 " .. formatted
		end
		table.insert(jobs_formatted, formatted)
	end

	if vim.tbl_isempty(jobs_formatted) then
		vim.notify("No background jobs running", vim.log.levels.INFO)
		return
	end

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
					vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, output)
					vim.api.nvim_set_option_value("filetype", "sh", { buf = self.state.bufnr })
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

				local open_in_temp_buffer = function()
					local selection = state.get_selected_entry(prompt_bufnr)
					actions.close(prompt_bufnr)
					local job = jobs_list[selection.index]
					local output = job.output or {}
					local buf = vim.api.nvim_create_buf(false, true)
					vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)
					vim.api.nvim_set_option_value("filetype", "sh", { buf = buf })
					vim.api.nvim_win_set_buf(0, buf)
				end

				map("i", "<C-k>", kill_job)
				map("n", "<C-k>", kill_job)
				map("i", "<CR>", open_in_temp_buffer)
				map("n", "<CR>", open_in_temp_buffer)
				map("i", "<C-w>", toggle_watch_binding)
				map("n", "<C-w>", toggle_watch_binding)

				return true
			end,
		})
		:find()
end

return {
	Launch = launches,
	Tasks = tasks,
	Inputs = inputs,
	History = history,
	Jobs = background_jobs_list,
	Set_command_handler = set_command_handler,
	Set_mappings = set_mappings,
	Set_term_opts = set_term_opts,
	Get_last = get_last,
}
