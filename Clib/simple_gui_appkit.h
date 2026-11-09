/*
 * simple_gui_appkit.h - simple_gui's macOS backend: real AppKit controls driven from
 * Eiffel through a polled queue. One function per GUI_BACKEND_API feature
 * (backend/appkit/gui_backend.e wraps them). Plain C; the Objective-C is in
 * simple_gui_appkit.m, built by Clib/Makefile. Every call runs on the main thread
 * except sga_wake. Ids are allocated here, from 1; 0 means none. Strings are UTF-8;
 * a returned string stays valid until the next call of the same kind.
 *
 * Queue [type, id, a, b, c]: click 1, text changed 2, activate 3, selection 4 (a = row),
 * menu 5 (a = item id), close requested 6, pointer 7 (a = x, b = y, c = kind + button*16 +
 * modifiers*256), key 8 (a = code, b = character, c = modifiers*256), resize 9 (a, b),
 * appearance 10 (a = 1 dark), wake 11, toggled 12 (a = 1 checked), page changed 13 (a = page). Modifiers: 1 shift, 2 control, 4 alt, 8 command.
 * Programmatic changes push no events.
 */
#ifndef SIMPLE_GUI_APPKIT_H
#define SIMPLE_GUI_APPKIT_H

/* Loop */
int sga_init(const char *a_name, const char *a_id);
int sga_is_gui_thread(void);
void sga_pump(int a_ms);
void sga_pump_until_idle(int a_ms);
void sga_start_heartbeat(int a_ms);
void sga_wake(void);
int sga_next(int *a_type, int *a_id, int *a_a, int *a_b, int *a_c);

/* Windows and layout */
int sga_window(const char *a_title, int a_width, int a_height);
void sga_window_set_content(int a_window, int a_child);
void sga_window_show(int a_window);
void sga_window_close(int a_window);
void sga_window_set_title(int a_window, const char *a_title);
int sga_stack(int a_vertical, int a_spacing);
void sga_stack_extend(int a_stack, int a_child, int a_stretch);
void sga_stack_set_spacing(int a_stack, int a_spacing);
void sga_stack_set_alignment(int a_stack, int a_alignment);   /* 0 fill, 1 start, 2 center, 3 end */
void sga_stack_align_child(int a_stack, int a_child, int a_alignment);
int sga_grid(void);
void sga_grid_set_homogeneous_columns(int a_grid, int a_on);
void sga_grid_set_stretching_column(int a_grid, int a_column);   /* 1-based; 0 none */
void sga_grid_put(int a_grid, int a_child, int a_row, int a_column, int a_rows, int a_columns);
void sga_grid_set_spacing(int a_grid, int a_row_gap, int a_column_gap);
int sga_splitter(int a_vertical);   /* side by side unless a_vertical; the first pane holds its size */
void sga_splitter_set_pane(int a_splitter, int a_pane, int a_child);   /* pane 1 leading or top, 2 trailing or bottom */
int sga_splitter_position(int a_splitter);   /* points from the leading edge or the top */
void sga_splitter_set_position(int a_splitter, int a_position);   /* no event; kept until the view has a size */

