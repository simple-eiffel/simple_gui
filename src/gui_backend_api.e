note
	description: "[
		The contract every simple_gui backend implements (GTK 4, AppKit, Windows).
		Native objects are named by positive integer ids. Strings cross the C boundary
		as UTF-8 (`to_c' and `from_c'). Events are polled with `next'; no backend ever
		calls into Eiffel.

		Events [type, id, a, b, c] (spec section 5): 1 click | 2 text changed | 3 activate
		| 4 selection (a = row, 1-based) | 5 menu (a = item id) | 6 close requested
		| 7 pointer (a = x, b = y, c = kind + buttons << 4 + modifiers << 8)
		| 8 key (a = key code, b = character, c = modifiers << 8) | 9 resize (a, b)
		| 10 appearance (a = 1 dark) | 11 wake | 12 toggled (a = 1 checked)
		| 13 page changed (a = page, 1-based).
		Text areas report text changed (2) like fields.

		Menu roles: 0 none | 1 about | 2 settings | 3 quit | 10 undo | 11 redo | 12 cut
		| 13 copy | 14 paste | 15 select all. A backend places role items where its
		platform expects them (the macOS application menu; window menus elsewhere).
	]"

deferred class
	GUI_BACKEND_API

feature -- Lifecycle and loop

	init (a_name, a_id: POINTER): BOOLEAN
			-- Start the toolkit for application `a_name' with identifier `a_id'. False without a display.
		deferred
		end

	is_gui_thread: BOOLEAN
			-- Is the caller on the thread that ran `init'?
		deferred
		end

	pump (a_ms: INTEGER)
			-- Run the native loop for at most `a_ms' milliseconds, returning early once an event is queued.
		require
			non_negative: a_ms >= 0
		deferred
		end

	pump_until_idle (a_ms: INTEGER)
			-- Run the loop until no native work is pending, or `a_ms' pass (tests).
		require
			non_negative: a_ms >= 0
		deferred
		end

	start_heartbeat (a_ms: INTEGER)
			-- Keep the loop turning at least every `a_ms' milliseconds.
		require
			positive: a_ms > 0
		deferred
		end

	wake
			-- Wake the GUI loop. Callable from any thread; coalescing.
		deferred
		end

	next (a_type, an_id, a_a, a_b, a_c: TYPED_POINTER [INTEGER]): BOOLEAN
			-- Take the oldest queued event into the five targets; False when the queue is empty.
		deferred
		end

