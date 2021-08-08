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

local get_relative_file = function()
  return vim.fn.getcwd() .. vim.fn.bufname()
end

local get_file = function()
  return get_last_element(vim.fn.bufname())
end

local get_workspacefolder_basename = function()
  return get_last_element(vim.fn.getcwd())
end

return {
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

