note
	description: "[
		One top-level menu. Role items (about, settings, quit) go where the platform
		expects: macOS moves them to the application menu. Edit items (undo ... select
		all) act on the focused text field through the toolkit's own text actions.
	]"

class
	GUI_MENU

inherit
	GUI_SHARED

create {GUI_MENU_MODEL}
	make

feature {NONE} -- Initialization

	make (a_model: GUI_MENU_MODEL; a_title: READABLE_STRING_GENERAL)
		local
			l_c: C_STRING
		do
			model := a_model
			title := a_title.to_string_32
			l_c := backend.to_c (a_title)
			handle := backend.menu_new (l_c.item)
		ensure
			model_set: model = a_model
		end

feature -- Access

	title: STRING_32

	model: GUI_MENU_MODEL

	last_item_id: INTEGER
			-- The id of the item most recently added with an agent (for `invoke_menu' in tests).

feature -- Roles

	Role_none: INTEGER = 0
	Role_about: INTEGER = 1
	Role_settings: INTEGER = 2
	Role_quit: INTEGER = 3
	Role_undo: INTEGER = 10
	Role_redo: INTEGER = 11
	Role_cut: INTEGER = 12
	Role_copy: INTEGER = 13
	Role_paste: INTEGER = 14
	Role_select_all: INTEGER = 15

feature -- Element change

	add_item (a_text, a_shortcut: READABLE_STRING_GENERAL; an_action: PROCEDURE)
			-- An item running `an_action'; `a_shortcut' such as "primary+O", or empty.
		require
			gui_thread: is_gui_thread
			has_text: not a_text.is_empty
		do
			add_role_item (Role_none, a_text, a_shortcut, an_action)
		ensure
			numbered: last_item_id = model.item_count
		end

	add_role_item (a_role: INTEGER; a_text, a_shortcut: READABLE_STRING_GENERAL; an_action: PROCEDURE)
			-- An about, settings or quit item, placed where the platform expects it.
		require
			gui_thread: is_gui_thread
			has_text: not a_text.is_empty
			role: a_role >= Role_none and a_role <= Role_quit
		local
			l_t, l_s: C_STRING
		do
			model.register_item (an_action, a_shortcut)
			last_item_id := model.item_count
			l_t := backend.to_c (a_text)
			l_s := backend.to_c (a_shortcut)
			backend.menu_add_item (handle, l_t.item, l_s.item, last_item_id, a_role)
		ensure
			numbered: last_item_id = model.item_count
			one_more: model.item_count = old model.item_count + 1
		end

	add_edit_item (a_role: INTEGER; a_text: READABLE_STRING_GENERAL)
			-- An Edit item acting on the focused text field (the toolkit's own action; its id is
			-- for relabelling only).
		require
			gui_thread: is_gui_thread
			has_text: not a_text.is_empty
			edit_role: a_role >= Role_undo and a_role <= Role_select_all
		local
			l_t, l_s: C_STRING
		do
			model.register_item (agent do_nothing, "")
			last_item_id := model.item_count
			l_t := backend.to_c (a_text)
			l_s := backend.to_c ("")
			backend.menu_add_item (handle, l_t.item, l_s.item, last_item_id, a_role)
		ensure
			numbered: last_item_id = model.item_count
			one_more: model.item_count = old model.item_count + 1
		end

	set_title (a_title: READABLE_STRING_GENERAL)
			-- Relabel this menu (for example on a change of language).
		require
			gui_thread: is_gui_thread
			has_text: not a_title.is_empty
		local
			l_c: C_STRING
		do
			title := a_title.to_string_32
			l_c := backend.to_c (a_title)
			backend.menu_set_title (handle, l_c.item)
		ensure
			set: title.same_string_general (a_title)
			shown: shown_title.same_string_general (a_title)
		end

	shown_title: STRING_32
			-- The title the toolkit shows now.
		do
			Result := backend.from_c (backend.menu_title (handle))
		end

	set_item_text (an_item_id: INTEGER; a_text: READABLE_STRING_GENERAL)
			-- Relabel item `an_item_id' (from `last_item_id'), keeping its action and shortcut.
		require
			gui_thread: is_gui_thread
			numbered: an_item_id >= 1 and an_item_id <= model.item_count
			has_text: not a_text.is_empty
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.menu_set_item_text (an_item_id, l_c.item)
		ensure
			shown: item_text (an_item_id).has_substring (a_text)
				-- Contains, not equals: a Mac shows About and Quit as "About <app>", "Quit <app>".
		end

	item_text (an_item_id: INTEGER): STRING_32
			-- The label the toolkit shows now for item `an_item_id'.
		require
			numbered: an_item_id >= 1 and an_item_id <= model.item_count
		do
			Result := backend.from_c (backend.menu_item_text (an_item_id))
		end

	add_standard_edit_items
			-- Undo, Redo, Cut, Copy, Paste and Select All.
		require
			gui_thread: is_gui_thread
		do
			add_edit_item (Role_undo, "Undo")
			add_edit_item (Role_redo, "Redo")
			add_separator
			add_edit_item (Role_cut, "Cut")
			add_edit_item (Role_copy, "Copy")
			add_edit_item (Role_paste, "Paste")
			add_edit_item (Role_select_all, "Select All")
		end

	add_separator
		require
			gui_thread: is_gui_thread
		do
			backend.menu_add_separator (handle)
		end

feature {NONE} -- Implementation

	handle: POINTER
			-- The backend's menu.

end
