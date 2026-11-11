note
	description: "[
		A find-and-replace bar for a GUI_CODE_EDITOR (1v-b): a find field, Previous and Next,
		Match case, a replace field, Replace and Replace all, and a status ("3 replaced",
		"Not found"). A shared composite the program places above the editor and shows with
		`show' (Command or Ctrl+F, say) and hides with `hide' (Escape). Return in the find
		field goes to the next match.
	]"

class
	GUI_FIND_BAR

inherit
	GUI_STACK
		rename
			make_vertical as make_stack
		export
			{NONE} make_stack, make_horizontal, extend, extend_stretching, extend_aligned
		end

create
	make

feature {NONE} -- Initialization

	make (an_editor: GUI_CODE_EDITOR)
		require
			gui_thread: is_gui_thread
			has_application: has_application
		local
			l_find_row, l_replace_row: GUI_STACK
		do
				-- every part first: the stack registers Current, which must then be whole
			editor := an_editor
			create find_field.make
			create replace_field.make
			create previous_button.make ("Previous")
			create next_button.make ("Next")
			create replace_button.make ("Replace")
			create replace_all_button.make ("Replace all")
			create case_box.make ("Match case")
			create status.make (" ")
			make_stack
			set_spacing (4)
			find_field.set_accessible_label ("Find")
			replace_field.set_accessible_label ("Replace with")
			create l_find_row.make_horizontal
			l_find_row.set_spacing (6)
			l_find_row.extend_stretching (find_field)
			l_find_row.extend (previous_button)
			l_find_row.extend (next_button)
			l_find_row.extend (case_box)
			create l_replace_row.make_horizontal
			l_replace_row.set_spacing (6)
			l_replace_row.extend_stretching (replace_field)
			l_replace_row.extend (replace_button)
			l_replace_row.extend (replace_all_button)
			l_replace_row.extend (status)
			extend (l_find_row)
			extend (l_replace_row)
			next_button.click_actions.extend (agent find_next)
			previous_button.click_actions.extend (agent find_previous)
			replace_button.click_actions.extend (agent replace_one)
			replace_all_button.click_actions.extend (agent replace_every)
			find_field.activate_actions.extend (agent find_next)
		end

feature -- Access

	editor: GUI_CODE_EDITOR
	find_field, replace_field: GUI_TEXT_FIELD
	previous_button, next_button, replace_button, replace_all_button: GUI_BUTTON
	case_box: GUI_CHECK_BOX
	status: GUI_LABEL

feature -- Basic operations

	find_next
		do
			if not find_field.text.is_empty then
				report (editor.find_next (find_field.text, case_box.is_checked, False), "")
			end
		end

	find_previous
		do
			if not find_field.text.is_empty then
				report (editor.find_previous (find_field.text, case_box.is_checked, False), "")
			end
		end

	replace_one
			-- Replace the selection when it is a match, then find the next.
		local
			l_selected: STRING_32
		do
			if not find_field.text.is_empty then
				if editor.selection_end >= editor.selection_start then
					l_selected := editor.text.substring (editor.selection_start, editor.selection_end)
					if l_selected.same_string (find_field.text) or else (not case_box.is_checked and then l_selected.as_lower.same_string (find_field.text.as_lower)) then
						editor.replace_selection (replace_field.text)
					end
				end
				find_next
			end
		end

	replace_every
		local
			l_n: INTEGER
		do
			if not find_field.text.is_empty then
				l_n := editor.replace_all (find_field.text, replace_field.text, case_box.is_checked, False)
				status.set_text (l_n.out + " replaced")
			end
		end

feature {NONE} -- Implementation

	report (a_found: BOOLEAN; a_text: STRING)
		do
			if a_found then status.set_text (" ") else status.set_text ("Not found") end
		end

end
