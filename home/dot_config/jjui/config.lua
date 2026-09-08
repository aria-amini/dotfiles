local WORKSPACE_LIST_TEMPLATE = [[self.name() ++ "\t" ++ self.root() ++ "\n"]]

local function current_workspace_root()
	local out = jj("root")
	if not out then
		return nil
	end
	return (out:gsub("%s+$", ""))
end

local function list_workspaces()
	local out, err = jj("workspace", "list", "-T", WORKSPACE_LIST_TEMPLATE)
	if not out then
		return nil, err
	end
	local workspaces = {}
	for line in out:gmatch("[^\n]+") do
		local name, root = line:match("^(.-)\t(.+)$")
		if name and root then
			table.insert(workspaces, { name = name, root = root })
		end
	end
	return workspaces
end

local function find_workspace(workspaces, root, name)
	for _, ws in ipairs(workspaces) do
		if ws.root == root then
			return ws
		end
	end
	for _, ws in ipairs(workspaces) do
		if ws.name == name then
			return ws
		end
	end
end

local function record_workspace(root)
	local result_path = os.getenv("JJUI_WORKSPACE_RESULT_FILE")
	if not result_path or result_path == "" then
		return true
	end

	local file, err = io.open(result_path, "w")
	if not file then
		return nil, err
	end
	local ok, write_err = file:write(root)
	local closed, close_err = file:close()
	if not ok then
		return nil, write_err
	end
	if not closed then
		return nil, close_err
	end
	return true
end

local function switch_workspace(ws)
	local ok, err = change_workspace(ws.root)
	if not ok then
		flash({ text = "switch failed: " .. tostring(err), error = true })
		return
	end

	local recorded, record_err = record_workspace(ws.root)
	if not recorded then
		flash({
			text = "shell handoff failed: " .. tostring(record_err),
			error = true,
		})
	end
	revisions.refresh()
	flash("workspace: " .. ws.name)
end

local function first_bookmark(change_id)
	local out = jj(
		"--color",
		"never",
		"log",
		"-r",
		change_id,
		"-T",
		"bookmarks",
		"--no-graph"
	)
	if not out then
		return nil
	end
	return out:match("([%w%._/-]+)")
end

local function stack_base(change_id)
	local revset =
		string.format("latest(::parents(%s) & bookmarks())", change_id)
	local out = jj(
		"--color",
		"never",
		"log",
		"-r",
		revset,
		"-T",
		"bookmarks",
		"--no-graph"
	)
	local base = out and out:match("([%w%._/-]+)")
	if base then
		return base
	end
	local trunk = jj(
		"--color",
		"never",
		"log",
		"-r",
		"trunk()",
		"-T",
		"bookmarks",
		"--no-graph"
	)
	return (trunk and trunk:match("([%w%._/-]+)")) or "main"
end