feature -- Windows and containers

	window (a_title: POINTER; a_width, a_height: INTEGER): INTEGER
		require
			sized: a_width > 0 and a_height > 0
		deferred
		ensure
			named: Result > 0
		end

	window_set_content (a_window, a_child: INTEGER)
		deferred
		end

	window_show (a_window: INTEGER)
		deferred
		end

	window_close (a_window: INTEGER)
		deferred
		end

	window_set_title (a_window: INTEGER; a_title: POINTER)
		deferred
		end

	window_install_shortcuts (a_window: INTEGER; a_spec: POINTER)
			-- Keyboard shortcuts for menu items, "item_id=shortcut;..." (a backend whose menus carry
			-- their own key equivalents may ignore this).
		deferred
		end

	stack (a_vertical: BOOLEAN; a_spacing: INTEGER): INTEGER
		require
			non_negative: a_spacing >= 0
		deferred
		ensure
			named: Result > 0
		end

	stack_extend (a_stack, a_child: INTEGER; a_stretch: BOOLEAN)
		deferred
		end

	stack_set_spacing (a_stack, a_spacing: INTEGER)
		deferred
		end

	stack_set_alignment (a_stack, an_alignment: INTEGER)
			-- Cross-axis alignment for the stack's children, existing and later:
			-- 0 fill, 1 start, 2 center, 3 end.
		require
			known: an_alignment >= 0 and an_alignment <= 3
		deferred
		end

	stack_align_child (a_stack, a_child, an_alignment: INTEGER)
			-- Cross-axis alignment for one child.
		require
			known: an_alignment >= 0 and an_alignment <= 3
		deferred
		end

	grid: INTEGER
		deferred
		ensure
			named: Result > 0
		end

	grid_put (a_grid, a_child, a_row, a_column, a_rows, a_columns: INTEGER)
		require
			cell: a_row >= 1 and a_column >= 1 and a_rows >= 1 and a_columns >= 1
		deferred
		end

	grid_set_spacing (a_grid, a_row_gap, a_column_gap: INTEGER)
		deferred
		end

	splitter (a_vertical: BOOLEAN): INTEGER
			-- Two panes and a divider: side by side, or stacked when `a_vertical'. When it grows,
			-- the first pane keeps its size.
		deferred
		ensure
			named: Result > 0
		end

	splitter_set_pane (a_splitter, a_pane, a_child: INTEGER)
			-- Put `a_child' in pane `a_pane' (1 leading or top, 2 trailing or bottom).
		require
			pane: a_pane = 1 or a_pane = 2
		deferred
		end

	splitter_position (a_splitter: INTEGER): INTEGER
			-- The divider's distance from the leading edge (or the top), in logical pixels.
		deferred
		end

	splitter_set_position (a_splitter, a_position: INTEGER)
			-- Move the divider (no event).
		deferred
		end

	grid_set_homogeneous_columns (a_grid: INTEGER; a_on: BOOLEAN)
			-- Give every column the same width.
		deferred
		end

	grid_set_stretching_column (a_grid, a_column: INTEGER)
			-- Column `a_column' (1-based; 0 = none) takes the spare width.
		require
			non_negative: a_column >= 0
		deferred
		end

feature -- Controls

	label (a_text: POINTER): INTEGER
		deferred
		ensure
			named: Result > 0
		end

	label_set (an_id: INTEGER; a_text: POINTER)
		deferred
		end

	label_get (an_id: INTEGER): POINTER
		deferred
		end

	label_set_wrap_width (an_id, a_characters: INTEGER)
			-- `a_characters' > 0: wrap at about that many characters wide; 0: one line, ending in an ellipsis.
		require
			non_negative: a_characters >= 0
		deferred
		end

	button (a_text: POINTER): INTEGER
		deferred
		ensure
			named: Result > 0
		end

	button_set (an_id: INTEGER; a_text: POINTER)
		deferred
		end

	button_get (an_id: INTEGER): POINTER
		deferred
		end

	field: INTEGER
		deferred
		ensure
			named: Result > 0
		end

	field_set (an_id: INTEGER; a_text: POINTER)
			-- Set the text WITHOUT a text-changed event.
		deferred
		end

	field_get (an_id: INTEGER): POINTER
		deferred
		end

	field_set_placeholder (an_id: INTEGER; a_text: POINTER)
		deferred
		end

	check_box (a_text: POINTER): INTEGER
		deferred
		ensure
			named: Result > 0
		end

	check_box_set (an_id: INTEGER; a_on: BOOLEAN)
			-- Check or clear WITHOUT a toggled event.
		deferred
		end

	check_box_is_checked (an_id: INTEGER): BOOLEAN
		deferred
		end

	check_box_set_text (an_id: INTEGER; a_text: POINTER)
		deferred
		end

	check_box_text (an_id: INTEGER): POINTER
		deferred
		end

	text_area: INTEGER
		deferred
		ensure
			named: Result > 0
		end

	text_area_set (an_id: INTEGER; a_text: POINTER)
			-- Set the text WITHOUT a text-changed event.
		deferred
		end

	text_area_get (an_id: INTEGER): POINTER
		deferred
		end

	text_area_set_read_only (an_id: INTEGER; a_on: BOOLEAN)
		deferred
		end

	tabs: INTEGER
			-- Pages under a row of tabs.
		deferred
		ensure
			named: Result > 0
		end

	tabs_extend (a_tabs, a_page: INTEGER; a_title: POINTER)
			-- Add `a_page' as the last page; the first page added is shown.
		deferred
		end

	tabs_select (a_tabs, a_page: INTEGER)
			-- Show page `a_page' (1-based) WITHOUT a page-changed event.
		deferred
		end

	tabs_selected (a_tabs: INTEGER): INTEGER
			-- The page shown (1-based), or 0.
		deferred
		end

	tabs_set_title (a_tabs, a_page: INTEGER; a_title: POINTER)
		deferred
		end

	list: INTEGER
		deferred
		ensure
			named: Result > 0
		end

	list_extend (an_id: INTEGER; a_text: POINTER)
		deferred
		end

	list_wipe_out (an_id: INTEGER)
		deferred
		end

	list_select (an_id, a_row: INTEGER)
			-- Select row `a_row' (1-based; 0 clears) WITHOUT a selection event.
		require
			not_negative: a_row >= 0
		deferred
		end

	list_selected (an_id: INTEGER): INTEGER
			-- The selected row, 1-based; 0 when none.
		deferred
		ensure
			not_negative: Result >= 0
		end

	table (a_titles: POINTER): INTEGER
			-- Rows of text in columns titled by `a_titles' (joined by U+001F). A user's selection
			-- sends selection (4, a = first selected row); a click on a header sends header
			-- clicked (14, a = column, 1-based).
		deferred
		ensure
			named: Result > 0
		end

	table_extend (a_table: INTEGER; a_cells: POINTER)
			-- Add a row: one text per column, joined by U+001F.
		deferred
		end

	table_wipe_out (a_table: INTEGER)
			-- Remove every row and the selection, without an event.
		deferred
		end

	table_set_multiple (a_table: INTEGER; a_on: BOOLEAN)
		deferred
		end

	table_select (a_table, a_row: INTEGER; a_extend: BOOLEAN)
			-- Select row `a_row' (0: clear), adding to the selection when `a_extend'; no event.
		deferred
		end

	table_selected_count (a_table: INTEGER): INTEGER
		deferred
		end

	table_selected_at (a_table, i: INTEGER): INTEGER
			-- The `i'-th selected row, ascending.
		deferred
		end

	table_set_sort_indicator (a_table, a_column: INTEGER; a_ascending: BOOLEAN)
			-- Show the sort indicator on `a_column' (0: none); no event.
		deferred
		end

	table_set_source (a_table, a_count: INTEGER)
			-- Rows 1 .. `a_count' come from the program from now on (1f): drop the rows held and the
			-- selection; when a row to be drawn is not held, draw it empty and send rows wanted
			-- (16, a = first, b = last) for the rows in view plus a margin, never again for rows
			-- asked for and not yet answered; a count of 0 asks for nothing. No other event.
		deferred
		end

	table_set_row (a_table, a_row: INTEGER; a_cells: POINTER)
			-- Row `a_row''s texts (one per column, joined by U+001F), answering rows wanted: hold
			-- them (a bounded cache) and draw the row.
		deferred
		end

	table_set_row_count (a_table, a_count: INTEGER)
			-- The source now has `a_count' rows: rows held past it go, and so do selected rows past
			-- it; no event.
		deferred
		end

	table_forget_rows (a_table: INTEGER)
			-- Every row may have changed: drop what is held and ask again for what is in view.
		deferred
		end

	table_forget_row (a_table, a_row: INTEGER)
			-- Row `a_row' changed: drop it and ask again if it is in view.
		deferred
		end

	table_scroll_to (a_table, a_row: INTEGER)
			-- Bring row `a_row' into view.
		deferred
		end

	tree: INTEGER
			-- A hierarchy of text nodes. A user's selection sends selection (4, a = node); a user's
			-- expanding or collapsing sends expansion (15, a = node, b = 1 when expanded).
		deferred
		ensure
			named: Result > 0
		end

	tree_add (a_tree, a_node, a_parent: INTEGER; a_text: POINTER)
			-- Add node `a_node' (numbered by the caller, 1, 2, 3...) under `a_parent' (0: a root).
		deferred
		end

	tree_set_expanded (a_tree, a_node: INTEGER; a_on: BOOLEAN)
			-- Expand or collapse `a_node', without an event.
		deferred
		end

	tree_is_expanded (a_tree, a_node: INTEGER): BOOLEAN
		deferred
		end

	tree_select (a_tree, a_node: INTEGER)
			-- Select `a_node' (0: clear), expanding its ancestors; no event.
		deferred
		end

	tree_selected (a_tree: INTEGER): INTEGER
			-- The selected node, or 0.
		deferred
		end

