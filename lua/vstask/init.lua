local M = {}

M.Predefined = require("vstask.Predefined")
M.Config = require("vstask.Config")
M.Telescope = require("vstask.Telescope")
M.Parse = require("vstask.Parse")


function M.setup(opts)
  if opts == nil then
    return
  end
  if opts.use_harpoon ~= nil and opts.use_harpoon == true then
    M.Telescope.Set_command_handler(require("vstask.Harpoon").Process)
  elseif opts.terminal ~= nil and opts.terminal == "toggleterm" then
    M.Telescope.Set_command_handler(require("vstask.ToggleTerm").Process)
  end
  if opts.telescope_keys ~= nil then
    M.Telescope.Set_mappings(opts.telescope_keys)
  end
  if opts.term_opts ~= nil then
    M.Telescope.Set_term_opts(opts.term_opts)
  end
  if opts.cache_strategy ~= nil then
    M.Parse.Cache_strategy(opts.cache_strategy)
  end
  if opts.autodetect ~= nil then
    M.Parse.Set_autodetect(opts.autodetect)
  end
  if opts.config_dir ~= nil then
    M.Parse.Set_config_dir(opts.config_dir)
  end
  if opts.cache_json_conf ~= nil then
    M.Parse.Set_cache_json_conf(opts.cache_json_conf)
  end
end

M.get_last = M.Telescope.Get_last

return M
