note
	description: "[
		Styled text the user edits (NSTextView with attributes, GtkTextView with tags,
		SW_DOCUMENT_VIEW or SW_MARKED_TEXT). A GUI_TEXT_AREA whose ranges can be bold, italic,
		underlined, colored and sized. Positions are 1-based characters, as STRING_32 counts
		them, and a range `a_start' .. `an_end' is inclusive. Formatting from code fires
		nothing; the user's edits fire `change_actions' as in any text area.
	]"

class
	GUI_RICH_TEXT_AREA

inherit
	GUI_TEXT_AREA
		redefine
			make
		end

create
	make

feature {NONE} -- Initialization

	make
		do
			create change_actions.make
			register (backend.rich_text_area)
		end

feature -- Access

	count: INTEGER
			-- How many characters the text has.
		do
			Result := text.count
		end

	selection_start: INTEGER
			-- The first selected character (at the caret when nothing is selected).
		do
			Result := backend.rich_text_selection_start (id)
		end

	selection_end: INTEGER
			-- The last selected character; `selection_start' - 1 when nothing is selected.
		do
			Result := backend.rich_text_selection_end (id)
		end

	is_bold_at (i: INTEGER): BOOLEAN
		require
			valid: is_valid_position (i)
		do
			Result := backend.rich_text_trait_at (id, i, Trait_bold)
		end

	is_italic_at (i: INTEGER): BOOLEAN
		require
			valid: is_valid_position (i)
		do
			Result := backend.rich_text_trait_at (id, i, Trait_italic)
		end

	is_underlined_at (i: INTEGER): BOOLEAN
		require
			valid: is_valid_position (i)
		do
			Result := backend.rich_text_trait_at (id, i, Trait_underline)
		end

	has_text_color_at (i: INTEGER): BOOLEAN
			-- Does character `i' have a color of its own (not the theme's text color)?
		require
			valid: is_valid_position (i)
		do
			Result := backend.rich_text_color_at (id, i) >= 0
		end

	text_color_at (i: INTEGER): NATURAL_32
			-- Character `i''s color, 0xRRGGBB.
		require
			valid: is_valid_position (i)
			colored: has_text_color_at (i)
		do
			Result := backend.rich_text_color_at (id, i).to_natural_32
		end

	font_size_at (i: INTEGER): REAL_64
			-- Character `i''s size in points.
		require
			valid: is_valid_position (i)
		do
			Result := backend.rich_text_size_at (id, i)
		end

feature -- Status

	is_valid_position (i: INTEGER): BOOLEAN
		do
			Result := 1 <= i and i <= count
		end

	is_valid_range (a_start, an_end: INTEGER): BOOLEAN
			-- Is `a_start' .. `an_end' a range of the text (empty when `an_end' = `a_start' - 1)?
		do
			Result := 1 <= a_start and a_start <= an_end + 1 and an_end <= count
		end

feature -- Formatting

	set_bold (a_start, an_end: INTEGER; a_on: BOOLEAN)
		require
			gui_thread: is_gui_thread
			valid: is_valid_range (a_start, an_end)
		do
			backend.rich_text_set_trait (id, a_start, an_end, Trait_bold, a_on)
		ensure
			set: a_start <= an_end implies is_bold_at (a_start) = a_on
		end

	set_italic (a_start, an_end: INTEGER; a_on: BOOLEAN)
		require
			gui_thread: is_gui_thread
			valid: is_valid_range (a_start, an_end)
		do
			backend.rich_text_set_trait (id, a_start, an_end, Trait_italic, a_on)
		end

	set_underline (a_start, an_end: INTEGER; a_on: BOOLEAN)
		require
			gui_thread: is_gui_thread
			valid: is_valid_range (a_start, an_end)
		do
			backend.rich_text_set_trait (id, a_start, an_end, Trait_underline, a_on)
		ensure
			set: a_start <= an_end implies is_underlined_at (a_start) = a_on
		end

	set_text_color (a_start, an_end: INTEGER; a_color: NATURAL_32)
		require
			gui_thread: is_gui_thread
			valid: is_valid_range (a_start, an_end)
			rgb: a_color <= 0xFFFFFF
		do
			backend.rich_text_set_color (id, a_start, an_end, a_color.to_integer_32)
		ensure
			set: a_start <= an_end implies text_color_at (a_start) = a_color
		end

	set_font_size (a_start, an_end: INTEGER; a_points: REAL_64)
		require
			gui_thread: is_gui_thread
			valid: is_valid_range (a_start, an_end)
			positive: a_points > 0
		do
			backend.rich_text_set_size (id, a_start, an_end, a_points)
		end

	select_range (a_start, an_end: INTEGER)
			-- Select `a_start' .. `an_end' (an empty range puts the caret before `a_start').
		require
			gui_thread: is_gui_thread
			valid: is_valid_range (a_start, an_end)
		do
			backend.rich_text_select (id, a_start, an_end)
		ensure
			start_set: selection_start = a_start
			end_set: selection_end = an_end
		end

feature {NONE} -- Implementation

	Trait_bold: INTEGER = 1

	Trait_italic: INTEGER = 2

	Trait_underline: INTEGER = 3

end
