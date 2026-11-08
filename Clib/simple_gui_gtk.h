/* simple_gui_gtk.h - simple_gui's GTK 4 backend (Linux).

   Native GTK 4 widgets, named across the C boundary by integer ids. GTK signals push
   [type, id, a, b] into one queue; Eiffel polls it (NEVER a callback into Eiffel).
   Events are [type, id, a, b, c]. Programmatic changes (set_text, select_row) do not emit: a guard flag suppresses the
   signal while the change is made. Strings cross the boundary as UTF-8.

   Shared data is __attribute__((weak)): this header is included by several classes'
   inline externals and each generated C file would otherwise get a private copy.

   Event types (simple_gui spec section 5):
     1 click | 2 text changed | 3 activate | 4 selection(a = row, 1-based)
     5 menu(a = item id) | 6 close requested | 7 pointer(a = x, b = y, c = kind | buttons << 4 | modifiers << 8)
     8 key(a = key code, b = character, c = modifiers << 8) | 9 resize(a = width, b = height)
     10 appearance(a = 1 dark) | 11 wake
   Pointer kind: 1 press, 2 release, 3 motion. Modifiers: 1 shift, 2 control, 4 alt, 8 super. */

#ifndef SIMPLE_GUI_GTK_H
#define SIMPLE_GUI_GTK_H

#include <gtk/gtk.h>
#include <string.h>

#define SG_QCAP 2048
#define SG_MAX 4096

__attribute__((weak)) int sg_q[SG_QCAP][5] = {{0}};
__attribute__((weak)) int sg_qh = 0;
__attribute__((weak)) int sg_qt = 0;
__attribute__((weak)) GtkWidget *sg_w[SG_MAX] = {0};
__attribute__((weak)) int sg_kind[SG_MAX] = {0};      /* 1 window 2 stack 3 grid 4 label 5 button 6 field 7 list 8 canvas */
__attribute__((weak)) int sg_n = 1;                   /* id 0 is "none" */
__attribute__((weak)) int sg_quiet = 0;               /* >0 while a programmatic change runs */
__attribute__((weak)) GThread *sg_gui_thread = NULL;
__attribute__((weak)) volatile gint sg_wake_pending = 0;
__attribute__((weak)) GSimpleActionGroup *sg_actions = NULL;
__attribute__((weak)) GMenu *sg_menubar = NULL;
__attribute__((weak)) int sg_dark_seen = -1;
__attribute__((weak)) cairo_surface_t *sg_canvas_image[SG_MAX] = {0};

static void sg_push5(int t, int id, int a, int b, int c) {
    int n = (sg_qt + 1) % SG_QCAP;
    if (n == sg_qh) return;
    sg_q[sg_qt][0] = t; sg_q[sg_qt][1] = id; sg_q[sg_qt][2] = a; sg_q[sg_qt][3] = b; sg_q[sg_qt][4] = c;
    sg_qt = n;
}
static void sg_push(int t, int id, int a, int b) { sg_push5(t, id, a, b, 0); }
static int sg_reg(GtkWidget *w, int kind) {
    if (sg_n >= SG_MAX) return 0;
    sg_w[sg_n] = w; sg_kind[sg_n] = kind;
    g_object_set_data(G_OBJECT(w), "sg-id", GINT_TO_POINTER(sg_n));
    return sg_n++;
}

/* ---------- lifecycle and loop ---------- */

static void sg_on_dark(GObject *o, GParamSpec *p, gpointer d);

__attribute__((weak)) char sg_app_name[128] = "";
static int sg_init(const char *name, const char *app_id) {
    (void) app_id;   /* GTK without GtkApplication needs no id; kept for the AppKit and future GtkApplication path */
    if (!gtk_init_check()) return 0;
    g_strlcpy(sg_app_name, name, sizeof sg_app_name);
    g_set_application_name(name);
    sg_gui_thread = g_thread_self();
    sg_actions = g_simple_action_group_new();
    sg_menubar = g_menu_new();
    g_signal_connect(gtk_settings_get_default(), "notify::gtk-application-prefer-dark-theme", G_CALLBACK(sg_on_dark), NULL);
    return 1;
}
static int sg_is_gui_thread(void) { return sg_gui_thread == NULL || g_thread_self() == sg_gui_thread; }

/* Run the loop for up to `ms' milliseconds, returning early when an event is queued. */
static void sg_pump(int ms) {
    gint64 until = g_get_monotonic_time() + (gint64) ms * 1000;
    do {
        while (g_main_context_iteration(NULL, FALSE)) { }
        if (sg_qh != sg_qt) return;
        if (g_atomic_int_compare_and_exchange(&sg_wake_pending, 1, 0)) { sg_push(11, 0, 0, 0); return; }
        g_main_context_iteration(NULL, TRUE);   /* blocks until a source fires; the heartbeat below bounds it */
    } while (g_get_monotonic_time() < until);
}
static gboolean sg_heartbeat(gpointer d) { (void) d; return G_SOURCE_CONTINUE; }
static void sg_start_heartbeat(int ms) { g_timeout_add(ms, sg_heartbeat, NULL); }

/* Callable from ANY thread: wake the GUI loop. */
static void sg_wake(void) { g_atomic_int_set(&sg_wake_pending, 1); g_main_context_wakeup(NULL); }

static int sg_next(int *t, int *id, int *a, int *b, int *c) {
    if (sg_qh == sg_qt) return 0;
    *t = sg_q[sg_qh][0]; *id = sg_q[sg_qh][1]; *a = sg_q[sg_qh][2]; *b = sg_q[sg_qh][3]; *c = sg_q[sg_qh][4];
    sg_qh = (sg_qh + 1) % SG_QCAP;
    return 1;
}

/* ---------- signals -> queue ---------- */

static int sg_id_of(gpointer o) { return GPOINTER_TO_INT(g_object_get_data(G_OBJECT(o), "sg-id")); }
static void sg_on_click(GtkButton *b, gpointer d) { (void) d; if (!sg_quiet) sg_push(1, sg_id_of(b), 0, 0); }
static void sg_on_changed(GtkEditable *e, gpointer d) { (void) d; if (!sg_quiet) sg_push(2, sg_id_of(e), 0, 0); }
static void sg_on_activate(GtkEntry *e, gpointer d) { (void) d; if (!sg_quiet) sg_push(3, sg_id_of(e), 0, 0); }
static void sg_on_row(GtkListBox *l, GtkListBoxRow *r, gpointer d) {
    (void) d; if (!sg_quiet) sg_push(4, sg_id_of(l), r ? gtk_list_box_row_get_index(r) + 1 : 0, 0);
}
static gboolean sg_on_close(GtkWindow *w, gpointer d) { (void) d; sg_push(6, sg_id_of(w), 0, 0); return TRUE; }
static void sg_on_menu(GSimpleAction *a, GVariant *p, gpointer d) { (void) a; (void) p; sg_push(5, 0, GPOINTER_TO_INT(d), 0); }
static void sg_on_dark(GObject *o, GParamSpec *p, gpointer d) {
    gboolean v = FALSE; (void) p; (void) d;
    g_object_get(o, "gtk-application-prefer-dark-theme", &v, NULL);
    sg_push(10, 0, v ? 1 : 0, 0);
}

