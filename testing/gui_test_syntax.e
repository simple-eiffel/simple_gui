note
	description: "[
		A syntax object for the tests (1v-e-1): no parser, it records what the editor tells
		it and keeps its own copy of the text, made by applying each reported edit to it.
		A test then asks that `copy_text' still equals the editor's text.
	]"

class
	GUI_TEST_SYNTAX

inherit
	GUI_EDITOR_SYNTAX

create
	make

feature {NONE} -- Initialization

	make
		do
			create copy_text.make_empty
			create last_inserted.make_empty
			create log.make_empty
		end

feature -- Access

	editor: detachable GUI_CODE_EDITOR

	copy_text: STRING_32
			-- The text as this object knows it: what it was told, edit by edit.

	log: STRING
			-- The calls in order: "A" attach, "D" detach, "R" replaced, "E" edited,
			-- "B" bracket wanted.

	attach_count, detach_count, replaced_count, edit_count: INTEGER

	last_start, last_removed: INTEGER

	last_inserted: STRING_32

	false_edits: INTEGER
			-- Edits reported that do not fit `copy_text' (never applied).

feature -- Attachment

	attach (an_editor: GUI_CODE_EDITOR)
		do
			editor := an_editor
			copy_text := an_editor.text
			attach_count := attach_count + 1
			log.append_character ('A')
		end

	detach
		do
			editor := Void
			detach_count := detach_count + 1
			log.append_character ('D')
		end

feature -- Changes

	text_replaced (a_text: READABLE_STRING_32)
		do
			create copy_text.make_from_string (a_text)
			replaced_count := replaced_count + 1
			log.append_character ('R')
		end

	text_edited (a_start, a_removed: INTEGER; an_inserted: READABLE_STRING_32)
		do
			edit_count := edit_count + 1
			last_start := a_start
			last_removed := a_removed
			create last_inserted.make_from_string (an_inserted)
			log.append_character ('E')
			if a_start <= copy_text.count + 1 and a_start + a_removed - 1 <= copy_text.count then
				copy_text.replace_substring (last_inserted, a_start, a_start + a_removed - 1)
			else
				false_edits := false_edits + 1
			end
		end

feature -- Coloring by the view

	wanted: ARRAYED_LIST [TUPLE [first, last: INTEGER]]
			-- Each range `spans_wanted' was asked for, in order.
		attribute
			create Result.make (8)
		end

	span_maker: detachable FUNCTION [INTEGER, INTEGER, GUI_SYNTAX_SPANS]
			-- Answers `spans_wanted' at once with the spans it makes for the lines; Void: no
			-- answer (a test then answers itself, as a parser on another processor would).

	set_span_maker (a_maker: like span_maker)
		do
			span_maker := a_maker
		ensure
			set: span_maker = a_maker
		end

	spans_wanted (a_first_line, a_last_line: INTEGER)
		do
			wanted.extend ([a_first_line, a_last_line])
			if attached editor as al_editor and then attached span_maker as al_maker then
				al_editor.apply_spans (a_first_line, a_last_line, al_maker.item ([a_first_line, a_last_line]))
			end
		end

feature -- Brackets

	bracket_position: INTEGER
			-- Where the bracket last asked about is; 0 before any.

	bracket_count: INTEGER
			-- How many times a bracket's partner was wanted.

	pair_answer: detachable TUPLE [first_start, first_count, second_start, second_count: INTEGER]
			-- What `bracket_wanted' answers with at once; Void: it answers nothing (a test
			-- then answers a turn later, as a parser on another processor would).

	set_pair_answer (an_answer: like pair_answer)
		do
			pair_answer := an_answer
		ensure
			set: pair_answer = an_answer
		end

	bracket_wanted (a_position: INTEGER)
		do
			log.append_character ('B')
			bracket_position := a_position
			bracket_count := bracket_count + 1
			if attached editor as al_editor and then attached pair_answer as al_answer then
				al_editor.show_bracket_pair (al_answer.first_start, al_answer.first_count,
					al_answer.second_start, al_answer.second_count)
			end
		end

end
