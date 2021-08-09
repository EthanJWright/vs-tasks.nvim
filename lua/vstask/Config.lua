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

return {
  load_json = load_setting_json
}