/* ---------- windows and containers ---------- */

static int sg_window(const char *title, int w, int h) {
    GtkWidget *win = gtk_window_new();
    int id;
    gtk_window_set_title(GTK_WINDOW(win), title);
    gtk_window_set_default_size(GTK_WINDOW(win), w, h);
    id = sg_reg(win, 1);
    gtk_widget_insert_action_group(win, "app", G_ACTION_GROUP(sg_actions));
    g_signal_connect(win, "close-request", G_CALLBACK(sg_on_close), NULL);
    return id;
}
/* The window's content: a box holding the menu bar (when there is one) above `child'. */
/* GTK 4: a widget whose direction is NONE takes the global default, not its parent's, so
   the menu bar (no Eiffel widget, outside the cascade) is given the window's direction here. */
static void sg_direction_tree(GtkWidget *w, GtkTextDirection d) {
    GtkWidget *c;
    gtk_widget_set_direction(w, d);
    for (c = gtk_widget_get_first_child(w); c; c = gtk_widget_get_next_sibling(c)) sg_direction_tree(c, d);
}
static void sg_bar_items(GMenuModel *m, int pos, int removed, int added, gpointer bar) {
    int d = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(bar), "sg-dir"));
    (void) pos; (void) removed; (void) added;
    gtk_widget_set_visible(GTK_WIDGET(bar), g_menu_model_get_n_items(m) > 0);
    /* Relabelling rebuilds the bar's items: give the new ones the window's direction. */
    if (d) sg_direction_tree(GTK_WIDGET(bar), (GtkTextDirection) d);
}
static void sg_window_set_content(int win, int child) {
    GtkWidget *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    /* Positions (sg_x, sg_y) are measured from the content's top-left: no title bar, no menu bar. */
    g_object_set_data(G_OBJECT(sg_w[win]), "sg-content", sg_w[child]);
    GtkWidget *bar = gtk_popover_menu_bar_new_from_model(G_MENU_MODEL(sg_menubar));
    /* The bar follows the application's menu model: hidden while it is empty. */
    gtk_widget_set_visible(bar, g_menu_model_get_n_items(G_MENU_MODEL(sg_menubar)) > 0);
    g_signal_connect_object(sg_menubar, "items-changed", G_CALLBACK(sg_bar_items), bar, 0);
    g_object_set_data(G_OBJECT(sg_w[win]), "sg-bar", bar);
    g_object_set_data(G_OBJECT(sg_w[win]), "sg-outer", outer);
    gtk_box_append(GTK_BOX(outer), bar);
    gtk_widget_set_vexpand(sg_w[child], TRUE);
    gtk_box_append(GTK_BOX(outer), sg_w[child]);
    gtk_window_set_child(GTK_WINDOW(sg_w[win]), outer);
}
static void sg_window_show(int win) { gtk_window_present(GTK_WINDOW(sg_w[win])); }
static void sg_window_close(int win) { gtk_window_destroy(GTK_WINDOW(sg_w[win])); sg_w[win] = NULL; }
static void sg_window_set_title(int win, const char *t) { gtk_window_set_title(GTK_WINDOW(sg_w[win]), t); }

static int sg_stack(int vertical, int spacing) {
    GtkWidget *b = gtk_box_new(vertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL, spacing);
    gtk_widget_set_margin_start(b, 12); gtk_widget_set_margin_end(b, 12);
    gtk_widget_set_margin_top(b, 12); gtk_widget_set_margin_bottom(b, 12);
    return sg_reg(b, 2);
}
/* Cross-axis alignment: 0 fill, 1 start, 2 centre, 3 end. */
static GtkAlign sg_galign(int a) {
    return a == 1 ? GTK_ALIGN_START : a == 2 ? GTK_ALIGN_CENTER : a == 3 ? GTK_ALIGN_END : GTK_ALIGN_FILL;
}
static int sg_is_vertical(int stack) {
    return gtk_orientable_get_orientation(GTK_ORIENTABLE(sg_w[stack])) == GTK_ORIENTATION_VERTICAL;
}
static void sg_stack_align_child(int stack, int child, int a) {
    if (sg_is_vertical(stack)) gtk_widget_set_halign(sg_w[child], sg_galign(a));
    else gtk_widget_set_valign(sg_w[child], sg_galign(a));
}
static void sg_stack_extend(int stack, int child, int stretch) {
    GtkWidget *c = sg_w[child];
    int stored = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[stack]), "sg-align"));
    if (sg_is_vertical(stack)) gtk_widget_set_vexpand(c, stretch ? TRUE : FALSE);
    else gtk_widget_set_hexpand(c, stretch ? TRUE : FALSE);
    if (stored) sg_stack_align_child(stack, child, stored - 1);
    gtk_box_append(GTK_BOX(sg_w[stack]), c);
}
/* The stack's alignment for its children, existing and later. */
static void sg_stack_set_alignment(int stack, int a) {
    GtkWidget *c;
    g_object_set_data(G_OBJECT(sg_w[stack]), "sg-align", GINT_TO_POINTER(a + 1));
    for (c = gtk_widget_get_first_child(sg_w[stack]); c; c = gtk_widget_get_next_sibling(c)) {
        if (sg_is_vertical(stack)) gtk_widget_set_halign(c, sg_galign(a)); else gtk_widget_set_valign(c, sg_galign(a));
    }
}
static void sg_stack_set_spacing(int stack, int s) { gtk_box_set_spacing(GTK_BOX(sg_w[stack]), s); }

