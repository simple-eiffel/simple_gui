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
		mark for every colored run of a long text costs more than drawing it. A frame draws
		the lines in view only, and an edit lays out the edited paragraphs only.
	]"
	performance: "[
		2026-11-10, Windows, 10,000 lines (388,893 characters), contract checking off: a
		frame's text drawing 4 to 5 milliseconds; a test keystroke (3 to 5 frames) 84
		milliseconds mean. What still grows with the text on each keystroke: the style
		sync (about 7 milliseconds) and the editor's comparison of the old text with the
		new (about 8), the copy the box keeps for undo, and `report_caret' finding the
		caret's line by a scan (about 2, twice). An edit report from the box (start,
		removed, inserted; planned as 1v-e) ends the comparing.
	]"

class
	GUI_SW_CODE_AREA

inherit
	GUI_SW_RICH_TEXT_AREA
		redefine
			make_rich, set_text, changed, ensure_layout, refresh_marks, draw, text_left, text_top,
			wrap_width_in, effective_text_alignment, preferred_height, select_characters,
			handle_click, handle_double_click, handle_triple_click, handle_drag,
			handle_char, handle_key, handle_wheel, handle_release, wants_tab, offset_at,
			set_focused
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

	on_bracket_key: detachable PROCEDURE
			-- Told when the user presses the key that goes to the matching bracket.

feature -- The bracket pair (1v-e-2)

	has_bracket_pair: BOOLEAN
			-- Are two brackets tinted?

	pair_first_start, pair_first_count, pair_second_start, pair_second_count: INTEGER
			-- The two tinted ranges, in characters from 1; meaningful with `has_bracket_pair'.

	is_range_in_text (a_start, a_count: INTEGER): BOOLEAN
			-- Do `a_count' characters from position `a_start' lie in the text, one at least?
		do
			Result := a_start >= 1 and a_count >= 1 and a_start <= text.count
				and then a_count <= text.count - a_start + 1
		end

	is_bracket_tinted (a_position: INTEGER): BOOLEAN
			-- Is the character at `a_position' under the tint?
		do
			Result := has_bracket_pair and then
				((pair_first_start <= a_position and a_position < pair_first_start + pair_first_count)
				or (pair_second_start <= a_position and a_position < pair_second_start + pair_second_count))
		end

	show_bracket_pair (a_first_start, a_first_count, a_second_start, a_second_count: INTEGER)
			-- Tint the two ranges, in place of any pair shown before; no pair when either
			-- does not lie in the text. The tint is dropped at the next change of the text.
		do
			has_bracket_pair := is_range_in_text (a_first_start, a_first_count)
				and is_range_in_text (a_second_start, a_second_count)
			if has_bracket_pair then
				pair_first_start := a_first_start
				pair_first_count := a_first_count
				pair_second_start := a_second_start
				pair_second_count := a_second_count
			end
		ensure
			shown_when_in_text: has_bracket_pair = (is_range_in_text (a_first_start, a_first_count)
				and is_range_in_text (a_second_start, a_second_count))
			first_kept: has_bracket_pair implies (pair_first_start = a_first_start and pair_first_count = a_first_count)
			second_kept: has_bracket_pair implies (pair_second_start = a_second_start and pair_second_count = a_second_count)
		end

	hide_bracket_pair
			-- No pair is tinted.
		do
			has_bracket_pair := False
		ensure
			hidden: not has_bracket_pair
		end

	press_bracket_key
			-- The user pressed the key that goes to the matching bracket: tell `on_bracket_key'.
		do
			if attached on_bracket_key as al_told then
				al_told.call (Void)
			end
		end

