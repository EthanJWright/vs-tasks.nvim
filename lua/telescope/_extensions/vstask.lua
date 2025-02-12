local Parse = require("vstask.Parse")
local Telescope = require("vstask.Telescope")

return require("telescope").register_extension({
	exports = {
		tasks = Telescope.Tasks,
		inputs = Telescope.Inputs,
		history = Telescope.History,
		launch = Telescope.Launch,
		jobs = Telescope.Jobs,
		clear_inputs = Parse.Clear_inputs,
		cleanup_completed_jobs = Telescope.cleanup_completed_jobs,
	},
})