static int sg_grid(void) { return sg_reg(gtk_grid_new(), 3); }
static void sg_grid_put(int grid, int child, int row, int col, int rows, int cols) {
    int stretch = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[grid]), "sg-stretch"));
    if (stretch && stretch == col) gtk_widget_set_hexpand(sg_w[child], TRUE);
    gtk_grid_attach(GTK_GRID(sg_w[grid]), sg_w[child], col - 1, row - 1, cols, rows);
}
static void sg_grid_set_homogeneous_columns(int grid, int on) {
    gtk_grid_set_column_homogeneous(GTK_GRID(sg_w[grid]), on ? TRUE : FALSE);
}
/* Column col (1-based; 0 = none) takes the spare width. */
static void sg_grid_set_stretching_column(int grid, int col) {
    GtkWidget *c;
    g_object_set_data(G_OBJECT(sg_w[grid]), "sg-stretch", GINT_TO_POINTER(col));
    for (c = gtk_widget_get_first_child(sg_w[grid]); c; c = gtk_widget_get_next_sibling(c)) {
        int column, row, w, h;
        gtk_grid_query_child(GTK_GRID(sg_w[grid]), c, &column, &row, &w, &h);
        gtk_widget_set_hexpand(c, col > 0 && column == col - 1);
    }
}
static void sg_grid_set_spacing(int grid, int row_gap, int col_gap) {
    gtk_grid_set_row_spacing(GTK_GRID(sg_w[grid]), row_gap); gtk_grid_set_column_spacing(GTK_GRID(sg_w[grid]), col_gap);
}

/* ---------- controls ---------- */

static void sg_set_description_a11y(int id, const char *text) {
    gtk_accessible_update_property(GTK_ACCESSIBLE(sg_w[id]), GTK_ACCESSIBLE_PROPERTY_DESCRIPTION, text, -1);
}

static int sg_label(const char *text) {
    GtkWidget *l = gtk_label_new(text);
    gtk_label_set_xalign(GTK_LABEL(l), 0.0);
    /* One line, giving way with an ellipsis (matches AppKit, simple_gui #6); see sg_label_set_wrap_width. */
    gtk_label_set_ellipsize(GTK_LABEL(l), PANGO_ELLIPSIZE_END);
    return sg_reg(l, 4);
}
/* chars > 0: wrap at about `chars' characters wide; 0: one line, ellipsized.
   `chars' is the label's natural width (max_width_chars), not its minimum: a minimum of
   `chars' made a grid squeeze its neighbours (the calculator's captions turned to "...")
   rather than wrap the label sooner. The minimum is the longest word, as GTK's default. */
static void sg_label_set_wrap_width(int id, int chars) {
    GtkLabel *l = GTK_LABEL(sg_w[id]);
    if (chars > 0) {
        gtk_label_set_ellipsize(l, PANGO_ELLIPSIZE_NONE);
        gtk_label_set_wrap(l, TRUE);
        gtk_label_set_wrap_mode(l, PANGO_WRAP_WORD_CHAR);
        gtk_label_set_max_width_chars(l, chars);
        gtk_label_set_width_chars(l, -1);
    } else {
        gtk_label_set_wrap(l, FALSE);
        gtk_label_set_max_width_chars(l, -1);
        gtk_label_set_width_chars(l, -1);
        gtk_label_set_ellipsize(l, PANGO_ELLIPSIZE_END);
    }
}
static void sg_label_set(int id, const char *t) { gtk_label_set_text(GTK_LABEL(sg_w[id]), t); }
static const char *sg_label_get(int id) { return gtk_label_get_text(GTK_LABEL(sg_w[id])); }

static int sg_button(const char *text) {
    GtkWidget *b = gtk_button_new_with_label(text);
    int id = sg_reg(b, 5);
    gtk_widget_set_halign(b, GTK_ALIGN_START);
    g_signal_connect(b, "clicked", G_CALLBACK(sg_on_click), NULL);
    return id;
}
static void sg_button_set(int id, const char *t) { gtk_button_set_label(GTK_BUTTON(sg_w[id]), t); }
static const char *sg_button_get(int id) { const char *s = gtk_button_get_label(GTK_BUTTON(sg_w[id])); return s ? s : ""; }

static int sg_field(void) {
    GtkWidget *e = gtk_entry_new();
    int id = sg_reg(e, 6);
    g_signal_connect(e, "changed", G_CALLBACK(sg_on_changed), NULL);
    g_signal_connect(e, "activate", G_CALLBACK(sg_on_activate), NULL);
    return id;
}
static void sg_field_set(int id, const char *t) { sg_quiet++; gtk_editable_set_text(GTK_EDITABLE(sg_w[id]), t); sg_quiet--; }
static const char *sg_field_get(int id) { return gtk_editable_get_text(GTK_EDITABLE(sg_w[id])); }
static void sg_field_set_placeholder(int id, const char *t) { gtk_entry_set_placeholder_text(GTK_ENTRY(sg_w[id]), t); }

static int sg_list(void) {
    GtkWidget *l = gtk_list_box_new();
    GtkWidget *scroll = gtk_scrolled_window_new();
    int id;
    gtk_list_box_set_selection_mode(GTK_LIST_BOX(l), GTK_SELECTION_SINGLE);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), l);
    gtk_scrolled_window_set_min_content_height(GTK_SCROLLED_WINDOW(scroll), 80);
    gtk_widget_add_css_class(l, "boxed-list");
    id = sg_reg(scroll, 7);
    g_object_set_data(G_OBJECT(l), "sg-id", GINT_TO_POINTER(id));
    g_object_set_data(G_OBJECT(scroll), "sg-list", l);
    g_signal_connect(l, "row-selected", G_CALLBACK(sg_on_row), NULL);
    return id;
}
static GtkListBox *sg_list_box(int id) { return GTK_LIST_BOX(g_object_get_data(G_OBJECT(sg_w[id]), "sg-list")); }
static void sg_list_extend(int id, const char *t) {
    GtkWidget *row = gtk_label_new(t);
    gtk_label_set_xalign(GTK_LABEL(row), 0.0);
    gtk_widget_set_margin_start(row, 6); gtk_widget_set_margin_top(row, 3); gtk_widget_set_margin_bottom(row, 3);
    gtk_list_box_append(sg_list_box(id), row);
}
static void sg_list_wipe_out(int id) { sg_quiet++; gtk_list_box_remove_all(sg_list_box(id)); sg_quiet--; }
static void sg_list_select(int id, int row) {
    GtkListBoxRow *r = gtk_list_box_get_row_at_index(sg_list_box(id), row - 1);
    sg_quiet++;
    if (r) gtk_list_box_select_row(sg_list_box(id), r); else gtk_list_box_unselect_all(sg_list_box(id));
    sg_quiet--;
}
static int sg_list_selected(int id) {
    GtkListBoxRow *r = gtk_list_box_get_selected_row(sg_list_box(id));
    return r ? gtk_list_box_row_get_index(r) + 1 : 0;
}

/* ---------- check box (kind 9; event 12 toggled, a = 1 checked) ---------- */

