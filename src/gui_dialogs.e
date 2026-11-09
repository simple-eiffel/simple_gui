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

	save_file_named (a_title: READABLE_STRING_GENERAL; a_extensions: ARRAY [READABLE_STRING_GENERAL]; a_suggested_name: READABLE_STRING_GENERAL): detachable PATH
			-- A file the user chose to save to, offered `a_suggested_name' first, or Void.
		require
			gui_thread: is_gui_thread
		local
			l_t, l_e, l_n: C_STRING
			l_path: POINTER
		do
			l_t := backend.to_c (a_title)
			l_e := backend.to_c (joined_extensions (a_extensions))
			l_n := backend.to_c (a_suggested_name)
			l_path := backend.save_file_named (parent_window, l_t.item, l_e.item, l_n.item)
			if l_path /= default_pointer then
				create Result.make_from_string (backend.from_c (l_path))
			end
		end

	choose_folder (a_title: READABLE_STRING_GENERAL): detachable PATH
			-- A folder the user chose, or Void.
		require
			gui_thread: is_gui_thread
		local
			l_t: C_STRING
			l_path: POINTER
		do
			l_t := backend.to_c (a_title)
			l_path := backend.choose_folder (parent_window, l_t.item)
			if l_path /= default_pointer then
				create Result.make_from_string (backend.from_c (l_path))
			end
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

	ask (a_title, a_text: READABLE_STRING_GENERAL): INTEGER
			-- A three-way question: `Answer_yes', `Answer_no' or `Answer_cancel'. On macOS
			-- Return is Yes, Escape is Cancel and Command-D is No.
		require
			gui_thread: is_gui_thread
		local
			l_t, l_x: C_STRING
		do
			l_t := backend.to_c (a_title)
			l_x := backend.to_c (a_text)
			Result := backend.ask (parent_window, l_t.item, l_x.item)
		ensure
			known: Result = Answer_yes or Result = Answer_no or Result = Answer_cancel
		end

	ask_text (a_title, a_prompt, an_initial: READABLE_STRING_GENERAL): detachable STRING_32
			-- One line of text the user entered, starting from `an_initial', or Void when cancelled.
		require
			gui_thread: is_gui_thread
		local
			l_t, l_p, l_i: C_STRING
			l_text: POINTER
		do
			l_t := backend.to_c (a_title)
			l_p := backend.to_c (a_prompt)
			l_i := backend.to_c (an_initial)
			l_text := backend.ask_text (parent_window, l_t.item, l_p.item, l_i.item)
			if l_text /= default_pointer then
				Result := backend.from_c (l_text)
			end
		end

	confirm_with_check (a_title, a_text, a_check_text: READABLE_STRING_GENERAL): TUPLE [ok, checked: BOOLEAN]
			-- OK or Cancel, with a check box such as "Don't ask again" (the program keeps the choice).
		require
			gui_thread: is_gui_thread
		local
			l_t, l_x, l_c: C_STRING
			l_answer: INTEGER
		do
			l_t := backend.to_c (a_title)
			l_x := backend.to_c (a_text)
			l_c := backend.to_c (a_check_text)
			l_answer := backend.confirm_with_check (parent_window, l_t.item, l_x.item, l_c.item)
			Result := [l_answer \\ 2 = 1, l_answer // 2 \\ 2 = 1]
		end

	choose_font (a_title: READABLE_STRING_GENERAL; an_initial: detachable GUI_FONT_CHOICE): detachable GUI_FONT_CHOICE
			-- A font the user chose, starting from `an_initial', or Void when cancelled.
		require
			gui_thread: is_gui_thread
		local
			l_t, l_f: C_STRING
			l_answer: POINTER
			l_parts: LIST [STRING_32]
		do
			l_t := backend.to_c (a_title)
			if attached an_initial as al_font then
				l_f := backend.to_c (al_font.family)
				l_answer := backend.choose_font (parent_window, l_t.item, l_f.item, al_font.size, al_font.is_bold, al_font.is_italic)
			else
				l_f := backend.to_c ("")
				l_answer := backend.choose_font (parent_window, l_t.item, l_f.item, 0.0, False, False)
			end
			if l_answer /= default_pointer then
				l_parts := backend.from_c (l_answer).split ((0x1F).to_character_32)
				if l_parts.count = 4 and then l_parts [2].is_real_64 and then l_parts [2].to_real_64 > 0 then
					create Result.make (l_parts [1], l_parts [2].to_real_64, l_parts [3].same_string ("1"), l_parts [4].same_string ("1"))
				end
			end
		end

	show_about (a_name, a_version, a_copyright, a_comments: READABLE_STRING_GENERAL)
			-- The platform's About window for this program. The one exception to this class's
			-- rule: on macOS the standard About panel is not modal, and this returns at once.
		require
			gui_thread: is_gui_thread
		local
			l_n, l_v, l_c, l_x: C_STRING
		do
			l_n := backend.to_c (a_name)
			l_v := backend.to_c (a_version)
			l_c := backend.to_c (a_copyright)
			l_x := backend.to_c (a_comments)
			backend.show_about (l_n.item, l_v.item, l_c.item, l_x.item)
		end

	Answer_cancel: INTEGER = 0

	Answer_yes: INTEGER = 1

	Answer_no: INTEGER = 2

feature {NONE} -- Implementation

	joined_extensions (a_extensions: ARRAY [READABLE_STRING_GENERAL]): STRING_32
			-- `a_extensions' joined by ';'.
		do
			create Result.make_empty
			across a_extensions as ic loop
				if not Result.is_empty then
					Result.append_character (';')
				end
				Result.append_string_general (ic)
			end
		end

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
