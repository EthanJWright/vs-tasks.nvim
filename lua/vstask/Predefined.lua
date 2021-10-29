-- split a string into a table
-- @param s string to split
-- @param delimiter substring to split on
function Split(s, delimiter)
  local result = {};
  for match in (s..delimiter):gmatch("(.-)"..delimiter) do
    table.insert(result, match);
  end
  return result;
end

-- get filename from path string
-- returns the filename from a absolute path
-- @param path character to split on
local get_filename = function(path)
  local split = Split(path, "/")
  return split[#split]
end

local get_relative_file_dirname = function()
  local path = vim.fn.expand("%:p:h") -- get the path
  local split = Split(path, "/") -- split on /
  table.remove(split, #split) -- remove filename
  return table.concat(split, "/") -- join back together
end

local get_relative_file = function()
  return vim.fn.bufname()
end

local get_file = function()
  return get_filename(vim.fn.bufname())
end

local get_workspacefolder_basename = function()
  return get_filename(vim.fn.getcwd())
end

return {
  [ "workspaceFolder" ] = vim.fn.cwd,
  [ "workspaceFolderBasename" ] = get_workspacefolder_basename,
  [ "file" ] = get_file,
  [ "fileWorkspaceFolder" ] = nil,
  [ "relativeFile" ] = get_relative_file,
  [ "relativeFileDirname" ] = get_relative_file_dirname,
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