static void sg_on_toggled(GtkCheckButton *b, gpointer d) {
    (void) d;
    if (!sg_quiet) sg_push(12, sg_id_of(b), gtk_check_button_get_active(b) ? 1 : 0, 0);
}
static int sg_check_box(const char *text) {
    GtkWidget *b = gtk_check_button_new_with_label(text);
    int id = sg_reg(b, 9);
    gtk_widget_set_halign(b, GTK_ALIGN_START);
    g_signal_connect(b, "toggled", G_CALLBACK(sg_on_toggled), NULL);
    return id;
}
static void sg_check_box_set(int id, int on) { sg_quiet++; gtk_check_button_set_active(GTK_CHECK_BUTTON(sg_w[id]), on ? TRUE : FALSE); sg_quiet--; }
static int sg_check_box_is_checked(int id) { return gtk_check_button_get_active(GTK_CHECK_BUTTON(sg_w[id])) ? 1 : 0; }
static void sg_check_box_set_text(int id, const char *t) { gtk_check_button_set_label(GTK_CHECK_BUTTON(sg_w[id]), t); }
static const char *sg_check_box_text(int id) { const char *s = gtk_check_button_get_label(GTK_CHECK_BUTTON(sg_w[id])); return s ? s : ""; }

/* ---------- text area (kind 10; event 2 on change) ---------- */

__attribute__((weak)) char *sg_text_buf = NULL;
static void sg_on_buffer_changed(GtkTextBuffer *b, gpointer d) { (void) b; if (!sg_quiet) sg_push(2, GPOINTER_TO_INT(d), 0, 0); }
static int sg_text_area(void) {
    GtkWidget *view = gtk_text_view_new();
    GtkWidget *scroll = gtk_scrolled_window_new();
    int id;
    gtk_text_view_set_wrap_mode(GTK_TEXT_VIEW(view), GTK_WRAP_WORD_CHAR);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), view);
    gtk_scrolled_window_set_min_content_height(GTK_SCROLLED_WINDOW(scroll), 80);
    gtk_scrolled_window_set_has_frame(GTK_SCROLLED_WINDOW(scroll), TRUE);
    id = sg_reg(scroll, 10);
    g_object_set_data(G_OBJECT(scroll), "sg-view", view);
    g_object_set_data(G_OBJECT(view), "sg-id", GINT_TO_POINTER(id));
    g_signal_connect(gtk_text_view_get_buffer(GTK_TEXT_VIEW(view)), "changed", G_CALLBACK(sg_on_buffer_changed), GINT_TO_POINTER(id));
    return id;
}
static GtkTextView *sg_view_of(int id) { return GTK_TEXT_VIEW(g_object_get_data(G_OBJECT(sg_w[id]), "sg-view")); }
static void sg_text_area_set(int id, const char *t) { sg_quiet++; gtk_text_buffer_set_text(gtk_text_view_get_buffer(sg_view_of(id)), t, -1); sg_quiet--; }
static const char *sg_text_area_get(int id) {
    GtkTextBuffer *b = gtk_text_view_get_buffer(sg_view_of(id));
    GtkTextIter s, e;
    gtk_text_buffer_get_bounds(b, &s, &e);
    g_free(sg_text_buf);
    sg_text_buf = gtk_text_buffer_get_text(b, &s, &e, FALSE);
    return sg_text_buf;
}
static void sg_text_area_set_read_only(int id, int on) {
    gtk_text_view_set_editable(sg_view_of(id), on ? FALSE : TRUE);
    gtk_text_view_set_cursor_visible(sg_view_of(id), on ? FALSE : TRUE);
}

/* ---------- system colours (0xRRGGBB) ---------- */

static int sg_is_dark(void);

/* role: 1 window background, 2 text, 3 secondary text, 4 accent, 5 selection, 6 separator.
   Read from the theme's named colours (Adwaita defines them); a fallback if a theme lacks one. */
static int sg_system_color(int role) {
    static const char *names[7][2] = {
        {NULL, NULL}, {"window_bg_color", "theme_bg_color"}, {"window_fg_color", "theme_fg_color"},
        {"insensitive_fg_color", "unfocused_insensitive_color"}, {"accent_bg_color", "theme_selected_bg_color"},
        {"theme_selected_bg_color", "accent_bg_color"}, {"borders", "unfocused_borders"}};
    GtkWidget *probe = NULL;
    GtkStyleContext *ctx;
    GdkRGBA c;
    int i, found = 0, dark;
    if (role < 1 || role > 6) return 0;
    for (i = 1; i < sg_n && !probe; i++) if (sg_kind[i] == 1 && sg_w[i]) probe = sg_w[i];
    if (!probe) return 0;
G_GNUC_BEGIN_IGNORE_DEPRECATIONS
    ctx = gtk_widget_get_style_context(probe);
    for (i = 0; i < 2 && !found; i++) found = gtk_style_context_lookup_color(ctx, names[role][i], &c);
G_GNUC_END_IGNORE_DEPRECATIONS
    if (found)
        return ((int) (c.red * 255.0 + 0.5) << 16) | ((int) (c.green * 255.0 + 0.5) << 8) | (int) (c.blue * 255.0 + 0.5);
    dark = sg_is_dark();
    switch (role) {
        case 1: return dark ? 0x242424 : 0xFAFAFA;
        case 2: return dark ? 0xFFFFFF : 0x1E1E1E;
        case 3: return dark ? 0x9A9A9A : 0x6A6A6A;
        case 6: return dark ? 0x3A3A3A : 0xD0D0D0;
        default: return 0x3584E4;
    }
}

/* ---------- position in the window's content (logical pixels, y down) ---------- */

static int sg_point(int id, int want_y) {
    GtkWidget *w = sg_w[id];
    GtkRoot *root = gtk_widget_get_root(w);
    GtkWidget *content = root ? g_object_get_data(G_OBJECT(root), "sg-content") : NULL;
    graphene_point_t src = GRAPHENE_POINT_INIT(0, 0), dst;
    if (!content || !gtk_widget_compute_point(w, content, &src, &dst)) return 0;
    return (int) (want_y ? dst.y : dst.x);
}
static int sg_x(int id) { return sg_point(id, 0); }
static int sg_y(int id) { return sg_point(id, 1); }

/* ---------- common widget state ---------- */

static void sg_set_enabled(int id, int on) { gtk_widget_set_sensitive(sg_w[id], on ? TRUE : FALSE); }
static int sg_is_enabled(int id) { return gtk_widget_get_sensitive(sg_w[id]) ? 1 : 0; }
static void sg_set_visible(int id, int on) { gtk_widget_set_visible(sg_w[id], on ? TRUE : FALSE); }
static int sg_is_visible(int id) { return gtk_widget_get_visible(sg_w[id]) ? 1 : 0; }
/* 0 auto, 1 left to right, 2 right to left */
static void sg_set_direction(int id, int d) {
    GtkTextDirection l_dir = d == 1 ? GTK_TEXT_DIR_LTR : d == 2 ? GTK_TEXT_DIR_RTL : GTK_TEXT_DIR_NONE;
    gtk_widget_set_direction(sg_w[id], l_dir);
    if (sg_kind[id] == 1) {
        GtkWidget *bar = g_object_get_data(G_OBJECT(sg_w[id]), "sg-bar");
        GtkWidget *outer = g_object_get_data(G_OBJECT(sg_w[id]), "sg-outer");
        if (outer) gtk_widget_set_direction(outer, l_dir);
        if (bar) {
            g_object_set_data(G_OBJECT(bar), "sg-dir", GINT_TO_POINTER((int) l_dir));
            sg_direction_tree(bar, l_dir);
        }
    }
}

