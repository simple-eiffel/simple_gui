note
	description: "[
		Preferences (1v-d): typed, saved settings and a ready preferences window built from
		them (EiffelStudio's preferences library, cross-platform). Entries are added in
		sections with a key, a label and a default; values are read and set by key, kept in a
		JSON file in the platform's settings folder, saved on every change and loaded at
		creation. Unknown keys in the file are kept; a value of the wrong type, or out of
		range, falls back to the default.

		`show_window' builds the window: a GUI_SIDEBAR of the sections, each a form of the
		matching controls, with "Restore defaults" per section. Changes apply at once, with no
		OK button, as the macOS and GNOME guidelines ask.
	]"

class
	GUI_PREFERENCES

inherit
	GUI_SHARED

create
	make, make_in_file

feature {NONE} -- Initialization

	make (an_application_name: READABLE_STRING_GENERAL)
			-- Preferences kept in the platform's settings folder, under `an_application_name'.
		require
			named: not an_application_name.is_empty
			no_separator: not an_application_name.has ('/') and not an_application_name.has ('\')
		do
			make_in_file (settings_folder (an_application_name).extended ("preferences.json"))
		end

	make_in_file (a_path: PATH)
			-- Preferences kept in `a_path' (tests; a portable install).
		do
			file := a_path
			create entries.make (8)
			create values.make (8)
			create changed_actions.make
			create section.make_from_string ("General")
			create refreshers.make (8)
			load
		ensure
			no_entries: count = 0
		end

feature -- Access

	file: PATH
			-- Where the values are kept.

	count: INTEGER
		do
			Result := entries.count
		end

	has (a_key: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := entry (a_key) /= Void
		end

	section: STRING_32
			-- The section entries are added to now.

	sections: ARRAYED_LIST [STRING_32]
			-- Every section, in the order first used.
		do
			create Result.make (4)
			Result.compare_objects
			across entries as ic loop
				if not Result.has (ic.section) then
					Result.extend (ic.section)
				end
			end
		end

	label_of (a_key: READABLE_STRING_GENERAL): STRING_32
		require
			known: has (a_key)
		do
			check attached entry (a_key) as al_e then Result := al_e.label end
		end

	kind_of (a_key: READABLE_STRING_GENERAL): INTEGER
		require
			known: has (a_key)
		do
			check attached entry (a_key) as al_e then Result := al_e.kind end
		end

	changed_actions: GUI_ACTIONS [TUPLE [key: STRING_32]]
			-- Run after a value changed, from code or the window.

feature -- Kinds

	Kind_boolean: INTEGER = 1
	Kind_integer: INTEGER = 2
	Kind_text: INTEGER = 3
	Kind_choice: INTEGER = 4
	Kind_color: INTEGER = 5
	Kind_font: INTEGER = 6
	Kind_path: INTEGER = 7

feature -- Adding entries

	set_section (a_name: READABLE_STRING_GENERAL)
			-- Entries added from now on go in section `a_name'.
		require
			named: not a_name.is_empty
		do
			create section.make_from_string_general (a_name)
		ensure
			set: section.same_string_general (a_name)
		end

	add_boolean (a_key, a_label: READABLE_STRING_GENERAL; a_default: BOOLEAN)
		require
			new: is_new_key (a_key)
			labeled: not a_label.is_empty
		do
			add (a_key, a_label, Kind_boolean, a_default.out, 0, 0, Void)
		ensure
			added: has (a_key)
		end

	add_integer (a_key, a_label: READABLE_STRING_GENERAL; a_default, a_min, a_max: INTEGER)
		require
			new: is_new_key (a_key)
			labeled: not a_label.is_empty
			range: a_min <= a_default and a_default <= a_max
		do
			add (a_key, a_label, Kind_integer, a_default.out, a_min, a_max, Void)
		ensure
			added: has (a_key)
		end

	add_text (a_key, a_label, a_default: READABLE_STRING_GENERAL)
		require
			new: is_new_key (a_key)
			labeled: not a_label.is_empty
		do
			add (a_key, a_label, Kind_text, a_default, 0, 0, Void)
		ensure
			added: has (a_key)
		end

	add_choice (a_key, a_label: READABLE_STRING_GENERAL; a_choices: ARRAY [READABLE_STRING_GENERAL]; a_default: READABLE_STRING_GENERAL)
		require
			new: is_new_key (a_key)
			labeled: not a_label.is_empty
			has_choices: not a_choices.is_empty
			default_is_a_choice: across a_choices as ic some ic.same_string (a_default) end
		local
			l_choices: ARRAYED_LIST [STRING_32]
		do
			create l_choices.make (a_choices.count)
			l_choices.compare_objects
			across a_choices as ic loop
				l_choices.extend (ic.to_string_32)
			end
			add (a_key, a_label, Kind_choice, a_default, 0, 0, l_choices)
		ensure
			added: has (a_key)
		end

	add_color (a_key, a_label: READABLE_STRING_GENERAL; a_default: NATURAL_32)
			-- A color as 0xRRGGBB.
		require
			new: is_new_key (a_key)
			labeled: not a_label.is_empty
		do
			add (a_key, a_label, Kind_color, color_text (a_default), 0, 0, Void)
		ensure
			added: has (a_key)
		end

	add_font (a_key, a_label: READABLE_STRING_GENERAL; a_default: GUI_FONT_CHOICE)
		require
			new: is_new_key (a_key)
			labeled: not a_label.is_empty
		do
			add (a_key, a_label, Kind_font, font_text (a_default), 0, 0, Void)
		ensure
			added: has (a_key)
		end

	add_path (a_key, a_label: READABLE_STRING_GENERAL; a_default: detachable PATH)
		require
			new: is_new_key (a_key)
			labeled: not a_label.is_empty
		do
			if attached a_default as al_path then
				add (a_key, a_label, Kind_path, al_path.name, 0, 0, Void)
			else
				add (a_key, a_label, Kind_path, "", 0, 0, Void)
			end
		ensure
			added: has (a_key)
		end

	is_new_key (a_key: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := not a_key.is_empty and then not has (a_key)
		end

feature -- Values

	boolean_item (a_key: READABLE_STRING_GENERAL): BOOLEAN
		require
			boolean: has (a_key) and then kind_of (a_key) = Kind_boolean
		do
			Result := raw (a_key).same_string ("True")
		end

	integer_item (a_key: READABLE_STRING_GENERAL): INTEGER
		require
			integer: has (a_key) and then kind_of (a_key) = Kind_integer
		do
			Result := raw (a_key).to_integer
		end

	text_item (a_key: READABLE_STRING_GENERAL): STRING_32
			-- A text, a choice, or a path's name.
		require
			textual: has (a_key) and then (kind_of (a_key) = Kind_text or kind_of (a_key) = Kind_choice or kind_of (a_key) = Kind_path)
		do
			Result := raw (a_key).twin
		end

	color_item (a_key: READABLE_STRING_GENERAL): NATURAL_32
		require
			color: has (a_key) and then kind_of (a_key) = Kind_color
		do
			Result := color_of (raw (a_key))
		end

	font_item (a_key: READABLE_STRING_GENERAL): GUI_FONT_CHOICE
		require
			font: has (a_key) and then kind_of (a_key) = Kind_font
		do
			Result := font_of (raw (a_key))
		end

	path_item (a_key: READABLE_STRING_GENERAL): detachable PATH
		require
			path: has (a_key) and then kind_of (a_key) = Kind_path
		do
			if not raw (a_key).is_empty then
				create Result.make_from_string (raw (a_key))
			end
		end

	set_boolean (a_key: READABLE_STRING_GENERAL; a_value: BOOLEAN)
		require
			boolean: has (a_key) and then kind_of (a_key) = Kind_boolean
		do
			put (a_key, a_value.out)
		ensure
			set: boolean_item (a_key) = a_value
		end

	set_integer (a_key: READABLE_STRING_GENERAL; a_value: INTEGER)
			-- Clamped into the entry's range.
		require
			integer: has (a_key) and then kind_of (a_key) = Kind_integer
		do
			check attached entry (a_key) as al_e then
				put (a_key, a_value.max (al_e.minimum).min (al_e.maximum).out)
			end
		end

	set_text (a_key, a_value: READABLE_STRING_GENERAL)
			-- A text, or a path's name; for a choice, one of its choices.
		require
			textual: has (a_key) and then (kind_of (a_key) = Kind_text or kind_of (a_key) = Kind_choice or kind_of (a_key) = Kind_path)
			a_choice: kind_of (a_key) = Kind_choice implies is_choice (a_key, a_value)
		do
			put (a_key, a_value)
		ensure
			set: text_item (a_key).same_string_general (a_value)
		end

	set_color (a_key: READABLE_STRING_GENERAL; a_value: NATURAL_32)
		require
			color: has (a_key) and then kind_of (a_key) = Kind_color
		do
			put (a_key, color_text (a_value))
		ensure
			set: color_item (a_key) = a_value & 0xFFFFFF
		end

	set_font (a_key: READABLE_STRING_GENERAL; a_value: GUI_FONT_CHOICE)
		require
			font: has (a_key) and then kind_of (a_key) = Kind_font
		do
			put (a_key, font_text (a_value))
		end

	set_path (a_key: READABLE_STRING_GENERAL; a_value: detachable PATH)
		require
			path: has (a_key) and then kind_of (a_key) = Kind_path
		do
			if attached a_value as al_path then
				put (a_key, al_path.name)
			else
				put (a_key, "")
			end
		end

	is_choice (a_key, a_value: READABLE_STRING_GENERAL): BOOLEAN
		do
			Result := attached entry (a_key) as al_e and then attached al_e.choices as al_c
				and then across al_c as ic some ic.same_string_general (a_value) end
		end

	choices_of (a_key: READABLE_STRING_GENERAL): ARRAYED_LIST [STRING_32]
		require
			choice: has (a_key) and then kind_of (a_key) = Kind_choice
		do
			check attached entry (a_key) as al_e and then attached al_e.choices as al_c then
				Result := al_c
			end
		end

	reset (a_key: READABLE_STRING_GENERAL)
			-- Back to its default.
		require
			known: has (a_key)
		do
			check attached entry (a_key) as al_e then
				put (a_key, al_e.default_value)
			end
		end

	reset_section (a_section: READABLE_STRING_GENERAL)
		do
			across entries as ic loop
				if ic.section.same_string_general (a_section) then
					reset (ic.key)
				end
			end
		end

	reset_all
		do
			across entries as ic loop
				reset (ic.key)
			end
		end

feature -- The window

	show_window (a_parent: detachable GUI_WINDOW)
			-- A preferences window: the sections in a sidebar, each a form of its entries with
			-- "Restore defaults"; changes apply at once.
		require
			gui_thread: is_gui_thread
			has_application: has_application
			has_entries: count > 0
		local
			l_window: GUI_WINDOW
			l_side: GUI_SIDEBAR
		do
			refreshers.wipe_out
			create l_window.make ("Preferences", 640, 420)
			create l_side.make
			across sections as ic loop
				l_side.extend (section_form (ic), ic)
			end
			l_window.set_content (l_side)
			l_window.show
			window := l_window
		end

	window: detachable GUI_WINDOW
			-- The last preferences window shown.

	control_for (a_key: READABLE_STRING_GENERAL): detachable GUI_WIDGET
			-- The window's control for `a_key' (tests).
		do
			Result := controls.item (a_key.to_string_32)
		end

feature {NONE} -- Entries

	entries: ARRAYED_LIST [TUPLE [key, label, section: STRING_32; kind: INTEGER; default_value: STRING_32; minimum, maximum: INTEGER; choices: detachable ARRAYED_LIST [STRING_32]]]

	values: HASH_TABLE [STRING_32, STRING_32]
			-- Each key's value, as text.

	loaded: detachable SIMPLE_JSON_OBJECT
			-- The file as read, so unknown keys are written back.

	refreshers: ARRAYED_LIST [PROCEDURE]
			-- Bring the window's controls up to date after a reset.

	controls: HASH_TABLE [GUI_WIDGET, STRING_32]
		attribute
			create Result.make (8)
		end

	entry (a_key: READABLE_STRING_GENERAL): detachable like entries.item
		do
			across entries as ic until Result /= Void loop
				if ic.key.same_string_general (a_key) then
					Result := ic
				end
			end
		end

	add (a_key, a_label: READABLE_STRING_GENERAL; a_kind: INTEGER; a_default: READABLE_STRING_GENERAL; a_min, a_max: INTEGER; a_choices: detachable ARRAYED_LIST [STRING_32])
			-- The entry, with the file's value when it is valid, else the default.
		local
			l_key: STRING_32
		do
			l_key := a_key.to_string_32
			entries.extend ([l_key, a_label.to_string_32, section.twin, a_kind, a_default.to_string_32, a_min, a_max, a_choices])
			values.force (a_default.to_string_32, l_key)
			if attached loaded as al_file and then al_file.has_key (l_key) and then attached al_file.item (l_key) as al_v then
				take_loaded (l_key, a_kind, al_v, a_min, a_max, a_choices)
			end
		end

	take_loaded (a_key: STRING_32; a_kind: INTEGER; a_value: SIMPLE_JSON_VALUE; a_min, a_max: INTEGER; a_choices: detachable ARRAYED_LIST [STRING_32])
			-- `a_value' from the file, when it fits the entry.
		do
			inspect a_kind
			when Kind_boolean then
				if a_value.is_boolean then values.force (a_value.as_boolean.out, a_key) end
			when Kind_integer then
				if a_value.is_integer and then a_value.as_integer >= a_min and then a_value.as_integer <= a_max then
					values.force (a_value.as_integer.out, a_key)
				end
			when Kind_choice then
				if a_value.is_string and then attached a_choices as al_c and then al_c.has (a_value.as_string_32) then
					values.force (a_value.as_string_32, a_key)
				end
			when Kind_color then
				if a_value.is_string and then is_color_text (a_value.as_string_32) then values.force (a_value.as_string_32, a_key) end
			else
				if a_value.is_string then values.force (a_value.as_string_32, a_key) end
			end
		end

	raw (a_key: READABLE_STRING_GENERAL): STRING_32
		do
			if attached values.item (a_key.to_string_32) as al_v then
				Result := al_v
			else
				create Result.make_empty
			end
		end

	put (a_key, a_value: READABLE_STRING_GENERAL)
			-- Set, save and tell, when it changed.
		local
			l_key: STRING_32
		do
			l_key := a_key.to_string_32
			if not raw (l_key).same_string_general (a_value) then
				values.force (a_value.to_string_32, l_key)
				save
				changed_actions.call ([l_key])
			end
		end

feature {NONE} -- The file

	load
			-- Read the file, if there is one; a bad file is ignored.
		local
			l_json: SIMPLE_JSON
		do
			if (create {RAW_FILE}.make_with_path (file)).exists then
				create l_json
				if attached l_json.deserialize_file (file.name) as al_v and then al_v.is_object then
					loaded := al_v.as_object
				end
			end
		end

	save
			-- Write every value (and the file's unknown keys) as JSON.
		local
			l_object: SIMPLE_JSON_OBJECT
			l_out: PLAIN_TEXT_FILE
			l_utf: UTF_CONVERTER
		do
			if attached loaded as al_file then
				l_object := al_file
			else
				create l_object.make
				loaded := l_object
			end
			across entries as ic loop
				if attached values.item (ic.key) as al_v then
					inspect ic.kind
					when Kind_boolean then
						l_object.put_boolean (al_v.same_string ("True"), ic.key).do_nothing
					when Kind_integer then
						l_object.put_integer (al_v.to_integer_64, ic.key).do_nothing
					else
						l_object.put_string (al_v, ic.key).do_nothing
					end
				end
			end
			ensure_folder
			create l_out.make_with_path (file)
			l_out.open_write
			l_out.put_string (l_utf.string_32_to_utf_8_string_8 (l_object.to_pretty_json))
			l_out.close
		end

	ensure_folder
		local
			l_dir: DIRECTORY
		do
			if attached file.parent as al_parent then
				create l_dir.make_with_path (al_parent)
				if not l_dir.exists then
					l_dir.recursive_create_dir
				end
			end
		end

	settings_folder (an_application_name: READABLE_STRING_GENERAL): PATH
			-- %APPDATA%\name on Windows, ~/Library/Application Support/name on macOS,
			-- $XDG_CONFIG_HOME/name or ~/.config/name elsewhere.
		local
			l_env: EXECUTION_ENVIRONMENT
			l_home: STRING_32
		do
			create l_env
			if attached l_env.item ("HOME") as al_h then l_home := al_h else l_home := {STRING_32} "." end
			if {PLATFORM}.is_windows then
				if attached l_env.item ("APPDATA") as al_a then
					create Result.make_from_string (al_a)
				else
					create Result.make_from_string (l_home)
				end
			elseif {PLATFORM}.is_mac then
				create Result.make_from_string (l_home + "/Library/Application Support")
			elseif attached l_env.item ("XDG_CONFIG_HOME") as al_x and then not al_x.is_empty then
				create Result.make_from_string (al_x)
			else
				create Result.make_from_string (l_home + "/.config")
			end
			Result := Result.extended (an_application_name)
		end

feature {NONE} -- Text forms

	color_text (a_color: NATURAL_32): STRING_32
			-- "#RRGGBB".
		do
			Result := {STRING_32} "#" + (a_color & 0xFFFFFF).to_hex_string.tail (6)
		end

	is_color_text (a_text: READABLE_STRING_32): BOOLEAN
		do
			Result := a_text.count = 7 and then a_text [1] = '#'
				and then across a_text.substring (2, 7) as ic all ic.is_hexa_digit end
		end

	color_of (a_text: READABLE_STRING_32): NATURAL_32
		local
			i: INTEGER
			c: CHARACTER_32
		do
			if is_color_text (a_text) then
				from i := 2 until i > 7 loop
					c := a_text [i].as_lower
					if c.is_digit then
						Result := Result * 16 + (c.code - ('0').code).to_natural_32
					else
						Result := Result * 16 + (c.code - ('a').code + 10).to_natural_32
					end
					i := i + 1
				end
			end
		end

	font_text (a_font: GUI_FONT_CHOICE): STRING_32
			-- "family|size|bold|italic".
		do
			Result := a_font.family + "|" + a_font.size.out + "|" + a_font.is_bold.out + "|" + a_font.is_italic.out
		end

	font_of (a_text: READABLE_STRING_32): GUI_FONT_CHOICE
		local
			l_parts: LIST [READABLE_STRING_32]
			l_size: REAL_64
		do
			l_parts := a_text.split ('|')
			if l_parts.count = 4 and then l_parts [2].is_real_64 and then l_parts [2].to_real_64 > 0.0 then
				l_size := l_parts [2].to_real_64
				create Result.make (l_parts [1], l_size, l_parts [3].same_string ("True"), l_parts [4].same_string ("True"))
			else
				create Result.make ("Sans", 11.0, False, False)
			end
		end

feature {NONE} -- The window's forms

	section_form (a_section: STRING_32): GUI_STACK
			-- Section `a_section''s entries, a label and a control each, then "Restore defaults".
		local
			l_reset: GUI_BUTTON
		do
			create Result.make_vertical
			Result.set_spacing (8)
			across entries as ic loop
				if ic.section.same_string (a_section) then
					Result.extend (control_row (ic.key, ic.label, ic.kind))
				end
			end
			create l_reset.make ("Restore defaults")
			l_reset.click_actions.extend (agent restore_section (a_section))
			Result.extend (l_reset)
		end

	control_row (a_key, a_label: STRING_32; a_kind: INTEGER): GUI_WIDGET
			-- A row: the label, then the entry's control, bound both ways.
		local
			l_row: GUI_STACK
			l_switch: GUI_SWITCH
			l_spin: GUI_SPIN_BOX
			l_field: GUI_TEXT_FIELD
			l_drop: GUI_DROPDOWN
			l_color: GUI_COLOR_CHOOSER
			l_font: GUI_BUTTON
			l_path: GUI_FILE_FIELD
			l_control: GUI_WIDGET
		do
			create l_row.make_horizontal
			l_row.set_spacing (12)
			l_row.extend (create {GUI_LABEL}.make (a_label))
			inspect a_kind
			when Kind_boolean then
				create l_switch.make
				l_switch.set_on (boolean_item (a_key))
				l_switch.toggle_actions.extend (agent (on: BOOLEAN; k: STRING_32) do set_boolean (k, on) end (?, a_key))
				refreshers.extend (agent (k: STRING_32; s: GUI_SWITCH) do s.set_on (boolean_item (k)) end (a_key, l_switch))
				l_control := l_switch
			when Kind_integer then
				check attached entry (a_key) as al_e then
					create l_spin.make (al_e.minimum, al_e.maximum)
				end
				l_spin.set_value (integer_item (a_key))
				l_spin.change_actions.extend (agent (v: INTEGER; k: STRING_32) do set_integer (k, v) end (?, a_key))
				refreshers.extend (agent (k: STRING_32; s: GUI_SPIN_BOX) do s.set_value (integer_item (k)) end (a_key, l_spin))
				l_control := l_spin
			when Kind_choice then
				create l_drop.make
				across choices_of (a_key) as ic loop l_drop.extend (ic) end
				l_drop.select_row (choices_of (a_key).index_of (text_item (a_key), 1).max (1))
				l_drop.selection_actions.extend (agent (r: INTEGER; k: STRING_32) do if r >= 1 then set_text (k, choices_of (k) [r]) end end (?, a_key))
				refreshers.extend (agent (k: STRING_32; d: GUI_DROPDOWN) do d.select_row (choices_of (k).index_of (text_item (k), 1).max (1)) end (a_key, l_drop))
				l_control := l_drop
			when Kind_color then
				create l_color.make
				l_color.set_color (color_item (a_key))
				l_color.change_actions.extend (agent (c: NATURAL_32; k: STRING_32) do set_color (k, c) end (?, a_key))
				refreshers.extend (agent (k: STRING_32; c: GUI_COLOR_CHOOSER) do c.set_color (color_item (k)) end (a_key, l_color))
				l_control := l_color
			when Kind_font then
				create l_font.make (font_label (font_item (a_key)))
				l_font.click_actions.extend (agent choose_font (a_key, l_font))
				refreshers.extend (agent (k: STRING_32; b: GUI_BUTTON) do b.set_text (font_label (font_item (k))) end (a_key, l_font))
				l_control := l_font
			when Kind_path then
				create l_path.make_open (a_label, <<>>)
				l_path.set_path (path_item (a_key))
				l_path.change_actions.extend (agent (k: STRING_32; f: GUI_FILE_FIELD) do set_path (k, f.path) end (a_key, l_path))
				refreshers.extend (agent (k: STRING_32; f: GUI_FILE_FIELD) do f.set_path (path_item (k)) end (a_key, l_path))
				l_control := l_path
			else
				create l_field.make
				l_field.set_text (text_item (a_key))
				l_field.change_actions.extend (agent (k: STRING_32; f: GUI_TEXT_FIELD) do set_text (k, f.text) end (a_key, l_field))
				refreshers.extend (agent (k: STRING_32; f: GUI_TEXT_FIELD) do f.set_text (text_item (k)) end (a_key, l_field))
				l_control := l_field
			end
			l_control.set_accessible_label (a_label)
			controls.force (l_control, a_key)
			l_row.extend_stretching (l_control)
			Result := l_row
		end

	font_label (a_font: GUI_FONT_CHOICE): STRING_32
		do
			Result := a_font.family + " " + a_font.size.truncated_to_integer.out
		end

	choose_font (a_key: STRING_32; a_button: GUI_BUTTON)
		do
			if attached application.dialogs.choose_font (label_of (a_key), font_item (a_key)) as al_font then
				set_font (a_key, al_font)
				a_button.set_text (font_label (al_font))
			end
		end

	restore_section (a_section: STRING_32)
		do
			reset_section (a_section)
			across refreshers as ic loop
				ic.call (Void)
			end
		end

invariant
	one_value_each: entries.count <= values.count

end
