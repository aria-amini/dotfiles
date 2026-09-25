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
