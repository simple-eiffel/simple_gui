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
		(a = node, b = 1 open) | 16 rows wanted (a = first, b = last) | 17 closed (a popover the user dismissed).
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

	set_tooltip (an_id: INTEGER; a_text: POINTER)
			-- Short help on hover; empty removes it.
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
