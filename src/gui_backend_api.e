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
		| 10 appearance (a = 1 dark) | 11 wake | 12 toggled (a = 1 checked).
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
			-- 0 fill, 1 start, 2 centre, 3 end.
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

feature -- Dialogs

	open_file (a_window: INTEGER; a_title: POINTER; a_save: BOOLEAN; an_extensions: POINTER): POINTER
			-- Chosen path (UTF-8), or default_pointer when cancelled. `an_extensions' is "txt;md" or "".
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
			-- The theme's colour as 0xRRGGBB: 1 window background, 2 text, 3 secondary text,
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

	test_type (an_id: INTEGER; a_text: POINTER)
			-- Set a field's text AS A USER WOULD (emits text changed).
		deferred
		end

	test_choose (an_id, a_row: INTEGER)
			-- Select a row AS A USER WOULD (emits selection).
		deferred
		end

	test_menu (an_item_id: INTEGER)
		deferred
		end

	test_request_close (a_window: INTEGER)
			-- Ask to close window `a_window' as the user would (emits close requested).
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