/* ---------- canvas: present a finished Cairo image ---------- */

static void sg_canvas_draw(GtkDrawingArea *a, cairo_t *cr, int w, int h, gpointer d) {
    int id = GPOINTER_TO_INT(d);
    cairo_surface_t *img = sg_canvas_image[id];
    double scale = gtk_widget_get_scale_factor(GTK_WIDGET(a));
    (void) w; (void) h;
    if (!img) return;
    cairo_save(cr);
    cairo_scale(cr, 1.0 / scale, 1.0 / scale);
    cairo_set_source_surface(cr, img, 0, 0);
    cairo_paint(cr);
    cairo_restore(cr);
}
static void sg_canvas_resized(GtkDrawingArea *a, int w, int h, gpointer d) { (void) a; sg_push(9, GPOINTER_TO_INT(d), w, h); }
static int sg_mods(GdkModifierType m) {
    return ((m & GDK_SHIFT_MASK) ? 1 : 0) | ((m & GDK_CONTROL_MASK) ? 2 : 0) | ((m & GDK_ALT_MASK) ? 4 : 0) | ((m & GDK_SUPER_MASK) ? 8 : 0);
}
static void sg_pointer(GtkGesture *g, int kind, double x, double y, gpointer d) {
    GdkModifierType m = gtk_event_controller_get_current_event_state(GTK_EVENT_CONTROLLER(g));
    int button = (int) gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(g));
    sg_push5(7, GPOINTER_TO_INT(d), (int) x, (int) y, kind | (button << 4) | (sg_mods(m) << 8));
}
/* A click gives the canvas keyboard focus, so arrow keys reach it (AppKit: makeFirstResponder). */
static void sg_canvas_pressed(GtkGestureClick *g, int n, double x, double y, gpointer d) {
    (void) n;
    gtk_widget_grab_focus(gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(g)));
    sg_pointer(GTK_GESTURE(g), 1, x, y, d);
}
static void sg_canvas_released(GtkGestureClick *g, int n, double x, double y, gpointer d) { (void) n; sg_pointer(GTK_GESTURE(g), 2, x, y, d); }
static void sg_canvas_motion(GtkEventControllerMotion *c, double x, double y, gpointer d) {
    GdkModifierType m = gtk_event_controller_get_current_event_state(GTK_EVENT_CONTROLLER(c));
    sg_push5(7, GPOINTER_TO_INT(d), (int) x, (int) y, 3 | (sg_mods(m) << 8));
}
static gboolean sg_canvas_key(GtkEventControllerKey *c, guint keyval, guint code, GdkModifierType m, gpointer d) {
    (void) c; (void) code;
    sg_push5(8, GPOINTER_TO_INT(d), (int) keyval, (int) gdk_keyval_to_unicode(keyval), sg_mods(m) << 8);
    return TRUE;
}

static int sg_canvas(int w, int h) {
    GtkWidget *a = gtk_drawing_area_new();
    GtkGesture *click = gtk_gesture_click_new();
    GtkEventController *motion = gtk_event_controller_motion_new();
    GtkEventController *keys = gtk_event_controller_key_new();
    int id = sg_reg(a, 8);
    gtk_drawing_area_set_content_width(GTK_DRAWING_AREA(a), w);
    gtk_drawing_area_set_content_height(GTK_DRAWING_AREA(a), h);
    gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(a), sg_canvas_draw, GINT_TO_POINTER(id), NULL);
    g_signal_connect(a, "resize", G_CALLBACK(sg_canvas_resized), GINT_TO_POINTER(id));
    g_signal_connect(click, "pressed", G_CALLBACK(sg_canvas_pressed), GINT_TO_POINTER(id));
    g_signal_connect(click, "released", G_CALLBACK(sg_canvas_released), GINT_TO_POINTER(id));
    gtk_widget_add_controller(a, GTK_EVENT_CONTROLLER(click));
    g_signal_connect(motion, "motion", G_CALLBACK(sg_canvas_motion), GINT_TO_POINTER(id));
    gtk_widget_add_controller(a, motion);
    g_signal_connect(keys, "key-pressed", G_CALLBACK(sg_canvas_key), GINT_TO_POINTER(id));
    gtk_widget_add_controller(a, keys);
    gtk_widget_set_focusable(a, TRUE);
    return id;
}
static int sg_scale_factor(int id) { return gtk_widget_get_scale_factor(sg_w[id]); }
static int sg_width(int id) { return gtk_widget_get_width(sg_w[id]); }
static int sg_height(int id) { return gtk_widget_get_height(sg_w[id]); }
/* Keep a reference to `image' (a cairo_surface_t) and redraw. The caller keeps its own reference. */
static void sg_canvas_present(int id, void *image) {
    if (sg_canvas_image[id]) cairo_surface_destroy(sg_canvas_image[id]);
    sg_canvas_image[id] = image ? cairo_surface_reference((cairo_surface_t *) image) : NULL;
    gtk_widget_queue_draw(sg_w[id]);
}

/* ---------- menus ---------- */

/* Shortcut "primary+O" -> "<Control>o" (GTK has no Cmd); "" for none. */
static void sg_accel(const char *neutral, char *out, size_t n) {
    const char *p = neutral; out[0] = 0;
    if (!neutral || !*neutral) return;
    while (*p) {
        const char *plus = strchr(p, '+');
        size_t len = plus ? (size_t) (plus - p) : strlen(p);
        char part[32];
        if (len >= sizeof part) len = sizeof part - 1;
        memcpy(part, p, len); part[len] = 0;
        if (plus) {
            if (!g_ascii_strcasecmp(part, "primary") || !g_ascii_strcasecmp(part, "ctrl")) g_strlcat(out, "<Control>", n);
            else if (!g_ascii_strcasecmp(part, "shift")) g_strlcat(out, "<Shift>", n);
            else if (!g_ascii_strcasecmp(part, "alt")) g_strlcat(out, "<Alt>", n);
            p = plus + 1;
        } else {
            gchar *low = g_ascii_strdown(part, -1);
            g_strlcat(out, strlen(part) == 1 ? low : part, n);
            g_free(low);
            break;
        }
    }
}
__attribute__((weak)) GtkShortcutController *sg_shortcuts = NULL;

