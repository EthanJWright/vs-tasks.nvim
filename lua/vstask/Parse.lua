local Inputs = {}
local Config = require("vstask.Config")
local Predefined = require("vstask.Predefined")

local cache_json_conf = true

local function set_cache_json_conf(value)
	cache_json_conf = value
end

local auto_detect = {
	npm = "on",
}

local function should_handle_pick_string(input_config)
return input_config and input_config.type == "command" and input_config.command == "extension.commandvariable.pickStringRemember"
end


local function handle_pick_string_remember(input, input_config, opts, callback)
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    -- Extract options from args
    local options = input_config.args.options or {}
    local description = input_config.args.description or "Select an option:"

    pickers.new(opts, {
        prompt_title = description,
        finder = finders.new_table {
            results = options,
            entry_maker = function(entry)
                return {
                    value = entry[2],
                    display = entry[1],
                    ordinal = entry[1],
                }
            end,
        },
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, _)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                if selection then
                    if Inputs[input] == nil then
                        Inputs[input] = {}
                    end
                    Inputs[input].value = selection.value
                    Inputs[input].id = input
                    if callback ~= nil then
                      callback()
                    end
                end
            end)
            return true
        end,
    }):find()
end

local config_dir = ".vscode"

local function set_config_dir(dirname)
	if string.match(dirname, [[^[%w-\.]+$]]) ~= nil then
		config_dir = dirname
	end
end

local function set_autodetect(autodetect)
	if autodetect == nil then
		return
	end
	if autodetect.npm == "on" or autodetect.npm == "off" then
		auto_detect.npm = autodetect.npm
	end
end

local MISSING_FILE_MESSAGE = "tasks.json file could not be found."

local CACHE_STRATEGY = nil
local set_cache_strategy = function(strategy)
	CACHE_STRATEGY = strategy
end

local JSON_PARSER = vim.json.decode
--- Set JSON Parser
---@param json_parser function that takes inputstr
local set_json_parser = function(json_parser)
	JSON_PARSER = json_parser
end

local function file_exists(name)
	local f = io.open(name, "r")
	if f ~= nil then
		io.close(f)
		return true
	else
		return false
	end
end

local function setContains(set, key)
	return set[key] ~= nil
end

local function get_inputs()
	if Inputs ~= nil and next(Inputs) ~= nil then
		return Inputs
	end
	local path = vim.fn.getcwd() .. "/" .. config_dir .. "/tasks.json"
	if not file_exists(path) then
		vim.notify(MISSING_FILE_MESSAGE, vim.log.levels.ERROR)
		return {}
	end
	local config = Config.load_json(path, JSON_PARSER)
	if config == nil or config["inputs"] == nil then
		Inputs = {}
		return Inputs
	end

	local inputs = config["inputs"]
	for _, input_dict in pairs(inputs) do
		local input_id = input_dict["id"]
		-- Skip if input already exists
		if Inputs[input_id] ~= nil then
			goto continue
		end

		-- Create new input entry
		Inputs[input_id] = input_dict
		-- Set value to default if provided, otherwise empty string
		Inputs[input_id]["value"] = input_dict["default"] or ""

		::continue::
	end
	return Inputs
end

local task_cache = nil
local launch_cache = nil

local function hit_sorter(a, b)
	return a.hits > b.hits
end

local function time_sorter(a, b)
	return a.timestamp > b.timestamp
end

local function cache_scheme(cache_list, fn)
	local tasks_with_hits = {}
	local other_tasks = {}
	for _, task in pairs(cache_list) do
		if task.hits > 0 then
			table.insert(tasks_with_hits, task)
		else
			table.insert(other_tasks, task)
		end
	end
	-- return tasks in order of most used
	table.sort(tasks_with_hits, fn)
	local formatted = {}
	for _, task in pairs(tasks_with_hits) do
		table.insert(formatted, task.entry)
	end
	for _, task in pairs(other_tasks) do
		table.insert(formatted, task.entry)
	end
	return formatted
end

local function manage_cache(cache_list, scheme)
	if scheme == nil or scheme == "last" then
		return cache_scheme(cache_list, time_sorter)
	end
	if scheme == "most" then
		return cache_scheme(cache_list, hit_sorter)
	end
end

