local M = {}

M.Predefined = require("vslaunch.Predefined")
M.Config = require("vslaunch.Config")
M.Telescope = require("vslaunch.Telescope")
M.Parse = require("vslaunch.Parse")


function M.setup(opts)
  if opts.use_harpoon ~= nil and opts.use_harpoon == true then
    M.Telescope.Set_command_handler(require("vslaunch.Harpoon").Process)
  elseif opts.terminal ~= nil and opts.terminal == "toggleterm" then
    M.Telescope.Set_command_handler(require("vslaunch.ToggleTerm").Process)
  end
  if opts.telescope_keys ~= nil then
    M.Telescope.Set_mappings(opts.telescope_keys)
  end
  if opts.term_opts ~= nil then
    M.Telescope.Set_term_opts(opts.term_opts)
  end
end

return M
