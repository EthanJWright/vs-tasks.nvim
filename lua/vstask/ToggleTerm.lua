local function ToggleTerm_process(command, direction, opts)
  if direction == 'vertical'
  then
    vim.cmd("ToggleTerm size=" .. opts.vertical.size .. " direction=" .. opts.vertical.direction)
  elseif direction == 'horizontal'
  then
    vim.cmd("ToggleTerm size=" .. opts.horizontal.size .. " direction=" .. opts.horizontal.direction)
  elseif direction == 'current'
  then
    vim.cmd("ToggleTerm direction=" .. opts.current.direction)
  elseif direction == 'tab'
  then
    vim.cmd("ToggleTerm direction=" .. opts.tab.direction)
  end
  vim.cmd([[TermExec cmd="]] .. command .. [["]])
end

return { Process = ToggleTerm_process }
