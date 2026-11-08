note
	description: "A push button (GtkButton, NSButton)."

class
	GUI_BUTTON

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
			create click_actions.make
			l_c := backend.to_c (a_text)
			register (backend.button (l_c.item))
		ensure
			text_set: text.same_string_general (a_text)
		end

feature -- Access

	text: STRING_32
		do
			Result := backend.from_c (backend.button_get (id))
		end

	click_actions: GUI_ACTIONS [TUPLE]
			-- Run when the user presses the button.

feature -- Element change

	set_text (a_text: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.button_set (id, l_c.item)
		ensure
			text_set: text.same_string_general (a_text)
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 1 then
				click_actions.call (Void)
			end
		end

feature {NONE} -- Implementation

	default_accessible_label: STRING_32
		do
			Result := text
		end

end
