local Parse = require("vstask.Parse")
local Job = require("vstask.Job")
local core = require("vstask.picker_core")

local M = {}

-- Picker identification
M.name = "snacks.nvim"

-- Snacks-specific state
local mappings = vim.tbl_deep_extend("force", {}, core.default_mappings)

-- Refresh function placeholder (jobs picker specific)
local function refresh_picker()
	-- Snacks doesn't have a built-in refresh mechanism like Telescope
	-- We would need to reopen the picker, which is handled case by case
end

-- Helper function to handle direction-based task execution
local function handle_snacks_direction(direction, item, selection_list, is_launch, opts)
	local selection = { index = item.idx }
	core.handle_direction(direction, selection, selection_list, is_launch, opts, refresh_picker, M.name)
end

-- Helper function to create snacks actions and key bindings
local function create_snacks_config(selection_list, is_launch, opts)
	-- Actions with descriptive names (not key strings)
	local actions = {
		confirm = function(picker, item)
			picker:close()
			handle_snacks_direction("current", item, selection_list, is_launch, opts)
		end,
		vertical = function(picker, item)
			picker:close()
			handle_snacks_direction("vertical", item, selection_list, is_launch, opts)
		end,
		split = function(picker, item)
			picker:close()
			handle_snacks_direction("horizontal", item, selection_list, is_launch, opts)
		end,
		tab = function(picker, item)
			picker:close()
			handle_snacks_direction("tab", item, selection_list, is_launch, opts)
		end,
		background_job = function(picker, item)
			picker:close()
			handle_snacks_direction("background_job", item, selection_list, is_launch, opts)
		end,
		watch_job = function(picker, item)
			picker:close()
			handle_snacks_direction("watch_job", item, selection_list, is_launch, opts)
		end,
		run = function(picker, item)
			picker:close()
			handle_snacks_direction("run", item, selection_list, is_launch, opts)
		end,
	}
	
	-- Key mappings to action names
	local win_config = {
		input = {
			keys = {
				[mappings.vertical] = { "vertical", mode = { "n", "i" } },
				[mappings.split] = { "split", mode = { "n", "i" } },
				[mappings.tab] = { "tab", mode = { "n", "i" } },
				[mappings.background_job] = { "background_job", mode = { "n", "i" } },
				[mappings.watch_job] = { "watch_job", mode = { "n", "i" } },
				[mappings.run] = { "run", mode = { "n", "i" } },
			}
		}
	}
	
	
	return actions, win_config
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

	-- Convert tasks to snacks picker items
	local items = {}
	for i, task in ipairs(task_list) do
		table.insert(items, {
			idx = i,
			text = task.label,
			name = task.label,
			command = task.command,
			description = task.description or "",
			preview = {
				text = "Command: " .. (task.command or "") .. "\n" ..
					   "Description: " .. (task.description or "") .. "\n" ..
					   "Type: " .. (task.type or "shell") .. "\n" ..
					   "Group: " .. (task.group and task.group.kind or "default")
			}
		})
	end

	local actions, win_config = create_snacks_config(task_list, false, opts)
	
	return require("snacks").picker.pick({
		source = "vstask_tasks",
		title = "Tasks",
		items = items,
		format = function(item)
			local ret = {}
			ret[#ret + 1] = { item.name, "SnacksPickerLabel" }
			if item.description and item.description ~= "" then
				ret[#ret + 1] = { "  ", virtual = true }
				ret[#ret + 1] = { item.description, "SnacksPickerComment" }
			end
			return ret
		end,
		preview = "preview",
		actions = actions,
		confirm = actions.confirm,
		win = win_config,
	})
end

-- Launches picker implementation
function M.launches(opts)
	opts = opts or {}

	local launch_list = Parse.Launches()

	if vim.tbl_isempty(launch_list) then
		return
	end

	-- Convert launches to snacks picker items
	local items = {}
	for i, launch in ipairs(launch_list) do
		table.insert(items, {
			idx = i,
			text = launch.name,
			name = launch.name,
			program = launch.program,
			description = launch.type or "",
			preview = {
				text = "Program: " .. (launch.program or "") .. "\n" ..
					   "Type: " .. (launch.type or "") .. "\n" ..
					   "Request: " .. (launch.request or "") .. "\n" ..
					   "Args: " .. (launch.args and table.concat(launch.args, " ") or "")
			}
		})
	end

	-- Only allow certain directions for launches (no background/watch jobs)
	local launch_actions = {
		["<CR>"] = function(picker, item)
			picker:close()
			handle_snacks_direction("current", item, launch_list, true, opts)
		end,
		[mappings.vertical] = function(picker, item)
			picker:close()
			handle_snacks_direction("vertical", item, launch_list, true, opts)
		end,
		[mappings.split] = function(picker, item)
			picker:close()
			handle_snacks_direction("horizontal", item, launch_list, true, opts)
		end,
		[mappings.tab] = function(picker, item)
			picker:close()
			handle_snacks_direction("tab", item, launch_list, true, opts)
		end,
	}

	return require("snacks").picker.pick({
		source = "vstask_launches",
		title = "Launches",
		items = items,
		format = function(item)
			local ret = {}
			ret[#ret + 1] = { item.name, "SnacksPickerLabel" }
			if item.description and item.description ~= "" then
				ret[#ret + 1] = { "  ", virtual = true }
				ret[#ret + 1] = { item.description, "SnacksPickerComment" }
			end
			return ret
		end,
		preview = "preview",
		actions = launch_actions,
		confirm = function(picker, item)
			picker:close()
			handle_snacks_direction("current", item, launch_list, true, opts)
		end,
	})
end

-- Inputs picker implementation
function M.inputs(opts)
	opts = opts or {}

	local input_list = Parse.Inputs()

	if input_list == nil or vim.tbl_isempty(input_list) then
		return
	end

	-- Convert inputs to snacks picker items
	local items = {}
	local selection_list = {}

	for i, input_dict in pairs(input_list) do
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

		local display_text = input_dict["id"] .. add_current .. " => " .. description

		table.insert(items, {
			idx = i,
			text = display_text,
			id = input_dict["id"],
			value = input_dict["value"] or "",
			description = description,
			preview = {
				text = "ID: " .. input_dict["id"] .. "\n" ..
					   "Current Value: " .. (input_dict["value"] or "(empty)") .. "\n" ..
					   "Description: " .. description
			}
		})
		table.insert(selection_list, input_dict)
	end

	return require("snacks").picker.pick({
		source = "vstask_inputs",
		title = "Inputs",
		items = items,
		format = "text",
		preview = "preview",
		confirm = function(picker, item)
			picker:close()
			local input = selection_list[item.idx]["id"]
			Parse.Set(input, opts)
		end,
	})
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

	-- Convert jobs to snacks picker items
	local items = {}
	for i, job_info in ipairs(jobs_list) do
		local is_running = not job_info.completed and vim.fn.jobwait({ job_info.id }, 0)[1] == -1
		local formatted_text = core.format_job_entry(job_info, is_running)
		
		-- Create preview content
		local output = ""
		if Job.is_job_running(job_info.id) then
			local buffer_content = Job.get_buffer_content(job_info.id)
			output = table.concat(buffer_content or {}, "\n")
		else
			local background_job = Job.get_background_job(job_info.id)
			local job_output = background_job.output or {}
			if type(job_output) == "string" then
				job_output = vim.split(job_output, "\n")
			end
			output = table.concat(job_output, "\n")
		end

		table.insert(items, {
			idx = i,
			text = formatted_text,
			job_id = job_info.id,
			label = job_info.label,
			is_running = is_running,
			preview = {
				text = "Job: " .. job_info.label .. "\n" ..
					   "Status: " .. (is_running and "Running" or "Completed") .. "\n" ..
					   "Command: " .. (job_info.command or "") .. "\n\n" ..
					   "Output:\n" .. output
			}
		})
	end

	-- Create job-specific actions and key bindings
	local job_actions = {
		-- Open job buffer
		confirm = function(picker, item)
			picker:close()
			local job = jobs_list[item.idx]
			Job.job_selected(job.id)
			Job.open_buffer(job.label)
		end,
		-- Kill job
		kill_job = function(picker, item)
			local job = jobs_list[item.idx]
			if not job or not job.id then
				return
			end
			
			local background_job = Job.get_background_job(job.id)
			picker:close()
			Job.fully_clear_job(background_job)
			-- Reopen jobs picker
			M.jobs(opts)
		end,
		-- Toggle watch
		toggle_watch = function(picker, item)
			local job = jobs_list[item.idx]
			picker:close()
			Job.toggle_watch(job.id)
			-- Reopen jobs picker
			M.jobs(opts)
		end,
		-- Open vertical
		open_vertical = function(picker, item)
			picker:close()
			local job = jobs_list[item.idx]
			Job.job_selected(job.id)
			Job.split_to_direction("vertical")
			Job.open_buffer(job.label)
		end,
		-- Open horizontal
		open_horizontal = function(picker, item)
			picker:close()
			local job = jobs_list[item.idx]
			Job.job_selected(job.id)
			Job.split_to_direction("horizontal")
			Job.open_buffer(job.label)
		end,
	}

	-- Key mappings for jobs
	local job_win_config = {
		input = {
			keys = {
				[mappings.vertical] = { "open_vertical", mode = { "n", "i" } },
				[mappings.split] = { "open_horizontal", mode = { "n", "i" } },
				[mappings.kill_job] = { "kill_job", mode = { "n", "i" } },
				[mappings.watch_job] = { "toggle_watch", mode = { "n", "i" } },
			}
		}
	}


	return require("snacks").picker.pick({
		source = "vstask_jobs",
		title = "Jobs",
		items = items,
		format = "text",
		preview = "preview",
		actions = job_actions,
		confirm = job_actions.confirm,
		win = job_win_config,
	})
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