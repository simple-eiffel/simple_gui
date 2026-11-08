note
	description: "[
		A check box with a caption (GtkCheckButton, NSButton checkbox). `set_checked' never
		fires `toggle_actions'; only the user's clicks do.
	]"

class
	GUI_CHECK_BOX

inherit
	GUI_WIDGET
		redefine
			default_accessible_label, dispatch
		end

create
	make

feature {NONE} -- Initialization

	make (a_text: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
			has_application: has_application
		local
			l_c: C_STRING
		do
			create toggle_actions.make
			l_c := backend.to_c (a_text)
			register (backend.check_box (l_c.item))
		ensure
			text_set: text.same_string_general (a_text)
			clear: not is_checked
		end

feature -- Access

	text: STRING_32
		do
			Result := backend.from_c (backend.check_box_text (id))
		end

	is_checked: BOOLEAN
		do
			Result := backend.check_box_is_checked (id)
		end

	toggle_actions: GUI_ACTIONS [TUPLE [checked: BOOLEAN]]
			-- Run when the user checks or clears the box.

feature -- Element change

	set_checked (a_on: BOOLEAN)
			-- Check or clear, without a toggled event.
		require
			gui_thread: is_gui_thread
		do
			backend.check_box_set (id, a_on)
		ensure
			set: is_checked = a_on
			no_event: toggle_actions.fire_count = old toggle_actions.fire_count
		end

	set_text (a_text: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.check_box_set_text (id, l_c.item)
		ensure
			text_set: text.same_string_general (a_text)
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 12 then
				toggle_actions.call ([a_a = 1])
			end
		end

feature {NONE} -- Implementation

	default_accessible_label: STRING_32
		do
			Result := text
		end

end