/* A top-level menu (returns its GMenu as an opaque handle). */
/* Where each item lives, so it can be relabelled (a GMenu item cannot change in place:
   it is replaced at the same position with the same action and accelerator). */
#define SG_MAX_ITEMS 1024
__attribute__((weak)) GMenu *sg_item_menu[SG_MAX_ITEMS] = {0};
__attribute__((weak)) int sg_item_pos[SG_MAX_ITEMS] = {0};
__attribute__((weak)) char *sg_item_action[SG_MAX_ITEMS] = {0};
__attribute__((weak)) char *sg_item_accel[SG_MAX_ITEMS] = {0};

static void sg_remember_item(int item_id, GMenu *m, int pos, const char *action, const char *accel) {
    if (item_id <= 0 || item_id >= SG_MAX_ITEMS) return;
    sg_item_menu[item_id] = m;
    sg_item_pos[item_id] = pos;
    g_free(sg_item_action[item_id]); sg_item_action[item_id] = g_strdup(action);
    g_free(sg_item_accel[item_id]); sg_item_accel[item_id] = (accel && *accel) ? g_strdup(accel) : NULL;
}

/* An item relabel rebuilds a submenu's rows with direction NONE (MACMINI, #12 review):
   after the popover has rebuilt them, give every window's bar its direction again. */
static void sg_submenu_items(GMenuModel *m, int pos, int removed, int added, gpointer d) {
    int i;
    (void) m; (void) pos; (void) removed; (void) added; (void) d;
    for (i = 1; i < sg_n; i++) {
        if (sg_kind[i] == 1 && sg_w[i]) {
            GtkWidget *bar = g_object_get_data(G_OBJECT(sg_w[i]), "sg-bar");
            int dir = bar ? GPOINTER_TO_INT(g_object_get_data(G_OBJECT(bar), "sg-dir")) : 0;
            if (dir) sg_direction_tree(bar, (GtkTextDirection) dir);
        }
    }
}
static void *sg_menu_new(const char *title) {   /* menus live at application level, as the spec says */
    GMenu *m = g_menu_new();
    g_signal_connect_after(m, "items-changed", G_CALLBACK(sg_submenu_items), NULL);
    g_object_set_data(G_OBJECT(m), "sg-index", GINT_TO_POINTER(g_menu_model_get_n_items(G_MENU_MODEL(sg_menubar))));
    g_menu_append_submenu(sg_menubar, title, G_MENU_MODEL(m));
    return m;
}
static void sg_menu_set_title(void *menu, const char *title) {
    int pos = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(menu), "sg-index"));
    g_menu_remove(sg_menubar, pos);
    g_menu_insert_submenu(sg_menubar, pos, title, G_MENU_MODEL(menu));
}
__attribute__((weak)) char *sg_label_buf = NULL;
/* The label GTK's menu model holds now for the top-level `menu'. */
static const char *sg_menu_title(void *menu) {
    int pos = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(menu), "sg-index"));
    g_free(sg_label_buf); sg_label_buf = NULL;
    g_menu_model_get_item_attribute(G_MENU_MODEL(sg_menubar), pos, G_MENU_ATTRIBUTE_LABEL, "s", &sg_label_buf);
    return sg_label_buf ? sg_label_buf : "";
}
static void sg_menu_set_item_text(int item_id, const char *text) {
    GMenuItem *mi;
    if (item_id <= 0 || item_id >= SG_MAX_ITEMS || !sg_item_menu[item_id]) return;
    mi = g_menu_item_new(text, sg_item_action[item_id]);
    if (sg_item_accel[item_id]) g_menu_item_set_attribute(mi, "accel", "s", sg_item_accel[item_id]);
    g_menu_remove(sg_item_menu[item_id], sg_item_pos[item_id]);
    g_menu_insert_item(sg_item_menu[item_id], sg_item_pos[item_id], mi);
    g_object_unref(mi);
}
/* The label GTK's menu model holds now for item `item_id'. */
static const char *sg_menu_item_text(int item_id) {
    g_free(sg_label_buf); sg_label_buf = NULL;
    if (item_id > 0 && item_id < SG_MAX_ITEMS && sg_item_menu[item_id])
        g_menu_model_get_item_attribute(G_MENU_MODEL(sg_item_menu[item_id]), sg_item_pos[item_id], G_MENU_ATTRIBUTE_LABEL, "s", &sg_label_buf);
    return sg_label_buf ? sg_label_buf : "";
}
/* Item `item_id' (> 0): activating it pushes event 5 with a = item_id. */
static void sg_menu_add_item(void *menu, const char *text, const char *shortcut, int item_id) {
    char name[32], detailed[40], accel[64];
    GSimpleAction *a;
    snprintf(name, sizeof name, "item%d", item_id);
    snprintf(detailed, sizeof detailed, "app.%s", name);
    a = g_simple_action_new(name, NULL);
    g_signal_connect(a, "activate", G_CALLBACK(sg_on_menu), GINT_TO_POINTER(item_id));
    g_action_map_add_action(G_ACTION_MAP(sg_actions), G_ACTION(a));
    {
        GMenuItem *mi = g_menu_item_new(text, detailed);
        sg_accel(shortcut, accel, sizeof accel);
        if (accel[0]) g_menu_item_set_attribute(mi, "accel", "s", accel);
        sg_remember_item(item_id, G_MENU(menu), g_menu_model_get_n_items(G_MENU_MODEL(menu)), detailed, accel);
        g_menu_append_item(G_MENU(menu), mi);
        g_object_unref(mi);
    }
}
static void sg_menu_add_separator(void *menu) {
    GMenu *section = g_menu_new();
    g_menu_append_section(G_MENU(menu), NULL, G_MENU_MODEL(section));
}
/* Install keyboard shortcuts for every menu item that carries one, on window `win'. */
static void sg_window_install_shortcuts(int win, const char *spec_list) {
    /* spec_list: "item_id=shortcut;item_id=shortcut" */
    GtkEventController *c = gtk_shortcut_controller_new();
    gchar **pairs = g_strsplit(spec_list, ";", -1);
    int i;
    gtk_shortcut_controller_set_scope(GTK_SHORTCUT_CONTROLLER(c), GTK_SHORTCUT_SCOPE_GLOBAL);
    for (i = 0; pairs[i]; i++) {
        gchar **kv = g_strsplit(pairs[i], "=", 2);
        if (kv[0] && kv[1] && *kv[1]) {
            char accel[64], action[40];
            sg_accel(kv[1], accel, sizeof accel);
            snprintf(action, sizeof action, "app.item%s", kv[0]);
            gtk_shortcut_controller_add_shortcut(GTK_SHORTCUT_CONTROLLER(c),
                gtk_shortcut_new(gtk_shortcut_trigger_parse_string(accel), gtk_named_action_new(action)));
        }
        g_strfreev(kv);
    }
    g_strfreev(pairs);
    gtk_widget_add_controller(sg_w[win], c);
}
/* Edit roles act on the focused widget of the active window (a menu bar's own action scope
   does not reach a text field's "clipboard.*" actions). */
