--- Decodes from JSON.
---
---@param data string Data to decode
---@param parser function Parser to use
---@returns table json_obj Decoded JSON object
local json_decode = function(data, parser)
  local Parser = parser or vim.fn.json_decode
  local lines = vim.fn.readfile(data)
  local inputstr = table.concat(lines, '\n')
  local ok, result = pcall(Parser, inputstr)
  if ok then
    return result
  else
    return nil, result
  end
end

--- load settings from JSON file
---@param path string JSON file path
---@param parser function the parser to use
---@return boolean is_error if error then true
local load_setting_json = function(path, parser)
  vim.validate {
    path = { path, 's' },
  }

  if vim.fn.filereadable(path) == 0 then
    print("Invalid file path.")
    return
  end

  local decoded, err = json_decode(path, parser)
  if err ~= nil then
    print(err)
    return
  end
  return decoded
end

return {
  load_json = load_setting_json
}
