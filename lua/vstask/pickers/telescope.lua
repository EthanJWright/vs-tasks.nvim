local actions = require("telescope.actions")
local state = require("telescope.actions.state")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local sorters = require("telescope.sorters")
local previewers = require("telescope.previewers")

local Parse = require("vstask.Parse")
local Job = require("vstask.Job")
local core = require("vstask.picker_core")

local M = {}

-- Picker identification
M.name = "telescope"

-- Telescope-specific state
local current_picker = nil
local mappings = vim.tbl_deep_extend("force", {}, core.default_mappings)

-- Set current picker reference for refreshing
local function set_current_picker(picker)
	current_picker = picker
end

-- Refresh the current picker
local function refresh_picker()
	local jobs_list = Job.build_jobs_list()
	local jobs_formatted = core.format_jobs_list(jobs_list)
	if current_picker then
		current_picker:refresh(
			finders.new_table({
				results = jobs_formatted,
			}),
			{ reset_prompt = false }
		)
	end
end

-- Telescope job previewer implementation
local function telescope_job_previewer(self, entry, jobs_list)
	return core.create_job_previewer(jobs_list, self.state.bufnr)(entry.index)
end

-- Handle direction with telescope-specific selection handling
local function handle_telescope_direction(direction, prompt_bufnr, selection_list, is_launch, opts)
	local selection = state.get_selected_entry()
	actions.close(prompt_bufnr)

	-- Handle run command case (telescope-specific)
	if selection == nil or direction == "run" then
		if direction == "run" then
			direction = "current"
		end
		local current_line = state.get_current_line()
		local fake_selection = { index = 1 }
		local fake_selection_list = {{
			command = current_line,
			options = nil,
			label = "CMD: " .. current_line,
			args = nil
		}}
		core.handle_direction(direction, fake_selection, fake_selection_list, false, opts, refresh_picker, M.name)
		return
	end

	core.handle_direction(direction, selection, selection_list, is_launch, opts, refresh_picker, M.name)
end

-- Create telescope picker with common setup
local function create_telescope_picker(opts, config)
	return pickers.new(opts, config)
end

-- Setup direction mappings for telescope
local function setup_telescope_direction_mappings(map, direction_handler, selection_list, opts)
	local directions = {
		current = mappings.current,
		vertical = mappings.vertical,
		horizontal = mappings.split,
		tab = mappings.tab,
		background_job = mappings.background_job,
		watch_job = mappings.watch_job,
		run = mappings.run,
	}

	for direction, mapping in pairs(directions) do
		local handler = function()
			direction_handler(direction, selection_list, opts)
		end
		map("i", mapping, handler)
		map("n", mapping, handler)
	end
end

-- Tasks picker implementation
function M.tasks(opts)
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

	create_telescope_picker(opts, {
		prompt_title = "Tasks",
		finder = finders.new_table({
			results = tasks_formatted,
		}),
		sorter = sorters.get_generic_fuzzy_sorter(),
		attach_mappings = function(prompt_bufnr, map)
			local direction_handler = function(direction, selection_list, picker_opts)
				handle_telescope_direction(direction, prompt_bufnr, selection_list, false, picker_opts)
			end

			setup_telescope_direction_mappings(map, direction_handler, task_list, opts)
			return true
		end,
	}):find()
end

-- Launches picker implementation
function M.launches(opts)
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

	create_telescope_picker(opts, {
		prompt_title = "Launches",
		finder = finders.new_table({
			results = launch_formatted,
		}),
		sorter = sorters.get_generic_fuzzy_sorter(),
		attach_mappings = function(prompt_bufnr, map)
			local direction_handler = function(direction, selection_list, picker_opts)
				handle_telescope_direction(direction, prompt_bufnr, selection_list, true, picker_opts)
			end

			-- Only allow certain directions for launches
			local directions = {
				current = mappings.current,
				vertical = mappings.vertical,
				horizontal = mappings.split,
				tab = mappings.tab,
			}

			for direction, mapping in pairs(directions) do
				local handler = function()
					direction_handler(direction, launch_list, opts)
				end
				map("i", mapping, handler)
				map("n", mapping, handler)
			end

			return true
		end,
	}):find()
end

-- Inputs picker implementation
function M.inputs(opts)
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

	create_telescope_picker(opts, {
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
	}):find()
end

-- Jobs picker implementation
function M.jobs(opts)
	opts = opts or {}

	local jobs_list = Job.build_jobs_list()
	local jobs_formatted = core.format_jobs_list(jobs_list)

	if vim.tbl_isempty(jobs_formatted) then
		vim.notify("No jobs available", vim.log.levels.INFO)
		return
	end

	local picker = create_telescope_picker(opts, {
		prompt_title = "Jobs",
		finder = finders.new_table({
			results = jobs_formatted,
		}),
		sorter = sorters.get_generic_fuzzy_sorter(),
		previewer = previewers.new_buffer_previewer({
			title = "Jobs",
			define_preview = function(self, entry)
				return telescope_job_previewer(self, entry, jobs_list)
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

				-- Close the picker first
				actions.close(prompt_bufnr)
				Job.fully_clear_job(job)
				M.jobs(opts)
			end

			local toggle_watch_binding = function()
				local selection = state.get_selected_entry()
				local job = jobs_list[selection.index]
				actions.close(prompt_bufnr)
				Job.toggle_watch(job.id)
				M.jobs(opts)
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
				Job.split_to_direction("horizontal")
				Job.open_buffer(job.label)
			end

			map("i", mappings.kill_job, kill_job)
			map("n", mappings.kill_job, kill_job)
			map("i", mappings.current, open_job)
			map("n", mappings.current, open_job)
			map("i", mappings.split, open_horizontal)
			map("n", mappings.split, open_horizontal)
			map("i", mappings.vertical, open_vertical)
			map("n", mappings.vertical, open_vertical)
			map("i", mappings.watch_job, toggle_watch_binding)
			map("n", mappings.watch_job, toggle_watch_binding)

			return true
		end,
	})

	set_current_picker(picker)
	picker:find()
end

-- Command input implementation
function M.command_input(opts)
	return core.create_command_input_handler(mappings, refresh_picker, M.name)(opts)
end

-- Configuration functions
function M.set_mappings(new_mappings)
	for key, value in pairs(new_mappings) do
		mappings[key] = value
	end
end

function M.set_term_opts(new_opts)
	core.term_opts = new_opts
end

function M.get_last()
	return core.last_cmd
end

function M.refresh_picker()
	return refresh_picker()
end

function M.add_watch_autocmd()
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
			callback = function()
				core.restart_watched_jobs(refresh_picker)
			end,
			desc = "Restart watched background tasks on file save",
		})
	end
end

return M