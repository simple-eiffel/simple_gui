note
	description: "[
		simple_gui's GTK 4 backend (Linux). Each feature is one call into
		Clib/simple_gui_gtk.h. Externals that WAIT (the pump and the dialogs) are
		marked `blocking', so other SCOOP processors and the collector keep running
		while the GUI thread waits (simple_shell's freeze-assault lesson).
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
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_init((const char *) $a_name, (const char *) $a_id) ? EIF_TRUE : EIF_FALSE;"
		end

	is_gui_thread: BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_is_gui_thread() ? EIF_TRUE : EIF_FALSE;"
		end

	pump (a_ms: INTEGER)
		external "C blocking inline use %"simple_gui_gtk.h%""
		alias "sg_pump($a_ms);"
		end

	pump_until_idle (a_ms: INTEGER)
		external "C blocking inline use %"simple_gui_gtk.h%""
		alias "sg_pump_until_idle($a_ms);"
		end

	start_heartbeat (a_ms: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_start_heartbeat($a_ms);"
		end

	wake
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_wake();"
		end

	next (a_type, an_id, a_a, a_b, a_c: TYPED_POINTER [INTEGER]): BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_next((int *) $a_type, (int *) $an_id, (int *) $a_a, (int *) $a_b, (int *) $a_c) ? EIF_TRUE : EIF_FALSE;"
		end

feature -- Windows and containers

	window (a_title: POINTER; a_width, a_height: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_window((const char *) $a_title, $a_width, $a_height);"
		end

	window_set_content (a_window, a_child: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_window_set_content($a_window, $a_child);"
		end

	window_show (a_window: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_window_show($a_window);"
		end

	window_close (a_window: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_window_close($a_window);"
		end

	window_set_title (a_window: INTEGER; a_title: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_window_set_title($a_window, (const char *) $a_title);"
		end

	window_install_shortcuts (a_window: INTEGER; a_spec: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_window_install_shortcuts($a_window, (const char *) $a_spec);"
		end

	stack (a_vertical: BOOLEAN; a_spacing: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_stack($a_vertical ? 1 : 0, $a_spacing);"
		end

	stack_extend (a_stack, a_child: INTEGER; a_stretch: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_stack_extend($a_stack, $a_child, $a_stretch ? 1 : 0);"
		end

	stack_set_spacing (a_stack, a_spacing: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_stack_set_spacing($a_stack, $a_spacing);"
		end

	stack_set_alignment (a_stack, an_alignment: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_stack_set_alignment($a_stack, $an_alignment);"
		end

	stack_align_child (a_stack, a_child, an_alignment: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_stack_align_child($a_stack, $a_child, $an_alignment);"
		end

	grid_set_homogeneous_columns (a_grid: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_grid_set_homogeneous_columns($a_grid, $a_on ? 1 : 0);"
		end

	grid_set_stretching_column (a_grid, a_column: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_grid_set_stretching_column($a_grid, $a_column);"
		end

	grid: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_grid();"
		end

	grid_put (a_grid, a_child, a_row, a_column, a_rows, a_columns: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_grid_put($a_grid, $a_child, $a_row, $a_column, $a_rows, $a_columns);"
		end

	grid_set_spacing (a_grid, a_row_gap, a_column_gap: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_grid_set_spacing($a_grid, $a_row_gap, $a_column_gap);"
		end

	splitter (a_vertical: BOOLEAN): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_splitter($a_vertical ? 1 : 0);"
		end

	splitter_set_pane (a_splitter, a_pane, a_child: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_splitter_set_pane($a_splitter, $a_pane, $a_child);"
		end

	splitter_position (a_splitter: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_splitter_position($a_splitter);"
		end

	splitter_set_position (a_splitter, a_position: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_splitter_set_position($a_splitter, $a_position);"
		end

feature -- Controls

	label (a_text: POINTER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_label((const char *) $a_text);"
		end

	label_set (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_label_set($an_id, (const char *) $a_text);"
		end

	label_get (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_label_get($an_id);"
		end

	label_set_wrap_width (an_id, a_characters: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_label_set_wrap_width($an_id, $a_characters);"
		end

	button (a_text: POINTER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_button((const char *) $a_text);"
		end

	button_set (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_button_set($an_id, (const char *) $a_text);"
		end

	button_get (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_button_get($an_id);"
		end

	field: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_field();"
		end

	field_set (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_field_set($an_id, (const char *) $a_text);"
		end

	field_get (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_field_get($an_id);"
		end

	field_set_placeholder (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_field_set_placeholder($an_id, (const char *) $a_text);"
		end

	check_box (a_text: POINTER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_check_box((const char *) $a_text);"
		end

	check_box_set (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_check_box_set($an_id, $a_on ? 1 : 0);"
		end

	check_box_is_checked (an_id: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_check_box_is_checked($an_id) ? EIF_TRUE : EIF_FALSE;"
		end

	check_box_set_text (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_check_box_set_text($an_id, (const char *) $a_text);"
		end

	check_box_text (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_check_box_text($an_id);"
		end

	text_area: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_text_area();"
		end

	text_area_set (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_text_area_set($an_id, (const char *) $a_text);"
		end

	text_area_get (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_text_area_get($an_id);"
		end

	text_area_set_read_only (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_text_area_set_read_only($an_id, $a_on ? 1 : 0);"
		end

	tabs: INTEGER
			-- A GtkNotebook (first pass by MACMINI; PROD to verify on GTK).
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_tabs();"
		end

	tabs_extend (a_tabs, a_page: INTEGER; a_title: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_tabs_extend($a_tabs, $a_page, (const char *) $a_title);"
		end

	tabs_select (a_tabs, a_page: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_tabs_select($a_tabs, $a_page);"
		end

	tabs_selected (a_tabs: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_tabs_selected($a_tabs);"
		end

	tabs_set_title (a_tabs, a_page: INTEGER; a_title: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_tabs_set_title($a_tabs, $a_page, (const char *) $a_title);"
		end

	list: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_list();"
		end

	list_extend (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_list_extend($an_id, (const char *) $a_text);"
		end

	list_wipe_out (an_id: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_list_wipe_out($an_id);"
		end

	list_select (an_id, a_row: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_list_select($an_id, $a_row);"
		end

	list_selected (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_list_selected($an_id);"
		end

	table (a_titles: POINTER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_table((const char *) $a_titles);"
		end

	table_extend (a_table: INTEGER; a_cells: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_table_extend($a_table, (const char *) $a_cells);"
		end

	table_wipe_out (a_table: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_table_wipe_out($a_table);"
		end

	table_set_multiple (a_table: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_table_set_multiple($a_table, $a_on ? 1 : 0);"
		end

	table_select (a_table, a_row: INTEGER; a_extend: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_table_select($a_table, $a_row, $a_extend ? 1 : 0);"
		end

	table_selected_count (a_table: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_table_selected_count($a_table);"
		end

	table_selected_at (a_table, i: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_table_selected_at($a_table, $i);"
		end

	table_set_sort_indicator (a_table, a_column: INTEGER; a_ascending: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_table_set_sort_indicator($a_table, $a_column, $a_ascending ? 1 : 0);"
		end

	tree: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_tree();"
		end

	tree_add (a_tree, a_node, a_parent: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_tree_add($a_tree, $a_node, $a_parent, (const char *) $a_text);"
		end

	tree_set_expanded (a_tree, a_node: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_tree_set_expanded($a_tree, $a_node, $a_on ? 1 : 0);"
		end

	tree_is_expanded (a_tree, a_node: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_tree_is_expanded($a_tree, $a_node) ? EIF_TRUE : EIF_FALSE;"
		end

	tree_select (a_tree, a_node: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_tree_select($a_tree, $a_node);"
		end

	tree_selected (a_tree: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_tree_selected($a_tree);"
		end

feature -- Common widget state

	set_enabled (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_set_enabled($an_id, $a_on ? 1 : 0);"
		end

	is_enabled (an_id: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_is_enabled($an_id) ? EIF_TRUE : EIF_FALSE;"
		end

	set_visible (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_set_visible($an_id, $a_on ? 1 : 0);"
		end

	is_visible (an_id: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_is_visible($an_id) ? EIF_TRUE : EIF_FALSE;"
		end

	set_direction (an_id, a_direction: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_set_direction($an_id, $a_direction);"
		end

	set_accessible_label (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_set_a11y_label($an_id, (const char *) $a_text);"
		end

	set_accessible_description (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_set_description_a11y($an_id, (const char *) $a_text);"
		end

	widget_x (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_x($an_id);"
		end

	widget_y (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_y($an_id);"
		end

	accessible_role (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_role($an_id);"
		end

feature -- Canvas

	canvas (a_width, a_height: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_canvas($a_width, $a_height);"
		end

	canvas_present (an_id: INTEGER; a_cairo_surface: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_canvas_present($an_id, (void *) $a_cairo_surface);"
		end

	scale_factor (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "{ int s = sg_scale_factor($an_id); return s < 1 ? 1 : s; }"
		end

	scale (an_id: INTEGER): REAL_64
			-- The surface's own scale: fractional under Wayland's fractional scaling (GTK 4.12+).
		external "C inline use %"simple_gui_gtk.h%""
		alias "{ double s = sg_scale($an_id); return s > 0.0 ? s : 1.0; }"
		end

	width (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_width($an_id);"
		end

	height (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_height($an_id);"
		end

feature -- Menus

	menu_new (a_title: POINTER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_menu_new((const char *) $a_title);"
		end

	menu_add_item (a_menu: POINTER; a_text, a_shortcut: POINTER; an_item_id, a_role: INTEGER)
			-- GTK has no application menu: about, settings and quit stay ordinary items where
			-- the program put them; edit roles act on the focused text widget.
		do
			if a_role >= 10 then
				c_menu_add_edit_role (a_menu, a_text, a_role, an_item_id)
			else
				c_menu_add_item (a_menu, a_text, a_shortcut, an_item_id)
			end
		end

	menu_add_separator (a_menu: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_menu_add_separator((void *) $a_menu);"
		end

	context_menu_new: POINTER
			-- A GMenu outside the bar (first pass by MACMINI; PROD to verify on GTK).
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_context_menu_new();"
		end

	widget_set_context_menu (an_id: INTEGER; a_menu: POINTER)
			-- A GtkPopoverMenu shown where a secondary click lands.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_widget_set_context_menu($an_id, (void *) $a_menu);"
		end

	menu_set_title (a_menu: POINTER; a_title: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_menu_set_title((void *) $a_menu, (const char *) $a_title);"
		end

	menu_title (a_menu: POINTER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_menu_title((void *) $a_menu);"
		end

	menu_set_item_text (an_item_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_menu_set_item_text($an_item_id, (const char *) $a_text);"
		end

	menu_item_text (an_item_id: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_menu_item_text($an_item_id);"
		end

feature -- Dialogs

	open_file (a_window: INTEGER; a_title: POINTER; a_save: BOOLEAN; an_extensions: POINTER): POINTER
		external "C blocking inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_open_file($a_window, (const char *) $a_title, $a_save ? 1 : 0, (const char *) $an_extensions);"
		end

	message (a_window: INTEGER; a_title, a_text: POINTER; a_confirm: BOOLEAN): BOOLEAN
		external "C blocking inline use %"simple_gui_gtk.h%""
		alias "return sg_message($a_window, (const char *) $a_title, (const char *) $a_text, $a_confirm ? 1 : 0) ? EIF_TRUE : EIF_FALSE;"
		end

feature -- Appearance

	is_dark: BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_is_dark() ? EIF_TRUE : EIF_FALSE;"
		end

	system_color (a_role: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_system_color($a_role);"
		end

	set_dark (a_on: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_set_dark($a_on ? 1 : 0);"
		end

feature -- Test driver

	test_click (an_id: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_click($an_id);"
		end

	test_click_header (a_table, a_column: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_click_header($a_table, $a_column);"
		end

	test_expand (a_tree, a_node: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_expand($a_tree, $a_node, $a_on ? 1 : 0);"
		end

	test_type (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_type($an_id, (const char *) $a_text);"
		end

	test_choose (an_id, a_row: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_choose($an_id, $a_row);"
		end

	test_menu (an_item_id: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_menu($an_item_id);"
		end

	test_request_close (a_window: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_request_close($a_window);"
		end

	test_context_menu (an_id, an_item_id: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_test_context_menu($an_id, $an_item_id) ? EIF_TRUE : EIF_FALSE;"
		end

	snapshot (an_id: INTEGER; a_path: POINTER): BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_snapshot($an_id, (const char *) $a_path) ? EIF_TRUE : EIF_FALSE;"
		end

	describe_accessibility (a_window: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_describe($a_window);"
		end

feature {NONE} -- C

	c_menu_add_item (a_menu: POINTER; a_text, a_shortcut: POINTER; an_item_id: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_menu_add_item((void *) $a_menu, (const char *) $a_text, (const char *) $a_shortcut, $an_item_id);"
		end

	c_menu_add_edit_role (a_menu: POINTER; a_text: POINTER; a_role, an_item_id: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_menu_add_edit_role((void *) $a_menu, (const char *) $a_text, $a_role, $an_item_id);"
		end

end
