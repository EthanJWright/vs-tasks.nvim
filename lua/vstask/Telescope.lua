local actions = require('telescope.actions')
local state  = require('telescope.actions.state')
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local sorters = require('telescope.sorters')
local Parse = require('vstask.Parse')
local Opts = require('vstask.Opts')
local Command_handler = nil
local Mappings = {
  vertical = '<C-v>',
  split = '<C-p>',
  tab = '<C-t>',
  current = '<CR>'
}

local command_history = {}
local function set_history(label, command, options)
  if not command_history[label] then
    command_history[label] = {
      command = command,
      options = options,
      label = label,
      hits = 1
    }
  else
    command_history[label].hits = command_history[label].hits + 1
  end
  Parse.Used_task(label)
end

local last_cmd = nil
local Term_opts = {}

local function set_term_opts(new_opts)
    Term_opts= new_opts
end

local function get_last()
  return last_cmd
end

local function format_command(pre, options)
  local command = pre
  if nil ~= options then
      local cwd = options["cwd"]
      if nil ~= cwd then
          local cd_command = string.format("cd %s", cwd)
          command = string.format("%s && %s", cd_command, command)
      end
  end
  command = Parse.replace(command)
  return {
    pre = pre,
    command = command,
    options = options
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


local process_command = function(command, direction, opts)
  last_cmd = command
  if Command_handler ~= nil then
    Command_handler(command, direction, opts)
  else
    local opt_direction = Opts.get_direction(direction, opts)
    local size = Opts.get_size(direction, opts)
    local command_map = {
      vertical = { size = 'vertical resize', command = 'vsplit' },
      horizontal = { size = 'resize ', command = 'split' },
      tab = { command = 'tabnew' },
    }

    if command_map[opt_direction] ~= nil then
      vim.cmd(command_map[opt_direction].command)
      if command_map[opt_direction].size ~= nil  and size ~= nil then
        vim.cmd(command_map[opt_direction].size .. size)
      end
    end
    vim.cmd(
      string.format('terminal echo "%s" && %s', command, command)
    )
  end
end

local function set_command_handler(handler)
  Command_handler = handler
end

local function inputs(opts)
  opts = opts or {}

  local input_list = Parse.Inputs()

  if vim.tbl_isempty(input_list) then
    return
  end

  local  inputs_formatted = {}
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

  pickers.new(opts, {
    prompt_title = 'Inputs',
    finder    = finders.new_table {
      results = inputs_formatted
    },
    sorter = sorters.get_generic_fuzzy_sorter(),
    attach_mappings = function(prompt_bufnr, map)

      local start_task = function()
        local selection = state.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)

        local input = selection_list[selection.index]["id"]
        Parse.Set(input)
      end


      map('i', '<CR>', start_task)
      map('n', '<CR>', start_task)

      return true
    end
  }):find()
end

local function start_launch_direction(direction, prompt_bufnr, _, selection_list)
    local selection = state.get_selected_entry(prompt_bufnr)
    actions.close(prompt_bufnr)

    local command = selection_list[selection.index]["program"]
    local options = selection_list[selection.index]["options"]
    local label = selection_list[selection.index]["name"]
    local args = selection_list[selection.index]["args"]
    Parse.Used_launch(label)
    command = Parse.Build_launch(command, args)
    local built = format_command(command, options)
    process_command(built.command, direction, Term_opts)
end