/* Controls */
int sga_label(const char *a_text);
void sga_label_set(int a_id, const char *a_text);
void sga_label_set_wrap_width(int a_id, int a_characters);   /* > 0: wrap at about that many characters; 0: one line ending in an ellipsis */
const char *sga_label_get(int a_id);
int sga_button(const char *a_text);
void sga_button_set(int a_id, const char *a_text);
const char *sga_button_get(int a_id);
int sga_field(void);
void sga_field_set(int a_id, const char *a_text);
const char *sga_field_get(int a_id);
void sga_field_set_placeholder(int a_id, const char *a_text);
int sga_check_box(const char *a_text);
void sga_check_box_set(int a_id, int a_on);   /* no event */
int sga_check_box_is_checked(int a_id);
void sga_check_box_set_text(int a_id, const char *a_text);
const char *sga_check_box_text(int a_id);
int sga_text_area(void);
void sga_text_area_set(int a_id, const char *a_text);   /* no event */
const char *sga_text_area_get(int a_id);
void sga_text_area_set_read_only(int a_id, int a_on);
int sga_tabs(void);
void sga_tabs_extend(int a_tabs, int a_page, const char *a_title);   /* the first page added is shown */
void sga_tabs_select(int a_tabs, int a_page);   /* 1-based; no event */
int sga_tabs_selected(int a_tabs);   /* 1-based; 0 none */
void sga_tabs_set_title(int a_tabs, int a_page, const char *a_title);
int sga_list(void);
void sga_list_extend(int a_id, const char *a_text);
void sga_list_wipe_out(int a_id);
void sga_list_select(int a_id, int a_row);
int sga_list_selected(int a_id);
int sga_table(const char *a_titles);   /* titles joined by U+001F; selection 4 (a = first row), header clicked 14 (a = column) */
void sga_table_extend(int a_id, const char *a_cells);   /* one row, cells joined by U+001F */
void sga_table_wipe_out(int a_id);   /* no event */
void sga_table_set_multiple(int a_id, int a_on);
void sga_table_select(int a_id, int a_row, int a_extend);   /* 0 clears; no event */
int sga_table_selected_count(int a_id);
int sga_table_selected_at(int a_id, int i);   /* the i-th selected row, ascending */
void sga_table_set_sort_indicator(int a_id, int a_column, int a_ascending);   /* 0: none */
/* Lazy rows (1f): rows come from the program, asked for with event 16 (a = first, b = last). */
void sga_table_set_source(int a_id, int a_count);
void sga_table_set_row(int a_id, int a_row, const char *a_cells);
void sga_table_set_row_count(int a_id, int a_count);
void sga_table_forget_rows(int a_id);
void sga_table_forget_row(int a_id, int a_row);
void sga_table_scroll_to(int a_id, int a_row);
int sga_tree(void);   /* selection 4 (a = node), expansion 15 (a = node, b = 1 expanded) */
void sga_tree_add(int a_id, int a_node, int a_parent, const char *a_text);   /* nodes numbered 1, 2, 3... by the caller; parent 0: a root */
void sga_tree_set_expanded(int a_id, int a_node, int a_on);   /* no event */
int sga_tree_is_expanded(int a_id, int a_node);
void sga_tree_select(int a_id, int a_node);   /* 0 clears; expands the ancestors; no event */
int sga_tree_selected(int a_id);   /* 0: none */

/* Common */
void sga_set_enabled(int a_id, int a_on);
int sga_is_enabled(int a_id);
void sga_set_visible(int a_id, int a_on);
int sga_is_visible(int a_id);
void sga_set_direction(int a_id, int a_direction);   /* 0 auto, 1 left to right, 2 right to left: this widget only */
void sga_set_accessible_label(int a_id, const char *a_text);
void sga_set_accessible_description(int a_id, const char *a_text);
const char *sga_accessible_role(int a_id);
int sga_widget_x(int a_id);   /* own frame, from the content area's top-left, y down, points, after layout */
int sga_widget_y(int a_id);

/* Canvas */
int sga_canvas(int a_width, int a_height);
void sga_canvas_present(int a_id, void *a_cairo_surface);
double sga_scale(int a_id);   /* device pixels per point */
int sga_scale_factor(int a_id);   /* sga_scale rounded up */
int sga_width(int a_id);
int sga_height(int a_id);

/* Menus: roles 0 none, 1 about, 2 settings, 3 quit, 10 undo, 11 redo, 12 cut, 13 copy,
   14 paste, 15 select all. Shortcuts "primary+O", "primary+shift+Z". */
void *sga_menu_new(const char *a_title);
void sga_menu_add_item(void *a_menu, const char *a_text, const char *a_shortcut, int a_item_id, int a_role);
void sga_menu_add_separator(void *a_menu);
void *sga_context_menu_new(void);   /* a menu outside the menu bar */
void sga_widget_set_context_menu(int a_id, void *a_menu);   /* shown on a secondary click */
void sga_menu_set_title(void *a_menu, const char *a_title);
const char *sga_menu_title(void *a_menu);   /* what the menu bar shows */
void sga_menu_set_item_text(int a_item_id, const char *a_text);   /* About and Quit keep the app name */
const char *sga_menu_item_text(int a_item_id);   /* what the item shows */

/* Dialogs (blocking) */
const char *sga_open_file(int a_window, const char *a_title, int a_save, const char *a_extensions);
int sga_message(int a_window, const char *a_title, const char *a_text, int a_confirm);

/* 1g: five more controls */
int sga_dropdown(void);
void sga_dropdown_extend(int a_id, const char *a_text);   /* the first is selected, silently */
void sga_dropdown_wipe_out(int a_id);
void sga_dropdown_select(int a_id, int a_row);   /* silent */
int sga_dropdown_selected(int a_id);   /* 0: none */
int sga_spin_box(int a_min, int a_max);
void sga_spin_box_set_value(int a_id, int a_value);   /* silent */
int sga_spin_box_value(int a_id);
void sga_spin_box_set_step(int a_id, int a_step);
int sga_progress_bar(void);
void sga_progress_bar_set(int a_id, int a_value);   /* 0 .. 100 */
int sga_progress_bar_value(int a_id);
int sga_toolbar(void);
void sga_toolbar_extend(int a_toolbar, int a_button);
void sga_toolbar_add_separator(int a_toolbar);
int sga_status_bar(void);
void sga_status_bar_set_text(int a_id, const char *a_text);
const char *sga_status_bar_text(int a_id);
void sga_window_set_toolbar(int a_window, int a_toolbar);   /* in the title bar; the content keeps its size */
void sga_window_set_status_bar(int a_window, int a_bar);   /* in the window's bottom bar */

