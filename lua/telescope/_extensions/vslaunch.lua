local Telescope = require('vslaunch.Telescope')

return require('telescope').register_extension {
  exports = {
    launches = Telescope.Launches,
    inputs = Telescope.Inputs,
    close = Telescope.Close
  }
}
