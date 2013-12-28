--[[
Description
	Auto4 script written in Lua for subtitle editor Aegisub.
	Purpose is stated in the "script_description" variable. Aegisub itself, as well as similar script from plorkyeran (ATM does not select all collisions (!)) allow users to select collisions, but they both have one drawback: if you want to edit one subtitle from the collided group, sooner or later you'll have to deselect other subs. Having marks like these can make user experience more pleasant: you just browse and edit whatever you want w/o the need to reselect subs. Also, sometimes, you want to know whether subtitle collided with other subs or not, even when you solved the collision and there's no chance of it ever happening again.


Notes
	http://en.wikipedia.org/wiki/Interval_tree
]]--


script_author = "8day"
script_version = "1.3.1"
script_modified = "27.12.2013"
script_name = "Mark-, unmark two selected collided subtitles"
script_description = "Marks selected collided subs by adding keyword \"collision\" to the Actor field of SSA subtitles"


local mark_collisions = {}
local undo_marking_of_collisions = {}


mark_collisions.script_name = "Mark selected collisions"
mark_collisions.script_description = script_description
undo_marking_of_collisions.script_name = "Un-mark selected collisions"
undo_marking_of_collisions.script_description = "Un-marks marked subtitles"


function mark(sub)
	if sub.actor == "" then
		sub.actor = "collision"
	else
		sub.actor = "collision (" .. sub.actor .. ")"
	end
	return sub
end


function sort_by_time(subs, sel, field)
	-- AFAIK, while sorting, info for comparing can be used
	-- few times, so it must be precomputed.
	-- See notes on why I used pairs() instead of ipairs() in macro().
	aegisub.progress.task("Pre-sorting subtitles")
	local tmp1 = {}
	local i = 1
	for _, v in pairs(sel) do
		tmp1[i] = {idx = v, val = subs[v][field]}
		i = i + 1
	end
	-- Lua's built-in function sorts tables in place.
	table.sort(tmp1, function (a, b) return a.val < b.val end)
	local tmp2 = {}
	local i = 1
	for _, v in pairs(tmp1) do
		tmp2[i] = v.idx
		i = i + 1
	end
	return tmp2
end


function find_collisions(subs, sel)
	aegisub.progress.task("Searching collisions")
	local prv, act, nxt
	local overlap_with_prev = false
	local idxs = {}
	for i = 1, #sel - 1 do
		act = subs[sel[i]]
		nxt = subs[sel[i + 1]]
		if act.end_time > nxt.start_time then
			table.insert(idxs, sel[i])
			overlap_with_prev = true
		else
			if overlap_with_prev then
				prv = subs[sel[i - 1]]
				if prv.end_time > act.start_time then
					table.insert(idxs, sel[i])
					overlap_with_prev = false
				end
			end
		end
	end
	if overlap_with_prev then
		prv = subs[sel[#sel - 1]]
		act = subs[sel[#sel]]
		if prv.end_time > act.start_time then
			table.insert(idxs, sel[#sel])
			overlap_with_prev = false
		end
	end
	return idxs
end


function mark_collisions.macro(subs, sel)
	if #sel > 1 then
		aegisub.progress.task("Initializing")
		local stime, etime
		stime = sort_by_time(subs, sel, "start_time")
		etime = sort_by_time(subs, sel, "end_time")
		stime = find_collisions(subs, stime)
		etime = find_collisions(subs, etime)
		local idxs = {}
		if next(stime) and next(etime) then
			-- Create set for faster (?!) concatenation of arrays.
			local set = {}
			for _, v in pairs(stime) do
				set[v] = v
			end
			for _, v in pairs(etime) do
				set[v] = v
			end
			-- Convert back to an array.
			-- Don't know why, but I had some problems with ipairs(),
			-- it lead to really weierd bug... Probably, it would
			-- be better to leave this cycle in it's current form.
			local i = 1
			for _, v in pairs(set) do
				idxs[i] = v
				i = i + 1
			end
		elseif next(stime) then
			idxs = stime
		elseif next(etime) then
			idxs = etime
		end
		if next(idxs) then
			for _, v in pairs(idxs) do
				subs[v] = mark(subs[v])
			end
			aegisub.set_undo_point("\"" .. script_name .. "\"")
		end
	else
		aegisub.progress.task("Error")
		aegisub.debug.out("You have selected only one subtitle, try to select some more.")
		return false
	end
end


function undo_marking_of_collisions.macro(subs, sel)
	aegisub.progress.task("Un-marking")
	local sub
	local changes_were_made = false
	for i = sel[1], sel[#sel] do
		sub = subs[i]
		if string.find(sub.actor, "^collision %(.+%)$") then
			sub.actor = string.gsub(sub.actor, "^collision %((.+)%)$", "%1")
			subs[i] = sub
			changes_were_made = true
		elseif string.find(sub.actor, "^collision$") then
			sub.actor = ""
			subs[i] = sub
			changes_were_made = true
		end
	end
	if changes_were_made then aegisub.set_undo_point("\"" .. undo_marking_of_collisions.script_name .. "\"") end
end


aegisub.register_macro(mark_collisions.script_name, mark_collisions.script_description, mark_collisions.macro)
aegisub.register_macro(undo_marking_of_collisions.script_name, undo_marking_of_collisions.script_description, undo_marking_of_collisions.macro)
