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
	make, make_number

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

	make_number (a_text: READABLE_STRING_GENERAL)
			-- A label for a number or expression: always left to right, even in a right-to-left
			-- container (the bidi algorithm otherwise moves a minus sign to the other end).
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			make (a_text)
			set_base_direction (Direction_left_to_right)
		ensure
			text_set: text.same_string_general (a_text)
			left_to_right: base_direction = Direction_left_to_right and has_own_direction
		end

feature -- Access

	wrap_width: INTEGER
			-- Wrap at about this many characters; 0 = one line, ending in an ellipsis when cut.

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

	set_wrap_width (a_characters: INTEGER)
			-- Wrap at about `a_characters' characters wide (0: one line).
		require
			gui_thread: is_gui_thread
			non_negative: a_characters >= 0
		do
			wrap_width := a_characters
			backend.label_set_wrap_width (id, a_characters)
		ensure
			set: wrap_width = a_characters
		end

feature {NONE} -- Implementation

	default_accessible_label: STRING_32
		do
			Result := text
		end

end
