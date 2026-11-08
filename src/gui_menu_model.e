note
	description: "[
		The application's menus (on macOS they belong to the application, not a window).
		Items are numbered 1, 2, 3... across all menus; choosing one runs its agent.
		Shortcuts are written neutrally: "primary+O" is Cmd+O on macOS and Ctrl+O elsewhere.
	]"

class
	GUI_MENU_MODEL

inherit
	GUI_SHARED

create
	make

feature {NONE} -- Initialization

	make
		do
			create menus.make (4)
			create actions.make (16)
			create shortcut_spec.make_empty
		ensure
			no_items: item_count = 0
		end

feature -- Access

	menus: ARRAYED_LIST [GUI_MENU]
			-- Top-level menus, in order.

	item_count: INTEGER
			-- Items with an agent, across all menus (their ids are 1 .. item_count).

	shortcut_spec: STRING_32
			-- "id=shortcut;..." for every item with a shortcut.

feature -- Element change

	add_menu (a_title: READABLE_STRING_GENERAL): GUI_MENU
			-- A new top-level menu titled `a_title'.
		require
			gui_thread: is_gui_thread
			titled: not a_title.is_empty
		do
			create Result.make (Current, a_title)
			menus.extend (Result)
		ensure
			added: menus.last = Result
		end

feature {GUI_APPLICATION, GUI_TEST_DRIVER} -- Events

	invoke (an_item_id: INTEGER)
			-- Run item `an_item_id''s agent.
		do
			if attached actions.item (an_item_id) as al_action then
				al_action.call (Void)
			end
		end

feature {GUI_MENU} -- Registration

	register_item (an_action: PROCEDURE; a_shortcut: READABLE_STRING_GENERAL)
			-- Number a new item `item_count' + 1, running `an_action'.
		do
			item_count := item_count + 1
			actions.force (an_action, item_count)
			if not a_shortcut.is_empty then
				if not shortcut_spec.is_empty then
					shortcut_spec.append_character (';')
				end
				shortcut_spec.append_integer (item_count)
				shortcut_spec.append_character ('=')
				shortcut_spec.append_string_general (a_shortcut)
			end
		ensure
			one_more: item_count = old item_count + 1
		end

feature {NONE} -- Implementation

	actions: HASH_TABLE [PROCEDURE, INTEGER]

end