static void sg_on_edit(GSimpleAction *a, GVariant *p, gpointer d) {
    int i; (void) a; (void) p;
    for (i = 1; i < sg_n; i++) {
        if (sg_kind[i] == 1 && sg_w[i] && gtk_window_is_active(GTK_WINDOW(sg_w[i]))) {
            GtkWidget *f = gtk_root_get_focus(GTK_ROOT(sg_w[i]));
            if (f) gtk_widget_activate_action(f, (const char *) d, NULL);
            return;
        }
    }
}
/* role: 10 undo 11 redo 12 cut 13 copy 14 paste 15 select all */
static void sg_menu_add_edit_role(void *menu, const char *text, int role, int item_id) {
    static const char *names[] = {"undo", "redo", "cut", "copy", "paste", "select_all"};
    static const char *actions[] = {"text.undo", "text.redo", "clipboard.cut", "clipboard.copy", "clipboard.paste", "selection.select-all"};
    char name[32], detailed[40];
    if (role < 10 || role > 15) return;
    snprintf(name, sizeof name, "edit_%s", names[role - 10]);
    snprintf(detailed, sizeof detailed, "app.%s", name);
    if (!g_action_map_lookup_action(G_ACTION_MAP(sg_actions), name)) {
        GSimpleAction *a = g_simple_action_new(name, NULL);
        g_signal_connect(a, "activate", G_CALLBACK(sg_on_edit), (gpointer) actions[role - 10]);
        g_action_map_add_action(G_ACTION_MAP(sg_actions), G_ACTION(a));
    }
    sg_remember_item(item_id, G_MENU(menu), g_menu_model_get_n_items(G_MENU_MODEL(menu)), detailed, NULL);
    g_menu_append(G_MENU(menu), text, detailed);
}

/* ---------- accessibility description (what GTK exposes, walked from the window) ---------- */

__attribute__((weak)) GString *sg_describe_buf = NULL;
/* The widget a screen reader meets: a text area's view, not its scrolled window. */
static GtkWidget *sg_a11y_target(int id) {
    GtkWidget *v = g_object_get_data(G_OBJECT(sg_w[id]), "sg-view");
    return v ? v : sg_w[id];
}
static void sg_set_a11y_label(int id, const char *text) {
    GtkWidget *w = sg_a11y_target(id);
    g_object_set_data_full(G_OBJECT(w), "sg-a11y", g_strdup(text), g_free);
    gtk_accessible_update_property(GTK_ACCESSIBLE(w), GTK_ACCESSIBLE_PROPERTY_LABEL, text, -1);
}
static const char *sg_role_nick(GtkWidget *w) {
    GtkAccessibleRole r = gtk_accessible_get_accessible_role(GTK_ACCESSIBLE(w));
    GEnumClass *k = g_type_class_ref(GTK_TYPE_ACCESSIBLE_ROLE);
    GEnumValue *v = g_enum_get_value(k, r);
    const char *nick = v ? v->value_nick : "?";
    g_type_class_unref(k);
    return nick;
}
static void sg_describe_walk(GtkWidget *w, int depth) {
    GtkWidget *c;
    const char *role = sg_role_nick(w);
    const char *name = g_object_get_data(G_OBJECT(w), "sg-a11y");
    if (!name && GTK_IS_LABEL(w)) name = gtk_label_get_text(GTK_LABEL(w));
    if (!name && GTK_IS_BUTTON(w)) name = gtk_button_get_label(GTK_BUTTON(w));
    if (!name && GTK_IS_CHECK_BUTTON(w)) name = gtk_check_button_get_label(GTK_CHECK_BUTTON(w));
    if (strcmp(role, "generic") && strcmp(role, "none") && strcmp(role, "presentation")) {
        int i; for (i = 0; i < depth; i++) g_string_append(sg_describe_buf, "  ");
        g_string_append_printf(sg_describe_buf, "%s: %s\n", role, name ? name : "");
    }
    for (c = gtk_widget_get_first_child(w); c; c = gtk_widget_get_next_sibling(c))
        sg_describe_walk(c, depth + 1);
}
static const char *sg_describe(int win) {
    if (sg_describe_buf) g_string_free(sg_describe_buf, TRUE);
    sg_describe_buf = g_string_new("");
    if (win > 0 && sg_w[win]) sg_describe_walk(sg_w[win], 0);
    return sg_describe_buf->str;
}
static int sg_direction_of(int id) {
    GtkTextDirection d = gtk_widget_get_direction(sg_w[id]);
    return d == GTK_TEXT_DIR_RTL ? 2 : 1;
}

/* ---------- dialogs (nested loop until answered) ---------- */

__attribute__((weak)) int sg_dialog_done = 0;
__attribute__((weak)) char *sg_dialog_path = NULL;
__attribute__((weak)) int sg_dialog_choice = -1;

