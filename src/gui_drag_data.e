note
	description: "[
		What a widget gives other programs when the user drags out of it (1q-c): text, file
		paths, or both. The program keeps it current with GUI_WIDGET.set_drag_out (on a list,
		set it again when the selection changes), because every toolkit wants the data in
		hand the moment a drag starts.
	]"

class
	GUI_DRAG_DATA

create
	make, make_text, make_files

feature {NONE} -- Initialization

	make (a_text: READABLE_STRING_GENERAL; a_paths: ITERABLE [PATH])
			-- Carry `a_text' and `a_paths' together.
		require
			something: not a_text.is_empty or across a_paths as ic some True end
		do
			create text.make_from_string_general (a_text)
			create paths.make (2)
			across a_paths as ic loop
				paths.extend (ic)
			end
		ensure
			text_set: text.same_string_general (a_text)
		end

	make_text (a_text: READABLE_STRING_GENERAL)
			-- Carry `a_text' alone.
		require
			something: not a_text.is_empty
		do
			make (a_text, create {ARRAYED_LIST [PATH]}.make (0))
		ensure
			text_set: text.same_string_general (a_text)
			no_paths: paths.is_empty
		end

	make_files (a_paths: ITERABLE [PATH])
			-- Carry `a_paths' alone.
		require
			something: across a_paths as ic some True end
		do
			make ({STRING_32} "", a_paths)
		ensure
			no_text: text.is_empty
		end

feature -- Access

	text: STRING_32
			-- The text dragged out (empty: none).

	paths: ARRAYED_LIST [PATH]
			-- The files dragged out (empty: none).

	joined_paths: STRING_32
			-- `paths' one per line, as the backend takes them.
		do
			create Result.make (80)
			across paths as ic loop
				if not Result.is_empty then
					Result.append_character ('%N')
				end
				Result.append (ic.name)
			end
		end

invariant
	something: not text.is_empty or not paths.is_empty

end