local function start_task_direction(direction, promp_bufnr, _, selection_list)
    local selection = state.get_selected_entry(promp_bufnr)
    actions.close(promp_bufnr)

    local command = selection_list[selection.index]["command"]
    local options = selection_list[selection.index]["options"]
    local label = selection_list[selection.index]["label"]
    local args = selection_list[selection.index]["args"]
    set_history(label, command, options)
    if (args ~= nil) then
        command = Parse.Build_launch(command, args)
    end
    local formatted_command = format_command(command, options)
    process_command(formatted_command.command, direction, Term_opts)
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
  table.sort(sorted_history, function(a, b) return a.hits > b.hits end)

  -- build label table
  local  labels = {}
  for i = 1, #sorted_history do
    local current_task = sorted_history[i]["label"]
    table.insert(labels, current_task)
  end


  pickers.new(opts, {
    prompt_title = 'Task History',
    finder    = finders.new_table {
      results = labels
    },
    sorter = sorters.get_generic_fuzzy_sorter(),
    attach_mappings = function(prompt_bufnr, map)
      local function start_task()
        start_task_direction('current', prompt_bufnr, map, sorted_history)
      end
      local function start_task_vertical()
        start_task_direction('vertical', prompt_bufnr, map, sorted_history)
      end
      local function start_task_split()
        start_task_direction('horizontal', prompt_bufnr, map, sorted_history)
      end
      local function start_task_tab()
        start_task_direction('tab', prompt_bufnr, map, sorted_history)
      end
      map('i', Mappings.current, start_task)
      map('n', Mappings.current, start_task)
      map('i', Mappings.vertical, start_task_vertical)
      map('n', Mappings.vertical, start_task_vertical)
      map('i', Mappings.split, start_task_split)
      map('n', Mappings.split, start_task_split)
      map('i', Mappings.tab, start_task_tab)
      map('n', Mappings.tab, start_task_tab)
      return true
    end
  }):find()
end

local function tasks(opts)
  opts = opts or {}

  local task_list = Parse.Tasks()

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
        start_task_direction('current', prompt_bufnr, map, task_list)
      end

      local start_in_vert = function()
        start_task_direction('vertical', prompt_bufnr, map, task_list)
        vim.cmd('normal! G')
      end

      local start_in_split = function()
        start_task_direction('horizontal', prompt_bufnr, map, task_list)
        vim.cmd('normal! G')
      end

      local start_in_tab = function()
        start_task_direction('tab', prompt_bufnr, map, task_list)
        vim.cmd('normal! G')
      end

      map('i', Mappings.current, start_task)
      map('n', Mappings.current, start_task)
      map('i', Mappings.vertical, start_in_vert)
      map('n', Mappings.vertical, start_in_vert)
      map('i', Mappings.split, start_in_split)
      map('n', Mappings.split, start_in_split)
      map('i', Mappings.tab, start_in_tab)
      map('n', Mappings.tab, start_in_tab)
      return true
    end
  }):find()
end

local function launches(opts)
  opts = opts or {}

  local launch_list = Parse.Launches()

  if vim.tbl_isempty(launch_list) then
    return
  end

  local  launch_formatted = {}

  for i = 1, #launch_list do
    local current_launch = launch_list[i]["name"]
    table.insert(launch_formatted, current_launch)
  end

  pickers.new(opts, {
    prompt_title = 'Launches',
    finder    = finders.new_table {
      results = launch_formatted
    },
    sorter = sorters.get_generic_fuzzy_sorter(),
    attach_mappings = function(prompt_bufnr, map)

      local start_task = function()
        start_launch_direction('current', prompt_bufnr, map, launch_list)
      end

      local start_in_vert = function()
        start_launch_direction('vertical', prompt_bufnr, map, launch_list)
        vim.cmd('normal! G')
      end

      local start_in_split = function()
        start_launch_direction('horizontal', prompt_bufnr, map, launch_list)
        vim.cmd('normal! G')
      end

      local start_in_tab = function()
        start_launch_direction('tab', prompt_bufnr, map, launch_list)
        vim.cmd('normal! G')
      end

      map('i', Mappings.current, start_task)
      map('n', Mappings.current, start_task)
      map('i', Mappings.vertical, start_in_vert)
      map('n', Mappings.vertical, start_in_vert)
      map('i', Mappings.split, start_in_split)
      map('n', Mappings.split, start_in_split)
      map('i', Mappings.tab, start_in_tab)
      map('n', Mappings.tab, start_in_tab)
      return true
    end
  }):find()
end

return {
  Launch = launches,
  Tasks = tasks,
  Inputs = inputs,
  History = history,
  Set_command_handler = set_command_handler,
  Set_mappings = set_mappings,
  Set_term_opts = set_term_opts,
  Get_last = get_last,
}
