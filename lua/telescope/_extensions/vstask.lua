local Telescope = require('vstask.Telescope')

return require('telescope').register_extension {
  exports = {
    tasks = Telescope.Tasks,
    inputs = Telescope.Inputs,
    close = Telescope.Close,
  }
}
