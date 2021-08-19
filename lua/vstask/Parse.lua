local Inputs = {}
local Config = require("vstask.Config")
local Predefined = require('vstask.Predefined')

local function get_inputs()
  local path = vim.fn.getcwd() .."/.vscode/tasks.json"
  local config = Config.load_json(path)
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

local function get_tasks()
  local path = vim.fn.getcwd() .."/.vscode/tasks.json"
  get_inputs()
  local tasks = Config.load_json(path)
  Tasks = tasks["tasks"]
  return Tasks
end

local function get_predefined_function(getvar, predefined)
  for name, func in pairs(predefined) do
    if name == getvar then
      return func
    end
  end
end

local function get_input_variable(getvar, inputs)
  for _, input_dict in pairs(inputs) do
    if input_dict["id"] == getvar then
      return input_dict["value"]
    end
  end
end

local function get_input_variables(command)
  local input_variables = {}
  local count = 0
  for w in string.gmatch(command, "%{input:(%a+)%}") do
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
    Inputs[input]["value"] = input_val
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
  local input_vars, predefined_vars = extract_variables(command, get_inputs())
  for _, replacing in pairs(input_vars) do
    local replace_pattern = "${input:" .. replacing .. "}"
    command = string.gsub(command, replace_pattern, get_input_variable(replacing, get_inputs()))
  end

  for _, replacing in pairs(predefined_vars) do
    local func = get_predefined_function(replacing)
    if func ~= nil then
      local replace_pattern = "${" .. replacing .. "}"
      command = string.gsub(command, replace_pattern, func())
    end
  end
  return command
end

return {
  replace = replace_vars_in_command,
  Inputs = get_inputs,
  Tasks = get_tasks,
  Set = load_input_variable,
}
