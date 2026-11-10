note
	description: "[
		A path as clickable parts, a breadcrumb (NSPathControl; linked buttons on GTK; drawn on
		Windows). A click on a part fires `selection_actions' with its number (1 = the root);
		the program decides where to go.
	]"

class
	GUI_PATH_CONTROL

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
			create selection_actions.make
			register (backend.path_control)
		ensure
			no_path: path = Void
		end

feature -- Access

	path: detachable PATH

	part_count: INTEGER
			-- How many parts are shown (the platform may name the root, as "Macintosh HD").
		do
			Result := backend.path_control_count (id)
		end

	part (i: INTEGER): STRING_32
			-- Part `i''s text, from the root.
		require
			valid: 1 <= i and i <= part_count
		do
			Result := backend.from_c (backend.path_control_part (id, i))
		end

	selection_actions: GUI_ACTIONS [TUPLE [part: INTEGER]]
			-- Run when the user clicks a part.

feature -- Element change

	set_path (a_path: PATH)
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			path := a_path
			l_c := backend.to_c (a_path.name)
			backend.path_control_set (id, l_c.item)
		ensure
			set: path = a_path
		end

	set_parts (a_parts: ARRAY [READABLE_STRING_GENERAL])
			-- Show any parts, from the first (1t breadcrumbs); `path' becomes Void.
		require
			gui_thread: is_gui_thread
			has_parts: not a_parts.is_empty
			no_separator: across a_parts as ic all not ic.has ('%/31/') end
		local
			l_joined: STRING_32
			l_c: C_STRING
			l_first: BOOLEAN
		do
			path := Void
			create l_joined.make (32)
			l_first := True
			across a_parts as ic loop
				if not l_first then
					l_joined.append_character ('%/31/')
				end
				l_joined.append_string_general (ic)
				l_first := False
			end
			l_c := backend.to_c (l_joined)
			backend.path_control_set_parts (id, l_c.item)
		ensure
			no_path: path = Void
			counted: part_count = a_parts.count
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 4 then
				selection_actions.call ([a_a])
			end
		end

end
