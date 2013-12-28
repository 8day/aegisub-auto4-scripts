--[[
Description
	Auto4 script written in Lua for subtitle editor Aegisub.
	Purpose is stated in the "script_description" variable. Take a note that the approach described here does not always work (!). That's probably because the **whole** vanishing point should've been used as an origin \org, but since its calculation is very hard (I don't know math that well), I came up with this alternative (org.y = video.height/2) that does not work always, but simplifies handpicking of approximate angles for \fr[xyz].


HowTo
	1) find rotated plane on top of which you want to place your graphics. Make sure that edges are visible, at least enough to draw a line on top of them;
	2) create first subtitle, and use \move (start and end point should represent ends of an interval) to draw a line on top of one edge;
	3) repeat second step, but make sure that second line is parallel to the one that was drawn in the first step;
	4) select both subtitles and use this script;
	5) through trial-and-error try to find the best possible \fr[xyz] to suit your plane.
	Video showing how to do this is here: youtu.be/oLNLzyvOGj0


ToDo
	Add function to determine plane rotation.
]]--


include("karaskel.lua")


script_name = "Calculate \\org to reproduce perspective distortion"
script_description = "Calculates values for \\org to aid in manual perspective distortion reproduction, i.e. to make your subs look like they were positioned in 3D space."
script_author = "8day"
script_version = "1.2.2"
script_modified = "27.12.2013"


function roundNum(val, decimal)
	if (decimal) then
		return math.floor(((val * 10^decimal) + 0.5) / (10^decimal))
	else
		return math.floor(val + 0.5)
	end
end


-- This algorithm was taken from http://alienryderflex.com/intersect/
-- Apperently, its author is Darel Rex Finley.
function point_of_intersection(Ax, Ay, Bx, By, Cx, Cy, Dx, Dy)
	local msg, distAB, theCos, theSin, newX, ABpos, X, Y
	-- Fail if either line is undefined.
	if (Ax == Bx and Ay == By) or (Cx == Dx and Cy == Dy) then
		msg = "One of the lines is undefined, i.e. both points specified in one of the \\move are in the same place.\n"
		aegisub.progress.title("Error")
		aegisub.debug.out(msg)
		return false
	end
	-- 1) Translate the system so that point A is on the origin.
	Bx = Bx - Ax; By = By - Ay
	Cx = Cx - Ax; Cy = Cy - Ay
	Dx = Dx - Ax; Dy = Dy - Ay
	-- Discover the length of segment A-B.
	distAB = math.sqrt(Bx * Bx + By * By)
	-- 2) Rotate the system so that point B is on the positive X axis.
	theCos = Bx / distAB
	theSin = By / distAB
	newX = Cx * theCos + Cy * theSin
	Cy = Cy * theCos - Cx * theSin
	Cx = newX
	newX = Dx * theCos + Dy * theSin
	Dy = Dy * theCos - Dx * theSin
	Dx = newX
	-- Somehow, I cannot simply compare two numbers...
	-- Had to use this "rounding"...
	-- WTF I'm doing wrong here...?!
	if roundNum(Cy, 12) == roundNum(Dy, 12) then
		msg = "Lines specified by \\move are parallel!\n"
		aegisub.progress.title("Error")
		aegisub.debug.out(msg)
		return false
	end
	-- 3) Discover the position of the intersection point along line A-B.
	ABpos = Dx + (Cx - Dx) * Dy / (Dy - Cy)
	-- 4) Apply the discovered position to line A-B in the original coordinate system.
	X = Ax + ABpos * theCos
	Y = Ay + ABpos * theSin
	-- Success.
	return {["x"] = X, ["y"] = Y}

end


-- Main abracadabra.
function calculate_org(subs, sel)
	local msg
	-- Check whether user selected exactly two subs.
	if #sel ~= 2 then
		msg = string.format("You should choose exactly two subtitles, not %d!\n", #sel)
		aegisub.progress.title("Error")
		aegisub.debug.out(msg)
		return false
	end
	-- Check whether both subs are alike.
	local meta, styles, fst, snd
	meta, styles = karaskel.collect_head(subs, false)
	fst, snd = subs[sel[1]], subs[sel[2]]
	karaskel.preproc_line_text(meta, styles, fst)
	karaskel.preproc_line_text(meta, styles, snd)
	entries = {"class", "text_stripped", "layer", "start_time", "end_time", "style", "actor", "margin_l", "margin_r", "margin_t", "margin_b", "effect"}
	for i, entry in pairs(entries) do
		if fst[entry] ~= snd[entry] then
			msg = string.format("Selected subtitles are different in the field \"%s\".\n", entry)
			aegisub.progress.title("Error")
			aegisub.debug.out(msg)
			return false
		end
	end
	-- Find which \move flavour were used.
	local nmb, content1, content2, pattern1, pattern2, pattern_move
	nmb = "%s*(-?%d+%.?%d*)%s*"
	content1 = string.format("%s,%s,%s,%s,%s,%s", nmb, nmb, nmb, nmb, nmb, nmb)
	content2 = string.format("%s,%s,%s,%s", nmb, nmb, nmb, nmb)
	pattern1 = "\\move%(" .. content1 .. "%)"
	pattern2 = "\\move%(" .. content2 .. "%)"
	if string.find(fst.text, pattern1) and string.find(snd.text, pattern1) then
		pattern_move = pattern1
	elseif string.find(fst.text, pattern2) and string.find(snd.text, pattern2) then
		pattern_move = pattern2
	else
		msg = "Couldn't find all \\move tags. Most likely one of them is absent or malformed."
		aegisub.progress.title("Error")
		aegisub.debug.out(msg)
		return false
	end
	-- Find vanishing point.
	local m1_x1, m1_x2, m1_y1, m1_y2, m2_x1, m2_x2, m2_y1, m2_y2, vanishing_point
	m1_x1, m1_x2, m1_y1, m1_y2 = string.match(fst.text, pattern_move)
	m2_x1, m2_x2, m2_y1, m2_y2 = string.match(snd.text, pattern_move)
	vanishing_point = point_of_intersection(m1_x1, m1_x2, m1_y1, m1_y2, m2_x1, m2_x2, m2_y1, m2_y2)
	if vanishing_point == false then
		return false
	end
	-- Final processing:
	-- 1) calculate coordinates for \org;
	-- 2) replace first \move by \org;
	-- 3) remove second \move.
	local org_x, org_y, org, pattern_org
	org_x = math.floor(meta.res_x / 2)
	org_y = math.floor(vanishing_point.y)
	org = string.format("\\org(%d,%d)", org_x, org_y)
	pattern_org = "\\org%(" .. nmb .. "," .. nmb .. "%)"
	if string.find(fst.text, pattern_org) then
		fst.text = string.gsub(fst.text, pattern_org, org)
		fst.text = string.gsub(fst.text, pattern_move, "")
	else
		fst.text = string.gsub(fst.text, pattern_move, org)
	end
	subs[sel[1]] = fst
	subs.delete(sel[2])
	return true
end


-- Macro.
function macro(subs, sel)
	if calculate_org(subs, sel) then aegisub.set_undo_point("\"" .. script_name .. "\"") end
end


-- Register macro in Aegisub.
aegisub.register_macro(script_name, script_description, macro)
