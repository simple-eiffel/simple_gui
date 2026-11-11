note
	description: "[
		GUI_CODE_EDITOR's text area on Windows: the rich text area in the fixed-pitch role,
		never wrapped, scrolled both ways, with a line-number gutter.

		The scrolling is SW_VSCROLLING inherited beside the text box (its bar, wheel and
		clamping) plus an SW_HSCROLLBAR of its own; the text is moved by redefining the box's
		frame (`text_left', `text_top', `wrap_width_in'), so hit testing, the caret and the
		selection follow with no copy of the box's code.

		Return keeps the line's indent; Tab inserts a tab (or spaces to the next stop) and
		indents the selected lines; Shift+Tab unindents them. Lines and columns count from 1,
		in characters, and are read from the text, so they answer before the first layout.

		Cost: the colors are marks, and only the lines in view carry them (`mark_view'): a
		mark for every colored run of a long text costs more than drawing it. The box still
		lays out the whole text after an edit and walks every character when it draws, so
		the time of one keystroke grows with the size of the text.
	]"

class
	GUI_SW_CODE_AREA

inherit
	GUI_SW_RICH_TEXT_AREA
		redefine
			make_rich, set_text, changed, ensure_layout, refresh_marks, draw, text_left, text_top,
			wrap_width_in, effective_text_alignment, preferred_height, select_characters,
			handle_click, handle_double_click, handle_triple_click, handle_drag,
			handle_char, handle_key, handle_wheel, handle_release, wants_tab
		end

	SW_VSCROLLING
		undefine
			accepts_focus, preferred_width, context_menu, accepts_pebble, receive_pebble,
			cursor_kind, accessible_role, accessible_value, set_focused, takes_typing,
			can_edit, perform_edit
		redefine
			handle_click, handle_double_click, handle_triple_click, handle_drag,
			handle_char, handle_key, handle_wheel, handle_release, wants_tab
		end

create
	make_rich

feature {NONE} -- Initialization

	make_rich (a_body_size: REAL_64)
			-- Empty, fixed-pitch, line numbers shown, tab stops four columns apart.
		do
			Precursor (a_body_size)
			tab_width := 4
			is_line_numbers_shown := True
			told_line := 1
			told_column := 1
			set_text_role ({SW_PAINTER}.Role_mono)
			set_spellcheck (False)
			set_tab_spaces (4)
		ensure then
			numbered: is_line_numbers_shown
			four_wide: tab_width = 4
			tabs_kept: not is_indent_with_spaces
		end

feature -- Access

	is_line_numbers_shown: BOOLEAN
			-- Is the gutter of line numbers drawn?

	tab_width: INTEGER
			-- Columns between tab stops.

	is_indent_with_spaces: BOOLEAN
			-- Does Tab insert spaces to the next stop, not a tab character?

	scroll_x: REAL_64
			-- How far the text is moved left.

	h_bar: SW_HSCROLLBAR
			-- The bar under the text, shown when a line is wider than the view.
		attribute
			create Result.make
		end

	on_caret_move: detachable PROCEDURE [INTEGER, INTEGER]
			-- Told (line, column) when the user moves the caret to another place.

feature -- Element change

	set_on_caret_move (an_action: detachable PROCEDURE [INTEGER, INTEGER])
		do
			on_caret_move := an_action
		ensure
			set: on_caret_move = an_action
		end

	set_line_numbers_shown (a_on: BOOLEAN)
		do
			is_line_numbers_shown := a_on
			is_measured := False
		ensure
			set: is_line_numbers_shown = a_on
		end

	set_indent (a_tab_width: INTEGER; a_spaces: BOOLEAN)
			-- Tab stops every `a_tab_width' columns; Tab inserts spaces when `a_spaces'.
		require
			positive: a_tab_width >= 1
		do
			tab_width := a_tab_width
			is_indent_with_spaces := a_spaces
			set_tab_spaces (a_tab_width)
			is_measured := False
		ensure
			width_set: tab_width = a_tab_width
			spaces_set: is_indent_with_spaces = a_spaces
		end

	set_text (a_text: READABLE_STRING_GENERAL)
			-- New text; the caret's place is noted, not reported.
		do
			Precursor {GUI_SW_RICH_TEXT_AREA} (a_text)
			is_reveal_pending := True
			note_caret
		end

	replace_characters (a_start, an_end: INTEGER; a_text: READABLE_STRING_GENERAL)
			-- Put `a_text' in place of characters `a_start' to `an_end' (none when `an_end' is
			-- `a_start' - 1), as one undo step, and leave it selected with the caret at its
			-- start. The program's own change: nothing is reported.
		require
			range: 1 <= a_start and a_start <= an_end + 1 and an_end <= text.count
		local
			l_new: STRING_32
		do
			create l_new.make_from_string_general (a_text)
			remember (Kind_block)
			if an_end >= a_start then
				text.remove_substring (a_start, an_end)
				marks.text_removed (a_start - 1, an_end)
			end
			if not l_new.is_empty then
				text.insert_string (l_new, a_start)
				marks.text_inserted (a_start - 1, l_new.count)
			end
			caret := a_start - 1
			sel_anchor := a_start - 1 + l_new.count
			extra_ranges.wipe_out
			sync
			is_style_stale := True
			layout_width := -1.0
			spell_dirty := True
			is_reveal_pending := True
			note_caret
		ensure
			count_follows: text.count = old text.count - (an_end - a_start + 1) + a_text.count
			selected: selection_first = a_start and selection_last = a_start + a_text.count - 1
		end

feature -- Lines and columns (from 1, in characters)

	code_line_count: INTEGER
			-- Lines of text: one more than the line breaks.
		do
			Result := text.occurrences ('%N') + 1
		ensure
			at_least_one: Result >= 1
		end

	code_caret_line: INTEGER
		do
			Result := code_line_at (caret)
		ensure
			in_lines: 1 <= Result and Result <= code_line_count
		end

	code_caret_column: INTEGER
		do
			Result := caret - start_of_line_at (caret) + 1
		ensure
			positive: Result >= 1
		end

	code_line_start (a_line: INTEGER): INTEGER
			-- Characters before line `a_line'.
		require
			valid: 1 <= a_line and a_line <= code_line_count
		local
			l_line: INTEGER
		do
			from
				l_line := 1
			until
				l_line = a_line
			loop
				Result := text.index_of ('%N', Result + 1)
				l_line := l_line + 1
			end
		ensure
			in_text: 0 <= Result and Result <= text.count
		end

	code_line_text (a_line: INTEGER): STRING_32
			-- Line `a_line' without its line break.
		require
			valid: 1 <= a_line and a_line <= code_line_count
		local
			l_start: INTEGER
		do
			l_start := code_line_start (a_line)
			Result := text.substring (l_start + 1, end_of_line_at (l_start))
		ensure
			one_line: not Result.has ('%N')
		end

	go_to_line (a_line: INTEGER)
			-- The caret at the start of line `a_line', brought into view. The program's own
			-- move: nothing is reported.
		require
			valid: 1 <= a_line and a_line <= code_line_count
		do
			caret := code_line_start (a_line)
			sel_anchor := caret
			extra_ranges.wipe_out
			is_reveal_pending := True
			note_caret
		ensure
			there: code_caret_line = a_line and code_caret_column = 1
			collapsed: not has_selection
		end

	move_caret_to (a_line, a_column: INTEGER)
			-- The caret at (`a_line', `a_column') as the user would put it there (a column
			-- past the line's end lands on the end), and reported.
		require
			valid: 1 <= a_line and a_line <= code_line_count
			column_positive: a_column >= 1
		local
			l_start: INTEGER
		do
			l_start := code_line_start (a_line)
			caret := (l_start + a_column - 1).min (end_of_line_at (l_start))
			sel_anchor := caret
			extra_ranges.wipe_out
			is_reveal_pending := True
			report_caret
		ensure
			on_line: code_caret_line = a_line
			collapsed: not has_selection
		end

	select_characters (a_start, an_end: INTEGER)
			-- Also brought into view (a found match must be seen).
		do
			Precursor {GUI_SW_RICH_TEXT_AREA} (a_start, an_end)
			is_reveal_pending := True
			note_caret
		end

feature -- Typing

	wants_tab: BOOLEAN
			-- Tab is this widget's own key.
		do
			Result := True
		end

	type_code (a_text: READABLE_STRING_GENERAL)
			-- Type `a_text' as the user would: a line break through Return, a tab through
			-- Tab, every other character as itself.
		require
			writable: not is_read_only
		local
			i: INTEGER
			c: CHARACTER_32
		do
			from
				i := 1
			until
				i > a_text.count
			loop
				c := a_text.item (i)
				if c = '%N' then
					press_return
				elseif c = '%T' then
					press_tab (False)
				elseif c.code >= 32 then
					handle_char (c.code)
				end
				i := i + 1
			end
			is_reveal_pending := True
			report_caret
		end

	handle_char (a_code: INTEGER)
		local
			l_keys: SW_KEYS
			l_caret: INTEGER
		do
			l_caret := caret
			if is_read_only then
				Precursor {GUI_SW_RICH_TEXT_AREA} (a_code)
			elseif a_code = 13 then
				press_return
			elseif a_code = 9 then
					-- Control+I arrives as character 9 too; it is not Tab
				create l_keys
				if not l_keys.control_down then
					press_tab (l_keys.shift_down)
				end
			else
				Precursor {GUI_SW_RICH_TEXT_AREA} (a_code)
			end
			if caret /= l_caret and a_code /= 1 then
					-- (select all moves the caret to the end; the view stays)
				is_reveal_pending := True
			end
			report_caret
		end

	handle_key (a_vk: INTEGER; a_shift: BOOLEAN)
			-- Page Up and Page Down move the caret a page; Control+Home and Control+End go
			-- to the ends of the text; the rest as the text box.
		local
			l_keys: SW_KEYS
			l_caret, l_line: INTEGER
			l_x: REAL_64
		do
			l_caret := caret
			create l_keys
			if (a_vk = 33 or a_vk = 34) and then is_laid_out then
				l_line := caret_line
				l_x := caret_x
				if a_vk = 33 then
					l_line := (l_line - page_rows).max (0)
				else
					l_line := (l_line + page_rows).min (lay_lines - 1)
				end
				caret := offset_on_line (l_line, l_x)
				collapse_unless (a_shift)
			elseif (a_vk = 35 or a_vk = 36) and then l_keys.control_down then
				if a_vk = 36 then
					caret := 0
				else
					caret := text.count
				end
				collapse_unless (a_shift)
			else
				Precursor {GUI_SW_RICH_TEXT_AREA} (a_vk, a_shift)
			end
			if caret /= l_caret then
				is_reveal_pending := True
			end
			report_caret
		end

feature -- Pointer

	handle_click (a_px, a_py: REAL_64): BOOLEAN
			-- A press on a scrollbar scrolls; anywhere else places the caret.
		do
			if press_bar (a_px, a_py) then
				Result := True
			elseif h_bar.contains (a_px, a_py) then
				scroll_x := h_bar.press (a_px, scroll_x)
				Result := True
			else
				Result := Precursor {GUI_SW_RICH_TEXT_AREA} (a_px, a_py)
				is_reveal_pending := True
				report_caret
			end
		end

	handle_double_click (a_px, a_py: REAL_64): BOOLEAN
			-- Select the name or number under the point: a run of letters, digits and
			-- underscores.
		local
			l_lo, l_hi: INTEGER
		do
			Result := True
			if not bar.contains (a_px, a_py) and then not h_bar.contains (a_px, a_py) then
				l_lo := offset_at (a_px, a_py)
				l_hi := l_lo
				from until l_lo = 0 or else not is_word_character (text.item (l_lo)) loop
					l_lo := l_lo - 1
				end
				from until l_hi = text.count or else not is_word_character (text.item (l_hi + 1)) loop
					l_hi := l_hi + 1
				end
				if l_hi > l_lo then
					sel_anchor := l_lo
					caret := l_hi
					extra_ranges.wipe_out
					is_reveal_pending := True
					report_caret
				end
			end
		end

	handle_triple_click (a_px, a_py: REAL_64): BOOLEAN
			-- Select the line under the point with its line break (the whole text when
			-- that line is empty and the last).
		local
			l_start, l_end: INTEGER
		do
			l_start := start_of_line_at (offset_at (a_px, a_py))
			l_end := end_of_line_at (l_start)
			if l_end < text.count then
				l_end := l_end + 1
			end
			if l_end > l_start then
				sel_anchor := l_start
				caret := l_end
				extra_ranges.wipe_out
				Result := True
			else
				Result := Precursor {GUI_SW_RICH_TEXT_AREA} (a_px, a_py)
			end
			report_caret
		end

	handle_drag (a_px, a_py: REAL_64)
		do
			if drag_bar (a_py) then
					-- the side bar has it
			elseif h_bar.is_dragging then
				scroll_x := h_bar.drag_to (a_px)
			else
				Precursor {GUI_SW_RICH_TEXT_AREA} (a_px, a_py)
				is_reveal_pending := True
				report_caret
			end
		end

	handle_release (a_x, a_y: INTEGER)
		do
			release_bar
			h_bar.release
		end

	handle_wheel (a_delta: INTEGER): BOOLEAN
			-- The wheel scrolls the lines; with Shift held, the columns.
		local
			l_keys: SW_KEYS
		do
			create l_keys
			if l_keys.shift_down then
				scroll_x := h_bar.wheel_scroll (scroll_x, a_delta, wheel_line)
			else
				wheel_scrolled (a_delta)
			end
			Result := True
		end

feature -- Text frame

	Unwrapped_width: REAL_64 = 100_000.0
			-- The wrap width handed to the layout: wider than any line of code (about
			-- twelve thousand characters at the body size), so no line wraps.

	text_left: REAL_64
			-- Right of the gutter, moved left by `scroll_x'.
		do
			Result := x + gutter_width + Pad_x - scroll_x
		end

	text_top: REAL_64
			-- Moved up by `scroll_y'.
		do
			Result := y + Pad_y - scroll_y
		end

	wrap_width_in (a_width: REAL_64): REAL_64
			-- Never wrapped, whatever the box's width.
		do
			Result := Unwrapped_width
		end

	effective_text_alignment: INTEGER
			-- Code reads left to right in every language of the interface.
		do
			Result := text_alignment
		end

feature -- Layout

	Preferred_rows: INTEGER = 8
			-- Rows the editor asks for when nothing stretches it.

	Default_row_pitch: REAL_64 = 16.0
			-- The wheel's line before the first layout has measured one.

	scroll_extent: REAL_64
			-- Every line, the insets above and below, and room for the bottom bar.
		do
			Result := content_height + 2.0 * Pad_y + bottom_room
		end

	wheel_line: REAL_64
			-- One row.
		do
			if row_pitch > 0.0 then
				Result := row_pitch
			else
				Result := Default_row_pitch
			end
		end

	preferred_height (a_p: SW_PAINTER; a_width: REAL_64): REAL_64
			-- `Preferred_rows' rows: the editor scrolls, so its text does not size it.
		do
			ensure_layout (a_p, wrap_width_in (a_width))
			Result := (Preferred_rows * wheel_line + 2.0 * Pad_y).max (minimum_height (a_p))
		end

feature -- Drawing

	draw (a_p: SW_PAINTER)
			-- The field; the text clipped to its view; the gutter; the two bars.
		local
			l_theme: SW_THEME
			l_view_w, l_view_h, l_bar_w: REAL_64
		do
			l_theme := a_p.theme
			ensure_layout (a_p, wrap_width_in (width))
			l_bar_w := l_theme.scrollbar_width
				-- the bottom bar takes room from the rows and the side bar from the
				-- columns, so each can bring the other in
			bottom_room := 0.0
			side_room := 0.0
			if widest_line + 2.0 * Pad_x > width - gutter_width then
				bottom_room := l_bar_w
			end
			if scroll_extent > height then
				side_room := l_bar_w
				if widest_line + 2.0 * Pad_x > width - gutter_width - side_room then
					bottom_room := l_bar_w
				end
			end
			l_view_w := (width - gutter_width - side_room).max (0.0)
			l_view_h := (height - bottom_room).max (0.0)
			place_bar (l_theme)
			h_bar.place (x + gutter_width, y + height - l_bar_w, l_view_w, l_bar_w, l_theme)
			h_bar.set_extent (l_view_w, widest_line + 2.0 * Pad_x)
			scroll_x := h_bar.clamped (scroll_x)
			if is_reveal_pending then
				reveal_caret (l_view_w, l_view_h)
				is_reveal_pending := False
			end
			mark_view (l_view_h)
			draw_field (a_p)
			a_p.push_clip (x + gutter_width, y + 1.0, l_view_w, (l_view_h - 2.0).max (0.0))
			draw_content (a_p)
			a_p.pop_clip
			if gutter_width > 0.0 then
				draw_gutter (a_p, l_view_h)
			end
			draw_bar (a_p)
			h_bar.draw (a_p, scroll_x, shows_hover and then h_bar.contains (hover_px, hover_py))
		end

feature {NONE} -- Implementation

	gutter_width: REAL_64
			-- The line numbers' column (0 when hidden), as last measured.

	row_pitch: REAL_64
			-- One line's height, as last measured.

	widest_line: REAL_64
			-- The widest line's right edge from the text's origin, as last measured.

	bottom_room, side_room: REAL_64
			-- What the bottom bar and the side bar take from the view (0 when not shown).

	is_measured: BOOLEAN
			-- Do `gutter_width', `row_pitch' and `widest_line' fit the layout?

	is_reveal_pending: BOOLEAN
			-- Is the caret to be scrolled into view at the next draw?

	told_line, told_column: INTEGER
			-- The caret's place when it was last reported or noted.

	changed
			-- An edit: report it, then the caret's new place.
		do
			Precursor {GUI_SW_RICH_TEXT_AREA}
			is_reveal_pending := True
			report_caret
		end

	ensure_layout (a_p: SW_PAINTER; a_wrap: REAL_64)
			-- Measure again whenever the text was laid out again.
		local
			l_width: REAL_64
			l_size: INTEGER
			l_shaped, l_restyled, l_edited: BOOLEAN
		do
			l_width := layout_width
			l_size := laid_size
			l_shaped := laid_shaped
			l_restyled := is_glyph_stale
			l_edited := geometry.count /= text.count
			Precursor {GUI_SW_RICH_TEXT_AREA} (a_p, a_wrap)
			if not is_measured or l_restyled or l_edited or l_width /= layout_width or l_size /= laid_size or l_shaped /= laid_shaped then
				measure_code (a_p)
			end
		end

	refresh_marks
			-- Not here: `draw' marks the lines in view (`mark_view'), once it knows where the
			-- text is scrolled to.
		do
		end

	marked_first, marked_last: INTEGER
			-- The characters the marks were last built for.

	mark_view (a_view_h: REAL_64)
			-- Build the marks (the colors) of the lines a view `a_view_h' high shows, when
			-- the styles changed or the view moved.
		require
			laid_out: is_laid_out
		local
			l_first, l_last: INTEGER
			l_geometry: SW_TEXT_GEOMETRY
		do
			l_geometry := geometry
			l_first := l_geometry.line_start (l_geometry.line_at_y (scroll_y - Pad_y)) + 1
			l_last := l_geometry.line_end (l_geometry.line_at_y (scroll_y - Pad_y + a_view_h))
			if is_style_stale or l_first /= marked_first or l_last /= marked_last then
				sync
				apply_marks (l_first, l_last.min (styles.count))
				marked_first := l_first
				marked_last := l_last
				is_style_stale := False
			end
		ensure
			fresh: not is_style_stale
		end

	measure_code (a_p: SW_PAINTER)
			-- The gutter, the row and the widest line of the layout just made.
		require
			laid_out: is_laid_out
		local
			l_geometry: SW_TEXT_GEOMETRY
		do
			l_geometry := geometry
			row_pitch := l_geometry.height_of_line (0)
			if is_line_numbers_shown then
				a_p.font (face_role, body_size (a_p), False)
				gutter_width := a_p.advance ("8") * l_geometry.line_count.out.count.max (2) + 2.0 * a_p.theme.padding
			else
				gutter_width := 0.0
			end
			widest_line := l_geometry.rightmost_edge
			is_measured := True
		ensure
			measured: is_measured
		end

	reveal_caret (a_view_w, a_view_h: REAL_64)
			-- Scroll the least that puts the caret inside a view of that size.
		require
			laid_out: is_laid_out
		local
			l_line: INTEGER
			l_top, l_bottom, l_x: REAL_64
		do
			l_line := caret_line
			l_top := geometry.top_of_line (l_line)
			l_bottom := l_top + geometry.height_of_line (l_line) + 2.0 * Pad_y
			if l_top < scroll_y then
				scroll_to (l_top)
			elseif l_bottom > scroll_y + a_view_h then
				scroll_to (l_bottom - a_view_h)
			end
			l_x := caret_x
			if l_x < scroll_x then
				scroll_x := l_x
			elseif l_x + 2.0 * Pad_x > scroll_x + a_view_w then
				scroll_x := l_x + 2.0 * Pad_x - a_view_w
			end
			scroll_x := h_bar.clamped (scroll_x)
		end

	draw_gutter (a_p: SW_PAINTER; a_view_h: REAL_64)
			-- The numbers of the lines in view, right-aligned, and the rule beside them.
		local
			l_theme: SW_THEME
			l_geometry: SW_TEXT_GEOMETRY
			i, l_last: INTEGER
			l_number: STRING_32
			l_right, l_clip_h: REAL_64
		do
			l_theme := a_p.theme
			l_geometry := geometry
			l_clip_h := (a_view_h - 2.0).max (0.0)
			a_p.push_clip (x, y + 1.0, gutter_width, l_clip_h)
			a_p.font (face_role, body_size (a_p), False)
			a_p.set_color (l_theme.ink_muted)
			l_right := x + gutter_width - l_theme.padding
			from
				i := l_geometry.line_at_y (scroll_y - Pad_y)
				l_last := l_geometry.line_at_y (scroll_y - Pad_y + a_view_h)
			until
				i > l_last
			loop
				l_number := (i + 1).out.to_string_32
				a_p.text (l_right - a_p.advance (l_number),
					text_top + l_geometry.top_of_line (i) + l_geometry.ascent_of_line (i), l_number)
				i := i + 1
			end
			a_p.set_color (l_theme.outline)
			a_p.fill_rect (x + gutter_width - 1.0, y + 1.0, 1.0, l_clip_h)
			a_p.pop_clip
		end

	page_rows: INTEGER
			-- Rows a page key moves: one less than the view holds, at least one.
		do
			Result := (((height - bottom_room - 2.0 * Pad_y) / wheel_line).floor - 1).max (1)
		ensure
			positive: Result >= 1
		end

	report_caret
			-- Tell `on_caret_move' when the caret is on another line or column than last told.
		local
			l_line, l_column: INTEGER
		do
			l_line := code_caret_line
			l_column := code_caret_column
			if l_line /= told_line or l_column /= told_column then
				told_line := l_line
				told_column := l_column
				if attached on_caret_move as al_told then
					al_told.call ([l_line, l_column])
				end
			end
		end

	note_caret
			-- Remember the caret's place without telling anyone (the program moved it).
		do
			told_line := code_caret_line
			told_column := code_caret_column
		end

	code_line_at (a_offset: INTEGER): INTEGER
			-- The line a caret with `a_offset' characters before it stands on.
		require
			in_text: 0 <= a_offset and a_offset <= text.count
		local
			i: INTEGER
		do
			Result := 1
			from
				i := 1
			until
				i > a_offset
			loop
				if text.item (i) = '%N' then
					Result := Result + 1
				end
				i := i + 1
			end
		ensure
			in_lines: 1 <= Result and Result <= code_line_count
		end

	start_of_line_at (a_offset: INTEGER): INTEGER
			-- Characters before the line that offset `a_offset' is on.
		require
			in_text: 0 <= a_offset and a_offset <= text.count
		do
			from
				Result := a_offset
			until
				Result = 0 or else text.item (Result) = '%N'
			loop
				Result := Result - 1
			end
		ensure
			at_or_before: 0 <= Result and Result <= a_offset
		end

	end_of_line_at (a_offset: INTEGER): INTEGER
			-- Characters before the line break (or the text's end) that closes the line
			-- offset `a_offset' is on.
		require
			in_text: 0 <= a_offset and a_offset <= text.count
		do
			from
				Result := a_offset
			until
				Result = text.count or else text.item (Result + 1) = '%N'
			loop
				Result := Result + 1
			end
		ensure
			at_or_after: a_offset <= Result and Result <= text.count
		end

	is_word_character (a_character: CHARACTER_32): BOOLEAN
			-- Is `a_character' part of a name or a number?
			-- Why not SW_WORD_BOUNDARY: its word is for prose, where a digit run after a letter
			-- run is a word of its own (a Strong's number) and an underscore is a letter only
			-- by accident. In code `item_2' is one name, so a double click must take all of it.
		do
			Result := a_character.is_alpha or a_character.is_digit or a_character = '_'
		end

	press_return
			-- A line break, then the leading spaces and tabs of the caret's line.
		require
			writable: not is_read_only
		local
			i: INTEGER
			l_new: STRING_32
		do
			create l_new.make (8)
			l_new.append_character ('%N')
			from
				i := start_of_line_at (caret) + 1
			until
				i > text.count or else (text.item (i) /= ' ' and text.item (i) /= '%T')
			loop
				l_new.append_character (text.item (i))
				i := i + 1
			end
			insert_block (l_new)
		end

	press_tab (a_shift: BOOLEAN)
			-- Shift: unindent the selected lines. A selection over a line break: indent its
			-- lines. Otherwise replace the selection with a tab, or with spaces up to the
			-- next stop.
		require
			writable: not is_read_only
		local
			l_lo, l_hi: INTEGER
		do
			l_lo := caret.min (sel_anchor)
			l_hi := caret.max (sel_anchor)
			if a_shift then
				shift_lines (False)
			elseif l_hi > l_lo and then text.substring (l_lo + 1, l_hi).has ('%N') then
				shift_lines (True)
			elseif is_indent_with_spaces then
				insert_block (create {STRING_32}.make_filled (' ',
					tab_width - (l_lo - start_of_line_at (l_lo)) \\ tab_width))
			else
				insert_block ({STRING_32} "%T")
			end
		end

	insert_block (a_text: READABLE_STRING_32)
			-- `a_text' in place of the selection, as one undo step, the caret after it.
		require
			writable: not is_read_only
		do
			remember (Kind_block)
			if has_selection then
				delete_selection
			end
			text.insert_string (a_text, caret + 1)
			marks.text_inserted (caret, a_text.count)
			caret := caret + a_text.count
			sel_anchor := caret
			changed
		ensure
			collapsed: not has_selection
		end

	shift_lines (a_in: BOOLEAN)
			-- Indent (`a_in') or unindent every line the selection touches (the caret's line
			-- when nothing is selected), as one undo step. A selection that ends at the
			-- start of a line leaves that line alone. Unindenting takes one tab, or up to
			-- `tab_width' spaces.
		require
			writable: not is_read_only
		local
			l_lo, l_hi, l_first, l_start, l_cut: INTEGER
			l_pad: STRING_32
			l_edited: BOOLEAN
		do
			l_lo := caret.min (sel_anchor)
			l_hi := caret.max (sel_anchor)
			if l_hi > l_lo and then text.item (l_hi) = '%N' then
				l_hi := l_hi - 1
			end
			l_first := start_of_line_at (l_lo)
			if is_indent_with_spaces then
				create l_pad.make_filled (' ', tab_width)
			else
				create l_pad.make_filled ('%T', 1)
			end
			from
				l_start := start_of_line_at (l_hi)
			until
				l_start < l_first
			loop
				if a_in then
					if not l_edited then
						remember (Kind_block)
						l_edited := True
					end
					text.insert_string (l_pad, l_start + 1)
					marks.text_inserted (l_start, l_pad.count)
					caret := shifted (caret, l_start, l_pad.count)
					sel_anchor := shifted (sel_anchor, l_start, l_pad.count)
				else
					l_cut := 0
					if l_start < text.count and then text.item (l_start + 1) = '%T' then
						l_cut := 1
					else
						from until
							l_cut >= tab_width or else l_start + l_cut >= text.count
								or else text.item (l_start + l_cut + 1) /= ' '
						loop
							l_cut := l_cut + 1
						end
					end
					if l_cut > 0 then
						if not l_edited then
							remember (Kind_block)
							l_edited := True
						end
						text.remove_substring (l_start + 1, l_start + l_cut)
						marks.text_removed (l_start, l_start + l_cut)
						caret := shifted (caret, l_start, - l_cut)
						sel_anchor := shifted (sel_anchor, l_start, - l_cut)
					end
				end
				if l_start = 0 then
					l_start := -1
				else
					l_start := start_of_line_at (l_start - 1)
				end
			end
			extra_ranges.wipe_out
			if l_edited then
				changed
			end
		end

	shifted (a_offset, a_at, a_by: INTEGER): INTEGER
			-- `a_offset' after `a_by' characters were inserted at offset `a_at' (removed
			-- from there, when negative): an offset inside a removed stretch lands on `a_at'.
		do
			if a_by >= 0 then
				if a_offset >= a_at then
					Result := a_offset + a_by
				else
					Result := a_offset
				end
			elseif a_offset > a_at then
				Result := (a_offset + a_by).max (a_at)
			else
				Result := a_offset
			end
		end

invariant
	tab_positive: tab_width >= 1
	scroll_x_non_negative: scroll_x >= 0.0
	told_positive: told_line >= 1 and told_column >= 1

end
