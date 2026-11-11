note
	description: "[
		A code editor (1v-b): a GUI_RICH_TEXT_AREA with a gutter of line numbers, a monospace
		font, no wrapping, auto-indent (Return keeps the line's indentation; Tab and Shift+Tab
		indent and unindent the selected lines), syntax highlighting, and find and replace.

		Highlighting is by rules (`add_keywords', `add_line_comment', `add_delimited') or by
		an agent (`set_highlighter'). It runs in Eiffel on the lines an edit touched, then on
		the lines after them while the state they start in (inside a block comment, say)
		changes; never on the whole text per keystroke. The styles' colors come from the
		theme and follow dark mode.

		Cost: the control says only that the text changed, so each edit reads the whole text
		and finds the changed lines from what it shares with the text as last highlighted
		(GUI_TEXT_COMPARISON): one comparison of memory and one count of line breaks, no
		list of lines. The highlighter itself is called for the changed lines alone.
	]"

class
	GUI_CODE_EDITOR

inherit
	GUI_RICH_TEXT_AREA
		redefine
			make, set_text, dispatch
		end

	GUI_TEXT_COMPARISON

create
	make

feature {NONE} -- Initialization

	make
		do
			create change_actions.make
			create caret_actions.make
			create keywords.make (32)
			create line_comments.make (2)
			create delimiters.make (2)
			create highlighted.make_empty
			create starts.make (64)
			is_case_sensitive := True
			tab_width := 4
			register (backend.code_editor)
			change_actions.extend (agent rehighlight)
			application.appearance_changed_actions.extend (agent (d: BOOLEAN) do highlight_all end)
		end

feature -- Styles

	Style_plain: INTEGER = 0
	Style_keyword: INTEGER = 1
	Style_type: INTEGER = 2
	Style_string: INTEGER = 3
	Style_comment: INTEGER = 4
	Style_number: INTEGER = 5
	Style_operator: INTEGER = 6

	is_valid_style (a_style: INTEGER): BOOLEAN
		do
			Result := a_style >= Style_plain and a_style <= Style_operator
		end

	style_color (a_style: INTEGER): NATURAL_32
			-- The theme's color for `a_style', light or dark.
		require
			valid: is_valid_style (a_style)
		do
			if application.is_dark then
				inspect a_style
				when Style_keyword then Result := 0xC586C0
				when Style_type then Result := 0x4EC9B0
				when Style_string then Result := 0xCE9178
				when Style_comment then Result := 0x6A9955
				when Style_number then Result := 0xB5CEA8
				when Style_operator then Result := 0xD4D4D4
				else Result := 0xD4D4D4
				end
			else
				inspect a_style
				when Style_keyword then Result := 0x0000C0
				when Style_type then Result := 0x267F99
				when Style_string then Result := 0xA31515
				when Style_comment then Result := 0x008000
				when Style_number then Result := 0x098658
				when Style_operator then Result := 0x333333
				else Result := 0x1E1E1E
				end
			end
		end

feature -- Display

	is_line_numbers_shown: BOOLEAN
		do
			Result := not line_numbers_hidden
		end

	tab_width: INTEGER

	is_indent_with_spaces: BOOLEAN

	set_line_numbers_shown (a_on: BOOLEAN)
		require
			gui_thread: is_gui_thread
		do
			line_numbers_hidden := not a_on
			backend.code_set_line_numbers (id, a_on)
		ensure
			set: is_line_numbers_shown = a_on
		end

	set_tab_width (a_width: INTEGER)
		require
			gui_thread: is_gui_thread
			sensible: 1 <= a_width and a_width <= 16
		do
			tab_width := a_width
			backend.code_set_indent (id, a_width, is_indent_with_spaces)
		ensure
			set: tab_width = a_width
		end

	set_indent_with_spaces (a_on: BOOLEAN)
		require
			gui_thread: is_gui_thread
		do
			is_indent_with_spaces := a_on
			backend.code_set_indent (id, tab_width, a_on)
		ensure
			set: is_indent_with_spaces = a_on
		end

feature -- Lines and the caret

	line_count: INTEGER
		do
			Result := backend.text_line_count (id)
		end

	caret_line: INTEGER
			-- The caret's line, from 1.
		do
			Result := backend.text_caret_line (id)
		end

	caret_column: INTEGER
			-- The caret's column, from 1, in characters.
		do
			Result := backend.text_caret_column (id)
		end

	line_text (n: INTEGER): STRING_32
			-- Line `n''s text, without its line break.
		require
			valid: 1 <= n and n <= line_count
		do
			Result := backend.from_c (backend.text_line_text (id, n))
		end

	go_to_line (n: INTEGER)
			-- The caret at the start of line `n', scrolled into view; no event.
		require
			gui_thread: is_gui_thread
			valid: 1 <= n and n <= line_count
		do
			backend.text_go_to_line (id, n)
		ensure
			there: caret_line = n and caret_column = 1
		end

	caret_actions: GUI_ACTIONS [TUPLE [line, column: INTEGER]]
			-- Run when the user moves the caret (for a status bar).

feature -- Highlighting by rules

	is_case_sensitive: BOOLEAN

	set_case_sensitive (a_on: BOOLEAN)
		do
			is_case_sensitive := a_on
			highlight_all
		end

	add_keywords (a_words: ARRAY [READABLE_STRING_GENERAL]; a_style: INTEGER)
		require
			valid_style: is_valid_style (a_style)
		do
			across a_words as ic loop
				keywords.force (a_style, word_key (ic.to_string_32))
			end
			highlight_all
		end

	add_line_comment (a_prefix: READABLE_STRING_GENERAL; a_style: INTEGER)
			-- From `a_prefix' to the line's end.
		require
			has_prefix: not a_prefix.is_empty
			valid_style: is_valid_style (a_style)
		do
			line_comments.extend ([a_prefix.to_string_32, a_style])
			highlight_all
		end

	add_delimited (an_open, a_close: READABLE_STRING_GENERAL; a_style: INTEGER)
			-- From `an_open' to `a_close' (strings, block comments), across lines; a close of ""
			-- ends at the line's end.
		require
			has_open: not an_open.is_empty
			valid_style: is_valid_style (a_style)
		do
			delimiters.extend ([an_open.to_string_32, a_close.to_string_32, a_style])
			highlight_all
		end

feature -- Highlighting by an agent

	set_highlighter (a_function: detachable FUNCTION [STRING_32, INTEGER, TUPLE [spans: LIST [TUPLE [start, length, style: INTEGER]]; state: INTEGER]])
			-- `a_function' gets a line and the state it starts in (0 at the text's start), and
			-- answers the line's spans (start from 1, in characters) and the state the next line
			-- starts in. Void: the rules.
		do
			highlighter := a_function
			highlight_all
		end

feature -- Find and replace

	find_next (a_text: READABLE_STRING_GENERAL; a_case_sensitive, a_whole_word: BOOLEAN): BOOLEAN
			-- Select the next match after the selection, wrapping; False when there is none.
		require
			gui_thread: is_gui_thread
			has_text: not a_text.is_empty
		do
			Result := find_from (a_text, a_case_sensitive, a_whole_word, True)
		end

	find_previous (a_text: READABLE_STRING_GENERAL; a_case_sensitive, a_whole_word: BOOLEAN): BOOLEAN
		require
			gui_thread: is_gui_thread
			has_text: not a_text.is_empty
		do
			Result := find_from (a_text, a_case_sensitive, a_whole_word, False)
		end

	replace_selection (a_text: READABLE_STRING_GENERAL)
			-- Put `a_text' in place of the selection (or at the caret), selected.
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.text_replace_range (id, selection_start, selection_end, l_c.item)
			highlight_all
		end

	replace_all (a_text, a_with: READABLE_STRING_GENERAL; a_case_sensitive, a_whole_word: BOOLEAN): INTEGER
			-- Replace every match, as one undo step; answer how many.
		require
			gui_thread: is_gui_thread
			has_text: not a_text.is_empty
		local
			l_text, l_out: STRING_32
			i, j: INTEGER
			l_c: C_STRING
		do
			l_text := text
			create l_out.make (l_text.count)
			from i := 1 until i > l_text.count loop
				j := match_at_or_after (l_text, a_text, i, a_case_sensitive, a_whole_word)
				if j = 0 then
					l_out.append (l_text.substring (i, l_text.count))
					i := l_text.count + 1
				else
					l_out.append (l_text.substring (i, j - 1))
					l_out.append_string_general (a_with)
					i := j + a_text.count
					Result := Result + 1
				end
			end
			if Result > 0 then
				l_c := backend.to_c (l_out)
				backend.text_replace_range (id, 1, count, l_c.item)
				highlight_all
			end
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
			-- 52: the user moved the caret (line, column); else as a text area.
		do
			if a_type = 52 then
				caret_actions.call ([a_a, a_b])
			else
				Precursor (a_type, a_a, a_b, a_c)
			end
		end

feature -- Element change

	set_text (a_text: READABLE_STRING_GENERAL)
		do
			Precursor (a_text)
			highlight_all
		end

	highlight_all
			-- Highlight every line again (after a rule change or a new text).
		do
			starts.wipe_out
			rehighlight
		end

feature {NONE} -- Highlighting

	keywords: HASH_TABLE [INTEGER, STRING_32]
	line_comments: ARRAYED_LIST [TUPLE [prefix_text: STRING_32; style: INTEGER]]
	delimiters: ARRAYED_LIST [TUPLE [open, close: STRING_32; style: INTEGER]]
	highlighter: detachable FUNCTION [STRING_32, INTEGER, TUPLE [spans: LIST [TUPLE [start, length, style: INTEGER]]; state: INTEGER]]
	line_numbers_hidden: BOOLEAN

	highlighted: STRING_32
			-- The text as last highlighted.

	starts: ARRAYED_LIST [INTEGER]
			-- The state each line of `highlighted' started in; empty when every line is
			-- to be highlighted again.

	rehighlight
			-- Highlight the lines that changed since `highlighted', then the following ones
			-- while the state they start in differs from before.
			-- The changed lines are found from the characters the two texts share at their
			-- start and at their end (as whole lines, the first that differs from the top and
			-- the last from the bottom), and each is cut from the text as it is painted: no
			-- list of the lines is made. With 10,000 lines the split into lines cost 15 ms
			-- of every keystroke, more than the highlighting it saved.
		local
			l_text, l_line: STRING_32
			l_head, l_tail, l_limit, l_count, l_old_count, l_kept: INTEGER
			l_first, l_last_new, l_last_old, i, j, l_offset, l_end, l_state: INTEGER
			l_starts: ARRAYED_LIST [INTEGER]
			l_done: BOOLEAN
		do
			l_text := text
			l_count := l_text.occurrences ('%N') + 1
			l_old_count := starts.count
			if l_old_count = 0 then
				l_first := 1
				l_offset := 1
				l_last_new := l_count
			else
				l_limit := l_text.count.min (highlighted.count)
				l_head := shared_head (l_text, highlighted, l_limit)
				l_tail := shared_tail (l_text, highlighted, l_limit)
				if l_head = l_limit and l_text.count = highlighted.count then
						-- the same text again (one edit reported twice): every line stands
				elseif l_head + l_tail > l_limit then
						-- The shared start and the shared end overlap: a stretch that repeats
						-- ("do%Ndo" given one more "do" line). The texts alone do not say where
						-- in the overlap the edit was, and the control's colors followed the
						-- real edit, so every line of the overlap is highlighted.
					i := l_head
					l_head := l_limit - l_tail
					l_tail := l_limit - i
				end
					-- the first line that differs, from the top
				l_first := line_breaks_in (l_text, 1, l_head) + 1
				if l_head > 0 then l_offset := l_text.last_index_of ('%N', l_head) + 1 else l_offset := 1 end
				if is_line_end (l_text, l_head) and is_line_end (highlighted, l_head) then
						-- the line the texts part in is the same in both: one text ends there
					l_first := l_first + 1
					l_offset := l_head + 2
				end
					-- and the last, matching whole lines from the bottom, never past the first
				l_kept := line_breaks_in (l_text, l_text.count - l_tail + 1, l_text.count)
				if is_line_start (l_text, l_tail) and is_line_start (highlighted, l_tail) then
					l_kept := l_kept + 1
				end
				l_kept := l_kept.min (l_count - l_first + 1).min (l_old_count - l_first + 1)
				l_last_new := l_count - l_kept
				l_last_old := l_old_count - l_kept
			end
			create l_starts.make (l_count)
			from i := 1 until i >= l_first loop
				l_starts.extend (starts [i])
				i := i + 1
			end
			if l_first > 1 and l_first <= l_count then
					-- the state the first changed line starts in, from the line before it
				j := l_offset - 2
				if j >= 1 then l_end := l_text.last_index_of ('%N', j) + 1 else l_end := 1 end
				l_state := next_state (l_text.substring (l_end, j), l_starts [l_first - 1])
			end
			from
				i := l_first
			until
				i > l_count or l_done
			loop
				j := i - l_last_new + l_last_old
				if i > l_last_new and then j >= 1 and then j <= l_old_count and then starts [j] = l_state then
						-- past the edit, and this line starts as it did: the rest stands
					l_done := True
				else
					l_end := l_text.index_of ('%N', l_offset)
					if l_end = 0 then l_end := l_text.count + 1 end
					l_line := l_text.substring (l_offset, l_end - 1)
					l_starts.extend (l_state)
					paint_line (l_line, l_offset, l_state)
					l_state := next_state (l_line, l_state)
					l_offset := l_end + 1
					i := i + 1
				end
			end
			if l_done then
					-- the unchanged tail keeps its states, shifted to the new lines
				from until i > l_count loop
					l_starts.extend (starts [i - l_last_new + l_last_old])
					i := i + 1
				end
			end
			highlighted := l_text
			starts := l_starts
		ensure
			one_start_each: starts.count = highlighted.occurrences ('%N') + 1
		end

	is_line_end (a_text: READABLE_STRING_32; a_before: INTEGER): BOOLEAN
			-- Does a line of `a_text' end after its first `a_before' characters?
		require
			in_text: 0 <= a_before and a_before <= a_text.count
		do
			Result := a_before = a_text.count or else a_text.item (a_before + 1) = '%N'
		end

	is_line_start (a_text: READABLE_STRING_32; a_after: INTEGER): BOOLEAN
			-- Does a line of `a_text' start at its last `a_after' characters?
		require
			in_text: 0 <= a_after and a_after <= a_text.count
		do
			Result := a_after = a_text.count or else a_text.item (a_text.count - a_after) = '%N'
		end

	paint_line (a_line: STRING_32; an_offset, a_state: INTEGER)
			-- Color line `a_line', which starts at `an_offset' in the text.
		do
			if not a_line.is_empty then
				color_run (an_offset, an_offset + a_line.count - 1, style_color (Style_plain))
				across spans_of (a_line, a_state) as ic loop
					if ic.length > 0 and then ic.start >= 1 and then ic.start + ic.length - 1 <= a_line.count and then is_valid_style (ic.style) then
						color_run (an_offset + ic.start - 1, an_offset + ic.start + ic.length - 2, style_color (ic.style))
					end
				end
			end
		end

	color_run (a_start, an_end: INTEGER; a_color: NATURAL_32)
			-- Color characters `a_start' to `an_end': `set_text_color' without its check of
			-- the range against `count', which fetches the whole text from the backend. The
			-- highlighter cuts its runs from the text it has just read, so each one lies in
			-- the text, and a 10,000-line text has some 60,000 of them: checked the general
			-- way, coloring it would fetch the text 60,000 times.
		require
			ordered: 1 <= a_start and a_start <= an_end
			rgb: a_color <= 0xFFFFFF
		do
			backend.rich_text_set_color (id, a_start, an_end, a_color.to_integer_32)
		end

	spans_of (a_line: STRING_32; a_state: INTEGER): LIST [TUPLE [start, length, style: INTEGER]]
		do
			if attached highlighter as al_h then
				Result := al_h.item ([a_line, a_state]).spans
			else
				Result := rule_spans (a_line, a_state).spans
			end
		end

	next_state (a_line: STRING_32; a_state: INTEGER): INTEGER
		do
			if attached highlighter as al_h then
				Result := al_h.item ([a_line, a_state]).state
			else
				Result := rule_spans (a_line, a_state).state
			end
		end

	rule_spans (a_line: STRING_32; a_state: INTEGER): TUPLE [spans: ARRAYED_LIST [TUPLE [start, length, style: INTEGER]]; state: INTEGER]
			-- The rules' spans for a line starting in state `a_state' (0, or a delimiter's
			-- number while inside it), and the state after it.
		local
			l_spans: ARRAYED_LIST [TUPLE [start, length, style: INTEGER]]
			i, j, k, l_state, l_close_at: INTEGER
			l_found: BOOLEAN
			c: CHARACTER_32
		do
			create l_spans.make (4)
			l_state := a_state
			i := 1
			if l_state > 0 and l_state <= delimiters.count then
				l_close_at := a_line.substring_index (delimiters [l_state].close, 1)
				if l_close_at = 0 then
					l_spans.extend ([1, a_line.count, delimiters [l_state].style])
					i := a_line.count + 1
				else
					l_spans.extend ([1, l_close_at + delimiters [l_state].close.count - 1, delimiters [l_state].style])
					i := l_close_at + delimiters [l_state].close.count
					l_state := 0
				end
			end
			from until i > a_line.count loop
				l_found := False
				across line_comments as ic until l_found loop
					if a_line.substring_index (ic.prefix_text, i) = i then
						l_spans.extend ([i, a_line.count - i + 1, ic.style])
						i := a_line.count + 1
						l_found := True
					end
				end
				if not l_found then
					k := 0
					across delimiters as ic until l_found loop
						k := k + 1
						if a_line.substring_index (ic.open, i) = i then
							l_found := True
							if ic.close.is_empty then
								l_close_at := 0
							else
								l_close_at := a_line.substring_index (ic.close, i + ic.open.count)
							end
							if l_close_at = 0 then
								l_spans.extend ([i, a_line.count - i + 1, ic.style])
								if not ic.close.is_empty then
									l_state := k
								end
								i := a_line.count + 1
							else
								l_spans.extend ([i, l_close_at + ic.close.count - i, ic.style])
								i := l_close_at + ic.close.count
							end
						end
					end
				end
				if not l_found then
					c := a_line [i]
					if c.is_alpha or c = '_' then
						from j := i until j > a_line.count or else not (a_line [j].is_alpha or a_line [j].is_digit or a_line [j] = '_') loop
							j := j + 1
						end
						if keywords.has_key (word_key (a_line.substring (i, j - 1))) then
							l_spans.extend ([i, j - i, keywords.found_item])
						end
						i := j
					elseif c.is_digit then
						from j := i until j > a_line.count or else not (a_line [j].is_digit or a_line [j] = '.' or a_line [j] = '_') loop
							j := j + 1
						end
						l_spans.extend ([i, j - i, Style_number])
						i := j
					else
						i := i + 1
					end
				end
			end
			Result := [l_spans, l_state]
		end

	word_key (a_word: STRING_32): STRING_32
		do
			if is_case_sensitive then Result := a_word else Result := a_word.as_lower end
		end

