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

local get_relative_file = function()
  return vim.fn.bufname()
end

-- get the path seperator for the current os
local get_path_seperator = function()
  return "/"
end

-- get filename from path string
-- returns the filename from a absolute path
-- @param path character to split on
local get_filename = function(path)
  local sep = get_path_seperator()
  local split = Split(path, sep)
  return split[#split]
end

-- get the current opened file's dirname relative to workspaceFolder
-- @param workspaceFolder the workspace folder
-- @param filePath the file path
-- @return the relative path to the file
-- @return the filename
local get_relative_path = function(workspaceFolder, filePath)
  local filename = get_filename(filePath)
  local relativePath = filePath:gsub(workspaceFolder, "")
  return relativePath, filename
end


-- get the current opened files base name (without extension)
local get_current_file_basename_no_extension = function()
  local sep = get_path_seperator()
  local path = get_relative_file() -- get the path
  local split = Split(path, sep) -- split on /
  local filename = split[#split] -- get the filename
  split = Split(filename, ".") -- split on .
  table.remove(split, #split) -- remove extension
  return table.concat(split, ".") -- join back together
end

-- get the current opened files base name
local get_current_file_basename = function()
  local sep = get_path_seperator()
  local path = get_relative_file() -- get the path
  local split = Split(path, sep) -- split on /
  local filename = split[#split] -- get the filename
  return filename
end

-- get current opened files dirname
local get_current_file_dirname = function()
  local sep = get_path_seperator()
  local path = get_relative_file() -- get the path
  local split = Split(path, sep) -- split on /
  table.remove(split, #split) -- remove filename
  return table.concat(split, sep) -- join back together
end

-- get the current open files extension
local get_current_file_extension = function()
  local sep = get_path_seperator()
  local path = get_relative_file() -- get the path
  local split = Split(path, sep) -- split on /
  local filename = split[#split] -- get the filename
  split = Split(filename, ".") -- split on .
  return split[#split] -- get the extension
end

-- get the current working directory
local get_current_dir = function()
  return vim.fn.fnamemodify(vim.fn.getcwd(), ":h")
end

-- get the current line number
local get_current_line_number = function()
  return vim.fn.line(".")
end

-- get the selected text
local get_selected_text = function()
  return vim.fn.getreg("*")
end

-- get the exec path
local get_exec_path = function()
  return vim.fn.executable()
end



local get_file = function()
  return get_filename(vim.fn.bufname())
end

-- get the file workspace folder
local get_file_workspace_folder = function()
  local sep = get_path_seperator()
  local path = get_relative_file()
  local split = Split(path, sep) -- split on /
  table.remove(split, #split) -- remove filename
  table.remove(split, #split) -- remove filename
  return table.concat(split, sep) -- join back together
end

local get_workspacefolder_basename = function()
  return get_filename(vim.fn.getcwd())
end

local get_relative_file_dirname = function()
  local sep = get_path_seperator()
  local workspaceFolder = get_file_workspace_folder()
  local filePath = get_relative_file()
  local relativePath, filename = get_relative_path(workspaceFolder, filePath)
  local relativeFileDirname = Split(relativePath, filename)[1]
  -- if the last char is / then remove it
  if relativeFileDirname:sub(-1) == sep then
    relativeFileDirname = relativeFileDirname:sub(1, -2)
  end
  return relativeFileDirname
end

return {
  [ "workspaceFolder" ] = vim.fn.getcwd,
  [ "workspaceFolderBasename" ] = get_workspacefolder_basename,
  [ "file" ] = get_file,
  [ "fileWorkspaceFolder" ] = get_file_workspace_folder,
  [ "relativeFile" ] = get_relative_file,
  [ "relativeFileDirname" ] = get_relative_file_dirname,
  [ "fileBasename" ] = get_current_file_basename,
  [ "fileBasenameNoExtension" ] = get_current_file_basename_no_extension,
  [ "fileDirname" ] = get_current_file_dirname,
  [ "fileExtname" ] = get_current_file_extension,
  [ "cwd" ] = get_current_dir,
  [ "lineNumber" ] = get_current_line_number,
  [ "selectedText" ] = get_selected_text,
  [ "execPath" ] = get_exec_path,
  [ "defaultBuildTask" ] = nil,
  [ "pathSeparator" ] = get_path_seperator
}

