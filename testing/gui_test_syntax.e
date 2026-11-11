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

feature -- Brackets

	bracket_wanted (a_position: INTEGER)
		do
			log.append_character ('B')
		end

end
