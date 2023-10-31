---@alias openmode
---|>"r"   # Read mode.
---| "w"   # Write mode.
---| "a"   # Append mode.
---| "r+"  # Update mode, all previous data is preserved.
---| "w+"  # Update mode, all previous data is erased.
---| "a+"  # Append update mode, previous data is preserved, writing is only allowed at the end of file.
---| "rb"  # Read mode. (in binary mode.)
---| "wb"  # Write mode. (in binary mode.)
---| "ab"  # Append mode. (in binary mode.)
---| "r+b" # Update mode, all previous data is preserved. (in binary mode.)
---| "w+b" # Update mode, all previous data is erased. (in binary mode.)
---| "a+b" # Append update mode, previous data is preserved, writing is only allowed at the end of file. (in binary mode.)

--- read a file on disk
---@param filePath string
---@param mode? openmode
---@return file*?
---@return string? errmsg
local readfile = function(filePath, mode)
  mode = vim.F.if_nil(mode, "r")
  local file = io.open(filePath, "r")
  if file then
    local data = file:read "*a"
    file.close()
    return data
  end
end

--- Decodes from JSON.
---
---@param filepath string File on disk to decode
---@param parser function Parser to use
---@returns table json_obj Decoded JSON object
local json_decode = function(filepath, parser)
  local Parser = parser or vim.json.decode
  local inputstr = readfile(filepath)
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
---@return boolean? is_error if error then true
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
