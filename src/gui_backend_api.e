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
		| 13 page changed (a = page, 1-based) | 14 header clicked (a = column) | 15 expansion
		(a = node, b = 1 open) | 16 rows wanted (a = first, b = last) | 17 closed (a popover the user dismissed) | 29 editing ended (a field the user left, 1p).
		A drawn view (1i): 18 pointer (a = x, b = y, c = kind + button * 16 + modifiers * 256;
		kind 1 press, 2 release, 3 move, 4 leave, 5 double, 6 triple; button 1 primary,
		2 secondary, 3 middle) | 19 wheel (a, b, c = delta, 120 a notch, positive away from the
		user) | 20 key (a = GDK keyval, b = 1 down, c = modifiers * 256) | 21 character
		(a = code point) | 22 focus (a = 1 in) | 23 timers (a = 0 tick, 1 fast tick, 2 dwell
		with b = serial).
		Text areas report text changed (2) like fields; spin boxes report it with a = the
		new value; dropdowns report selection (4).

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

	window_set_toolbar (a_window, a_toolbar: INTEGER)
			-- Place `a_toolbar' where the platform expects a window's toolbar.
		deferred
		end

	window_set_status_bar (a_window, a_bar: INTEGER)
			-- Place `a_bar' at the window's bottom.
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

	dock (a_center: INTEGER): INTEGER
			-- 1r-a: a dock around widget `a_center', with no panels.
		deferred
		end

	dock_add (a_dock, a_content, a_side: INTEGER; a_key, a_title: POINTER)
			-- A panel showing widget `a_content', last on `a_side' (1 left, 2 right, 3 top,
			-- 4 bottom); its index is one more than the panels already added.
		deferred
		end

	dock_move (a_dock, an_index, a_side, a_position: INTEGER)
			-- Panel `an_index' to `a_position' (from 1) on `a_side'.
		deferred
		end

	dock_remove (a_dock, an_index: INTEGER)
			-- Panel `an_index' out of the dock; the indices after it move down one.
		deferred
		end

	dock_set_title (a_dock, an_index: INTEGER; a_title: POINTER)
		deferred
		end

	dock_set_tabbed (a_dock, a_side: INTEGER; a_on: BOOLEAN)
		deferred
		end

	dock_activate (a_dock, an_index: INTEGER)
			-- Show panel `an_index' on its tabbed side; no event.
		deferred
		end

	dock_set_size (a_dock, a_side, a_size: INTEGER)
			-- The side's depth in logical units, as far as `Min_center' allows; no event.
		deferred
		end

	dock_size (a_dock, a_side: INTEGER): INTEGER
		deferred
		end

	dock_collapse (a_dock, a_side: INTEGER; a_on: BOOLEAN)
			-- Fold the side to a strip naming its panels, or open it at the size it had; no event.
		deferred
		end

	dock_show_panel (a_dock, an_index: INTEGER; a_on: BOOLEAN)
		deferred
		end

	dock_float (a_dock, an_index: INTEGER; a_on: BOOLEAN)
			-- 1r-b: panel `an_index' into a window of its own, or back to its side and place.
		deferred
		end

	dock_float_frame (a_dock, an_index, a_x, a_y, a_width, a_height: INTEGER)
			-- The panel's floating window frame, logical units relative to the dock's window.
		deferred
		end

	dock_float_frame_field (a_dock, an_index, a_field: INTEGER): INTEGER
			-- 1 x, 2 y, 3 width, 4 height of the panel's floating window frame.
		deferred
		end

	dock_set_auto_hide (a_dock, a_side: INTEGER; a_on: BOOLEAN)
		deferred
		end

	dock_maximize_center (a_dock: INTEGER; a_on: BOOLEAN)
		deferred
		end

	test_float_by_user (a_dock, an_index: INTEGER)
			-- As the user's double click on the panel's tab or title: 38 (index, 1).
		deferred
		end

	test_close_floating (a_dock, an_index: INTEGER)
			-- As the user closing the panel's floating window: it docks again, 38 (index, 0).
		deferred
		end

	test_drag_panel (a_dock, an_index, a_side, a_position: INTEGER)
			-- As the user dragging the panel to `a_position' on `a_side': 41.
		deferred
		end

	test_slide_out (a_dock, an_index: INTEGER): BOOLEAN
			-- As the user resting on the panel's name in its auto-hide strip; did it slide out?
		deferred
		end

	test_toggle_center (a_dock: INTEGER)
			-- As the user's double click on the center's frame: 40.
		deferred
		end

	dock_set_panel_fields (a_dock, an_index: INTEGER; a_short_title, a_description, a_tab_tooltip: POINTER)
			-- 1r-c: the panel's short title (its tab and strip name), accessible description and
			-- tab tooltip; empty strings: not set.
		deferred
		end

	dock_set_panel_pill (a_dock, an_index: INTEGER; a_code: POINTER)
			-- 1r-c: a reference pill on the panel's title bar and tab (empty: none).
		deferred
		end

	test_panel_tab_text (a_dock, an_index: INTEGER): POINTER
			-- What a tab for the panel shows, whatever the side's mode.
		deferred
		end

	test_panel_tab_tooltip (a_dock, an_index: INTEGER): POINTER
			-- A tab's tooltip for the panel, whatever the side's mode.
		deferred
		end

	splitter_set_collapsible (a_splitter, a_pane: INTEGER; a_on: BOOLEAN)
			-- 1r-c.
		deferred
		end

	splitter_collapse (a_splitter, a_pane: INTEGER; a_on: BOOLEAN)
			-- Collapse pane `a_pane' (its room to the other, the position remembered) or open it.
		deferred
		end

	splitter_is_collapsed (a_splitter, a_pane: INTEGER): BOOLEAN
		deferred
		end

	test_toggle_splitter_pane (a_splitter, a_pane: INTEGER)
			-- As the user pressing the divider's button for `a_pane': 42.
		deferred
		end

	list_extend_rich (an_id: INTEGER; a_title, a_subtitle, an_icon: POINTER; a_badge, a_flags: INTEGER)
			-- 1s: a rich row at the end; `a_flags': 1 checkable, 2 checked, 4 closable.
		deferred
		end

	list_set_checked (an_id, a_row: INTEGER; a_on: BOOLEAN)
		deferred
		end

	list_is_checked (an_id, a_row: INTEGER): BOOLEAN
			-- What row `a_row''s box shows.
		deferred
		end

	list_remove (an_id, a_row: INTEGER)
		deferred
		end

	list_reorder (an_id: INTEGER; an_order: POINTER)
			-- The old rows (from 1) in their new order, joined by ","; the selection stays with its row.
		deferred
		end

	list_set_filter (an_id: INTEGER; a_text: POINTER)
		deferred
		end

	list_shown_count (an_id: INTEGER): INTEGER
		deferred
		end

	table_set_column_editor (a_table, a_column, a_kind: INTEGER; a_choices: POINTER)
			-- 1s: kind 0 none, 1 text, 2 check, 3 choice; choices joined by U+001F.
		deferred
		end

	table_take_edit (a_table: INTEGER): POINTER
			-- The committed text of the edit event 45 told of.
		deferred
		end

	table_refuse_edit (a_table, a_row, a_column: INTEGER; a_message: POINTER)
			-- Put the cell's old text back and show `a_message' under it until the next edit in the table.
		deferred
		end

	table_set_filter (a_table: INTEGER; a_text: POINTER; a_columns_mask: INTEGER)
			-- Held rows: bit 0 is column 1; 0: all columns.
		deferred
		end

	table_set_shown_rows (a_table: INTEGER; a_rows: POINTER)
			-- Lazy rows: the model rows to show, joined by ","; empty: all.
		deferred
		end

	table_shown_count (a_table: INTEGER): INTEGER
		deferred
		end

	test_check_row (an_id, a_row: INTEGER)
			-- As the user pressing row `a_row''s check box: 43.
		deferred
		end

	test_close_row (an_id, a_row: INTEGER)
			-- As the user pressing row `a_row''s close button: the row goes, 44.
		deferred
		end

	test_edit_cell (a_table, a_row, a_column: INTEGER; a_text: POINTER)
			-- As the user editing the cell to `a_text' and committing (a check: "1" or "0";
			-- a choice: the option's text): 45.
		deferred
		end

	test_cancel_edit (a_table, a_row, a_column: INTEGER)
			-- As the user starting an edit and pressing Escape: nothing changes, no event.
		deferred
		end

	test_cell_text (a_table, a_row, a_column: INTEGER): POINTER
			-- What the cell shows (model row).
		deferred
		end

	test_cell_note (a_table: INTEGER): POINTER
			-- The refusal note showing in the table; empty: none.
		deferred
		end

	grid_view: INTEGER
			-- 1v-a: items in a flowing grid of cells (120 by 120 until set).
		deferred
		end

	grid_view_extend (an_id: INTEGER; a_title, a_picture, an_icon: POINTER)
			-- An item at the end; `a_picture' a file path and `an_icon' a GUI_ICON name, empty for none.
		deferred
		end

	grid_view_set_subtitle (an_id, i: INTEGER; a_text: POINTER)
		deferred
		end

	grid_view_remove (an_id, i: INTEGER)
		deferred
		end

	grid_view_wipe_out (an_id: INTEGER)
		deferred
		end

	grid_view_set_item_size (an_id, a_width, a_height: INTEGER)
		deferred
		end

	grid_view_set_spacing (an_id, a_spacing: INTEGER)
		deferred
		end

	grid_view_set_multiple (an_id: INTEGER; a_on: BOOLEAN)
		deferred
		end

	grid_view_select (an_id, i: INTEGER; an_extend: BOOLEAN)
			-- Quiet; 0 clears.
		deferred
		end

	grid_view_selected_count (an_id: INTEGER): INTEGER
		deferred
		end

	grid_view_selected_at (an_id, k: INTEGER): INTEGER
			-- The `k'th selected item, in order.
		deferred
		end

	grid_view_scroll_to (an_id, i: INTEGER)
		deferred
		end

	grid_view_set_filter (an_id: INTEGER; a_text: POINTER)
		deferred
		end

	grid_view_shown_count (an_id: INTEGER): INTEGER
		deferred
		end

	test_activate_item (an_id, i: INTEGER)
			-- As a double click on item `i': 51.
		deferred
		end

	test_item_picture_ready (an_id, i: INTEGER): BOOLEAN
			-- Has item `i''s picture been loaded and shown?
		deferred
		end

	path_control_set_chevrons (an_id: INTEGER; a_on: BOOLEAN)
			-- 1p-b: each separator a clickable chevron (53, a = the part before it), with one
			-- after the last part too; a click on the empty space after the last part sends 54.
		deferred
		end

	path_control_set_root_icon (an_id: INTEGER; a_name: POINTER)
		deferred
		end

	widget_focus (an_id: INTEGER)
			-- 1p-b: the keyboard focus to widget `an_id', from code.
		deferred
		end

	test_press_chevron (an_id, a_part: INTEGER)
		deferred
		end

	test_press_path_space (an_id: INTEGER)
		deferred
		end

	test_field_escape (an_id: INTEGER)
			-- As Escape in a text field: 55.
		deferred
		end

	dialog (a_title: POINTER): INTEGER
			-- 1u: a modal dialog, not shown.
		deferred
		end

	dialog_set_content (a_dialog, a_widget: INTEGER)
		deferred
		end

	dialog_add_button (a_dialog: INTEGER; a_text: POINTER; a_role: INTEGER): INTEGER
			-- Roles: 1 default, 2 cancel, 3 destructive, 4 other; the platform orders them.
		deferred
		end

	dialog_set_button_enabled (a_dialog, n: INTEGER; a_on: BOOLEAN)
		deferred
		end

	dialog_present (a_dialog, a_parent_window: INTEGER; an_app_modal: BOOLEAN)
			-- Show it, never blocking (`a_parent_window' 0: none). The user's button, Return,
			-- Escape or close box sends 48 (a = the button).
		deferred
		end

	dialog_pump (a_dialog: INTEGER)
			-- One turn of what keeps an app-modal dialog modal (macOS `runModalSession:'); else nothing.
		deferred
		end

	dialog_close (a_dialog: INTEGER)
		deferred
		end

	dialog_is_shown (a_dialog: INTEGER): BOOLEAN
		deferred
		end

	help_show_tip (a_widget: INTEGER; a_text: POINTER)
			-- 1u: the default help, a popover at the widget.
		deferred
		end

	test_press_dialog_button (a_dialog, n: INTEGER)
			-- As the user's click on button `n': 48.
		deferred
		end

	test_dialog_key (a_dialog, a_key: INTEGER)
			-- 1 Return, 2 Escape, 3 the close box: 48 with the button it presses, or nothing.
		deferred
		end

	test_press_dialog_button_later (a_dialog, n, a_ms: INTEGER)
		deferred
		end

	test_dialog_button_order (a_dialog: INTEGER): POINTER
			-- The buttons' numbers in the order shown, leading to trailing, joined by ",".
		deferred
		end

	test_press_help (a_window: INTEGER)
			-- As F1 in the window: 49 with the focused widget.
		deferred
		end

	test_help_tip_shown: POINTER
			-- The default help popover's text; empty: none.
		deferred
		end

	tabs_set_position (a_tabs, a_position: INTEGER)
			-- 1t: 0 none, 1 top, 2 bottom, 3 left, 4 right.
		deferred
		end

	sidebar: INTEGER
			-- 1t: pages one at a time beside a list of their titles.
		deferred
		end

	sidebar_extend (a_sidebar, a_page: INTEGER; a_title: POINTER)
			-- The first page added is shown.
		deferred
		end

	sidebar_add_heading (a_sidebar: INTEGER; a_text: POINTER)
			-- A group heading before the next page: not selectable, not counted.
		deferred
		end

	sidebar_set_icon (a_sidebar, i: INTEGER; a_name: POINTER)
		deferred
		end

	sidebar_set_badge (a_sidebar, i: INTEGER; a_text: POINTER)
		deferred
		end

	sidebar_select (a_sidebar, i: INTEGER)
			-- Quiet.
		deferred
		end

	sidebar_selected (a_sidebar: INTEGER): INTEGER
		deferred
		end

	sidebar_set_collapsible (a_sidebar: INTEGER; a_on: BOOLEAN)
		deferred
		end

	sidebar_set_collapsed (a_sidebar: INTEGER; a_on: BOOLEAN)
			-- Quiet: icons only, titles as tooltips.
		deferred
		end

	sidebar_is_collapsed (a_sidebar: INTEGER): BOOLEAN
		deferred
		end

	path_control_set_parts (an_id: INTEGER; a_parts: POINTER)
			-- 1t: any parts, joined by U+001F.
		deferred
		end

	test_toggle_sidebar (a_sidebar: INTEGER)
			-- As the user pressing the collapse button: 47.
		deferred
		end

	test_page_shown (an_id: INTEGER): INTEGER
			-- The page the user sees in tabs or a sidebar, from the native control.
		deferred
		end

	test_locate_row (an_id, a_row: INTEGER): INTEGER
			-- The row a drop's locating finds at the middle of row `a_row''s place on screen: a
			-- list's row, a tree's node number, a token field's token; 0 when it finds none.
		deferred
		end

	test_drag_dock_edge (a_dock, a_side, a_size: INTEGER)
			-- As the user dragging the side's edge to `a_size': 35.
		deferred
		end

	test_press_dock_strip (a_dock, an_index: INTEGER)
			-- As the user pressing panel `an_index''s name in its collapsed side's strip: the side
			-- opens showing it (36 with b = 0, and 37 when the side is tabbed).
		deferred
		end

	test_click_dock_tab (a_dock, an_index: INTEGER)
			-- As the user clicking panel `an_index''s tab: 37.
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

	tree_move (a_tree, a_node, a_parent, a_position: INTEGER)
			-- 1q-c: move `a_node' (with its subtree) under `a_parent' (0: the top level) as child
			-- number `a_position' there (1-based, counted after taking it out).
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

	dropdown: INTEGER
			-- An empty pick-one dropdown.
		deferred
		ensure
			named: Result > 0
		end

	dropdown_extend (an_id: INTEGER; a_text: POINTER)
			-- Add a row; the first row added becomes the selection, without an event.
		deferred
		end

	dropdown_wipe_out (an_id: INTEGER)
		deferred
		end

	dropdown_select (an_id, a_row: INTEGER)
			-- Select `a_row' (1-based), without an event.
		require
			positive: a_row >= 1
		deferred
		end

	dropdown_selected (an_id: INTEGER): INTEGER
			-- The selected row, or 0 when empty.
		deferred
		end

	spin_box (a_min, a_max: INTEGER): INTEGER
			-- A spin box at `a_min', stepping by 1.
		require
			ordered: a_min <= a_max
		deferred
		ensure
			named: Result > 0
		end

	spin_box_set_value (an_id, a_value: INTEGER)
			-- Without an event.
		deferred
		end

	spin_box_value (an_id: INTEGER): INTEGER
		deferred
		end

	spin_box_set_step (an_id, a_step: INTEGER)
		require
			positive: a_step > 0
		deferred
		end

	progress_bar: INTEGER
			-- A progress bar at 0.
		deferred
		ensure
			named: Result > 0
		end

	progress_bar_set (an_id, a_percent: INTEGER)
		require
			percent: 0 <= a_percent and a_percent <= 100
		deferred
		end

	progress_bar_value (an_id: INTEGER): INTEGER
		deferred
		end

	toolbar: INTEGER
			-- An empty toolbar.
		deferred
		ensure
			named: Result > 0
		end

	toolbar_extend (a_toolbar, a_button: INTEGER)
		deferred
		end

	toolbar_add_separator (a_toolbar: INTEGER)
		deferred
		end

	status_bar: INTEGER
			-- An empty status bar.
		deferred
		ensure
			named: Result > 0
		end

	status_bar_set_text (an_id: INTEGER; a_text: POINTER)
		deferred
		end

	status_bar_text (an_id: INTEGER): POINTER
		deferred
		end

	radio_group (a_vertical: BOOLEAN): INTEGER
			-- An empty radio group, one above the next or in a row.
		deferred
		end

	radio_group_extend (an_id: INTEGER; a_text: POINTER)
			-- Add a radio; the first is chosen, without an event.
		deferred
		end

	radio_group_select (an_id, i: INTEGER)
			-- Choose radio `i' (1-based), without an event.
		deferred
		end

	radio_group_selected (an_id: INTEGER): INTEGER
			-- The chosen radio, or 0 when there are none.
		deferred
		end

	segmented: INTEGER
			-- An empty segmented control.
		deferred
		end

	segmented_extend (an_id: INTEGER; a_text: POINTER)
			-- Add a segment; the first is selected, without an event.
		deferred
		end

	segmented_select (an_id, i: INTEGER)
			-- Select segment `i', without an event.
		deferred
		end

	segmented_selected (an_id: INTEGER): INTEGER
		deferred
		end

	slider (a_min, a_max: INTEGER; a_vertical: BOOLEAN): INTEGER
			-- A slider at `a_min' that reports every move (2, a = value).
		deferred
		end

	slider_set_value (an_id, a_value: INTEGER)
			-- Without an event.
		deferred
		end

	slider_value (an_id: INTEGER): INTEGER
		deferred
		end

	slider_set_step (an_id, a_step: INTEGER)
			-- The knob stops every `a_step'.
		deferred
		end

	switch: INTEGER
			-- A switch, off; a flip sends toggled (12).
		deferred
		end

	switch_set (an_id: INTEGER; a_on: BOOLEAN)
			-- Without an event.
		deferred
		end

	switch_is_on (an_id: INTEGER): BOOLEAN
		deferred
		end

	date_picker: INTEGER
			-- A date picker showing today; value year * 10000 + month * 100 + day.
		deferred
		end

	time_picker: INTEGER
			-- A time picker showing now; value hour * 60 + minute.
		deferred
		end

	date_picker_set (an_id, a_value: INTEGER)
			-- A date or a time picker's value, without an event.
		deferred
		end

	date_picker_value (an_id: INTEGER): INTEGER
			-- A date or a time picker's value.
		deferred
		end

	color_chooser: INTEGER
			-- A color chooser holding black (0xRRGGBB, sRGB).
		deferred
		end

	color_chooser_set (an_id, a_rgb: INTEGER)
			-- Without an event.
		deferred
		end

	color_chooser_value (an_id: INTEGER): INTEGER
		deferred
		end

	scroll_area: INTEGER
			-- An empty scroll area.
		deferred
		end

	scroll_area_set_content (an_id, a_child: INTEGER)
		deferred
		end

	scroll_area_scroll_to (an_id, a_x, a_y: INTEGER)
		deferred
		end

	image: INTEGER
			-- An empty image.
		deferred
		end

	image_set_file (an_id: INTEGER; a_path: POINTER): BOOLEAN
			-- Show the picture in the file; False when it is not one.
		deferred
		end

	image_set_bytes (an_id: INTEGER; a_bytes: POINTER; a_count: INTEGER): BOOLEAN
			-- Show the PNG picture in the bytes; False when they are not one.
		deferred
		end

	separator (a_vertical: BOOLEAN): INTEGER
		deferred
		end

	group_box (a_title: POINTER): INTEGER
			-- An empty titled frame.
		deferred
		end

	group_box_set_title (an_id: INTEGER; a_title: POINTER)
		deferred
		end

	group_box_set_content (an_id, a_child: INTEGER)
		deferred
		end

	expander (a_title: POINTER): INTEGER
			-- An empty expander, collapsed; a user's toggle sends toggled (12, a = 1 expanded).
		deferred
		end

	expander_set_title (an_id: INTEGER; a_title: POINTER)
		deferred
		end

	expander_set_content (an_id, a_child: INTEGER)
		deferred
		end

	expander_set_expanded (an_id: INTEGER; a_on: BOOLEAN)
			-- Without an event.
		deferred
		end

	expander_is_expanded (an_id: INTEGER): BOOLEAN
		deferred
		end

	combo_box: INTEGER
			-- An empty editable combo box; a committed change sends text changed (2).
		deferred
		end

	combo_box_extend (an_id: INTEGER; a_text: POINTER)
		deferred
		end

	combo_box_wipe_out (an_id: INTEGER)
		deferred
		end

	combo_box_set_text (an_id: INTEGER; a_text: POINTER)
			-- Without an event.
		deferred
		end

	combo_box_text (an_id: INTEGER): POINTER
		deferred
		end

	tree_table (a_titles: POINTER): INTEGER
			-- An empty tree table; column titles joined by 0x1F.
		deferred
		end

	tree_table_set_cell (an_id, a_node, a_column: INTEGER; a_text: POINTER)
			-- Node `a_node''s text in column `a_column' (1: its node text).
		deferred
		end

	calendar: INTEGER
			-- A month grid showing today; a date picker's value and events.
		deferred
		end

	menu_button (a_text: POINTER; a_split: BOOLEAN): INTEGER
			-- A button that opens a menu; split: its main part sends click (1).
		deferred
		end

	menu_button_set_menu (an_id: INTEGER; a_menu: POINTER)
			-- The menu (a GUI_MENU's handle) the button opens.
		deferred
		end

	level_bar (a_min, a_max: INTEGER): INTEGER
			-- A level bar at `a_min'.
		deferred
		end

	level_bar_set (an_id, a_value: INTEGER)
		deferred
		end

	level_bar_value (an_id: INTEGER): INTEGER
		deferred
		end

	level_bar_set_warning (an_id, a_value: INTEGER)
		deferred
		end

	level_bar_set_critical (an_id, a_value: INTEGER)
		deferred
		end

	popover: INTEGER
			-- An empty popover, hidden; a user's dismissal sends closed (17).
		deferred
		end

	popover_set_content (an_id, a_child: INTEGER)
		deferred
		end

	popover_show_at (an_id, an_anchor: INTEGER)
		deferred
		end

	popover_hide (an_id: INTEGER)
			-- Without an event.
		deferred
		end

	popover_is_shown (an_id: INTEGER): BOOLEAN
		deferred
		end

	search_field: INTEGER
			-- A search field: a field's text features; Return sends activate (3).
		deferred
		end

	token_field: INTEGER
			-- An empty token field; a user's change sends text changed (2).
		deferred
		end

	token_field_extend (an_id: INTEGER; a_text: POINTER)
			-- Without an event.
		deferred
		end

	token_field_remove (an_id, i: INTEGER)
			-- Without an event.
		deferred
		end

	token_field_wipe_out (an_id: INTEGER)
			-- Without an event.
		deferred
		end

	token_field_count (an_id: INTEGER): INTEGER
		deferred
		end

	token_field_item (an_id, i: INTEGER): POINTER
		deferred
		end

	path_control: INTEGER
			-- An empty path control; a click on a part sends selection (4, a = part).
		deferred
		end

	path_control_set (an_id: INTEGER; a_path: POINTER)
		deferred
		end

	path_control_count (an_id: INTEGER): INTEGER
		deferred
		end

	path_control_part (an_id, i: INTEGER): POINTER
		deferred
		end

	rating (a_maximum: INTEGER): INTEGER
			-- No stars of `a_maximum'; a user's click sends text changed (2, a = stars).
		deferred
		end

	rating_set (an_id, a_value: INTEGER)
			-- Without an event.
		deferred
		end

	rating_value (an_id: INTEGER): INTEGER
		deferred
		end

	rich_text_area: INTEGER
			-- An empty rich text area: a text area's features, plus formatting.
		deferred
		end

	rich_text_set_trait (an_id, a_start, an_end, a_trait: INTEGER; a_on: BOOLEAN)
			-- Bold (1), italic (2) or underline (3) over `a_start' .. `an_end' (1-based characters, inclusive).
		deferred
		end

	rich_text_set_color (an_id, a_start, an_end, a_rgb: INTEGER)
		deferred
		end

	rich_text_set_size (an_id, a_start, an_end: INTEGER; a_points: REAL_64)
		deferred
		end

	rich_text_trait_at (an_id, i, a_trait: INTEGER): BOOLEAN
		deferred
		end

	rich_text_color_at (an_id, i: INTEGER): INTEGER
			-- 0xRRGGBB, or -1 for the theme's text color.
		deferred
		end

	rich_text_size_at (an_id, i: INTEGER): REAL_64
		deferred
		end

	rich_text_selection_start (an_id: INTEGER): INTEGER
		deferred
		end

	rich_text_selection_end (an_id: INTEGER): INTEGER
			-- `rich_text_selection_start' - 1 when nothing is selected.
		deferred
		end

	rich_text_select (an_id, a_start, an_end: INTEGER)
		deferred
		end

	drawn (a_width, a_height: INTEGER): INTEGER
			-- A drawn view (1i) of the preferred logical size: a canvas with the whole input a hosted simple_widgets window needs (events 18 to 23).
		deferred
		end

	drawn_present (an_id: INTEGER; a_surface: POINTER; a_width, a_height: INTEGER)
			-- Show the top-left `a_width' by `a_height' device pixels of the Cairo image surface `a_surface' (copied).
		deferred
		end

	drawn_set_cursor (an_id, a_kind: INTEGER)
			-- The pointer shape over the view: 0 arrow, 1 I-beam, 2 hand, 3 size west-east, 4 size north-south, 5 cross, 6 wait.
		deferred
		end

	drawn_set_ticks (an_id, a_tick_ms, a_fast_ms: INTEGER)
			-- Event 23 with a = 0 every `a_tick_ms', and with a = 1 every `a_fast_ms' (0: off).
		deferred
		end

	drawn_arm_dwell (an_id, a_ms, a_serial: INTEGER)
			-- Event 23 with a = 2 and b = `a_serial', once, `a_ms' from now.
		deferred
		end

	drawn_set_description (an_id: INTEGER; a_text: POINTER)
			-- The hosted window's accessibility tree, for `describe_accessibility' under the view's group.
		deferred
		end

	password_field: INTEGER
			-- 1p: an empty password field: a field's text features and events; toggled (12, a = 1 revealed) for its eye.
		deferred
		end

	password_set_revealed (an_id: INTEGER; a_on: BOOLEAN)
			-- Without an event.
		deferred
		end

	password_is_revealed (an_id: INTEGER): BOOLEAN
		deferred
		end

	caps_lock_on: BOOLEAN
		deferred
		end

	field_set_error (an_id: INTEGER; a_message: POINTER)
			-- The platform's error look on field `an_id', with `a_message' under it; empty clears both.
		deferred
		end

	field_set_suggestions (an_id: INTEGER; a_joined: POINTER)
			-- Show these suggestions (joined by 0x1F; empty: none) for the field's text, as the user types.
		deferred
		end

	dropdown_add_header (an_id: INTEGER; a_text: POINTER)
			-- A group header; not a choice.
		deferred
		end

	dropdown_add_separator (an_id: INTEGER)
			-- A separator; not a choice.
		deferred
		end

	date_time_picker (a_kind: INTEGER): INTEGER
			-- 2: a date and time picker (event 2, a = date, b = h*60+m); 3: a month picker (event 2, a = y*100+m).
		deferred
		end

	date_time_set (an_id, a_date, a_time: INTEGER)
			-- Date y*10000+m*100+d and time h*60+m; without an event.
		deferred
		end

	date_time_date (an_id: INTEGER): INTEGER
		deferred
		end

	date_time_time (an_id: INTEGER): INTEGER
		deferred
		end

	range_slider (a_min, a_max: INTEGER): INTEGER
			-- A two-thumb slider, the whole range selected; a change sends 2 (a = low, b = high).
		deferred
		end

	range_slider_set (an_id, a_low, a_high: INTEGER)
			-- Without an event.
		deferred
		end

	range_slider_low (an_id: INTEGER): INTEGER
		deferred
		end

	range_slider_high (an_id: INTEGER): INTEGER
		deferred
		end

	range_slider_set_step (an_id, a_step: INTEGER)
		deferred
		end

	list_set_multiple (an_id: INTEGER; a_on: BOOLEAN)
			-- 1p: several rows at once.
		deferred
		end

	list_selected_count (an_id: INTEGER): INTEGER
		deferred
		end

	list_selected_at (an_id, i: INTEGER): INTEGER
			-- The `i'th selected row, in order.
		deferred
		end

	set_tooltip (an_id: INTEGER; a_text: POINTER)
			-- Short help on hover; empty removes it.
		deferred
		end

	timer_start (a_timer_id, a_ms: INTEGER; a_repeat: BOOLEAN)
			-- 1m: event 24 (id 0, a = `a_timer_id') every `a_ms' milliseconds, or once.
		deferred
		end

	timer_stop (a_timer_id: INTEGER)
			-- No more events from timer `a_timer_id'.
		deferred
		end

	clipboard_text: POINTER
			-- The clipboard's text now; empty when it holds none.
		deferred
		end

	clipboard_set_text (a_text: POINTER)
		deferred
		end

	window_add_shortcut (a_window: INTEGER; a_shortcut: POINTER; a_shortcut_id: INTEGER)
			-- Event 25 (id = `a_window', a = `a_shortcut_id') when the neutral `a_shortcut' is
			-- pressed while `a_window' is active, wherever the focus is.
		deferred
		end

	window_set_fullscreen (a_window: INTEGER; a_on: BOOLEAN)
		deferred
		end

	window_is_fullscreen (a_window: INTEGER): BOOLEAN
		deferred
		end

	follow_system_appearance
			-- Undo `set_dark': follow the system's light or dark again (event 10 if it changes).
		deferred
		end

	list_scroll_to_row (an_id, a_row: INTEGER)
		deferred
		end

	test_press_shortcut (a_window: INTEGER; a_shortcut: POINTER)
			-- As the user pressing `a_shortcut' in `a_window' (event 25 when it is one of its own).
		deferred
		end

	spinner: INTEGER
			-- 1o: a busy wheel, not turning.
		deferred
		end

	spinner_set (an_id: INTEGER; a_on: BOOLEAN)
		deferred
		end

	info_bar (a_kind: INTEGER; a_message: POINTER): INTEGER
			-- An inline banner: 1 info, 2 success, 3 warning, 4 error. Event 26 (a = action
			-- number, 0 for close).
		deferred
		end

	info_bar_set (an_id, a_kind: INTEGER; a_message: POINTER)
		deferred
		end

	info_bar_add_action (an_id: INTEGER; a_text: POINTER; a_number: INTEGER)
		deferred
		end

	info_bar_set_closable (an_id: INTEGER; a_on: BOOLEAN)
		deferred
		end

	window_show_toast (a_window: INTEGER; a_message, an_action_text: POINTER; a_toast_id: INTEGER)
			-- A toast at the bottom of `a_window'; with action text, a button sending event 27
			-- (id = window, a = `a_toast_id').
		deferred
		end

	notify (a_title, a_body: POINTER; a_notification_id: INTEGER)
			-- A desktop notification; when `a_notification_id' > 0, a click sends event 28 (a = it).
		deferred
		end

	test_info_bar_press (an_id, a_number: INTEGER)
			-- As the user pressing action `a_number' (0: close).
		deferred
		end

	test_toast_shown (a_window: INTEGER): POINTER
			-- The message of the toast showing in `a_window' now; "" for none.
		deferred
		end

	test_toast_press (a_window: INTEGER)
			-- As the user pressing the action of the toast showing in `a_window'.
		deferred
		end

	button_set_icon (an_id: INTEGER; a_name: POINTER)
			-- 1n: icon `a_name' (GUI_ICON's vocabulary) before the button's text; "" removes it.
		deferred
		end

	button_set_style (an_id, a_style: INTEGER)
			-- 0 normal, 1 suggested, 2 destructive, 3 flat, 4 pill.
		deferred
		end

	button_set_busy (an_id: INTEGER; a_on: BOOLEAN)
			-- A spinner in place of the icon (the shared class disables the button).
		deferred
		end

	menu_set_item_icon (an_item_id: INTEGER; a_name: POINTER)
		deferred
		end

	tabs_set_page_icon (a_tabs, a_page: INTEGER; a_name: POINTER)
		deferred
		end

	tabs_set_page_badge (a_tabs, a_page: INTEGER; a_text: POINTER)
			-- "" removes it.
		deferred
		end

	widget_set_badge (an_id: INTEGER; a_text: POINTER; a_kind: INTEGER)
			-- 0 none, 1 the text in a small red bubble, 2 a dot; at the trailing top corner,
			-- above everything in the window, always shown.
		deferred
		end

	test_button_icon (an_id: INTEGER): POINTER
			-- The icon name the button shows now; "" for none (tests).
		deferred
		end

	test_badge_shown (an_id: INTEGER): POINTER
			-- The badge widget `an_id' shows now: its text, a bullet for a dot, "" for none (tests).
		deferred
		end

	widget_set_pick (an_id, a_mode: INTEGER; a_is_source, a_by_row: BOOLEAN)
			-- 1q: whether a pick starts on `an_id' and how (1 drag, 2 click, 3 menu). A start pushes
			-- event 30 (id = source, a = the row or node under the pointer when `a_by_row', else 0).
		deferred
		end

	widget_set_drop_target (an_id: INTEGER; an_internal, a_files, a_text: BOOLEAN)
			-- Whether `an_id' takes pebbles, files from other programs, text from other programs.
		deferred
		end

	pick_targets (a_source: INTEGER; a_ids: POINTER; a_count: INTEGER; a_labels: POINTER)
			-- The answer to event 30: the `a_count' widgets (INTEGER_32s at `a_ids') that take the
			-- pebble, and their labels (newline-separated, for the menu mode). Only these light
			-- as accepting; a drop on one pushes 31 (id = target, a = row, 0 for none), a cancel 32.
		deferred
		end

	pick_cancel
			-- The answer to event 30 when the source has no pebble: end the gesture, no event.
		deferred
		end

	widget_set_drag_out (an_id: INTEGER; a_text, a_paths: POINTER)
			-- 1q-c: a drag out of `an_id' carries `a_text' and the newline-separated `a_paths'
			-- (both empty: no drag out). Copy both; they are freed after the call.
		deferred
		end

	test_drag_out (an_id: INTEGER): POINTER
			-- What a drag out of `an_id' would carry now: the text, a line feed, then the paths
			-- one per line; empty when it carries nothing.
		deferred
		end

	test_drag_out_ended (an_id, a_how: INTEGER)
			-- As a drag out of `an_id' ending in another program with `a_how' (event 34);
			-- nothing unless `an_id' has something to drag out.
		deferred
		end

	take_dropped_paths (an_id: INTEGER): POINTER
			-- 1q-b: the files dropped on `an_id' (event 33, a = 1), newline-separated; taken once.
		deferred
		end

	take_dropped_text (an_id: INTEGER): POINTER
			-- The text dropped on `an_id' (event 33, a = 2); taken once.
		deferred
		end

	test_drop_files (an_id: INTEGER; a_paths: POINTER)
			-- As another program dropping these files (newline-separated) on `an_id': nothing
			-- happens unless it takes files.
		deferred
		end

	test_drop_text (an_id: INTEGER; a_text: POINTER)
			-- As another program dropping text on `an_id': nothing unless it takes text.
		deferred
		end

	test_pick (a_source, a_row: INTEGER)
			-- As the user starting a pick on `a_source' (row `a_row', 0 for the widget).
		deferred
		end

	test_drop (a_target, a_row: INTEGER)
			-- As the user dropping on `a_target' (row `a_row'), or choosing it in the menu mode.
		deferred
		end

	test_cancel_pick
		deferred
		end

	test_is_accepting (a_target: INTEGER): BOOLEAN
			-- Does `a_target' light as taking the pebble in flight now?
		deferred
		end

	pill_set (an_id: INTEGER; a_code, a_tip: POINTER; a_corner: INTEGER)
			-- 1l: widget `an_id' wears the reference pill `a_code' at `a_corner' (1 top-left,
			-- 2 top-right, 3 bottom-left, 4 bottom-right; leading and trailing mirror right to
			-- left), reading `a_tip' under the pointer; replaces any pill it had. Drawn while
			-- `pills_show' is on, above everything in its window, and placed again as layout
			-- moves its widget. A widget not in a window yet gets its pill when it is.
		deferred
		end

	pill_clear (an_id: INTEGER)
			-- Widget `an_id' wears no pill.
		deferred
		end

	pills_show (a_shown: BOOLEAN)
			-- Draw every pill, or none.
		deferred
		end

	pill_tip_shown (an_id: INTEGER): POINTER
			-- The tip of the pill widget `an_id' shows now, as a person hovering it would read
			-- it: empty when it has none, pills are hidden, or it is not in a shown window (tests).
		deferred
		end

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

	save_file_named (a_window: INTEGER; a_title, an_extensions, a_name: POINTER): POINTER
			-- Chosen path (UTF-8), offered `a_name' first, or default_pointer when canceled.
		deferred
		end

	choose_folder (a_window: INTEGER; a_title: POINTER): POINTER
			-- Chosen folder (UTF-8), or default_pointer when canceled.
		deferred
		end

	ask (a_window: INTEGER; a_title, a_text: POINTER): INTEGER
			-- 1 yes, 2 no, 0 cancel.
		deferred
		end

	ask_text (a_window: INTEGER; a_title, a_prompt, an_initial: POINTER): POINTER
			-- One line of text (UTF-8), or default_pointer when cancelled.
		deferred
		end

	confirm_with_check (a_window: INTEGER; a_title, a_text, a_check: POINTER): INTEGER
			-- Bit 0: OK; bit 1: the box was checked.
		deferred
		end

	choose_font (a_window: INTEGER; a_title, a_family: POINTER; a_points: REAL_64; a_bold, an_italic: BOOLEAN): POINTER
			-- "family<0x1F>points<0x1F>bold<0x1F>italic" (bold and italic 0 or 1), or default_pointer when cancelled.
		deferred
		end

	show_about (a_name, a_version, a_copyright, a_comments: POINTER)
			-- The platform's About window.
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

