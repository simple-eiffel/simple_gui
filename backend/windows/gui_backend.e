note
	description: "[
		simple_gui's Windows backend: the API over simple_widgets (drawn, the Cairo look) on
		simple_shell. Widgets live in an id table; their agents push simple_gui's events onto a
		queue that `next' drains, and programmatic changes stay silent (simple_widgets' setters
		already are). Windows are GUI_SW_WINDOWs: one open at a time in this first stage, opened
		step by step (simple_shell's shell_open_window and shell_turn, W1).

		Stage 1 covers the loop, windows, stacks, grids, labels, buttons, fields, check boxes,
		text areas, lists, the canvas, menus, dialogs, appearance, accessibility and the test
		doors. The splitter, tabs, table, tree and context menus come in stage 2; until then
		they fail loudly ("not yet on Windows") rather than quietly doing nothing.
	]"

class
	GUI_BACKEND

inherit
	GUI_BACKEND_API
		redefine
			scale
		end

feature -- Lifecycle and loop

	init (a_name, a_id: POINTER): BOOLEAN
			-- Windows always has a display.
		do
			Result := True
		end

	is_gui_thread: BOOLEAN
		do
			Result := (create {SHELL_WAKE}).is_pump_thread
		end

	pump (a_ms: INTEGER)
			-- Run the open window's loop until an event is queued or `a_ms' pass.
		do
			if events.is_empty then
				if attached open_window as al_w and then al_w.is_window_open then
					al_w.shell_turn (a_ms.max (0))
				else
					pump_windowless (a_ms.max (0))
				end
			end
		end

	pump_until_idle (a_ms: INTEGER)
			-- Dispatch what is waiting, then lay out and draw, so positions and sizes are current
			-- (the shared tests' rule 2).
		do
			if attached open_window as al_w and then al_w.is_window_open then
				al_w.shell_turn_pending
				al_w.request_render
				al_w.shell_turn_pending
			end
		end

	start_heartbeat (a_ms: INTEGER)
			-- simple_shell's window keeps its own heartbeat.
		do
		end

	wake
			-- Reach the pump from any processor (simple_shell's wake is process-wide).
		do
			(create {SHELL_WAKE}).wake
		end

	next (a_type, an_id, a_a, a_b, a_c: TYPED_POINTER [INTEGER]): BOOLEAN
			-- Hand over the oldest queued event.
		do
			if not events.is_empty then
				put_int (a_type, events.item.type)
				put_int (an_id, events.item.id)
				put_int (a_a, events.item.a)
				put_int (a_b, events.item.b)
				put_int (a_c, events.item.c)
				events.remove
				Result := True
			end
		end

feature {GUI_SW_WINDOW} -- Events

	push (a_type, an_id, a_a, a_b, a_c: INTEGER)
			-- Queue one simple_gui event.
		do
			events.extend ([a_type, an_id, a_a, a_b, a_c])
		end

feature -- Windows and containers

	window (a_title: POINTER; a_width, a_height: INTEGER): INTEGER
		local
			l_w: GUI_SW_WINDOW
		do
			Result := register (Void)
			create l_w.make (Current, Result, from_c (a_title), device (a_width.max (1)), device (a_height.max (1)))
			if forced_dark_set then
				l_w.set_theme (themed (forced_dark))
			end
			windows.put (l_w, Result)
		end

	window_set_content (a_window, a_child: INTEGER)
		do
			window_content.force (a_child, a_window)
			if attached windows.item (a_window) as al_w and then al_w.is_window_open then
				compose (a_window, al_w)
			end
		end

	window_show (a_window: INTEGER)
			-- Open the native window (one at a time in stage 1).
		do
			if attached windows.item (a_window) as al_w and then not al_w.is_window_open then
				if attached open_window as al_other and then al_other.is_window_open then
					not_yet ("a second window open at the same time")
				end
				compose (a_window, al_w)
				al_w.set_close_requests_are_events (True)
				al_w.shell_open_window (al_w.title, al_w.win_x, al_w.win_y, al_w.win_w, al_w.win_h)
				open_window := al_w
				al_w.request_render
			end
		end

	window_close (a_window: INTEGER)
		do
			if attached windows.item (a_window) as al_w and then al_w.is_window_open then
				al_w.close
				al_w.shell_turn_pending
			end
		end

	window_set_title (a_window: INTEGER; a_title: POINTER)
		do
			if attached windows.item (a_window) as al_w then
				al_w.set_title (from_c (a_title))
			end
		end

	window_install_shortcuts (a_window: INTEGER; a_spec: POINTER)
			-- "id=shortcut;id=shortcut": each registrable shortcut runs its menu item.
		local
			l_pair: LIST [STRING_32]
			l_shortcut: SW_SHORTCUT
		do
			if attached windows.item (a_window) as al_w then
				across from_c (a_spec).split (';') as ic loop
					l_pair := ic.split ('=')
					if l_pair.count = 2 and then l_pair.first.is_integer then
						create l_shortcut.make (l_pair.last)
						if l_shortcut.is_registrable then
							al_w.register_shortcut (l_pair.last, agent choose_menu_item (l_pair.first.to_integer))
						end
					end
				end
			end
		end

	stack (a_vertical: BOOLEAN; a_spacing: INTEGER): INTEGER
		local
			l_col: SW_COLUMN
			l_row: SW_ROW
		do
			if a_vertical then
				create l_col.make
				l_col.set_padding (0.0)
				l_col.set_gap (a_spacing.max (0).to_double)
				Result := register (l_col)
			else
				create l_row.make
				l_row.set_gap (a_spacing.max (0).to_double)
				Result := register (l_row)
			end
		end

	stack_extend (a_stack, a_child: INTEGER; a_stretch: BOOLEAN)
		do
			if attached {SW_BOX_CONTAINER} widget (a_stack) as al_box and then attached widget (a_child) as al_child then
				al_box.put (al_child)
				if a_stretch then
					al_child.set_grow (1.0)
				end
				if stack_alignment.has (a_stack) then
					al_child.set_cross_alignment (stack_alignment.item (a_stack))
				elseif attached {SW_COLUMN} al_box and then attached {SW_BUTTON} al_child then
						-- GTK and AppKit keep a button at its natural width in a column
					al_child.set_cross_alignment ({SW_WIDGET}.Place_start)
				end
			end
		end

	stack_set_spacing (a_stack, a_spacing: INTEGER)
		do
			if attached {SW_BOX_CONTAINER} widget (a_stack) as al_box then
				al_box.set_gap (a_spacing.max (0).to_double)
			end
		end

	stack_set_alignment (a_stack, an_alignment: INTEGER)
			-- simple_gui's Align_fill .. Align_end are simple_widgets' Place_fill .. Place_end.
		do
			stack_alignment.force (an_alignment, a_stack)
			if attached {SW_BOX_CONTAINER} widget (a_stack) as al_box then
				across al_box.children as ic loop
					ic.set_cross_alignment (an_alignment)
				end
			end
		end

	stack_align_child (a_stack, a_child, an_alignment: INTEGER)
		do
			if attached widget (a_child) as al_child then
				al_child.set_cross_alignment (an_alignment)
			end
		end

	grid: INTEGER
		do
			Result := register (create {SW_GRID}.make)
		end

	grid_put (a_grid, a_child, a_row, a_column, a_rows, a_columns: INTEGER)
		do
			if attached {SW_GRID} widget (a_grid) as al_g and then attached widget (a_child) as al_child then
				al_g.put_spanning (al_child, a_row, a_column, a_rows, a_columns)
			end
		end

	grid_set_spacing (a_grid, a_row_gap, a_column_gap: INTEGER)
		do
			if attached {SW_GRID} widget (a_grid) as al_g then
				al_g.set_gaps (a_row_gap.max (0).to_double, a_column_gap.max (0).to_double)
			end
		end

	grid_set_homogeneous_columns (a_grid: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_GRID} widget (a_grid) as al_g then
				al_g.set_homogeneous_columns (a_on)
			end
		end

	grid_set_stretching_column (a_grid, a_column: INTEGER)
		do
			if attached {SW_GRID} widget (a_grid) as al_g then
				al_g.set_stretching_column (a_column.max (0))
			end
		end

	splitter (a_vertical: BOOLEAN): INTEGER
		do
			not_yet ("splitter")
		end

	splitter_set_pane (a_splitter, a_pane, a_child: INTEGER)
		do
			not_yet ("splitter")
		end

	splitter_position (a_splitter: INTEGER): INTEGER
		do
			not_yet ("splitter")
		end

	splitter_set_position (a_splitter, a_position: INTEGER)
		do
			not_yet ("splitter")
		end

feature -- Controls

	label (a_text: POINTER): INTEGER
		do
			Result := register (create {SW_LABEL}.make_ui (from_c (a_text)))
		end

	label_set (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_LABEL} widget (an_id) as al_l then
				al_l.set_text (from_c (a_text))
				changed
			end
		end

	label_get (an_id: INTEGER): POINTER
		do
			if attached {SW_LABEL} widget (an_id) as al_l then
				Result := c_text (al_l.text)
			end
		end

	label_set_wrap_width (an_id, a_characters: INTEGER)
		do
			if attached {SW_LABEL} widget (an_id) as al_l then
				al_l.set_wrap_chars (a_characters.max (0))
				changed
			end
		end

	button (a_text: POINTER): INTEGER
		local
			l_b: SW_BUTTON
		do
			create l_b.make (from_c (a_text), Void)
			Result := register (l_b)
			l_b.set_on_click (agent push (1, Result, 0, 0, 0))
		end

	button_set (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_BUTTON} widget (an_id) as al_b then
				al_b.set_label (from_c (a_text))
				changed
			end
		end

	button_get (an_id: INTEGER): POINTER
		do
			if attached {SW_BUTTON} widget (an_id) as al_b then
				Result := c_text (al_b.label)
			end
		end

	field: INTEGER
		local
			l_t: SW_TEXT_BOX
		do
			create l_t.make_single_line ("")
			Result := register (l_t)
			l_t.set_on_change (agent push (2, Result, 0, 0, 0))
			l_t.set_on_activate (agent push (3, Result, 0, 0, 0))
		end

	field_set (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t then
				al_t.set_text (from_c (a_text))
				changed
			end
		end

	field_get (an_id: INTEGER): POINTER
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t then
				Result := c_text (al_t.text)
			end
		end

	field_set_placeholder (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t then
				al_t.set_placeholder (from_c (a_text))
				changed
			end
		end

	check_box (a_text: POINTER): INTEGER
		local
			l_c: SW_CHECK_BOX
		do
			create l_c.make (from_c (a_text), False, Void)
			Result := register (l_c)
			l_c.set_on_change (agent report_toggle (Result))
		end

	check_box_set (an_id: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_CHECK_BOX} widget (an_id) as al_c then
				al_c.set_checked (a_on)
				changed
			end
		end

	check_box_is_checked (an_id: INTEGER): BOOLEAN
		do
			Result := attached {SW_CHECK_BOX} widget (an_id) as al_c and then al_c.is_checked
		end

	check_box_set_text (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_CHECK_BOX} widget (an_id) as al_c then
				al_c.set_label (from_c (a_text))
				changed
			end
		end

	check_box_text (an_id: INTEGER): POINTER
		do
			if attached {SW_CHECK_BOX} widget (an_id) as al_c then
				Result := c_text (al_c.label)
			end
		end

	text_area: INTEGER
		local
			l_t: SW_TEXT_BOX
		do
			create l_t.make ("")
			Result := register (l_t)
			l_t.set_on_change (agent push (2, Result, 0, 0, 0))
		end

	text_area_set (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t then
				al_t.set_text (from_c (a_text))
				changed
			end
		end

	text_area_get (an_id: INTEGER): POINTER
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t then
				Result := c_text (al_t.text)
			end
		end

	text_area_set_read_only (an_id: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t then
				al_t.set_read_only (a_on)
			end
		end

	tabs: INTEGER
		do
			not_yet ("tabs")
		end

	tabs_extend (a_tabs, a_page: INTEGER; a_title: POINTER)
		do
			not_yet ("tabs")
		end

	tabs_select (a_tabs, a_page: INTEGER)
		do
			not_yet ("tabs")
		end

	tabs_selected (a_tabs: INTEGER): INTEGER
		do
			not_yet ("tabs")
		end

	tabs_set_title (a_tabs, a_page: INTEGER; a_title: POINTER)
		do
			not_yet ("tabs")
		end

	list: INTEGER
		local
			l_l: SW_TEXT_LIST
		do
			create l_l.make (120.0)
			Result := register (l_l)
			l_l.set_on_select (agent report_row (Result, ?))
		end

	list_extend (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l then
				al_l.extend (from_c (a_text))
				changed
			end
		end

	list_wipe_out (an_id: INTEGER)
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l then
				al_l.wipe_out
				changed
			end
		end

	list_select (an_id, a_row: INTEGER)
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l and then a_row >= 0 and then a_row <= al_l.count then
				al_l.select_row_quietly (a_row)
				if a_row > 0 then
					al_l.scroll_to_row (a_row)
				end
				changed
			end
		end

	list_selected (an_id: INTEGER): INTEGER
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l then
				Result := al_l.selected_index
			end
		end

	table (a_titles: POINTER): INTEGER
		do
			not_yet ("table")
		end

	table_extend (a_table: INTEGER; a_cells: POINTER)
		do
			not_yet ("table")
		end

	table_wipe_out (a_table: INTEGER)
		do
			not_yet ("table")
		end

	table_set_multiple (a_table: INTEGER; a_on: BOOLEAN)
		do
			not_yet ("table")
		end

	table_select (a_table, a_row: INTEGER; a_extend: BOOLEAN)
		do
			not_yet ("table")
		end

	table_selected_count (a_table: INTEGER): INTEGER
		do
			not_yet ("table")
		end

	table_selected_at (a_table, i: INTEGER): INTEGER
		do
			not_yet ("table")
		end

	table_set_sort_indicator (a_table, a_column: INTEGER; a_ascending: BOOLEAN)
		do
			not_yet ("table")
		end

	tree: INTEGER
		do
			not_yet ("tree")
		end

	tree_add (a_tree, a_node, a_parent: INTEGER; a_text: POINTER)
		do
			not_yet ("tree")
		end

	tree_set_expanded (a_tree, a_node: INTEGER; a_on: BOOLEAN)
		do
			not_yet ("tree")
		end

	tree_is_expanded (a_tree, a_node: INTEGER): BOOLEAN
		do
			not_yet ("tree")
		end

	tree_select (a_tree, a_node: INTEGER)
		do
			not_yet ("tree")
		end

	tree_selected (a_tree: INTEGER): INTEGER
		do
			not_yet ("tree")
		end

feature -- Every widget

	set_enabled (an_id: INTEGER; a_on: BOOLEAN)
		do
			if attached widget (an_id) as al_w then
				al_w.set_enabled (a_on)
				changed
			end
		end

	is_enabled (an_id: INTEGER): BOOLEAN
		do
			Result := attached widget (an_id) as al_w and then al_w.is_enabled
		end

	set_visible (an_id: INTEGER; a_on: BOOLEAN)
			-- A widget hides or shows; a window is shown by opening it.
		do
			if attached widget (an_id) as al_w then
				al_w.set_visible (a_on)
				changed
			elseif attached windows.item (an_id) as al_win then
				if not a_on then
					if al_win.is_window_open then
						al_win.hide_window
					end
					hidden_windows.force (True, an_id)
				elseif al_win.is_window_open then
					al_win.show_window
					hidden_windows.remove (an_id)
				else
					window_show (an_id)
				end
			end
		end

	is_visible (an_id: INTEGER): BOOLEAN
			-- A widget not hidden; a window open.
		do
			if attached widget (an_id) as al_w then
				Result := al_w.is_visible
			elseif attached windows.item (an_id) as al_win then
				Result := al_win.is_window_open and not hidden_windows.has (an_id)
			end
		end

	set_direction (an_id, a_direction: INTEGER)
			-- simple_gui's Direction_auto .. Direction_right_to_left are simple_widgets'
			-- Layout_inherit .. Layout_right_to_left.
		do
			if attached widget (an_id) as al_w then
				al_w.set_layout_direction (a_direction)
				changed
			elseif attached windows.item (an_id) as al_win then
				window_direction.force (a_direction, an_id)
				if attached al_win.root as al_root then
					al_root.set_layout_direction (a_direction)
				end
				changed
			end
		end

	set_accessible_label (an_id: INTEGER; a_text: POINTER)
		do
			if attached widget (an_id) as al_w then
				al_w.set_accessible_name (from_c (a_text))
			end
		end

	set_accessible_description (an_id: INTEGER; a_text: POINTER)
		do
			if attached widget (an_id) as al_w then
				al_w.set_accessible_description (from_c (a_text))
			end
		end

	widget_x (an_id: INTEGER): INTEGER
			-- Logical pixels from the content area's left edge.
		do
			if attached widget (an_id) as al_w and then attached content_origin (al_w) as al_o then
				Result := logical (al_w, al_w.x - al_o.x)
			end
		end

	widget_y (an_id: INTEGER): INTEGER
			-- Logical pixels from the content area's top edge.
		do
			if attached widget (an_id) as al_w and then attached content_origin (al_w) as al_o then
				Result := logical (al_w, al_w.y - al_o.y)
			end
		end

	accessible_role (an_id: INTEGER): POINTER
		do
			if attached widget (an_id) as al_w then
				Result := c_text (accessibility_names.role_name (al_w.accessible_role))
			else
				Result := c_text ({STRING_32} "application")
			end
		end

feature -- Canvas

	canvas (a_width, a_height: INTEGER): INTEGER
		local
			l_c: SW_CANVAS
		do
			create l_c.make (a_height.max (1).to_double)
			l_c := l_c.with_min_size (a_width.max (1).to_double, a_height.max (1).to_double)
			Result := register (l_c)
			l_c.set_on_pointer (agent report_pointer (Result, ?, ?, ?, ?, ?))
			l_c.set_on_resize (agent report_resize (Result, ?, ?))
			l_c.set_on_key (agent report_key (Result, ?, ?))
			l_c.set_on_char (agent report_char (Result, ?))
		end

	canvas_present (an_id: INTEGER; a_cairo_surface: POINTER)
			-- Keep our own cairo reference to the finished image (the program keeps its own)
			-- and show it 1:1.
		local
			l_img: CAIRO_SURFACE
		do
			if attached {SW_CANVAS} widget (an_id) as al_c and then a_cairo_surface /= default_pointer then
				if presented.has (an_id) then
					c_surface_destroy (presented.item (an_id))
				end
				presented.force (c_surface_reference (a_cairo_surface), an_id)
				create l_img.make_from_handle (presented.item (an_id))
				if l_img.width > 0 and l_img.height > 0 then
					al_c.present_image (l_img, (l_img.width / al_c.width.max (1.0)).max (0.01))
				end
				changed
			end
		end

	scale_factor (an_id: INTEGER): INTEGER
		do
			Result := scale (an_id).ceiling.max (1)
		end

	scale (an_id: INTEGER): REAL_64
			-- simple_widgets lays out in device pixels: one canvas unit per pixel, so the image
			-- the program draws at width x scale lands 1:1.
		do
			if attached {SW_CANVAS} widget (an_id) as al_c then
				Result := al_c.device_scale
			else
				Result := 1.0
			end
		end

	width (an_id: INTEGER): INTEGER
		do
			if attached widget (an_id) as al_w then
				Result := logical (al_w, al_w.width)
			elseif attached windows.item (an_id) as al_win then
				Result := (al_win.win_w / dpi).rounded
			end
		end

	height (an_id: INTEGER): INTEGER
		do
			if attached widget (an_id) as al_w then
				Result := logical (al_w, al_w.height)
			elseif attached windows.item (an_id) as al_win then
				Result := (al_win.win_h / dpi).rounded
			end
		end

feature -- Menus

	menu_new (a_title: POINTER): POINTER
		do
			menus.extend ([from_c (a_title), create {ARRAYED_LIST [TUPLE [text, shortcut: STRING_32; id, role: INTEGER; separator: BOOLEAN]]}.make (8)])
			Result := default_pointer + menus.count
		end

	menu_add_item (a_menu: POINTER; a_text, a_shortcut: POINTER; an_item_id, a_role: INTEGER)
		do
			if attached menu_of (a_menu) as al_m then
				al_m.items.extend ([from_c (a_text), from_c (a_shortcut), an_item_id, a_role, False])
			end
		end

	menu_set_title (a_menu: POINTER; a_title: POINTER)
		local
			i: INTEGER
		do
			i := menu_index (a_menu)
			if attached menu_of (a_menu) as al_m then
				al_m.title := from_c (a_title)
				across windows as ic loop
					if attached ic.menu_bar as al_bar and then i <= al_bar.labels.count then
						al_bar.set_title (i, al_m.title)
					end
				end
				changed
			end
		end

	menu_title (a_menu: POINTER): POINTER
		do
			if attached menu_of (a_menu) as al_m then
				Result := c_text (al_m.title)
			end
		end

	menu_set_item_text (an_item_id: INTEGER; a_text: POINTER)
			-- Menus are built on every open, so the next open shows it.
		do
			if attached menu_item (an_item_id) as al_i then
				al_i.text := from_c (a_text)
			end
		end

	menu_item_text (an_item_id: INTEGER): POINTER
		do
			if attached menu_item (an_item_id) as al_i then
				Result := c_text (al_i.text)
			end
		end

	menu_add_separator (a_menu: POINTER)
		do
			if attached menu_of (a_menu) as al_m then
				al_m.items.extend ([{STRING_32} "", {STRING_32} "", 0, 0, True])
			end
		end

	context_menu_new: POINTER
		do
			not_yet ("context menus")
		end

	widget_set_context_menu (an_id: INTEGER; a_menu: POINTER)
		do
			not_yet ("context menus")
		end

feature -- Dialogs

	open_file (a_window: INTEGER; a_title: POINTER; a_save: BOOLEAN; an_extensions: POINTER): POINTER
			-- simple_widgets' drawn file dialog, waited for (W9).
		do
			if attached windows.item (a_window) as al_w and then attached al_w.choose_file (a_save, ".", "", from_c (an_extensions)) as al_path then
				Result := c_text (al_path)
			end
		end

	message (a_window: INTEGER; a_title, a_text: POINTER; a_confirm: BOOLEAN): BOOLEAN
			-- simple_widgets' drawn dialog, waited for (W9).
		do
			if attached windows.item (a_window) as al_w then
				Result := al_w.ask ({SW_DIALOG}.Kind_info, from_c (a_title), from_c (a_text), a_confirm)
			end
		end

feature -- Appearance

	is_dark: BOOLEAN
		do
			if forced_dark_set then
				Result := forced_dark
			else
				Result := (create {SHELL_APPEARANCE}).system_prefers_dark
			end
		end

	system_color (a_role: INTEGER): INTEGER
			-- The theme's colors: 1 background, 2 text, 3 secondary text, 4 accent, 5 selection,
			-- 6 separator.
		local
			t: SW_THEME
			l_rgb: NATURAL_32
		do
			if is_dark then
				create t.make_dark
			else
				create t.make_light
			end
			inspect a_role
			when 1 then l_rgb := t.background
			when 2 then l_rgb := t.ink
			when 3 then l_rgb := t.ink_muted
			when 4 then l_rgb := t.accent
			when 5 then l_rgb := t.wash_accent
			else l_rgb := t.outline
			end
			Result := (l_rgb & 0xFFFFFF).to_integer_32
		end

	set_dark (a_on: BOOLEAN)
			-- Tests: wear dark (or light) everywhere and report the change.
		do
			forced_dark_set := True
			forced_dark := a_on
			across windows as ic loop
				ic.set_theme (themed (a_on))
			end
			push (10, 0, a_on.to_integer, 0, 0)
			changed
		end

feature -- Test doors (act on the widget as a user would)

	test_click (an_id: INTEGER)
		do
			if attached widget (an_id) as al_w then
				al_w.perform_click
				changed
			end
		end

	test_click_header (a_table, a_column: INTEGER)
		do
			not_yet ("table")
		end

	test_expand (a_tree, a_node: INTEGER; a_on: BOOLEAN)
		do
			not_yet ("tree")
		end

	test_type (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t and then not al_t.is_read_only then
				al_t.type_text (from_c (a_text))
				changed
			end
		end

	test_choose (an_id, a_row: INTEGER)
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l and then a_row >= 1 and then a_row <= al_l.count then
				al_l.select_row (a_row)
				changed
			else
				not_yet ("choosing in this control")
			end
		end

	test_menu (an_item_id: INTEGER)
		do
			choose_menu_item (an_item_id)
		end

	test_request_close (a_window: INTEGER)
		do
			if attached windows.item (a_window) as al_w and then al_w.is_window_open then
				al_w.request_close
			end
		end

	test_context_menu (an_id, an_item_id: INTEGER): BOOLEAN
		do
			not_yet ("context menus")
		end

	snapshot (an_id: INTEGER; a_path: POINTER): BOOLEAN
		do
			if attached windows.item (an_id) as al_w then
				al_w.request_render
				Result := al_w.write_frame (from_c (a_path))
			end
		end

	describe_accessibility (a_window: INTEGER): POINTER
		do
			if attached windows.item (a_window) as al_w then
				Result := c_text (al_w.describe_accessibility)
			end
		end

feature {NONE} -- State

	items: ARRAYED_LIST [detachable SW_WIDGET]
			-- Every widget by id (a window's slot is Void).
		once ("OBJECT")
			create Result.make (64)
		end

	windows: HASH_TABLE [GUI_SW_WINDOW, INTEGER]
		once ("OBJECT")
			create Result.make (4)
		end

	window_content: HASH_TABLE [INTEGER, INTEGER]
			-- Each window's content widget.
		once ("OBJECT")
			create Result.make (4)
		end

	window_direction: HASH_TABLE [INTEGER, INTEGER]
		once ("OBJECT")
			create Result.make (4)
		end

	stack_alignment: HASH_TABLE [INTEGER, INTEGER]
			-- A stack's alignment for children added later.
		once ("OBJECT")
			create Result.make (8)
		end

	events: ARRAYED_QUEUE [TUPLE [type, id, a, b, c: INTEGER]]
		once ("OBJECT")
			create Result.make (64)
		end

	menus: ARRAYED_LIST [TUPLE [title: STRING_32; items: ARRAYED_LIST [TUPLE [text, shortcut: STRING_32; id, role: INTEGER; separator: BOOLEAN]]]]
		once ("OBJECT")
			create Result.make (4)
		end

	presented: HASH_TABLE [POINTER, INTEGER]
			-- Our cairo reference to each canvas's shown image.
		once ("OBJECT")
			create Result.make (4)
		end

	accessibility_names: SW_ACCESSIBILITY
		once ("OBJECT")
			create Result
		end

	open_window: detachable GUI_SW_WINDOW
			-- The native window open now.

	forced_dark, forced_dark_set: BOOLEAN

	last_c: detachable C_STRING
			-- The text handed out last (alive until the next).

feature {GUI_SW_WINDOW} -- Themes

	themed (a_dark: BOOLEAN): SW_THEME
			-- A light or dark theme at the desktop's scale (150% draws everything half again as
			-- large): simple_widgets lays out in device pixels.
		do
			if a_dark then
				create Result.make_dark
			else
				create Result.make_light
			end
			Result.set_text_scale (dpi)
		ensure
			scaled: Result.text_scale = dpi
		end

feature {NONE} -- Implementation

	dpi: REAL_64
			-- Device pixels per logical pixel on the desktop.
		do
			Result := desktop.dpi_scale
			if Result <= 0.0 then
				Result := 1.0
			end
		ensure
			positive: Result > 0.0
		end

	device (a_logical: INTEGER): INTEGER
			-- Logical pixels as device pixels.
		do
			Result := (a_logical * dpi).rounded.max (1)
		end

	hidden_windows: HASH_TABLE [BOOLEAN, INTEGER]
			-- Windows the program hid (open, not shown).
		once ("OBJECT")
			create Result.make (2)
		end

	pump_windowless (a_ms: INTEGER)
			-- No window open: pump this thread in short slices so a processor's wake still
			-- arrives (as event 11) within a slice, not after the whole `a_ms'.
		local
			i, l_slices: INTEGER
			l_woke: BOOLEAN
		do
			wake_reader.claim_pump_thread
			l_slices := (a_ms // 10).max (1)
			from
				i := 1
			until
				i > l_slices or l_woke
			loop
				desktop.pump_for (a_ms.min (10))
				l_woke := drain.took_wake
				i := i + 1
			end
			if l_woke then
				push (11, 0, 0, 0, 0)
			end
		end

	wake_reader: SHELL_WAKE
		once ("OBJECT")
			create Result
		end

	desktop: SHELL_DESKTOP
		once ("OBJECT")
			create Result
		end

	drain: GUI_SHELL_DRAIN
		once ("OBJECT")
			create Result
		end

	register (a_widget: detachable SW_WIDGET): INTEGER
		do
			items.extend (a_widget)
			Result := items.count
		ensure
			numbered: Result = items.count
		end

	widget (an_id: INTEGER): detachable SW_WIDGET
		do
			if an_id >= 1 and an_id <= items.count then
				Result := items.i_th (an_id)
			end
		end

	compose (a_window: INTEGER; a_w: GUI_SW_WINDOW)
			-- The window's root: the menu bar (when there are menus) above the content.
		local
			l_root: SW_COLUMN
			l_bar: SW_MENU_BAR
			i: INTEGER
		do
			create l_root.make
			l_root.set_padding (0.0)
			l_root.set_gap (0.0)
			if not menus.is_empty then
				create l_bar.make
				from i := 1 until i > menus.count loop
					l_bar.add_menu (menus.i_th (i).title, agent build_menu (i, a_w))
					i := i + 1
				end
				l_root.put (l_bar)
				a_w.set_menu_bar (l_bar)
			end
			if window_content.has (a_window) and then attached widget (window_content.item (a_window)) as al_content then
				al_content.set_grow (1.0)
				l_root.put (al_content)
			end
			if window_direction.has (a_window) then
				l_root.set_layout_direction (window_direction.item (a_window))
			end
			a_w.set_root (l_root)
		end

	build_menu (a_index: INTEGER; a_w: GUI_SW_WINDOW): SW_MENU
			-- Menu `a_index' as it stands now: items report event 5; edit roles act on the
			-- focused widget and gray when it cannot act.
		local
			l_hint: STRING_32
		do
			create Result.make
			across menus.i_th (a_index).items as ic loop
				if ic.separator then
					Result.add_separator
				else
					l_hint := shortcut_text (ic.shortcut)
					if ic.role >= {SW_WIDGET}.Edit_undo and ic.role <= {SW_WIDGET}.Edit_select_all then
						Result.add_item (ic.text, l_hint, a_w.can_edit_focused (ic.role), agent a_w.edit_focused (ic.role))
					else
						Result.add_item (ic.text, l_hint, True, agent push (5, 0, ic.id, 0, 0))
					end
				end
			end
		end

	shortcut_text (a_spec: STRING_32): STRING_32
		local
			l_s: SW_SHORTCUT
		do
			create l_s.make (a_spec)
			if l_s.is_valid then
				Result := l_s.display_text
			else
				create Result.make_empty
			end
		end

	choose_menu_item (an_item_id: INTEGER)
			-- As a user choosing the item: an edit role acts on the focused widget, anything
			-- else reports event 5.
		do
			if attached menu_item (an_item_id) as al_i and then al_i.role >= {SW_WIDGET}.Edit_undo and then al_i.role <= {SW_WIDGET}.Edit_select_all then
				if attached open_window as al_w then
					al_w.edit_focused (al_i.role)
				end
			else
				push (5, 0, an_item_id, 0, 0)
			end
		end

	menu_index (a_menu: POINTER): INTEGER
		do
			Result := a_menu.to_integer_32
		end

	menu_of (a_menu: POINTER): detachable TUPLE [title: STRING_32; items: ARRAYED_LIST [TUPLE [text, shortcut: STRING_32; id, role: INTEGER; separator: BOOLEAN]]]
		do
			if menu_index (a_menu) >= 1 and menu_index (a_menu) <= menus.count then
				Result := menus.i_th (menu_index (a_menu))
			end
		end

	menu_item (an_item_id: INTEGER): detachable TUPLE [text, shortcut: STRING_32; id, role: INTEGER; separator: BOOLEAN]
		do
			across menus as m loop
				across m.items as ic loop
					if Result = Void and then not ic.separator and then ic.id = an_item_id then
						Result := ic
					end
				end
			end
		end

	report_toggle (an_id: INTEGER)
		do
			push (12, an_id, check_box_is_checked (an_id).to_integer, 0, 0)
		end

	report_row (an_id, a_row: INTEGER)
		do
			push (4, an_id, a_row, 0, 0)
		end

	report_pointer (an_id, a_kind: INTEGER; a_x, a_y: REAL_64; a_button, a_modifiers: INTEGER)
		do
			if attached widget (an_id) as al_w then
				push (7, an_id, logical (al_w, a_x), logical (al_w, a_y), a_kind + a_button * 16 + a_modifiers * 256)
			end
		end

	report_resize (an_id: INTEGER; a_width, a_height: REAL_64)
		do
			if attached widget (an_id) as al_w then
				push (9, an_id, logical (al_w, a_width), logical (al_w, a_height), 0)
			end
		end

	report_key (an_id, a_vk: INTEGER; a_shift: BOOLEAN)
			-- Keys that type nothing, in GDK's key codes (the shared vocabulary); typing comes
			-- through `report_char'.
		local
			l_code: INTEGER
		do
			inspect a_vk
			when 37 then l_code := 0xFF51
			when 38 then l_code := 0xFF52
			when 39 then l_code := 0xFF53
			when 40 then l_code := 0xFF54
			when 36 then l_code := 0xFF50
			when 35 then l_code := 0xFF57
			when 33 then l_code := 0xFF55
			when 34 then l_code := 0xFF56
			when 46 then l_code := 0xFFFF
			when 112 .. 123 then l_code := 0xFFBE + (a_vk - 112)
			else
			end
			if l_code /= 0 and then attached {SW_CANVAS} widget (an_id) as al_c then
				push (8, an_id, l_code, 0, al_c.modifiers * 256)
			end
		end

	report_char (an_id, a_code: INTEGER)
		local
			l_code: INTEGER
		do
			inspect a_code
			when 8 then l_code := 0xFF08
			when 9 then l_code := 0xFF09
			when 13 then l_code := 0xFF0D
			when 27 then l_code := 0xFF1B
			else
				l_code := a_code
			end
			if a_code >= 8 and then attached {SW_CANVAS} widget (an_id) as al_c then
				push (8, an_id, l_code, if a_code >= 32 or l_code /= a_code then a_code else 0 end, al_c.modifiers * 256)
			end
		end

	logical (a_w: SW_WIDGET; a_device: REAL_64): INTEGER
			-- Device pixels as logical ones (simple_widgets lays out in device pixels).
		local
			l_scale: REAL_64
		do
			l_scale := 1.0
			if attached open_window as al_win then
				l_scale := al_win.theme.text_scale.max (0.01)
			end
			Result := (a_device / l_scale).rounded
		end

	content_origin (a_w: SW_WIDGET): detachable SW_WIDGET
			-- The content widget of the window `a_w' is in (positions count from its corner).
		do
			across window_content as ic loop
				if Result = Void and then attached widget (ic) as al_c and then is_inside (a_w, al_c) then
					Result := al_c
				end
			end
		end

	is_inside (a_w, a_ancestor: SW_WIDGET): BOOLEAN
		local
			l_w: detachable SW_WIDGET
		do
			from l_w := a_w until l_w = Void or Result loop
				Result := l_w = a_ancestor
				l_w := l_w.parent
			end
		end

	changed
			-- A programmatic change: lay out and draw again.
		do
			if attached open_window as al_w and then al_w.is_window_open then
				al_w.request_render
			end
		end

	c_text (a_text: READABLE_STRING_GENERAL): POINTER
			-- `a_text' as a UTF-8 C string, alive until the next one.
		local
			l_c: C_STRING
		do
			l_c := to_c (a_text)
			last_c := l_c
			Result := l_c.item
		end

	put_int (a_target: TYPED_POINTER [INTEGER]; a_value: INTEGER)
		do
			(create {MANAGED_POINTER}.share_from_pointer (a_target.to_pointer, 4)).put_integer_32 (a_value, 0)
		end

	not_yet (a_what: STRING)
			-- Fail loudly: stage 2 of the Windows backend.
		local
			l_e: DEVELOPER_EXCEPTION
		do
			l_e := create {DEVELOPER_EXCEPTION}
			l_e.set_description ("not yet on Windows: " + a_what)
			l_e.raise
		end

	c_surface_reference (a_surface: POINTER): POINTER
		external
			"C inline use <cairo.h>"
		alias
			"return cairo_surface_reference((cairo_surface_t *) $a_surface);"
		end

	c_surface_destroy (a_surface: POINTER)
		external
			"C inline use <cairo.h>"
		alias
			"cairo_surface_destroy((cairo_surface_t *) $a_surface);"
		end

end
