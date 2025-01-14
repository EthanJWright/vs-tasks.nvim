local Telescope = require("vstask.Telescope")

return require("telescope").register_extension({
	exports = {
		tasks = Telescope.Tasks,
		run = Telescope.Tasks_empty,
		inputs = Telescope.Inputs,
		history = Telescope.History,
		launch = Telescope.Launch,
		close = Telescope.Close,
		jobs = Telescope.Jobs,
		jobhistory = Telescope.JobHistory,
	},
})
