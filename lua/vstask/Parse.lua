local Inputs = {}
local Config = require("vstask.Config")
local Predefined = require('vstask.Predefined')

local cache_json_conf = true

local function set_cache_json_conf(value)
  cache_json_conf = value
end

local auto_detect = {
  npm = "on"
}

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
  if Inputs ~= nil then
    return Inputs
  end
  local path = vim.fn.getcwd() .. "/" .. config_dir .. "/tasks.json"
  if not file_exists(path) then
    vim.notify(MISSING_FILE_MESSAGE, "error")
    return {}
  end
  local config = Config.load_json(path)
  if (not setContains(config, "inputs")) then
    Inputs = {}
    return Inputs
  end

  local inputs = config["inputs"]
  for _, input_dict in pairs(inputs) do
    if Inputs[input_dict["id"]] == nil then
      Inputs[input_dict["id"]] = input_dict
      if Inputs[input_dict["id"]] == nil or Inputs[input_dict["id"]]["value"] == nil then
        Inputs[input_dict["id"]]["value"] = input_dict["default"]
      end
    end
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
    if (task.hits > 0) then
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
  if (scheme == nil or scheme == "last") then
    return cache_scheme(cache_list, time_sorter)
  end
  if (scheme == "most") then
    return cache_scheme(cache_list, hit_sorter)
  end
end

local function create_cache(raw_list, key)
  local new_cache = {}
  for _, entry in pairs(raw_list) do
    local cache_key = entry[key]
    new_cache[cache_key] = {entry = entry, hits = 0, timestamp = os.time()}
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
  if (cache[key] ~= nil) then
    cache[key].hits = cache[key].hits + 1
    cache[key].timestamp = os.time()
  end
end

local function auto_detect_npm()
  if auto_detect.npm == "off" then
    return {}
  end
  local cwd = vim.fn.getcwd()
  local packagejson = cwd .."/package.json"
  local script_tasks = {}

  if not file_exists(packagejson) then
    return script_tasks
  end

  local config = Config.load_json(packagejson)
  if (setContains(config, "scripts")) then
    local scripts = config["scripts"]
    for key in pairs(scripts) do
      local label = "npm: " .. key
      table.insert(script_tasks, {label = label, type = "npm", command = 'npm run ' .. key})
    end
  end
  return script_tasks
end

local function get_tasks()
  if task_cache ~= nil and cache_json_conf then
    return manage_cache(task_cache, CACHE_STRATEGY)
  end

  local cwd = vim.fn.getcwd()
  local path = cwd .. "/" .. config_dir .. "/tasks.json"
  if not file_exists(path) then
    vim.notify(MISSING_FILE_MESSAGE, "error")
    return {}
  end


  get_inputs()
  local tasks = Config.load_json(path)
  local task_list = tasks["tasks"]
  -- add script_tasks to Tasks
  local script_tasks = auto_detect_npm()
  for _, task in pairs(script_tasks) do
    table.insert(task_list, task)
  end
  -- add each task to cached while initializing 'hits' as 0
  task_cache = create_cache(task_list, "label")
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
      print("no match for: ".. input_dict["value"])
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

local function load_input_variable(input)
  local input_val = vim.fn.input(input .. "=", "")
  if input_val == "clear" then
    Inputs[input]["value"] = nil
  else
    if Inputs[input] == nil then
      Inputs[input] = { "value", nil }
    end
    Inputs[input]["value"] = input_val
    Inputs[input]["id"] = input
  end
end

local function get_predefined_variables(command)
  local predefined_vars = {}
  local count = 0
  for defined_var, _ in pairs(Predefined ) do
    local match_pattern = "${" .. defined_var .. "}"
    for w in string.gmatch(command,  match_pattern) do
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

local extract_variables = function(command, inputs)
  local input_vars = get_input_variables(command)
  local predefined_vars = get_predefined_variables(command)
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
  for _, input in pairs(missing) do
    load_input_variable(input)
  end
  return input_vars, predefined_vars
end

local function replace_vars_in_command(command)
  local inputs = get_inputs()
  local input_vars, predefined_vars = extract_variables(command, inputs)
  for _, replacing in pairs(input_vars) do
    local replace_pattern = "${input:" .. replacing .. "}"
    local replace = get_input_variable(replacing, inputs)
    command = string.gsub(command, replace_pattern, replace)
  end

  for _, replacing in pairs(predefined_vars) do
    local func = get_predefined_function(replacing, Predefined)
    if func ~= nil then
      local replace_pattern = "${" .. replacing .. "}"
      command = string.gsub(command, replace_pattern, func())
    end
  end
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
    vim.notify(MISSING_FILE_MESSAGE, "error")
    return {}
  end
  get_inputs()
  local configurations = Config.load_json(path)
  Launches = configurations["configurations"]
  launch_cache = create_cache(Launches, "name")
  return Launches
end

return {
  replace = replace_vars_in_command,
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
  Set_config_dir = set_config_dir
}
