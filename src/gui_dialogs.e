note
	description: "[
		Native dialogs, asked synchronously: each runs a nested loop until answered,
		modal to the application's first open window. The externals are `blocking', so
		other processors keep running meanwhile.
	]"

class
	GUI_DIALOGS

inherit
	GUI_SHARED

feature -- Files

	open_file (a_title: READABLE_STRING_GENERAL; a_extensions: ARRAY [READABLE_STRING_GENERAL]): detachable PATH
			-- A file the user chose to open, or Void. `a_extensions' such as <<"txt", "md">>; empty for any.
		require
			gui_thread: is_gui_thread
		do
			Result := chosen_file (a_title, a_extensions, False)
		end

	save_file (a_title: READABLE_STRING_GENERAL; a_extensions: ARRAY [READABLE_STRING_GENERAL]): detachable PATH
			-- A file the user chose to save to, or Void.
		require
			gui_thread: is_gui_thread
		do
			Result := chosen_file (a_title, a_extensions, True)
		end

feature -- Messages

	inform (a_title, a_text: READABLE_STRING_GENERAL)
			-- Show a message with one OK button.
		require
			gui_thread: is_gui_thread
		local
			l_t, l_x: C_STRING
			l_ignored: BOOLEAN
		do
			l_t := backend.to_c (a_title)
			l_x := backend.to_c (a_text)
			l_ignored := backend.message (parent_window, l_t.item, l_x.item, False)
		end

	confirm (a_title, a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Did the user choose OK over Cancel?
		require
			gui_thread: is_gui_thread
		local
			l_t, l_x: C_STRING
		do
			l_t := backend.to_c (a_title)
			l_x := backend.to_c (a_text)
			Result := backend.message (parent_window, l_t.item, l_x.item, True)
		end

feature {NONE} -- Implementation

	chosen_file (a_title: READABLE_STRING_GENERAL; a_extensions: ARRAY [READABLE_STRING_GENERAL]; a_save: BOOLEAN): detachable PATH
		local
			l_t, l_e: C_STRING
			l_joined: STRING_32
			l_path: POINTER
		do
			create l_joined.make_empty
			across a_extensions as ic loop
				if not l_joined.is_empty then
					l_joined.append_character (';')
				end
				l_joined.append_string_general (ic)
			end
			l_t := backend.to_c (a_title)
			l_e := backend.to_c (l_joined)
			l_path := backend.open_file (parent_window, l_t.item, a_save, l_e.item)
			if l_path /= default_pointer then
				create Result.make_from_string (backend.from_c (l_path))
			end
		end

	parent_window: INTEGER
			-- The id of the application's first open window, or 0.
		do
			if has_application and then not application.windows.is_empty then
				Result := application.windows.first.id
			end
		end

end
