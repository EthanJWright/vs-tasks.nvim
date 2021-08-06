local actions = require('telescope.actions')
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local sorters = require('telescope.sorters')

local Terminal = require('toggleterm.terminal').Terminal
local current_term = nil
local process_cmd = nil
local parent = nil
local Tasks = nil
local Inputs = {}

local function close()
  Terminal:close()
end

local function set_parent()
  parent = vim.api.nvim_get_current_win()
end

local function goto_parent()
  if parent and vim.api.nvim_win_is_valid(parent) then
    vim.api.nvim_set_current_win(parent)
  end
end

local process_command = function(command)
  if process_cmd ~= nil then
    process_cmd(command)
  else
    set_parent()
    if current_term ~= nil then
      current_term:close()
    end
    current_term = Terminal:new({
      cmd = command,
      hidden = true,
      close_on_exit = false,
    })
    current_term:open()
    vim.cmd('stopinsert')
    vim.cmd('normal! G')
    goto_parent()
    vim.cmd('stopinsert')
  end
end

local get_relative_file = function()
  return vim.fn.getcwd() .. vim.fn.bufname()
end

function Split(s, delimiter)
  local result = {};
  for match in (s..delimiter):gmatch("(.-)"..delimiter) do
    table.insert(result, match);
  end
  return result;
end

local get_last_element = function(path)
  local split = Split(path, "/")
  return split[#split]
end

local get_workspacefolder_basename = function()
  return get_last_element(vim.fn.getcwd())
end

local get_file = function()
  return get_last_element(vim.fn.bufname())
end

local predefined = {
  [ "workspaceFolder" ] = vim.fn.cwd,
  [ "workspaceFolderBasename" ] = get_workspacefolder_basename,
  [ "file" ] = get_file,
  [ "fileWorkspaceFolder" ] = nil,
  [ "relativeFile" ] = get_relative_file,
  [ "relativeFileDirname" ] = nil,
  [ "fileBasename" ] = nil,
  [ "fileBasenameNoExtension" ] = nil,
  [ "fileDirname" ] = nil,
  [ "fileExtname" ] = nil,
  [ "cwd" ] = nil,
  [ "lineNumber" ] = nil,
  [ "selectedText" ] = nil,
  [ "execPath" ] = nil,
  [ "defaultBuildTask" ] = nil,
  [ "pathSeparator" ] = nil
}

--- Decodes from JSON.
---
---@param data string Data to decode
---@returns table json_obj Decoded JSON object
local json_decode = function(data)
  local ok, result = pcall(vim.fn.json_decode, vim.fn.readfile(data))
  if ok then
    return result
  else
    return nil, result
  end
end

local function load_input_variable(input)
  local input_val = vim.fn.input(input .. "=", "")
  if input_val == "clear" then
    Inputs[input] = nil
  else
    Inputs[input] = input_val
  end
end

local function get_input_variable(getvar)
  for name, val in pairs(Inputs) do
    if name == getvar then
      return val
    end
  end
end

local function get_predefined_function(getvar)
  for name, func in pairs(predefined) do
    if name == getvar then
      return func
    end
  end
end

--- load settings from JSON file
---@param path string JSON file path
---@return boolean is_error if error then true
local load_setting_json = function(path)
  vim.validate {
    path = { path, 's' },
  }

  if vim.fn.filereadable(path) == 0 then
    print("Invalid file path.")
    return
  end

  local decoded, err = json_decode(path)
  if err ~= nil then
    print(err)
    return
  end
  return decoded
end

local function load_process_command_func(func)
  process_cmd = func
end

local function get_inputs()
  local path = vim.fn.getcwd() .."/.vscode/tasks.json"
  local config = load_setting_json(path)
  local inputs = config["inputs"]
  for _, input_dict in pairs(inputs) do
    if input_dict["default"] ~= "" and Inputs[input_dict["id"]] == nil then
      Inputs[input_dict["id"]] = input_dict["default"]
    end
  end
  return inputs
end

local function get_tasks()
  local path = vim.fn.getcwd() .."/.vscode/tasks.json"
  get_inputs()
  local tasks = load_setting_json(path)
  Tasks = tasks["tasks"]
  return Tasks
end

local function inputs(opts)
  opts = opts or {}

  local input_list = get_inputs()

  if vim.tbl_isempty(input_list) then
    return
  end

  local  inputs_formatted = {}

  for i = 1, #input_list do
    local add_current = ""
    for name, val in pairs(Inputs) do
      if name == input_list[i]["id"] then
        add_current = " [" .. val .. "] "
      end
    end
    local current_task = input_list[i]["id"] .. add_current .. " => " .. input_list[i]["description"]
    table.insert(inputs_formatted, current_task)
  end

  pickers.new(opts, {
    prompt_title = 'Inputs',
    finder    = finders.new_table {
      results = inputs_formatted
    },
    sorter = sorters.get_generic_fuzzy_sorter(),
    attach_mappings = function(prompt_bufnr, map)

      local start_task = function()
        local selection = actions.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)

        local input = input_list[selection.index]["id"]
        load_input_variable(input)
      end


      map('i', '<CR>', start_task)
      map('n', '<CR>', start_task)

      return true
    end
  }):find()
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

