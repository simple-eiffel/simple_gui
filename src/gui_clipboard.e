note
	description: "[
		The system clipboard's text (1m; EiffelStudio's EV_CLIPBOARD): `GUI_APPLICATION.clipboard'.
		Works with or without a window open.
	]"

class
	GUI_CLIPBOARD

inherit
	GUI_SHARED

create {GUI_APPLICATION}
	default_create

feature -- Access

	text: STRING_32
			-- The text on the clipboard now; empty when it holds none.
		require
			gui_thread: is_gui_thread
		do
			Result := backend.from_c (backend.clipboard_text)
		end

feature -- Element change

	set_text (a_text: READABLE_STRING_GENERAL)
			-- Put `a_text' on the clipboard, for this program and every other.
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.clipboard_set_text (l_c.item)
		end

end
