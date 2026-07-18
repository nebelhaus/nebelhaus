--- @since 26.1.22

-- peek-open — bound to Enter in the main yazi keymap, but only CHANGES anything
-- inside the "peek" overlay (Super y, see zellij/peek-run.sh, which exports
-- PEEK=1). There it branches on the hovered entry:
--   • directory → write its path to ~/.cache/peek.cwd and quit yazi, so
--     peek-run.sh spawns a new zellij tab cwd'd there (the old Super-Shift-t
--     browse-and-pick flow, folded into peek). Descend to browse with l/→.
--   • file → fall through to `open`, paging it fullscreen — peek stays a reader.
-- Outside peek (a normal `yy` session, PEEK unset) it is a plain passthrough to
-- `open`, i.e. exactly yazi's default Enter — so regular yazi is unaffected.
-- Uses only the modern (26.x) Lua API (ya.sync / ya.emit), matching the other
-- vendored plugins in this tree.

-- Read the hovered entry in the sync context; return its path iff it's a dir.
local hovered_dir = ya.sync(function()
	local h = cx.active.current.hovered
	if h and h.cha.is_dir then
		return tostring(h.url)
	end
	return nil
end)

return {
	entry = function()
		local dir = os.getenv("PEEK") == "1" and hovered_dir()
		if not dir then
			-- Not in peek, or hovering a file: yazi's default Enter (open/page).
			ya.emit("open", {})
			return
		end

		-- Hand the picked directory to peek-run.sh via a fixed drop file, then
		-- quit so it can spawn the tab. HOME is always set in the peek instance.
		local out = (os.getenv("HOME") or "") .. "/.cache/peek.cwd"
		local f = io.open(out, "w")
		if f then
			f:write(dir)
			f:close()
		end
		ya.emit("quit", {})
	end,
}
