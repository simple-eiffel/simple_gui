note
	description: "[
		A style (1w): a set of optional properties a widget can show, such as its text
		color, font, padding and border. Each property starts unset, and an unset property
		leaves the native default. A style is given to one widget (GUI_WIDGET.set_own_style) or
		named as a class for many (GUI_APPLICATION.define_style_class).

		Colors are 0xRRGGBB. Each may have a dark variant, used in the dark appearance; the
		foreground and background may instead name a theme role (GUI_APPLICATION's
		Color_text...), and then follow the theme. Setting a color anew drops its dark
		variant and its role.
	]"

class
	GUI_STYLE

inherit
	GUI_STYLE_PROPERTIES
		redefine
			copy, is_equal
		end

create
	make

feature {NONE} -- Initialization

	make
			-- A style with nothing set.
		do
			create flags.make_filled (False, 1, Property_count)
			create lights.make_filled (0, 1, Color_slots)
			create darks.make_filled (0, 1, Color_slots)
			create roles.make_filled (0, 1, Color_slots)
			create font_family.make_empty
		ensure
			nothing_set: is_empty
		end

feature -- Status

	is_set (a_property: INTEGER): BOOLEAN
			-- Does this style say anything about `a_property' (`Foreground', `Padding'...)?
		require
			known: is_style_property (a_property)
		do
			Result := flags [a_property]
		end

	is_empty: BOOLEAN
			-- Is nothing set?
		do
			Result := not flags.has (True)
		ensure
			definition: Result = across 1 |..| Property_count as ic all not is_set (ic) end
		end

