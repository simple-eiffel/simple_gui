note
	description: "[
		The names of a GUI_STYLE's properties (1w), for `is_set', `unset' and
		GUI_WIDGET.supports_style, and the key each one has in the flat style a backend
		is given.
	]"

class
	GUI_STYLE_PROPERTIES

feature -- Properties

	Property_foreground: INTEGER = 1
			-- The text (or tint) color.
	Property_background: INTEGER = 2
	Property_placeholder_color: INTEGER = 3
			-- A field's placeholder text.
	Property_selection_color: INTEGER = 4
			-- The text selection, and the selected rows of lists, tables and trees.
	Property_font_family: INTEGER = 5
	Property_font_size: INTEGER = 6
	Property_font_weight: INTEGER = 7
	Property_italic: INTEGER = 8
	Property_padding: INTEGER = 9
	Property_border: INTEGER = 10
			-- The border's width and color.
	Property_corner_radius: INTEGER = 11
	Property_shadow: INTEGER = 12
	Property_scroll_bars: INTEGER = 13

	Property_count: INTEGER = 13

feature -- Scroll bar kinds

	Scroll_bars_system: INTEGER = 0
			-- The system's choice.
	Scroll_bars_overlay: INTEGER = 1
			-- Shown while scrolling, over the content.
	Scroll_bars_always: INTEGER = 2
	Scroll_bars_hidden: INTEGER = 3
			-- No bars; the view still scrolls.

feature -- Status

	is_style_property (a_property: INTEGER): BOOLEAN
		do
			Result := a_property >= Property_foreground and a_property <= Property_count
		ensure
			definition: Result = (a_property >= Property_foreground and a_property <= Property_count)
		end

	is_scroll_bar_kind (a_kind: INTEGER): BOOLEAN
		do
			Result := a_kind >= Scroll_bars_system and a_kind <= Scroll_bars_hidden
		end

	is_rgb (a_color: NATURAL_32): BOOLEAN
			-- Is `a_color' a 0xRRGGBB value?
		do
			Result := a_color <= 0xFFFFFF
		end

feature -- Backend keys

	style_key (a_property: INTEGER): STRING
			-- The key of `a_property' in the flat style a backend is given ("fg", "pad"...).
		require
			known: is_style_property (a_property)
		do
			inspect a_property
			when Property_foreground then Result := "fg"
			when Property_background then Result := "bg"
			when Property_placeholder_color then Result := "placeholder"
			when Property_selection_color then Result := "selection"
			when Property_font_family then Result := "font"
			when Property_font_size then Result := "size"
			when Property_font_weight then Result := "weight"
			when Property_italic then Result := "italic"
			when Property_padding then Result := "pad"
			when Property_border then Result := "border"
			when Property_corner_radius then Result := "radius"
			when Property_shadow then Result := "shadow"
			else Result := "scroll"
			end
		ensure
			named: not Result.is_empty
		end

end