feature -- Common widget state

	set_enabled (an_id: INTEGER; a_on: BOOLEAN)
		deferred
		end

	is_enabled (an_id: INTEGER): BOOLEAN
		deferred
		end

	set_visible (an_id: INTEGER; a_on: BOOLEAN)
		deferred
		end

	is_visible (an_id: INTEGER): BOOLEAN
		deferred
		end

	set_direction (an_id, a_direction: INTEGER)
			-- 0 automatic, 1 left to right, 2 right to left.
		require
			known: a_direction >= 0 and a_direction <= 2
		deferred
		end

	set_accessible_label (an_id: INTEGER; a_text: POINTER)
		deferred
		end

	set_accessible_description (an_id: INTEGER; a_text: POINTER)
		deferred
		end

	widget_x (an_id: INTEGER): INTEGER
			-- Left edge of `an_id''s own frame, from the top-left of its window's content area
			-- (no title bar, no menu bar), logical pixels, after layout. For a container, its
			-- inner stack or grid (margins excluded).
		deferred
		end

	widget_y (an_id: INTEGER): INTEGER
			-- Top edge, measured like `widget_x', y growing downward.
		deferred
		end

	accessible_role (an_id: INTEGER): POINTER
			-- The toolkit's accessibility role name for `an_id'.
		deferred
		end