local function create_cache(raw_list, key)
	local new_cache = {}
	for _, entry in pairs(raw_list) do
		local cache_key = entry[key]
		if cache_key then
			new_cache[cache_key] = { entry = entry, hits = 0, timestamp = os.time() }
		end
	end
	return new_cache
end

local function update_cache(cache, key)
	if cache == nil then
		return
	end
	if cache[key] == nil then
		return
	end
	if cache[key] ~= nil then
		cache[key].hits = cache[key].hits + 1
		cache[key].timestamp = os.time()
	end
end

local function auto_detect_npm()
	if auto_detect.npm == "off" then
		return {}
	end
	local cwd = vim.fn.getcwd()
	local packagejson = cwd .. "/package.json"
	local script_tasks = {}

	if not file_exists(packagejson) then
		return script_tasks
	end

	local config = Config.load_json(packagejson, JSON_PARSER)
	if config == nil then
		return script_tasks
	end
	if setContains(config, "scripts") then
		local scripts = config["scripts"]
		for key in pairs(scripts) do
			local label = "npm: " .. key
			table.insert(script_tasks, { label = label, type = "npm", command = "npm run " .. key })
		end
	end
	return script_tasks
end

local function tasks_file_exists()
	local cwd = vim.fn.getcwd()
	local path = cwd .. "/" .. config_dir .. "/tasks.json"
	return file_exists(path)
end

local function notify_missing_task_file()
	vim.notify(MISSING_FILE_MESSAGE, vim.log.levels.ERROR)
end

local function get_tasks()
	if task_cache ~= nil and cache_json_conf then
		return manage_cache(task_cache, CACHE_STRATEGY)
	end

	local cwd = vim.fn.getcwd()
	local path = cwd .. "/" .. config_dir .. "/tasks.json"

	local task_list = {}

	get_inputs()

	-- add vscode/tasks.json
	if tasks_file_exists() == true then
		local tasks = Config.load_json(path, JSON_PARSER)
		if tasks == nil then
			goto continue
		end

		for _, task in pairs(tasks["tasks"]) do
			table.insert(task_list, task)
		end
		::continue::
	end

	-- add script_tasks to Tasks
	local script_tasks = auto_detect_npm()
	for _, task in pairs(script_tasks) do
		table.insert(task_list, task)
	end
	-- add each task to cached while initializing 'hits' as 0
	task_cache = create_cache(task_list, "label")

	if task_list == nil or #task_list == 0 then
		notify_missing_task_file()
	end

	return task_list
end

local function used_task(label)
	update_cache(task_cache, label)
end

local function used_launch(name)
	update_cache(launch_cache, name)
end

local function get_predefined_function(getvar, predefined)
	for name, func in pairs(predefined) do
		if name == getvar then
			return func
		end
	end
	return nil
end

local function get_input_variable(getvar, inputs)
	for _, input_dict in pairs(inputs) do
		if input_dict["id"] == getvar then
			return input_dict["value"]
		else
			print("no match for: " .. input_dict["value"])
		end
	end
end

local function get_input_variables(command)
	local input_variables = {}
	local count = 0
	for w in string.gmatch(command, "${input:([^}]*)}") do
		table.insert(input_variables, w)
		count = count + 1
	end
	return input_variables, count
end

local function handle_standard_input(input, callback)
    -- Handle regular input types
    local input_val = vim.fn.input(input .. "=", "")
    if input_val == "clear" then
        Inputs[input]["value"] = nil
    else
        if Inputs[input] == nil then
            Inputs[input] = { "value", nil }
        end
        Inputs[input]["value"] = input_val
        Inputs[input]["id"] = input
        if callback ~= nil then
          callback()
        end
    end
end

local get_input_config = function(input)
    local input_config = nil
    for _, cfg in pairs(Inputs) do
        if cfg.id == input then
            input_config = cfg
            break
        end
    end
  return input_config
end


local function load_input_variable(input, opts)
  local input_config = get_input_config(input)

  if should_handle_pick_string(input_config) then
      handle_pick_string_remember(input, input_config, opts)
      return
  end

  handle_standard_input(input)
end

local function get_predefined_variables(command)
	local predefined_vars = {}
	local count = 0
	for defined_var, _ in pairs(Predefined) do
		local match_pattern = "${" .. defined_var .. "}"
		for w in string.gmatch(command, match_pattern) do
			if w ~= nil then
				for word in string.gmatch(command, "%{(%a+)}") do
					table.insert(predefined_vars, word)
					count = count + 1
				end
			end
		end
	end
	return predefined_vars, count