feature -- Colors

	foreground: NATURAL_32
			-- The text (or tint) color in the light appearance.
		do
			Result := lights [Foreground]
		end

	foreground_dark: NATURAL_32
			-- The text color in the dark appearance (`foreground' when no variant is set).
		do
			Result := darks [Foreground]
		end

	foreground_role: INTEGER
			-- The theme role the text color follows; 0: a fixed color.
		do
			Result := roles [Foreground]
		end

	background: NATURAL_32
		do
			Result := lights [Background]
		end

	background_dark: NATURAL_32
		do
			Result := darks [Background]
		end

	background_role: INTEGER
		do
			Result := roles [Background]
		end

	placeholder_color: NATURAL_32
		do
			Result := lights [Placeholder_color]
		end

	placeholder_color_dark: NATURAL_32
		do
			Result := darks [Placeholder_color]
		end

	selection_color: NATURAL_32
		do
			Result := lights [Selection_color]
		end

	selection_color_dark: NATURAL_32
		do
			Result := darks [Selection_color]
		end

	set_foreground (a_rgb: NATURAL_32)
		require
			rgb: is_rgb (a_rgb)
		do
			put_color (Foreground, a_rgb)
			flags [Foreground] := True
		ensure
			set: is_set (Foreground) and foreground = a_rgb
			one_color: foreground_dark = a_rgb and foreground_role = 0
		end

	set_foreground_dark (a_rgb: NATURAL_32)
			-- Use `a_rgb' for the text in the dark appearance.
		require
			rgb: is_rgb (a_rgb)
			has_light: is_set (Foreground) and foreground_role = 0
		do
			darks [Foreground] := a_rgb
		ensure
			set: foreground_dark = a_rgb
			light_kept: foreground = old foreground
		end

	set_foreground_role (a_role: INTEGER)
			-- Let the text color follow theme role `a_role' (GUI_APPLICATION's `Color_text'...).
		require
			known: is_theme_role (a_role)
		do
			put_color (Foreground, 0)
			roles [Foreground] := a_role
			flags [Foreground] := True
		ensure
			set: is_set (Foreground) and foreground_role = a_role
		end

	set_background (a_rgb: NATURAL_32)
		require
			rgb: is_rgb (a_rgb)
		do
			put_color (Background, a_rgb)
			flags [Background] := True
		ensure
			set: is_set (Background) and background = a_rgb
			one_color: background_dark = a_rgb and background_role = 0
		end

	set_background_dark (a_rgb: NATURAL_32)
		require
			rgb: is_rgb (a_rgb)
			has_light: is_set (Background) and background_role = 0
		do
			darks [Background] := a_rgb
		ensure
			set: background_dark = a_rgb
			light_kept: background = old background
		end

	set_background_role (a_role: INTEGER)
		require
			known: is_theme_role (a_role)
		do
			put_color (Background, 0)
			roles [Background] := a_role
			flags [Background] := True
		ensure
			set: is_set (Background) and background_role = a_role
		end

	set_placeholder_color (a_rgb: NATURAL_32)
			-- The color of a field's placeholder text.
		require
			rgb: is_rgb (a_rgb)
		do
			put_color (Placeholder_color, a_rgb)
			flags [Placeholder_color] := True
		ensure
			set: is_set (Placeholder_color) and placeholder_color = a_rgb
		end

	set_placeholder_color_dark (a_rgb: NATURAL_32)
		require
			rgb: is_rgb (a_rgb)
			has_light: is_set (Placeholder_color)
		do
			darks [Placeholder_color] := a_rgb
		ensure
			set: placeholder_color_dark = a_rgb
		end

	set_selection_color (a_rgb: NATURAL_32)
			-- The color behind selected text, and behind the selected rows of lists, tables
			-- and trees.
		require
			rgb: is_rgb (a_rgb)
		do
			put_color (Selection_color, a_rgb)
			flags [Selection_color] := True
		ensure
			set: is_set (Selection_color) and selection_color = a_rgb
		end

	set_selection_color_dark (a_rgb: NATURAL_32)
		require
			rgb: is_rgb (a_rgb)
			has_light: is_set (Selection_color)
		do
			darks [Selection_color] := a_rgb
		ensure
			set: selection_color_dark = a_rgb
		end

feature -- Font

	font_family: STRING_32
			-- A family's name, or "monospace", "serif", "sans-serif" or "system" for the
			-- platform's own.

	font_size: REAL_64
			-- Points.

	font_weight: INTEGER
			-- 100 to 900: 400 regular, 700 bold.

	is_italic: BOOLEAN

	set_font_family (a_name: READABLE_STRING_GENERAL)
		require
			named: not a_name.is_empty
			one_family: not a_name.has (',') and not a_name.has ('=')
		do
			font_family := a_name.to_string_32
			flags [Font_family] := True
		ensure
			set: is_set (Font_family) and font_family.same_string_general (a_name)
		end

	set_font_size (a_points: REAL_64)
		require
			positive: a_points > 0
		do
			font_size := a_points
			flags [Font_size] := True
		ensure
			set: is_set (Font_size) and font_size = a_points
		end

	set_font_weight (a_weight: INTEGER)
		require
			in_range: a_weight >= 100 and a_weight <= 900
		do
			font_weight := a_weight
			flags [Font_weight] := True
		ensure
			set: is_set (Font_weight) and font_weight = a_weight
		end

	set_italic (a_on: BOOLEAN)
		do
			is_italic := a_on
			flags [Italic] := True
		ensure
			set: is_set (Italic) and is_italic = a_on
		end

	set_font (a_font: GUI_FONT_CHOICE)
			-- The family, size, weight and slant of `a_font', as a font dialog gives it.
		do
			if not a_font.family.is_empty and not a_font.family.has (',') and not a_font.family.has ('=') then
				set_font_family (a_font.family)
			end
			set_font_size (a_font.size)
			if a_font.is_bold then
				set_font_weight (700)
			else
				set_font_weight (400)
			end
			set_italic (a_font.is_italic)
		ensure
			size_set: is_set (Font_size) and font_size = a_font.size
			weight_set: is_set (Font_weight) and (font_weight = 700) = a_font.is_bold
			italic_set: is_set (Italic) and is_italic = a_font.is_italic
		end

feature -- Box

	padding_top, padding_end, padding_bottom, padding_start: INTEGER
			-- The room inside the border, in points. The start and end sides follow the text
			-- direction.

	border_width: INTEGER

	border_color: NATURAL_32
		do
			Result := lights [Border_slot]
		end

	border_color_dark: NATURAL_32
		do
			Result := darks [Border_slot]
		end

	corner_radius: INTEGER

	shadow_x, shadow_y, shadow_blur: INTEGER
			-- The shadow's offset (`shadow_y' grows downward) and blur, in points.

	shadow_color: NATURAL_32
		do
			Result := lights [Shadow_slot]
		end

	shadow_color_dark: NATURAL_32
		do
			Result := darks [Shadow_slot]
		end

	shadow_alpha: INTEGER
			-- How solid the shadow is, in percent.

	set_padding (a_top, an_end, a_bottom, a_start: INTEGER)
		require
			non_negative: a_top >= 0 and an_end >= 0 and a_bottom >= 0 and a_start >= 0
		do
			padding_top := a_top
			padding_end := an_end
			padding_bottom := a_bottom
			padding_start := a_start
			flags [Padding] := True
		ensure
			set: is_set (Padding)
			sides: padding_top = a_top and padding_end = an_end and padding_bottom = a_bottom and padding_start = a_start
		end

	set_padding_all (a_points: INTEGER)
		require
			non_negative: a_points >= 0
		do
			set_padding (a_points, a_points, a_points, a_points)
		ensure
			set: is_set (Padding)
			sides: padding_top = a_points and padding_end = a_points and padding_bottom = a_points and padding_start = a_points
		end

	set_border (a_width: INTEGER; a_rgb: NATURAL_32)
		require
			non_negative: a_width >= 0
			rgb: is_rgb (a_rgb)
		do
			border_width := a_width
			put_color (Border_slot, a_rgb)
			flags [Border] := True
		ensure
			set: is_set (Border) and border_width = a_width and border_color = a_rgb
		end

	set_border_dark (a_rgb: NATURAL_32)
			-- Use `a_rgb' for the border in the dark appearance.
		require
			rgb: is_rgb (a_rgb)
			has_light: is_set (Border)
		do
			darks [Border_slot] := a_rgb
		ensure
			set: border_color_dark = a_rgb
		end

	set_corner_radius (a_points: INTEGER)
		require
			non_negative: a_points >= 0
		do
			corner_radius := a_points
			flags [Corner_radius] := True
		ensure
			set: is_set (Corner_radius) and corner_radius = a_points
		end

	set_shadow (a_x, a_y, a_blur: INTEGER; a_rgb: NATURAL_32; an_alpha: INTEGER)
			-- A shadow moved by (`a_x', `a_y'), blurred over `a_blur' points, in color `a_rgb',
			-- `an_alpha' percent solid.
		require
			blur_non_negative: a_blur >= 0
			rgb: is_rgb (a_rgb)
			percent: an_alpha >= 0 and an_alpha <= 100
		do
			shadow_x := a_x
			shadow_y := a_y
			shadow_blur := a_blur
			shadow_alpha := an_alpha
			put_color (Shadow_slot, a_rgb)
			flags [Shadow] := True
		ensure
			set: is_set (Shadow) and shadow_color = a_rgb and shadow_alpha = an_alpha
			placed: shadow_x = a_x and shadow_y = a_y and shadow_blur = a_blur
		end

	set_shadow_dark (a_rgb: NATURAL_32)
			-- Use `a_rgb' for the shadow in the dark appearance.
		require
			rgb: is_rgb (a_rgb)
			has_light: is_set (Shadow)
		do
			darks [Shadow_slot] := a_rgb
		ensure
			set: shadow_color_dark = a_rgb
		end

