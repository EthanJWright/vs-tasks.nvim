-- Legacy compatibility layer for Telescope.lua
-- This maintains the original API while delegating to the new picker system

local picker = require("vstask.picker")

-- Ensure we're using the Telescope implementation
local telescope_picker = require("vstask.pickers.telescope")
picker.set_picker(telescope_picker)

-- Make the Add_watch_autocmd function globally available (legacy compatibility)
_G.Add_watch_autocmd = telescope_picker.add_watch_autocmd

-- Expose the same API as before
return {
	Launch = picker.launches,
	Tasks = picker.tasks,
	Inputs = picker.inputs,
	Jobs = picker.jobs,
	Set_mappings = picker.set_mappings,
	Set_term_opts = picker.set_term_opts,
	Get_last = picker.get_last,
	Command = picker.command_input,
}