feature {NONE} -- Finding

	find_from (a_text: READABLE_STRING_GENERAL; a_case_sensitive, a_whole_word, a_forward: BOOLEAN): BOOLEAN
		local
			l_text: STRING_32
			l_at, l_from: INTEGER
		do
			l_text := text
			if a_forward then
				l_from := selection_end + 1
				l_at := match_at_or_after (l_text, a_text, l_from.max (1), a_case_sensitive, a_whole_word)
				if l_at = 0 then
					l_at := match_at_or_after (l_text, a_text, 1, a_case_sensitive, a_whole_word)
				end
			else
				l_at := last_match_before (l_text, a_text, selection_start, a_case_sensitive, a_whole_word)
				if l_at = 0 then
					l_at := last_match_before (l_text, a_text, l_text.count + 1, a_case_sensitive, a_whole_word)
				end
			end
			if l_at > 0 then
				select_range (l_at, l_at + a_text.count - 1)
				Result := True
			end
		end

	match_at_or_after (a_text: STRING_32; a_find: READABLE_STRING_GENERAL; a_from: INTEGER; a_case_sensitive, a_whole_word: BOOLEAN): INTEGER
			-- The first match at or after `a_from', or 0.
		local
			l_hay, l_needle: STRING_32
			l_at: INTEGER
		do
			if a_case_sensitive then l_hay := a_text; l_needle := a_find.to_string_32 else l_hay := a_text.as_lower; l_needle := a_find.to_string_32.as_lower end
			from l_at := l_hay.substring_index (l_needle, a_from.min (l_hay.count + 1).max (1)) until l_at = 0 or else not a_whole_word or else is_whole (l_hay, l_at, l_needle.count) loop
				l_at := l_hay.substring_index (l_needle, l_at + 1)
			end
			Result := l_at
		end

	last_match_before (a_text: STRING_32; a_find: READABLE_STRING_GENERAL; a_before: INTEGER; a_case_sensitive, a_whole_word: BOOLEAN): INTEGER
			-- The last match starting before `a_before', or 0.
		local
			l_at: INTEGER
		do
			from l_at := match_at_or_after (a_text, a_find, 1, a_case_sensitive, a_whole_word) until l_at = 0 or l_at >= a_before loop
				Result := l_at
				l_at := match_at_or_after (a_text, a_find, l_at + 1, a_case_sensitive, a_whole_word)
			end
		end

	is_whole (a_text: STRING_32; an_at, a_length: INTEGER): BOOLEAN
		do
			Result := (an_at = 1 or else not is_word_character (a_text [an_at - 1]))
				and (an_at + a_length > a_text.count or else not is_word_character (a_text [an_at + a_length]))
		end

	is_word_character (c: CHARACTER_32): BOOLEAN
		do
			Result := c.is_alpha or c.is_digit or c = '_'
		end

invariant
	starts_fit_the_text: starts.count <= highlighted.count + 1

end