/* 1h: the standard controls */
int sga_radio_group(int a_vertical);
void sga_radio_group_extend(int a_id, const char *a_text);   /* the first is chosen, silently */
void sga_radio_group_select(int a_id, int i);   /* silent */
int sga_radio_group_selected(int a_id);
int sga_slider(int a_min, int a_max, int a_vertical);
void sga_slider_set_value(int a_id, int a_value);   /* silent */
int sga_slider_value(int a_id);
void sga_slider_set_step(int a_id, int a_step);
int sga_switch(void);
void sga_switch_set(int a_id, int a_on);   /* silent */
int sga_switch_is_on(int a_id);
int sga_segmented(void);
void sga_segmented_extend(int a_id, const char *a_text);   /* the first is selected, silently */
void sga_segmented_select(int a_id, int i);   /* silent */
int sga_segmented_selected(int a_id);
int sga_date_picker(void);   /* value: year * 10000 + month * 100 + day */
int sga_time_picker(void);   /* value: hour * 60 + minute */
void sga_date_picker_set(int a_id, int a_value);   /* silent; a date or a time picker */
int sga_date_picker_value(int a_id);
int sga_color_chooser(void);   /* 0xRRGGBB, sRGB */
void sga_color_chooser_set(int a_id, int a_rgb);   /* silent */
int sga_color_chooser_value(int a_id);
int sga_scroll_area(void);
void sga_scroll_area_set_content(int a_id, int a_child);
void sga_scroll_area_scroll_to(int a_id, int a_x, int a_y);
int sga_image(void);
int sga_image_set_file(int a_id, const char *a_path);   /* 0: not a picture */
int sga_image_set_bytes(int a_id, const void *a_bytes, int a_count);   /* PNG and the other formats AppKit reads */
int sga_separator(int a_vertical);
int sga_group_box(const char *a_title);
void sga_group_box_set_title(int a_id, const char *a_title);
void sga_group_box_set_content(int a_id, int a_child);
int sga_expander(const char *a_title);   /* collapsed */
void sga_expander_set_content(int a_id, int a_child);
void sga_expander_set_expanded(int a_id, int a_on);   /* silent */
int sga_expander_is_expanded(int a_id);
void sga_expander_set_title(int a_id, const char *a_title);
int sga_combo_box(void);
void sga_combo_box_extend(int a_id, const char *a_text);
void sga_combo_box_wipe_out(int a_id);
void sga_combo_box_set_text(int a_id, const char *a_text);   /* silent */
const char *sga_combo_box_text(int a_id);
const char *sga_save_file_named(int a_window, const char *a_title, const char *a_extensions, const char *a_name);
const char *sga_choose_folder(int a_window, const char *a_title);
int sga_ask(int a_window, const char *a_title, const char *a_text);   /* 1 yes, 2 no, 0 cancel */
void sga_set_tooltip(int a_id, const char *a_text);   /* empty removes it */
int sga_tree_table(const char *a_titles);   /* titles joined by 0x1F; a tree's nodes, with columns */
void sga_tree_table_set_cell(int a_id, int a_node, int a_column, const char *a_text);   /* column 1 is the node's text */

