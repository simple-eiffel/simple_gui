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

	dock (a_center: INTEGER): INTEGER
			-- 1r-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_dock($a_center);"
		end

	dock_add (a_dock, a_content, a_side: INTEGER; a_key, a_title: POINTER)
			-- 1r-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dock_add($a_dock, $a_content, $a_side, (const char *) $a_key, (const char *) $a_title);"
		end

	dock_move (a_dock, an_index, a_side, a_position: INTEGER)
			-- 1r-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dock_move($a_dock, $an_index, $a_side, $a_position);"
		end

	dock_remove (a_dock, an_index: INTEGER)
			-- 1r-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dock_remove($a_dock, $an_index);"
		end

	dock_set_title (a_dock, an_index: INTEGER; a_title: POINTER)
			-- 1r-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dock_set_title($a_dock, $an_index, (const char *) $a_title);"
		end

	dock_set_tabbed (a_dock, a_side: INTEGER; a_on: BOOLEAN)
			-- 1r-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dock_set_tabbed($a_dock, $a_side, $a_on);"
		end

	dock_activate (a_dock, an_index: INTEGER)
			-- 1r-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dock_activate($a_dock, $an_index);"
		end

	dock_set_size (a_dock, a_side, a_size: INTEGER)
			-- 1r-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dock_set_size($a_dock, $a_side, $a_size);"
		end

	dock_size (a_dock, a_side: INTEGER): INTEGER
			-- 1r-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_dock_size($a_dock, $a_side);"
		end

	dock_collapse (a_dock, a_side: INTEGER; a_on: BOOLEAN)
			-- 1r-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dock_collapse($a_dock, $a_side, $a_on);"
		end

	dock_show_panel (a_dock, an_index: INTEGER; a_on: BOOLEAN)
			-- 1r-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dock_show_panel($a_dock, $an_index, $a_on);"
		end

	test_drag_dock_edge (a_dock, a_side, a_size: INTEGER)
			-- 1r-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_drag_dock_edge($a_dock, $a_side, $a_size);"
		end

	test_press_dock_strip (a_dock, an_index: INTEGER)
			-- 1r-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_press_dock_strip($a_dock, $an_index);"
		end

	test_click_dock_tab (a_dock, an_index: INTEGER)
			-- 1r-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_click_dock_tab($a_dock, $an_index);"
		end

	dock_float (a_dock, an_index: INTEGER; a_on: BOOLEAN)
			-- 1r-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dock_float($a_dock, $an_index, $a_on);"
		end

	dock_float_frame (a_dock, an_index, a_x, a_y, a_width, a_height: INTEGER)
			-- 1r-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dock_float_frame($a_dock, $an_index, $a_x, $a_y, $a_width, $a_height);"
		end

	dock_float_frame_field (a_dock, an_index, a_field: INTEGER): INTEGER
			-- 1r-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_dock_float_frame_field($a_dock, $an_index, $a_field);"
		end

	dock_set_auto_hide (a_dock, a_side: INTEGER; a_on: BOOLEAN)
			-- 1r-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dock_set_auto_hide($a_dock, $a_side, $a_on);"
		end

	dock_maximize_center (a_dock: INTEGER; a_on: BOOLEAN)
			-- 1r-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dock_maximize_center($a_dock, $a_on);"
		end

	test_float_by_user (a_dock, an_index: INTEGER)
			-- 1r-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_float_by_user($a_dock, $an_index);"
		end

	test_close_floating (a_dock, an_index: INTEGER)
			-- 1r-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_close_floating($a_dock, $an_index);"
		end

	test_drag_panel (a_dock, an_index, a_side, a_position: INTEGER)
			-- 1r-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_drag_panel($a_dock, $an_index, $a_side, $a_position);"
		end

	test_slide_out (a_dock, an_index: INTEGER): BOOLEAN
			-- 1r-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_test_slide_out($a_dock, $an_index);"
		end

	test_toggle_center (a_dock: INTEGER)
			-- 1r-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_toggle_center($a_dock);"
		end

	dock_set_panel_fields (a_dock, an_index: INTEGER; a_short_title, a_description, a_tab_tooltip: POINTER)
			-- 1r-c.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dock_set_panel_fields($a_dock, $an_index, (const char *) $a_short_title, (const char *) $a_description, (const char *) $a_tab_tooltip);"
		end

	dock_set_panel_pill (a_dock, an_index: INTEGER; a_code: POINTER)
			-- 1r-c.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dock_set_panel_pill($a_dock, $an_index, (const char *) $a_code);"
		end

	test_panel_tab_text (a_dock, an_index: INTEGER): POINTER
			-- 1r-c.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_test_panel_tab_text($a_dock, $an_index);"
		end

	test_panel_tab_tooltip (a_dock, an_index: INTEGER): POINTER
			-- 1r-c.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_test_panel_tab_tooltip($a_dock, $an_index);"
		end

	splitter_set_collapsible (a_splitter, a_pane: INTEGER; a_on: BOOLEAN)
			-- 1r-c.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_splitter_set_collapsible($a_splitter, $a_pane, $a_on);"
		end

	splitter_collapse (a_splitter, a_pane: INTEGER; a_on: BOOLEAN)
			-- 1r-c.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_splitter_collapse($a_splitter, $a_pane, $a_on);"
		end

	splitter_is_collapsed (a_splitter, a_pane: INTEGER): BOOLEAN
			-- 1r-c.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_splitter_is_collapsed($a_splitter, $a_pane);"
		end

	test_toggle_splitter_pane (a_splitter, a_pane: INTEGER)
			-- 1r-c.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_toggle_splitter_pane($a_splitter, $a_pane);"
		end

	test_locate_row (an_id, a_row: INTEGER): INTEGER
			-- 1q-c.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_test_locate_row($an_id, $a_row);"
		end

	list_extend_rich (an_id: INTEGER; a_title, a_subtitle, an_icon: POINTER; a_badge, a_flags: INTEGER)
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_list_extend_rich($an_id, (const char *) $a_title, (const char *) $a_subtitle, (const char *) $an_icon, $a_badge, $a_flags);"
		end

	list_set_checked (an_id, a_row: INTEGER; a_on: BOOLEAN)
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_list_set_checked($an_id, $a_row, $a_on);"
		end

	list_is_checked (an_id, a_row: INTEGER): BOOLEAN
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_list_is_checked($an_id, $a_row);"
		end

	list_remove (an_id, a_row: INTEGER)
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_list_remove($an_id, $a_row);"
		end

	list_reorder (an_id: INTEGER; an_order: POINTER)
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_list_reorder($an_id, (const char *) $an_order);"
		end

	list_set_filter (an_id: INTEGER; a_text: POINTER)
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_list_set_filter($an_id, (const char *) $a_text);"
		end

	list_shown_count (an_id: INTEGER): INTEGER
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_list_shown_count($an_id);"
		end

	table_set_column_editor (a_table, a_column, a_kind: INTEGER; a_choices: POINTER)
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_table_set_column_editor($a_table, $a_column, $a_kind, (const char *) $a_choices);"
		end

	table_take_edit (a_table: INTEGER): POINTER
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_table_take_edit($a_table);"
		end

	table_refuse_edit (a_table, a_row, a_column: INTEGER; a_message: POINTER)
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_table_refuse_edit($a_table, $a_row, $a_column, (const char *) $a_message);"
		end

	table_set_filter (a_table: INTEGER; a_text: POINTER; a_columns_mask: INTEGER)
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_table_set_filter($a_table, (const char *) $a_text, $a_columns_mask);"
		end

	table_set_shown_rows (a_table: INTEGER; a_rows: POINTER)
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_table_set_shown_rows($a_table, (const char *) $a_rows);"
		end

	table_shown_count (a_table: INTEGER): INTEGER
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_table_shown_count($a_table);"
		end

	test_check_row (an_id, a_row: INTEGER)
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_check_row($an_id, $a_row);"
		end

	test_close_row (an_id, a_row: INTEGER)
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_close_row($an_id, $a_row);"
		end

	test_edit_cell (a_table, a_row, a_column: INTEGER; a_text: POINTER)
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_edit_cell($a_table, $a_row, $a_column, (const char *) $a_text);"
		end

	test_cancel_edit (a_table, a_row, a_column: INTEGER)
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_cancel_edit($a_table, $a_row, $a_column);"
		end

	test_cell_text (a_table, a_row, a_column: INTEGER): POINTER
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_test_cell_text($a_table, $a_row, $a_column);"
		end

	test_cell_note (a_table: INTEGER): POINTER
			-- 1s.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_test_cell_note($a_table);"
		end

	tabs_set_position (a_tabs, a_position: INTEGER)
			-- 1t.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_tabs_set_position($a_tabs, $a_position);"
		end

	sidebar: INTEGER
			-- 1t.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_sidebar();"
		end

	sidebar_extend (a_sidebar, a_page: INTEGER; a_title: POINTER)
			-- 1t.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_sidebar_extend($a_sidebar, $a_page, (const char *) $a_title);"
		end

	sidebar_add_heading (a_sidebar: INTEGER; a_text: POINTER)
			-- 1t.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_sidebar_add_heading($a_sidebar, (const char *) $a_text);"
		end

	sidebar_set_icon (a_sidebar, i: INTEGER; a_name: POINTER)
			-- 1t.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_sidebar_set_icon($a_sidebar, $i, (const char *) $a_name);"
		end

	sidebar_set_badge (a_sidebar, i: INTEGER; a_text: POINTER)
			-- 1t.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_sidebar_set_badge($a_sidebar, $i, (const char *) $a_text);"
		end

	sidebar_select (a_sidebar, i: INTEGER)
			-- 1t.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_sidebar_select($a_sidebar, $i);"
		end

	sidebar_selected (a_sidebar: INTEGER): INTEGER
			-- 1t.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_sidebar_selected($a_sidebar);"
		end

	sidebar_set_collapsible (a_sidebar: INTEGER; a_on: BOOLEAN)
			-- 1t.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_sidebar_set_collapsible($a_sidebar, $a_on);"
		end

	sidebar_set_collapsed (a_sidebar: INTEGER; a_on: BOOLEAN)
			-- 1t.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_sidebar_set_collapsed($a_sidebar, $a_on);"
		end

	sidebar_is_collapsed (a_sidebar: INTEGER): BOOLEAN
			-- 1t.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_sidebar_is_collapsed($a_sidebar);"
		end

	path_control_set_parts (an_id: INTEGER; a_parts: POINTER)
			-- 1t.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_path_control_set_parts($an_id, (const char *) $a_parts);"
		end

	test_toggle_sidebar (a_sidebar: INTEGER)
			-- 1t.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_toggle_sidebar($a_sidebar);"
		end

	test_page_shown (an_id: INTEGER): INTEGER
			-- 1t.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_test_page_shown($an_id);"
		end

	dialog (a_title: POINTER): INTEGER
			-- 1u.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_dialog((const char *) $a_title);"
		end

	dialog_set_content (a_dialog, a_widget: INTEGER)
			-- 1u.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dialog_set_content($a_dialog, $a_widget);"
		end

	dialog_add_button (a_dialog: INTEGER; a_text: POINTER; a_role: INTEGER): INTEGER
			-- 1u.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_dialog_add_button($a_dialog, (const char *) $a_text, $a_role);"
		end

	dialog_set_button_enabled (a_dialog, n: INTEGER; a_on: BOOLEAN)
			-- 1u.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dialog_set_button_enabled($a_dialog, $n, $a_on);"
		end

	dialog_present (a_dialog, a_parent_window: INTEGER; an_app_modal: BOOLEAN)
			-- 1u.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dialog_present($a_dialog, $a_parent_window, $an_app_modal);"
		end

	dialog_pump (a_dialog: INTEGER)
			-- 1u.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dialog_pump($a_dialog);"
		end

	dialog_close (a_dialog: INTEGER)
			-- 1u.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dialog_close($a_dialog);"
		end

	dialog_is_shown (a_dialog: INTEGER): BOOLEAN
			-- 1u.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_dialog_is_shown($a_dialog);"
		end

	help_show_tip (a_widget: INTEGER; a_text: POINTER)
			-- 1u.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_help_show_tip($a_widget, (const char *) $a_text);"
		end

	test_press_dialog_button (a_dialog, n: INTEGER)
			-- 1u.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_press_dialog_button($a_dialog, $n);"
		end

	test_dialog_key (a_dialog, a_key: INTEGER)
			-- 1u.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_dialog_key($a_dialog, $a_key);"
		end

	test_press_dialog_button_later (a_dialog, n, a_ms: INTEGER)
			-- 1u.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_press_dialog_button_later($a_dialog, $n, $a_ms);"
		end

	test_dialog_button_order (a_dialog: INTEGER): POINTER
			-- 1u.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_test_dialog_button_order($a_dialog);"
		end

	test_press_help (a_window: INTEGER)
			-- 1u.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_press_help($a_window);"
		end

	test_help_tip_shown: POINTER
			-- 1u.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_test_help_tip_shown();"
		end

	code_editor: INTEGER
			-- 1v-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_code_editor();"
		end

	code_set_line_numbers (an_id: INTEGER; a_on: BOOLEAN)
			-- 1v-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_code_set_line_numbers($an_id, $a_on);"
		end

	code_set_indent (an_id, a_tab_width: INTEGER; a_spaces: BOOLEAN)
			-- 1v-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_code_set_indent($an_id, $a_tab_width, $a_spaces);"
		end

	text_line_count (an_id: INTEGER): INTEGER
			-- 1v-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_text_line_count($an_id);"
		end

	text_caret_line (an_id: INTEGER): INTEGER
			-- 1v-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_text_caret_line($an_id);"
		end

	text_caret_column (an_id: INTEGER): INTEGER
			-- 1v-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_text_caret_column($an_id);"
		end

	text_line_text (an_id, n: INTEGER): POINTER
			-- 1v-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_text_line_text($an_id, $n);"
		end

	text_go_to_line (an_id, n: INTEGER)
			-- 1v-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_text_go_to_line($an_id, $n);"
		end

	text_replace_range (an_id, a_start, an_end: INTEGER; a_text: POINTER)
			-- 1v-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_text_replace_range($an_id, $a_start, $an_end, (const char *) $a_text);"
		end

	test_type_into_code (an_id: INTEGER; a_text: POINTER)
			-- 1v-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_type_into_code($an_id, (const char *) $a_text);"
		end

	test_caret_to (an_id, a_line, a_column: INTEGER)
			-- 1v-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_caret_to($an_id, $a_line, $a_column);"
	grid_view: INTEGER
			-- 1v-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_grid_view_new();"
		end

	grid_view_extend (an_id: INTEGER; a_title, a_picture, an_icon: POINTER)
			-- 1v-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_grid_view_extend($an_id, (const char *) $a_title, (const char *) $a_picture, (const char *) $an_icon);"
		end

	grid_view_set_subtitle (an_id, i: INTEGER; a_text: POINTER)
			-- 1v-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_grid_view_set_subtitle($an_id, $i, (const char *) $a_text);"
		end

	grid_view_remove (an_id, i: INTEGER)
			-- 1v-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_grid_view_remove($an_id, $i);"
		end

	grid_view_wipe_out (an_id: INTEGER)
			-- 1v-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_grid_view_wipe_out($an_id);"
		end

	grid_view_set_item_size (an_id, a_width, a_height: INTEGER)
			-- 1v-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_grid_view_set_item_size($an_id, $a_width, $a_height);"
		end

	grid_view_set_spacing (an_id, a_spacing: INTEGER)
			-- 1v-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_grid_view_set_spacing($an_id, $a_spacing);"
		end

	grid_view_set_multiple (an_id: INTEGER; a_on: BOOLEAN)
			-- 1v-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_grid_view_set_multiple($an_id, $a_on);"
		end

	grid_view_select (an_id, i: INTEGER; an_extend: BOOLEAN)
			-- 1v-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_grid_view_select($an_id, $i, $an_extend);"
		end

	grid_view_selected_count (an_id: INTEGER): INTEGER
			-- 1v-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_grid_view_selected_count($an_id);"
		end

	grid_view_selected_at (an_id, k: INTEGER): INTEGER
			-- 1v-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_grid_view_selected_at($an_id, $k);"
		end

	grid_view_scroll_to (an_id, i: INTEGER)
			-- 1v-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_grid_view_scroll_to($an_id, $i);"
		end

	grid_view_set_filter (an_id: INTEGER; a_text: POINTER)
			-- 1v-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_grid_view_set_filter($an_id, (const char *) $a_text);"
		end

	grid_view_shown_count (an_id: INTEGER): INTEGER
			-- 1v-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_grid_view_shown_count($an_id);"
		end

	test_activate_item (an_id, i: INTEGER)
			-- 1v-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_activate_item($an_id, $i);"
		end

	test_item_picture_ready (an_id, i: INTEGER): BOOLEAN
			-- 1v-a.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_test_item_picture_ready($an_id, $i);"
		end

	path_control_set_chevrons (an_id: INTEGER; a_on: BOOLEAN)
			-- 1p-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_path_control_set_chevrons($an_id, $a_on);"
		end

	path_control_set_root_icon (an_id: INTEGER; a_name: POINTER)
			-- 1p-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_path_control_set_root_icon($an_id, (const char *) $a_name);"
		end

	widget_focus (an_id: INTEGER)
			-- 1p-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_widget_focus($an_id);"
		end

	test_press_chevron (an_id, a_part: INTEGER)
			-- 1p-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_press_chevron($an_id, $a_part);"
		end

	test_press_path_space (an_id: INTEGER)
			-- 1p-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_press_path_space($an_id);"
		end

	test_field_escape (an_id: INTEGER)
			-- 1p-b.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_field_escape($an_id);"
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

	window_set_toolbar (a_window, a_toolbar: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_window_set_toolbar($a_window, $a_toolbar);"
		end

	window_set_status_bar (a_window, a_bar: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_window_set_status_bar($a_window, $a_bar);"
		end

	dropdown: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_dropdown();"
		end

	dropdown_extend (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dropdown_extend($an_id, (const char *) $a_text);"
		end

	dropdown_wipe_out (an_id: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dropdown_wipe_out($an_id);"
		end

	dropdown_select (an_id, a_row: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dropdown_select($an_id, $a_row);"
		end

	dropdown_selected (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_dropdown_selected($an_id);"
		end

	spin_box (a_min, a_max: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_spin_box($a_min, $a_max);"
		end

	spin_box_set_value (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_spin_box_set_value($an_id, $a_value);"
		end

	spin_box_value (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_spin_box_value($an_id);"
		end

	spin_box_set_step (an_id, a_step: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_spin_box_set_step($an_id, $a_step);"
		end

	progress_bar: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_progress_bar();"
		end

	progress_bar_set (an_id, a_percent: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_progress_bar_set($an_id, $a_percent);"
		end

	progress_bar_value (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_progress_bar_value($an_id);"
		end

	toolbar: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_toolbar();"
		end

	toolbar_extend (a_toolbar, a_button: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_toolbar_extend($a_toolbar, $a_button);"
		end

	toolbar_add_separator (a_toolbar: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_toolbar_add_separator($a_toolbar);"
		end

	status_bar: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_status_bar();"
		end

	status_bar_set_text (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_status_bar_set_text($an_id, (const char *) $a_text);"
		end

	status_bar_text (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_status_bar_text($an_id);"
		end

	test_set_number (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_set_number($an_id, $a_value);"
		end

	radio_group (a_vertical: BOOLEAN): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_radio_group($a_vertical ? 0 : 1);"
		end

	radio_group_extend (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_choices_extend($an_id, (const char *) $a_text);"
		end

	radio_group_select (an_id, i: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_choices_select($an_id, $i);"
		end

	radio_group_selected (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_choices_selected($an_id);"
		end

	segmented: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_segmented();"
		end

	segmented_extend (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_choices_extend($an_id, (const char *) $a_text);"
		end

	segmented_select (an_id, i: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_choices_select($an_id, $i);"
		end

	segmented_selected (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_choices_selected($an_id);"
		end

	slider (a_min, a_max: INTEGER; a_vertical: BOOLEAN): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "int id = sg_slider($a_min, $a_max); if ($a_vertical) { gtk_orientable_set_orientation(GTK_ORIENTABLE(sg_w[id]), GTK_ORIENTATION_VERTICAL); gtk_widget_set_vexpand(sg_w[id], TRUE); gtk_widget_set_hexpand(sg_w[id], FALSE); } return id;"
		end

	slider_set_value (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_slider_set_value($an_id, $a_value);"
		end

	slider_value (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_slider_value($an_id);"
		end

	slider_set_step (an_id, a_step: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_slider_set_step($an_id, $a_step);"
		end

	switch: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_switch();"
		end

	switch_set (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_switch_set($an_id, $a_on ? 1 : 0);"
		end

	switch_is_on (an_id: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_switch_is_on($an_id) ? EIF_TRUE : EIF_FALSE;"
		end

	date_picker: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "GDateTime *now = g_date_time_new_now_local(); int id = sg_date_picker(g_date_time_get_year(now), g_date_time_get_month(now), g_date_time_get_day_of_month(now)); g_date_time_unref(now); return id;"
		end

	time_picker: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "GDateTime *now = g_date_time_new_now_local(); int id = sg_time_picker(g_date_time_get_hour(now), g_date_time_get_minute(now)); g_date_time_unref(now); return id;"
		end

	date_picker_set (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_date_or_time_set($an_id, $a_value);"
		end

	date_picker_value (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_date_or_time_value($an_id);"
		end

	color_chooser: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_color_chooser(0);"
		end

	color_chooser_set (an_id, a_rgb: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_color_set($an_id, $a_rgb);"
		end

	color_chooser_value (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_color_value($an_id);"
		end

	scroll_area: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_scroll_area();"
		end

	scroll_area_set_content (an_id, a_child: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_single_set_content($an_id, $a_child);"
		end

	scroll_area_scroll_to (an_id, a_x, a_y: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_scroll_area_scroll_to($an_id, $a_x, $a_y);"
		end

	image: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_image();"
		end

	image_set_file (an_id: INTEGER; a_path: POINTER): BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_image_set_file($an_id, (const char *) $a_path) ? EIF_TRUE : EIF_FALSE;"
		end

	image_set_bytes (an_id: INTEGER; a_bytes: POINTER; a_count: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_image_set_bytes($an_id, (const unsigned char *) $a_bytes, $a_count) ? EIF_TRUE : EIF_FALSE;"
		end

	separator (a_vertical: BOOLEAN): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_separator($a_vertical ? 1 : 0);"
		end

	group_box (a_title: POINTER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_group_box((const char *) $a_title);"
		end

	group_box_set_title (an_id: INTEGER; a_title: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_group_box_set_title($an_id, (const char *) $a_title);"
		end

	group_box_set_content (an_id, a_child: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_single_set_content($an_id, $a_child);"
		end

	expander (a_title: POINTER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_expander((const char *) $a_title);"
		end

	expander_set_title (an_id: INTEGER; a_title: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_expander_set_title($an_id, (const char *) $a_title);"
		end

	expander_set_content (an_id, a_child: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_single_set_content($an_id, $a_child);"
		end

	expander_set_expanded (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_expander_set_expanded($an_id, $a_on ? 1 : 0);"
		end

	expander_is_expanded (an_id: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_expander_is_expanded($an_id) ? EIF_TRUE : EIF_FALSE;"
		end

	combo_box: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_combo_box();"
		end

	combo_box_extend (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_combo_extend($an_id, (const char *) $a_text);"
		end

	combo_box_wipe_out (an_id: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_combo_wipe_out($an_id);"
		end

	combo_box_set_text (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_combo_set_text($an_id, (const char *) $a_text);"
		end

	combo_box_text (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_combo_text($an_id);"
		end

	tree_table (a_titles: POINTER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_tree_table((const char *) $a_titles);"
		end

	tree_table_set_cell (an_id, a_node, a_column: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_tree_table_set_cell($an_id, $a_node, $a_column, (const char *) $a_text);"
		end

	set_tooltip (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_set_tooltip($an_id, (const char *) $a_text);"
		end

	timer_start (a_timer_id, a_ms: INTEGER; a_repeat: BOOLEAN)
			-- 1m: a GLib timeout (sg_timer_start), and the ten features after it.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_timer_start($a_timer_id, $a_ms, $a_repeat ? 1 : 0);"
		end

	timer_stop (a_timer_id: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_timer_stop($a_timer_id);"
		end

	clipboard_text: POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_clipboard_text();"
		end

	clipboard_set_text (a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_clipboard_set_text((const char *) $a_text);"
		end

	window_add_shortcut (a_window: INTEGER; a_shortcut: POINTER; a_shortcut_id: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_window_add_shortcut($a_window, (const char *) $a_shortcut, $a_shortcut_id);"
		end

	window_set_fullscreen (a_window: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_window_set_fullscreen($a_window, $a_on ? 1 : 0);"
		end

	window_is_fullscreen (a_window: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_window_is_fullscreen($a_window) != 0;"
		end

	follow_system_appearance
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_follow_system_appearance();"
		end

	list_scroll_to_row (an_id, a_row: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_list_scroll_to_row($an_id, $a_row);"
		end

	test_press_shortcut (a_window: INTEGER; a_shortcut: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_press_shortcut($a_window, (const char *) $a_shortcut);"
		end

	spinner: INTEGER
			-- 1o: a GtkSpinner.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_spinner();"
		end

	spinner_set (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_spinner_set($an_id, $a_on ? 1 : 0);"
		end

	info_bar (a_kind: INTEGER; a_message: POINTER): INTEGER
			-- A box styled by kind, with an icon, the message, action buttons and a close button.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_info_bar($a_kind, (const char *) $a_message);"
		end

	info_bar_set (an_id, a_kind: INTEGER; a_message: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_info_bar_set($an_id, $a_kind, (const char *) $a_message);"
		end

	info_bar_add_action (an_id: INTEGER; a_text: POINTER; a_number: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_info_bar_add_action($an_id, (const char *) $a_text, $a_number);"
		end

	info_bar_set_closable (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_info_bar_set_closable($an_id, $a_on ? 1 : 0);"
		end

	window_show_toast (a_window: INTEGER; a_message, an_action_text: POINTER; a_toast_id: INTEGER)
			-- A pill at the bottom of the window's overlay, gone after 4 s (8 s with an action).
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_window_show_toast($a_window, (const char *) $a_message, (const char *) $an_action_text, $a_toast_id);"
		end

	notify (a_title, a_body: POINTER; a_notification_id: INTEGER)
			-- org.freedesktop.Notifications over D-Bus; quiet when there is no server.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_notify((const char *) $a_title, (const char *) $a_body, $a_notification_id);"
		end

	test_info_bar_press (an_id, a_number: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_info_bar_press($an_id, $a_number);"
		end

	test_toast_shown (a_window: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_test_toast_shown($a_window);"
		end

	test_toast_press (a_window: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_toast_press($a_window);"
		end

	button_set_icon (an_id: INTEGER; a_name: POINTER)
			-- 1n: an Adwaita symbolic icon beside the label (sg_button_build), and the eight after it.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_button_set_icon($an_id, (const char *) $a_name);"
		end

	button_set_style (an_id, a_style: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_button_set_style($an_id, $a_style);"
		end

	button_set_busy (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_button_set_busy($an_id, $a_on ? 1 : 0);"
		end

	menu_set_item_icon (an_item_id: INTEGER; a_name: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_menu_set_item_icon($an_item_id, (const char *) $a_name);"
		end

	tabs_set_page_icon (a_tabs, a_page: INTEGER; a_name: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_tabs_set_page_icon($a_tabs, $a_page, (const char *) $a_name);"
		end

	tabs_set_page_badge (a_tabs, a_page: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_tabs_set_page_badge($a_tabs, $a_page, (const char *) $a_text);"
		end

	widget_set_badge (an_id: INTEGER; a_text: POINTER; a_kind: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_widget_set_badge($an_id, (const char *) $a_text, $a_kind);"
		end

	test_button_icon (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_test_button_icon($an_id);"
		end

	test_badge_shown (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_test_badge_shown($an_id);"
		end

	password_field: INTEGER
			-- 1p: a GtkEntry hiding its text, with an eye icon.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_password_field();"
		end

	password_set_revealed (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_password_set_revealed($an_id, $a_on ? 1 : 0);"
		end

	password_is_revealed (an_id: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_password_is_revealed($an_id) ? EIF_TRUE : EIF_FALSE;"
		end

	caps_lock_on: BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_caps_lock_on() ? EIF_TRUE : EIF_FALSE;"
		end

	field_set_error (an_id: INTEGER; a_message: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_field_set_error($an_id, (const char *) $a_message);"
		end

	field_set_suggestions (an_id: INTEGER; a_joined: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_field_set_suggestions($an_id, (const char *) $a_joined);"
		end

	dropdown_add_header (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dropdown_add_header($an_id, (const char *) $a_text);"
		end

	dropdown_add_separator (an_id: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_dropdown_add_separator($an_id);"
		end

	date_time_picker (a_kind: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_date_time_picker($a_kind);"
		end

	date_time_set (an_id, a_date, a_time: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_date_time_set($an_id, $a_date, $a_time);"
		end

	date_time_date (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_date_time_date($an_id);"
		end

	date_time_time (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_date_time_time($an_id);"
		end

	range_slider (a_min, a_max: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_range_slider($a_min, $a_max);"
		end

	range_slider_set (an_id, a_low, a_high: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_range_slider_set($an_id, $a_low, $a_high);"
		end

	range_slider_low (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_range_slider_low($an_id);"
		end

	range_slider_high (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_range_slider_high($an_id);"
		end

	range_slider_set_step (an_id, a_step: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_range_slider_set_step($an_id, $a_step);"
		end

	list_set_multiple (an_id: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_list_set_multiple($an_id, $a_on ? 1 : 0);"
		end

	list_selected_count (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_list_selected_count($an_id);"
		end

	list_selected_at (an_id, i: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_list_selected_at($an_id, $i);"
		end

	test_toggle_reveal (an_id: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_toggle_reveal($an_id);"
		end

	test_pick_suggestion (an_id, i: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_pick_suggestion($an_id, $i);"
		end

	test_end_editing (an_id: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_end_editing($an_id);"
		end

	test_set_date_time (an_id, a_date, a_time: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_set_date_time($an_id, $a_date, $a_time);"
		end

	test_slide_range (an_id, a_low, a_high: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_slide_range($an_id, $a_low, $a_high);"
		end

	test_extend_list_selection (an_id, a_row: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_extend_list_selection($an_id, $a_row);"
		end

	field_error_shown (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_field_error_shown($an_id);"
		end

	widget_set_pick (an_id, a_mode: INTEGER; a_is_source, a_by_row: BOOLEAN)
			-- 1q: a GtkDragSource and a secondary-click gesture on the widget (made once).
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_widget_set_pick($an_id, $a_mode, $a_is_source ? 1 : 0, $a_by_row ? 1 : 0);"
		end

	widget_set_drop_target (an_id: INTEGER; an_internal, a_files, a_text: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_widget_set_drop_target($an_id, $an_internal ? 1 : 0, $a_files ? 1 : 0, $a_text ? 1 : 0);"
		end

	pick_targets (a_source: INTEGER; a_ids: POINTER; a_count: INTEGER; a_labels: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_pick_targets($a_source, (const int *) $a_ids, $a_count, (const char *) $a_labels);"
		end

	pick_cancel
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_pick_cancel();"
		end

	widget_set_drag_out (an_id: INTEGER; a_text, a_paths: POINTER)
			-- 1q-c.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_widget_set_drag_out($an_id, (const char *) $a_text, (const char *) $a_paths);"
		end

	test_drag_out (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_test_drag_out($an_id);"
		end

	test_drag_out_ended (an_id, a_how: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_drag_out_ended($an_id, $a_how);"
		end

	take_dropped_paths (an_id: INTEGER): POINTER
			-- 1q-b: kept until the next drop.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_take_dropped_paths($an_id);"
		end

	take_dropped_text (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_take_dropped_text($an_id);"
		end

	test_drop_files (an_id: INTEGER; a_paths: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_drop_files($an_id, (const char *) $a_paths);"
		end

	test_drop_text (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_drop_text($an_id, (const char *) $a_text);"
		end

	test_pick (a_source, a_row: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_pick($a_source, $a_row);"
		end

	test_drop (a_target, a_row: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_drop($a_target, $a_row);"
		end

	test_cancel_pick
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_cancel_pick();"
		end

	test_is_accepting (a_target: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_test_is_accepting($a_target) ? EIF_TRUE : EIF_FALSE;"
		end

	pill_set (an_id: INTEGER; a_code, a_tip: POINTER; a_corner: INTEGER)
			-- 1l: a label in the window's overlay (sg_pill_set).
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_pill_set($an_id, (const char *) $a_code, (const char *) $a_tip, $a_corner);"
		end

	pill_clear (an_id: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_pill_clear($an_id);"
		end

	pills_show (a_shown: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_pills_show($a_shown ? 1 : 0);"
		end

	pill_tip_shown (an_id: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_pill_tip_shown($an_id);"
		end

	save_file_named (a_window: INTEGER; a_title, an_extensions, a_name: POINTER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_save_file_named($a_window, (const char *) $a_title, (const char *) $an_extensions, (const char *) $a_name);"
		end

	choose_folder (a_window: INTEGER; a_title: POINTER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_choose_folder($a_window, (const char *) $a_title);"
		end

	ask (a_window: INTEGER; a_title, a_text: POINTER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_ask($a_window, (const char *) $a_title, (const char *) $a_text);"
		end

	test_slide (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_set_value($an_id, $a_value);"
		end

	test_set_date (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_set_value($an_id, $a_value);"
		end

	test_set_color (an_id, a_rgb: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_set_value($an_id, $a_rgb);"
		end

	test_type_combo (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_type_combo($an_id, (const char *) $a_text);"
		end

	test_toggle_expander (an_id: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "gtk_expander_set_expanded(GTK_EXPANDER(sg_w[$an_id]), !gtk_expander_get_expanded(GTK_EXPANDER(sg_w[$an_id])));"
		end

	test_auto_cancel_dialogs (a_ms: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_auto_cancel_dialogs($a_ms);"
		end

	calendar: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_calendar();"
		end

	menu_button (a_text: POINTER; a_split: BOOLEAN): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_menu_button((const char *) $a_text, $a_split ? 1 : 0);"
		end

	menu_button_set_menu (an_id: INTEGER; a_menu: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_menu_button_set_menu($an_id, (void *) $a_menu);"
		end

	level_bar (a_min, a_max: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_level_bar($a_min, $a_max);"
		end

	level_bar_set (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_level_bar_set($an_id, $a_value);"
		end

	level_bar_value (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_level_bar_value($an_id);"
		end

	level_bar_set_warning (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_level_bar_set_warning($an_id, $a_value);"
		end

	level_bar_set_critical (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_level_bar_set_critical($an_id, $a_value);"
		end

	popover: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_popover();"
		end

	popover_set_content (an_id, a_child: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_popover_set_content($an_id, $a_child);"
		end

	popover_show_at (an_id, an_anchor: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_popover_show_at($an_id, $an_anchor);"
		end

	popover_hide (an_id: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_popover_hide($an_id);"
		end

	popover_is_shown (an_id: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_popover_is_shown($an_id) ? EIF_TRUE : EIF_FALSE;"
		end

	search_field: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_search_field();"
		end

	token_field: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_token_field();"
		end

	token_field_extend (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_token_field_extend($an_id, (const char *) $a_text);"
		end

	token_field_remove (an_id, i: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_token_field_remove($an_id, $i);"
		end

	token_field_wipe_out (an_id: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_token_field_wipe_out($an_id);"
		end

	token_field_count (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_token_field_count($an_id);"
		end

	token_field_item (an_id, i: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_token_field_item($an_id, $i);"
		end

	path_control: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_path_control();"
		end

	path_control_set (an_id: INTEGER; a_path: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_path_control_set($an_id, (const char *) $a_path);"
		end

	path_control_count (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_path_control_count($an_id);"
		end

	path_control_part (an_id, i: INTEGER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_path_control_part($an_id, $i);"
		end

	rating (a_maximum: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_rating($a_maximum);"
		end

	rating_set (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_rating_set($an_id, $a_value);"
		end

	rating_value (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_rating_value($an_id);"
		end

	rich_text_area: INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_rich_text_area();"
		end

	rich_text_set_trait (an_id, a_start, an_end, a_trait: INTEGER; a_on: BOOLEAN)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_rich_text_set_trait($an_id, $a_start, $an_end, $a_trait, $a_on ? 1 : 0);"
		end

	rich_text_set_color (an_id, a_start, an_end, a_rgb: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_rich_text_set_color($an_id, $a_start, $an_end, $a_rgb);"
		end

	rich_text_set_size (an_id, a_start, an_end: INTEGER; a_points: REAL_64)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_rich_text_set_size($an_id, $a_start, $an_end, $a_points);"
		end

	rich_text_trait_at (an_id, i, a_trait: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_rich_text_trait_at($an_id, $i, $a_trait) ? EIF_TRUE : EIF_FALSE;"
		end

	rich_text_color_at (an_id, i: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_rich_text_color_at($an_id, $i);"
		end

	rich_text_size_at (an_id, i: INTEGER): REAL_64
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_rich_text_size_at($an_id, $i);"
		end

	rich_text_selection_start (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_rich_text_selection_start($an_id);"
		end

	rich_text_selection_end (an_id: INTEGER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_rich_text_selection_end($an_id);"
		end

	rich_text_select (an_id, a_start, an_end: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_rich_text_select($an_id, $a_start, $an_end);"
		end

	ask_text (a_window: INTEGER; a_title, a_prompt, an_initial: POINTER): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_ask_text($a_window, (const char *) $a_title, (const char *) $a_prompt, (const char *) $an_initial);"
		end

	confirm_with_check (a_window: INTEGER; a_title, a_text, a_check: POINTER): INTEGER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_confirm_with_check($a_window, (const char *) $a_title, (const char *) $a_text, (const char *) $a_check);"
		end

	choose_font (a_window: INTEGER; a_title, a_family: POINTER; a_points: REAL_64; a_bold, an_italic: BOOLEAN): POINTER
		external "C inline use %"simple_gui_gtk.h%""
		alias "return (EIF_POINTER) sg_choose_font($a_window, (const char *) $a_title, (const char *) $a_family, $a_points, $a_bold ? 1 : 0, $an_italic ? 1 : 0);"
		end

	show_about (a_name, a_version, a_copyright, a_comments: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_show_about((const char *) $a_name, (const char *) $a_version, (const char *) $a_copyright, (const char *) $a_comments);"
		end

	test_dismiss_popover (an_id: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_dismiss_popover($an_id);"
		end

	test_type_tokens (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_type_tokens($an_id, (const char *) $a_text);"
		end

	test_rate (an_id, a_value: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_rate($an_id, $a_value);"
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

	table_set_source (a_table, a_count: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_table_set_source($a_table, $a_count);"
		end

	table_set_row (a_table, a_row: INTEGER; a_cells: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_table_set_row($a_table, $a_row, (const char *) $a_cells);"
		end

	table_set_row_count (a_table, a_count: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_table_set_row_count($a_table, $a_count);"
		end

	table_forget_rows (a_table: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_table_forget_rows($a_table);"
		end

	table_forget_row (a_table, a_row: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_table_forget_row($a_table, $a_row);"
		end

	table_scroll_to (a_table, a_row: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_table_scroll_to($a_table, $a_row);"
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

	tree_move (a_tree, a_node, a_parent, a_position: INTEGER)
			-- 1q-c.
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_tree_move($a_tree, $a_node, $a_parent, $a_position);"
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

	drawn (a_width, a_height: INTEGER): INTEGER
			-- 1i: a drawn view (sg_drawn), and the six features after it.
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_drawn($a_width, $a_height);"
		end

	drawn_present (an_id: INTEGER; a_surface: POINTER; a_width, a_height: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_drawn_present($an_id, (void *) $a_surface, $a_width, $a_height);"
		end

	drawn_set_cursor (an_id, a_kind: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_drawn_set_cursor($an_id, $a_kind);"
		end

	drawn_set_ticks (an_id, a_tick_ms, a_fast_ms: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_drawn_set_ticks($an_id, $a_tick_ms, $a_fast_ms);"
		end

	drawn_arm_dwell (an_id, a_ms, a_serial: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_drawn_arm_dwell($an_id, $a_ms, $a_serial);"
		end

	drawn_set_description (an_id: INTEGER; a_text: POINTER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_drawn_set_description($an_id, (const char *) $a_text);"
		end

	test_drawn_event (an_id, a_type, a_a, a_b, a_c: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_push5($a_type, $an_id, $a_a, $a_b, $a_c);"
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

	test_focus (an_id: INTEGER)
		external "C inline use %"simple_gui_gtk.h%""
		alias "sg_test_focus($an_id);"
		end

	test_edit_enabled (a_role: INTEGER): BOOLEAN
		external "C inline use %"simple_gui_gtk.h%""
		alias "return sg_test_edit_enabled($a_role) ? EIF_TRUE : EIF_FALSE;"
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
