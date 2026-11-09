note
	description: "[
		The application's reference pills (1l), defined once and put on widgets by code
		(`GUI_WIDGET.set_pill'). Shown or hidden together (`GUI_APPLICATION.set_pills_shown',
		or the item `GUI_MENU.add_pills_item' adds). `as_markdown' writes the list as a table for
		the program's documentation, so the pills and the docs say the same thing.
	]"

class
	GUI_PILLS

create {GUI_APPLICATION}
	make

feature {NONE} -- Initialization

	make
		do
			create definitions.make (16)
		ensure
			none: count = 0
		end

feature -- Access

	count: INTEGER
			-- Pills defined.
		do
			Result := definitions.count
		end

	has (a_code: READABLE_STRING_GENERAL): BOOLEAN
			-- Is a pill coded `a_code' defined?
		do
			Result := across definitions as ic some ic.code.same_string_general (a_code) end
		end

	item (a_code: READABLE_STRING_GENERAL): GUI_PILL
			-- The pill coded `a_code'.
		require
			defined: has (a_code)
		local
			l_found: detachable GUI_PILL
		do
			across definitions as ic until attached l_found loop
				if ic.code.same_string_general (a_code) then
					l_found := ic
				end
			end
			check attached l_found as al_pill then
				Result := al_pill
			end
		ensure
			coded: Result.code.same_string_general (a_code)
		end

	definitions: ARRAYED_LIST [GUI_PILL]
			-- In the order defined.

feature -- Element change

	define (a_code, a_name: READABLE_STRING_GENERAL): GUI_PILL
			-- A new pill coded `a_code', naming `a_name'; fill it with `with_purpose', `with_flow',
			-- `with_shortcut', `with_menu_path' or `with_menu_item'.
		require
			coded: not a_code.is_empty
			named: not a_name.is_empty
			new: not has (a_code)
		do
			create Result.make (a_code, a_name)
			definitions.extend (Result)
		ensure
			defined: has (a_code) and then item (a_code) = Result
			one_more: count = old count + 1
		end

feature -- Documentation

	as_markdown: STRING_32
			-- The pills as a Markdown table: code, name, what it does, place in the flow,
			-- keyboard and menu (shortcuts as this platform writes them).
		local
			l_pill: GUI_PILL
		do
			create Result.make (256 + 128 * count)
			Result.append ({STRING_32} "| Code | Name | What it does | In the flow | Keyboard | Menu |%N")
			Result.append ({STRING_32} "|---|---|---|---|---|---|%N")
			across definitions as ic loop
				l_pill := ic
				Result.append ({STRING_32} "| ")
				Result.append (cell (l_pill.code))
				Result.append ({STRING_32} " | ")
				Result.append (cell (l_pill.name))
				Result.append ({STRING_32} " | ")
				Result.append (cell (l_pill.purpose))
				Result.append ({STRING_32} " | ")
				Result.append (cell (l_pill.flow))
				Result.append ({STRING_32} " | ")
				Result.append (cell (l_pill.shown_shortcut (l_pill.shortcut)))
				Result.append ({STRING_32} " | ")
				Result.append (cell (l_pill.menu_path))
				Result.append ({STRING_32} " |%N")
			end
		end

feature {NONE} -- Implementation

	cell (a_text: STRING_32): STRING_32
			-- `a_text' fit for a table cell: pipes escaped, line breaks as spaces.
		do
			Result := a_text.twin
			Result.replace_substring_all ({STRING_32} "|", {STRING_32} "\|")
			Result.replace_substring_all ({STRING_32} "%N", {STRING_32} " ")
		end

invariant
	definitions_exist: definitions /= Void

end