/* 1j: the remaining controls */
int sga_calendar(void);   /* a date picker's value and events, as a month grid */
int sga_menu_button(const char *a_text, int a_split);
void sga_menu_button_set_menu(int a_id, void *a_menu);   /* a GUI_MENU's NSMenu */
int sga_level_bar(int a_min, int a_max);
void sga_level_bar_set(int a_id, int a_value);
int sga_level_bar_value(int a_id);
void sga_level_bar_set_warning(int a_id, int a_value);
void sga_level_bar_set_critical(int a_id, int a_value);
int sga_popover(void);
void sga_popover_set_content(int a_id, int a_child);
void sga_popover_show_at(int a_id, int an_anchor);
void sga_popover_hide(int a_id);   /* silent */
int sga_popover_is_shown(int a_id);
int sga_search_field(void);   /* a field's set and get; Return sends activate (3) */
int sga_token_field(void);
void sga_token_field_extend(int a_id, const char *a_text);   /* silent */
void sga_token_field_remove(int a_id, int i);   /* silent */
void sga_token_field_wipe_out(int a_id);   /* silent */
int sga_token_field_count(int a_id);
const char *sga_token_field_item(int a_id, int i);
int sga_path_control(void);
void sga_path_control_set(int a_id, const char *a_path);
int sga_path_control_count(int a_id);
const char *sga_path_control_part(int a_id, int i);
int sga_rich_text_area(void);   /* a text area's set and get, plus: */
void sga_rich_text_set_trait(int a_id, int a_start, int an_end, int a_trait, int a_on);   /* 1 bold, 2 italic, 3 underline */
void sga_rich_text_set_color(int a_id, int a_start, int an_end, int a_rgb);
void sga_rich_text_set_size(int a_id, int a_start, int an_end, double a_points);
int sga_rich_text_trait_at(int a_id, int i, int a_trait);
int sga_rich_text_color_at(int a_id, int i);   /* -1: the default color */
double sga_rich_text_size_at(int a_id, int i);
int sga_rich_text_selection_start(int a_id);
int sga_rich_text_selection_end(int a_id);   /* start - 1 when empty */
void sga_rich_text_select(int a_id, int a_start, int an_end);
int sga_rating(int a_maximum);
void sga_rating_set(int a_id, int a_value);   /* silent */
int sga_rating_value(int a_id);
const char *sga_ask_text(int a_window, const char *a_title, const char *a_prompt, const char *an_initial);
int sga_confirm_with_check(int a_window, const char *a_title, const char *a_text, const char *a_check);   /* bit 0 OK, bit 1 checked */
const char *sga_choose_font(int a_window, const char *a_title, const char *a_family, double a_points, int a_bold, int a_italic);   /* "family\x1fpoints\x1fbold\x1fitalic" */
void sga_show_about(const char *a_name, const char *a_version, const char *a_copyright, const char *a_comments);

/* 1i: the drawn-widget view (events 18 to 23) */
int sga_drawn(int a_width, int a_height);
void sga_drawn_present(int a_id, void *a_cairo_surface, int a_width, int a_height);   /* the top-left device pixels */
void sga_drawn_set_cursor(int a_id, int a_kind);   /* 0 arrow, 1 I-beam, 2 hand, 3 size W-E, 4 size N-S, 5 cross, 6 wait */
void sga_drawn_set_ticks(int a_id, int a_tick_ms, int a_fast_ms);   /* 0: off */
void sga_drawn_arm_dwell(int a_id, int a_ms, int a_serial);
void sga_drawn_set_description(int a_id, const char *a_text);
void sga_test_drawn_event(int a_id, int a_type, int a, int b, int c);

/* 1l: reference pills, keyed by widget */
void sga_pill_set(int a_id, const char *a_code, const char *a_tip, int a_corner);   /* 1 top-left .. 4 bottom-right; left and right mirror */
void sga_pill_clear(int a_id);
void sga_pills_show(int a_on);
const char *sga_pill_tip_shown(int a_id);   /* for tests: "" unless a user could read it now */

/* Appearance */
int sga_is_dark(void);
void sga_set_dark(int a_on);
int sga_system_color(int a_role);   /* 0xRRGGBB: 1 window background, 2 text, 3 secondary text, 4 accent, 5 selection, 6 separator */

/* Test driver */
void sga_test_click(int a_id);
void sga_test_click_header(int a_id, int a_column);   /* header clicked, as a user */
void sga_test_expand(int a_id, int a_node, int a_on);   /* expansion, as a user */
void sga_test_type(int a_id, const char *a_text);
void sga_test_choose(int a_id, int a_row);   /* a list's, table's, tree's, tabs' or dropdown's row, as a user */
void sga_test_set_number(int a_id, int a_value);   /* typed, then Return, as a user */
void sga_test_slide(int a_id, int a_value);   /* the knob moved there, as a user */
void sga_test_set_date(int a_id, int a_value);   /* a date or a time entered, as a user */
void sga_test_set_color(int a_id, int a_rgb);   /* chosen in the color panel, as a user */
void sga_test_type_combo(int a_id, const char *a_text);   /* typed, then Return, as a user */
void sga_test_toggle_expander(int a_id);   /* a click on the triangle */
void sga_test_dismiss_popover(int a_id);   /* Escape, as a user */
void sga_test_type_tokens(int a_id, const char *a_text);   /* typed, then Return */
void sga_test_rate(int a_id, int a_value);   /* a click on that star */
void sga_test_menu(int a_item_id);
void sga_test_request_close(int a_window);
void sga_test_focus(int a_id);   /* as a click: key window, first responder */
int sga_test_edit_enabled(int a_role);   /* 10 undo .. 15 select all: AppKit's menu validation now */
int sga_test_context_menu(int a_id, int a_item);   /* 0: no such item in that widget's context menu */
void sga_test_auto_cancel_dialogs(int a_ms);
int sga_snapshot(int a_window, const char *a_path);
const char *sga_describe_accessibility(int a_window);

#endif
