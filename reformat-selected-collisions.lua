--[[
Description
	Auto4 script written in Lua for subtitle editor Aegisub.
	Purpose is stated in the "script_description" variable. If you wonder why all the hassle with alignment etc., then the answer for you is this: because this way subs look more professional, as well as easier to read, at least for those accustomed to this kind of layout.
]]--


include("karaskel.lua")


script_name = "Reformat selected collisions"
script_description = "Reformats selected collisions by joining two selected subs \nand aligning them in a special way: by the left side inside bounding box, \nand their bounding box by the center of the video (script resolution)"
script_author = "8day"
script_version = "1.1.1"
script_modified = "27.12.2013"


-- GUI config.
function create_config()
	return {
		-- Checkboxes.
		{
			class = "checkbox", name = "right_to_left",
			label = "Right-to-left &writing style",
			x = 0, y = 0, width = 2, height = 1,
			value = false
		},
		{
			class = "checkbox", name = "differentiate_styles",
			label = "&Differentiate styles",
			x = 0, y = 1, width = 2, height = 1,
			value = true
		},
		-- Text to be added to the beginning of subtitles.
		{
			class = "label",
			x = 0, y = 2, width = 2, height = 1,
			label = "&Beginning of the 1-st and 2-nd subs:"
		},
		{
			class = "edit", name = "sub1beg",
			x = 0, y = 3, width = 1, height = 1,
			hint = "Text to be added to the beginning of the first subtitle", text = "— "
		},
		{
			class = "edit", name = "sub2beg",
			x = 1, y = 3, width = 1, height = 1,
			hint = "Text to be added to the beginning of the second subtitle", text = "— "
		},
		-- Text to be added to the end of subtitles.
		{
			class = "label",
			x = 0, y = 4, width = 2, height = 1,
			label = "&End of the 1-st and 2-nd subs:"
		},
		{
			class = "edit", name = "sub1fin",
			x = 0, y = 5, width = 1, height = 1,
			hint = "Text to be added to the end of the first subtitle", text = ""
		},
		{
			class = "edit", name = "sub2fin",
			x = 1, y = 5, width = 1, height = 1,
			hint = "Text to be added to the end of the second subtitle", text = ""
		},
	}
end


-- Checks whether specified object is inside table (here -- data).
function object_is_inside(data, object)
	for i = 1, #data do
		if data[object] then return true end
	end
	return false
end


-- Searches idx of the final "Style"-descriptor line in "[V4+ Styles]".
function last_style_idx(subs)
	local last_line, last_style_line
	for i = 1, #subs do
		last_line = i
		if subs[i].class == "head" and subs[i].section == "[V4+ Styles]" then
			-- Implicitly assumes that there is at least one style definition.
			for j = last_line + 1, #subs do
				if subs[j].class == "style" then last_style_line = j end
			end
			break
		end
	end
	return last_style_line
end


-- Main abracadabra.
function process(subs, sel, config)
	-- Initialize vars for the l-to-r system of writing.
	local sub1beg, sub2beg, sub1fin, sub2fin
	local an, margin
	sub1beg, sub2beg = config.sub1beg, config.sub2beg
	sub1fin, sub2fin = config.sub1fin, config.sub2fin
	an = {top = {beg=7, center=8, fin=9},
		  mid = {beg=4, center=5, fin=6},
		  bot = {beg=1, center=2, fin=3}}
	margin = "margin_l"
	-- If chosen in GUI, reconfig settings to r-to-l system of writing.
	if config.right_to_left then
		-- Doesn't need reversing of characters because r-to-l users
		-- will take this into account: they'll specify them in the correct order.
		local temp1, temp2
		temp1, temp2 = sub1beg, sub2beg
		sub1beg, sub2beg = sub1fin, sub2fin
		sub1fin, sub2fin = temp1, temp2
		for k, v in pairs(an) do
			an[k].beg, an[k].fin = an[k].fin, an[k].beg
		end
		margin = "margin_r"
	end
	-- Get the width of subs and script. Also get access to styles.
	local meta, styles
	local fst, snd
	local fst_width, snd_width, script_width, widest_sub_width
	meta, styles = karaskel.collect_head(subs, false)
	fst, snd = subs[sel[1]], subs[sel[2]]
	karaskel.preproc_line_text(meta, styles, fst)
	karaskel.preproc_line_text(meta, styles, snd)
	fst_width = aegisub.text_extents(styles[fst.style], sub1beg .. fst.text_stripped .. sub1fin)
	snd_width = aegisub.text_extents(styles[snd.style], sub2beg .. snd.text_stripped .. sub2fin)
	script_width = meta.res_x
	-- Check whether text width is not exceeding script width.
	if fst_width >= script_width or snd_width >= script_width then
		aegisub.progress.title("Error")
		aegisub.debug.out(string.format("Either width of selected subtitles is too big or " ..
		"width of the script is too small (i.e. not set at all).\nScript width (PlayResX): %d;\n" ..
		"First subtitle width: %f;\nSecond subtitle width: %f.", script_width, fst_width, snd_width))
		return false
	else
		if fst_width > snd_width then
			widest_sub_width = fst_width
		else
			widest_sub_width = snd_width
		end
	end
	-- Create collision style.
	-- Since joining of already joined subs is meaningless,
	-- check for "style_name.collision(.collision)+" is absent.
	local lines_shifting = 0
	if not object_is_inside(styles, fst.style .. ".collision") then
		local style
		style = table.copy_deep(styles[fst.style])
		style.name = style.name .. ".collision"
		for k, v in pairs(an) do
			for m, n in pairs(v) do
				if style.align == an[k][m] then
					style.align = an[k].beg
					break
				end
			end
		end
		style.margin_l = 0
		style.margin_r = 0
		subs.insert(last_style_idx(subs) + 1, style)
		-- Addition of new styles shifts subs idxs!
		-- BTW, ATM "lines_shifting + 1" is somewhat stupid, but
		-- later on when I'll write automated collision detection (hopefully),
		-- it'll help to avoid this bug right from the beginning.
		lines_shifting = lines_shifting + 1
	end
	-- Join subs.
	if config.differentiate_styles and (fst.style ~= snd.style) then
		fst.text = string.format("%s%s%s\\N{\\r%s}%s%s%s", sub1beg, fst.text, sub1fin, snd.style, sub2beg, snd.text, sub2fin)
	else
		fst.text = string.format("%s%s%s\\N%s%s%s", sub1beg, fst.text, sub1fin, sub2beg, snd.text, sub2fin)
	end
	-- Do some final job.
	fst[margin] = math.floor((script_width - widest_sub_width) / 2)
	fst.style = fst.style .. ".collision"
	if fst.end_time < snd.end_time then fst.end_time = snd.end_time end
	subs[sel[1] + lines_shifting] = fst
	subs.delete(sel[2] + lines_shifting)
	return true
end


-- Main.
function macro(subs, sel)
	-- Check whether at least two lines were selected.
	if #sel ~= 2 then
		aegisub.progress.title("Error")
		aegisub.debug.out(string.format("You should choose exactly two subtitles, not %d!", #sel))
		return false
	else
		local button, config
		repeat
			button, config = aegisub.dialog.display(create_config(), {"&Process", "&Cancel"})
		until true
		if button == "&Process" then
			if process(subs, sel, config) then aegisub.set_undo_point("\"" .. script_name .. "\"") end
		end
	end
end


aegisub.register_macro(script_name, script_description, macro)
