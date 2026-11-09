note
	description: "[
		A titled frame around one widget (NSBox, GtkFrame, a group box on Windows). Screen
		readers know it as a group named by its title.
	]"

class
	GUI_GROUP_BOX

inherit
	GUI_SINGLE_CONTAINER
		redefine
			default_accessible_label
		end

create
	make

feature {NONE} -- Initialization

	make (a_title: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
			has_application: has_application
		local
			l_c: C_STRING
		do
			create children.make (1)
			title := a_title.to_string_32
			l_c := backend.to_c (a_title)
			register (backend.group_box (l_c.item))
		ensure
			titled: title.same_string_general (a_title)
			empty: content = Void
		end

feature -- Access

	title: STRING_32

feature -- Element change

	set_title (a_title: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			title := a_title.to_string_32
			l_c := backend.to_c (a_title)
			backend.group_box_set_title (id, l_c.item)
		ensure
			titled: title.same_string_general (a_title)
		end

feature {NONE} -- Implementation

	backend_set_content (a_child: INTEGER)
		do
			backend.group_box_set_content (id, a_child)
		end

	default_accessible_label: STRING_32
		do
			Result := title
		end

end