function setup(config)
	config.action("switch workspace", function()
		local workspaces, err = list_workspaces()
		if not workspaces then
			flash({
				text = "workspace list failed: " .. tostring(err),
				error = true,
			})
			return
		end

		local current = current_workspace_root()
		local ordered = {}
		for _, ws in ipairs(workspaces) do
			if ws.root == current then
				table.insert(ordered, ws)
			end
		end
		for _, ws in ipairs(workspaces) do
			if ws.root ~= current then
				table.insert(ordered, ws)
			end
		end

		local options = {}
		for _, ws in ipairs(ordered) do
			local marker = ws.root == current and "* [current] " or "  "
			table.insert(options, marker .. ws.name .. "  (" .. ws.root .. ")")
		end

		local choice = choose({
			options = options,
			title = "Switch workspace",
			ordered = true,
		})
		if not choice then
			return
		end

		for i, option in ipairs(options) do
			if option == choice then
				switch_workspace(ordered[i])
				return
			end
		end
	end, {
		desc = "switch workspace",
		seq = { "w", "w" },
		scope = "revisions",
	})

	config.action("create workspace here", function()
		local change_id = context.change_id()
		if not change_id or change_id == "" then
			flash({ text = "No revision selected", error = true })
			return
		end

		local name = input({ title = "Create workspace", prompt = "name: " })
		if not name then
			return
		end
		name = name:gsub("^%s+", ""):gsub("%s+$", "")
		if name == "" then
			return
		end

		local result_path = os.tmpname()
		exec_shell(
			string.format(
				"WT_RESULT_FILE=%q command wt switch --create %q -r %q",
				result_path,
				name,
				change_id
			)
		)

		local result = io.open(result_path, "r")
		if not result then
			return
		end
		local root = result:read("*a"):gsub("%s+$", "")
		result:close()
		os.remove(result_path)
		if root == "" then
			return
		end

		local updated, err = list_workspaces()
		if not updated then
			flash({
				text = "workspace list failed: " .. tostring(err),
				error = true,
			})
			return
		end
		local ws = find_workspace(updated, root, name)
		if not ws then
			flash({
				text = "created workspace not found: " .. name,
				error = true,
			})
			return
		end
		switch_workspace(ws)
	end, {
		desc = "create workspace here",
		seq = { "w", "c" },
		scope = "revisions",
	})

	config.action("delete workspace", function()
		local workspaces, err = list_workspaces()
		if not workspaces then
			flash({
				text = "workspace list failed: " .. tostring(err),
				error = true,
			})
			return
		end

		local current = current_workspace_root()
		local removable = {}
		for _, ws in ipairs(workspaces) do
			if ws.root ~= current then
				table.insert(removable, ws)
			end
		end
		if #removable == 0 then
			flash("no other workspaces to delete")
			return
		end

		local options = {}
		for _, ws in ipairs(removable) do
			table.insert(options, ws.name .. "  (" .. ws.root .. ")")
		end

		local choice = choose({
			options = options,
			title = "Delete workspace",
			ordered = true,
		})
		if not choice then
			return
		end

		local target
		for i, option in ipairs(options) do
			if option == choice then
				target = removable[i]
				break
			end
		end
		if not target then
			return
		end

		local confirm = choose({
			options = { "delete " .. target.name, "cancel" },
			title = "Delete workspace " .. target.name .. "?",
		})
		if confirm == nil or confirm == "cancel" then
			return
		end

		local _, run_err =
			jj("util", "exec", "--", "wt", "remove", "-y", target.name)
		if run_err then
			flash({
				text = "delete failed: " .. tostring(run_err),
				error = true,
			})
			return
		end
		revisions.refresh()
		flash("deleted workspace: " .. target.name)
	end, {
		desc = "delete workspace",
		seq = { "w", "d" },
		scope = "revisions",
	})

	config.action("create PR", function()
		local change_id = context.change_id()
		if not change_id or change_id == "" then
			flash({ text = "No revision selected", error = true })
			return
		end

		local existing = first_bookmark(change_id)
		if existing then
			flash({ text = "already bookmarked: " .. existing, error = true })
			return
		end

		local name = input({ title = "Create PR", prompt = "branch name: " })
		if not name then
			return
		end
		name = name:gsub("^%s+", ""):gsub("%s+$", "")
		if name == "" then
			return
		end

		local _, create_err = jj("bookmark", "create", name, "-r", change_id)
		if create_err then
			flash({
				text = "bookmark failed: " .. tostring(create_err),
				error = true,
			})
			return
		end

		local _, push_err = jj("git", "push", "--bookmark", name, "--allow-new")
		if push_err then
			flash({ text = "push failed: " .. tostring(push_err), error = true })
			return
		end

		jj_interactive(
			"gh",
			"pr",
			"create",
			"--fill",
			"--head",
			name,
			"--base",
			stack_base(change_id)
		)
		revisions.refresh()
	end, {
		desc = "create PR",
		key = "ctrl+p",
		scope = "revisions",
	})

	config.action("view PR", function()
		local change_id = context.change_id()
		if not change_id or change_id == "" then
			flash({ text = "No revision selected", error = true })
			return
		end

		local name = first_bookmark(change_id)
		if not name then
			flash({ text = "no bookmark on revision", error = true })
			return
		end

		local out, err = jj("util", "exec", "--", "gh", "pr", "view", name)
		if not out then
			flash({ text = "gh failed: " .. tostring(err), error = true })
			return
		end
		jjui.ui.preview.show(out)
	end, {
		desc = "view PR",
		key = "ctrl+o",
		scope = "revisions",
	})

	config.action("open revision in Hunk", function()
		local change_id = context.change_id()
		if not change_id or change_id == "" then
			flash({ text = "No revision selected", error = true })
			return
		end

		exec_shell(string.format("hunk show %q", change_id))
	end, {
		desc = "open revision in Hunk",
		key = "d",
		scope = "revisions",
	})

	config.action("open file diff in Hunk", function()
		local change_id = context.change_id()
		local file = context.file()
		if not change_id or change_id == "" or not file or file == "" then
			flash({ text = "No file selected", error = true })
			return
		end

		exec_shell(string.format("hunk show %q -- %q", change_id, file))
	end, {
		desc = "open file diff in Hunk",
		key = "enter",
		scope = "revisions.details",
	})

	config.action("preview image", function()
		local change_id = context.change_id()
		local file = context.file()
		if not change_id or change_id == "" or not file or file == "" then
			flash({ text = "No file selected", error = true })
			return
		end

		local ext = file:lower():match("%.([%w]+)$")
		local image_exts = {
			png = true,
			jpg = true,
			jpeg = true,
			webp = true,
			gif = true,
			bmp = true,
			tiff = true,
			avif = true,
		}
		if not ext or not image_exts[ext] then
			ui.preview_toggle()
			return
		end

		exec_shell(
			string.format(
				"jj file show -r %q -- %q | imgview --hold -",
				change_id,
				file
			)
		)
	end, {
		desc = "preview image",
		key = "p",
		scope = "revisions.details",
	})

	config.action("diff change images in pix", function()
		local change_id = context.change_id()
		if not change_id or change_id == "" then
			flash({ text = "No revision selected", error = true })
			return
		end

		exec_shell(string.format("pix jj %q", change_id))
	end, {
		desc = "diff change images in pix",
		key = "shift+p",
		scope = "revisions",
	})

	config.action("diff image in pix", function()
		local change_id = context.change_id()
		local file = context.file()
		if not change_id or change_id == "" then
			flash({ text = "No revision selected", error = true })
			return
		end

		local ext = file and file:lower():match("%.([%w]+)$")
		local image_exts = {
			png = true,
			jpg = true,
			jpeg = true,
			webp = true,
			gif = true,
			bmp = true,
			tiff = true,
			avif = true,
		}
		if ext and image_exts[ext] then
			exec_shell(string.format("pix jj %q %q", change_id, file))
		else
			exec_shell(string.format("pix jj %q", change_id))
		end
	end, {
		desc = "diff image in pix",
		key = "shift+p",
		scope = "revisions.details",
	})

	config.action("open file in nvim", function()
		local file = context.file()
		if not file or file == "" then
			flash({ text = "No file selected", error = true })
			return
		end

		exec_shell(string.format("nvim %q", file))
	end, {
		desc = "open file in nvim",
		key = "e",
		scope = "revisions.details",
	})

	config.action("open file in yazi", function()
		local file = context.file()
		if not file or file == "" then
			flash({ text = "No file selected", error = true })
			return
		end

		exec_shell(string.format("yazi %q", file))
	end, {
		desc = "open file in yazi",
		key = "y",
		scope = "revisions.details",
	})
end