feature -- Completion (1v-e-4)

	completion_rows: ARRAYED_LIST [TUPLE [label, detail: STRING_32; kind: INTEGER]]
			-- The rows of the completion list; empty while none shows.
		attribute
			create Result.make (0)
		end

	completion_at: INTEGER
			-- The highlighted row; 0 while no list shows.

	is_completion_shown: BOOLEAN
			-- Does the completion list show?
		do
			Result := completion_rows.count > 0
		end

	on_completion_key: detachable PROCEDURE [INTEGER]
			-- Told 0 for Control+Space; with the list showing, 1 Up, 2 Down, 3 Page Up,
			-- 4 Page Down, 5 Return or Tab, 6 Escape, in place of the key's usual work; and 6
			-- when the list hid itself (the focus left, or the lines scrolled).

	on_completion_press: detachable PROCEDURE [INTEGER]
			-- Told the row the user clicked.

	set_on_completion_key (a_action: like on_completion_key)
		do
			on_completion_key := a_action
		end

	set_on_completion_press (a_action: like on_completion_press)
		do
			on_completion_press := a_action
		end

	show_completions (a_rows: ITERABLE [TUPLE [label, detail: STRING_32; kind: INTEGER]]; a_selected: INTEGER)
			-- The list, at the caret's line, with row `a_selected' highlighted (kept within the
			-- rows); in place of what it showed. No rows: no list.
		do
			completion_rows.wipe_out
			across a_rows as ic loop
				completion_rows.extend (ic)
			end
			completion_top := 1
			if completion_rows.is_empty then
				completion_at := 0
			else
				select_completion (a_selected)
			end
		ensure
			highlighted: is_completion_shown implies (1 <= completion_at and completion_at <= completion_rows.count)
		end

	select_completion (a_row: INTEGER)
			-- Highlight row `a_row' (kept within the rows) and scroll it into view.
		do
			if is_completion_shown then
				completion_at := a_row.max (1).min (completion_rows.count)
				if completion_at < completion_top then
					completion_top := completion_at
				elseif completion_at >= completion_top + Completion_rows_shown then
					completion_top := completion_at - Completion_rows_shown + 1
				end
			end
		end

	hide_completions
			-- No list. Tells nothing.
		do
			completion_rows.wipe_out
			completion_at := 0
			completion_top := 1
		ensure
			hidden: not is_completion_shown
		end

	press_completion_key (a_key: INTEGER)
			-- As the user pressing completion key `a_key' (0 Control+Space, 1 Up, 2 Down,
			-- 3 Page Up, 4 Page Down, 5 Return, 6 Escape): 0 always tells
			-- `on_completion_key'; 1 to 6 tell it while the list shows, and otherwise do the
			-- key's usual work.
		require
			a_key: 0 <= a_key and a_key <= 6
		do
			if a_key = 0 or is_completion_shown then
				tell_completion_key (a_key)
			else
				inspect a_key
				when 1 then
					handle_key (38, False)
				when 2 then
					handle_key (40, False)
				when 3 then
					handle_key (33, False)
				when 4 then
					handle_key (34, False)
				when 5 then
					handle_char (13)
				else
						-- Escape does nothing in a code editor
				end
			end
		end

	press_completion_row (a_row: INTEGER)
			-- As the user clicking row `a_row' of the list: tell `on_completion_press'.
			-- Nothing when no list shows or there is no such row.
		do
			if 1 <= a_row and a_row <= completion_rows.count and then attached on_completion_press as al_told then
				al_told.call (a_row)
			end
		end

	set_focused (a_focused: BOOLEAN)
			-- Also: losing the focus hides the completion list, and says so.
		do
			Precursor {GUI_SW_RICH_TEXT_AREA} (a_focused)
			if not a_focused then
				completion_hides_itself
			end
		end

