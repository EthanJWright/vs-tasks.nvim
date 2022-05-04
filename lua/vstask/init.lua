local M = {}

M.Predefined = require("vstask.Predefined")
M.Config = require("vstask.Config")
M.Telescope = require("vstask.Telescope")
M.Parse = require("vstask.Parse")


function M.setup(opts)
  if opts.use_harpoon ~= nil and opts.use_harpoon == true then
    M.Telescope.Set_command_handler(require("vstask.Harpoon").Process)
  end
  if opts.telescope_keys ~= nil then
    M.Telescope.Set_mappings(opts.telescope_keys)
  end
end

return M
