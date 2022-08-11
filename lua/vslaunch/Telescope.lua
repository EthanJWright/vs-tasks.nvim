local actions = require('telescope.actions')
local state  = require('telescope.actions.state')
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local sorters = require('telescope.sorters')
local Parse = require('vslaunch.Parse')
local Opts = require('vslaunch.Opts')
local Command_handler = nil
local Mappings = {
  vertical = '<C-v>',
  split = '<C-p>',
  tab = '<C-t>',
  current = '<CR>'
}

local Term_opts = {}

local function set_term_opts(new_opts)
    Term_opts= new_opts
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

    vim.cmd('terminal ' .. command)
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

      local start_launch = function()
        local selection = state.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)

        local command = launch_list[selection.index]["program"]
        print("PrograM ", command)

        local cwd = launch_list[selection.index]["cwd"]
        if nil ~= cwd then
            local cd_command = string.format("cd %s", cwd)
            command = string.format("%s && %s && cd -", cd_command, command)
        end

        local args = launch_list[selection.index]["args"]
        if nil ~= args then
            for _, arg in ipairs(args) do
                command = string.format("%s %s", command, arg)
            end
        end

        command = Parse.replace(command)
        process_command(command, 'current', Term_opts)
      end

      local start_in_vert = function()
        local selection = state.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)
        local command = launch_list[selection.index]["command"]
        command = Parse.replace(command)
        process_command(command, 'vertical', Term_opts)
        vim.cmd('normal! G')
      end

      local start_in_split = function()
        local selection = state.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)

        local command = launch_list[selection.index]["command"]
        command = Parse.replace(command)
        process_command(command, 'horizontal', Term_opts)
        vim.cmd('normal! G')
      end

      local start_in_tab = function()
        local selection = state.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)

        local command = launch_list[selection.index]["command"]
        command = Parse.replace(command)
        process_command(command, 'tab', Term_opts)
        vim.cmd('normal! G')
      end

      map('i', Mappings.current, start_launch)
      map('n', Mappings.current, start_launch)
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
  Launches = launches,
  Inputs = inputs,
  Set_command_handler = set_command_handler,
  Set_mappings = set_mappings,
  Set_term_opts = set_term_opts
}