feature -- Styles (1w)

	widget_set_style (an_id: INTEGER; a_spec: POINTER)
			-- Show a resolved style on a widget: `key=value' pairs separated by 0x1F. The keys:
			-- `fg', `bg', `placeholder', `selection', `border_color', `shadow_color' (six hex
			-- digits); `font' (a family, or monospace, serif, sans-serif, system); `size' (points);
			-- `weight' (100 to 900); `italic' (0 or 1); `pad' (top,end,bottom,start); `border' (its
			-- width); `radius'; `shadow' (x,y,blur,alpha percent); `scroll' (0 the system's choice,
			-- 1 overlay, 2 always, 3 hidden). A key the widget cannot show is ignored; an empty
			-- spec takes the widget back to its native look. Shared code has already picked the
			-- light or dark colors and left the colors out under the system's contrast setting.
		deferred
		end

	widget_style_supported (an_id: INTEGER; a_property: POINTER): BOOLEAN
			-- Can the widget show the property with this key (`fg', `bg', `placeholder',
			-- `selection', `font', `size', `weight', `italic', `pad', `border', `radius', `shadow',
			-- `scroll')?
		deferred
		end

	set_theme_color (a_role, a_rgb: INTEGER)
			-- The program's own color for a `system_color' role, where the toolkit lets a
			-- program change the theme (role 4, the accent: on the controls that show one);
			-- -1 goes back to the system's.
		require
			known: a_role >= 1 and a_role <= 6
			rgb_or_reset: a_rgb >= -1 and a_rgb <= 0xFFFFFF
		deferred
		end

	font_load (a_path: POINTER): POINTER
			-- Load a font file for this process only. The family names it adds, separated by
			-- 0x1F; empty when it cannot be loaded.
		deferred
		end

	font_family_available (a_name: POINTER): BOOLEAN
		deferred
		end

	is_high_contrast: BOOLEAN
			-- Is the system's contrast setting on (or forced by `test_set_high_contrast')?
		deferred
		end

	test_style_value (an_id: INTEGER; a_key: POINTER): POINTER
			-- Tests only: what the native control shows now for a key of `widget_set_style',
			-- read back from the control and written as the spec writes it (colors as six
			-- lowercase hex digits). Empty when the control does not show the key.
		deferred
		end

	test_set_high_contrast (a_on: BOOLEAN)
			-- Tests only: act as if the system's contrast setting were on (or off again).
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

	test_set_number (an_id, a_value: INTEGER)
			-- Set a spin box's value as a user would (emits text changed).
		deferred
		end

	test_slide (an_id, a_value: INTEGER)
			-- Move a slider's knob as a user would (emits text changed).
		deferred
		end

	test_set_date (an_id, a_value: INTEGER)
			-- Enter a date or a time picker's value as a user would (emits text changed).
		deferred
		end

	test_set_color (an_id, a_rgb: INTEGER)
			-- Choose a color as a user would (emits text changed).
		deferred
		end

	test_type_combo (an_id: INTEGER; a_text: POINTER)
			-- Type into a combo box and press Return, as a user would (emits text changed on a change).
		deferred
		end

	test_toggle_expander (an_id: INTEGER)
			-- Click an expander's title as a user would (emits toggled).
		deferred
		end

	test_auto_cancel_dialogs (a_ms: INTEGER)
			-- Cancel each dialog `a_ms' after it opens (0: never), so tests run unattended.
		deferred
		end

	test_dismiss_popover (an_id: INTEGER)
			-- Dismiss a popover as a user would, with Escape (emits closed).
		deferred
		end

	test_type_tokens (an_id: INTEGER; a_text: POINTER)
			-- Type tokens separated by commas and press Return, as a user would (emits text changed).
		deferred
		end

	test_rate (an_id, a_value: INTEGER)
			-- Click star `a_value' as a user would (emits text changed on a change).
		deferred
		end

	test_drawn_event (an_id, a_type, a_a, a_b, a_c: INTEGER)
			-- Put a drawn view's event (18 to 23) on the queue, as the view would.
		deferred
		end

	test_toggle_reveal (an_id: INTEGER)
			-- Click a password field's eye, as a user (emits 12).
		deferred
		end

	test_pick_suggestion (an_id, i: INTEGER)
			-- Choose suggestion `i', as a user (fills the field; emits 2).
		deferred
		end

	test_end_editing (an_id: INTEGER)
			-- Leave a field, as a user tabbing away (emits 29).
		deferred
		end

	test_set_date_time (an_id, a_date, a_time: INTEGER)
			-- Enter a date and time, or a month, as a user (emits 2).
		deferred
		end

	test_slide_range (an_id, a_low, a_high: INTEGER)
			-- Drag the thumbs, as a user (emits 2 for each change).
		deferred
		end

	test_extend_list_selection (an_id, a_row: INTEGER)
			-- Add a row to a list's selection, as a Command-click (emits 4).
		deferred
		end

	field_error_shown (an_id: INTEGER): POINTER
			-- For tests: the error message shown under field `an_id' now; empty when none.
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
