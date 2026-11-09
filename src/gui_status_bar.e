note
	description: "[
		One line of text that GUI_WINDOW.set_status_bar places at the window's bottom: the
		window's bottom bar on macOS, a strip below the content on Linux and Windows. Screen
		readers know it as a status.
	]"

class
	GUI_STATUS_BAR

inherit
	GUI_WIDGET

create
	make

feature {NONE} -- Initialization

	make
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			register (backend.status_bar)
		ensure
			empty: text.is_empty
		end

feature -- Access

	text: STRING_32
		do
			Result := backend.from_c (backend.status_bar_text (id))
		end

feature -- Element change

	set_text (a_text: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.status_bar_set_text (id, l_c.item)
		ensure
			text_set: text.same_string_general (a_text)
		end

end
