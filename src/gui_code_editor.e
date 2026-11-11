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

		A syntax object (`set_syntax', 1v-e-1) takes the place of both: the editor tells it
		each edit (the start, the count removed, the text inserted) and colors what it
		answers through `apply_spans'. A parser lives behind it; the editor names none.

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
			make, set_text, dispatch, select_range
		end

	GUI_TEXT_COMPARISON

create
	make

feature {NONE} -- Initialization

	make
		local
			l_appearance: PROCEDURE [TUPLE [dark: BOOLEAN]]
			l_closed: PROCEDURE [TUPLE [window: GUI_WINDOW]]
		do
			create change_actions.make
			create caret_actions.make
			create keywords.make (32)
			create line_comments.make (2)
			create delimiters.make (2)
			create highlighted.make_empty
			create starts.make (64)
			create fold_actions.make
			create fold_lines.make
			create closed_folds.make
			create hidden_lines.make
			is_fold_lines_stale := True
			is_case_sensitive := True
			is_bracket_matching := True
			create extra_carets.make (2)
			create completion_words.make (8)
			create completion_offers.make (8)
			create completion_shown.make (8)
			create completion_word.make_empty
			create completion_opened_actions.make
			create completion_accepted_actions.make
			completion_auto_count := 2
			tab_width := 4
			register (backend.code_editor)
			change_actions.extend (agent text_changed)
			l_appearance := agent appearance_changed
			l_closed := agent window_closed
			appearance_agent := l_appearance
			window_closed_agent := l_closed
			application.appearance_changed_actions.extend (l_appearance)
			application.window_closed_actions.extend (l_closed)
		end

feature -- Styles

	Style_plain: INTEGER = 0
	Style_keyword: INTEGER = 1
	Style_type: INTEGER = 2
	Style_string: INTEGER = 3
	Style_comment: INTEGER = 4
	Style_number: INTEGER = 5
	Style_operator: INTEGER = 6
	Style_function: INTEGER = 7
	Style_constant: INTEGER = 8
	Style_variable: INTEGER = 9
	Style_tag: INTEGER = 10
			-- 7 to 10 came with 1v-e-1. The numbers are those of simple_tree_sitter's
			-- TS_STYLES, so a parser's spans need no translation.

	is_valid_style (a_style: INTEGER): BOOLEAN
		do
			Result := a_style >= Style_plain and a_style <= Style_tag
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
				when Style_function then Result := 0xDCDCAA
				when Style_constant then Result := 0x4FC1FF
				when Style_variable then Result := 0x9CDCFE
				when Style_tag then Result := 0x569CD6
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
				when Style_function then Result := 0x795E26
				when Style_constant then Result := 0x0070C1
				when Style_variable then Result := 0x001080
				when Style_tag then Result := 0x800000
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
			if syntax = Void then
					-- the folds of the indentation depend on it
				is_fold_lines_stale := True
				folds_touched (highlighted)
			end
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
			-- The caret at the start of line `n', scrolled into view; no event. A closed
			-- fold that hides the line opens first.
		require
			gui_thread: is_gui_thread
			valid: 1 <= n and n <= line_count
		do
			show_lines (n, n)
			backend.text_go_to_line (id, n)
			look_for_bracket
		ensure
			there: caret_line = n and caret_column = 1
			shown: not is_line_hidden (n)
		end

	caret_actions: GUI_ACTIONS [TUPLE [line, column: INTEGER]]
			-- Run when the user moves the caret (for a status bar).

feature -- Highlighting by rules

	is_case_sensitive: BOOLEAN

	set_case_sensitive (a_on: BOOLEAN)
		do
			is_case_sensitive := a_on
			rules_changed
		end

	add_keywords (a_words: ARRAY [READABLE_STRING_GENERAL]; a_style: INTEGER)
		require
			valid_style: is_valid_style (a_style)
		do
			across a_words as ic loop
				keywords.force (a_style, word_key (ic.to_string_32))
			end
			rules_changed
		end

	add_line_comment (a_prefix: READABLE_STRING_GENERAL; a_style: INTEGER)
			-- From `a_prefix' to the line's end.
		require
			has_prefix: not a_prefix.is_empty
			valid_style: is_valid_style (a_style)
		do
			line_comments.extend ([a_prefix.to_string_32, a_style])
			rules_changed
		end

	add_delimited (an_open, a_close: READABLE_STRING_GENERAL; a_style: INTEGER)
			-- From `an_open' to `a_close' (strings, block comments), across lines; a close of ""
			-- ends at the line's end.
		require
			has_open: not an_open.is_empty
			valid_style: is_valid_style (a_style)
		do
			delimiters.extend ([an_open.to_string_32, a_close.to_string_32, a_style])
			rules_changed
		end

feature -- Highlighting by an agent

	set_highlighter (a_function: detachable FUNCTION [STRING_32, INTEGER, TUPLE [spans: LIST [TUPLE [start, length, style: INTEGER]]; state: INTEGER]])
			-- `a_function' gets a line and the state it starts in (0 at the text's start), and
			-- answers the line's spans (start from 1, in characters) and the state the next line
			-- starts in. Void: the rules.
		do
			highlighter := a_function
			rules_changed
		end

feature -- Highlighting by a syntax object

	syntax: detachable GUI_EDITOR_SYNTAX
			-- What colors the text in place of the rules and the agent, if anything.

	set_syntax (a_syntax: detachable GUI_EDITOR_SYNTAX)
			-- Let `a_syntax' color the text: every line goes plain, then it is attached and
			-- hears of each edit from now on. The one before it, if any, is detached first.
			-- Void: the rules and the agent color again.
		require
			gui_thread: is_gui_thread
			free: attached a_syntax as al_s implies (al_s = syntax or al_s.editor = Void)
		do
			if a_syntax /= syntax then
				if attached syntax as al_old then
					al_old.detach
				end
				syntax := a_syntax
					-- the folds were the old one's, or the indentation's: every fold opens,
					-- and they are found again
				open_every_fold
				create fold_lines.make
				is_fold_lines_stale := a_syntax = Void
				if attached a_syntax as al_new then
					make_plain
					al_new.attach (Current)
					look_for_bracket
				else
					highlight_all
				end
				folds_touched (highlighted)
			end
		ensure
			set: syntax = a_syntax
		end

	apply_spans (a_first_line, a_last_line: INTEGER; a_spans: GUI_SYNTAX_SPANS)
			-- Lines `a_first_line' to `a_last_line' go plain, then each of `a_spans' on one
			-- of them takes its style's color. For the syntax object, on the GUI processor.
			-- The control's text can be one event ahead of the last edit reported, so this
			-- clamps where another feature would require: a line the text does not have is
			-- passed over, a span that runs past its line's end is cut there, and a span on
			-- a line outside the range, or of a style the editor does not know, colors
			-- nothing.
			-- Cost: one read of the text, one walk over the line breaks down to the range's
			-- end, and one call to the control per span.
		require
			gui_thread: is_gui_thread
			lines_ordered: 1 <= a_first_line and a_first_line <= a_last_line
		local
			l_text: STRING_32
			l_starts: ARRAYED_LIST [INTEGER]
			l_colors: ARRAY [NATURAL_32]
			i, n, l_count, l_line, l_offset, l_break, l_from, l_to, l_style: INTEGER
		do
			l_text := text
			l_colors := style_colors
				-- where line `a_first_line' starts; 0 when the text has no such line
			from
				l_line := 1
				l_offset := 1
			until
				l_line = a_first_line or l_offset = 0
			loop
				l_break := l_text.index_of ('%N', l_offset)
				if l_break = 0 then
					l_offset := 0
				else
					l_offset := l_break + 1
					l_line := l_line + 1
				end
			end
			if l_offset > 0 then
					-- Where each line of the range starts, then where the line after the last
					-- would: line k is characters `l_starts [k]' to `l_starts [k + 1] - 2'.
				create l_starts.make ((a_last_line - a_first_line).min (l_text.count) + 2)
				from
					l_starts.extend (l_offset)
				until
					l_offset = 0 or l_starts.count - 1 > a_last_line - a_first_line
				loop
					l_break := l_text.index_of ('%N', l_offset)
					if l_break = 0 then
						l_offset := 0
						l_starts.extend (l_text.count + 2)
					else
						l_offset := l_break + 1
						l_starts.extend (l_offset)
					end
				end
				n := l_starts.count - 1
				l_to := l_starts [n + 1] - 2
				if l_starts [1] <= l_to then
					color_run (l_starts [1], l_to, l_colors [Style_plain])
				end
				from
					i := 1
					l_count := a_spans.count
				until
					i > l_count
				loop
					l_line := a_spans.line (i) - a_first_line + 1
					l_style := a_spans.style (i)
					if 1 <= l_line and l_line <= n and l_style /= Style_plain and is_valid_style (l_style) then
						l_from := l_starts [l_line] + a_spans.column (i) - 1
						l_to := l_starts [l_line + 1] - 2
						if a_spans.length (i) <= l_to - l_from then
							l_to := l_from + a_spans.length (i) - 1
						end
						if l_from <= l_to then
							color_run (l_from, l_to, l_colors [l_style])
						end
					end
					i := i + 1
				end
			end
		end

	set_folds (a_folds: GUI_SYNTAX_RANGES)
			-- The folds of the whole text are `a_folds'. For the syntax object, on the GUI
			-- processor. Read during the call: the object is not kept. A range of one line
			-- hides nothing and is no fold; of ranges that start on one line, the one that
			-- reaches furthest is the fold. A closed fold stays closed while one of
			-- `a_folds' starts on its first line.
			-- Cost: fastest with the ranges in order of their first lines.
		require
			gui_thread: is_gui_thread
			has_syntax: syntax /= Void
		do
			create fold_lines.make_from (a_folds)
			is_fold_lines_stale := False
			folds_touched (highlighted)
		ensure
			kept: fold_count <= a_folds.count
		end

feature -- Folding (1v-e-3)

	is_folding_shown: BOOLEAN
			-- Does the gutter show a marker beside each line that starts a fold, and do the
			-- fold keys work? (Off until set.) `fold' and its fellows work either way.
			-- The keys: Control+Shift+[ closes the innermost open fold that holds the
			-- caret's line, Control+Shift+] opens the closed fold that starts on it
			-- (Command+Option+[ and ] on macOS).

	set_folding_shown (a_on: BOOLEAN)
		require
			gui_thread: is_gui_thread
		do
			if a_on /= is_folding_shown then
				is_folding_shown := a_on
				backend.code_set_folding_shown (id, a_on)
				if a_on then
					folds_changed (highlighted)
				end
			end
		ensure
			set: is_folding_shown = a_on
		end

	fold_count: INTEGER
			-- How many folds the text has. A fold is a first line, which always shows, and
			-- the lines after it through its last, which a closed fold hides. With a syntax
			-- object the folds are those it gave last (`set_folds'). Without one they are
			-- the indentation's: a line followed by lines indented deeper folds through the
			-- last of them; blank lines between them belong to the fold, blank lines after
			-- them do not; a tab reaches the next multiple of `tab_width'.
			-- The folds are in order of their first lines, one to a first line.
			-- Cost, without a syntax object: the first call after a change of the text
			-- walks every line's indent (unless folding is shown, which has done so).
		do
			Result := current_folds.count
		ensure
			not_negative: Result >= 0
		end

	is_valid_fold (i: INTEGER): BOOLEAN
			-- Is `i' the number of a fold?
		do
			Result := 1 <= i and i <= fold_count
		ensure
			definition: Result = (1 <= i and i <= fold_count)
		end

	fold_first_line (i: INTEGER): INTEGER
			-- The line fold `i' starts on.
		require
			valid_fold: is_valid_fold (i)
		do
			Result := current_folds.first_line (i)
		ensure
			positive: Result >= 1
			foldable: is_foldable (Result)
		end

	fold_last_line (i: INTEGER): INTEGER
			-- The last line of fold `i'.
		require
			valid_fold: is_valid_fold (i)
		do
			Result := current_folds.last_line (i)
		ensure
			after_the_first: Result > fold_first_line (i)
		end

	is_foldable (a_line: INTEGER): BOOLEAN
			-- Does a fold start on `a_line'?
		do
			Result := current_folds.has_start (a_line)
		end

	is_folded (a_line: INTEGER): BOOLEAN
			-- Is the fold that starts on `a_line' closed?
		do
			Result := closed_folds.has_start (a_line)
		end

	is_line_hidden (a_line: INTEGER): BOOLEAN
			-- Is `a_line' hidden in a closed fold? (Never a fold's own first line, unless a
			-- fold around it is closed too.) The text is whole all the same: `text',
			-- `line_text' and the positions count hidden lines like any other.
		do
			Result := hidden_lines.is_hidden (a_line)
		end

	fold (a_line: INTEGER)
			-- Close the fold that starts on `a_line'. Where an end of the selection is in a
			-- line this hides, the caret goes to the end of `a_line', nothing selected.
			-- No event.
		require
			gui_thread: is_gui_thread
			foldable: is_foldable (a_line)
		local
			l_folds: GUI_LINE_RANGES
		do
			if not is_folded (a_line) then
				l_folds := current_folds
				closed_folds.put (a_line, l_folds.last_line (l_folds.index_starting_at (a_line)))
				closed_changed
				leave_hidden_lines
			end
		ensure
			folded: is_folded (a_line)
			hides_the_next: is_line_hidden (a_line + 1)
		end

	unfold (a_line: INTEGER)
			-- Open the fold that starts on `a_line'. A closed fold inside it stays closed;
			-- its lines stay hidden while a fold around it is closed. No event.
		require
			gui_thread: is_gui_thread
			foldable: is_foldable (a_line)
		do
			if is_folded (a_line) then
				closed_folds.remove_starting_at (a_line)
				closed_changed
			end
		ensure
			open: not is_folded (a_line)
		end

	toggle_fold (a_line: INTEGER)
			-- Close the fold that starts on `a_line' when it is open, open it when closed.
		require
			gui_thread: is_gui_thread
			foldable: is_foldable (a_line)
		do
			if is_folded (a_line) then
				unfold (a_line)
			else
				fold (a_line)
			end
		ensure
			toggled: is_folded (a_line) /= old is_folded (a_line)
		end

	fold_all
			-- Close every fold. The caret leaves a hidden line as with `fold'.
		require
			gui_thread: is_gui_thread
		do
			create closed_folds.make_from (current_folds)
			closed_changed
			leave_hidden_lines
		ensure
			all_closed: across 1 |..| fold_count as ic all is_folded (fold_first_line (ic)) end
		end

	unfold_all
			-- Open every fold.
		require
			gui_thread: is_gui_thread
		do
			open_every_fold
		ensure
			none_hidden: across 1 |..| fold_count as ic all not is_folded (fold_first_line (ic)) end
		end

	fold_actions: GUI_ACTIONS [TUPLE [line: INTEGER; folded: BOOLEAN]]
			-- Run when the user closes or opens a fold, by a click on its marker or by a
			-- fold key: the fold's first line, and whether it is closed now. Not run when
			-- the program folds, nor when a fold opens because the caret or an edit went
			-- into it.

feature -- Bracket matching (1v-e-2)

	is_bracket_matching: BOOLEAN
			-- Is a bracket at the caret shown with its partner? (On until set.)

	set_bracket_matching (a_on: BOOLEAN)
		require
			gui_thread: is_gui_thread
		do
			is_bracket_matching := a_on
			look_for_bracket
		ensure
			set: is_bracket_matching = a_on
			none_when_off: not a_on implies not has_bracket_pair
		end

	has_bracket_pair: BOOLEAN
			-- Are a bracket at the caret and its partner tinted?
			-- Each time the caret moves or the text changes, the character after the caret
			-- is looked at, then the one before it. One of ( ) [ ] { } there wants its
			-- partner: from the syntax object (`bracket_wanted'), which answers now or later
			-- with `show_bracket_pair' or `hide_bracket_pair'; without one, by counting
			-- brackets of that kind (see `find_partner').

	bracket_first, bracket_second: INTEGER
			-- Where the two brackets of the pair start, the first before the second;
			-- meaningful with `has_bracket_pair'.

	go_to_matching_bracket
			-- The caret just before the partner of the bracket it is at, brought into view;
			-- nothing without a pair. No event. From there the first bracket is the partner,
			-- so a second call comes back to it. The key: Control+Shift+\ (Command+Shift+\
			-- on macOS), which also runs `caret_actions'.
		require
			gui_thread: is_gui_thread
		local
			l_target: INTEGER
		do
			if has_bracket_pair then
				if bracket_first <= bracket_asked and bracket_asked < bracket_first + bracket_first_count then
					l_target := bracket_second
				else
					l_target := bracket_first
				end
				backend.rich_text_select (id, l_target, l_target - 1)
				look_for_bracket
			end
		end

	show_bracket_pair (a_first_start, a_first_count, a_second_start, a_second_count: INTEGER)
			-- The answer to `bracket_wanted', now or later: tint the `a_first_count'
			-- characters from `a_first_start' and the `a_second_count' from `a_second_start'.
			-- A decoration: no text color, no undo step, nothing `change_actions' hears of.
			-- No pair is shown when a range does not lie in the text or the first does not
			-- end before the second starts. A pair that does not hold the bracket last
			-- asked about is the answer to an older question: what is shown stands.
		require
			gui_thread: is_gui_thread
		do
			if not is_bracket_matching
				or else not is_pair_in_text (a_first_start, a_first_count, a_second_start, a_second_count)
			then
				hide_bracket_pair
			elseif (a_first_start <= bracket_asked and bracket_asked < a_first_start + a_first_count)
				or (a_second_start <= bracket_asked and bracket_asked < a_second_start + a_second_count)
			then
				has_bracket_pair := True
				bracket_first := a_first_start
				bracket_first_count := a_first_count
				bracket_second := a_second_start
				bracket_second_count := a_second_count
				backend.code_show_bracket_pair (id, a_first_start, a_first_count, a_second_start, a_second_count)
			end
		ensure
			none_out_of_text: not is_pair_in_text (a_first_start, a_first_count, a_second_start, a_second_count)
				implies not has_bracket_pair
		end

	hide_bracket_pair
			-- No pair is shown: the answer to `bracket_wanted' for a bracket without a partner.
		require
			gui_thread: is_gui_thread
		do
			if has_bracket_pair then
				has_bracket_pair := False
				backend.code_hide_bracket_pair (id)
			end
		ensure
			hidden: not has_bracket_pair
		end

	is_pair_in_text (a_first_start, a_first_count, a_second_start, a_second_count: INTEGER): BOOLEAN
			-- Do the two ranges lie in the text as last reported, one character each at
			-- least, the first ending before the second starts?
		do
			Result := a_first_start >= 1 and a_first_count >= 1 and a_second_count >= 1
				and then a_first_start < a_second_start
				and then a_first_count <= a_second_start - a_first_start
				and then a_second_start <= highlighted.count
				and then a_second_count <= highlighted.count - a_second_start + 1
		end

feature -- Completion (1v-e-4)

	completion_auto_count: INTEGER
			-- How many word characters, typed, open a list by itself (2 until set); 0: a list
			-- opens only on request (Control+Space, or `complete').

	set_completion_auto_count (a_count: INTEGER)
		require
			not_negative: a_count >= 0
		do
			completion_auto_count := a_count
		ensure
			set: completion_auto_count = a_count
		end

	set_completion_words (a_words: ITERABLE [READABLE_STRING_GENERAL])
			-- Offer each of `a_words' that is not empty, as plain offers, in place of the
			-- words set before. A list already open keeps what it has.
		do
			completion_words.wipe_out
			across a_words as ic loop
				if not ic.is_empty then
					completion_words.extend (create {GUI_COMPLETION}.make (ic))
				end
			end
		end

	completer: detachable FUNCTION [STRING_32, INTEGER, INTEGER, ITERABLE [GUI_COMPLETION]]
			-- Given the word so far, the caret's line and its column, the offers.

	set_completer (a_function: like completer)
			-- `a_function' answers offers when a list opens. It runs on the GUI processor, so
			-- it must be quick; a slow source answers through `completion_opened_actions' and
			-- `add_completions' instead. Void: none.
		do
			completer := a_function
		ensure
			set: completer = a_function
		end

	completion_opened_actions: GUI_ACTIONS [TUPLE [start: INTEGER]]
			-- Run when a list is wanted for the word that starts at position `start' (the
			-- caret's position when the word is empty): a slow source answers later with
			-- `add_completions'.

	completion_accepted_actions: GUI_ACTIONS [TUPLE [text: STRING_32]]
			-- Run after an offer's `text' is put in place of the word.

	complete
			-- Open a list for the word before the caret, as Control+Space does. No list shows
			-- while there are no offers.
		require
			gui_thread: is_gui_thread
		do
			open_completion
		end

	add_completions (a_start: INTEGER; an_offers: ITERABLE [GUI_COMPLETION])
			-- Add `an_offers' to the list opened for the word that starts at `a_start'.
			-- Nothing when that list has closed or a list belongs to another word.
		require
			gui_thread: is_gui_thread
		do
			if a_start > 0 and a_start = completion_start then
				across an_offers as ic loop
					completion_offers.extend (ic)
				end
				filter_completions
			end
		end

	is_completing: BOOLEAN
			-- Does a list show?
		do
			Result := completion_start > 0 and completion_shown.count > 0
		end

	completion_count: INTEGER
			-- How many rows the list has; 0 when none shows.
		do
			if completion_start > 0 then
				Result := completion_shown.count
			end
		ensure
			none_when_closed: not is_completing implies Result = 0
		end

	completion_label (i: INTEGER): STRING_32
			-- Row `i''s label.
		require
			valid: 1 <= i and i <= completion_count
		do
			Result := completion_shown [i].label
		end

	completion_selected: INTEGER
			-- The highlighted row; 0 when no list shows.

feature -- Multiple carets (1v-e-5)

	caret_count: INTEGER
			-- The carets: the control's own (1) and the extra ones.
		do
			Result := 1 + extra_carets.count
		ensure
			at_least_one: Result >= 1
		end

	caret_start (i: INTEGER): INTEGER
			-- Where caret `i''s selection starts, or its place when nothing is selected
			-- (1 is the control's own).
		require
			valid: 1 <= i and i <= caret_count
		do
			if i = 1 then
				Result := selection_start
			else
				Result := extra_carets [i - 1].caret.min (extra_carets [i - 1].anchor)
			end
		end

	caret_end (i: INTEGER): INTEGER
			-- The last character caret `i' selects; `caret_start (i)' - 1 when none.
		require
			valid: 1 <= i and i <= caret_count
		do
			if i = 1 then
				Result := selection_end
			else
				Result := extra_carets [i - 1].caret.max (extra_carets [i - 1].anchor) - 1
			end
		end

	add_caret (a_line, a_column: INTEGER)
			-- Another caret on line `a_line' at column `a_column' (the line's end when the
			-- line is shorter). Nothing when a caret is there already.
		require
			gui_thread: is_gui_thread
			valid_line: 1 <= a_line and a_line <= line_count
			valid_column: a_column >= 1
		local
			l_start, l_at: INTEGER
		do
			l_start := highlighted_line_start (a_line)
			if l_start > 0 then
				l_at := (l_start + a_column - 1).min (line_end_of (highlighted, l_start))
				add_extra (l_at, l_at)
			end
		end

	add_selection (a_start, an_end: INTEGER)
			-- Another caret selecting characters `a_start' to `an_end', its caret after them.
			-- Nothing when it meets a caret there already.
		require
			gui_thread: is_gui_thread
			valid: is_valid_range (a_start, an_end)
		do
			add_extra (an_end + 1, a_start)
		end

	add_next_occurrence
			-- As Control+D (Command+D): with nothing selected, select the word at the caret;
			-- else add the next occurrence of the first caret's selection after the last
			-- caret, wrapping round. Nothing when there is none.
		require
			gui_thread: is_gui_thread
		local
			l_text, l_find: STRING_32
			l_at, l_lo, l_hi: INTEGER
		do
			l_text := highlighted
			if selection_start > selection_end then
				l_lo := selection_start.min (l_text.count + 1)
				l_hi := l_lo
				from until l_lo <= 1 or else not is_word_character (l_text [l_lo - 1]) loop
					l_lo := l_lo - 1
				end
				from until l_hi > l_text.count or else not is_word_character (l_text [l_hi]) loop
					l_hi := l_hi + 1
				end
				if l_hi > l_lo then
					backend.rich_text_select (id, l_lo, l_hi - 1)
				end
			elseif selection_end <= l_text.count then
				l_find := l_text.substring (selection_start, selection_end)
				l_at := l_text.substring_index (l_find, last_caret_end.min (l_text.count + 1))
				if l_at = 0 then
					l_at := l_text.substring_index (l_find, 1)
				end
				if l_at > 0 then
					add_extra (l_at + l_find.count, l_at)
				end
			end
		end

	clear_extra_carets
			-- Back to the control's own caret.
		require
			gui_thread: is_gui_thread
		do
			if not extra_carets.is_empty then
				extra_carets.wipe_out
				send_extra_carets
			end
		ensure
			one: caret_count = 1
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
			program_edited
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
				program_edited
			end
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
			-- 52: the user moved the caret (line, column); 56: the user pressed the key that
			-- goes to the matching bracket; 57: the user clicked a fold marker or pressed a
			-- fold key (line, which); 58: a completion key (which); 59: a click on a
			-- completion row (row); 60: an editing key with extra carets (action, Shift);
			-- 61: a caret gesture (which, position); else as a text area.
		do
			if a_type = 52 then
				if not extra_carets.is_empty then
						-- the user placed the caret (a click): back to one
					clear_extra_carets
				end
				show_lines (a_a, a_a)
				look_for_bracket
				completion_caret_moved
				caret_actions.call ([a_a, a_b])
			elseif a_type = 60 then
				if not extra_carets.is_empty and then 1 <= a_a and then a_a <= 15 then
					if a_a = 1 then
						act_at_carets (1, a_b = 1, backend.from_c (backend.code_typed_text (id)))
					else
						act_at_carets (a_a, a_b = 1, create {STRING_32}.make_empty)
					end
				end
			elseif a_type = 61 then
				caret_gesture (a_a, a_b)
			elseif a_type = 58 then
				completion_key (a_a)
			elseif a_type = 59 then
				if 1 <= a_a and a_a <= completion_count then
					accept_completion (a_a)
				end
			elseif a_type = 57 then
				fold_by_user (a_a, a_b)
			elseif a_type = 56 then
				if has_bracket_pair then
					go_to_matching_bracket
					caret_actions.call ([caret_line, caret_column])
				end
			else
				Precursor (a_type, a_a, a_b, a_c)
			end
		end

feature -- Element change

	set_text (a_text: READABLE_STRING_GENERAL)
			-- Also: every fold opens, and the folds are found again; a completion list closes.
		do
			close_completion
			if not extra_carets.is_empty then
				clear_extra_carets
			end
			Precursor (a_text)
			open_every_fold
			if syntax = Void then
				is_fold_lines_stale := True
			else
					-- the syntax object gives the new text's folds (`set_folds')
				create fold_lines.make
			end
			highlight_all
			folds_touched (highlighted)
		end

	select_range (a_start, an_end: INTEGER)
			-- Also: a closed fold that hides either end opens first, and a bracket at the
			-- caret's new place gets its pair.
		local
			l_first: INTEGER
		do
			if hidden_lines.count > 0 then
				l_first := line_at (highlighted, a_start)
				show_lines (l_first, l_first + line_breaks_in (highlighted,
					a_start.min (highlighted.count + 1), an_end.min (highlighted.count).max (a_start.min (highlighted.count + 1) - 1)))
			end
			Precursor (a_start, an_end)
			look_for_bracket
		end

	highlight_all
			-- Highlight every line again (after a rule change, a new text or a change of
			-- theme). With a syntax object every line goes plain and the object is told the
			-- text was replaced, so that it colors all of it again.
		do
			if attached syntax as al_syntax then
				make_plain
				al_syntax.text_replaced (highlighted)
			else
				starts.wipe_out
				rehighlight (text)
			end
			look_for_bracket
		end

feature {NONE} -- The application's calls

	appearance_agent: detachable PROCEDURE [TUPLE [dark: BOOLEAN]]
			-- What `make' gave the application's `appearance_changed_actions'; Void once
			-- this editor has let go.

	window_closed_agent: detachable PROCEDURE [TUPLE [window: GUI_WINDOW]]
			-- What `make' gave the application's `window_closed_actions'; Void once this
			-- editor has let go.

	appearance_changed (a_dark: BOOLEAN)
			-- The theme changed: color everything again.
		do
			highlight_all
		end

	window_closed (a_window: GUI_WINDOW)
			-- `a_window' closed. If this editor was in it, its control is gone: the syntax
			-- object is detached (it must make no further call here) and the application
			-- stops calling. Before this, every editor ever made was colored again on each
			-- change of theme, its window open or not.
		do
			if enclosing_window = a_window then
				has_bracket_pair := False
				bracket_asked := 0
					-- the list and the extra carets went with the control
				extra_carets.wipe_out
				completion_start := 0
				completion_selected := 0
				completion_offers.wipe_out
				completion_shown.wipe_out
				if attached syntax as al_syntax then
					al_syntax.detach
					syntax := Void
				end
				if attached appearance_agent as al_agent then
					application.appearance_changed_actions.prune (al_agent)
					appearance_agent := Void
				end
				if attached window_closed_agent as al_agent then
					application.window_closed_actions.prune (al_agent)
					window_closed_agent := Void
				end
			end
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

	text_changed
			-- The user edited the text: the folds follow the edit, then the syntax object
			-- hears what changed, or the rules color the changed lines.
		local
			l_text: STRING_32
			l_before: INTEGER
		do
			l_text := text
			l_before := highlighted.count
				-- before the syntax object hears: it may answer with `set_folds' at once
			folds_follow (highlighted, l_text)
			if attached syntax as al_syntax then
				report_edit (al_syntax, l_text)
			else
				rehighlight (l_text)
			end
			look_for_bracket
			completion_follow_edit (l_text.count - l_before)
		end

	rules_changed
			-- The rules or the agent changed: color again, when they are what colors.
		do
			if syntax = Void then
				highlight_all
			end
		end

	program_edited
			-- A feature of this class changed a part of the text (no change event follows):
			-- the folds follow the edit, then the syntax object hears what changed, or the
			-- rules color every line.
		local
			l_text: STRING_32
		do
			l_text := text
			folds_follow (highlighted, l_text)
			if attached syntax as al_syntax then
				report_edit (al_syntax, l_text)
				look_for_bracket
			else
				highlight_all
			end
		end

	make_plain
			-- Every line plain, and no line states: the rules have colored nothing.
		do
			highlighted := text
			starts.wipe_out
			if not highlighted.is_empty then
				color_run (1, highlighted.count, style_color (Style_plain))
			end
		ensure
			no_states: starts.is_empty
		end

	report_edit (a_syntax: GUI_EDITOR_SYNTAX; a_text: STRING_32)
			-- Tell `a_syntax' the edit that makes `a_text', the text now, from `highlighted', the text
			-- as last reported: what lies between the start and the end the two share. Where
			-- the shared start and the shared end overlap (a stretch that repeats), the end
			-- gives way, so the edit is always a true one. Nothing is told when the texts are
			-- equal (one edit that reached here twice).
			-- Cost: one comparison of memory.
		require
			working_for_this: a_syntax.editor = Current
		local
			l_text, l_old: STRING_32
			l_head, l_tail, l_limit: INTEGER
		do
			l_text := a_text
			l_old := highlighted
			l_limit := l_text.count.min (l_old.count)
			l_head := shared_head (l_text, l_old, l_limit)
			if l_head < l_limit or l_text.count /= l_old.count then
				l_tail := shared_tail (l_text, l_old, l_limit).min (l_limit - l_head)
					-- before the call: the object may answer with `apply_spans' at once
				highlighted := l_text
				a_syntax.text_edited (l_head + 1, l_old.count - l_head - l_tail,
					l_text.substring (l_head + 1, l_text.count - l_tail))
			end
		end

	rehighlight (a_text: STRING_32)
			-- `a_text' is the text now.
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
			l_text := a_text
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

	style_colors: ARRAY [NATURAL_32]
			-- The color of each style now, by style number: the theme is asked once for
			-- many spans. (`style_color' asks the system whether it is dark on every call.)
		local
			i: INTEGER
		do
			create Result.make_filled (0, Style_plain, Style_tag)
			from i := Style_plain until i > Style_tag loop
				Result [i] := style_color (i)
				i := i + 1
			end
		ensure
			every_style: Result.lower = Style_plain and Result.upper = Style_tag
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

feature {NONE} -- Bracket matching

	bracket_asked: INTEGER
			-- Where the bracket is whose partner was last looked for; 0 when the caret was
			-- at none.

	bracket_first_count, bracket_second_count: INTEGER
			-- How many characters each range of the pair has.

	Brackets: STRING_32 = "()[]{}"
			-- The brackets that are matched, each opening one before its closing one.

	Bracket_reach: INTEGER = 2000
			-- How many lines, the bracket's own among them, the rules' search looks at.

	look_for_bracket
			-- No pair; then, when matching is on, the character after the caret and the one
			-- before it are looked at, and the first that is a bracket wants its partner.
			-- Cost: away from any bracket, what `is_bracket_near_caret' costs, which walks
			-- no text. Next to one: three calls to the control (the caret's line, its
			-- column, that line's text; the Windows control walks its text for each: 4 ms
			-- in all at the middle of 388,893 characters), one walk over `highlighted' down
			-- to the caret's line, then the syntax object's answer or `find_partner'.
			-- The control's text can be one event ahead of `highlighted'; then the caret's
			-- line differs there, no pair is shown, and the change event that follows
			-- looks again.
		local
			l_line: STRING_32
			l_number, l_column, l_at, l_start, l_end: INTEGER
		do
			hide_bracket_pair
			bracket_asked := 0
			if is_bracket_matching and then is_bracket_near_caret then
				l_number := caret_line
				l_column := caret_column
				if l_number >= 1 then
					l_line := line_text (l_number)
					if l_column >= 1 and then l_column <= l_line.count and then Brackets.has (l_line [l_column]) then
						l_at := l_column
					elseif l_column >= 2 and then l_column - 1 <= l_line.count and then Brackets.has (l_line [l_column - 1]) then
						l_at := l_column - 1
					end
					if l_at > 0 then
						l_start := highlighted_line_start (l_number)
						if l_start > 0 and l_start <= highlighted.count then
							l_end := highlighted.index_of ('%N', l_start)
							if l_end = 0 then l_end := highlighted.count + 1 end
							if l_end - l_start = l_line.count and then highlighted.same_characters (l_line, 1, l_line.count, l_start) then
								bracket_asked := l_start + l_at - 1
								if attached syntax as al_syntax then
									al_syntax.bracket_wanted (bracket_asked)
								elseif starts.valid_index (l_number) then
									find_partner (l_number, l_start, l_at, l_line)
								end
							end
						end
					end
				end
			end
		ensure
			none_when_off: not is_bracket_matching implies not has_bracket_pair
		end

	is_bracket_near_caret: BOOLEAN
			-- Can the caret be next to a bracket? With nothing selected, the caret's place
			-- is read from the control (two calls that walk no text) and `highlighted'
			-- answers. With a selection the caret is at one of its ends, and only its line
			-- and column say which: True.
			-- When the control's text is one event ahead of `highlighted' the answer can
			-- be wrong either way: a False shows no pair until the change event that
			-- follows looks again, and a True is settled by `look_for_bracket', which
			-- reads the control's own line.
		local
			l_first, l_last: INTEGER
		do
			l_first := backend.rich_text_selection_start (id)
			l_last := backend.rich_text_selection_end (id)
			if l_last >= l_first then
				Result := True
			else
				Result := (highlighted.valid_index (l_first) and then Brackets.has (highlighted [l_first]))
					or else (highlighted.valid_index (l_first - 1) and then Brackets.has (highlighted [l_first - 1]))
			end
		end

	highlighted_line_start (a_number: INTEGER): INTEGER
			-- Where line `a_number' of `highlighted' starts (one past the text's end for an
			-- empty last line); 0 when it has no such line.
		require
			positive: a_number >= 1
		local
			i: INTEGER
		do
			from
				Result := 1
				i := 1
			until
				i = a_number or Result = 0
			loop
				Result := highlighted.index_of ('%N', Result)
				if Result > 0 then
					Result := Result + 1
				end
				i := i + 1
			end
		ensure
			in_reach: 0 <= Result and Result <= highlighted.count + 1
		end

	find_partner (a_number, a_start, a_column: INTEGER; a_line: STRING_32)
			-- Without a syntax object: the partner of the bracket at column `a_column' of
			-- line `a_number' (`a_line', which starts at position `a_start' of `highlighted')
			-- is found by counting brackets of its kind, forward from an opening one and
			-- backward from a closing one, passing over what the rules (or the agent) color
			-- as a string or a comment. Found: the pair is shown. Not found within
			-- `Bracket_reach' lines, or the bracket is itself in a string or a comment: no
			-- pair.
			-- Cost: one pass over the lines searched; the rules are asked only for a line
			-- that has a bracket of the kind.
		require
			no_syntax: syntax = Void
			line_has_a_state: starts.valid_index (a_number)
			a_bracket: a_line.valid_index (a_column) and then Brackets.has (a_line [a_column])
			asked: bracket_asked = a_start + a_column - 1
		local
			l_own, l_other, c: CHARACTER_32
			l_kind, l_step, l_depth, l_number, l_offset, l_end, l_lines, l_found, i: INTEGER
			l_line: STRING_32
			l_spans: detachable LIST [TUPLE [start, length, style: INTEGER]]
			l_stop: BOOLEAN
		do
			l_own := a_line [a_column]
			l_kind := Brackets.index_of (l_own, 1)
			if l_kind \\ 2 = 1 then
				l_other := Brackets [l_kind + 1]
				l_step := 1
			else
				l_other := Brackets [l_kind - 1]
				l_step := -1
			end
			from
				l_number := a_number
				l_offset := a_start
				l_line := a_line
				l_lines := 1
				i := a_column + l_step
				l_spans := spans_of (l_line, starts [l_number])
				l_stop := is_passed_over (l_spans, a_column)
			until
				l_found > 0 or l_stop
			loop
				from until i < 1 or i > l_line.count or l_found > 0 loop
					c := l_line [i]
					if c = l_own or c = l_other then
						if l_spans = Void then
							l_spans := spans_of (l_line, starts [l_number])
						end
						if attached l_spans as al_spans and then not is_passed_over (al_spans, i) then
							if c = l_own then
								l_depth := l_depth + 1
							elseif l_depth = 0 then
								l_found := l_offset + i - 1
							else
								l_depth := l_depth - 1
							end
						end
					end
					i := i + l_step
				end
				if l_found = 0 then
					l_number := l_number + l_step
					if l_lines >= Bracket_reach or not starts.valid_index (l_number) then
						l_stop := True
					elseif l_step = 1 then
						l_offset := l_offset + l_line.count + 1
						if l_offset > highlighted.count + 1 then
							l_stop := True
						else
							l_end := highlighted.index_of ('%N', l_offset)
							if l_end = 0 then l_end := highlighted.count + 1 end
						end
					elseif l_offset < 2 then
						l_stop := True
					else
							-- the line break before this line ends the one before it
						l_end := l_offset - 1
						if l_end >= 2 then
							l_offset := highlighted.last_index_of ('%N', l_end - 1) + 1
						else
							l_offset := 1
						end
					end
					if not l_stop then
						l_line := highlighted.substring (l_offset, l_end - 1)
						l_spans := Void
						l_lines := l_lines + 1
						if l_step = 1 then i := 1 else i := l_line.count end
					end
				end
			end
			if l_found > 0 then
				if l_step = 1 then
					show_bracket_pair (bracket_asked, 1, l_found, 1)
				else
					show_bracket_pair (l_found, 1, bracket_asked, 1)
				end
			end
		end

	is_passed_over (a_spans: LIST [TUPLE [start, length, style: INTEGER]]; a_column: INTEGER): BOOLEAN
			-- Does one of `a_spans', a line's, color column `a_column' as a string or a
			-- comment?
		do
			across a_spans as ic loop
				if (ic.style = Style_string or ic.style = Style_comment)
					and then ic.start <= a_column and then a_column < ic.start + ic.length
				then
					Result := True
				end
			end
		end

feature {NONE} -- Folding

	fold_lines: GUI_LINE_RANGES
			-- The folds as last found; ask `current_folds'.

	is_fold_lines_stale: BOOLEAN
			-- Has the text changed since `fold_lines' were found from its indentation?

	closed_folds: GUI_LINE_RANGES
			-- The folds that are closed, each with the last line it had when last looked at.

	hidden_lines: GUI_LINE_RANGES
			-- The lines `closed_folds' hide together: what the control is given.

	has_left_hidden_lines: BOOLEAN
			-- Did the last `leave_hidden_lines' move the caret?

	current_folds: GUI_LINE_RANGES
			-- The folds of the text: the syntax object's, or the indentation's, found again
			-- when the text has changed since they were.
		do
			if is_fold_lines_stale then
				create fold_lines.make_by_indentation (highlighted, tab_width)
				is_fold_lines_stale := False
			end
			Result := fold_lines
		ensure
			fresh: not is_fold_lines_stale
		end

	folds_follow (a_old, a_new: STRING_32)
			-- The text was `a_old' and is `a_new'. The closed folds follow the edit by the
			-- rule of GUI_LINE_RANGES, and so do the syntax object's folds, which stand
			-- until it gives new ones; the indentation's are found again.
			-- Cost: one comparison of the texts while a fold is closed or a syntax object
			-- has given folds; else nothing.
		local
			l_had_hidden: BOOLEAN
		do
			l_had_hidden := hidden_lines.count > 0
			if syntax = Void then
				is_fold_lines_stale := True
				closed_folds.follow_texts (a_old, a_new)
			else
					-- (the edit is found once for the two)
				closed_folds.follow_both (a_old, a_new, fold_lines)
			end
			if is_folding_shown or l_had_hidden then
				folds_changed (a_new)
			end
		end

	folds_touched (a_text: STRING_32)
			-- The folds of `a_text', the text now, may be new: see to the closed folds and
			-- the control, where either has a part in it.
		do
			if is_folding_shown or closed_folds.count > 0 then
				folds_changed (a_text)
			end
		end

	folds_changed (a_text: STRING_32)
			-- The folds of `a_text', the text now, are new or have moved. A closed fold
			-- stays closed while a fold starts on its first line, and reaches as far as
			-- that one; any other opens. A fold that would hide an end of the selection
			-- opens: the caret is never in a hidden line. Then the control is told.
		local
			l_folds, l_kept: GUI_LINE_RANGES
			i, k: INTEGER
			l_had_hidden: BOOLEAN
		do
			l_had_hidden := hidden_lines.count > 0
			if is_fold_lines_stale then
				create fold_lines.make_by_indentation (a_text, tab_width)
				is_fold_lines_stale := False
			end
			l_folds := fold_lines
			if closed_folds.count > 0 then
				create l_kept.make
				from
					i := 1
				until
					i > closed_folds.count
				loop
					k := l_folds.index_starting_at (closed_folds.first_line (i))
					if k > 0 then
						l_kept.put (l_folds.first_line (k), l_folds.last_line (k))
					end
					i := i + 1
				end
				closed_folds := l_kept
				if closed_folds.count > 0 then
					open_folds_hiding (line_at (a_text, selection_start))
					open_folds_hiding (line_at (a_text, selection_end + 1))
				end
			end
			hidden_lines := closed_folds.merged
			if is_folding_shown then
				send_fold_marks
			end
			if l_had_hidden or hidden_lines.count > 0 then
				send_hidden_lines
			end
		end

	closed_changed
			-- `closed_folds' changed: the hidden lines are found again and the control told.
		do
			hidden_lines := closed_folds.merged
			send_hidden_lines
		end

	open_every_fold
			-- No fold is closed; the control is told when one was.
		do
			if closed_folds.count > 0 then
				closed_folds.wipe_out
				closed_changed
			end
		ensure
			none_closed: closed_folds.count = 0
		end

	open_folds_hiding (a_line: INTEGER)
			-- Every closed fold that hides `a_line' is open in `closed_folds'. (The caller
			-- sees to `hidden_lines' and the control.)
		local
			i: INTEGER
		do
			from
				i := 1
			until
				i > closed_folds.count
			loop
				if closed_folds.first_line (i) < a_line and a_line <= closed_folds.last_line (i) then
					closed_folds.remove_starting_at (closed_folds.first_line (i))
				else
					i := i + 1
				end
			end
		end

	show_lines (a_first, a_last: INTEGER)
			-- Open every closed fold that hides line `a_first' or line `a_last'.
			-- Cost: nothing while no fold is closed.
		do
			if hidden_lines.count > 0 and then (hidden_lines.is_hidden (a_first) or hidden_lines.is_hidden (a_last)) then
				open_folds_hiding (a_first)
				open_folds_hiding (a_last)
				closed_changed
			end
		ensure
			shown: not hidden_lines.is_hidden (a_first) and not hidden_lines.is_hidden (a_last)
		end

	leave_hidden_lines
			-- Where an end of the selection is in a hidden line, put the caret at the end
			-- of the first line of what hides it, nothing selected.
			-- `has_left_hidden_lines' tells whether the caret went.
		local
			k, l_end: INTEGER
		do
			has_left_hidden_lines := False
			if hidden_lines.count > 0 then
				k := hidden_lines.index_hiding (line_at (highlighted, selection_start))
				if k = 0 then
					k := hidden_lines.index_hiding (line_at (highlighted, selection_end + 1))
				end
				if k > 0 then
					l_end := line_end (highlighted, hidden_lines.first_line (k))
					backend.rich_text_select (id, l_end, l_end - 1)
					has_left_hidden_lines := True
					look_for_bracket
				end
			end
		end

	fold_by_user (a_line, a_which: INTEGER)
			-- 57. `a_which' 0: the user clicked the marker beside `a_line'. 1: the fold key
			-- with the caret on `a_line', which closes the innermost open fold that holds
			-- the line. 2: the unfold key, which opens the closed fold that starts on it.
			-- `fold_actions' run; so do `caret_actions' when the fold moved the caret.
		local
			l_line: INTEGER
		do
			if a_which = 0 then
				if is_foldable (a_line) then
					l_line := a_line
				end
			elseif a_which = 1 then
				l_line := open_fold_holding (a_line)
			elseif a_which = 2 and then is_folded (a_line) then
				l_line := a_line
			end
			if l_line > 0 then
				has_left_hidden_lines := False
				toggle_fold (l_line)
				fold_actions.call ([l_line, is_folded (l_line)])
				if has_left_hidden_lines then
					caret_actions.call ([caret_line, caret_column])
				end
			end
		end

	open_fold_holding (a_line: INTEGER): INTEGER
			-- The first line of the innermost fold that holds `a_line' (its first line
			-- among them) and is open; 0 when there is none.
		local
			l_folds: GUI_LINE_RANGES
			i: INTEGER
		do
			l_folds := current_folds
			from
				i := l_folds.count_starting_before (a_line + 1)
			until
				i = 0 or Result > 0
			loop
				if l_folds.last_line (i) >= a_line and not closed_folds.has_start (l_folds.first_line (i)) then
					Result := l_folds.first_line (i)
				end
				i := i - 1
			end
		ensure
			none_or_foldable: Result = 0 or else (is_foldable (Result) and not is_folded (Result))
		end

	send_fold_marks
			-- Tell the control the lines that start a fold.
		local
			l_buffer: MANAGED_POINTER
			i, n: INTEGER
		do
			n := fold_lines.count
			create l_buffer.make (n.max (1) * 4)
			from
				i := 1
			until
				i > n
			loop
				l_buffer.put_integer_32 (fold_lines.first_line (i), (i - 1) * 4)
				i := i + 1
			end
			backend.code_set_fold_marks (id, l_buffer.item, n)
		end

	send_hidden_lines
			-- Tell the control the lines that are hidden.
		local
			l_buffer: MANAGED_POINTER
			i, n: INTEGER
		do
			n := hidden_lines.count
			create l_buffer.make (n.max (1) * 8)
			from
				i := 1
			until
				i > n
			loop
				l_buffer.put_integer_32 (hidden_lines.first_line (i), (i - 1) * 8)
				l_buffer.put_integer_32 (hidden_lines.last_line (i), (i - 1) * 8 + 4)
				i := i + 1
			end
			backend.code_set_folded_lines (id, l_buffer.item, n)
		end

	line_at (a_text: STRING_32; a_position: INTEGER): INTEGER
			-- The line of `a_text' a caret before character `a_position' is on. A position
			-- past the text counts as its end.
		do
			Result := 1 + line_breaks_in (a_text, 1, (a_position - 1).min (a_text.count).max (0))
		ensure
			positive: Result >= 1
		end

	line_end (a_text: STRING_32; a_line: INTEGER): INTEGER
			-- Where the line break that ends line `a_line' of `a_text' is (a caret before
			-- it is at the line's end); one past the text for its last line.
		require
			line_positive: a_line >= 1
		local
			l_line: INTEGER
		do
			from
				l_line := 1
				Result := a_text.index_of ('%N', 1)
			until
				Result = 0 or l_line = a_line
			loop
				l_line := l_line + 1
				Result := a_text.index_of ('%N', Result + 1)
			end
			if Result = 0 then
				Result := a_text.count + 1
			end
		ensure
			in_or_just_past: 1 <= Result and Result <= a_text.count + 1
		end

feature {NONE} -- Multiple carets

	extra_carets: ARRAYED_LIST [TUPLE [caret, anchor: INTEGER]]
			-- The carets after the control's own: each a caret's position and its anchor (the
			-- other end of its selection), from 1 to the text's count + 1.

	add_extra (a_caret, an_anchor: INTEGER)
			-- Another caret at `a_caret' selecting back to `an_anchor', unless it meets one.
		do
			if not caret_meets (a_caret.min (an_anchor), a_caret.max (an_anchor)) then
				extra_carets.extend ([a_caret, an_anchor])
				show_lines (line_at (highlighted, a_caret.min (an_anchor)), line_at (highlighted, a_caret.max (an_anchor)))
				close_completion
				send_extra_carets
			end
		end

	caret_meets (a_lo, a_hi: INTEGER): BOOLEAN
			-- Does the span `a_lo' .. `a_hi' (positions) meet a caret or a selection?
		do
			Result := spans_meet (a_lo, a_hi, selection_start, selection_end + 1)
			across extra_carets as ic until Result loop
				Result := spans_meet (a_lo, a_hi, ic.caret.min (ic.anchor), ic.caret.max (ic.anchor))
			end
		end

	spans_meet (a_lo, a_hi, b_lo, b_hi: INTEGER): BOOLEAN
			-- Do two spans of positions share more than an end, or are they one place?
		do
			Result := (a_lo = b_lo and a_hi = b_hi) or (a_lo < b_hi and b_lo < a_hi)
		end

	last_caret_end: INTEGER
			-- The furthest position any caret reaches.
		do
			Result := selection_end + 1
			across extra_carets as ic loop
				Result := Result.max (ic.caret.max (ic.anchor))
			end
		end

	send_extra_carets
			-- Tell the control where the extra carets are.
		local
			l_pairs: MANAGED_POINTER
			i: INTEGER
		do
			create l_pairs.make ((extra_carets.count * 8).max (8))
			from i := 1 until i > extra_carets.count loop
				l_pairs.put_integer_32 (extra_carets [i].caret, (i - 1) * 8)
				l_pairs.put_integer_32 (extra_carets [i].anchor, (i - 1) * 8 + 4)
				i := i + 1
			end
			backend.code_set_extra_carets (id, l_pairs.item, extra_carets.count)
		end

	all_carets: ARRAYED_LIST [TUPLE [caret, anchor: INTEGER; own: BOOLEAN]]
			-- Every caret in order of place, the control's own marked.
		local
			l_new: TUPLE [caret, anchor: INTEGER; own: BOOLEAN]
			i: INTEGER
		do
			create Result.make (caret_count)
			if selection_start > selection_end then
				Result.extend ([selection_start, selection_start, True])
			else
				Result.extend ([selection_end + 1, selection_start, True])
			end
			across extra_carets as ic loop
				l_new := [ic.caret, ic.anchor, False]
				from
					i := 1
				until
					i > Result.count or else Result [i].caret.min (Result [i].anchor) > l_new.caret.min (l_new.anchor)
				loop
					i := i + 1
				end
				Result.go_i_th (i)
				Result.put_left (l_new)
			end
		end

	set_carets (a_carets: ARRAYED_LIST [TUPLE [caret, anchor: INTEGER; own: BOOLEAN]])
			-- Carets in order of place: those that meet become one; the control's own (or,
			-- when it merged away, the first) goes to the control, the rest are extra.
		local
			l_kept: ARRAYED_LIST [TUPLE [caret, anchor: INTEGER; own: BOOLEAN]]
			l_last: TUPLE [caret, anchor: INTEGER; own: BOOLEAN]
			l_own: detachable TUPLE [caret, anchor: INTEGER; own: BOOLEAN]
			l_lo, l_hi: INTEGER
			l_merged: BOOLEAN
		do
			create l_kept.make (a_carets.count)
			across a_carets as ic loop
				l_merged := False
				if not l_kept.is_empty then
					l_last := l_kept.last
					l_lo := l_last.caret.min (l_last.anchor)
					l_hi := l_last.caret.max (l_last.anchor)
					if spans_meet (l_lo, l_hi, ic.caret.min (ic.anchor), ic.caret.max (ic.anchor)) then
							-- they meet: one caret over both
						l_last.anchor := l_lo.min (ic.caret.min (ic.anchor))
						l_last.caret := l_hi.max (ic.caret.max (ic.anchor))
						l_last.own := l_last.own or ic.own
						l_merged := True
					end
				end
				if not l_merged then
					l_kept.extend ([ic.caret, ic.anchor, ic.own])
				end
			end
			extra_carets.wipe_out
			across l_kept as ic loop
				if ic.own and l_own = Void then
					l_own := ic
				else
					extra_carets.extend ([ic.caret, ic.anchor])
				end
			end
			if l_own = Void and then not extra_carets.is_empty then
				l_own := [extra_carets.first.caret, extra_carets.first.anchor, True]
				extra_carets.start
				extra_carets.remove
			end
			if attached l_own as al_own then
				backend.rich_text_select (id, al_own.caret.min (al_own.anchor), al_own.caret.max (al_own.anchor) - 1)
			end
			send_extra_carets
		end

	act_at_carets (a_action: INTEGER; a_shift: BOOLEAN; a_typed: STRING_32)
			-- Event 60 with extra carets: the same action at every caret. Edits are worked
			-- out on the text as it is, then applied from the last to the first as one group:
			-- one undo step, one change event.
		require
			an_action: 1 <= a_action and a_action <= 15
		local
			l_text, l_insert: STRING_32
			l_clip: detachable STRING_32
			l_carets: like all_carets
			l_new: like all_carets
			l_lines: detachable LIST [STRING_32]
			l_edits: ARRAYED_LIST [TUPLE [start, stop: INTEGER; insert: STRING_32; offset: INTEGER]]
			l_lo, l_hi, l_start, l_stop, l_offset, l_prev_stop, l_delta, l_moved, i, n: INTEGER
			l_c: C_STRING
		do
			if a_action = 15 then
				clear_extra_carets
			else
				l_text := text
				l_carets := all_carets
				if 6 <= a_action and a_action <= 11 then
					across l_carets as ic loop
						l_moved := moved_caret (l_text, ic.caret, ic.anchor, a_action, a_shift)
						if not a_shift then
							ic.anchor := l_moved
						end
						ic.caret := l_moved
					end
					set_carets (l_carets)
				else
					if a_action = 12 or a_action = 13 then
						copy_selections (l_carets, l_text)
					end
					if a_action /= 13 then
						if a_action = 14 then
							l_clip := application.clipboard.text
							l_lines := l_clip.split ('%N')
						end
						create l_edits.make (l_carets.count)
						l_prev_stop := 0
						i := 0
						across l_carets as ic loop
							i := i + 1
							l_lo := ic.caret.min (ic.anchor)
							l_hi := ic.caret.max (ic.anchor)
							l_start := l_lo
							l_stop := l_hi - 1
							create l_insert.make_empty
							l_offset := 0
							inspect a_action
							when 1 then
								l_insert := a_typed.twin
								l_offset := l_insert.count
							when 2 then
								l_insert := {STRING_32} "%N" + leading_space (l_text, l_lo)
								l_offset := l_insert.count
							when 3 then
								if a_shift then
									l_start := line_start_of (l_text, l_lo)
									n := unindent_count (l_text, l_start)
									l_stop := l_start + n - 1
									l_offset := (l_lo - n - l_start).max (0)
								else
									l_insert := indent_unit (l_lo - line_start_of (l_text, l_lo))
									l_offset := l_insert.count
								end
							when 4 then
								if l_hi = l_lo and l_lo > 1 then
									l_start := l_lo - 1
									l_stop := l_lo - 1
								end
							when 5 then
								if l_hi = l_lo and l_lo <= l_text.count then
									l_stop := l_lo
								end
							when 14 then
								if attached l_lines as al_lines and then al_lines.count = l_carets.count and then l_carets.count > 1 then
									l_insert := al_lines [i]
								elseif attached l_clip as al_clip then
									l_insert := al_clip.twin
								end
								l_offset := l_insert.count
							else
									-- 12, cut: the selection goes
							end
								-- never twice over one character
							if l_start <= l_prev_stop then
								l_start := l_prev_stop + 1
								l_stop := l_stop.max (l_start - 1)
							end
							l_prev_stop := l_stop.max (l_prev_stop)
							l_edits.extend ([l_start, l_stop, l_insert, l_offset])
						end
						backend.text_begin_edit_group (id)
						from i := l_edits.count until i < 1 loop
							if l_edits [i].stop >= l_edits [i].start or not l_edits [i].insert.is_empty then
								l_c := backend.to_c (l_edits [i].insert)
								backend.text_replace_range (id, l_edits [i].start, l_edits [i].stop, l_c.item)
							end
							i := i - 1
						end
						backend.text_end_edit_group (id)
						create l_new.make (l_carets.count)
						l_delta := 0
						from i := 1 until i > l_edits.count loop
							l_moved := l_edits [i].start + l_delta + l_edits [i].offset
							l_new.extend ([l_moved, l_moved, l_carets [i].own])
							l_delta := l_delta + l_edits [i].insert.count - (l_edits [i].stop - l_edits [i].start + 1)
							i := i + 1
						end
						set_carets (l_new)
					end
				end
			end
		end

	moved_caret (a_text: STRING_32; a_caret, an_anchor, a_action: INTEGER; a_shift: BOOLEAN): INTEGER
			-- Where a caret at `a_caret' (anchor `an_anchor') goes for movement `a_action':
			-- 6 Left, 7 Right, 8 Up, 9 Down, 10 Home, 11 End. Without Shift a selection
			-- collapses to its near end first for Left and Right.
		local
			l_start, l_end, l_column: INTEGER
		do
			Result := a_caret
			inspect a_action
			when 6 then
				if not a_shift and a_caret /= an_anchor then
					Result := a_caret.min (an_anchor)
				else
					Result := (a_caret - 1).max (1)
				end
			when 7 then
				if not a_shift and a_caret /= an_anchor then
					Result := a_caret.max (an_anchor)
				else
					Result := (a_caret + 1).min (a_text.count + 1)
				end
			when 8 then
				l_start := line_start_of (a_text, a_caret)
				if l_start > 1 then
					l_column := a_caret - l_start
					l_start := line_start_of (a_text, l_start - 1)
					Result := (l_start + l_column).min (line_end_of (a_text, l_start))
				end
			when 9 then
				l_end := line_end_of (a_text, a_caret)
				if l_end <= a_text.count then
					l_column := a_caret - line_start_of (a_text, a_caret)
					Result := (l_end + 1 + l_column).min (line_end_of (a_text, l_end + 1))
				end
			when 10 then
				Result := line_start_of (a_text, a_caret)
			when 11 then
				Result := line_end_of (a_text, a_caret)
			else
			end
		ensure
			in_text: 1 <= Result and Result <= a_text.count + 1
		end

	line_start_of (a_text: STRING_32; a_position: INTEGER): INTEGER
			-- Where the line holding position `a_position' starts.
		do
			from
				Result := a_position.min (a_text.count + 1).max (1)
			until
				Result <= 1 or else a_text [Result - 1] = '%N'
			loop
				Result := Result - 1
			end
		end

	line_end_of (a_text: STRING_32; a_position: INTEGER): INTEGER
			-- The position at the end of the line holding `a_position' (before its break).
		do
			from
				Result := a_position.min (a_text.count + 1).max (1)
			until
				Result > a_text.count or else a_text [Result] = '%N'
			loop
				Result := Result + 1
			end
		end

	leading_space (a_text: STRING_32; a_position: INTEGER): STRING_32
			-- The spaces and tabs that start the line of `a_position', up to it.
		local
			i: INTEGER
		do
			create Result.make (8)
			from
				i := line_start_of (a_text, a_position)
			until
				i >= a_position or else i > a_text.count or else (a_text [i] /= ' ' and a_text [i] /= '%T')
			loop
				Result.append_character (a_text [i])
				i := i + 1
			end
		end

	indent_unit (a_column: INTEGER): STRING_32
			-- What Tab inserts at column `a_column' (from 0): a tab, or spaces to the next stop.
		do
			if is_indent_with_spaces then
				create Result.make_filled (' ', tab_width - (a_column \\ tab_width))
			else
				Result := "%T"
			end
		end

	unindent_count (a_text: STRING_32; a_line_start: INTEGER): INTEGER
			-- How many characters Shift+Tab takes from the start of the line at `a_line_start':
			-- one tab, or up to `tab_width' spaces.
		do
			if a_line_start <= a_text.count and then a_text [a_line_start] = '%T' then
				Result := 1
			else
				from until
					Result >= tab_width or else a_line_start + Result > a_text.count or else a_text [a_line_start + Result] /= ' '
				loop
					Result := Result + 1
				end
			end
		end

	copy_selections (a_carets: like all_carets; a_text: STRING_32)
			-- The clipboard: each caret's selection, top to bottom, joined by line breaks.
		local
			l_joined: STRING_32
			l_lo, l_hi: INTEGER
		do
			create l_joined.make (64)
			across a_carets as ic loop
				l_lo := ic.caret.min (ic.anchor)
				l_hi := ic.caret.max (ic.anchor)
				if l_hi > l_lo then
					if not l_joined.is_empty then
						l_joined.append_character ('%N')
					end
					l_joined.append (a_text.substring (l_lo, l_hi - 1))
				end
			end
			if not l_joined.is_empty then
				application.clipboard.set_text (l_joined)
			end
		end

	caret_gesture (a_gesture, a_position: INTEGER)
			-- Event 61: 1 Alt+click at `a_position' (add a caret, or remove the one there),
			-- 2 add one below the last caret, 3 above the first, 4 the next occurrence.
		local
			l_carets: like all_carets
			l_at, l_moved, i: INTEGER
			l_found: BOOLEAN
		do
			inspect a_gesture
			when 1 then
				l_at := a_position.max (1).min (highlighted.count + 1)
				from i := 1 until i > extra_carets.count or l_found loop
					if extra_carets [i].caret = l_at and extra_carets [i].anchor = l_at then
						l_found := True
						extra_carets.go_i_th (i)
						extra_carets.remove
						send_extra_carets
					end
					i := i + 1
				end
				if not l_found then
					if selection_start > selection_end and selection_start = l_at then
						if not extra_carets.is_empty then
								-- the control's own goes: the first extra one takes its place
							set_carets (without_own (all_carets))
						end
					else
						add_extra (l_at, l_at)
					end
				end
			when 2, 3 then
				l_carets := all_carets
				if a_gesture = 2 then
					l_at := l_carets.last.caret
					l_moved := moved_caret (highlighted, l_at, l_at, 9, False)
				else
					l_at := l_carets.first.caret
					l_moved := moved_caret (highlighted, l_at, l_at, 8, False)
				end
				if l_moved /= l_at then
					add_extra (l_moved, l_moved)
				end
			when 4 then
				add_next_occurrence
			else
			end
		end

	without_own (a_carets: like all_carets): like all_carets
			-- `a_carets' less the control's own, the first of the rest made the own.
		do
			create Result.make (a_carets.count)
			across a_carets as ic loop
				if not ic.own then
					Result.extend ([ic.caret, ic.anchor, Result.is_empty])
				end
			end
		end

feature {NONE} -- Completion

	completion_words: ARRAYED_LIST [GUI_COMPLETION]
			-- The fixed list (`set_completion_words').

	completion_offers: ARRAYED_LIST [GUI_COMPLETION]
			-- Every offer for the word with a list, in the sources' order: the fixed list,
			-- the completer's, then what `add_completions' added.

	completion_shown: ARRAYED_LIST [GUI_COMPLETION]
			-- The rows: the offers that match `completion_word'.

	completion_start: INTEGER
			-- Where the word with a list starts; 0 when there is none. A list with no rows
			-- yet (a slow source has not answered) keeps its word here.

	completion_word: STRING_32
			-- The word the rows were matched against.

	Completion_page: INTEGER = 8
			-- Rows Page Up and Page Down move: the list's height.

	open_completion
			-- A list for the word before the caret: gather the offers, tell
			-- `completion_opened_actions', and show the rows that match.
		local
			l_caret, l_start: INTEGER
		do
			close_completion
			l_caret := selection_start.min (highlighted.count + 1)
			l_start := word_start_before (l_caret)
			completion_start := l_start
			completion_word := highlighted.substring (l_start, l_caret - 1)
			completion_offers.append (completion_words)
			if attached completer as al_completer then
				across al_completer.item ([completion_word.twin, caret_line, caret_column]) as ic loop
					completion_offers.extend (ic)
				end
			end
			completion_opened_actions.call ([l_start])
			filter_completions
		ensure
			for_the_word: completion_start > 0
		end

	filter_completions
			-- The rows again: offers whose label starts with `completion_word', then those
			-- whose label holds it elsewhere, each group in the sources' order, case ignored.
			-- Shown (the first row highlighted), or hidden when none match.
		local
			l_word: STRING_32
			l_later: ARRAYED_LIST [GUI_COMPLETION]
			l_at: INTEGER
		do
			l_word := completion_word.as_lower
			completion_shown.wipe_out
			create l_later.make (4)
			across completion_offers as ic loop
				if l_word.is_empty then
					completion_shown.extend (ic)
				else
					l_at := ic.label.as_lower.substring_index (l_word, 1)
					if l_at = 1 then
						completion_shown.extend (ic)
					elseif l_at > 1 then
						l_later.extend (ic)
					end
				end
			end
			completion_shown.append (l_later)
			if completion_shown.is_empty then
				completion_selected := 0
				backend.code_hide_completions (id)
			else
				completion_selected := 1
				show_completion_rows
			end
		ensure
			first_highlighted: completion_selected = completion_shown.count.min (1)
		end

	show_completion_rows
			-- Hand the rows to the control: rows joined by 0x1F, and in a row the label, the
			-- detail and the kind joined by 0x1E.
		require
			has_rows: completion_shown.count > 0
			highlighted_row: 1 <= completion_selected and completion_selected <= completion_shown.count
		local
			l_joined: STRING_32
			l_c: C_STRING
			l_first: BOOLEAN
		do
			create l_joined.make (32 * completion_shown.count)
			l_first := True
			across completion_shown as ic loop
				if not l_first then
					l_joined.append_character ((0x1F).to_character_32)
				end
				l_first := False
				l_joined.append (ic.label)
				l_joined.append_character ((0x1E).to_character_32)
				l_joined.append (ic.detail)
				l_joined.append_character ((0x1E).to_character_32)
				l_joined.append_integer (ic.kind)
			end
			l_c := backend.to_c (l_joined)
			backend.code_show_completions (id, l_c.item, completion_selected)
		end

	close_completion
			-- No list, and no word waiting for one.
		do
			if completion_start > 0 then
				backend.code_hide_completions (id)
				completion_start := 0
				completion_selected := 0
				completion_offers.wipe_out
				completion_shown.wipe_out
			end
		ensure
			closed: completion_start = 0 and not is_completing
		end

	completion_key (a_key: INTEGER)
			-- Event 58: 0 open a list; with one showing, 1 Up, 2 Down, 3 Page Up, 4 Page Down
			-- move, 5 accepts, 6 closes (Escape, or the control hid it).
		do
			inspect a_key
			when 0 then
				if extra_carets.is_empty then
					open_completion
				end
			when 1 then
				move_completion (-1)
			when 2 then
				move_completion (1)
			when 3 then
				move_completion (- Completion_page)
			when 4 then
				move_completion (Completion_page)
			when 5 then
				if is_completing then
					accept_completion (completion_selected)
				end
			when 6 then
				close_completion
			else
			end
		end

	move_completion (a_by: INTEGER)
			-- Highlight the row `a_by' rows on, kept within the list.
		do
			if is_completing then
				completion_selected := (completion_selected + a_by).max (1).min (completion_shown.count)
				backend.code_select_completion (id, completion_selected)
			end
		ensure
			in_list: is_completing implies (1 <= completion_selected and completion_selected <= completion_count)
		end

	accept_completion (a_row: INTEGER)
			-- Put row `a_row''s text in place of the word, as one undo step, with the caret
			-- after it; then `completion_accepted_actions'.
		require
			valid: 1 <= a_row and a_row <= completion_count
		local
			l_text: STRING_32
			l_start, l_end, l_after: INTEGER
			l_c: C_STRING
		do
			l_text := completion_shown [a_row].text.twin
			l_start := completion_start
			l_end := (selection_start - 1).max (l_start - 1)
			close_completion
			l_c := backend.to_c (l_text)
			backend.text_replace_range (id, l_start, l_end, l_c.item)
			l_after := l_start + l_text.count
			backend.rich_text_select (id, l_after, l_after - 1)
			program_edited
			completion_accepted_actions.call ([l_text])
		ensure
			closed: not is_completing
		end

	completion_follow_edit (a_grown: INTEGER)
			-- The user edited the text, which grew by `a_grown' characters: an open list
			-- narrows or widens to the word before the caret, and closes when the caret has
			-- left the word or the word is gone. With none open, typing that brings the word
			-- before the caret to `completion_auto_count' characters or more opens one.
		local
			l_caret, l_start: INTEGER
		do
			l_caret := selection_start.min (highlighted.count + 1)
			l_start := word_start_before (l_caret)
			if completion_start > 0 then
				if l_start = completion_start and l_caret > l_start then
					completion_word := highlighted.substring (l_start, l_caret - 1)
					filter_completions
				else
					close_completion
				end
			elseif extra_carets.is_empty and then completion_auto_count > 0 and then a_grown >= 1 and then a_grown <= l_caret - l_start
				and then l_caret - l_start >= completion_auto_count
			then
					-- what the edit added is all word, before the caret: typed (two keys can
					-- land before one change event), not pasted with other text
				open_completion
			end
		end

	completion_caret_moved
			-- The user moved the caret (52): an open list closes unless the caret is still at
			-- the end of its word (typing moves the caret there too).
		local
			l_caret: INTEGER
		do
			if completion_start > 0 then
				l_caret := selection_start.min (highlighted.count + 1)
				if word_start_before (l_caret) /= completion_start
					or else (l_caret <= highlighted.count and then is_word_character (highlighted [l_caret]))
				then
					close_completion
				end
			end
		end

	word_start_before (a_caret: INTEGER): INTEGER
			-- Where the run of word characters that ends just before position `a_caret'
			-- starts in `highlighted'; `a_caret' itself when there is none.
		require
			in_text: 1 <= a_caret and a_caret <= highlighted.count + 1
		do
			from
				Result := a_caret
			until
				Result <= 1 or else not is_word_character (highlighted [Result - 1])
			loop
				Result := Result - 1
			end
		ensure
			at_or_before: 1 <= Result and Result <= a_caret
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
	stale_folds_are_by_indentation: is_fold_lines_stale implies syntax = Void
	hidden_only_when_closed: closed_folds.count = 0 implies hidden_lines.count = 0
	hidden_lines_apart: hidden_lines.is_disjoint
	pair_only_when_matching: has_bracket_pair implies is_bracket_matching
	pair_answers_the_bracket_asked: has_bracket_pair implies bracket_asked >= 1
	pair_in_order: has_bracket_pair implies (1 <= bracket_first and bracket_first < bracket_second)

end
