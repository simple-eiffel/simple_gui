note
	description: "[
		A one-line text entry (GtkEntry, NSTextField). `set_text' never fires
		`change_actions'; only the user's edits do. Give it an accessible label: the
		placeholder is not one.
	]"

class
	GUI_TEXT_FIELD

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
			create activate_actions.make
			create placeholder.make_empty
			register (backend.field)
		ensure
			empty: text.is_empty
		end

feature -- Access

	text: STRING_32
		do
			Result := backend.from_c (backend.field_get (id))
		end

	placeholder: STRING_32
			-- Hint shown while empty.

	change_actions: GUI_ACTIONS [TUPLE]
			-- Run after each user edit.

	activate_actions: GUI_ACTIONS [TUPLE]
			-- Run when the user presses Enter.

	change_count: INTEGER
			-- Change events received.
		do
			Result := change_actions.fire_count
		end

feature -- Element change

	set_text (a_text: READABLE_STRING_GENERAL)
			-- Replace the text, without a change event.
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.field_set (id, l_c.item)
		ensure
			text_set: text.same_string_general (a_text)
			no_event: change_count = old change_count
		end

	set_numeric
			-- This field holds numbers or expressions: always left to right.
		require
			gui_thread: is_gui_thread
		do
			set_base_direction (Direction_left_to_right)
		ensure
			left_to_right: base_direction = Direction_left_to_right and has_own_direction
		end

	set_placeholder (a_text: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			placeholder := a_text.to_string_32
			l_c := backend.to_c (a_text)
			backend.field_set_placeholder (id, l_c.item)
		ensure
			set: placeholder.same_string_general (a_text)
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 2 then
				change_actions.call (Void)
			elseif a_type = 3 then
				activate_actions.call (Void)
			end
		end

end
