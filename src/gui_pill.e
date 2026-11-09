note
	description: "[
		A reference pill (1l): a short code that names a part of a window, so a person and a
		helper can talk about it ("C4"), and so anyone can learn what the part is, what it does,
		where it fits in the window's operational flow, and how to reach it from the keyboard
		and the menus. Defined once in the application's list (`GUI_APPLICATION.pills'), then
		put on any widget or container with `GUI_WIDGET.set_pill'. Filled fluently:

			app.pills.define ("C4", "Reference box")
				.with_purpose ("Opens a passage typed as 'John 3:16'; anything else is searched.")
				.with_flow ("Step 1 of reading: name a place, then read it in the text below.")
				.with_shortcut ("primary+L")
				.with_menu_path ("Go > Reference").do_nothing

		Shortcuts are written neutrally ("primary+shift+P") and shown as each platform writes
		them: Cmd+Shift+P on macOS, Ctrl+Shift+P elsewhere.
	]"

class
	GUI_PILL

create {GUI_PILLS}
	make

feature {NONE} -- Initialization

	make (a_code, a_name: READABLE_STRING_GENERAL)
		require
			coded: not a_code.is_empty
			named: not a_name.is_empty
		do
			code := a_code.to_string_32
			name := a_name.to_string_32
			create purpose.make_empty
			create flow.make_empty
			create shortcut.make_empty
			create menu_path.make_empty
		ensure
			code_set: code.same_string_general (a_code)
			name_set: name.same_string_general (a_name)
		end

feature -- Access

	code: STRING_32
			-- "C4", "P05.2": what the pill shows.

	name: STRING_32
			-- What the part is: "Reference box".

	purpose: STRING_32
			-- What it does.

	flow: STRING_32
			-- Where it fits in the window's operational flow.

	shortcut: STRING_32
			-- Its keyboard shortcut, neutral ("primary+L"); empty for none.

	menu_path: STRING_32
			-- Where it is in the menus ("Go > Reference"); empty for none.

	tip: STRING_32
			-- What the pointer reads on the pill: the code and name, then each part given, the
			-- shortcut as this platform writes it.
		do
			create Result.make (120)
			Result.append (code)
			Result.append ({STRING_32} ": ")
			Result.append (name)
			append_line (Result, "What it does: ", purpose)
			append_line (Result, "In the flow: ", flow)
			append_line (Result, "Keyboard: ", shown_shortcut (shortcut))
			append_line (Result, "Menu: ", menu_path)
		ensure
			leads_with_code: Result.starts_with (code)
		end

feature -- Element change

	with_purpose (a_text: READABLE_STRING_GENERAL): like Current
		do
			purpose := a_text.to_string_32
			Result := Current
		ensure
			set: purpose.same_string_general (a_text)
			chained: Result = Current
		end

	with_flow (a_text: READABLE_STRING_GENERAL): like Current
		do
			flow := a_text.to_string_32
			Result := Current
		ensure
			set: flow.same_string_general (a_text)
			chained: Result = Current
		end

	with_shortcut (a_shortcut: READABLE_STRING_GENERAL): like Current
			-- A neutral shortcut: "primary+L", "primary+shift+P", "F1".
		do
			shortcut := a_shortcut.to_string_32
			Result := Current
		ensure
			set: shortcut.same_string_general (a_shortcut)
			chained: Result = Current
		end

	with_menu_path (a_path: READABLE_STRING_GENERAL): like Current
		do
			menu_path := a_path.to_string_32
			Result := Current
		ensure
			set: menu_path.same_string_general (a_path)
			chained: Result = Current
		end

	with_menu_item (a_menu: GUI_MENU; an_item_id: INTEGER): like Current
			-- The menu path and shortcut of item `an_item_id' of `a_menu', as the menu has them,
			-- so the two never drift apart.
		require
			in_the_menu: a_menu.has_item (an_item_id)
		do
			create menu_path.make_from_string (a_menu.title)
			if not menu_path.is_empty then
				menu_path.append ({STRING_32} " > ")
			end
			menu_path.append (a_menu.item_text (an_item_id))
			if not a_menu.item_shortcut (an_item_id).is_empty then
				shortcut := a_menu.item_shortcut (an_item_id).twin
			end
			Result := Current
		ensure
			path_from_menu: menu_path.has_substring (a_menu.item_text (an_item_id))
			chained: Result = Current
		end

feature -- Conversion

	shown_shortcut (a_neutral: READABLE_STRING_GENERAL): STRING_32
			-- `a_neutral' ("primary+shift+P") as this platform writes it: "Cmd+Shift+P" on
			-- macOS, "Ctrl+Shift+P" elsewhere; empty for empty.
		local
			l_parts: LIST [READABLE_STRING_GENERAL]
			l_part: STRING_32
		do
			create Result.make (16)
			if not a_neutral.is_empty then
				l_parts := a_neutral.split ('+')
				across l_parts as ic loop
					l_part := ic.to_string_32
					l_part.to_lower
					if not Result.is_empty then
						Result.append_character ('+')
					end
					if l_part.same_string ("primary") then
						Result.append (if {PLATFORM}.is_mac then {STRING_32} "Cmd" else {STRING_32} "Ctrl" end)
					elseif l_part.same_string ("control") or l_part.same_string ("ctrl") then
						Result.append (if {PLATFORM}.is_mac then {STRING_32} "Control" else {STRING_32} "Ctrl" end)
					elseif l_part.same_string ("alt") or l_part.same_string ("option") then
						Result.append (if {PLATFORM}.is_mac then {STRING_32} "Option" else {STRING_32} "Alt" end)
					elseif l_part.same_string ("shift") then
						Result.append ({STRING_32} "Shift")
					elseif l_part.count = 1 then
						l_part.to_upper
						Result.append (l_part)
					else
						l_part.put (l_part.item (1).as_upper, 1)
						Result.append (l_part)
					end
				end
			end
		end

feature {NONE} -- Implementation

	append_line (a_text: STRING_32; a_label, a_value: READABLE_STRING_GENERAL)
			-- A new line "`a_label'`a_value'" on `a_text', unless `a_value' is empty.
		do
			if not a_value.is_empty then
				a_text.append_character ('%N')
				a_text.append_string_general (a_label)
				a_text.append_string_general (a_value)
			end
		end

invariant
	coded: not code.is_empty
	named: not name.is_empty

end
