--[[
Description
	Auto4 script written in Lua for subtitle editor Aegisub.
	Purpose is stated in the "script_description" variable. In some cases it is more preferable to the Aegisub's own Resample Resolution (Aegi scales drawing & fonts while this script, when in scaling mode, scales mainly output resolution, if I may say so, i.e. \fsc[xy] and Scale[XY]), but sometimes not. Compared to Aegisub's tool this one is modular, as you can see, which might have its own benefits (see description of desired tool). Also it fixed some wrong behaviour of Aegisub, like when you may have had doubled margins etc. In any case, both Aegisub and this script do not touch such codes like \fr[xyz] since it is very hard to transform them in the right way, one has to know math very, very, very well. If interested, you may google "pose estimation for planes".


ToDo
	Add notifications for cases when margins cannot be shifted further.
]]--


require "re"


script_author = "8day"
script_version = "1.1"
script_modified = "31.12.2013"
script_name = "Tools for Resize"
script_description = "Tools for misc script resizing."


resize_canvas = {}
shift_relative_layout = {}
shift_absolute_layout = {}
scale_subtitles = {}


resize_canvas.trafo_type					= "resize_canvas"
resize_canvas.script_name					= "Tools for Resize: Resize Canvas"
resize_canvas.script_description			= "Resize Canvas is the same as: Aegisub > Main menu > File > Properties > Resolution. Made as an Automation script in order to group related transformations in one place."
resize_canvas.script_author					= script_author
resize_canvas.script_version				= script_version
resize_canvas.script_modified				= script_modified


shift_absolute_layout.trafo_type			= "shift_absolute_layout"
shift_absolute_layout.script_name			= "Tools for Resize: Shift Absolute Layout"
shift_absolute_layout.script_description	= "Can be used for typeset remake for over-/undercropped video, e.g. letterboxed."
shift_absolute_layout.script_author			= script_author
shift_absolute_layout.script_version		= script_version
shift_absolute_layout.script_modified		= script_modified


shift_relative_layout.trafo_type			= "shift_relative_layout"
shift_relative_layout.script_name			= "Tools for Resize: Shift Relative Layout"
shift_relative_layout.script_description	= "Can be used for typeset remake for over-/undercropped video, e.g. letterboxed. Has some limitaions, e.g. it cannot shift relative layout outside of specified video resolution (SSA does not support negative margins) because it can be achieved only through \pos etc., i.e. by converting relative layout to absolute."
shift_relative_layout.script_author			= script_author
shift_relative_layout.script_version		= script_version
shift_relative_layout.script_modified		= script_modified


scale_subtitles.trafo_type					= "scale_subtitles"
scale_subtitles.script_name					= "Tools for Resize: Scale Subtitles"
scale_subtitles.script_description			= "Can be used for typeset remake for up-/downscaled video, e.g. anamorphic."
scale_subtitles.script_author				= script_author
scale_subtitles.script_version				= script_version
scale_subtitles.script_modified				= script_modified


-- "extensions" for lua.


function table.val_to_str(v)
	if "string" == type(v) then
		v = string.gsub(v, "\n", "\\n")
		if string.match( string.gsub(v, "[^'\"]", ""), '^"+$') then
			return "'" .. v .. "'"
		end
		return '"' .. string.gsub(v, '"', '\\"') .. '"'
	else
		return "table" == type(v) and table.tostring(v) or
			tostring(v)
	end
end


function table.key_to_str(k)
	if "string" == type(k) and string.match(k, "^[_%a][_%a%d]*$") then
		return k
	else
		return "[" .. table.val_to_str(k) .. "]"
	end
end


function table.tostring(tbl)
	local result, done = {}, {}
	for k, v in ipairs(tbl) do
		table.insert(result, table.val_to_str(v))
		done[k] = true
	end
	for k, v in pairs(tbl) do
		if not done[k] then
			table.insert(result, table.key_to_str(k) .. "=" .. table.val_to_str(v))
		end
	end
	return "{" .. table.concat(result, ",") .. "}"
end


function string.starts(String, Start)
   return string.sub(String, 1, string.len(Start)) == Start
end


function string.ends(String,End)
   return End == "" or string.sub(String, -string.len(End)) == End
