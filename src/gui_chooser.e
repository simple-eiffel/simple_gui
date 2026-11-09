note
	description: "[
		Pick one of several texts: GUI_DROPDOWN, GUI_RADIO_GROUP and GUI_SEGMENTED. Choices
		are 1-based. The first `extend' selects choice 1, and `select_row' never fires
		`selection_actions'; only the user's choices do (choosing the selected one again is
		not a choice).
	]"

deferred class
	GUI_CHOOSER

inherit
	GUI_WIDGET
		redefine
			dispatch
		end

feature -- Access

	count: INTEGER
		do
			Result := rows.count
		end

	i_th (i: INTEGER): STRING_32
		require
			valid: 1 <= i and i <= count
		do
			Result := rows.i_th (i)
		end

	selected_index: INTEGER
			-- The selected choice, or 0 when there are none.
		deferred
		ensure
			in_range: 0 <= Result and Result <= count
		end

	selected_text: STRING_32
			-- The selected choice's text, or empty when nothing is selected.
		do
			if selected_index > 0 then
				Result := i_th (selected_index)
			else
				create Result.make_empty
			end
		end

	selection_actions: GUI_ACTIONS [TUPLE [row: INTEGER]]
			-- Run when the user chooses another row.

feature -- Element change

	extend (a_text: READABLE_STRING_GENERAL)
			-- Add a choice; the first one added becomes the selection, without an event.
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			rows.extend (a_text.to_string_32)
			l_c := backend.to_c (a_text)
			backend_extend (l_c.item)
		ensure
			one_more: count = old count + 1
			last: i_th (count).same_string_general (a_text)
			first_selected: old count = 0 implies selected_index = 1
			no_event: selection_actions.fire_count = old selection_actions.fire_count
		end

	select_row (i: INTEGER)
			-- Select choice `i', without a selection event.
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count
		do
			backend_select (i)
		ensure
			selected: selected_index = i
			no_event: selection_actions.fire_count = old selection_actions.fire_count
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 4 then
				selection_actions.call ([a_a])
			end
		end

feature {NONE} -- Implementation

	rows: ARRAYED_LIST [STRING_32]

	make_chooser
			-- Make the lists; then the heir registers its backend widget.
		do
			create selection_actions.make
			create rows.make (8)
		end

	backend_extend (a_text: POINTER)
			-- Add a choice in the toolkit.
		deferred
		end

	backend_select (i: INTEGER)
			-- Select choice `i' in the toolkit, silently.
		deferred
		end

invariant
	rows_exist: rows /= Void

end