feature -- Canvas

	canvas (a_width, a_height: INTEGER): INTEGER
		require
			sized: a_width > 0 and a_height > 0
		deferred
		ensure
			named: Result > 0
		end

	canvas_present (an_id: INTEGER; a_cairo_surface: POINTER)
			-- Show the finished image `a_cairo_surface' (a cairo_surface_t at device scale).
			-- The backend keeps its own reference.
		deferred
		end

	scale_factor (an_id: INTEGER): INTEGER
			-- `scale' rounded up (superseded by `scale').
		deferred
		ensure
			positive: Result >= 1
		end

	scale (an_id: INTEGER): REAL_64
			-- Device pixels per logical pixel for canvas `an_id', fractional where the platform
			-- is (Windows 1.25 and 1.5, GTK's fractional scaling, AppKit's backingScaleFactor).
			-- By default the whole-number `scale_factor'; a backend redefines it.
		do
			Result := scale_factor (an_id)
		ensure
			positive: Result > 0.0
		end

	width (an_id: INTEGER): INTEGER
		deferred
		end

	height (an_id: INTEGER): INTEGER
		deferred
		end

feature -- Menus

	menu_new (a_title: POINTER): POINTER
			-- A new application-level menu.
		deferred
		end

	menu_add_item (a_menu: POINTER; a_text, a_shortcut: POINTER; an_item_id, a_role: INTEGER)
			-- Item `an_item_id' (event 5) with platform role `a_role'. Edit roles (10 to 15) use the
			-- toolkit's own text actions and raise no event; their id serves `menu_set_item_text'.
		require
			role_known: (a_role >= 0 and a_role <= 3) or (a_role >= 10 and a_role <= 15)
			numbered: an_item_id > 0
		deferred
		end

	menu_set_title (a_menu: POINTER; a_title: POINTER)
			-- Relabel top-level menu `a_menu'.
		deferred
		end

	menu_title (a_menu: POINTER): POINTER
			-- The label the toolkit shows now for `a_menu'.
		deferred
		end

	menu_set_item_text (an_item_id: INTEGER; a_text: POINTER)
			-- Relabel item `an_item_id', keeping its action and shortcut.
		require
			numbered: an_item_id > 0
		deferred
		end

	menu_item_text (an_item_id: INTEGER): POINTER
			-- The label the toolkit shows now for item `an_item_id'.
		require
			numbered: an_item_id > 0
		deferred
		end

	menu_add_separator (a_menu: POINTER)
		deferred
		end

	context_menu_new: POINTER
			-- A menu that is not in the menu bar, for `widget_set_context_menu'; items are added to
			-- it like any menu's and send menu events (5).
		deferred
		end

	widget_set_context_menu (an_id: INTEGER; a_menu: POINTER)
			-- Show `a_menu' on a secondary click on widget `an_id'.
		deferred
		end

