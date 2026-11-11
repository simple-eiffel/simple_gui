note
	description: "[
		Multi-line text (GtkTextView, NSTextView), scrolling and wrapping at word or
		character boundaries. `set_text' never fires `change_actions'. Read-only areas
		show results that can still be selected and copied.
	]"

class
	GUI_TEXT_AREA

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
			register (backend.text_area)
		ensure
			empty: text.is_empty
			editable: not is_read_only
		end

feature -- Access

	text: STRING_32
		do
			Result := backend.text_area_string (id)
		end

	is_read_only: BOOLEAN

	change_actions: GUI_ACTIONS [TUPLE]
			-- Run after each user edit.

	change_count: INTEGER
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
			backend.text_area_set (id, l_c.item)
		ensure
			text_set: text.same_string_general (a_text)
			no_event: change_count = old change_count
		end

	set_read_only (a_on: BOOLEAN)
		require
			gui_thread: is_gui_thread
		do
			is_read_only := a_on
			backend.text_area_set_read_only (id, a_on)
		ensure
			set: is_read_only = a_on
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 2 then
				change_actions.call (Void)
			end
		end

end