end

local find_missing_inputs = function(inputs, input_vars)
	local missing = {}
	for _, input_var in pairs(input_vars) do
		local found = false
		for _, stored_inputs in pairs(inputs) do
			if stored_inputs["id"] == input_var and stored_inputs["value"] ~= "" then
				found = true
			end
		end
		if not found then
			table.insert(missing, input_var)
		end
	end
  return missing
end

local function replace_input_vars(input_vars, inputs, command)
	for _, replacing in pairs(input_vars) do
		local replace_pattern = "${input:" .. replacing .. "}"
		local replace = get_input_variable(replacing, inputs)
		command = string.gsub(command, replace_pattern, replace)
	end
  return command
end

local function replace_predefined_vars(predefined_vars, command)
  for _, replacing in pairs(predefined_vars) do
    local func = get_predefined_function(replacing, Predefined)
    if func ~= nil then
      local replace_pattern = "${" .. replacing .. "}"
      command = string.gsub(command, replace_pattern, func())
    end
  end
  return command
end

local function command_replacements(input_vars, inputs, predefined_vars, command)
  command = replace_input_vars(input_vars, inputs, command)
  command = replace_predefined_vars(predefined_vars, command)
  return command
end

local get_inputs_and_run = function(input_vars, inputs, predefined_vars, missing, raw_command, callback, opts)
  local missing_length = #missing
  for index, input in pairs(missing) do
    local input_config = get_input_config(input)
    local run_callback = function()
      if missing_length == index then
        local command = command_replacements(input_vars, inputs, predefined_vars, raw_command)
        vim.notify("Running: " .. command, vim.log.levels.INFO)
        callback(command)
      end
    end
    if should_handle_pick_string(input_config) then
        handle_pick_string_remember(input, input_config, opts, run_callback)
        return
    end
    handle_standard_input(input, run_callback)
  end
end

local get_missing_inputs_from_user = function(missing)
  for _, input in pairs(missing) do
    load_input_variable(input)
  end
end

local get_existing_variables = function(command)
	local input_vars = get_input_variables(command)
	local predefined_vars = get_predefined_variables(command)
  return input_vars, predefined_vars
end

local extract_variables = function(command, inputs)
  local input_vars, predefined_vars = get_existing_variables(command)
  local missing = find_missing_inputs(inputs, input_vars)
  -- this gets user input
	return input_vars, predefined_vars, missing
end



local function replace_vars_in_command(command)
	local inputs = get_inputs()
	local input_vars, predefined_vars, missing = extract_variables(command, inputs)
  get_missing_inputs_from_user(missing)
  command = command_replacements(input_vars, inputs, predefined_vars, command)
	return command
end

local function build_launch(program, args)
	local command = program
	for _, arg in pairs(args) do
		command = command .. " " .. arg
	end
	return command
end

local function get_launches()
	if launch_cache ~= nil then
		return manage_cache(launch_cache, CACHE_STRATEGY)
	end
	local path = vim.fn.getcwd() .. "/" .. config_dir .. "/launch.json"
	if not file_exists(path) then
		vim.notify(MISSING_FILE_MESSAGE,  vim.log.levels.ERROR)
		return {}
	end
	get_inputs()
	local configurations = Config.load_json(path, JSON_PARSER)

  if configurations ~= nil then
    Launches = configurations["configurations"]
  end
	launch_cache = create_cache(Launches, "name")
	return Launches
end

-- Function to replace variables and execute callback
local function replace_and_run(command, callback)
  local inputs = get_inputs()
	local input_vars, predefined_vars, missing = extract_variables(command, inputs)
  get_inputs_and_run(input_vars, inputs, predefined_vars, missing, command, callback)
	return command
end

return {
	replace = replace_vars_in_command,
	replace_and_run = replace_and_run,
	Inputs = get_inputs,
	Tasks = get_tasks,
	Launches = get_launches,
	Set = load_input_variable,
	Used_task = used_task,
	Used_launch = used_launch,
	Build_launch = build_launch,
	Cache_strategy = set_cache_strategy,
	Set_autodetect = set_autodetect,
	Set_cache_json_conf = set_cache_json_conf,
	Set_config_dir = set_config_dir,
	Set_json_parser = set_json_parser,
}
