local M = {}

M.get_size = function(current, opts)
  if current == 'vertical'
  then
    if opts.vertical ~= nil and opts.vertical.size ~= nil then
      return opts.vertical.size
    end
  elseif current == 'horizontal'
  then
    if opts.horizontal ~= nil and opts.horizontal.size ~= nil then
      return opts.horizontal.size
    end
  end
end

M.get_direction = function (current, opts)
  if current == 'vertical'
  then
    if opts.vertical ~= nil and opts.vertical.direction ~= nil then
      return opts.vertical.direction
    end
  elseif current == 'horizontal'
  then
    if opts.horizontal ~= nil and opts.horizontal.direction ~= nil then
      return opts.horizontal.direction
    end
  elseif current == 'current' then
    if opts.current ~= nil and opts.current.direction ~= nil then
      return opts.current.direction
    end
  elseif current == 'tab' then
    if opts.tab ~= nil and opts.tab.direction ~= nil then
      return opts.tab.direction
    end
  end
  return current
end

return M
