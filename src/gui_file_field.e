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
			create breadcrumbs.make
			create part_folders.make (4)
			create typed_before.make_empty
			make_row
			field.set_accessible_label (a_title)
			choose_button.set_accessible_label ({STRING_32} "Choose " + title)
			breadcrumbs.set_accessible_label (a_title)
			extend_stretching (breadcrumbs)
			breadcrumbs.hide
			extend_stretching (field)
			extend (choose_button)
			breadcrumbs.selection_actions.extend (agent part_clicked)
			breadcrumbs.chevron_actions.extend (agent chevron_clicked)
			breadcrumbs.space_actions.extend (agent edit_path)
			field.activate_actions.extend (agent typed_done)
			field.leave_actions.extend (agent typed_done)
			field.escape_actions.extend (agent typed_cancelled)
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

	breadcrumbs: GUI_PATH_CONTROL
			-- The path as parts, when `is_breadcrumbs' and not editing (1p-b).

	folder_choices: detachable ARRAYED_LIST [GUI_BUTTON]
			-- The chevron's folder buttons, in order, while they show.

	is_breadcrumbs: BOOLEAN
			-- Does the path show as breadcrumbs at rest (1p-b)?

	is_editing: BOOLEAN
			-- Is the path being typed?
		do
			Result := not is_breadcrumbs or else field.is_shown
		end

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
			if is_breadcrumbs then
				show_breadcrumbs
			end
		ensure
			no_event: change_actions.fire_count = old change_actions.fire_count
		end

	set_breadcrumbs (a_on: BOOLEAN)
			-- Show the path as Explorer's address bar does: breadcrumbs at rest, with chevrons
			-- listing a folder's subfolders, turning into the typed path (with suggestions) on a
			-- click in the empty space.
		require
			gui_thread: is_gui_thread
		do
			is_breadcrumbs := a_on
			breadcrumbs.set_chevrons (a_on)
			if a_on then
				field.set_suggester (agent suggest)
				field.set_validator (agent path_problem)
				show_breadcrumbs
			else
				field.set_suggester (Void)
				field.set_validator (Void)
				breadcrumbs.hide
				field.show
			end
		ensure
			set: is_breadcrumbs = a_on
		end

	edit_path
			-- Turn the breadcrumbs into the typed path, all of it selected.
		require
			gui_thread: is_gui_thread
		do
			if is_breadcrumbs then
				typed_before := field.text.twin
				breadcrumbs.hide
				field.show
				field.focus
			end
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
				if is_breadcrumbs then
					show_breadcrumbs
				end
			end
		end

feature {NONE} -- The address bar (1p-b)

	part_folders: ARRAYED_LIST [STRING_32]
			-- The folder each breadcrumb part stands for.

	typed_before: STRING_32
			-- The path when typing began, for Escape.

	folder_popover: detachable GUI_POPOVER

	show_breadcrumbs
			-- The path as parts; an empty path stays a field to type in.
		local
			l_text, l_home, l_rest, l_folder, l_sep: STRING_32
			l_parts: ARRAYED_LIST [STRING_32]
			l_icon: STRING_32
		do
			l_text := field.text
			if l_text.is_empty then
				breadcrumbs.hide
				field.show
			else
				if {PLATFORM}.is_windows then l_sep := {STRING_32} "\" else l_sep := {STRING_32} "/" end
				create l_parts.make (6)
				part_folders.wipe_out
				l_home := home_folder
				l_icon := {STRING_32} "folder"
				if not l_home.is_empty and then (l_text.same_string (l_home) or else l_text.starts_with (l_home + l_sep)) then
					l_parts.extend ({STRING_32} "Home")
					part_folders.extend (l_home)
					l_folder := l_home.twin
					l_rest := l_text.substring (l_home.count + 2, l_text.count)
					l_icon := {STRING_32} "home"
				elseif l_text.starts_with ("/") then
					l_parts.extend ({STRING_32} "/")
					part_folders.extend ({STRING_32} "/")
					l_folder := {STRING_32} ""
					l_rest := l_text.substring (2, l_text.count)
				elseif l_text.count >= 2 and then l_text [2] = ':' then
					l_parts.extend (l_text.substring (1, 2))
					part_folders.extend (l_text.substring (1, 2) + l_sep)
					l_folder := l_text.substring (1, 2)
					l_rest := l_text.substring ((4).min (l_text.count + 1), l_text.count)
				else
					l_folder := {STRING_32} ""
					l_rest := l_text.twin
				end
				across l_rest.split (l_sep [1]) as ic loop
					if not ic.is_empty then
						if l_folder.is_empty or else l_folder.same_string ("/") then
							l_folder := l_folder + ic
							if not l_folder.starts_with ("/") and then l_text.starts_with ("/") then
								l_folder := {STRING_32} "/" + l_folder
							end
						else
							l_folder := l_folder + l_sep + ic
						end
						l_parts.extend (ic)
						part_folders.extend (l_folder.twin)
					end
				end
				breadcrumbs.set_parts (as_array (l_parts))
				breadcrumbs.set_root_icon (l_icon)
				field.close_suggestions
				field.hide
				breadcrumbs.show
			end
		end

	part_clicked (a_part: INTEGER)
			-- A folder field goes to that folder; a file field's chooser opens.
		do
			if is_folder and then part_folders.valid_index (a_part) then
				field.set_text (part_folders [a_part])
				change_actions.call (Void)
				show_breadcrumbs
			else
				choose
			end
		end

	chevron_clicked (a_part: INTEGER)
			-- The folder's subfolders (and files, for an open or save field) as a column of
			-- flat buttons in a popover: only a click chooses (a list would choose its first
			-- row as the focus enters it).
		local
			l_column: GUI_STACK
			l_scroll: GUI_SCROLL_AREA
			l_popover: GUI_POPOVER
			l_button: GUI_BUTTON
			l_choices: ARRAYED_LIST [GUI_BUTTON]
		do
			if part_folders.valid_index (a_part) then
				create l_column.make_vertical
				l_column.set_spacing (0)
				l_column.set_accessible_label ({STRING_32} "Folders in " + breadcrumbs.part (a_part))
				create l_choices.make (8)
				across entries_of (part_folders [a_part], not is_folder) as ic loop
					create l_button.make (ic)
					l_button.set_style (l_button.Style_flat)
					l_button.click_actions.extend (agent folder_chosen (a_part, ic))
					l_column.extend (l_button)
					l_choices.extend (l_button)
				end
				if attached folder_popover as al_old then
					al_old.hide
				end
				create l_scroll.make
				l_scroll.set_content (l_column)
				create l_popover.make
				l_popover.set_content (l_scroll)
				l_popover.show_at (breadcrumbs)
				folder_popover := l_popover
				folder_choices := l_choices
			end
		end

	folder_chosen (a_part: INTEGER; a_name: STRING_32)
		local
			l_sep: STRING_32
		do
			if part_folders.valid_index (a_part) then
				if {PLATFORM}.is_windows then l_sep := {STRING_32} "\" else l_sep := {STRING_32} "/" end
				if part_folders [a_part].ends_with (l_sep) then
					field.set_text (part_folders [a_part] + a_name)
				else
					field.set_text (part_folders [a_part] + l_sep + a_name)
				end
				if attached folder_popover as al_p then
					al_p.hide
				end
				folder_popover := Void
				folder_choices := Void
				change_actions.call (Void)
				show_breadcrumbs
			end
		end

	typed_done
			-- Enter, or the focus leaving: a usable path goes back to breadcrumbs.
		do
			if is_breadcrumbs and then field.is_shown and then path_problem (field.text) = Void then
				show_breadcrumbs
			end
		end

	typed_cancelled
			-- Escape: the old path, as breadcrumbs.
		do
			if is_breadcrumbs and then field.is_shown then
				field.set_text (typed_before)
				show_breadcrumbs
			end
		end

	path_problem (a_text: STRING_32): detachable STRING_32
			-- Why `a_text' can't be this field's path; Void when it can.
		local
			l_path: PATH
		do
			if not a_text.is_empty then
				create l_path.make_from_string (expanded_path (a_text))
				inspect mode
				when Mode_folder then
					if not (create {DIRECTORY}.make_with_path (l_path)).exists then
						Result := {STRING_32} "No such folder"
					end
				when Mode_save then
					if attached l_path.parent as al_parent and then not (create {DIRECTORY}.make_with_path (al_parent)).exists then
						Result := {STRING_32} "No such folder"
					end
				else
					if not (create {RAW_FILE}.make_with_path (l_path)).exists then
						Result := {STRING_32} "No such file"
					end
				end
			end
		end

	suggest (a_text: STRING_32): ITERABLE [READABLE_STRING_GENERAL]
			-- The entries of the folder typed so far that start with what follows it.
		local
			l_text, l_folder, l_start, l_sep: STRING_32
			l_cut: INTEGER
			l_out: ARRAYED_LIST [STRING_32]
		do
			create l_out.make (8)
			l_text := expanded_path (a_text)
			l_cut := l_text.last_index_of ('/', l_text.count).max (l_text.last_index_of ('\', l_text.count))
			if l_cut > 0 then
				l_folder := l_text.substring (1, l_cut)
				l_start := l_text.substring (l_cut + 1, l_text.count)
				if {PLATFORM}.is_windows then l_sep := {STRING_32} "\" else l_sep := {STRING_32} "/" end
				across entries_of (l_folder, not is_folder) as ic until l_out.count >= 50 loop
					if starts_alike (ic, l_start) then
						if is_folder_entry (l_folder, ic) then
							l_out.extend (l_folder + ic + l_sep)
						else
							l_out.extend (l_folder + ic)
						end
					end
				end
			end
			Result := l_out
		end

	entries_of (a_folder: READABLE_STRING_32; a_with_files: BOOLEAN): ARRAYED_LIST [STRING_32]
			-- `a_folder''s subfolders, then (when asked) its files, each sorted, names only.
		local
			l_dir: DIRECTORY
			l_folders, l_files: ARRAYED_LIST [STRING_32]
			l_name: STRING_32
		do
			create Result.make (16)
			create l_folders.make (16)
			create l_files.make (16)
			create l_dir.make (expanded_path (a_folder))
			if l_dir.exists then
				across l_dir.entries as ic loop
					l_name := ic.name
					if not (l_name.same_string (".") or l_name.same_string ("..")) then
						if is_folder_entry (a_folder, l_name) then
							l_folders.extend (l_name)
						elseif a_with_files then
							l_files.extend (l_name)
						end
					end
				end
			end
			sort (l_folders)
			sort (l_files)
			Result.append (l_folders)
			Result.append (l_files)
		end

	is_folder_entry (a_folder, a_name: READABLE_STRING_32): BOOLEAN
		do
			Result := (create {DIRECTORY}.make_with_path ((create {PATH}.make_from_string (expanded_path (a_folder))).extended (a_name))).exists
		end

	starts_alike (a_name, a_start: READABLE_STRING_32): BOOLEAN
			-- Ignoring case on Windows and macOS.
		do
			if {PLATFORM}.is_windows or {PLATFORM}.is_mac then
				Result := a_name.as_lower.starts_with (a_start.as_lower)
			else
				Result := a_name.starts_with (a_start)
			end
		end

	expanded_path (a_text: READABLE_STRING_32): STRING_32
			-- `a_text' with a leading ~ as the home folder.
		do
			if a_text.starts_with ("~") then
				Result := home_folder + a_text.substring (2, a_text.count)
			else
				Result := a_text.to_string_32
			end
		end

	home_folder: STRING_32
		local
			l_env: EXECUTION_ENVIRONMENT
		do
			create l_env
			if {PLATFORM}.is_windows and then attached l_env.item ("USERPROFILE") as al_u then
				Result := al_u
			elseif attached l_env.item ("HOME") as al_h then
				Result := al_h
			else
				create Result.make_empty
			end
		end

	sort (a_names: ARRAYED_LIST [STRING_32])
			-- In place, ignoring case (an insertion sort: folders hold tens of entries).
		local
			i, j: INTEGER
			l_name: STRING_32
		do
			from i := 2 until i > a_names.count loop
				l_name := a_names [i]
				from j := i - 1 until j < 1 or else a_names [j].as_lower <= l_name.as_lower loop
					a_names [j + 1] := a_names [j]
					j := j - 1
				end
				a_names [j + 1] := l_name
				i := i + 1
			end
		end

	as_array (a_list: ARRAYED_LIST [STRING_32]): ARRAY [READABLE_STRING_GENERAL]
		local
			i: INTEGER
		do
			create Result.make_filled ({STRING_32} "", 1, a_list.count)
			from i := 1 until i > a_list.count loop
				Result [i] := a_list [i]
				i := i + 1
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