local function get_predefined_variables(command)
  local predefined_vars = {}
  local count = 0
  for defined_var, _ in pairs(predefined ) do
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

local extract_variables = function(command)
  local input_vars = get_input_variables(command)
  local predefined_vars = get_predefined_variables(command)
  local missing = {}
  for _, input_var in pairs(input_vars) do
    local found = false
    for name, _ in pairs(Inputs) do
      if name == input_var then
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

local function replace_vars_in_command(command, input_vars, predefined_vars)
  for _, replacing in pairs(input_vars) do
    local replace_pattern = "${input:" .. replacing .. "}"
    command = string.gsub(command, replace_pattern, get_input_variable(replacing))
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

local function tasks(opts)
  opts = opts or {}

  local task_list = get_tasks()

  if vim.tbl_isempty(task_list) then
    return
  end

  local  tasks_formatted = {}

  for i = 1, #task_list do
    local current_task = task_list[i]["label"]
    table.insert(tasks_formatted, current_task)
  end

  pickers.new(opts, {
    prompt_title = 'Tasks',
    finder    = finders.new_table {
      results = tasks_formatted
    },
    sorter = sorters.get_generic_fuzzy_sorter(),
    attach_mappings = function(prompt_bufnr, map)

      local start_task = function()
        local selection = actions.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)

        local command = task_list[selection.index]["command"]
        local input_vars, predefined_vars = extract_variables(command)
        command = replace_vars_in_command(command, input_vars, predefined_vars)
        process_command(command)
      end

      local start_in_vert = function()
        local selection = actions.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)

        local command = task_list[selection.index]["command"]
        local input_vars, predefined_vars = extract_variables(command)
        command = replace_vars_in_command(command, input_vars, predefined_vars)
        vim.cmd('vsplit | terminal ' .. command)
        vim.cmd('stopinsert')
        vim.cmd('normal! G')
      end

      local start_in_split = function()
        local selection = actions.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)

        local command = task_list[selection.index]["command"]
        local input_vars, predefined_vars = extract_variables(command)
        command = replace_vars_in_command(command, input_vars, predefined_vars)
        vim.cmd('split | terminal ' .. command)
        vim.cmd('stopinsert')
        vim.cmd('normal! G')
      end

      map('i', '<CR>', start_task)
      map('n', '<CR>', start_task)
      map('i', '<C-v>', start_in_vert)
      map('n', '<C-v>', start_in_vert)
      map('i', '<C-p>', start_in_split)
      map('n', '<C-p>', start_in_split)
      return true
    end
  }):find()
end




return require('telescope').register_extension {
  exports = {
    load_process_command_func = load_process_command_func,
    tasks = tasks,
    inputs = inputs,
    close = close
  }
}
