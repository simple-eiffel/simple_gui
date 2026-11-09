note
	description: "[
		Text the user types or picks from a list of options (GtkEntry with a completion
		popover, NSComboBox, an editable combo on Windows). The user commits the text with
		Return, by leaving the box, or by picking an option; a commit that changes the text
		fires `change_actions'. `set_text' never does.
	]"

class
	GUI_COMBO_BOX

inherit
	GUI_WIDGET
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create change_actions.make
			create options.make (8)
			register (backend.combo_box)
		ensure
			empty: text.is_empty and count = 0
		end

feature -- Access

	text: STRING_32
		do
			Result := backend.from_c (backend.combo_box_text (id))
		end

	count: INTEGER
			-- How many options the list has.
		do
			Result := options.count
		end

	i_th (i: INTEGER): STRING_32
		require
			valid: 1 <= i and i <= count
		do
			Result := options.i_th (i)
		end

	change_actions: GUI_ACTIONS [TUPLE]
			-- Run when the user commits another text.

feature -- Element change

	set_text (a_text: READABLE_STRING_GENERAL)
			-- Show `a_text', without a change event.
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.combo_box_set_text (id, l_c.item)
		ensure
			set: text.same_string_general (a_text)
			no_event: change_actions.fire_count = old change_actions.fire_count
		end

	extend (an_option: READABLE_STRING_GENERAL)
			-- Add an option to the list.
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			options.extend (an_option.to_string_32)
			l_c := backend.to_c (an_option)
			backend.combo_box_extend (id, l_c.item)
		ensure
			one_more: count = old count + 1
			last: i_th (count).same_string_general (an_option)
		end

	wipe_out
			-- Remove every option (the text stays).
		require
			gui_thread: is_gui_thread
		do
			options.wipe_out
			backend.combo_box_wipe_out (id)
		ensure
			empty: count = 0
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 2 then
				change_actions.call (Void)
			end
		end

feature {NONE} -- Implementation

	options: ARRAYED_LIST [STRING_32]

end
