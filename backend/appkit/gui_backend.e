note
	description: "[
		simple_gui's AppKit backend (macOS). Each feature is one call into
		Clib/simple_gui_appkit.h. Externals that WAIT (the pump and the dialogs) are
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
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_init((const char *) $a_name, (const char *) $a_id) ? EIF_TRUE : EIF_FALSE;"
		end

	is_gui_thread: BOOLEAN
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_is_gui_thread() ? EIF_TRUE : EIF_FALSE;"
		end

	pump (a_ms: INTEGER)
		external "C blocking inline use %"simple_gui_appkit.h%""
		alias "sga_pump($a_ms);"
		end

	pump_until_idle (a_ms: INTEGER)
		external "C blocking inline use %"simple_gui_appkit.h%""
		alias "sga_pump_until_idle($a_ms);"
		end

	start_heartbeat (a_ms: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_start_heartbeat($a_ms);"
		end

	wake
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_wake();"
		end

	next (a_type, an_id, a_a, a_b, a_c: TYPED_POINTER [INTEGER]): BOOLEAN
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_next((int *) $a_type, (int *) $an_id, (int *) $a_a, (int *) $a_b, (int *) $a_c) ? EIF_TRUE : EIF_FALSE;"
		end

feature -- Windows and containers

	window (a_title: POINTER; a_width, a_height: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_window((const char *) $a_title, $a_width, $a_height);"
		end

	window_set_content (a_window, a_child: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_window_set_content($a_window, $a_child);"
		end

	window_set_toolbar (a_window, a_toolbar: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_window_set_toolbar($a_window, $a_toolbar);"
		end

	window_set_status_bar (a_window, a_bar: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_window_set_status_bar($a_window, $a_bar);"
		end

	window_show (a_window: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_window_show($a_window);"
		end

	window_close (a_window: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_window_close($a_window);"
		end

	window_set_title (a_window: INTEGER; a_title: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_window_set_title($a_window, (const char *) $a_title);"
		end

	window_install_shortcuts (a_window: INTEGER; a_spec: POINTER)
			-- Nothing to do on the Mac: menu items carry their own key equivalents.
		do
		end

	stack (a_vertical: BOOLEAN; a_spacing: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_stack($a_vertical ? 1 : 0, $a_spacing);"
		end

	stack_extend (a_stack, a_child: INTEGER; a_stretch: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_stack_extend($a_stack, $a_child, $a_stretch ? 1 : 0);"
		end

	stack_set_alignment (a_stack, an_alignment: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_stack_set_alignment($a_stack, $an_alignment);"
		end

	stack_align_child (a_stack, a_child, an_alignment: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_stack_align_child($a_stack, $a_child, $an_alignment);"
		end

	grid_set_homogeneous_columns (a_grid: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_grid_set_homogeneous_columns($a_grid, $a_on ? 1 : 0);"
		end

	grid_set_stretching_column (a_grid, a_column: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_grid_set_stretching_column($a_grid, $a_column);"
		end

	stack_set_spacing (a_stack, a_spacing: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_stack_set_spacing($a_stack, $a_spacing);"
		end

	grid: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_grid();"
		end

	grid_put (a_grid, a_child, a_row, a_column, a_rows, a_columns: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_grid_put($a_grid, $a_child, $a_row, $a_column, $a_rows, $a_columns);"
		end

	grid_set_spacing (a_grid, a_row_gap, a_column_gap: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_grid_set_spacing($a_grid, $a_row_gap, $a_column_gap);"
		end

	splitter (a_vertical: BOOLEAN): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_splitter($a_vertical ? 1 : 0);"
		end

	splitter_set_pane (a_splitter, a_pane, a_child: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_splitter_set_pane($a_splitter, $a_pane, $a_child);"
		end

	splitter_position (a_splitter: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_splitter_position($a_splitter);"
		end

	splitter_set_position (a_splitter, a_position: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_splitter_set_position($a_splitter, $a_position);"
		end

feature -- Controls

	label (a_text: POINTER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_label((const char *) $a_text);"
		end

	label_set (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_label_set($an_id, (const char *) $a_text);"
		end

	label_get (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_label_get($an_id);"
		end

	label_set_wrap_width (an_id, a_characters: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_label_set_wrap_width($an_id, $a_characters);"
		end

	button (a_text: POINTER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_button((const char *) $a_text);"
		end

	button_set (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_button_set($an_id, (const char *) $a_text);"
		end

	button_get (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_button_get($an_id);"
		end

	check_box (a_text: POINTER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_check_box((const char *) $a_text);"
		end

	check_box_set (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_check_box_set($an_id, $a_on ? 1 : 0);"
		end

	check_box_is_checked (an_id: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_check_box_is_checked($an_id) ? EIF_TRUE : EIF_FALSE;"
		end

	check_box_set_text (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_check_box_set_text($an_id, (const char *) $a_text);"
		end

	check_box_text (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_check_box_text($an_id);"
		end

	field: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_field();"
		end

	field_set (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_field_set($an_id, (const char *) $a_text);"
		end

	field_get (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_field_get($an_id);"
		end

	field_set_placeholder (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_field_set_placeholder($an_id, (const char *) $a_text);"
		end

	text_area: INTEGER
			-- An NSTextView in a scroll view; the label and role are the text view's.
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_text_area();"
		end

	text_area_set (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_text_area_set($an_id, (const char *) $a_text);"
		end

	text_area_get (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_text_area_get($an_id);"
		end

	text_area_set_read_only (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_text_area_set_read_only($an_id, $a_on ? 1 : 0);"
		end

	tabs: INTEGER
			-- An NSTabView; the shared target is its delegate (page changed, 13).
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_tabs();"
		end

	tabs_extend (a_tabs, a_page: INTEGER; a_title: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_tabs_extend($a_tabs, $a_page, (const char *) $a_title);"
		end

	tabs_select (a_tabs, a_page: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_tabs_select($a_tabs, $a_page);"
		end

	tabs_selected (a_tabs: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_tabs_selected($a_tabs);"
		end

	tabs_set_title (a_tabs, a_page: INTEGER; a_title: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_tabs_set_title($a_tabs, $a_page, (const char *) $a_title);"
		end

	list: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_list();"
		end

	list_extend (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_list_extend($an_id, (const char *) $a_text);"
		end

	list_wipe_out (an_id: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_list_wipe_out($an_id);"
		end

	list_select (an_id, a_row: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_list_select($an_id, $a_row);"
		end

	list_selected (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_list_selected($an_id);"
		end

	table (a_titles: POINTER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_table((const char *) $a_titles);"
		end

	table_extend (a_table: INTEGER; a_cells: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_table_extend($a_table, (const char *) $a_cells);"
		end

	table_wipe_out (a_table: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_table_wipe_out($a_table);"
		end

	table_set_multiple (a_table: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_table_set_multiple($a_table, $a_on ? 1 : 0);"
		end

	table_select (a_table, a_row: INTEGER; a_extend: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_table_select($a_table, $a_row, $a_extend ? 1 : 0);"
		end

	table_set_source (a_table, a_count: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_table_set_source($a_table, $a_count);"
		end

	table_set_row (a_table, a_row: INTEGER; a_cells: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_table_set_row($a_table, $a_row, (const char *) $a_cells);"
		end

	table_set_row_count (a_table, a_count: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_table_set_row_count($a_table, $a_count);"
		end

	table_forget_rows (a_table: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_table_forget_rows($a_table);"
		end

	table_forget_row (a_table, a_row: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_table_forget_row($a_table, $a_row);"
		end

	table_scroll_to (a_table, a_row: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_table_scroll_to($a_table, $a_row);"
		end

	table_selected_count (a_table: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_table_selected_count($a_table);"
		end

	table_selected_at (a_table, i: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_table_selected_at($a_table, $i);"
		end

	table_set_sort_indicator (a_table, a_column: INTEGER; a_ascending: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_table_set_sort_indicator($a_table, $a_column, $a_ascending ? 1 : 0);"
		end

	tree: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_tree();"
		end

	tree_add (a_tree, a_node, a_parent: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_tree_add($a_tree, $a_node, $a_parent, (const char *) $a_text);"
		end

	tree_set_expanded (a_tree, a_node: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_tree_set_expanded($a_tree, $a_node, $a_on ? 1 : 0);"
		end

	tree_is_expanded (a_tree, a_node: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_tree_is_expanded($a_tree, $a_node) ? EIF_TRUE : EIF_FALSE;"
		end

	tree_select (a_tree, a_node: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_tree_select($a_tree, $a_node);"
		end

	tree_selected (a_tree: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_tree_selected($a_tree);"
		end

feature -- Common widget state

	dropdown: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_dropdown();"
		end

	dropdown_extend (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_dropdown_extend($an_id, (const char *) $a_text);"
		end

	dropdown_wipe_out (an_id: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_dropdown_wipe_out($an_id);"
		end

	dropdown_select (an_id, a_row: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_dropdown_select($an_id, $a_row);"
		end

	dropdown_selected (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_dropdown_selected($an_id);"
		end

	spin_box (a_min, a_max: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_spin_box($a_min, $a_max);"
		end

	spin_box_set_value (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_spin_box_set_value($an_id, $a_value);"
		end

	spin_box_value (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_spin_box_value($an_id);"
		end

	spin_box_set_step (an_id, a_step: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_spin_box_set_step($an_id, $a_step);"
		end

	progress_bar: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_progress_bar();"
		end

	progress_bar_set (an_id, a_percent: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_progress_bar_set($an_id, $a_percent);"
		end

	progress_bar_value (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_progress_bar_value($an_id);"
		end

	toolbar: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_toolbar();"
		end

	toolbar_extend (a_toolbar, a_button: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_toolbar_extend($a_toolbar, $a_button);"
		end

	toolbar_add_separator (a_toolbar: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_toolbar_add_separator($a_toolbar);"
		end

	status_bar: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_status_bar();"
		end

	status_bar_set_text (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_status_bar_set_text($an_id, (const char *) $a_text);"
		end

	status_bar_text (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_status_bar_text($an_id);"
		end

	radio_group (a_vertical: BOOLEAN): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_radio_group($a_vertical ? 1 : 0);"
		end

	radio_group_extend (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_radio_group_extend($an_id, (const char *) $a_text);"
		end

	radio_group_select (an_id, i: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_radio_group_select($an_id, $i);"
		end

	radio_group_selected (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_radio_group_selected($an_id);"
		end

	segmented: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_segmented();"
		end

	segmented_extend (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_segmented_extend($an_id, (const char *) $a_text);"
		end

	segmented_select (an_id, i: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_segmented_select($an_id, $i);"
		end

	segmented_selected (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_segmented_selected($an_id);"
		end

	slider (a_min, a_max: INTEGER; a_vertical: BOOLEAN): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_slider($a_min, $a_max, $a_vertical ? 1 : 0);"
		end

	slider_set_value (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_slider_set_value($an_id, $a_value);"
		end

	slider_value (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_slider_value($an_id);"
		end

	slider_set_step (an_id, a_step: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_slider_set_step($an_id, $a_step);"
		end

	switch: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_switch();"
		end

	switch_set (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_switch_set($an_id, $a_on ? 1 : 0);"
		end

	switch_is_on (an_id: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_switch_is_on($an_id) ? EIF_TRUE : EIF_FALSE;"
		end

	date_picker: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_date_picker();"
		end

	time_picker: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_time_picker();"
		end

	date_picker_set (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_date_picker_set($an_id, $a_value);"
		end

	date_picker_value (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_date_picker_value($an_id);"
		end

	color_chooser: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_color_chooser();"
		end

	color_chooser_set (an_id, a_rgb: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_color_chooser_set($an_id, $a_rgb);"
		end

	color_chooser_value (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_color_chooser_value($an_id);"
		end

	scroll_area: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_scroll_area();"
		end

	scroll_area_set_content (an_id, a_child: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_scroll_area_set_content($an_id, $a_child);"
		end

	scroll_area_scroll_to (an_id, a_x, a_y: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_scroll_area_scroll_to($an_id, $a_x, $a_y);"
		end

	image: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_image();"
		end

	image_set_file (an_id: INTEGER; a_path: POINTER): BOOLEAN
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_image_set_file($an_id, (const char *) $a_path) ? EIF_TRUE : EIF_FALSE;"
		end

	image_set_bytes (an_id: INTEGER; a_bytes: POINTER; a_count: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_image_set_bytes($an_id, (const void *) $a_bytes, $a_count) ? EIF_TRUE : EIF_FALSE;"
		end

	separator (a_vertical: BOOLEAN): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_separator($a_vertical ? 1 : 0);"
		end

	group_box (a_title: POINTER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_group_box((const char *) $a_title);"
		end

	group_box_set_title (an_id: INTEGER; a_title: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_group_box_set_title($an_id, (const char *) $a_title);"
		end

	group_box_set_content (an_id, a_child: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_group_box_set_content($an_id, $a_child);"
		end

	expander (a_title: POINTER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_expander((const char *) $a_title);"
		end

	expander_set_title (an_id: INTEGER; a_title: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_expander_set_title($an_id, (const char *) $a_title);"
		end

	expander_set_content (an_id, a_child: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_expander_set_content($an_id, $a_child);"
		end

	expander_set_expanded (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_expander_set_expanded($an_id, $a_on ? 1 : 0);"
		end

	expander_is_expanded (an_id: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_expander_is_expanded($an_id) ? EIF_TRUE : EIF_FALSE;"
		end

	combo_box: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_combo_box();"
		end

	combo_box_extend (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_combo_box_extend($an_id, (const char *) $a_text);"
		end

	combo_box_wipe_out (an_id: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_combo_box_wipe_out($an_id);"
		end

	combo_box_set_text (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_combo_box_set_text($an_id, (const char *) $a_text);"
		end

	combo_box_text (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_combo_box_text($an_id);"
		end

	tree_table (a_titles: POINTER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_tree_table((const char *) $a_titles);"
		end

	tree_table_set_cell (an_id, a_node, a_column: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_tree_table_set_cell($an_id, $a_node, $a_column, (const char *) $a_text);"
		end

	calendar: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_calendar();"
		end

	menu_button (a_text: POINTER; a_split: BOOLEAN): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_menu_button((const char *) $a_text, $a_split ? 1 : 0);"
		end

	menu_button_set_menu (an_id: INTEGER; a_menu: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_menu_button_set_menu($an_id, (void *) $a_menu);"
		end

	level_bar (a_min, a_max: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_level_bar($a_min, $a_max);"
		end

	level_bar_set (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_level_bar_set($an_id, $a_value);"
		end

	level_bar_value (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_level_bar_value($an_id);"
		end

	level_bar_set_warning (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_level_bar_set_warning($an_id, $a_value);"
		end

	level_bar_set_critical (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_level_bar_set_critical($an_id, $a_value);"
		end

	popover: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_popover();"
		end

	popover_set_content (an_id, a_child: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_popover_set_content($an_id, $a_child);"
		end

	popover_show_at (an_id, an_anchor: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_popover_show_at($an_id, $an_anchor);"
		end

	popover_hide (an_id: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_popover_hide($an_id);"
		end

	popover_is_shown (an_id: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_popover_is_shown($an_id) ? EIF_TRUE : EIF_FALSE;"
		end

	search_field: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_search_field();"
		end

	token_field: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_token_field();"
		end

	token_field_extend (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_token_field_extend($an_id, (const char *) $a_text);"
		end

	token_field_remove (an_id, i: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_token_field_remove($an_id, $i);"
		end

	token_field_wipe_out (an_id: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_token_field_wipe_out($an_id);"
		end

	token_field_count (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_token_field_count($an_id);"
		end

	token_field_item (an_id, i: INTEGER): POINTER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_token_field_item($an_id, $i);"
		end

	path_control: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_path_control();"
		end

	path_control_set (an_id: INTEGER; a_path: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_path_control_set($an_id, (const char *) $a_path);"
		end

	path_control_count (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_path_control_count($an_id);"
		end

	path_control_part (an_id, i: INTEGER): POINTER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_path_control_part($an_id, $i);"
		end

	rating (a_maximum: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_rating($a_maximum);"
		end

	rating_set (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_rating_set($an_id, $a_value);"
		end

	rating_value (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_rating_value($an_id);"
		end

	rich_text_area: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_rich_text_area();"
		end

	rich_text_set_trait (an_id, a_start, an_end, a_trait: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_rich_text_set_trait($an_id, $a_start, $an_end, $a_trait, $a_on ? 1 : 0);"
		end

	rich_text_set_color (an_id, a_start, an_end, a_rgb: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_rich_text_set_color($an_id, $a_start, $an_end, $a_rgb);"
		end

	rich_text_set_size (an_id, a_start, an_end: INTEGER; a_points: REAL_64)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_rich_text_set_size($an_id, $a_start, $an_end, $a_points);"
		end

	rich_text_trait_at (an_id, i, a_trait: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_rich_text_trait_at($an_id, $i, $a_trait) ? EIF_TRUE : EIF_FALSE;"
		end

	rich_text_color_at (an_id, i: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_rich_text_color_at($an_id, $i);"
		end

	rich_text_size_at (an_id, i: INTEGER): REAL_64
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_rich_text_size_at($an_id, $i);"
		end

	rich_text_selection_start (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_rich_text_selection_start($an_id);"
		end

	rich_text_selection_end (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_rich_text_selection_end($an_id);"
		end

	rich_text_select (an_id, a_start, an_end: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_rich_text_select($an_id, $a_start, $an_end);"
		end

	drawn (a_width, a_height: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_drawn($a_width, $a_height);"
		end

	drawn_present (an_id: INTEGER; a_surface: POINTER; a_width, a_height: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_drawn_present($an_id, (void *) $a_surface, $a_width, $a_height);"
		end

	drawn_set_cursor (an_id, a_kind: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_drawn_set_cursor($an_id, $a_kind);"
		end

	drawn_set_ticks (an_id, a_tick_ms, a_fast_ms: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_drawn_set_ticks($an_id, $a_tick_ms, $a_fast_ms);"
		end

	drawn_arm_dwell (an_id, a_ms, a_serial: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_drawn_arm_dwell($an_id, $a_ms, $a_serial);"
		end

	drawn_set_description (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_drawn_set_description($an_id, (const char *) $a_text);"
		end

	timer_start (a_timer_id, a_ms: INTEGER; a_repeat: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_timer_start($a_timer_id, $a_ms, $a_repeat ? 1 : 0);"
		end

	timer_stop (a_timer_id: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_timer_stop($a_timer_id);"
		end

	clipboard_text: POINTER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_clipboard_text();"
		end

	clipboard_set_text (a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_clipboard_set_text((const char *) $a_text);"
		end

	window_add_shortcut (a_window: INTEGER; a_shortcut: POINTER; a_shortcut_id: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_window_add_shortcut($a_window, (const char *) $a_shortcut, $a_shortcut_id);"
		end

	window_set_fullscreen (a_window: INTEGER; a_on: BOOLEAN)
		external "C blocking inline use %"simple_gui_appkit.h%""
		alias "sga_window_set_fullscreen($a_window, $a_on ? 1 : 0);"
		end

	window_is_fullscreen (a_window: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_window_is_fullscreen($a_window) ? EIF_TRUE : EIF_FALSE;"
		end

	follow_system_appearance
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_follow_system_appearance();"
		end

	list_scroll_to_row (an_id, a_row: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_list_scroll_to_row($an_id, $a_row);"
		end

	table_scroll_to_row (an_id, a_row: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_table_scroll_to_row($an_id, $a_row);"
		end

	test_press_shortcut (a_window: INTEGER; a_shortcut: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_press_shortcut($a_window, (const char *) $a_shortcut);"
		end

	spinner: INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_spinner();"
		end

	spinner_set (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_spinner_set($an_id, $a_on ? 1 : 0);"
		end

	info_bar (a_kind: INTEGER; a_message: POINTER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_info_bar($a_kind, (const char *) $a_message);"
		end

	info_bar_set (an_id, a_kind: INTEGER; a_message: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_info_bar_set($an_id, $a_kind, (const char *) $a_message);"
		end

	info_bar_add_action (an_id: INTEGER; a_text: POINTER; a_number: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_info_bar_add_action($an_id, (const char *) $a_text, $a_number);"
		end

	info_bar_set_closable (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_info_bar_set_closable($an_id, $a_on ? 1 : 0);"
		end

	window_show_toast (a_window: INTEGER; a_message, an_action_text: POINTER; a_toast_id: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_window_show_toast($a_window, (const char *) $a_message, (const char *) $an_action_text, $a_toast_id);"
		end

	notify (a_title, a_body: POINTER; a_notification_id: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_notify((const char *) $a_title, (const char *) $a_body, $a_notification_id);"
		end

	test_info_bar_press (an_id, a_number: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_info_bar_press($an_id, $a_number);"
		end

	test_toast_shown (a_window: INTEGER): POINTER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_test_toast_shown($a_window);"
		end

	test_toast_press (a_window: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_toast_press($a_window);"
		end

	pill_set (an_id: INTEGER; a_code, a_tip: POINTER; a_corner: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_pill_set($an_id, (const char *) $a_code, (const char *) $a_tip, $a_corner);"
		end

	pill_clear (an_id: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_pill_clear($an_id);"
		end

	pills_show (a_shown: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_pills_show($a_shown ? 1 : 0);"
		end

	pill_tip_shown (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_pill_tip_shown($an_id);"
		end

	set_tooltip (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_set_tooltip($an_id, (const char *) $a_text);"
		end

	set_enabled (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_set_enabled($an_id, $a_on ? 1 : 0);"
		end

	is_enabled (an_id: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_is_enabled($an_id) ? EIF_TRUE : EIF_FALSE;"
		end

	set_visible (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_set_visible($an_id, $a_on ? 1 : 0);"
		end

	is_visible (an_id: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_is_visible($an_id) ? EIF_TRUE : EIF_FALSE;"
		end

	set_direction (an_id, a_direction: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_set_direction($an_id, $a_direction);"
		end

	set_accessible_label (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_set_accessible_label($an_id, (const char *) $a_text);"
		end

	set_accessible_description (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_set_accessible_description($an_id, (const char *) $a_text);"
		end

	widget_x (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_widget_x($an_id);"
		end

	widget_y (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_widget_y($an_id);"
		end

	accessible_role (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_accessible_role($an_id);"
		end

feature -- Canvas

	canvas (a_width, a_height: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_canvas($a_width, $a_height);"
		end

	canvas_present (an_id: INTEGER; a_cairo_surface: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_canvas_present($an_id, (void *) $a_cairo_surface);"
		end

	scale_factor (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "{ int s = sga_scale_factor($an_id); return s < 1 ? 1 : s; }"
		end

	scale (an_id: INTEGER): REAL_64
			-- The window's backingScaleFactor.
		external "C inline use %"simple_gui_appkit.h%""
		alias "{ double s = sga_scale($an_id); return s > 0.0 ? s : 1.0; }"
		end

	width (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_width($an_id);"
		end

	height (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_height($an_id);"
		end

feature -- Menus

	menu_new (a_title: POINTER): POINTER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_menu_new((const char *) $a_title);"
		end

	menu_add_item (a_menu: POINTER; a_text, a_shortcut: POINTER; an_item_id, a_role: INTEGER)
			-- About, settings and quit go to the application menu, as a Mac user expects;
			-- edit roles go through the responder chain to the focused text field.
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_menu_add_item((void *) $a_menu, (const char *) $a_text, (const char *) $a_shortcut, $an_item_id, $a_role);"
		end

	menu_set_title (a_menu: POINTER; a_title: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_menu_set_title((void *) $a_menu, (const char *) $a_title);"
		end

	menu_title (a_menu: POINTER): POINTER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_menu_title((void *) $a_menu);"
		end

	menu_set_item_text (an_item_id: INTEGER; a_text: POINTER)
			-- About and Quit keep the application name: "About <app>" in any language.
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_menu_set_item_text($an_item_id, (const char *) $a_text);"
		end

	menu_item_text (an_item_id: INTEGER): POINTER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_menu_item_text($an_item_id);"
		end

	menu_add_separator (a_menu: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_menu_add_separator((void *) $a_menu);"
		end

	context_menu_new: POINTER
			-- An NSMenu outside the menu bar.
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_context_menu_new();"
		end

	widget_set_context_menu (an_id: INTEGER; a_menu: POINTER)
			-- The view's `menu': right-click, Control-click and a two-finger click show it.
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_widget_set_context_menu($an_id, (void *) $a_menu);"
		end

feature -- Dialogs

	open_file (a_window: INTEGER; a_title: POINTER; a_save: BOOLEAN; an_extensions: POINTER): POINTER
		external "C blocking inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_open_file($a_window, (const char *) $a_title, $a_save ? 1 : 0, (const char *) $an_extensions);"
		end

	message (a_window: INTEGER; a_title, a_text: POINTER; a_confirm: BOOLEAN): BOOLEAN
		external "C blocking inline use %"simple_gui_appkit.h%""
		alias "return sga_message($a_window, (const char *) $a_title, (const char *) $a_text, $a_confirm ? 1 : 0) ? EIF_TRUE : EIF_FALSE;"
		end

	save_file_named (a_window: INTEGER; a_title, an_extensions, a_name: POINTER): POINTER
		external "C blocking inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_save_file_named($a_window, (const char *) $a_title, (const char *) $an_extensions, (const char *) $a_name);"
		end

	choose_folder (a_window: INTEGER; a_title: POINTER): POINTER
		external "C blocking inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_choose_folder($a_window, (const char *) $a_title);"
		end

	ask (a_window: INTEGER; a_title, a_text: POINTER): INTEGER
		external "C blocking inline use %"simple_gui_appkit.h%""
		alias "return sga_ask($a_window, (const char *) $a_title, (const char *) $a_text);"
		end

	ask_text (a_window: INTEGER; a_title, a_prompt, an_initial: POINTER): POINTER
		external "C blocking inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_ask_text($a_window, (const char *) $a_title, (const char *) $a_prompt, (const char *) $an_initial);"
		end

	confirm_with_check (a_window: INTEGER; a_title, a_text, a_check: POINTER): INTEGER
		external "C blocking inline use %"simple_gui_appkit.h%""
		alias "return sga_confirm_with_check($a_window, (const char *) $a_title, (const char *) $a_text, (const char *) $a_check);"
		end

	choose_font (a_window: INTEGER; a_title, a_family: POINTER; a_points: REAL_64; a_bold, an_italic: BOOLEAN): POINTER
		external "C blocking inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_choose_font($a_window, (const char *) $a_title, (const char *) $a_family, $a_points, $a_bold ? 1 : 0, $an_italic ? 1 : 0);"
		end

	show_about (a_name, a_version, a_copyright, a_comments: POINTER)
		external "C blocking inline use %"simple_gui_appkit.h%""
		alias "sga_show_about((const char *) $a_name, (const char *) $a_version, (const char *) $a_copyright, (const char *) $a_comments);"
		end

feature -- Appearance

	is_dark: BOOLEAN
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_is_dark() ? EIF_TRUE : EIF_FALSE;"
		end

	system_color (a_role: INTEGER): INTEGER
			-- NSColor's semantic colors in the current appearance; translucent ones as seen
			-- over the window background.
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_system_color($a_role);"
		end

	set_dark (a_on: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_set_dark($a_on ? 1 : 0);"
		end

feature -- Test driver

	test_click (an_id: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_click($an_id);"
		end

	test_click_header (a_table, a_column: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_click_header($a_table, $a_column);"
		end

	test_expand (a_tree, a_node: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_expand($a_tree, $a_node, $a_on ? 1 : 0);"
		end

	test_type (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_type($an_id, (const char *) $a_text);"
		end

	test_choose (an_id, a_row: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_choose($an_id, $a_row);"
		end

	test_set_number (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_set_number($an_id, $a_value);"
		end

	test_slide (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_slide($an_id, $a_value);"
		end

	test_set_date (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_set_date($an_id, $a_value);"
		end

	test_set_color (an_id, a_rgb: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_set_color($an_id, $a_rgb);"
		end

	test_type_combo (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_type_combo($an_id, (const char *) $a_text);"
		end

	test_toggle_expander (an_id: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_toggle_expander($an_id);"
		end

	test_auto_cancel_dialogs (a_ms: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_auto_cancel_dialogs($a_ms);"
		end

	test_dismiss_popover (an_id: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_dismiss_popover($an_id);"
		end

	test_type_tokens (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_type_tokens($an_id, (const char *) $a_text);"
		end

	test_rate (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_rate($an_id, $a_value);"
		end

	test_drawn_event (an_id, a_type, a_a, a_b, a_c: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_drawn_event($an_id, $a_type, $a_a, $a_b, $a_c);"
		end

	test_menu (an_item_id: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_menu($an_item_id);"
		end

	test_request_close (a_window: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_request_close($a_window);"
		end

	test_focus (an_id: INTEGER)
		external "C inline use %"simple_gui_appkit.h%""
		alias "sga_test_focus($an_id);"
		end

	test_edit_enabled (a_role: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_test_edit_enabled($a_role) ? EIF_TRUE : EIF_FALSE;"
		end

	test_context_menu (an_id, an_item_id: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_test_context_menu($an_id, $an_item_id) ? EIF_TRUE : EIF_FALSE;"
		end

	snapshot (an_id: INTEGER; a_path: POINTER): BOOLEAN
		external "C inline use %"simple_gui_appkit.h%""
		alias "return sga_snapshot($an_id, (const char *) $a_path) ? EIF_TRUE : EIF_FALSE;"
		end

	describe_accessibility (a_window: INTEGER): POINTER
		external "C inline use %"simple_gui_appkit.h%""
		alias "return (EIF_POINTER) sga_describe_accessibility($a_window);"
		end

end
