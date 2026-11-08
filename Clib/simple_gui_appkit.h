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
 * appearance 10 (a = 1 dark), wake 11. Modifiers: 1 shift, 2 control, 4 alt, 8 command.
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
int sga_grid(void);
void sga_grid_put(int a_grid, int a_child, int a_row, int a_column, int a_rows, int a_columns);
void sga_grid_set_spacing(int a_grid, int a_row_gap, int a_column_gap);

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
int sga_list(void);
void sga_list_extend(int a_id, const char *a_text);
void sga_list_wipe_out(int a_id);
void sga_list_select(int a_id, int a_row);
int sga_list_selected(int a_id);

/* Common */
void sga_set_enabled(int a_id, int a_on);
int sga_is_enabled(int a_id);
void sga_set_visible(int a_id, int a_on);
int sga_is_visible(int a_id);
void sga_set_direction(int a_id, int a_direction);   /* 0 auto, 1 left to right, 2 right to left: this widget only */
void sga_set_accessible_label(int a_id, const char *a_text);
void sga_set_accessible_description(int a_id, const char *a_text);
const char *sga_accessible_role(int a_id);

/* Canvas */
int sga_canvas(int a_width, int a_height);
void sga_canvas_present(int a_id, void *a_cairo_surface);
int sga_scale_factor(int a_id);
int sga_width(int a_id);
int sga_height(int a_id);

/* Menus: roles 0 none, 1 about, 2 settings, 3 quit, 10 undo, 11 redo, 12 cut, 13 copy,
   14 paste, 15 select all. Shortcuts "primary+O", "primary+shift+Z". */
void *sga_menu_new(const char *a_title);
void sga_menu_add_item(void *a_menu, const char *a_text, const char *a_shortcut, int a_item_id, int a_role);
void sga_menu_add_separator(void *a_menu);

/* Dialogs (blocking) */
const char *sga_open_file(int a_window, const char *a_title, int a_save, const char *a_extensions);
int sga_message(int a_window, const char *a_title, const char *a_text, int a_confirm);

/* Appearance */
int sga_is_dark(void);
void sga_set_dark(int a_on);

/* Test driver */
void sga_test_click(int a_id);
void sga_test_type(int a_id, const char *a_text);
void sga_test_choose(int a_id, int a_row);
void sga_test_menu(int a_item_id);
void sga_test_request_close(int a_window);
void sga_test_auto_cancel_dialogs(int a_ms);
int sga_snapshot(int a_window, const char *a_path);
const char *sga_describe_accessibility(int a_window);

#endif