end


-- initing.


local current_trafo_type = ""
if not intervals_of_sections then local intervals_of_sections = {} end
local registry = {} -- must be predefined!
local digit_sequence = "(?:[0-9]+)"
local sign = "[+-]"
local fraction = string.format("(?:%s?\\.%s|%s\\.)", digit_sequence, digit_sequence, digit_sequence)
local signed_number = string.format("(?:%s?%s|%s?%s)", sign, fraction, sign, digit_sequence)
local unsigned_number = string.format("(?:%s|%s)", fraction, digit_sequence)


-- caching of sections indeces.


function calculate_intervals_of_sections(lines)
	local new_section = true
	local curr = {}
	local next = {}
	local prev = {}
	local interval = {}
	local list_of_intervals = {}
	if #lines > 2 then
		for i = 1, #lines - 1 do
			curr = lines[i]
			next = lines[i + 1]
			if curr.section == next.section then
				-- create a new interval and set an end of it later on since it has continuation
				if new_section == true then
					list_of_intervals[curr.section] = {start = i}
					new_section = false
				end
			else
				-- create a new interval
				if new_section == true then
					list_of_intervals[curr.section] = {start = i}
					new_section = false
				end
				-- set an end of an interval since that is its last occurance
				interval = list_of_intervals[curr.section]
				interval["end"] = i
				list_of_intervals[curr.section] = interval
				new_section = true
			end
		end
		prev = lines[#lines - 1]
		curr = lines[#lines]
		if prev.section == curr.section then
			-- set an end of an unclosed interval
			interval = list_of_intervals[prev.section]
			interval["end"] = #lines
			list_of_intervals[prev.section] = interval
			new_section = true
		else
			-- create a new interval
			list_of_intervals[curr.section] = {start = #lines}
			new_section = false
			-- set an end of an interval since that is its last occurance
			interval = list_of_intervals[curr.section]
			interval["end"] = #lines
			list_of_intervals[curr.section] = interval
			new_section = true
		end
	end
	return list_of_intervals
end


-- processing funcs.


local shift_point = {rep_count = 1}
function shift_point.process(opA, opB)
	if shift_point.rep_count == 1 then
		shift_point.rep_count = 2
		opA = opA + opB.x
	elseif shift_point.rep_count == 2 then
		shift_point.rep_count = 1
		opA = opA + opB.y
	end
	return opA
end


local scale_point = {rep_count = 1}
function scale_point.process(opA, opB)
	if scale_point.rep_count == 1 then
		scale_point.rep_count = 2
		opA = opA * opB.x
	elseif scale_point.rep_count == 2 then
		scale_point.rep_count = 1
		opA = opA * opB.y
	end
	return opA
end


function choose_rep_count(axes, x, y)
	local rep_count = 0
	if axes == "X axes" then
		rep_count = 1
	elseif axes == "Y axes" then
		rep_count = 2
	elseif axes == "X and Y axes: whichever is bigger" then
		if x > y then
			rep_count = 1
		else
			rep_count = 2
		end
	elseif axes == "X and Y axes: whichever is smaller" then
		if x < y then
			rep_count = 1
		else
			rep_count = 2
		end
	end
	return rep_count
end


-- functions for SSA Script Info section processing.


local playresx = {}
function playresx.process(opA, operator, opB)
	return tostring(opB.x)
end


local playresy = {}
function playresy.process(opA, operator, opB)
	return tostring(opB.y)
end


local info = {call_counter = 1, name = "", value = ""}
function info.process(opA, operator, opB)
	local supported_infos = registry[current_trafo_type]["[Script Info]"]["Aegisub's Advanced SSA script info"]
	if info.call_counter == 1 then
		info.call_counter = 2
		info.name = opA
	elseif info.call_counter == 2 and info.value ~= nil then
		info.call_counter = 1
		info.value = opA
		if supported_infos[info.name] then
			opA = supported_infos[info.name].process(opA, operator, opB)
		end
	end
	return opA
end


-- functions for SSA V4+ Styles section atts processing.


local scale_x = {}
function scale_x.process(opA, operator, opB)
	operator.rep_count = 1
	return tostring(operator.process(opA, opB))
end


local scale_y = {}
function scale_y.process(opA, operator, opB)
	operator.rep_count = 2
	return tostring(operator.process(opA, opB))
end


local outline = {}
function outline.process(opA, operator, opB)
	operator.rep_count = choose_rep_count(opB.type_of_scaling_for_codes_with_one_axes, opB.x, opB.y)
	return tostring(operator.process(opA, opB))
end


local shadow = {}
function shadow.process(opA, operator, opB)
	operator.rep_count = choose_rep_count(opB.type_of_scaling_for_codes_with_one_axes, opB.x, opB.y)
	return tostring(operator.process(opA, opB))
end


local margin_l_styles = {}
function margin_l_styles.process(opA, operator, opB)
	operator.rep_count = 1
	if opB.margin_l ~= nil then opB.x = opB.margin_l end -- it is a hack, as all similar code below.
	return tostring(operator.process(opA, opB))
end


local margin_r_styles = {}
function margin_r_styles.process(opA, operator, opB)
	operator.rep_count = 1
	if opB.margin_r ~= nil then opB.x = opB.margin_r end
	return tostring(operator.process(opA, opB))
end


local margin_t_styles = {}
function margin_t_styles.process(opA, operator, opB)
	operator.rep_count = 2
	if opB.margin_v ~= nil then opB.y = opB.margin_v end
	return tostring(operator.process(opA, opB))
end


local margin_b_styles = {}
function margin_b_styles.process(opA, operator, opB)
	operator.rep_count = 2
	if opB.margin_v ~= nil then opB.y = opB.margin_v end
	return tostring(operator.process(opA, opB))
end


-- functions for SSA Events section atts processing.
-- event's margins are here because unlike style's margins they are processed only when they have overriden values, i.e. non-zero.


local margin_l_events = {processed_opA = 0}
function margin_l_events.process(opA, operator, opB)
	if tonumber(opA) > 0 then
		operator.rep_count = 1
		if opB.margin_l ~= nil then opB.x = opB.margin_l end
		margin_l_events.processed_opA = operator.process(opA, opB)
		if margin_l_events.processed_opA > 0 then
			opA = margin_l_events.processed_opA
		else -- warn user!
			opA = 0
		end
		opA = tostring(opA)
	end
	return opA
end


local margin_r_events = {processed_opA = 0}
function margin_r_events.process(opA, operator, opB)
	if tonumber(opA) > 0 then
		operator.rep_count = 1
		if opB.margin_r ~= nil then opB.x = opB.margin_r end
		margin_r_events.processed_opA = operator.process(opA, opB)
		if margin_r_events.processed_opA > 0 then
			opA = margin_r_events.processed_opA
		else -- warn user!
			opA = 0
		end
		opA = tostring(opA)
	end
	return opA
end


local margin_t_events = {processed_opA = 0}
function margin_t_events.process(opA, operator, opB)
	if tonumber(opA) > 0 then
		operator.rep_count = 2
		if opB.margin_v ~= nil then opB.y = opB.margin_v end
		margin_t_events.processed_opA = operator.process(opA, opB)
		if margin_t_events.processed_opA > 0 then
			opA = margin_t_events.processed_opA
		else -- warn user!
			opA = 0
		end
		opA = tostring(opA)
	end
	return opA
end


local margin_b_events = {processed_opA = 0}
function margin_b_events.process(opA, operator, opB)
	if tonumber(opA) > 0 then
		operator.rep_count = 2
		if opB.margin_v ~= nil then opB.y = opB.margin_v end
		margin_b_events.processed_opA = operator.process(opA, opB)
		if margin_b_events.processed_opA > 0 then
			opA = margin_b_events.processed_opA
		else -- warn user!
			opA = 0
		end
		opA = tostring(opA)
	end
	return opA
end


-- functions for SSA codes processing.


function format_and_compile_code_re(str)
	str = str:gsub("%s+", "")
	str = str:gsub("{signed_number}", signed_number)
	str = str:gsub("{unsigned_number}", unsigned_number)
	return re.compile(str, re.ICASE)
end


-- \p, and only \p (e.g. not \clip), should be checked for collision with \pos & \move. if there is such abs. pos. code (when abs. shifting; the code can be anywhere in the subtitle since it is "absolute", according to my classification) then either drawings should be shifted or such codes. frankly, i don't know which way is the right one, so it may be better to make it an option.
local p = {text_type = "", abs_pos_code_in_line = true}
function p.process(opA, operator, opB)
	if tonumber(p.re:match(opA)[3]["str"]) > 0 then
		p.text_type = "drawing"
	else
		p.text_type = "text"
	end
	return opA
end
function p.process_drawing(opA, operator, opB)
	local coordinate = 0
	local processed_strs = ""
	if current_trafo_type == "shift_absolute_layout" and p.abs_pos_code_in_line == false then
		operator.rep_count = 1
		for str in p.drawing_re:gfind(opA) do
			coordinate = tonumber(str)
			if coordinate ~= nil then
				processed_strs = processed_strs .. operator.process(coordinate, opB)
			else
				processed_strs = processed_strs .. str
			end
		end
		opA = processed_strs
	end
	return opA
end
p.re = format_and_compile_code_re("(\\\\p \\s* ) ({unsigned_number})")
p.drawing_re = format_and_compile_code_re(signed_number .. "|.")


local clip = {}
function clip.process(opA, operator, opB)
	local match = clip.scaling_factor_re:match(opA)
	local coordinate = 0
	local processed_strs = ""
	if #match == 4 then
		processed_strs = match[2]["str"] .. match[3]["str"]
		opA = match[4]["str"]
	elseif #match == 3 then
		processed_strs = match[2]["str"]
		opA = match[3]["str"]
	end
	operator.rep_count = 1
	for str in clip.drawing_re:gfind(opA) do
		coordinate = tonumber(str)
		if coordinate ~= nil then
			processed_strs = processed_strs .. operator.process(coordinate, opB)
		else
			processed_strs = processed_strs .. str
		end
	end
	return processed_strs
end
clip.re = format_and_compile_code_re("(\\\\clip \\s*? \\() ([^)]+) (\\) .*)")
clip.scaling_factor_re = format_and_compile_code_re("(\\\\clip \\s*? \\( \\s*? ) (\\d+ \\s*? , \\s*?)? (.*)")
clip.drawing_re = format_and_compile_code_re(signed_number .. "|.")


local iclip = {}
function iclip.process(opA, operator, opB)
	local match = iclip.scaling_factor_re:match(opA)
	local coordinate = 0
	local processed_strs = ""
	if #match == 4 then
		processed_strs = match[2]["str"] .. match[3]["str"]
		opA = match[4]["str"]
	elseif #match == 3 then
		processed_strs = match[2]["str"]
		opA = match[3]["str"]
	end
	operator.rep_count = 1
	for str in iclip.drawing_re:gfind(opA) do
		coordinate = tonumber(str)
		if coordinate ~= nil then
			processed_strs = processed_strs .. operator.process(coordinate, opB)
		else
			processed_strs = processed_strs .. str
		end
	end
	return processed_strs
end
iclip.re = format_and_compile_code_re("(\\\\iclip \\s*? \\() ([^)]+) (\\) .*)")
iclip.scaling_factor_re = format_and_compile_code_re("(\\\\iclip \\s*? \\( \\s*? ) (\\d+ \\s*? , \\s*?)? (.*)")
iclip.drawing_re = format_and_compile_code_re(signed_number .. "|.")


local org = {}
function org.process(opA, operator, opB)
	local match = org.re:match(opA)
	operator.rep_count = 1
	return match[2]["str"] .. operator.process(match[3]["str"], opB) .. match[4]["str"] .. operator.process(match[5]["str"], opB) .. match[6]["str"]
end
org.re = format_and_compile_code_re("(\\\\org \\s*? \\( \\s*? )({signed_number}) (\\s*? , \\s*?) ({signed_number}) (\\) .*)")


local pos = {}
function pos.process(opA, operator, opB)
	local match = pos.re:match(opA)
	operator.rep_count = 1
	return match[2]["str"] .. operator.process(match[3]["str"], opB) .. match[4]["str"] .. operator.process(match[5]["str"], opB) .. match[6]["str"]
end
pos.re = format_and_compile_code_re("(\\\\pos \\s*? \\( \\s*? )({signed_number}) (\\s*? , \\s*?) ({signed_number}) (\\) .*)")


local move = {}
function move.process(opA, operator, opB)
	local vals = re.split(move.re:match(opA)[4]["str"], ",")
	operator.rep_count = 1
	if #vals == 4 then
		-- simple move
		opA = string.format("\\move(%g,%g,%g,%g)", operator.process(vals[1], opB), operator.process(vals[2], opB), operator.process(vals[3], opB), operator.process(vals[4], opB))
	elseif #vals == 6 then
		-- complex move
		opA = string.format("\\move(%g,%g,%g,%g,%g,%g)", operator.process(vals[1], opB), operator.process(vals[2], opB), operator.process(vals[3], opB), operator.process(vals[4], opB), vals[5], vals[6])
	end
	return opA
end
move.re = format_and_compile_code_re("(\\\\move \\s*?) (\\( \\s*?) (.+?) (\\s*? \\))")


local bord = {}
function bord.process(opA, operator, opB)
	local match = bord.re:match(opA)
	operator.rep_count = choose_rep_count(opB.type_of_scaling_for_codes_with_one_axes, opB.x, opB.y)
	return match[2]["str"] .. operator.process(match[3]["str"], opB) .. match[4]["str"]
end
bord.re = format_and_compile_code_re("(\\\\bord \\s*?) ({unsigned_number}) (.*)")


local shad = {}
function shad.process(opA, operator, opB)
	local match = shad.re:match(opA)
	operator.rep_count = choose_rep_count(opB.type_of_scaling_for_codes_with_one_axes, opB.x, opB.y)
	return match[2]["str"] .. operator.process(match[3]["str"], opB) .. match[4]["str"]
end
shad.re = format_and_compile_code_re("(\\\\shad \\s*?) ({signed_number}) (.*)")


local fscx = {}
function fscx.process(opA, operator, opB)
	local match = fscx.re:match(opA)
	operator.rep_count = 1
	return match[2]["str"] .. operator.process(match[3]["str"], opB) .. match[4]["str"]
end
fscx.re = format_and_compile_code_re("(\\\\fscx \\s*?) ({unsigned_number}) (.*)")


local fscy = {}
function fscy.process(opA, operator, opB)
	local match = fscy.re:match(opA)
	operator.rep_count = 2
	return match[2]["str"] .. operator.process(match[3]["str"], opB) .. match[4]["str"]
end
fscy.re = format_and_compile_code_re("(\\\\fscy \\s*?) ({unsigned_number}) (.*)")


local xbord = {}
function xbord.process(opA, operator, opB)
	local match = xbord.re:match(opA)
	operator.rep_count = 1
	return match[2]["str"] .. operator.process(match[3]["str"], opB) .. match[4]["str"]
end
xbord.re = format_and_compile_code_re("(\\\\xbord \\s*?) ({unsigned_number}) (.*)")


local ybord = {}
function ybord.process(opA, operator, opB)
	local match = ybord.re:match(opA)
	operator.rep_count = 2
	return match[2]["str"] .. operator.process(match[3]["str"], opB) .. match[4]["str"]
end
ybord.re = format_and_compile_code_re("(\\\\ybord \\s*?) ({unsigned_number}) (.*)")


local xshad = {}
function xshad.process(opA, operator, opB)
	local match = xshad.re:match(opA)
	operator.rep_count = 1
	return match[2]["str"] .. operator.process(match[3]["str"], opB) .. match[4]["str"]
end
xshad.re = format_and_compile_code_re("(\\\\xshad \\s*?) ({signed_number}) (.*)")


local yshad = {}
function yshad.process(opA, operator, opB)
	local match = yshad.re:match(opA)
	operator.rep_count = 2
	return match[2]["str"] .. operator.process(match[3]["str"], opB) .. match[4]["str"]
end
yshad.re = format_and_compile_code_re("(\\\\yshad \\s*?) ({signed_number}) (.*)")


local pbo = {}
function pbo.process(opA, operator, opB)
	local match = pbo.re:match(opA)
	operator.rep_count = 2
	return match[2]["str"] .. operator.process(match[3]["str"], opB) .. match[4]["str"]
end
pbo.re = format_and_compile_code_re("(\\\\pbo \\s*?) ({signed_number}) (.*)")


local blur = {}
function blur.process(opA, operator, opB)
	local match = blur.re:match(opA)
	operator.rep_count = choose_rep_count(opB.type_of_scaling_for_codes_with_one_axes, opB.x, opB.y)
	return match[2]["str"] .. operator.process(match[3]["str"], opB) .. match[4]["str"]
end
blur.re = format_and_compile_code_re("(\\\\blur \\s*?) ({unsigned_number}) (.*)")


-- if i ever implement \t processing, i should split this into text & boc splitting with delegation of boc and text processing to another funcs.
local text = {}
function text.process(opA, operator, opB)
	local supported_codes = registry[current_trafo_type]["[Events]"]["Aegisub's Advanced SSA codes"]
	local blocks = {}
	local block = ""
	local processed_block = ""
	local codes = {}
	local code = ""
	local code_name = ""
	local m = 0
	local n = 0
	if opA:find("\\pos") ~= nil or opA:find("\\move") ~= nil then
		p.abs_pos_code_in_line = true
	else
		p.abs_pos_code_in_line = false
	end
	blocks = re.find(opA, "\\{.*?\\}|[^\\{]+")
	for i = 1, #blocks do
		block = blocks[i]["str"]
		processed_block = ""
		if block:starts("{\\") and block:ends("}") then
			block = block:sub(2, -2)
			if block ~= nil then
				codes = re.find(block, "\\\\[^\\\\]+")
				if codes ~= nil then
					for j = 1, #codes do
						code = codes[j]["str"]
						m, n = code:find("\\%a+")
						if m ~= nil and n ~= nil then
							code_name = code:sub(m, n)
							if supported_codes[code_name] ~= nil then
								code = supported_codes[code_name].process(code, operator, opB)
							end
						end
						processed_block = processed_block .. code
					end
					blocks[i]["str"] = "{" .. processed_block .. "}"
				end
			end
		else
			if p.text_type == "drawing" then
				blocks[i]["str"] = p.process_drawing(block, operator, opB)
			end
		end
	end
	opA = ""
	for i = 1, #blocks do
		opA = opA .. blocks[i]["str"]
	end
	return opA
end


-- the almighty Registry; defined in the very beginning.
-- describes the elements that should be processed as well as maps them to the their objects.


registry = {
	["resize_canvas"] = {
		["[Script Info]"] = {
			["key"]			= info,
			["value"]		= info,
			["Aegisub's Advanced SSA script info"] = {
				["PlayResX"]= playresx,
				["PlayResY"]= playresy,
			},
		},
	},
	["shift_absolute_layout"] = {
		["[Events]"] = {
			["text"]		= text,
			["Aegisub's Advanced SSA codes"] = {
				["\\org"]	= org,
				["\\pos"]	= pos,
				["\\move"]	= move,
				["\\p"]		= p,
				["\\clip"]	= clip,
				["\\iclip"]	= iclip,
			},
		},
	},
	["shift_relative_layout"] = {
		["[V4+ Styles]"] = {
			-- "margin_x_styles" always changes.
			["margin_l"]	= margin_l_styles,
			["margin_r"]	= margin_r_styles,
			["margin_t"]	= margin_t_styles,
			["margin_b"]	= margin_b_styles,
		},
		["[Events]"] = {
			-- "margin_x_events" should change only when the original value is greater than zero.
			["margin_l"]	= margin_l_events,
			["margin_r"]	= margin_r_events,
			["margin_t"]	= margin_t_events,
			["margin_b"]	= margin_b_events,
		},
	},
	["scale_subtitles"] = {
		["[V4+ Styles]"] = {
			["shadow"]		= shadow,
			["outline"]		= outline,
			["scale_x"]		= scale_x,
			["scale_y"]		= scale_y,
			["margin_l"]	= margin_l_styles,
			["margin_r"]	= margin_r_styles,
			["margin_t"]	= margin_t_styles,
			["margin_b"]	= margin_b_styles,
		},
		["[Events]"] = {
			["margin_l"]	= margin_l_events,
			["margin_r"]	= margin_r_events,
			["margin_t"]	= margin_t_events,
			["margin_b"]	= margin_b_events,
			["text"]		= text,
			["Aegisub's Advanced SSA codes"] = {
				["\\bord"]	= bord,
				["\\shad"]	= shad,
				
				["\\fscx"]	= fscx,
				["\\fscy"]	= fscy,
				["\\xbord"]	= xbord,
				["\\ybord"]	= ybord,
				["\\xshad"]	= xshad,
				["\\yshad"]	= yshad,
				["\\pbo"]	= pbo,
				["\\blur"]	= blur,
				
				["\\org"]	= org,
				["\\pos"]	= pos,
				["\\move"]	= move,
				
				["\\clip"]	= clip,
				["\\iclip"]	= iclip,
			},
		},
	},
}


function macro(lines, trafo)
	-- dbg = io.open("auto4-debug.log", "w")
	-- dbg:write("dbg opened for logging\n")
	current_trafo_type = trafo.trafo_type
	local btn, cfg
	repeat
		btn, cfg = aegisub.dialog.display(trafo.gui, trafo.btn)
	until true
	if btn ~= "&Cancel" then
		if intervals_of_sections == nil then
			intervals_of_sections = calculate_intervals_of_sections(lines)
		else
			if cfg.update_cached_intervals_of_sections then
				intervals_of_sections = calculate_intervals_of_sections(lines)
			end
		end
		local operator
		if current_trafo_type == "resize_canvas" then
			operator = shift_point
		elseif current_trafo_type == "shift_absolute_layout" then
			operator = shift_point
		elseif current_trafo_type == "shift_relative_layout" then
			operator = shift_point
		elseif current_trafo_type == "scale_subtitles" then
			operator = scale_point
		end
		-- every subtitle consists of 1) sections, 2) lines, 3) attributes. after that there is almost no similarities, so further processing is passed down the road to respectful funcs: dialogues > margins | text | ..., text > blocks of codes | text | drawings, script info > key | value, ...
		for section_name, supported_atts in pairs(registry[current_trafo_type]) do
			for i = intervals_of_sections[section_name]["start"], intervals_of_sections[section_name]["end"] do
				for attr_name, attr_value in pairs(lines[i]) do
					if supported_atts[attr_name] then
						line = lines[i]
						line[attr_name] = supported_atts[attr_name].process(attr_value, operator, cfg) -- operand "A", operator, operand "B"
						lines[i] = line
					end
				end
			end
		end
	end
	-- dbg:write("dbg closed")
	-- dbg:close()