feature -- Scroll bars

	scroll_bars: INTEGER
			-- `Scroll_bars_system', `Scroll_bars_overlay', `Scroll_bars_always' or
			-- `Scroll_bars_hidden'.

	set_scroll_bars (a_kind: INTEGER)
		require
			known: is_scroll_bar_kind (a_kind)
		do
			scroll_bars := a_kind
			flags [Scroll_bars] := True
		ensure
			set: is_set (Scroll_bars) and scroll_bars = a_kind
		end

feature -- Element change

	unset (a_property: INTEGER)
			-- Say nothing about `a_property' any more: the native default, or what a class says.
		require
			known: is_style_property (a_property)
		do
			flags [a_property] := False
		ensure
			unset: not is_set (a_property)
		end

	take (other: GUI_STYLE; a_property: INTEGER)
			-- Make `a_property' here what it is in `other', set or not.
		require
			known: is_style_property (a_property)
		do
			flags [a_property] := other.is_set (a_property)
			inspect a_property
			when Foreground, Background, Placeholder_color, Selection_color then
				take_color (other, a_property)
			when Font_family then
				font_family := other.font_family.twin
			when Font_size then
				font_size := other.font_size
			when Font_weight then
				font_weight := other.font_weight
			when Italic then
				is_italic := other.is_italic
			when Padding then
				padding_top := other.padding_top
				padding_end := other.padding_end
				padding_bottom := other.padding_bottom
				padding_start := other.padding_start
			when Border then
				border_width := other.border_width
				take_color (other, Border_slot)
			when Corner_radius then
				corner_radius := other.corner_radius
			when Shadow then
				shadow_x := other.shadow_x
				shadow_y := other.shadow_y
				shadow_blur := other.shadow_blur
				shadow_alpha := other.shadow_alpha
				take_color (other, Shadow_slot)
			else
				scroll_bars := other.scroll_bars
			end
		ensure
			same: same_property (other, a_property)
		end

