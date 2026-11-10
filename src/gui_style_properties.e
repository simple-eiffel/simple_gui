note
	description: "[
		The names of a GUI_STYLE's properties (1w), for `is_set', `unset' and
		GUI_WIDGET.supports_style, and the key each one has in the flat style a backend
		is given.
	]"

class
	GUI_STYLE_PROPERTIES

feature -- Properties

	Foreground: INTEGER = 1
			-- The text (or tint) color.
	Background: INTEGER = 2
	Placeholder_color: INTEGER = 3
			-- A field's placeholder text.
	Selection_color: INTEGER = 4
			-- The text selection, and the selected rows of lists, tables and trees.
	Font_family: INTEGER = 5
	Font_size: INTEGER = 6
	Font_weight: INTEGER = 7
	Italic: INTEGER = 8
	Padding: INTEGER = 9
	Border: INTEGER = 10
			-- The border's width and color.
	Corner_radius: INTEGER = 11
	Shadow: INTEGER = 12
	Scroll_bars: INTEGER = 13

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
			Result := a_property >= Foreground and a_property <= Property_count
		ensure
			definition: Result = (a_property >= Foreground and a_property <= Property_count)
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
			when Foreground then Result := "fg"
			when Background then Result := "bg"
			when Placeholder_color then Result := "placeholder"
			when Selection_color then Result := "selection"
			when Font_family then Result := "font"
			when Font_size then Result := "size"
			when Font_weight then Result := "weight"
			when Italic then Result := "italic"
			when Padding then Result := "pad"
			when Border then Result := "border"
			when Corner_radius then Result := "radius"
			when Shadow then Result := "shadow"
			else Result := "scroll"
			end
		ensure
			named: not Result.is_empty
		end

end