end


resize_canvas.gui = {
	{
		class = "label",
		x = 0, y = 0, width = 1, height = 1,
		label = "Width:",
	},
	{
		class = "intedit",
		x = 1, y = 0, width = 1, height = 1, text = 0,
		name = "x",
	},
	{
		class = "label",
		x = 0, y = 1, width = 1, height = 1,
		label = "Height:",
	},
	{
		class = "intedit",
		x = 1, y = 1, width = 1, height = 1, text = 0,
		name = "y",
	},
	{
		class = "checkbox",
		x = 0, y = 2, width = 2, height = 1,
		name = "update_cached_intervals_of_sections",
		label = "File structure was modified since the last run",
		value = true,
		hint = "Caching of intervals of SSA sections for faster processing of huge files",
	},
}
resize_canvas.btn = {"&Resize canvas", "&Cancel"}


shift_absolute_layout.gui = {
	{
		class = "label",
		x = 0, y = 0, width = 1, height = 1,
		label = "X axes:",
	},
	{
		class = "intedit",
		x = 1, y = 0, width = 1, height = 1, text = 0,
		name = "x",
	},
	{
		class = "label",
		x = 0, y = 1, width = 1, height = 1,
		label = "Y axes:",
	},
	{
		class = "intedit",
		x = 1, y = 1, width = 1, height = 1, text = 0,
		name = "y",
	},
	{
		class = "checkbox",
		x = 0, y = 2, width = 2, height = 1,
		name = "update_cached_intervals_of_sections",
		label = "File structure was modified since the last run",
		value = true,
		hint = "Caching of intervals of SSA sections for faster processing of huge files",
	},
}
shift_absolute_layout.btn = {"&Shift absolute layout", "&Cancel"}