feature -- Combination

	merged (other: GUI_STYLE): GUI_STYLE
			-- This style with `other' over it: what `other' sets wins, property by property.
		do
			Result := twin
			across 1 |..| Property_count as ic loop
				if other.is_set (ic) then
					Result.take (other, ic)
				end
			end
		ensure
			others_win: across 1 |..| Property_count as ic all other.is_set (ic) implies Result.same_property (other, ic) end
			mine_kept: across 1 |..| Property_count as ic all (not other.is_set (ic)) implies Result.same_property (Current, ic) end
		end

feature -- Comparison

	same_property (other: GUI_STYLE; a_property: INTEGER): BOOLEAN
			-- Is `a_property' the same here and in `other': unset in both, or set to equal values?
		require
			known: is_style_property (a_property)
		do
			if is_set (a_property) /= other.is_set (a_property) then
				Result := False
			elseif not is_set (a_property) then
				Result := True
			else
				inspect a_property
				when Foreground, Background, Placeholder_color, Selection_color then
					Result := same_color (other, a_property)
				when Font_family then
					Result := font_family.same_string (other.font_family)
				when Font_size then
					Result := font_size = other.font_size
				when Font_weight then
					Result := font_weight = other.font_weight
				when Italic then
					Result := is_italic = other.is_italic
				when Padding then
					Result := padding_top = other.padding_top and padding_end = other.padding_end
						and padding_bottom = other.padding_bottom and padding_start = other.padding_start
				when Border then
					Result := border_width = other.border_width and same_color (other, Border_slot)
				when Corner_radius then
					Result := corner_radius = other.corner_radius
				when Shadow then
					Result := shadow_x = other.shadow_x and shadow_y = other.shadow_y and shadow_blur = other.shadow_blur
						and shadow_alpha = other.shadow_alpha and same_color (other, Shadow_slot)
				else
					Result := scroll_bars = other.scroll_bars
				end
			end
		end

	is_equal (other: like Current): BOOLEAN
			-- Do both styles set the same properties to the same values?
		do
			Result := across 1 |..| Property_count as ic all same_property (other, ic) end
		end

feature -- Duplication

	copy (other: like Current)
		do
			standard_copy (other)
			flags := other.flags.twin
			lights := other.lights.twin
			darks := other.darks.twin
			roles := other.roles.twin
			font_family := other.font_family.twin
		end

