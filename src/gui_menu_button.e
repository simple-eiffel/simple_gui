note
	description: "[
		A button that opens a menu (GtkMenuButton, a pull-down NSPopUpButton, an SW_BUTTON with
		an SW_MENU popup). Its menu's items report as any GUI_MENU's do. `make_split' adds a main
		part that is a button of its own: a click on it fires `click_actions'; the arrow opens
		the menu (NSComboButton on macOS).
	]"

class
	GUI_MENU_BUTTON

inherit
	GUI_WIDGET
		redefine
			default_accessible_label, dispatch
		end

create
	make, make_split

feature {NONE} -- Initialization

	make (a_text: READABLE_STRING_GENERAL)
			-- A button titled `a_text' that opens its menu.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			make_button (a_text, False)
		ensure
			not_split: not is_split
		end

	make_split (a_text: READABLE_STRING_GENERAL)
			-- A button titled `a_text' with an arrow beside it that opens its menu.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			make_button (a_text, True)
		ensure
			split: is_split
		end

feature -- Access

	text: STRING_32

	is_split: BOOLEAN

	menu: detachable GUI_MENU

	click_actions: GUI_ACTIONS [TUPLE]
			-- Run when the user clicks the main part of a split button.

feature -- Element change

	set_menu (a_menu: GUI_MENU)
			-- Open `a_menu' from this button.
		require
			gui_thread: is_gui_thread
		do
			menu := a_menu
			backend.menu_button_set_menu (id, a_menu.handle)
		ensure
			set: menu = a_menu
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 1 then
				click_actions.call (Void)
			end
		end

feature {NONE} -- Implementation

	make_button (a_text: READABLE_STRING_GENERAL; a_split: BOOLEAN)
		local
			l_c: C_STRING
		do
			create click_actions.make
			text := a_text.to_string_32
			is_split := a_split
			l_c := backend.to_c (a_text)
			register (backend.menu_button (l_c.item, a_split))
		end

	default_accessible_label: STRING_32
		do
			Result := text
		end

end