shift_relative_layout.gui = {
	{
		class = "label",
		x = 0, y = 0, width = 1, height = 1,
		label = "Left margin:",
	},
	{
		class = "intedit",
		x = 1, y = 0, width = 1, height = 1, text = 0,
		name = "margin_l",
	},
	{
		class = "label",
		x = 0, y = 1, width = 1, height = 1,
		label = "Vertical margin:",
	},
	{
		class = "intedit",
		x = 1, y = 1, width = 1, height = 1, text = 0,
		name = "margin_v",
	},
	{
		class = "label",
		x = 0, y = 2, width = 1, height = 1,
		label = "Right margin:",
	},
	{
		class = "intedit",
		x = 1, y = 2, width = 1, height = 1, text = 0,
		name = "margin_r",
	},
	{
		class = "checkbox",
		x = 0, y = 3, width = 2, height = 1,
		name = "update_cached_intervals_of_sections",
		label = "File structure was modified since the last run",
		value = true,
		hint = "Caching of intervals of SSA sections for faster processing of huge files",
	},
}
shift_relative_layout.btn = {"&Shift relative layout", "&Cancel"}


scale_subtitles.gui = {
	-- option to restrain scaling to: 1. x axes; 2. y axes; 3. x and y axes: whichever is bigger; 4. x and y axes: whichever is smaller;
	{
		class = "label",
		x = 0, y = 0, width = 1, height = 1,
		label = "X axes:",
	},
	{
		class = "floatedit",
		x = 1, y = 0, width = 1, height = 1, text = 0,
		name = "x",
		hint = "Scaling factor",
	},
	{
		class = "label",
		x = 0, y = 1, width = 1, height = 1,
		label = "Y axes:",
	},
	{
		class = "floatedit",
		x = 1, y = 1, width = 1, height = 1, text = 0,
		name = "y",
		hint = "Scaling factor",
	},
	{
		class = "label",
		x = 0, y = 2, width = 1, height = 1,
		label = "Uni-axes atts:",
	},
	{
		class = "dropdown",
		x = 1, y = 2, width = 1, height = 1,
		name = "type_of_scaling_for_codes_with_one_axes",
		items = {"X axes", "Y axes", "X and Y axes: whichever is bigger", "X and Y axes: whichever is smaller"},
		value = "X and Y axes: whichever is bigger",
		hint = "Axes from which scaling factor will be used for codes like \\bord, i.e. for those that cannot be scaled unproportionally",
	},
	{
		class = "checkbox",
		x = 0, y = 3, width = 2, height = 1,
		name = "update_cached_intervals_of_sections",
		label = "File structure was modified since the last run",
		value = true,
		hint = "Caching of intervals of SSA sections for faster processing of huge files",
	},
}
scale_subtitles.btn = {"&Scale subtitles", "&Cancel"}


function resize_canvas.macro(lines)
	if macro(lines, resize_canvas) then aegisub.set_undo_point("\"" .. resize_canvas.script_name .. "\"") end
end


function shift_absolute_layout.macro(lines)
	if macro(lines, shift_absolute_layout) then aegisub.set_undo_point("\"" .. shift_absolute_layout.script_name .. "\"") end
end


function shift_relative_layout.macro(lines)
	if macro(lines, shift_relative_layout) then aegisub.set_undo_point("\"" .. shift_relative_layout.script_name .. "\"") end
end


function scale_subtitles.macro(lines)
	if macro(lines, scale_subtitles) then aegisub.set_undo_point("\"" .. scale_subtitles.script_name .. "\"") end
end


aegisub.register_macro(	resize_canvas.script_name,			resize_canvas.script_description,			resize_canvas.macro			)
aegisub.register_macro(	shift_absolute_layout.script_name,	shift_absolute_layout.script_description,	shift_absolute_layout.macro	)
aegisub.register_macro(	shift_relative_layout.script_name,	shift_relative_layout.script_description,	shift_relative_layout.macro	)
aegisub.register_macro(	scale_subtitles.script_name,		scale_subtitles.script_description,			scale_subtitles.macro		)