feature -- Accessibility

	contrast_ratio (a_foreground, a_background: NATURAL_32): REAL_64
			-- The WCAG 2 contrast ratio of two colors: 1 (the same) to 21 (black on white).
			-- Body text wants 4.5 or more.
		require
			rgb: is_rgb (a_foreground) and is_rgb (a_background)
		local
			l_a, l_b: REAL_64
		do
			l_a := luminance (a_foreground)
			l_b := luminance (a_background)
			if l_a >= l_b then
				Result := (l_a + 0.05) / (l_b + 0.05)
			else
				Result := (l_b + 0.05) / (l_a + 0.05)
			end
		ensure
			in_range: Result >= 1.0 and Result < 21.001
			symmetric: (Result - contrast_ratio (a_background, a_foreground)).abs < 0.000001
		end

feature -- For the backend

	flat (a_dark, a_with_colors: BOOLEAN; a_role_color: detachable FUNCTION [INTEGER, NATURAL_32]): STRING_32
			-- This style as the backend takes it: `key=value' pairs separated by 0x1F, with each
			-- color resolved for the light or the dark appearance and each role through
			-- `a_role_color'. Without `a_with_colors' (the system's contrast setting is on), the
			-- colors, backgrounds and shadows are left out; fonts, padding and borders stay.
		do
			create Result.make (64)
			if a_with_colors then
				if is_set (Foreground) then
					add (Result, "fg", hex (color (Foreground, a_dark, a_role_color)))
				end
				if is_set (Background) then
					add (Result, "bg", hex (color (Background, a_dark, a_role_color)))
				end
				if is_set (Placeholder_color) then
					add (Result, "placeholder", hex (color (Placeholder_color, a_dark, Void)))
				end
				if is_set (Selection_color) then
					add (Result, "selection", hex (color (Selection_color, a_dark, Void)))
				end
			end
			if is_set (Font_family) then
				add (Result, "font", font_family)
			end
			if is_set (Font_size) then
				add (Result, "size", number (font_size))
			end
			if is_set (Font_weight) then
				add (Result, "weight", font_weight.out)
			end
			if is_set (Italic) then
				add (Result, "italic", if is_italic then "1" else "0" end)
			end
			if is_set (Padding) then
				add (Result, "pad", padding_top.out + "," + padding_end.out + "," + padding_bottom.out + "," + padding_start.out)
			end
			if is_set (Border) then
				add (Result, "border", border_width.out)
				if a_with_colors then
					add (Result, "border_color", hex (color (Border_slot, a_dark, Void)))
				end
			end
			if is_set (Corner_radius) then
				add (Result, "radius", corner_radius.out)
			end
			if is_set (Shadow) and a_with_colors then
				add (Result, "shadow", shadow_x.out + "," + shadow_y.out + "," + shadow_blur.out + "," + shadow_alpha.out)
				add (Result, "shadow_color", hex (color (Shadow_slot, a_dark, Void)))
			end
			if is_set (Scroll_bars) then
				add (Result, "scroll", scroll_bars.out)
			end
		ensure
			empty_for_empty: is_empty implies Result.is_empty
		end

	color (a_slot: INTEGER; a_dark: BOOLEAN; a_role_color: detachable FUNCTION [INTEGER, NATURAL_32]): NATURAL_32
			-- The color in `a_slot' for the light or the dark appearance, its role resolved
			-- through `a_role_color' (without one, a role gives black).
		require
			slot: a_slot >= 1 and a_slot <= Color_slots
		do
			if roles [a_slot] /= 0 then
				if attached a_role_color as al_f then
					Result := al_f.item ([roles [a_slot]])
				end
			elseif a_dark then
				Result := darks [a_slot]
			else
				Result := lights [a_slot]
			end
		end

	Border_slot: INTEGER = 5
	Shadow_slot: INTEGER = 6
			-- Where the border's and the shadow's colors are kept; the other colors are kept
			-- under their property's number.

	Color_slots: INTEGER = 6

	is_theme_role (a_role: INTEGER): BOOLEAN
			-- Is `a_role' one of GUI_APPLICATION's theme roles (1 window background .. 6 separator)?
		do
			Result := a_role >= 1 and a_role <= 6
		end

feature {GUI_STYLE} -- Implementation

	flags: ARRAY [BOOLEAN]
			-- Which properties are set.

	lights, darks: ARRAY [NATURAL_32]
			-- Each color slot's light and dark values (the same when no dark variant is set).

	roles: ARRAY [INTEGER]
			-- Each color slot's theme role; 0: a fixed color.

feature {NONE} -- Implementation

	put_color (a_slot: INTEGER; a_rgb: NATURAL_32)
			-- One fixed color in `a_slot', for light and dark.
		do
			lights [a_slot] := a_rgb
			darks [a_slot] := a_rgb
			roles [a_slot] := 0
		end

	take_color (other: GUI_STYLE; a_slot: INTEGER)
		do
			lights [a_slot] := other.lights [a_slot]
			darks [a_slot] := other.darks [a_slot]
			roles [a_slot] := other.roles [a_slot]
		end

	same_color (other: GUI_STYLE; a_slot: INTEGER): BOOLEAN
		do
			Result := lights [a_slot] = other.lights [a_slot] and darks [a_slot] = other.darks [a_slot]
				and roles [a_slot] = other.roles [a_slot]
		end

	add (a_flat: STRING_32; a_key: STRING; a_value: READABLE_STRING_GENERAL)
			-- Add `a_key'=`a_value' to `a_flat'.
		do
			if not a_flat.is_empty then
				a_flat.append_character ('%/31/')
			end
			a_flat.append_string_general (a_key)
			a_flat.append_character ('=')
			a_flat.append_string_general (a_value)
		end

	hex (a_rgb: NATURAL_32): STRING
			-- `a_rgb' as six lowercase hexadecimal digits.
		do
			Result := a_rgb.to_hex_string
			Result.keep_tail (6)
			Result.to_lower
		ensure
			six: Result.count = 6
		end

	number (a_value: REAL_64): STRING
			-- `a_value' with at most two decimals, and none when it is whole.
		local
			l_hundredths: INTEGER
		do
			l_hundredths := (a_value * 100).rounded
			Result := (l_hundredths // 100).out
			if l_hundredths \\ 100 /= 0 then
				Result.append_character ('.')
				if l_hundredths \\ 100 < 10 then
					Result.append_character ('0')
				end
				Result.append_integer (l_hundredths \\ 100)
				if Result.item (Result.count) = '0' then
					Result.remove_tail (1)
				end
			end
		end

	luminance (a_rgb: NATURAL_32): REAL_64
			-- WCAG 2's relative luminance of `a_rgb': 0 black, 1 white.
		do
			Result := 0.2126 * linear ((a_rgb |>> 16) & 0xFF) + 0.7152 * linear ((a_rgb |>> 8) & 0xFF) + 0.0722 * linear (a_rgb & 0xFF)
		end

	linear (a_channel: NATURAL_32): REAL_64
			-- An sRGB channel (0 to 255) as linear light (0 to 1).
		local
			l_c: REAL_64
		do
			l_c := a_channel.to_real_64 / 255.0
			if l_c <= 0.03928 then
				Result := l_c / 12.92
			else
				Result := ((l_c + 0.055) / 1.055) ^ 2.4
			end
		end

invariant
	flags_sized: flags.lower = 1 and flags.upper = Property_count
	colors_sized: lights.count = Color_slots and darks.count = Color_slots and roles.count = Color_slots
	weight_in_range: is_set (Font_weight) implies (font_weight >= 100 and font_weight <= 900)
	size_positive: is_set (Font_size) implies font_size > 0
	scroll_bars_known: is_scroll_bar_kind (scroll_bars)

end
