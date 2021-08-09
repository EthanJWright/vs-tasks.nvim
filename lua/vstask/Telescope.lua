local actions = require('telescope.actions')
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local sorters = require('telescope.sorters')

local Parse = require('vstask.Parse')
local parent = nil
local process_cmd = nil

local Terminal = require('toggleterm.terminal').Terminal
local current_term = nil

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
        local selection = actions.get_selected_entry(prompt_bufnr)
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
        local selection = actions.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)

        local command = task_list[selection.index]["command"]
        command = Parse.replace(command)
        process_command(command)
      end

      local start_in_vert = function()
        local selection = actions.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)

        local command = task_list[selection.index]["command"]
        command = Parse.replace(command)
        vim.cmd('vsplit | terminal ' .. command)
        vim.cmd('stopinsert')
        vim.cmd('normal! G')
      end

      local start_in_split = function()
        local selection = actions.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)

        local command = task_list[selection.index]["command"]
        command = Parse.replace(command)
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

return {
  Tasks = tasks,
  Inputs = inputs,
  Close = close
}
