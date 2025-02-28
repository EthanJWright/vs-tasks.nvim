local Parse = require("vstask.Parse")
local Telescope = require("vstask.Telescope")
local Jobs = require("vstask.Job")
local telescope = require("telescope")

local M = telescope.register_extension({
	setup = require("vstask").setup,
	exports = {
		tasks = Telescope.Tasks,
		inputs = Telescope.Inputs,
		history = Telescope.History,
		launch = Telescope.Launch,
		jobs = Telescope.Jobs,
		clear_inputs = Parse.Clear_inputs,
		cleanup_completed_jobs = Jobs.cleanup_completed_jobs,
		command = Telescope.Command,
	},
})

return M
