--- @since 25.5.31

local function run_root_command(command)
	local handle = io.popen(command)
	local result = handle:read("*a")
	local status_table = { handle:close() }
	local status_code = status_table[3]

	if status_code == 0 then
		return result:gsub("[\n\r]", "") .. "/"
	end
	return nil
end

local function get_repo_root()
	return run_root_command("git rev-parse --show-toplevel 2>/dev/null")
end

return {
	entry = function()
		local destination = get_repo_root()
		ya.dbg(destination)
		if destination then
			local target = Url(destination)
			ya.emit("cd", { target })
		else
			ya.notify({
				title = "Could not change directory!",
				content = "You are not in a git repository.",
				timeout = 3,
				level = "error",
			})
		end
	end,
}
