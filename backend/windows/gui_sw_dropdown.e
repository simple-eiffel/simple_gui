note
	description: "[
		GUI_DROPDOWN on Windows: simple_widgets' combo made read-only, so a click anywhere on
		it opens the option menu. It tracks the selected row. A pick of a different row is
		reported through `on_pick'; picking the row already selected is not, as on GTK and
		macOS.
	]"

class
	GUI_SW_DROPDOWN

inherit
	SW_COMBO
		redefine
			handle_click
		end

create
	make_dropdown

feature {NONE} -- Initialization

	make_dropdown
		do
			make_with_options
			set_read_only (True)
		ensure
			empty: options.is_empty
			none_selected: selected_index = 0
		end

feature -- Access

	selected_index: INTEGER
			-- The selected option, or 0 when there are none.

	on_pick: detachable PROCEDURE [INTEGER]
			-- Run with the row when the user picks a different option.

feature -- Element change

	set_on_pick (a_action: PROCEDURE [INTEGER])
		do
			on_pick := a_action
		ensure
			set: on_pick = a_action
		end

	menu_rows: ARRAYED_LIST [TUPLE [kind: INTEGER; text: STRING_32; choice: INTEGER]]
			-- The popup's rows in order: choices (kind 0, by their number), group headers (1) and
			-- separators (2), which are not choices (simple_gui 1p).
		attribute
			create Result.make (4)
		end

	add_header (a_text: READABLE_STRING_GENERAL)
			-- A group header in the popup: shown, never chosen, not counted.
		do
			menu_rows.extend ([1, a_text.to_string_32, 0])
		end

	add_separator_row
			-- A line in the popup, not counted.
		do
			menu_rows.extend ([2, {STRING_32} "", 0])
		end

	extend_option (a_text: READABLE_STRING_GENERAL)
			-- Add an option; the first becomes the selection, without a report.
		do
			add_option (a_text)
			menu_rows.extend ([0, a_text.to_string_32, options.count])
			if options.count = 1 then
				select_quietly (1)
			end
		ensure
			one_more: options.count = old options.count + 1
			first_selected: old options.is_empty implies selected_index = 1
		end

	clear_options
		do
			options.wipe_out
			menu_rows.wipe_out
			selected_index := 0
			set_text ("")
		ensure
			empty: options.is_empty
			none_selected: selected_index = 0
		end

	select_quietly (i: INTEGER)
			-- Show option `i', without a report.
		require
			valid: 1 <= i and i <= options.count
		do
			choose_option (i)
			selected_index := i
		ensure
			selected: selected_index = i
		end

	pick (i: INTEGER)
			-- As the user choosing option `i'.
		require
			valid: 1 <= i and i <= options.count
		do
			if i /= selected_index then
				select_quietly (i)
				if attached on_pick as al_action then
					al_action.call ([i])
				end
			end
		ensure
			selected: selected_index = i
		end

feature -- Input

	handle_click (a_px, a_py: REAL_64): BOOLEAN
			-- Anywhere on the box opens the options: the text cannot be edited.
		local
			l_menu: SW_MENU
		do
			if is_enabled and then not options.is_empty then
				create l_menu.make
				across menu_rows as ic loop
					inspect ic.kind
					when 1 then
						l_menu.add_item (ic.text, "", False, Void)
					when 2 then
						l_menu.add_separator
					else
						l_menu.add_item (ic.text, "", True, agent pick (ic.choice))
					end
				end
				pending_menu := l_menu
				Result := True
			else
				Result := Precursor (a_px, a_py)
			end
		end

invariant
	read_only: is_read_only
	selection_in_range: 0 <= selected_index and selected_index <= options.count
	empty_means_none: options.is_empty = (selected_index = 0)

end