static void sg_open_done(GObject *src, GAsyncResult *res, gpointer d) {
    GFile *f = gtk_file_dialog_open_finish(GTK_FILE_DIALOG(src), res, NULL);
    (void) d;
    g_free(sg_dialog_path); sg_dialog_path = NULL;
    if (f) { sg_dialog_path = g_file_get_path(f); g_object_unref(f); }
    sg_dialog_done = 1;
}
static void sg_save_done(GObject *src, GAsyncResult *res, gpointer d) {
    GFile *f = gtk_file_dialog_save_finish(GTK_FILE_DIALOG(src), res, NULL);
    (void) d;
    g_free(sg_dialog_path); sg_dialog_path = NULL;
    if (f) { sg_dialog_path = g_file_get_path(f); g_object_unref(f); }
    sg_dialog_done = 1;
}
static void sg_wait_dialog(void) { while (!sg_dialog_done) g_main_context_iteration(NULL, TRUE); }
/* Returns the chosen path or NULL. `extensions' is "txt;md" or "" for any file. */
static const char *sg_open_file(int win, const char *title, int save, const char *extensions) {
    GtkFileDialog *dlg = gtk_file_dialog_new();
    gtk_file_dialog_set_title(dlg, title);
    if (extensions && *extensions) {
        GtkFileFilter *f = gtk_file_filter_new();
        GListStore *filters = g_list_store_new(GTK_TYPE_FILE_FILTER);
        gchar **ext = g_strsplit(extensions, ";", -1);
        int i;
        gtk_file_filter_set_name(f, extensions);
        for (i = 0; ext[i]; i++) if (*ext[i]) { gchar *pat = g_strdup_printf("*.%s", ext[i]); gtk_file_filter_add_pattern(f, pat); g_free(pat); }
        g_strfreev(ext);
        g_list_store_append(filters, f);
        gtk_file_dialog_set_filters(dlg, G_LIST_MODEL(filters));
        g_object_unref(filters); g_object_unref(f);
    }
    gtk_file_dialog_set_modal(dlg, TRUE);
    sg_dialog_done = 0;
    if (save) gtk_file_dialog_save(dlg, win > 0 ? GTK_WINDOW(sg_w[win]) : NULL, NULL, sg_save_done, NULL);
    else gtk_file_dialog_open(dlg, win > 0 ? GTK_WINDOW(sg_w[win]) : NULL, NULL, sg_open_done, NULL);
    sg_wait_dialog();
    g_object_unref(dlg);
    return sg_dialog_path;
}
static void sg_alert_done(GObject *src, GAsyncResult *res, gpointer d) {
    (void) d;
    sg_dialog_choice = gtk_alert_dialog_choose_finish(GTK_ALERT_DIALOG(src), res, NULL);
    sg_dialog_done = 1;
}
/* confirm = 1: buttons Cancel, OK; returns 1 for OK. confirm = 0: a single OK. */
static int sg_message(int win, const char *title, const char *text, int confirm) {
    GtkAlertDialog *dlg = gtk_alert_dialog_new("%s", title);
    const char *two[] = {"Cancel", "OK", NULL}, *one[] = {"OK", NULL};
    gtk_alert_dialog_set_detail(dlg, text);
    gtk_alert_dialog_set_buttons(dlg, confirm ? two : one);
    gtk_alert_dialog_set_cancel_button(dlg, 0);
    gtk_alert_dialog_set_default_button(dlg, confirm ? 1 : 0);
    sg_dialog_done = 0; sg_dialog_choice = -1;
    gtk_alert_dialog_choose(dlg, win > 0 ? GTK_WINDOW(sg_w[win]) : NULL, NULL, sg_alert_done, NULL);
    sg_wait_dialog();
    g_object_unref(dlg);
    return confirm ? (sg_dialog_choice == 1 ? 1 : 0) : 1;
}

/* ---------- appearance ---------- */

static int sg_is_dark(void) {
    gboolean v = FALSE; gchar *theme = NULL; int dark;
    g_object_get(gtk_settings_get_default(), "gtk-application-prefer-dark-theme", &v, "gtk-theme-name", &theme, NULL);
    dark = v || (theme && g_str_has_suffix(theme, "-dark"));
    g_free(theme);
    return dark ? 1 : 0;
}
static void sg_set_dark(int on) { g_object_set(gtk_settings_get_default(), "gtk-application-prefer-dark-theme", on ? TRUE : FALSE, NULL); }

/* ---------- test driver ---------- */

/* A user's click is the "clicked" signal; gtk_widget_activate would emit it only after a 250 ms press animation. */
static void sg_test_click(int id) {
    if (sg_kind[id] == 9) gtk_check_button_set_active(GTK_CHECK_BUTTON(sg_w[id]), !gtk_check_button_get_active(GTK_CHECK_BUTTON(sg_w[id])));
    else g_signal_emit_by_name(sg_w[id], "clicked");
}
static void sg_test_type(int id, const char *t) {   /* emits, like a user */
    GtkWidget *v = g_object_get_data(G_OBJECT(sg_w[id]), "sg-view");
    if (v) gtk_text_buffer_set_text(gtk_text_view_get_buffer(GTK_TEXT_VIEW(v)), t, -1);
    else gtk_editable_set_text(GTK_EDITABLE(sg_w[id]), t);
}
static void sg_test_choose(int id, int row) {
    GtkListBoxRow *r = gtk_list_box_get_row_at_index(sg_list_box(id), row - 1);
    if (r) gtk_list_box_select_row(sg_list_box(id), r);
}
static void sg_test_request_close(int win) { gtk_window_close(GTK_WINDOW(sg_w[win])); }   /* emits close-request */
static void sg_test_menu(int item_id) {
    char name[32]; snprintf(name, sizeof name, "item%d", item_id);
    g_action_group_activate_action(G_ACTION_GROUP(sg_actions), name, NULL);
}
/* A snapshot shows the window as its user sees it while using it. A window the desktop has
   not focused (WSLg gives a new window the focus or not, depending on what else is happening)
   wears GTK's "backdrop" style: grey title, every control greyed as if disabled. So the
   snapshot lifts the backdrop state, lets one frame restyle, draws, and puts it back. */
static int sg_snapshot(int id, const char *path) {
    GtkWidget *w = sg_w[id];
    int W = gtk_widget_get_width(w), H = gtk_widget_get_height(w), ok;
    gboolean backdrop = (gtk_widget_get_state_flags(w) & GTK_STATE_FLAG_BACKDROP) != 0;
    GdkPaintable *p; GtkSnapshot *s; GskRenderNode *n; GdkTexture *t;
    if (W <= 0 || H <= 0) return 0;
    if (backdrop) {
        gint64 until = g_get_monotonic_time() + 100 * 1000;
        gtk_widget_unset_state_flags(w, GTK_STATE_FLAG_BACKDROP);
        gtk_widget_queue_draw(w);
        while (g_get_monotonic_time() < until) {
            while (g_main_context_iteration(NULL, FALSE)) { }
            g_usleep(5000);
        }
    }
    p = gtk_widget_paintable_new(w);
    s = gtk_snapshot_new();
    gdk_paintable_snapshot(p, GDK_SNAPSHOT(s), W, H);
    n = gtk_snapshot_free_to_node(s);
    if (!n) { g_object_unref(p); return 0; }
    t = gsk_renderer_render_texture(gtk_native_get_renderer(GTK_NATIVE(w)), n, NULL);
    ok = gdk_texture_save_to_png(t, path) ? 1 : 0;
    g_object_unref(t); gsk_render_node_unref(n); g_object_unref(p);
    if (backdrop && (!GTK_IS_WINDOW(w) || !gtk_window_is_active(GTK_WINDOW(w)))) gtk_widget_set_state_flags(w, GTK_STATE_FLAG_BACKDROP, FALSE);
    return ok;
}
static const char *sg_role(int id) { return sg_role_nick(sg_w[id]); }

/* Drive the loop until the queue stays empty for one turn, or `ms' pass (tests). */
static void sg_pump_until_idle(int ms) {
    gint64 until = g_get_monotonic_time() + (gint64) ms * 1000;
    while (g_get_monotonic_time() < until) {
        while (g_main_context_iteration(NULL, FALSE)) { }
        if (!g_main_context_pending(NULL)) break;
    }
}

#endif
