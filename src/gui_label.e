note
	description: "Text the user reads (GtkLabel, NSTextField as a label)."

class
	GUI_LABEL

inherit
	GUI_WIDGET
		redefine
			default_accessible_label
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
			l_c := backend.to_c (a_text)
			register (backend.label (l_c.item))
		ensure
			text_set: text.same_string_general (a_text)
		end

feature -- Access

	text: STRING_32
		do
			Result := backend.from_c (backend.label_get (id))
		end

feature -- Element change

	set_text (a_text: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.label_set (id, l_c.item)
		ensure
			text_set: text.same_string_general (a_text)
		end

feature {NONE} -- Implementation

	default_accessible_label: STRING_32
		do
			Result := text
		end

end
