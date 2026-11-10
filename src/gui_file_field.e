note
	description: "[
		A path and a "Choose..." button (1p, HTML's file input): the button opens the file or
		folder dialog, and the chosen path shows in the field, which the user may also type
		in, or drop a file on (1q-b: one the dialog would offer). `set_path' never fires
		`change_actions'; a choice, a drop or an edit does. Shared Eiffel:
		a GUI_TEXT_FIELD and a GUI_BUTTON over GUI_DIALOGS, the same on every platform.
	]"

class
	GUI_FILE_FIELD

inherit
	GUI_STACK
		rename
			make_horizontal as make_row,
			make_vertical as make_column
		export
			{NONE} make_row, make_column
		end

create
	make_open, make_save, make_folder

feature {NONE} -- Initialization

	make_open (a_title: READABLE_STRING_GENERAL; a_extensions: ARRAY [READABLE_STRING_GENERAL])
			-- A field for a file to open, of `a_extensions' (empty: any).
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			make_field (a_title, a_extensions, Mode_open)
		end

	make_save (a_title: READABLE_STRING_GENERAL; a_extensions: ARRAY [READABLE_STRING_GENERAL])
			-- A field for a file to save to.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			make_field (a_title, a_extensions, Mode_save)
		end

	make_folder (a_title: READABLE_STRING_GENERAL)
			-- A field for a folder.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			make_field (a_title, <<>>, Mode_folder)
		end

	make_field (a_title: READABLE_STRING_GENERAL; a_extensions: ARRAY [READABLE_STRING_GENERAL]; a_mode: INTEGER)
		do
			title := a_title.to_string_32
			extensions := a_extensions
			mode := a_mode
			create change_actions.make
			create field.make
			create choose_button.make ("Choose...")
			make_row
			field.set_accessible_label (a_title)
			choose_button.set_accessible_label ({STRING_32} "Choose " + title)
			extend_stretching (field)
			extend (choose_button)
			field.change_actions.extend (agent change_actions.call (Void))
			choose_button.click_actions.extend (agent choose)
			field.file_drop_actions.extend (agent take_dropped)
			choose_button.file_drop_actions.extend (agent take_dropped)
		end

feature -- Access

	title: STRING_32
			-- The dialog's title, and the field's accessible label.

	path: detachable PATH
			-- The path in the field; Void when it is empty.
		do
			if not field.text.is_empty then
				create Result.make_from_string (field.text)
			end
		end

	field: GUI_TEXT_FIELD
			-- Where the path shows.

	choose_button: GUI_BUTTON
			-- "Choose...".

	change_actions: GUI_ACTIONS [TUPLE]
			-- Run when the user chooses a path or edits the field.

	is_save: BOOLEAN do Result := mode = Mode_save end

	is_folder: BOOLEAN do Result := mode = Mode_folder end

feature -- Element change

	set_path (a_path: detachable PATH)
			-- Show `a_path' (Void: empty), without a change event.
		require
			gui_thread: is_gui_thread
		do
			if attached a_path as al_path then
				field.set_text (al_path.name)
			else
				field.set_text ("")
			end
		ensure
			no_event: change_actions.fire_count = old change_actions.fire_count
		end

feature -- Basic operations

	choose
			-- Open the dialog, as the button does; a chosen path fills the field and fires
			-- `change_actions'.
		require
			gui_thread: is_gui_thread
		local
			l_path: detachable PATH
		do
			inspect mode
			when Mode_save then
				l_path := application.dialogs.save_file_named (title, extensions, suggested_name)
			when Mode_folder then
				l_path := application.dialogs.choose_folder (title)
			else
				l_path := application.dialogs.open_file (title, extensions)
			end
			if attached l_path as al_path then
				field.set_text (al_path.name)
				change_actions.call (Void)
			end
		end

feature {NONE} -- Implementation

	take_dropped (a_paths: ARRAYED_LIST [PATH])
			-- Files dropped on the field or the button: the first the dialog would offer fills
			-- the field and fires `change_actions'.
		local
			l_done: BOOLEAN
		do
			across a_paths as ic until l_done loop
				if is_offered (ic) then
					field.set_text (ic.name)
					change_actions.call (Void)
					l_done := True
				end
			end
		end

	is_offered (a_path: PATH): BOOLEAN
			-- Would the dialog offer `a_path'? A folder field takes folders; a file field takes
			-- what is not a folder, of one of `extensions' when there are any.
		local
			l_dir: DIRECTORY
			l_name: STRING_32
		do
			create l_dir.make_with_path (a_path)
			if mode = Mode_folder then
				Result := l_dir.exists
			elseif not l_dir.exists then
				if extensions.is_empty or mode = Mode_save then
					Result := True
				else
					l_name := a_path.name.as_lower
					Result := across extensions as ic some l_name.ends_with ({STRING_32} "." + ic.as_lower.to_string_32) end
				end
			end
		end

	suggested_name: STRING_32
			-- The file name now in the field, offered first when saving.
		do
			if attached path as al_path and then attached al_path.entry as al_entry then
				Result := al_entry.name
			else
				create Result.make_empty
			end
		end

	mode: INTEGER

	extensions: ARRAY [READABLE_STRING_GENERAL]

	Mode_open: INTEGER = 1
	Mode_save: INTEGER = 2
	Mode_folder: INTEGER = 3

end