feature -- Dialogs

	open_file (a_window: INTEGER; a_title: POINTER; a_save: BOOLEAN; an_extensions: POINTER): POINTER
			-- Chosen path (UTF-8), or default_pointer when canceled. `an_extensions' is "txt;md" or "".
		deferred
		end

	message (a_window: INTEGER; a_title, a_text: POINTER; a_confirm: BOOLEAN): BOOLEAN
			-- Show a message; with `a_confirm', True when the user chose OK.
		deferred
		end

feature -- Appearance

	is_dark: BOOLEAN
		deferred
		end

	system_color (a_role: INTEGER): INTEGER
			-- The theme's color as 0xRRGGBB: 1 window background, 2 text, 3 secondary text,
			-- 4 accent, 5 selection, 6 separator. It follows the light or dark appearance.
		require
			known: a_role >= 1 and a_role <= 6
		deferred
		ensure
			rgb: Result >= 0 and Result <= 0xFFFFFF
		end

	set_dark (a_on: BOOLEAN)
			-- Tests only: force the dark or light appearance.
		deferred
		end

feature -- Test driver

	test_click (an_id: INTEGER)
		deferred
		end

	test_click_header (a_table, a_column: INTEGER)
			-- Click column `a_column's header AS A USER WOULD (emits header clicked, 14).
		deferred
		end

	test_expand (a_tree, a_node: INTEGER; a_on: BOOLEAN)
			-- Expand or collapse `a_node' AS A USER WOULD (emits expansion, 15). Choosing a node as
			-- a user is `test_choose' with the node's number.
		deferred
		end

	test_type (an_id: INTEGER; a_text: POINTER)
			-- Set a field's text AS A USER WOULD (emits text changed).
		deferred
		end

	test_choose (an_id, a_row: INTEGER)
			-- Select row `a_row' of a list, or show page `a_row' of tabs, AS A USER WOULD
			-- (emits selection, or page changed).
		deferred
		end

	test_menu (an_item_id: INTEGER)
		deferred
		end

	test_request_close (a_window: INTEGER)
			-- Ask to close window `a_window' as the user would (emits close requested).
		deferred
		end

	test_focus (an_id: INTEGER)
			-- Give widget `an_id' the keyboard focus, as a click on it would.
		deferred
		end

	test_edit_enabled (a_role: INTEGER): BOOLEAN
			-- Would Edit role `a_role' (10 undo .. 15 select all) be enabled now, for the focus
			-- of the window in front?
		require
			edit_role: a_role >= 10 and a_role <= 15
		deferred
		end

	test_context_menu (an_id, an_item_id: INTEGER): BOOLEAN
			-- Choose item `an_item_id' from widget `an_id's context menu AS A USER WOULD (emits the
			-- menu event); False when that widget's context menu has no such item.
		deferred
		end

	snapshot (an_id: INTEGER; a_path: POINTER): BOOLEAN
			-- Render window `an_id' to a PNG at `a_path'.
		deferred
		end

	describe_accessibility (a_window: INTEGER): POINTER
			-- The assistive tree of window `a_window', one "role: name" line per node,
			-- indented by depth: what a screen reader is given, not what was set.
		deferred
		end

feature -- Strings across the boundary

	to_c (a_text: READABLE_STRING_GENERAL): C_STRING
			-- `a_text' as a UTF-8 C string.
		do
			create Result.make ({UTF_CONVERTER}.utf_32_string_to_utf_8_string_8 (a_text.to_string_32))
		end

	from_c (a_pointer: POINTER): STRING_32
			-- The UTF-8 C string at `a_pointer', or empty for a null pointer.
		local
			l_c: C_STRING
		do
			if a_pointer = default_pointer then
				create Result.make_empty
			else
				create l_c.make_by_pointer (a_pointer)
				Result := {UTF_CONVERTER}.utf_8_string_8_to_string_32 (l_c.string)
			end
		end

end
