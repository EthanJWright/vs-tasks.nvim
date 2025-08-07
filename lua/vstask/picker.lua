local M = {}

-- Picker interface specification
-- Any picker implementation should provide these methods

M.PickerInterface = {
	-- Core picker functions
	tasks = function(opts) end,
	launches = function(opts) end,
	inputs = function(opts) end,
	jobs = function(opts) end,
	command_input = function(opts) end,

	-- Configuration
	set_mappings = function(mappings) end,
	set_term_opts = function(opts) end,

	-- State management
	get_last = function() end,
	refresh_picker = function() end,

	-- Job management (for jobs picker)
	add_watch_autocmd = function() end,
}

-- Current active picker implementation
M.current_picker = nil

-- Set the picker implementation
function M.set_picker(picker_impl)
	-- Validate that the picker implements the interface
	for method_name, _ in pairs(M.PickerInterface) do
		if type(picker_impl[method_name]) ~= "function" then
			error("Picker implementation missing method: " .. method_name)
		end
	end

	M.current_picker = picker_impl
end

-- Proxy methods that delegate to the current picker
function M.tasks(opts)
	if not M.current_picker then
		error("No picker implementation set. Call M.set_picker() first.")
	end
	return M.current_picker.tasks(opts)
end

function M.launches(opts)
	if not M.current_picker then
		error("No picker implementation set. Call M.set_picker() first.")
	end
	return M.current_picker.launches(opts)
end

function M.inputs(opts)
	if not M.current_picker then
		error("No picker implementation set. Call M.set_picker() first.")
	end
	return M.current_picker.inputs(opts)
end

function M.jobs(opts)
	if not M.current_picker then
		error("No picker implementation set. Call M.set_picker() first.")
	end
	return M.current_picker.jobs(opts)
end

function M.command_input(opts)
	if not M.current_picker then
		error("No picker implementation set. Call M.set_picker() first.")
	end
	return M.current_picker.command_input(opts)
end

function M.set_mappings(mappings)
	if not M.current_picker then
		error("No picker implementation set. Call M.set_picker() first.")
	end
	return M.current_picker.set_mappings(mappings)
end

function M.set_term_opts(opts)
	if not M.current_picker then
		error("No picker implementation set. Call M.set_picker() first.")
	end
	return M.current_picker.set_term_opts(opts)
end

function M.get_last()
	if not M.current_picker then
		error("No picker implementation set. Call M.set_picker() first.")
	end
	return M.current_picker.get_last()
end

function M.refresh_picker()
	if M.current_picker and M.current_picker.refresh_picker then
		return M.current_picker.refresh_picker()
	end
end

function M.add_watch_autocmd()
	if M.current_picker and M.current_picker.add_watch_autocmd then
		return M.current_picker.add_watch_autocmd()
	end
end

return M