feature -- Folding (1v-e-3)

	is_folding_shown: BOOLEAN
			-- Does the gutter show a marker beside each line of `fold_marks', and do the
			-- fold keys (Control+Shift+[ and Control+Shift+]) tell `on_fold'?

	fold_marks: GUI_LINE_RANGES
			-- The lines that start a fold, each as a range of that one line.
		attribute
			create Result.make
		end

	hidden_lines: GUI_LINE_RANGES
			-- The closed folds, apart and in order. The first line of each shows, with a
			-- mark after its end that lines are hidden; the lines after it through the
			-- last take no room, and neither the keys nor the pointer put the caret in
			-- them. The text is whole all the same.
		attribute
			create Result.make
		end

	on_fold: detachable PROCEDURE [INTEGER, INTEGER]
			-- Told (line, 0) when the user clicks the marker beside a line; (the caret's
			-- line, 1) on the fold key; (the caret's line, 2) on the unfold key.

	is_line_shown (a_line: INTEGER): BOOLEAN
			-- Is `a_line' a line of the text that no closed fold hides?
		do
			Result := 1 <= a_line and then a_line <= code_line_count
				and then not hidden_lines.is_hidden (a_line)
		end

	set_on_fold (an_action: detachable PROCEDURE [INTEGER, INTEGER])
		do
			on_fold := an_action
		ensure
			set: on_fold = an_action
		end

	set_folding_shown (a_on: BOOLEAN)
		do
			is_folding_shown := a_on
			is_measured := False
			keep_folded_text
		ensure
			set: is_folding_shown = a_on
		end

	set_fold_marks (a_marks: GUI_LINE_RANGES)
			-- `a_marks' in place of the last set. (Kept, and moved by the next edits.)
		do
			fold_marks := a_marks
			keep_folded_text
		ensure
			set: fold_marks = a_marks
		end

	set_hidden_lines (a_ranges: GUI_LINE_RANGES)
			-- `a_ranges' in place of the last set. (Kept, and moved by the next edits.)
		require
			apart: a_ranges.is_disjoint
		do
			hidden_lines := a_ranges
			is_style_stale := True
			keep_folded_text
		ensure
			set: hidden_lines = a_ranges
		end

	press_fold_marker (a_line: INTEGER)
			-- The user clicked the marker beside `a_line': tell `on_fold', when the line
			-- has a marker to click.
		do
			if is_folding_shown and then fold_marks.has_start (a_line) and then is_line_shown (a_line)
				and then attached on_fold as al_told
			then
				al_told.call ([a_line, 0])
			end
		end

	press_fold_key (a_unfold: BOOLEAN)
			-- The user pressed the fold key (the unfold key when `a_unfold'): tell
			-- `on_fold', when folding is shown.
		do
			if is_folding_shown and then attached on_fold as al_told then
				if a_unfold then
					al_told.call ([code_caret_line, 2])
				else
					al_told.call ([code_caret_line, 1])
				end
			end
		end

feature -- Element change

	set_on_bracket_key (an_action: detachable PROCEDURE)
		do
			on_bracket_key := an_action
		ensure
			set: on_bracket_key = an_action
		end

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
			hide_bracket_pair
			follow_edit
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
			hide_bracket_pair
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
			follow_edit
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
			-- Tab, character 8 through Backspace, every other character as itself.
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
				elseif c.code = 8 then
					handle_char (8)
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
			l_eaten: BOOLEAN
		do
			l_caret := caret
				-- the character that trails a key the completion list took (Return, Tab,
				-- Escape, or the space of Control+Space)
			l_eaten := is_completion_char_pending and (a_code = 13 or a_code = 9 or a_code = 27 or a_code = 32)
			is_completion_char_pending := False
			if l_eaten then
				do_nothing
			elseif is_read_only then
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
			-- to the ends of the text; Control+Shift+\ (key 220 on a US keyboard) asks for
			-- the matching bracket; Control+Shift+[ (219) is the fold key and
			-- Control+Shift+] (221) the unfold key; the rest as the text box. A key that
			-- would put the caret in a hidden line takes it past the fold.
			-- (The page keys count hidden lines among the rows they move.)
		local
			l_keys: SW_KEYS
			l_caret, l_line: INTEGER
			l_x, l_was_x: REAL_64
		do
			l_caret := caret
			if hidden_lines.count > 0 then
				l_was_x := caret_x
			end
			create l_keys
			if a_vk = 32 and then l_keys.control_down then
					-- Control+Space: a completion list is wanted
				is_completion_char_pending := True
				tell_completion_key (0)
			elseif is_completion_shown and then completion_key_of (a_vk) > 0 then
				is_completion_char_pending := True
				tell_completion_key (completion_key_of (a_vk))
			elseif (a_vk = 33 or a_vk = 34) and then is_laid_out then
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
			elseif a_vk = 220 and then a_shift and then l_keys.control_down then
				press_bracket_key
			elseif (a_vk = 219 or a_vk = 221) and then a_shift and then l_keys.control_down then
				press_fold_key (a_vk = 221)
			else
				Precursor {GUI_SW_RICH_TEXT_AREA} (a_vk, a_shift)
			end
			if caret /= l_caret then
				if hidden_lines.count > 0 then
					leave_hidden_line (caret > l_caret, a_vk = 38 or a_vk = 40 or a_vk = 33 or a_vk = 34, l_was_x)
				end
				is_reveal_pending := True
			end
			report_caret
		end

feature -- Pointer

	handle_click (a_px, a_py: REAL_64): BOOLEAN
			-- A press on a completion row tells `on_completion_press'; on a scrollbar it
			-- scrolls; on a fold marker it tells `on_fold'; anywhere else it places the caret.
		local
			l_line, l_row: INTEGER
		do
			is_marker_pressed := False
			if is_completion_shown then
				l_row := completion_row_at (a_px, a_py)
			end
			if l_row > 0 then
				press_completion_row (l_row)
				Result := True
			elseif press_bar (a_px, a_py) then
				completion_hides_itself
				Result := True
			elseif h_bar.contains (a_px, a_py) then
				scroll_x := h_bar.press (a_px, scroll_x)
				Result := True
			else
				if is_folding_shown and then is_laid_out and then a_px >= x + marker_left
					and then a_px < x + gutter_width
				then
					build_bands
					l_line := marker_line_at (a_py)
				end
				if l_line > 0 then
					is_marker_pressed := True
					press_fold_marker (l_line)
					Result := True
				else
					Result := Precursor {GUI_SW_RICH_TEXT_AREA} (a_px, a_py)
					is_reveal_pending := True
					report_caret
				end
			end
		end

	offset_at (a_px, a_py: REAL_64): INTEGER
			-- Among the shown lines only, while lines are hidden. (The bands are found
			-- again first: a cache, nothing a client sees.)
		do
			if hidden_lines.count = 0 or else not is_laid_out then
				Result := Precursor {GUI_SW_RICH_TEXT_AREA} (a_px, a_py)
			else
				build_bands
				Result := offset_on_line (line_at_shown_y (a_py - text_top), a_px - text_left)
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
				if hidden_lines.count > 0 then
						-- (the first line of a closed fold: its hidden lines go with it)
					leave_hidden_line (True, False, 0.0)
				end
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
			elseif is_marker_pressed then
					-- the press was a fold marker's
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
			is_marker_pressed := False
		end

	handle_wheel (a_delta: INTEGER): BOOLEAN
			-- The wheel scrolls the lines; with Shift held, the columns.
		local
			l_keys: SW_KEYS
		do
			completion_hides_itself
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
			-- Moved up by `scroll_y', and while a band is drawn by the hidden lines above it.
		do
			Result := y + Pad_y - scroll_y - fold_shift
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
			-- Every shown line, the insets above and below, and room for the bottom bar.
		do
			Result := (content_height - hidden_height).max (0.0) + 2.0 * Pad_y + bottom_room
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
			-- The field; the text clipped to its view, band by band around the hidden
			-- lines; the gutter; the two bars.
			-- Cost: the content is drawn once for each band in view: once while no closed
			-- fold is in view.
		local
			l_theme: SW_THEME
			l_geometry: SW_TEXT_GEOMETRY
			l_view_w, l_view_h, l_bar_w, l_view_top, l_view_bottom, l_top, l_bottom: REAL_64
			k, l_bands: INTEGER
		do
			l_theme := a_p.theme
			ensure_layout (a_p, wrap_width_in (width))
			build_bands
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
			l_geometry := geometry
			l_bands := band_firsts.count
			l_view_top := y + 1.0
			l_view_bottom := l_view_top + (l_view_h - 2.0).max (0.0)
			from
				k := band_at_y (scroll_y - Pad_y)
			until
				k > l_bands
			loop
				fold_shift := band_shifts [k]
				if k = 1 then
					l_top := l_view_top
				else
					l_top := (text_top + l_geometry.top_of_line (band_firsts [k])).max (l_view_top)
				end
				if k = l_bands then
					l_bottom := l_view_bottom
				else
					l_bottom := (text_top + l_geometry.top_of_line (band_lasts [k])
						+ l_geometry.height_of_line (band_lasts [k])).min (l_view_bottom)
				end
				if k > 1 and l_top >= l_view_bottom then
						-- this band and the rest are below the view
					k := l_bands
				elseif l_bottom > l_top or l_bands = 1 then
					a_p.push_clip (x + gutter_width, l_top, l_view_w, (l_bottom - l_top).max (0.0))
					if has_bracket_pair then
						draw_bracket_tint (a_p, pair_first_start, pair_first_count)
						draw_bracket_tint (a_p, pair_second_start, pair_second_count)
					end
					draw_content (a_p)
					if band_lasts [k] < l_geometry.line_count - 1 then
						draw_hidden_mark (a_p, band_lasts [k])
					end
					a_p.pop_clip
				end
				k := k + 1
			end
			fold_shift := 0.0
			if gutter_width > 0.0 then
				draw_gutter (a_p, l_view_h)
			end
			draw_bar (a_p)
			h_bar.draw (a_p, scroll_x, shows_hover and then h_bar.contains (hover_px, hover_py))
			if is_completion_shown then
				draw_completions (a_p)
			end
		end

	draw_completions (a_p: SW_PAINTER)
			-- The completion list over the text: under the caret's line, or above it when
			-- there is no room below in the view; at most `Completion_rows_shown' rows from
			-- `completion_top', each with its kind's mark, its label and, at the right, its
			-- detail in the muted ink.
		require
			showing: is_completion_shown
			laid_out: is_laid_out
		local
			l_theme: SW_THEME
			r: like completion_drawn
			i: INTEGER
			l_y, l_base: REAL_64
			l_row: TUPLE [label, detail: STRING_32; kind: INTEGER]
		do
			l_theme := a_p.theme
			r := completion_rect (a_p)
			completion_drawn := r
			a_p.set_color (l_theme.surface)
			a_p.rrect_fill (r.x, r.y, r.w, r.h, 4.0)
			a_p.set_color (l_theme.outline)
			a_p.rrect_stroke (r.x + 0.5, r.y + 0.5, r.w - 1.0, r.h - 1.0, 4.0)
			from
				i := completion_top
			until
				i > completion_rows.count or i >= completion_top + Completion_rows_shown
			loop
				l_row := completion_rows [i]
				l_y := r.y + 2.0 + (i - completion_top) * r.row
				l_base := a_p.baseline_in (l_y, r.row)
				if i = completion_at then
					a_p.set_color (l_theme.wash_accent)
					a_p.fill_rect (r.x + 2.0, l_y, r.w - 4.0, r.row)
				end
				if l_row.kind > 0 then
					a_p.set_color (l_theme.ink_accent)
					a_p.text (r.x + 8.0, l_base, kind_mark (l_row.kind))
				end
				a_p.set_color (l_theme.ink)
				a_p.text (r.x + Completion_label_x, l_base, l_row.label)
				if not l_row.detail.is_empty then
					a_p.set_color (l_theme.ink_muted)
					a_p.text (r.x + r.w - 10.0 - a_p.advance (l_row.detail), l_base, l_row.detail)
				end
				i := i + 1
			end
		end

	draw_bracket_tint (a_p: SW_PAINTER; a_start, a_count: INTEGER)
			-- The theme's accent wash under the `a_count' characters from `a_start', before
			-- the glyphs are drawn over it.
		require
			laid_out: is_laid_out
			in_text: is_range_in_text (a_start, a_count)
		local
			i, l_line: INTEGER
			l_geometry: SW_TEXT_GEOMETRY
		do
			l_geometry := geometry
			a_p.set_color (a_p.theme.wash_accent)
			from i := a_start until i >= a_start + a_count loop
				if l_geometry.width_of (i) > 0.0 then
					l_line := l_geometry.line_of (i)
					a_p.fill_rect (text_left + l_geometry.x_of (i), text_top + l_geometry.top_of_line (l_line),
						l_geometry.width_of (i), l_geometry.height_of_line (l_line))
				end
				i := i + 1
			end
		end

feature {NONE} -- Completion

	completion_rect (a_p: SW_PAINTER): TUPLE [x, y, w, h, row: REAL_64]
			-- Where the list goes: as wide as its widest row needs (within the view), under
			-- the caret's line, or above it when the rows do not fit below and do above.
			-- Leaves `a_p' set to the list's font.
		require
			showing: is_completion_shown
			laid_out: is_laid_out
			built: band_firsts.count >= 1
		local
			l_row, l_w, l_h, l_top, l_bottom, l_x: REAL_64
			l_line: INTEGER
		do
			a_p.font ({SW_PAINTER}.Role_ui, a_p.theme.size_label, False)
			l_row := 22.0 * a_p.theme.text_scale
			l_h := completion_rows.count.min (Completion_rows_shown) * l_row + 4.0
			l_w := 160.0
			across completion_rows as ic loop
				l_w := l_w.max (Completion_label_x + a_p.advance (ic.label) + 24.0 + a_p.advance (ic.detail) + 10.0)
			end
			l_w := l_w.min ((width - gutter_width).max (40.0))
			l_line := caret_line
			l_top := text_top + shown_top (l_line)
			l_bottom := l_top + geometry.height_of_line (l_line)
			l_x := (text_left + caret_x).min (x + width - l_w).max (x + gutter_width)
			if l_bottom + 2.0 + l_h > y + height and then l_top - 2.0 - l_h >= y then
				Result := [l_x, l_top - 2.0 - l_h, l_w, l_h, l_row]
			else
				Result := [l_x, l_bottom + 2.0, l_w, l_h, l_row]
			end
		end

	Completion_rows_shown: INTEGER = 8
			-- The list's height in rows; more scroll.

	Completion_label_x: REAL_64 = 26.0
			-- Where a row's label starts, after its kind's mark.

	completion_top: INTEGER
			-- The first row in view.

	completion_drawn: TUPLE [x, y, w, h, row: REAL_64]
			-- Where the list was last drawn, for the pointer.
		attribute
			Result := [0.0, 0.0, 0.0, 0.0, 0.0]
		end

	is_completion_char_pending: BOOLEAN
			-- Did the completion list take a key whose character is still to come?

	completion_key_of (a_vk: INTEGER): INTEGER
			-- The completion key for virtual key `a_vk' while the list shows; 0 for none.
		do
			inspect a_vk
			when 38 then Result := 1
			when 40 then Result := 2
			when 33 then Result := 3
			when 34 then Result := 4
			when 13, 9 then Result := 5
			when 27 then Result := 6
			else
			end
		ensure
			a_key: 0 <= Result and Result <= 6
		end

	tell_completion_key (a_key: INTEGER)
		do
			if attached on_completion_key as al_told then
				al_told.call (a_key)
			end
		end

	completion_hides_itself
			-- The focus left or the lines scroll: no list, and `on_completion_key' hears 6.
		do
			if is_completion_shown then
				hide_completions
				tell_completion_key (6)
			end
		ensure
			hidden: not is_completion_shown
		end

	completion_row_at (a_px, a_py: REAL_64): INTEGER
			-- The list's row at the point, as last drawn; 0 for none.
		local
			r: like completion_drawn
		do
			r := completion_drawn
			if r.row > 0.0 and then a_px >= r.x and then a_px < r.x + r.w
				and then a_py >= r.y + 2.0 and then a_py < r.y + r.h - 2.0
			then
				Result := completion_top + ((a_py - r.y - 2.0) / r.row).truncated_to_integer
				if Result > completion_rows.count then
					Result := 0
				end
			end
		end

	kind_mark (a_kind: INTEGER): STRING_32
			-- The small mark before a row of kind `a_kind'.
		do
			inspect a_kind
			when 1 then Result := {STRING_32} "k"
			when 2 then Result := {STRING_32} "T"
			when 3 then Result := {STRING_32} "f"
			when 4 then Result := {STRING_32} "v"
			when 5 then Result := {STRING_32} "s"
			else Result := {STRING_32} ""
			end
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
			-- An edit: the bracket tint goes; report the edit, then the caret's new place.
		do
			hide_bracket_pair
			follow_edit
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
			-- Build the marks (the colors) of the shown lines a view `a_view_h' high holds,
			-- when the styles or the hidden lines changed or the view moved.
		require
			laid_out: is_laid_out
			built: band_firsts.count >= 1
		local
			l_first, l_last, l_line_a, l_line_b, k: INTEGER
			l_geometry: SW_TEXT_GEOMETRY
		do
			l_geometry := geometry
			l_line_a := line_at_shown_y (scroll_y - Pad_y)
			l_line_b := line_at_shown_y (scroll_y - Pad_y + a_view_h)
			l_first := l_geometry.line_start (l_line_a) + 1
			l_last := l_geometry.line_end (l_line_b)
			if is_style_stale or l_first /= marked_first or l_last /= marked_last then
				sync
				if band_firsts.count = 1 then
					apply_marks (l_first, l_last.min (styles.count))
				else
						-- band by band: a hidden line gets no mark
					apply_marks (1, 0)
					from
						k := band_of_line (l_line_a)
					until
						k > band_firsts.count or else band_firsts [k] > l_line_b
					loop
						add_marks (l_geometry.line_start (band_firsts [k].max (l_line_a)) + 1,
							l_geometry.line_end (band_lasts [k].min (l_line_b)).min (styles.count))
						k := k + 1
					end
				end
				marked_first := l_first
				marked_last := l_last
				is_style_stale := False
			end
		ensure
			fresh: not is_style_stale
		end

	measure_code (a_p: SW_PAINTER)
			-- The gutter, the row and the widest line of the layout just made. The gutter
			-- is the numbers' column, then the fold markers', between two paddings.
		require
			laid_out: is_laid_out
		local
			l_geometry: SW_TEXT_GEOMETRY
			l_numbers: REAL_64
		do
			l_geometry := geometry
			row_pitch := l_geometry.height_of_line (0)
			if is_line_numbers_shown then
				a_p.font (face_role, body_size (a_p), False)
				l_numbers := a_p.advance ("8") * l_geometry.line_count.out.count.max (2)
			end
			if is_folding_shown then
				marker_width := (row_pitch * 0.75).floor
			else
				marker_width := 0.0
			end
			if is_line_numbers_shown or is_folding_shown then
				gutter_width := l_numbers + marker_width + 2.0 * a_p.theme.padding
			else
				gutter_width := 0.0
			end
			marker_left := l_numbers + a_p.theme.padding
			widest_line := l_geometry.rightmost_edge
			is_measured := True
		ensure
			measured: is_measured
		end

	reveal_caret (a_view_w, a_view_h: REAL_64)
			-- Scroll the least that puts the caret inside a view of that size.
		require
			laid_out: is_laid_out
			built: band_firsts.count >= 1
		local
			l_line: INTEGER
			l_top, l_bottom, l_x: REAL_64
		do
			l_line := caret_line
			l_top := shown_top (l_line)
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
			-- The numbers of the shown lines in view, right-aligned; the fold markers
			-- beside them; the rule at the gutter's edge.
		require
			laid_out: is_laid_out
			built: band_firsts.count >= 1
		local
			l_theme: SW_THEME
			l_geometry: SW_TEXT_GEOMETRY
			i, k, l_first, l_last, l_band_last: INTEGER
			l_number: STRING_32
			l_right, l_clip_h, l_top: REAL_64
		do
			l_theme := a_p.theme
			l_geometry := geometry
			l_clip_h := (a_view_h - 2.0).max (0.0)
			a_p.push_clip (x, y + 1.0, gutter_width, l_clip_h)
			a_p.font (face_role, body_size (a_p), False)
			a_p.set_color (l_theme.ink_muted)
			l_right := x + marker_left
			l_first := line_at_shown_y (scroll_y - Pad_y)
			l_last := line_at_shown_y (scroll_y - Pad_y + a_view_h)
			from
				k := band_of_line (l_first)
			until
				k > band_firsts.count or else band_firsts [k] > l_last
			loop
				from
					i := band_firsts [k].max (l_first)
					l_band_last := band_lasts [k].min (l_last)
				until
					i > l_band_last
				loop
					l_top := text_top + l_geometry.top_of_line (i) - band_shifts [k]
					if is_line_numbers_shown then
						l_number := (i + 1).out.to_string_32
						a_p.text (l_right - a_p.advance (l_number), l_top + l_geometry.ascent_of_line (i), l_number)
					end
					if is_folding_shown and then fold_marks.has_start (i + 1) then
						draw_fold_marker (a_p, l_top, l_geometry.height_of_line (i), hidden_lines.has_start (i + 1))
					end
					i := i + 1
				end
				k := k + 1
			end
			a_p.set_color (l_theme.outline)
			a_p.fill_rect (x + gutter_width - 1.0, y + 1.0, 1.0, l_clip_h)
			a_p.pop_clip
		end

	marker_line_at (a_py: REAL_64): INTEGER
			-- The line (from 1) whose fold marker is at window height `a_py'; 0 when no
			-- marker is there.
		require
			laid_out: is_laid_out
			built: band_firsts.count >= 1
		local
			l_line: INTEGER
			l_dy, l_top: REAL_64
		do
			l_dy := a_py - text_top
			l_line := line_at_shown_y (l_dy)
			l_top := shown_top (l_line)
			if l_dy >= l_top and then l_dy < l_top + geometry.height_of_line (l_line)
				and then fold_marks.has_start (l_line + 1)
			then
				Result := l_line + 1
			end
		ensure
			none_or_marked: Result = 0 or else fold_marks.has_start (Result)
		end

	is_marker_pressed: BOOLEAN
			-- Did the last press land on a fold marker? (Its drag selects nothing.)

	folded_text: detachable STRING_32
			-- The text as it was when the fold marks and the hidden lines last fitted it;
			-- kept only while there is one of them to take through the next edit.

	fold_shift: REAL_64
			-- While a band is drawn: the height of the hidden lines above it. (0 outside
			-- `draw'.)

	marker_left, marker_width: REAL_64
			-- The fold markers' column in the gutter, from `x' (no width when folding is
			-- not shown), as last measured.

	hidden_height: REAL_64
			-- The height of every hidden line together, as of the last `build_bands'.

	band_firsts, band_lasts: ARRAYED_LIST [INTEGER]
			-- The bands: the stretches of shown lines between the hidden ones, in layout
			-- lines from 0. One band of every line when nothing is hidden. As of the last
			-- `build_bands'.
		attribute
			create Result.make (4)
		end

	band_shifts: ARRAYED_LIST [REAL_64]
			-- For each band, the height of the hidden lines above it.
		attribute
			create Result.make (4)
		end

	keep_folded_text
			-- Keep a copy of the text while an edit would have something to move.
		do
			if is_folding_shown or hidden_lines.count > 0 or fold_marks.count > 0 then
				folded_text := text.twin
			else
				folded_text := Void
			end
		end

	follow_edit
			-- The text changed: the hidden lines and the fold marks follow the edit by the
			-- rule of GUI_LINE_RANGES, so the frame drawn before the editor has answered
			-- hides what was hidden.
			-- Cost, while there is a mark or a hidden line: one comparison of the texts
			-- and one copy.
		do
			if attached folded_text as al_old then
				hidden_lines.follow_both (al_old, text, fold_marks)
				is_style_stale := True
			end
			keep_folded_text
		end

	build_bands
			-- Find the bands and `hidden_height' from `hidden_lines' and the layout.
			-- (A range the layout does not reach hides nothing here.)
		require
			laid_out: is_laid_out
		local
			l_geometry: SW_TEXT_GEOMETRY
			i, l_lines, l_next, l_hidden, l_after: INTEGER
			l_shift: REAL_64
		do
			l_geometry := geometry
			l_lines := l_geometry.line_count
			band_firsts.wipe_out
			band_lasts.wipe_out
			band_shifts.wipe_out
			from
				i := 1
			until
				i > hidden_lines.count or l_next >= l_lines
			loop
					-- range `i' hides lines first + 1 to last: layout lines first to last - 1
				l_hidden := hidden_lines.first_line (i)
				l_after := hidden_lines.last_line (i).min (l_lines)
				if l_hidden > l_next and l_hidden < l_after then
					band_firsts.extend (l_next)
					band_lasts.extend (l_hidden - 1)
					band_shifts.extend (l_shift)
					if l_after < l_lines then
						l_shift := l_shift + l_geometry.top_of_line (l_after) - l_geometry.top_of_line (l_hidden)
					else
						l_shift := l_shift + l_geometry.content_height - l_geometry.top_of_line (l_hidden)
					end
					l_next := l_after
				end
				i := i + 1
			end
			if l_next < l_lines then
				band_firsts.extend (l_next)
				band_lasts.extend (l_lines - 1)
				band_shifts.extend (l_shift)
			end
			hidden_height := l_shift
		ensure
			a_band: band_firsts.count >= 1
			matched: band_lasts.count = band_firsts.count and band_shifts.count = band_firsts.count
			from_the_top: band_firsts.first = 0
			nothing_hidden_one_band: hidden_lines.count = 0 implies (band_firsts.count = 1 and hidden_height = 0.0)
		end

	band_of_line (a_line: INTEGER): INTEGER
			-- The band that holds layout line `a_line'; for a hidden line, the band that
			-- ends on the first line of its fold.
		require
			built: band_firsts.count >= 1
		local
			l_low, l_high, l_middle: INTEGER
		do
			from
				Result := 1
				l_low := 2
				l_high := band_firsts.count
			until
				l_low > l_high
			loop
				l_middle := l_low + (l_high - l_low) // 2
				if band_firsts [l_middle] <= a_line then
					Result := l_middle
					l_low := l_middle + 1
				else
					l_high := l_middle - 1
				end
			end
		ensure
			a_band: 1 <= Result and Result <= band_firsts.count
		end

	band_at_y (a_dy: REAL_64): INTEGER
			-- The band shown at `a_dy' below the top of the first line; the first band
			-- above them all, the last below.
		require
			built: band_firsts.count >= 1
			laid_out: is_laid_out
		local
			l_low, l_high, l_middle: INTEGER
			l_geometry: SW_TEXT_GEOMETRY
		do
			l_geometry := geometry
			from
				Result := 1
				l_low := 2
				l_high := band_firsts.count
			until
				l_low > l_high
			loop
				l_middle := l_low + (l_high - l_low) // 2
				if l_geometry.top_of_line (band_firsts [l_middle]) - band_shifts [l_middle] <= a_dy then
					Result := l_middle
					l_low := l_middle + 1
				else
					l_high := l_middle - 1
				end
			end
		ensure
			a_band: 1 <= Result and Result <= band_firsts.count
		end

	line_at_shown_y (a_dy: REAL_64): INTEGER
			-- The shown layout line at `a_dy' below the top of the first line; the
			-- nearest shown line when none is there.
		require
			built: band_firsts.count >= 1
			laid_out: is_laid_out
		local
			k: INTEGER
		do
			k := band_at_y (a_dy)
			Result := geometry.line_at_y (a_dy + band_shifts [k]).max (band_firsts [k]).min (band_lasts [k])
		ensure
			a_line: 0 <= Result and Result < geometry.line_count
		end

	shown_top (a_line: INTEGER): REAL_64
			-- Where layout line `a_line' starts below the top of the first line, the
			-- hidden lines above it taken out.
		require
			built: band_firsts.count >= 1
			laid_out: is_laid_out
			a_line: 0 <= a_line and a_line < geometry.line_count
		do
			Result := geometry.top_of_line (a_line) - band_shifts [band_of_line (a_line)]
		end

	leave_hidden_line (a_forward, a_keep_x: BOOLEAN; a_x: REAL_64)
			-- When a key has put the caret in a hidden line, take it on to the first line
			-- shown after the fold (`a_forward') or back to the fold's first line; at
			-- `a_x' from the text's left edge when `a_keep_x' (the keys that go up and
			-- down), else at the start of the line after and at the end of the first
			-- line. With no line after the fold, to the end of its first line.
		local
			k, l_first, l_last: INTEGER
			l_collapsed: BOOLEAN
		do
			k := hidden_lines.index_hiding (code_caret_line)
			if k > 0 then
				l_collapsed := sel_anchor = caret
				l_first := hidden_lines.first_line (k)
				l_last := hidden_lines.last_line (k)
				if a_forward and l_last < code_line_count then
					if a_keep_x and is_laid_out then
						caret := offset_on_line (l_last, a_x)
					else
						caret := code_line_start (l_last + 1)
					end
				elseif a_keep_x and not a_forward and is_laid_out then
					caret := offset_on_line (l_first - 1, a_x)
				else
					caret := end_of_line_at (code_line_start (l_first))
				end
				if l_collapsed then
					sel_anchor := caret
				end
			end
		ensure
			out_of_it: not hidden_lines.is_hidden (code_caret_line)
		end

	draw_fold_marker (a_p: SW_PAINTER; a_top, a_height: REAL_64; a_closed: BOOLEAN)
			-- A triangle in the markers' column of the row at `a_top': pointing down for
			-- an open fold, to the right for a closed one.
		local
			l_cx, l_cy, l_r: REAL_64
		do
			l_cx := x + marker_left + marker_width / 2.0
			l_cy := a_top + a_height / 2.0
			l_r := marker_width * 0.3
			if a_closed then
				a_p.triangle_fill (l_cx - l_r * 0.6, l_cy - l_r, l_cx - l_r * 0.6, l_cy + l_r, l_cx + l_r * 0.8, l_cy)
			else
				a_p.triangle_fill (l_cx - l_r, l_cy - l_r * 0.6, l_cx + l_r, l_cy - l_r * 0.6, l_cx, l_cy + l_r * 0.8)
			end
		end

	draw_hidden_mark (a_p: SW_PAINTER; a_line: INTEGER)
			-- After the end of layout line `a_line', the first line of a closed fold: an
			-- ellipsis in a box, the mark that lines are hidden here.
		require
			laid_out: is_laid_out
			a_line: 0 <= a_line and a_line < geometry.line_count
		local
			l_theme: SW_THEME
			l_geometry: SW_TEXT_GEOMETRY
			l_left, l_top, l_width, l_height, l_inset: REAL_64
			l_dots: STRING_32
		do
			l_theme := a_p.theme
			l_geometry := geometry
			l_dots := {STRING_32} "%/8230/"
			a_p.font (face_role, body_size (a_p), False)
			l_inset := l_theme.padding / 2.0
			l_left := text_left + l_geometry.x_at_offset (l_geometry.line_end (a_line)) + l_theme.padding
			l_top := text_top + l_geometry.top_of_line (a_line)
			l_height := l_geometry.height_of_line (a_line)
			l_width := a_p.advance (l_dots) + 2.0 * l_inset
			a_p.set_color (l_theme.outline)
			a_p.rrect_stroke (l_left, l_top + 1.0, l_width, (l_height - 2.0).max (0.0), l_theme.radius)
			a_p.set_color (l_theme.ink_muted)
			a_p.text (l_left + l_inset, l_top + l_geometry.ascent_of_line (a_line), l_dots)
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
	hidden_apart: hidden_lines.is_disjoint
	bands_matched: band_lasts.count = band_firsts.count and band_shifts.count = band_firsts.count
	pair_in_text: has_bracket_pair implies (is_range_in_text (pair_first_start, pair_first_count)
		and is_range_in_text (pair_second_start, pair_second_count))

end
