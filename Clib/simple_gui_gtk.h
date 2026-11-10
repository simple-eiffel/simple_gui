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
#include <math.h>

#define SG_QCAP 2048
#define SG_MAX 4096

__attribute__((weak)) int sg_q[SG_QCAP][5] = {{0}};
__attribute__((weak)) int sg_qh = 0;
__attribute__((weak)) int sg_qt = 0;
__attribute__((weak)) GtkWidget *sg_w[SG_MAX] = {0};
__attribute__((weak)) int sg_kind[SG_MAX] = {0};      /* 1 window 2 stack 3 grid 4 label 5 button 6 field 7 list 8 canvas (9 check box, 10 text area, 11 tabs; 13 table, 14 tree; 15 dropdown, 16 spin box, 17 progress bar, 18 toolbar, 19 status bar; 20 radio group, 21 segmented, 22 slider, 23 switch, 24 date, 25 time, 26 color, 27 scroll area, 28 image, 29 separator, 30 group box, 31 expander, 32 combo box, 33 tree table; 40 calendar, 41 menu button, 42 split button, 43 level bar, 44 popover, 45 search field, 46 token field, 47 path control, 48 rating, 49 rich text area; 50 drawn view) */
__attribute__((weak)) int sg_n = 1;                   /* id 0 is "none" */
__attribute__((weak)) int sg_quiet = 0;               /* >0 while a programmatic change runs */
__attribute__((weak)) GThread *sg_gui_thread = NULL;
__attribute__((weak)) volatile gint sg_wake_pending = 0;
__attribute__((weak)) GSimpleActionGroup *sg_actions = NULL;
static void sg_update_edit_enabled(void);   /* below, with the Edit roles */
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
    g_object_add_weak_pointer(G_OBJECT(w), (gpointer *) &sg_w[sg_n]);   /* emptied when it dies */
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
        sg_update_edit_enabled();
        if (sg_qh != sg_qt) return;
        if (g_atomic_int_compare_and_exchange(&sg_wake_pending, 1, 0)) { sg_push(11, 0, 0, 0); return; }
        g_main_context_iteration(NULL, TRUE);   /* blocks until a source fires; the heartbeat below bounds it */
    } while (g_get_monotonic_time() < until);
}
static gboolean sg_heartbeat(gpointer d) { (void) d; return G_SOURCE_CONTINUE; }
static void sg_start_heartbeat(int ms) { g_timeout_add(ms, sg_heartbeat, NULL); }

/* Callable from ANY thread: wake the GUI loop. */
static void sg_wake(void) { g_atomic_int_set(&sg_wake_pending, 1); g_main_context_wakeup(NULL); }

/* The next event, skipping any that name a widget destroyed since it was queued (its slot is
   a weak pointer, emptied then): a handler answering one would touch freed memory. */
static int sg_next(int *t, int *id, int *a, int *b, int *c) {
    for (;;) {
        if (sg_qh == sg_qt) return 0;
        *t = sg_q[sg_qh][0]; *id = sg_q[sg_qh][1]; *a = sg_q[sg_qh][2]; *b = sg_q[sg_qh][3]; *c = sg_q[sg_qh][4];
        sg_qh = (sg_qh + 1) % SG_QCAP;
        if (*id <= 0 || *id >= SG_MAX || sg_w[*id] != NULL) return 1;
    }
}

/* ---------- signals -> queue ---------- */

static int sg_id_of(gpointer o) { return GPOINTER_TO_INT(g_object_get_data(G_OBJECT(o), "sg-id")); }
static void sg_on_click(GtkButton *b, gpointer d) { (void) d; if (!sg_quiet) sg_push(1, sg_id_of(b), 0, 0); }
/* Is `w' a widget an event may name? Not while it or its window is being destroyed: the event
   is read after the slot dangles, and a handler that answers it (1p's live validation) would
   touch freed memory. */
static int sg_live(GtkWidget *w) {
    GtkRoot *root = gtk_widget_get_root(w);
    return !gtk_widget_in_destruction(w) && (!root || !gtk_widget_in_destruction(GTK_WIDGET(root)));
}
static void sg_on_changed(GtkEditable *e, gpointer d) { (void) d; if (!sg_quiet && sg_live(GTK_WIDGET(e))) sg_push(2, sg_id_of(e), 0, 0); }
static void sg_on_activate(GtkEntry *e, gpointer d) { (void) d; if (!sg_quiet) sg_push(3, sg_id_of(e), 0, 0); }
/* A selection is reported only when it changes ("sg-row", the row last selected, 1-based): GTK
   says "row-selected" again for the same row when a shown list takes the focus. */
static void sg_on_row(GtkListBox *l, GtkListBoxRow *r, gpointer d) {
    int now = r ? gtk_list_box_row_get_index(r) + 1 : 0;
    (void) d;
    if (now == GPOINTER_TO_INT(g_object_get_data(G_OBJECT(l), "sg-row"))) return;
    g_object_set_data(G_OBJECT(l), "sg-row", GINT_TO_POINTER(now));
    if (!sg_quiet) sg_push(4, sg_id_of(l), now, 0);
}
static gboolean sg_on_close(GtkWindow *w, gpointer d) { (void) d; sg_push(6, sg_id_of(w), 0, 0); return TRUE; }
static void sg_on_menu(GSimpleAction *a, GVariant *p, gpointer d) { (void) a; (void) p; sg_push(5, 0, GPOINTER_TO_INT(d), 0); }
static void sg_on_dark(GObject *o, GParamSpec *p, gpointer d) {
    gboolean v = FALSE; (void) p; (void) d;
    g_object_get(o, "gtk-application-prefer-dark-theme", &v, NULL);
    sg_push(10, 0, v ? 1 : 0, 0);
}

/* ---------- 1l: reference pills. Each window's content sits in a GtkOverlay ("sg-overlay");
   a pill is a small label over it, placed at a corner of its widget on every layout (corner
   1 top-left, 2 top-right, 3 bottom-left, 4 bottom-right; left and right mirror right to
   left), reading its tip as a tooltip. Targets and labels are held by weak pointers, so a
   widget gone with its window leaves an empty slot, never a dangling one. ---------- */
__attribute__((weak)) GtkWidget *sg_pill_target[SG_MAX] = {0};
__attribute__((weak)) GtkWidget *sg_pill_label[SG_MAX] = {0};
__attribute__((weak)) int sg_pill_corner[SG_MAX] = {0};
__attribute__((weak)) int sg_pills_on = 0;
__attribute__((weak)) int sg_pill_css_done = 0;
static void sg_pill_css(void) {
    GtkCssProvider *p;
    if (sg_pill_css_done) return;
    sg_pill_css_done = 1;
    p = gtk_css_provider_new();
    /* the design boards' pill: burnt orange, white text and rim, the same in both themes */
    gtk_css_provider_load_from_string(p,
        "label.sg-pill { background-color: #c2410c; color: #ffffff; border: 1px solid #ffffff;"
        " border-radius: 8px; padding: 0 5px; font-size: 10px; font-weight: bold; }");
    gtk_style_context_add_provider_for_display(gdk_display_get_default(), GTK_STYLE_PROVIDER(p),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(p);
}
__attribute__((weak)) GtkWidget *sg_badge_target[SG_MAX];
static gboolean sg_pill_position(GtkOverlay *o, GtkWidget *child, GdkRectangle *a, gpointer d) {
    int id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(child), "sg-pill-id")), corner, w, h;
    int badge = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(child), "sg-badge-id"));
    GtkWidget *t;
    graphene_rect_t r;
    gboolean rtl, right, bottom;
    (void) d;
    if (badge > 0 && badge < SG_MAX) {
        /* a badge: over the trailing top corner, mostly inside the widget */
        if (!(t = sg_badge_target[badge]) || !gtk_widget_get_mapped(t) || !gtk_widget_compute_bounds(t, GTK_WIDGET(o), &r)) return FALSE;
        gtk_widget_measure(child, GTK_ORIENTATION_HORIZONTAL, -1, NULL, &w, NULL, NULL);
        gtk_widget_measure(child, GTK_ORIENTATION_VERTICAL, -1, NULL, &h, NULL, NULL);
        rtl = gtk_widget_get_direction(t) == GTK_TEXT_DIR_RTL;
        a->x = (int) (rtl ? r.origin.x - w / 3 : r.origin.x + r.size.width - (2 * w) / 3);
        a->y = (int) (r.origin.y - h / 3);
        if (a->x < 0) a->x = 0;
        if (a->y < 0) a->y = 0;
        a->width = w;
        a->height = h;
        return TRUE;
    }
    if (id <= 0 || id >= SG_MAX || !(t = sg_pill_target[id]) || !gtk_widget_get_mapped(t)) return FALSE;
    if (!gtk_widget_compute_bounds(t, GTK_WIDGET(o), &r)) return FALSE;
    gtk_widget_measure(child, GTK_ORIENTATION_HORIZONTAL, -1, NULL, &w, NULL, NULL);
    gtk_widget_measure(child, GTK_ORIENTATION_VERTICAL, -1, NULL, &h, NULL, NULL);
    corner = sg_pill_corner[id];
    rtl = gtk_widget_get_direction(t) == GTK_TEXT_DIR_RTL;
    right = (corner == 2 || corner == 4) != rtl;
    bottom = corner == 3 || corner == 4;
    /* half outside its corner, as simple_bible's pills sit, but kept inside the window */
    a->x = (int) (right ? r.origin.x + r.size.width - w / 2 : r.origin.x - w / 2);
    a->y = (int) (bottom ? r.origin.y + r.size.height - h / 2 : r.origin.y - h / 2);
    if (a->x < 0) a->x = 0;
    if (a->y < 0) a->y = 0;
    a->width = w;
    a->height = h;
    return TRUE;
}
/* The overlay a widget's pill goes in: its window's, once it is in a window. */
static GtkOverlay *sg_pill_overlay(GtkWidget *t) {
    GtkRoot *root = t ? gtk_widget_get_root(t) : NULL;
    return root ? g_object_get_data(G_OBJECT(root), "sg-overlay") : NULL;
}
/* Make, update or drop widget `id''s pill label to match what is held for it. */
static void sg_pill_sync(int id) {
    GtkWidget *t = sg_pill_target[id], *l = sg_pill_label[id];
    GtkOverlay *o;
    const char *code = t ? g_object_get_data(G_OBJECT(t), "sg-pill-code") : NULL;
    if (l && (!code || gtk_widget_get_parent(l) != (GtkWidget *) sg_pill_overlay(t))) {
        GtkWidget *parent = gtk_widget_get_parent(l);
        if (parent && GTK_IS_OVERLAY(parent)) gtk_overlay_remove_overlay(GTK_OVERLAY(parent), l);
        l = sg_pill_label[id];   /* the weak pointer emptied if that freed it */
    }
    if (!code || !(o = sg_pill_overlay(t))) return;
    if (!l) {
        l = gtk_label_new(code);
        gtk_widget_add_css_class(l, "sg-pill");
        gtk_widget_set_halign(l, GTK_ALIGN_START);
        gtk_widget_set_valign(l, GTK_ALIGN_START);
        g_object_set_data(G_OBJECT(l), "sg-pill-id", GINT_TO_POINTER(id));
        sg_pill_label[id] = l;
        g_object_add_weak_pointer(G_OBJECT(l), (gpointer *) &sg_pill_label[id]);
        gtk_overlay_add_overlay(o, l);
    }
    gtk_label_set_text(GTK_LABEL(l), code);
    gtk_widget_set_tooltip_text(l, g_object_get_data(G_OBJECT(t), "sg-pill-tip"));
    gtk_widget_set_visible(l, sg_pills_on);
    gtk_widget_queue_allocate(GTK_WIDGET(o));
}
static void sg_badge_sync_all(void);
static void sg_pill_sync_all(void) {
    int i;
    for (i = 1; i < SG_MAX; i++) if (sg_pill_target[i]) sg_pill_sync(i);
    sg_badge_sync_all();
}
static void sg_pill_set(int id, const char *code, const char *tip, int corner) {
    GtkWidget *t = sg_w[id];
    if (!t) return;
    sg_pill_css();
    if (sg_pill_target[id] != t) {
        sg_pill_target[id] = t;
        g_object_add_weak_pointer(G_OBJECT(t), (gpointer *) &sg_pill_target[id]);
    }
    sg_pill_corner[id] = corner;
    g_object_set_data_full(G_OBJECT(t), "sg-pill-code", g_strdup(code), g_free);
    g_object_set_data_full(G_OBJECT(t), "sg-pill-tip", g_strdup(tip), g_free);
    sg_pill_sync(id);
}
static void sg_pill_clear(int id) {
    GtkWidget *t = sg_pill_target[id];
    if (t) g_object_set_data(G_OBJECT(t), "sg-pill-code", NULL);
    sg_pill_sync(id);
}
static void sg_pills_show(int on) { sg_pills_on = on; sg_pill_sync_all(); }
static const char *sg_pill_tip_shown(int id) {
    GtkWidget *l = id > 0 && id < SG_MAX ? sg_pill_label[id] : NULL;
    const char *tip;
    if (!sg_pills_on || !l || !gtk_widget_get_mapped(l) || !sg_pill_target[id]) return "";
    tip = g_object_get_data(G_OBJECT(sg_pill_target[id]), "sg-pill-tip");
    return tip ? tip : "";
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
/* Rows, cells and headers that GTK makes on the fly (a list's rows, a column view's, a tree's)
   are born with no direction, and a widget with none takes GTK's global default, not its
   parent's. A view whose direction was set keeps it ("sg-dir", the GtkTextDirection plus 1);
   a widget born inside it later takes it, with every ancestor up to the view. */
static void sg_follow_view_direction(GtkWidget *w) {
    GtkWidget *a;
    int stored = 0;
    for (a = w ? gtk_widget_get_parent(w) : NULL; a && !stored; a = gtk_widget_get_parent(a))
        stored = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(a), "sg-dir"));
    if (stored)
        for (a = w; a && !g_object_get_data(G_OBJECT(a), "sg-dir"); a = gtk_widget_get_parent(a))
            gtk_widget_set_direction(a, (GtkTextDirection) (stored - 1));
}
static void sg_direction_tree(GtkWidget *w, GtkTextDirection d) {
    GtkWidget *c;
    gtk_widget_set_direction(w, d);
    for (c = gtk_widget_get_first_child(w); c; c = gtk_widget_get_next_sibling(c)) sg_direction_tree(c, d);
}
static void sg_bar_items(GMenuModel *m, int pos, int removed, int added, gpointer bar) {
    int d = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(bar), "sg-dir"));
    (void) pos; (void) removed; (void) added;
    gtk_widget_set_visible(GTK_WIDGET(bar), g_menu_model_get_n_items(m) > 0);
    /* Relabeling rebuilds the bar's items: give the new ones the window's direction. */
    if (d) sg_direction_tree(GTK_WIDGET(bar), (GtkTextDirection) d);
}
/* The window's outer box, made once: the menu bar, then three slots - the toolbar ("sg-top"),
   the content ("sg-mid", which grows) and the status bar ("sg-bottom"). The slots carry the
   window's direction, since a GTK 4 widget with none takes the global default. */
static GtkWidget *sg_window_outer(int win) {
    GtkWidget *outer = g_object_get_data(G_OBJECT(sg_w[win]), "sg-outer");
    GtkWidget *bar, *top, *mid, *bottom;
    GtkTextDirection dir;
    if (outer) return outer;
    dir = gtk_widget_get_direction(sg_w[win]);
    outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    bar = gtk_popover_menu_bar_new_from_model(G_MENU_MODEL(sg_menubar));
    /* The bar follows the application's menu model: hidden while it is empty. */
    gtk_widget_set_visible(bar, g_menu_model_get_n_items(G_MENU_MODEL(sg_menubar)) > 0);
    g_signal_connect_object(sg_menubar, "items-changed", G_CALLBACK(sg_bar_items), bar, 0);
    top = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    mid = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    bottom = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    gtk_widget_set_vexpand(mid, TRUE);
    gtk_widget_set_direction(outer, dir);
    gtk_widget_set_direction(top, dir);
    gtk_widget_set_direction(mid, dir);
    gtk_widget_set_direction(bottom, dir);
    g_object_set_data(G_OBJECT(sg_w[win]), "sg-bar", bar);
    g_object_set_data(G_OBJECT(sg_w[win]), "sg-outer", outer);
    g_object_set_data(G_OBJECT(sg_w[win]), "sg-top", top);
    g_object_set_data(G_OBJECT(sg_w[win]), "sg-mid", mid);
    g_object_set_data(G_OBJECT(sg_w[win]), "sg-bottom", bottom);
    gtk_box_append(GTK_BOX(outer), bar);
    gtk_box_append(GTK_BOX(outer), top);
    gtk_box_append(GTK_BOX(outer), mid);
    gtk_box_append(GTK_BOX(outer), bottom);
    {
        /* the content under an overlay that carries the reference pills (1l) */
        GtkWidget *overlay = gtk_overlay_new();
        gtk_overlay_set_child(GTK_OVERLAY(overlay), outer);
        g_signal_connect(overlay, "get-child-position", G_CALLBACK(sg_pill_position), NULL);
        g_object_set_data(G_OBJECT(sg_w[win]), "sg-overlay", overlay);
        gtk_window_set_child(GTK_WINDOW(sg_w[win]), overlay);
    }
    return outer;
}
static GtkBox *sg_window_slot(int win, const char *slot) {
    sg_window_outer(win);
    return GTK_BOX(g_object_get_data(G_OBJECT(sg_w[win]), slot));
}
static void sg_window_set_content(int win, int child) {
    /* Positions (sg_x, sg_y) are measured from the content's top-left: no title bar, no menu bar. */
    g_object_set_data(G_OBJECT(sg_w[win]), "sg-content", sg_w[child]);
    gtk_widget_set_vexpand(sg_w[child], TRUE);
    gtk_box_append(sg_window_slot(win, "sg-mid"), sg_w[child]);
    sg_pill_sync_all();
}
static void sg_window_set_toolbar(int win, int tb) {
    gtk_box_append(sg_window_slot(win, "sg-top"), sg_w[tb]);
    gtk_box_append(sg_window_slot(win, "sg-top"), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL));
}
static void sg_window_set_status_bar(int win, int sb) {
    gtk_box_append(sg_window_slot(win, "sg-bottom"), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL));
    gtk_box_append(sg_window_slot(win, "sg-bottom"), sg_w[sb]);
}
static void sg_window_show(int win) { sg_window_outer(win); gtk_window_present(GTK_WINDOW(sg_w[win])); sg_pill_sync_all(); }
static void sg_window_close(int win) { gtk_window_destroy(GTK_WINDOW(sg_w[win])); sg_w[win] = NULL; }
static void sg_window_set_title(int win, const char *t) { gtk_window_set_title(GTK_WINDOW(sg_w[win]), t); }

static int sg_stack(int vertical, int spacing) {
    GtkWidget *b = gtk_box_new(vertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL, spacing);
    gtk_widget_set_margin_start(b, 12); gtk_widget_set_margin_end(b, 12);
    gtk_widget_set_margin_top(b, 12); gtk_widget_set_margin_bottom(b, 12);
    return sg_reg(b, 2);
}
/* Cross-axis alignment: 0 fill, 1 start, 2 center, 3 end. */
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

static int sg_grid(void) {
    GtkWidget *g = gtk_grid_new();
    /* 12 clear around it, as around a stack */
    gtk_widget_set_margin_start(g, 12); gtk_widget_set_margin_end(g, 12);
    gtk_widget_set_margin_top(g, 12); gtk_widget_set_margin_bottom(g, 12);
    return sg_reg(g, 3);
}
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
/* ---------- splitter: a GtkPaned (kind 12). The first pane keeps its size when the paned
   grows; neither pane shrinks below its minimum. (First pass by MACMINI, untested on GTK.) ---------- */
/* Until the program sets a position, the divider starts halfway, once the paned first knows
   its size (GTK would give the first pane its minimum: an ellipsized label shrinks to "..."). */
static void sg_on_paned_size(GObject *o, GParamSpec *ps, gpointer d) {
    gboolean set = FALSE; int max = 0;
    (void) ps; (void) d;
    g_object_get(o, "position-set", &set, "max-position", &max, NULL);
    if (!set && max > 0) gtk_paned_set_position(GTK_PANED(o), max / 2);
}
static int sg_splitter(int vertical) {
    GtkWidget *p = gtk_paned_new(vertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL);
    g_signal_connect(p, "notify::max-position", G_CALLBACK(sg_on_paned_size), NULL);
    gtk_paned_set_resize_start_child(GTK_PANED(p), FALSE);
    gtk_paned_set_resize_end_child(GTK_PANED(p), TRUE);
    gtk_paned_set_shrink_start_child(GTK_PANED(p), FALSE);
    gtk_paned_set_shrink_end_child(GTK_PANED(p), FALSE);
    return sg_reg(p, 12);
}
static void sg_splitter_set_pane(int s, int pane, int child) {
    if (pane == 1) gtk_paned_set_start_child(GTK_PANED(sg_w[s]), sg_w[child]);
    else gtk_paned_set_end_child(GTK_PANED(sg_w[s]), sg_w[child]);
}
static int sg_splitter_position(int s) { return gtk_paned_get_position(GTK_PANED(sg_w[s])); }
static void sg_splitter_set_position(int s, int position) { gtk_paned_set_position(GTK_PANED(sg_w[s]), position); }

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
   `chars' made a grid squeeze its neighbors (the calculator's captions turned to "...")
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

static void sg_button_build(int id);
static int sg_button(const char *text) {
    GtkWidget *b = gtk_button_new_with_label(text);
    int id = sg_reg(b, 5);
    g_object_set_data_full(G_OBJECT(b), "sg-text", g_strdup(text ? text : ""), g_free);
    gtk_widget_set_halign(b, GTK_ALIGN_START);
    g_signal_connect(b, "clicked", G_CALLBACK(sg_on_click), NULL);
    return id;
}
static void sg_button_set(int id, const char *t) {
    g_object_set_data_full(G_OBJECT(sg_w[id]), "sg-text", g_strdup(t ? t : ""), g_free);
    sg_button_build(id);
}
static const char *sg_button_get(int id) {
    const char *s = g_object_get_data(G_OBJECT(sg_w[id]), "sg-text");
    if (!s) s = gtk_button_get_label(GTK_BUTTON(sg_w[id]));
    return s ? s : "";
}

/* 1p, defined with the forms below */
static void sg_field_hook_leave(GtkWidget *e, int id);
static int sg_dd_is_choice(int id, guint pos);
static guint sg_dd_pos_of_choice(int id, int choice);
static int sg_dd_choice_of_pos(int id, guint pos);

static int sg_field(void) {
    GtkWidget *e = gtk_entry_new();
    int id = sg_reg(e, 6);
    g_signal_connect(e, "changed", G_CALLBACK(sg_on_changed), NULL);
    g_signal_connect(e, "activate", G_CALLBACK(sg_on_activate), NULL);
    sg_field_hook_leave(e, id);
    return id;
}
static void sg_field_set(int id, const char *t) { sg_quiet++; gtk_editable_set_text(GTK_EDITABLE(sg_w[id]), t); sg_quiet--; }
static const char *sg_field_get(int id) { return gtk_editable_get_text(GTK_EDITABLE(sg_w[id])); }
static void sg_field_set_placeholder(int id, const char *t) {
    if (GTK_IS_SEARCH_ENTRY(sg_w[id])) gtk_search_entry_set_placeholder_text(GTK_SEARCH_ENTRY(sg_w[id]), t);
    else gtk_entry_set_placeholder_text(GTK_ENTRY(sg_w[id]), t);
}

/* A scrolled view of rows asks for its rows' natural height, up to 400 pixels, as the list,
   table and tree are on macOS and Windows (otherwise GTK gives it its minimum: a row or two). */
static void sg_natural_rows(GtkWidget *scroll) {
    gtk_scrolled_window_set_propagate_natural_height(GTK_SCROLLED_WINDOW(scroll), TRUE);
    gtk_scrolled_window_set_max_content_height(GTK_SCROLLED_WINDOW(scroll), 400);
}
static int sg_list(void) {
    GtkWidget *l = gtk_list_box_new();
    GtkWidget *scroll = gtk_scrolled_window_new();
    int id;
    gtk_list_box_set_selection_mode(GTK_LIST_BOX(l), GTK_SELECTION_SINGLE);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), l);
    gtk_scrolled_window_set_min_content_height(GTK_SCROLLED_WINDOW(scroll), 80);
    gtk_widget_add_css_class(l, "boxed-list");
    sg_natural_rows(scroll);
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
    sg_follow_view_direction(row);
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

/* ---------- tables: a GtkColumnView (kind 13) over a GtkStringList whose strings are the
   rows, cells joined by U+001F; each column's factory shows its own field. A user's
   selection sends 4 (a = first selected row); a click on a header (the view's sorter
   changes) sends 14 (a = column). Every column has a sorter that keeps the order, so GTK
   shows the indicator while the program does the sorting; the indicator is set from code
   under sg_quiet. (First pass by MACMINI, untested on GTK.) ---------- */
static char *sg_row_field(const char *joined, int k) {   /* field k (0-based), newly allocated */
    gchar **f = g_strsplit(joined, "\x1f", -1);
    char *r = g_strdup((guint) k < g_strv_length(f) ? f[k] : "");
    g_strfreev(f);
    return r;
}
static void sg_cell_setup(GtkSignalListItemFactory *fa, GtkListItem *it, gpointer d) {
    GtkWidget *l = gtk_label_new(NULL);
    (void) fa; (void) d;
    gtk_label_set_xalign(GTK_LABEL(l), 0.0);
    gtk_label_set_ellipsize(GTK_LABEL(l), PANGO_ELLIPSIZE_END);
    gtk_list_item_set_child(it, l);
}
/* 1f, lazy tables: a row not yet answered holds this one-character placeholder. */
#define SG_UNANSWERED "\x1e"
static void sg_want_row(int id, int row);   /* below, with the tables */
static void sg_cell_bind(GtkSignalListItemFactory *fa, GtkListItem *it, gpointer d) {
    GtkStringObject *o = GTK_STRING_OBJECT(gtk_list_item_get_item(it));
    const char *joined = gtk_string_object_get_string(o);
    if (strcmp(joined, SG_UNANSWERED) == 0) {
        /* in sight and not answered: show it empty and ask for it */
        gtk_label_set_text(GTK_LABEL(gtk_list_item_get_child(it)), "");
        sg_want_row(GPOINTER_TO_INT(g_object_get_data(G_OBJECT(fa), "sg-table")), (int) gtk_list_item_get_position(it) + 1);
    } else {
        char *v = sg_row_field(joined, GPOINTER_TO_INT(d));
        gtk_label_set_text(GTK_LABEL(gtk_list_item_get_child(it)), v);
        g_free(v);
    }
    sg_follow_view_direction(gtk_list_item_get_child(it));
}
static GtkColumnView *sg_table_view(int id) { return GTK_COLUMN_VIEW(g_object_get_data(G_OBJECT(sg_w[id]), "sg-view")); }
static GtkSelectionModel *sg_table_model(int id) { return gtk_column_view_get_model(sg_table_view(id)); }
static void sg_on_table_selection(GtkSelectionModel *m, guint pos, guint n, gpointer d) {
    GtkBitset *b;
    int first;
    (void) pos; (void) n;
    if (sg_quiet) return;
    b = gtk_selection_model_get_selection(m);
    first = gtk_bitset_is_empty(b) ? 0 : (int) gtk_bitset_get_minimum(b) + 1;
    gtk_bitset_unref(b);
    sg_push(4, GPOINTER_TO_INT(d), first, 0);
}
static void sg_on_table_sorter(GtkSorter *s, GtkSorterChange change, gpointer d) {
    GtkColumnViewColumn *col;
    GListModel *cols;
    guint i, n;
    (void) change;
    if (sg_quiet) return;
    col = gtk_column_view_sorter_get_primary_sort_column(GTK_COLUMN_VIEW_SORTER(s));
    if (!col) return;
    cols = gtk_column_view_get_columns(sg_table_view(GPOINTER_TO_INT(d)));
    n = g_list_model_get_n_items(cols);
    for (i = 0; i < n; i++) {
        GtkColumnViewColumn *k = g_list_model_get_item(cols, i);
        g_object_unref(k);
        if (k == col) { sg_push(14, GPOINTER_TO_INT(d), (int) i + 1, 0); return; }
    }
}
static int sg_keep_order(gconstpointer a, gconstpointer b, gpointer d) { (void) a; (void) b; (void) d; return 0; }
static void sg_table_use_selection(int id, int multiple) {
    GListModel *rows = G_LIST_MODEL(g_object_get_data(G_OBJECT(sg_w[id]), "sg-rows"));
    GtkSelectionModel *m;
    if (multiple) m = GTK_SELECTION_MODEL(gtk_multi_selection_new(g_object_ref(rows)));
    else {
        GtkSingleSelection *s = gtk_single_selection_new(g_object_ref(rows));
        gtk_single_selection_set_autoselect(s, FALSE);
        gtk_single_selection_set_can_unselect(s, TRUE);
        m = GTK_SELECTION_MODEL(s);
    }
    g_signal_connect(m, "selection-changed", G_CALLBACK(sg_on_table_selection), GINT_TO_POINTER(id));
    gtk_column_view_set_model(sg_table_view(id), m);
    g_object_unref(m);
}
static int sg_table(const char *titles) {
    GtkStringList *rows = gtk_string_list_new(NULL);
    GtkWidget *v = gtk_column_view_new(NULL);
    GtkWidget *scroll = gtk_scrolled_window_new();
    gchar **t = g_strsplit(titles, "\x1f", -1);
    int i, id;
    for (i = 0; t[i]; i++) {
        GtkListItemFactory *f = gtk_signal_list_item_factory_new();
        GtkColumnViewColumn *c;
        g_signal_connect(f, "setup", G_CALLBACK(sg_cell_setup), NULL);
        g_signal_connect(f, "bind", G_CALLBACK(sg_cell_bind), GINT_TO_POINTER(i));
        c = gtk_column_view_column_new(t[i], f);
        gtk_column_view_column_set_expand(c, TRUE);
        gtk_column_view_column_set_resizable(c, TRUE);
        gtk_column_view_column_set_sorter(c, GTK_SORTER(gtk_custom_sorter_new(sg_keep_order, NULL, NULL)));
        gtk_column_view_append_column(GTK_COLUMN_VIEW(v), c);
        g_object_unref(c);
    }
    g_strfreev(t);
    gtk_column_view_set_reorderable(GTK_COLUMN_VIEW(v), FALSE);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), v);
    sg_natural_rows(scroll);
    id = sg_reg(scroll, 13);
    g_object_set_data_full(G_OBJECT(scroll), "sg-rows", rows, g_object_unref);
    g_object_set_data(G_OBJECT(scroll), "sg-view", v);
    {   /* each cell's bind needs the table's id, to ask for unanswered rows (1f) */
        GListModel *cols = gtk_column_view_get_columns(GTK_COLUMN_VIEW(v));
        guint k, nc = g_list_model_get_n_items(cols);
        for (k = 0; k < nc; k++) {
            GtkColumnViewColumn *c = g_list_model_get_item(cols, k);
            g_object_set_data(G_OBJECT(gtk_column_view_column_get_factory(c)), "sg-table", GINT_TO_POINTER(id));
            g_object_unref(c);
        }
    }
    sg_table_use_selection(id, 0);
    g_signal_connect(gtk_column_view_get_sorter(GTK_COLUMN_VIEW(v)), "changed", G_CALLBACK(sg_on_table_sorter), GINT_TO_POINTER(id));
    return id;
}
static void sg_table_extend(int id, const char *cells) {
    sg_quiet++;
    gtk_string_list_append(GTK_STRING_LIST(g_object_get_data(G_OBJECT(sg_w[id]), "sg-rows")), cells);
    sg_quiet--;
}
static void sg_table_wipe_out(int id) {
    GtkStringList *rows = GTK_STRING_LIST(g_object_get_data(G_OBJECT(sg_w[id]), "sg-rows"));
    g_object_set_data(G_OBJECT(sg_w[id]), "sg-source", NULL);   /* leaves source mode (1f) */
    sg_quiet++;
    gtk_selection_model_unselect_all(sg_table_model(id));
    gtk_string_list_splice(rows, 0, g_list_model_get_n_items(G_LIST_MODEL(rows)), NULL);
    sg_quiet--;
}
/* ---------- 1f, lazy tables (GTK half). Source mode fills the table's GtkStringList with
   SG_UNANSWERED, one per row. A cell bound to it shows empty and asks for its row; the asks
   since the last idle go to Eiffel as ONE rows wanted event (16, a = first, b = last), and a
   row asked for is not asked for again until answered or forgotten (a GtkBitset). An answer
   is spliced in (GTK rebinds it), keeping that row's selection. The answered rows are kept
   oldest first; past SG_ROW_CACHE the oldest go back to SG_UNANSWERED. ---------- */
#define SG_ROW_CACHE 2000
typedef struct { int count; GtkBitset *pending; int lo, hi; guint idle; GQueue answered; } SgSource;
static void sg_source_free(gpointer p) {
    SgSource *s = p;
    if (s->idle) g_source_remove(s->idle);
    gtk_bitset_unref(s->pending);
    g_queue_clear(&s->answered);
    g_free(s);
}
static SgSource *sg_source(int id) { return sg_w[id] ? g_object_get_data(G_OBJECT(sg_w[id]), "sg-source") : NULL; }
static gboolean sg_want_flush(gpointer d) {
    int id = GPOINTER_TO_INT(d);
    SgSource *s = sg_source(id);
    if (!s) return G_SOURCE_REMOVE;
    s->idle = 0;
    if (s->lo > 0) sg_push(16, id, s->lo, s->hi);
    s->lo = s->hi = 0;
    return G_SOURCE_REMOVE;
}
static void sg_want_row(int id, int row) {
    SgSource *s = sg_source(id);
    if (!s || row < 1 || row > s->count || gtk_bitset_contains(s->pending, (guint) row)) return;
    gtk_bitset_add(s->pending, (guint) row);
    if (s->lo == 0 || row < s->lo) s->lo = row;
    if (row > s->hi) s->hi = row;
    if (!s->idle) s->idle = g_idle_add(sg_want_flush, GINT_TO_POINTER(id));
}
/* Replace rows pos .. pos + n - 1 of table `id' by `texts' (NULL: the placeholder), quietly,
   keeping the selection by row number. */
static void sg_table_put(int id, guint pos, guint n, const char *const *texts) {
    GtkStringList *rows = GTK_STRING_LIST(g_object_get_data(G_OBJECT(sg_w[id]), "sg-rows"));
    GtkSelectionModel *m = sg_table_model(id);
    GtkBitset *kept = gtk_selection_model_get_selection(m);
    const char **fill = NULL;
    guint i;
    if (!texts) {
        fill = g_new(const char *, n + 1);
        for (i = 0; i < n; i++) fill[i] = SG_UNANSWERED;
        fill[n] = NULL;
        texts = fill;
    }
    sg_quiet++;
    gtk_string_list_splice(rows, pos, n, texts);
    if (!gtk_bitset_is_empty(kept)) {
        GtkBitset *all = gtk_bitset_new_range(0, g_list_model_get_n_items(G_LIST_MODEL(rows)));
        gtk_selection_model_set_selection(m, kept, all);
        gtk_bitset_unref(all);
    }
    sg_quiet--;
    gtk_bitset_unref(kept);
    g_free(fill);
}
static void sg_table_set_source(int id, int count) {
    GtkStringList *rows = GTK_STRING_LIST(g_object_get_data(G_OBJECT(sg_w[id]), "sg-rows"));
    SgSource *s = g_new0(SgSource, 1);
    guint n = g_list_model_get_n_items(G_LIST_MODEL(rows));
    s->count = count;
    s->pending = gtk_bitset_new_empty();
    g_queue_init(&s->answered);
    g_object_set_data_full(G_OBJECT(sg_w[id]), "sg-source", s, sg_source_free);
    sg_quiet++;
    gtk_selection_model_unselect_all(sg_table_model(id));
    gtk_string_list_splice(rows, 0, n, NULL);
    sg_quiet--;
    if (count > 0) {
        const char **fill = g_new(const char *, (gsize) count + 1);
        int i;
        for (i = 0; i < count; i++) fill[i] = SG_UNANSWERED;
        fill[count] = NULL;
        sg_quiet++;
        gtk_string_list_splice(rows, 0, 0, fill);
        sg_quiet--;
        g_free(fill);
    }
}
static void sg_table_set_row(int id, int row, const char *cells) {
    SgSource *s = sg_source(id);
    GtkStringList *rows = GTK_STRING_LIST(g_object_get_data(G_OBJECT(sg_w[id]), "sg-rows"));
    const char *one[2];
    if (!s || row < 1 || row > s->count || (guint) row > g_list_model_get_n_items(G_LIST_MODEL(rows))) return;
    one[0] = cells; one[1] = NULL;
    sg_table_put(id, (guint) row - 1, 1, one);
    gtk_bitset_remove(s->pending, (guint) row);
    g_queue_push_tail(&s->answered, GINT_TO_POINTER(row));
    while (g_queue_get_length(&s->answered) > SG_ROW_CACHE) {
        int old = GPOINTER_TO_INT(g_queue_pop_head(&s->answered));
        if ((guint) old <= g_list_model_get_n_items(G_LIST_MODEL(rows))
            && strcmp(gtk_string_list_get_string(rows, (guint) old - 1), SG_UNANSWERED) != 0)
            sg_table_put(id, (guint) old - 1, 1, NULL);
    }
}
static void sg_table_set_row_count(int id, int count) {
    SgSource *s = sg_source(id);
    GtkStringList *rows = GTK_STRING_LIST(g_object_get_data(G_OBJECT(sg_w[id]), "sg-rows"));
    guint n = g_list_model_get_n_items(G_LIST_MODEL(rows));
    if (!s || count < 0) return;
    s->count = count;
    if (count < (int) n) {
        sg_quiet++;
        gtk_string_list_splice(rows, (guint) count, n - (guint) count, NULL);   /* selected rows past it go */
        sg_quiet--;
        gtk_bitset_remove_range_closed(s->pending, (guint) count + 1, G_MAXUINT - 1);
    } else if (count > (int) n) {
        guint add = (guint) count - n, i;
        const char **fill = g_new(const char *, add + 1);
        for (i = 0; i < add; i++) fill[i] = SG_UNANSWERED;
        fill[add] = NULL;
        sg_quiet++;
        gtk_string_list_splice(rows, n, 0, fill);
        sg_quiet--;
        g_free(fill);
    }
}
static void sg_table_forget_rows(int id) {
    SgSource *s = sg_source(id);
    GtkStringList *rows = GTK_STRING_LIST(g_object_get_data(G_OBJECT(sg_w[id]), "sg-rows"));
    guint n = g_list_model_get_n_items(G_LIST_MODEL(rows));
    if (!s) return;
    gtk_bitset_remove_all(s->pending);
    g_queue_clear(&s->answered);
    if (n > 0) sg_table_put(id, 0, n, NULL);   /* in sight, they rebind and ask again */
}
static void sg_table_forget_row(int id, int row) {
    SgSource *s = sg_source(id);
    GtkStringList *rows = GTK_STRING_LIST(g_object_get_data(G_OBJECT(sg_w[id]), "sg-rows"));
    if (!s || row < 1 || (guint) row > g_list_model_get_n_items(G_LIST_MODEL(rows))) return;
    gtk_bitset_remove(s->pending, (guint) row);
    sg_table_put(id, (guint) row - 1, 1, NULL);
}
static void sg_table_scroll_to(int id, int row) {
    if (row >= 1) gtk_column_view_scroll_to(sg_table_view(id), (guint) row - 1, NULL, GTK_LIST_SCROLL_NONE, NULL);
}

static void sg_table_set_multiple(int id, int on) { sg_quiet++; sg_table_use_selection(id, on); sg_quiet--; }
static void sg_table_select(int id, int row, int extend) {
    sg_quiet++;
    if (row <= 0) gtk_selection_model_unselect_all(sg_table_model(id));
    else gtk_selection_model_select_item(sg_table_model(id), (guint) (row - 1), extend ? FALSE : TRUE);
    sg_quiet--;
}
static int sg_table_selected_count(int id) {
    GtkBitset *b = gtk_selection_model_get_selection(sg_table_model(id));
    int n = (int) gtk_bitset_get_size(b);
    gtk_bitset_unref(b);
    return n;
}
static int sg_table_selected_at(int id, int i) {
    GtkBitset *b = gtk_selection_model_get_selection(sg_table_model(id));
    int r = (int) gtk_bitset_get_nth(b, (guint) (i - 1)) + 1;
    gtk_bitset_unref(b);
    return r;
}
static void sg_table_sort_by(int id, int column, int ascending) {
    GtkColumnView *v = sg_table_view(id);
    if (column <= 0) gtk_column_view_sort_by_column(v, NULL, GTK_SORT_ASCENDING);
    else {
        GtkColumnViewColumn *c = g_list_model_get_item(gtk_column_view_get_columns(v), (guint) (column - 1));
        gtk_column_view_sort_by_column(v, c, ascending ? GTK_SORT_ASCENDING : GTK_SORT_DESCENDING);
        g_object_unref(c);
    }
}
static void sg_table_set_sort_indicator(int id, int column, int ascending) { sg_quiet++; sg_table_sort_by(id, column, ascending); sg_quiet--; }
static void sg_test_click_header(int id, int column) { sg_table_sort_by(id, column, 1); }   /* as a click: sorter changed -> 14 */

/* ---------- trees: a GtkListView (kind 14) over a GtkTreeListModel. Each node is a
   GtkStringObject carrying its number ("sg-number") and a GListStore of children
   ("sg-children"); a GtkTreeExpander in each row shows the triangle. A user's selection sends 4
   (a = node); a row's "expanded" changing, unless quiet, sends 15 (a = node, b = 1 expanded).
   A node becomes expandable when its first child is added; build the tree before showing it
   for the expanders to appear on first display. (First pass by MACMINI, untested on GTK.) ---------- */
static GListModel *sg_tree_children(gpointer item, gpointer d) {
    GListStore *c = g_object_get_data(G_OBJECT(item), "sg-children");
    (void) d;
    return (c && g_list_model_get_n_items(G_LIST_MODEL(c)) > 0) ? G_LIST_MODEL(g_object_ref(c)) : NULL;
}
static GtkTreeListModel *sg_tree_model(int id) { return GTK_TREE_LIST_MODEL(g_object_get_data(G_OBJECT(sg_w[id]), "sg-tree-model")); }
static GtkSingleSelection *sg_tree_selection(int id) { return GTK_SINGLE_SELECTION(g_object_get_data(G_OBJECT(sg_w[id]), "sg-tree-selection")); }
/* The node number a row shows, or 0. The row's item may be gone (a row being torn down as the
   window closes); get_item hands over a reference, given back here. */
static int sg_row_number(GtkTreeListRow *r) {
    GObject *o = r ? gtk_tree_list_row_get_item(r) : NULL;
    int n = o ? GPOINTER_TO_INT(g_object_get_data(o, "sg-number")) : 0;
    if (o) g_object_unref(o);
    return n;
}
/* The row showing node `n', or NULL when it is not shown (an ancestor is collapsed). */
static GtkTreeListRow *sg_tree_row(int id, int n, guint *pos) {
    GtkTreeListModel *m = sg_tree_model(id);
    guint i, k = g_list_model_get_n_items(G_LIST_MODEL(m));
    for (i = 0; i < k; i++) {
        GtkTreeListRow *r = gtk_tree_list_model_get_row(m, i);
        GObject *o = gtk_tree_list_row_get_item(r);
        int num = GPOINTER_TO_INT(g_object_get_data(o, "sg-number"));
        g_object_unref(o);
        if (num == n) { if (pos) *pos = i; return r; }
        g_object_unref(r);
    }
    return NULL;
}
/* A row's "expanded" notification also arrives for rows that did not change: collapsing a
   node notifies its never-opened children as their rows go (traced on GTK 4.14: one collapse
   reported three times). So each node keeps its last known state ("sg-open", 1 closed /
   2 open; never recorded counts as closed) and only a real change is reported. Quiet changes
   update it silently. */
static void sg_on_tree_expanded(GObject *row, GParamSpec *p, gpointer d) {
    GtkTreeListRow *r = GTK_TREE_LIST_ROW(row);
    GObject *o;
    int open, known;
    (void) p;
    o = gtk_tree_list_row_get_item(r);
    if (!o) return;   /* a row being torn down (the window closing) has no item left */
    open = gtk_tree_list_row_get_expanded(r) ? 2 : 1;
    known = GPOINTER_TO_INT(g_object_get_data(o, "sg-open"));
    if (known == 0) known = 1;   /* never recorded: nodes start closed */
    g_object_set_data(o, "sg-open", GINT_TO_POINTER(open));
    if (!sg_quiet && open != known)
        sg_push(15, GPOINTER_TO_INT(d), GPOINTER_TO_INT(g_object_get_data(o, "sg-number")), open == 2 ? 1 : 0);
    g_object_unref(o);
}
static void sg_tree_setup(GtkSignalListItemFactory *fa, GtkListItem *it, gpointer d) {
    GtkWidget *x = gtk_tree_expander_new();
    GtkWidget *l = gtk_label_new(NULL);
    (void) fa; (void) d;
    gtk_label_set_xalign(GTK_LABEL(l), 0.0);
    gtk_tree_expander_set_child(GTK_TREE_EXPANDER(x), l);
    gtk_list_item_set_child(it, x);
}
/* Disconnect the "expanded" watch item `it' put on the row it was bound to: that exact row and
   handler (kept on the item), not whatever row the item holds now. Watches that stayed
   connected made one collapse report three times. */
static void sg_tree_forget_row(GtkListItem *it) {
    GObject *r = g_object_get_data(G_OBJECT(it), "sg-expanded-row");
    gulong h = GPOINTER_TO_SIZE(g_object_get_data(G_OBJECT(it), "sg-expanded-handler"));
    if (r && h && g_signal_handler_is_connected(r, h)) g_signal_handler_disconnect(r, h);
    g_object_set_data(G_OBJECT(it), "sg-expanded-handler", NULL);
    g_object_set_data(G_OBJECT(it), "sg-expanded-row", NULL);
}
static void sg_tree_bind(GtkSignalListItemFactory *fa, GtkListItem *it, gpointer d) {
    GtkTreeListRow *r = GTK_TREE_LIST_ROW(gtk_list_item_get_item(it));
    GtkWidget *x = gtk_list_item_get_child(it);
    GObject *o = gtk_tree_list_row_get_item(r);
    gulong h;
    (void) fa;
    gtk_tree_expander_set_list_row(GTK_TREE_EXPANDER(x), r);
    sg_follow_view_direction(gtk_tree_expander_get_child(GTK_TREE_EXPANDER(x)));   /* the label, then the expander and up */
    gtk_label_set_text(GTK_LABEL(gtk_tree_expander_get_child(GTK_TREE_EXPANDER(x))), gtk_string_object_get_string(GTK_STRING_OBJECT(o)));
    g_object_unref(o);
    sg_tree_forget_row(it);   /* GTK 4.12+ may bind again without unbinding first */
    h = g_signal_connect(r, "notify::expanded", G_CALLBACK(sg_on_tree_expanded), d);
    g_object_set_data_full(G_OBJECT(it), "sg-expanded-row", g_object_ref(r), g_object_unref);
    g_object_set_data(G_OBJECT(it), "sg-expanded-handler", GSIZE_TO_POINTER(h));
}
static void sg_tree_unbind(GtkSignalListItemFactory *fa, GtkListItem *it, gpointer d) {
    (void) fa; (void) d;
    sg_tree_forget_row(it);
}
static void sg_on_tree_selection(GtkSelectionModel *m, guint pos, guint n, gpointer d) {
    (void) pos; (void) n;
    if (sg_quiet || !gtk_widget_get_root(sg_w[GPOINTER_TO_INT(d)])) return;   /* not while closing */
    sg_push(4, GPOINTER_TO_INT(d), sg_row_number(GTK_TREE_LIST_ROW(gtk_single_selection_get_selected_item(GTK_SINGLE_SELECTION(m)))), 0);
}
static int sg_tree(void) {
    GListStore *roots = g_list_store_new(GTK_TYPE_STRING_OBJECT);
    GtkTreeListModel *m = gtk_tree_list_model_new(G_LIST_MODEL(roots), FALSE, FALSE, sg_tree_children, NULL, NULL);
    GtkSingleSelection *s = gtk_single_selection_new(G_LIST_MODEL(m));
    GtkListItemFactory *f = gtk_signal_list_item_factory_new();
    GtkWidget *v, *scroll = gtk_scrolled_window_new();
    GPtrArray *nodes = g_ptr_array_new();
    int id;
    gtk_single_selection_set_autoselect(s, FALSE);
    gtk_single_selection_set_can_unselect(s, TRUE);
    v = gtk_list_view_new(GTK_SELECTION_MODEL(s), f);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), v);
    sg_natural_rows(scroll);
    id = sg_reg(scroll, 14);
    g_signal_connect(f, "setup", G_CALLBACK(sg_tree_setup), NULL);
    g_signal_connect(f, "bind", G_CALLBACK(sg_tree_bind), GINT_TO_POINTER(id));
    g_signal_connect(f, "unbind", G_CALLBACK(sg_tree_unbind), NULL);
    g_signal_connect(s, "selection-changed", G_CALLBACK(sg_on_tree_selection), GINT_TO_POINTER(id));
    g_object_set_data(G_OBJECT(scroll), "sg-view", v);
    /* gtk_tree_list_model_new took the creation reference to `roots' (transfer full), so the
       copy kept here needs a reference of its own: without it, closing the window released
       `roots' twice (a segfault). */
    g_object_set_data_full(G_OBJECT(scroll), "sg-roots", g_object_ref(roots), g_object_unref);
    g_object_set_data(G_OBJECT(scroll), "sg-tree-model", m);
    g_object_set_data(G_OBJECT(scroll), "sg-tree-selection", s);
    g_object_set_data_full(G_OBJECT(scroll), "sg-tree-nodes", nodes, (GDestroyNotify) g_ptr_array_unref);
    return id;
}
static void sg_tree_add(int id, int node, int parent, const char *text) {
    GPtrArray *nodes = g_object_get_data(G_OBJECT(sg_w[id]), "sg-tree-nodes");
    GtkStringObject *o = gtk_string_object_new(text);
    GListStore *into;
    g_object_set_data(G_OBJECT(o), "sg-number", GINT_TO_POINTER(node));
    g_object_set_data(G_OBJECT(o), "sg-parent", GINT_TO_POINTER(parent));
    g_object_set_data_full(G_OBJECT(o), "sg-children", g_list_store_new(GTK_TYPE_STRING_OBJECT), g_object_unref);
    g_ptr_array_add(nodes, o);   /* node n at index n - 1; the stores keep it alive */
    if (parent >= 1 && (guint) parent <= nodes->len)
        into = g_object_get_data(G_OBJECT(g_ptr_array_index(nodes, parent - 1)), "sg-children");
    else
        into = G_LIST_STORE(g_object_get_data(G_OBJECT(sg_w[id]), "sg-roots"));
    sg_quiet++;
    g_list_store_append(into, o);
    sg_quiet--;
    g_object_unref(o);
}
/* Expand every ancestor of `node', root first (silently), so its row is shown. */
static void sg_tree_reveal(int id, int node) {
    GPtrArray *nodes = g_object_get_data(G_OBJECT(sg_w[id]), "sg-tree-nodes");
    int chain[256], n = 0, k = node;
    while (k >= 1 && (guint) k <= nodes->len && n < 256) {
        k = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(g_ptr_array_index(nodes, k - 1)), "sg-parent"));
        if (k >= 1) chain[n++] = k;
    }
    sg_quiet++;
    while (n > 0) {
        GtkTreeListRow *r = sg_tree_row(id, chain[--n], NULL);
        if (r) { gtk_tree_list_row_set_expanded(r, TRUE); g_object_unref(r); }
    }
    sg_quiet--;
}
static void sg_tree_set_expanded(int id, int node, int on) {
    GtkTreeListRow *r;
    sg_tree_reveal(id, node);
    r = sg_tree_row(id, node, NULL);
    sg_quiet++;
    if (r) { gtk_tree_list_row_set_expanded(r, on ? TRUE : FALSE); g_object_unref(r); }
    sg_quiet--;
}
static int sg_tree_is_expanded(int id, int node) {
    GtkTreeListRow *r = sg_tree_row(id, node, NULL);
    int e = r ? (gtk_tree_list_row_get_expanded(r) ? 1 : 0) : 0;
    if (r) g_object_unref(r);
    return e;
}
static void sg_tree_select(int id, int node) {
    guint pos = GTK_INVALID_LIST_POSITION;
    GtkTreeListRow *r;
    if (node <= 0) { sg_quiet++; gtk_single_selection_set_selected(sg_tree_selection(id), GTK_INVALID_LIST_POSITION); sg_quiet--; return; }
    sg_tree_reveal(id, node);
    r = sg_tree_row(id, node, &pos);
    if (r) g_object_unref(r);
    sg_quiet++;
    gtk_single_selection_set_selected(sg_tree_selection(id), pos);
    sg_quiet--;
}
static int sg_tree_selected(int id) {
    return sg_row_number(GTK_TREE_LIST_ROW(gtk_single_selection_get_selected_item(sg_tree_selection(id))));
}
/* As a user: the expander clicked (the row's "expanded" changes, not quietly: 15). */
static void sg_test_expand(int id, int node, int on) {
    GtkTreeListRow *r;
    sg_tree_reveal(id, node);
    r = sg_tree_row(id, node, NULL);
    if (r) { gtk_tree_list_row_set_expanded(r, on ? TRUE : FALSE); g_object_unref(r); }
}
/* As a user: the node shown, then its row clicked (4). */
static void sg_test_choose_node(int id, int node) {
    guint pos = GTK_INVALID_LIST_POSITION;
    GtkTreeListRow *r;
    sg_tree_reveal(id, node);
    r = sg_tree_row(id, node, &pos);
    if (r) g_object_unref(r);
    if (pos != GTK_INVALID_LIST_POSITION) gtk_single_selection_set_selected(sg_tree_selection(id), pos);
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

/* ---------- 1g: dropdown (15; event 4, a = row), spin box (16; event 2, a = value),
   progress bar (17), toolbar (18), status bar (19) ---------- */

static void sg_on_dropdown(GObject *o, GParamSpec *p, gpointer d) {
    guint s;
    (void) p; (void) d;
    if (sg_quiet) return;
    s = gtk_drop_down_get_selected(GTK_DROP_DOWN(o));
    if (s != GTK_INVALID_LIST_POSITION && !sg_dd_is_choice(sg_id_of(o), s)) {
        /* a header or separator is never the selection (1p): the next choice is */
        guint n = g_list_model_get_n_items(gtk_drop_down_get_model(GTK_DROP_DOWN(o)));
        while (s < n && !sg_dd_is_choice(sg_id_of(o), s)) s++;
        sg_quiet++;
        gtk_drop_down_set_selected(GTK_DROP_DOWN(o), s < n ? s : GTK_INVALID_LIST_POSITION);
        sg_quiet--;
    }
    s = gtk_drop_down_get_selected(GTK_DROP_DOWN(o));
    sg_push(4, sg_id_of(o), sg_dd_choice_of_pos(sg_id_of(o), s), 0);
}
static int sg_dropdown(void) {
    /* gtk_drop_down_new takes the model's reference (transfer full) */
    GtkWidget *dd = gtk_drop_down_new(G_LIST_MODEL(gtk_string_list_new(NULL)), NULL);
    int id = sg_reg(dd, 15);
    gtk_widget_set_halign(dd, GTK_ALIGN_START);
    g_signal_connect(dd, "notify::selected", G_CALLBACK(sg_on_dropdown), NULL);
    return id;
}
static GtkStringList *sg_dropdown_model(int id) { return GTK_STRING_LIST(gtk_drop_down_get_model(GTK_DROP_DOWN(sg_w[id]))); }
static void sg_dropdown_extend(int id, const char *t) {
    sg_quiet++;
    gtk_string_list_append(sg_dropdown_model(id), t);
    if (sg_dd_choice_of_pos(id, g_list_model_get_n_items(G_LIST_MODEL(sg_dropdown_model(id))) - 1) == 1)
        gtk_drop_down_set_selected(GTK_DROP_DOWN(sg_w[id]), sg_dd_pos_of_choice(id, 1));   /* the first choice is the selection */
    sg_quiet--;
}
static void sg_dropdown_wipe_out(int id) {
    guint n = g_list_model_get_n_items(G_LIST_MODEL(sg_dropdown_model(id)));
    sg_quiet++;
    gtk_string_list_splice(sg_dropdown_model(id), 0, n, NULL);
    sg_quiet--;
}
static void sg_dropdown_select(int id, int row) {
    sg_quiet++;
    gtk_drop_down_set_selected(GTK_DROP_DOWN(sg_w[id]), sg_dd_pos_of_choice(id, row));
    sg_quiet--;
}
static int sg_dropdown_selected(int id) {
    guint s = gtk_drop_down_get_selected(GTK_DROP_DOWN(sg_w[id]));
    if (g_list_model_get_n_items(G_LIST_MODEL(sg_dropdown_model(id))) == 0) return 0;
    return sg_dd_choice_of_pos(id, s);
}

static void sg_on_spin(GtkSpinButton *s, gpointer d) {
    (void) d;
    if (!sg_quiet) sg_push(2, sg_id_of(s), gtk_spin_button_get_value_as_int(s), 0);
}
static int sg_spin_box(int lo, int hi) {
    GtkWidget *s = gtk_spin_button_new_with_range(lo, hi, 1);
    int id = sg_reg(s, 16);
    gtk_spin_button_set_digits(GTK_SPIN_BUTTON(s), 0);
    gtk_spin_button_set_numeric(GTK_SPIN_BUTTON(s), TRUE);
    sg_quiet++; gtk_spin_button_set_value(GTK_SPIN_BUTTON(s), lo); sg_quiet--;
    gtk_widget_set_halign(s, GTK_ALIGN_START);
    g_signal_connect(s, "value-changed", G_CALLBACK(sg_on_spin), NULL);
    return id;
}
static void sg_spin_box_set_value(int id, int v) { sg_quiet++; gtk_spin_button_set_value(GTK_SPIN_BUTTON(sg_w[id]), v); sg_quiet--; }
static int sg_spin_box_value(int id) { return gtk_spin_button_get_value_as_int(GTK_SPIN_BUTTON(sg_w[id])); }
static void sg_spin_box_set_step(int id, int step) { gtk_spin_button_set_increments(GTK_SPIN_BUTTON(sg_w[id]), step, step * 10.0); }
static void sg_test_set_number(int id, int v) { gtk_spin_button_set_value(GTK_SPIN_BUTTON(sg_w[id]), v); }   /* emits */

static int sg_progress_bar(void) {
    GtkWidget *p = gtk_progress_bar_new();
    int id = sg_reg(p, 17);
    gtk_widget_set_hexpand(p, TRUE);
    gtk_widget_set_valign(p, GTK_ALIGN_CENTER);
    return id;
}
/* The percent is kept as given: the fraction would not round-trip every integer. */
static void sg_progress_bar_set(int id, int percent) {
    g_object_set_data(G_OBJECT(sg_w[id]), "sg-percent", GINT_TO_POINTER(percent));
    gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(sg_w[id]), percent / 100.0);
}
static int sg_progress_bar_value(int id) { return GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-percent")); }

static int sg_toolbar(void) {
    GtkWidget *b = g_object_new(GTK_TYPE_BOX, "orientation", GTK_ORIENTATION_HORIZONTAL, "spacing", 4,
                                "accessible-role", GTK_ACCESSIBLE_ROLE_TOOLBAR, NULL);
    gtk_widget_add_css_class(b, "toolbar");
    gtk_widget_set_margin_start(b, 4); gtk_widget_set_margin_end(b, 4);
    gtk_widget_set_margin_top(b, 4); gtk_widget_set_margin_bottom(b, 4);
    return sg_reg(b, 18);
}
static void sg_toolbar_extend(int tb, int button) { gtk_box_append(GTK_BOX(sg_w[tb]), sg_w[button]); }
static void sg_toolbar_add_separator(int tb) { gtk_box_append(GTK_BOX(sg_w[tb]), gtk_separator_new(GTK_ORIENTATION_VERTICAL)); }

static int sg_status_bar(void) {
    GtkWidget *l = g_object_new(GTK_TYPE_LABEL, "label", "", "xalign", 0.0f,
                                "accessible-role", GTK_ACCESSIBLE_ROLE_STATUS, NULL);
    gtk_widget_set_margin_start(l, 8); gtk_widget_set_margin_end(l, 8);
    gtk_widget_set_margin_top(l, 3); gtk_widget_set_margin_bottom(l, 3);
    return sg_reg(l, 19);
}
static void sg_status_bar_set_text(int id, const char *t) { gtk_label_set_text(GTK_LABEL(sg_w[id]), t); }
static const char *sg_status_bar_text(int id) { return gtk_label_get_text(GTK_LABEL(sg_w[id])); }

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

/* ---------- system colors (0xRRGGBB) ---------- */

static int sg_is_dark(void);

/* role: 1 window background, 2 text, 3 secondary text, 4 accent, 5 selection, 6 separator.
   Read from the theme's named colors (Adwaita defines them); a fallback if a theme lacks one. */
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
    if (sg_kind[id] == 7 || sg_kind[id] == 13 || sg_kind[id] == 14 || sg_kind[id] == 33) {
        g_object_set_data(G_OBJECT(sg_w[id]), "sg-dir", GINT_TO_POINTER((int) l_dir + 1));
        sg_direction_tree(sg_w[id], l_dir);
    }
    if (sg_kind[id] == 1) {
        GtkWidget *bar = g_object_get_data(G_OBJECT(sg_w[id]), "sg-bar");
        GtkWidget *outer = g_object_get_data(G_OBJECT(sg_w[id]), "sg-outer");
        static const char *slots[] = {"sg-top", "sg-mid", "sg-bottom", NULL};
        int s;
        if (outer) gtk_widget_set_direction(outer, l_dir);
        for (s = 0; slots[s]; s++) {
            GtkWidget *slot = g_object_get_data(G_OBJECT(sg_w[id]), slots[s]);
            if (slot) gtk_widget_set_direction(slot, l_dir);
        }
        if (bar) {
            g_object_set_data(G_OBJECT(bar), "sg-dir", GINT_TO_POINTER((int) l_dir));
            sg_direction_tree(bar, l_dir);
        }
    }
}

/* ---------- tabs: a GtkNotebook (kind 11). Choosing a tab sends page changed (13);
   appending and selecting from code send nothing. (MACMINI's first pass; PROD's GTK half.) ---------- */

/* GTK 4.14 gives each tab ("tab" role, an internal widget) no accessible name: the title is a
   label inside it (probed). Name the tab itself, so a screen reader reads "tab: First". The
   tab label's parent is that tab widget. */
static void sg_name_tab(GtkNotebook *nb, GtkWidget *page, const char *title) {
    GtkWidget *label = gtk_notebook_get_tab_label(nb, page);
    GtkWidget *tab = label ? gtk_widget_get_parent(label) : NULL;
    if (tab) {
        gtk_accessible_update_property(GTK_ACCESSIBLE(tab), GTK_ACCESSIBLE_PROPERTY_LABEL, title, -1);
        g_object_set_data_full(G_OBJECT(tab), "sg-a11y", g_strdup(title), g_free);
    }
}

static void sg_on_switch_page(GtkNotebook *nb, GtkWidget *page, guint num, gpointer d) {
    (void) page; (void) d;
    if (!sg_quiet) sg_push(13, sg_id_of(nb), (int) num + 1, 0);
}
static int sg_tabs(void) {
    GtkWidget *nb = gtk_notebook_new();
    gtk_notebook_set_scrollable(GTK_NOTEBOOK(nb), TRUE);
    g_signal_connect(nb, "switch-page", G_CALLBACK(sg_on_switch_page), NULL);
    return sg_reg(nb, 11);
}
static void sg_tabs_extend(int tabs, int page, const char *title) {
    sg_quiet++;
    gtk_notebook_append_page(GTK_NOTEBOOK(sg_w[tabs]), sg_w[page], gtk_label_new(title));
    sg_name_tab(GTK_NOTEBOOK(sg_w[tabs]), sg_w[page], title);
    sg_quiet--;
}
static void sg_tabs_select(int tabs, int page) {
    sg_quiet++;
    gtk_notebook_set_current_page(GTK_NOTEBOOK(sg_w[tabs]), page - 1);
    sg_quiet--;
}
static int sg_tabs_selected(int tabs) {
    int n = gtk_notebook_get_current_page(GTK_NOTEBOOK(sg_w[tabs]));
    return n < 0 ? 0 : n + 1;
}
static void sg_tabs_set_title(int tabs, int page, const char *title) {
    GtkNotebook *nb = GTK_NOTEBOOK(sg_w[tabs]);
    GtkWidget *p = gtk_notebook_get_nth_page(nb, page - 1);
    if (p) {
        GtkWidget *box_title = g_object_get_data(G_OBJECT(p), "sg-tab-title");
        if (box_title) gtk_label_set_text(GTK_LABEL(box_title), title);
        else gtk_notebook_set_tab_label_text(nb, p, title);
        sg_name_tab(nb, p, title);
    }
}

/* ---------- canvas: present a finished Cairo image ---------- */

/* Device pixels per logical pixel: the surface's own scale, fractional under Wayland's
   fractional scaling (GTK 4.12+); the whole-number factor before the widget is realized. */
static double sg_scale(int id) {
    GtkNative *n = sg_w[id] ? gtk_widget_get_native(sg_w[id]) : NULL;
    GdkSurface *s = n ? gtk_native_get_surface(n) : NULL;
    double v = s ? gdk_surface_get_scale(s) : 0.0;
    return v > 0.0 ? v : sg_w[id] ? (double) gtk_widget_get_scale_factor(sg_w[id]) : 1.0;
}
static void sg_canvas_draw(GtkDrawingArea *a, cairo_t *cr, int w, int h, gpointer d) {
    int id = GPOINTER_TO_INT(d);
    cairo_surface_t *img = sg_canvas_image[id];
    double scale = sg_scale(id);
    (void) a;
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
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(click), 0);   /* every button, not just the primary */
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
/* 0 for a slot that went empty (a drawn view destroyed with its window). */
static int sg_width(int id) { return sg_w[id] ? gtk_widget_get_width(sg_w[id]) : 0; }
static int sg_height(int id) { return sg_w[id] ? gtk_widget_get_height(sg_w[id]) : 0; }
/* Keep a reference to `image' (a cairo_surface_t) and redraw. The caller keeps its own reference. */
static void sg_canvas_present(int id, void *image) {
    if (sg_canvas_image[id]) cairo_surface_destroy(sg_canvas_image[id]);
    sg_canvas_image[id] = image ? cairo_surface_reference((cairo_surface_t *) image) : NULL;
    gtk_widget_queue_draw(sg_w[id]);
}

/* ---------- 1i: the drawn view (kind 50). A GUI_DRAWN hosts a simple_widgets window in it: a
   canvas (its draw and resize, 9 in logical pixels) with the whole input SW needs.
   18 pointer (c = kind + button * 16 + modifiers * 256; kind 1 press, 2 release, 3 move,
   4 leave, 5 double press, 6 triple press; button 1 primary, 2 secondary, 3 middle),
   19 wheel (c = delta, 120 a notch, positive away from the user), 20 key (a = GDK keyval,
   b = 1 down or 0 up), 21 character (a = code point; Return, Tab, Backspace and Escape too,
   as 13, 9, 8, 27, as the Windows WM_CHAR gives them), 22 focus (a = 1 in), 23 timers (a = 0
   the tick, 1 the fast tick, 2 the dwell shot with b = its serial). Text is the key's own
   character (no input method: committed text only, as SW has it). ---------- */
static int sg_drawn_button(GtkGestureSingle *g) {
    guint b = gtk_gesture_single_get_current_button(g);
    return b == 1 ? 1 : b == 3 ? 2 : b == 2 ? 3 : 0;
}
static int sg_drawn_held(GdkModifierType m) {
    return (m & GDK_BUTTON1_MASK) ? 1 : (m & GDK_BUTTON3_MASK) ? 2 : (m & GDK_BUTTON2_MASK) ? 3 : 0;
}
static void sg_drawn_pointer(GtkEventController *c, int id, int kind, int button, double x, double y) {
    GdkModifierType m = gtk_event_controller_get_current_event_state(c);
    g_object_set_data(G_OBJECT(sg_w[id]), "sg-px", GINT_TO_POINTER((int) lround(x)));
    g_object_set_data(G_OBJECT(sg_w[id]), "sg-py", GINT_TO_POINTER((int) lround(y)));
    sg_push5(18, id, (int) lround(x), (int) lround(y), kind + button * 16 + sg_mods(m) * 256);
}
static void sg_drawn_pressed(GtkGestureClick *g, int n, double x, double y, gpointer d) {
    int id = GPOINTER_TO_INT(d);
    gtk_widget_grab_focus(sg_w[id]);
    sg_drawn_pointer(GTK_EVENT_CONTROLLER(g), id, n == 2 ? 5 : n >= 3 ? 6 : 1, sg_drawn_button(GTK_GESTURE_SINGLE(g)), x, y);
}
static void sg_drawn_released(GtkGestureClick *g, int n, double x, double y, gpointer d) {
    (void) n;
    sg_drawn_pointer(GTK_EVENT_CONTROLLER(g), GPOINTER_TO_INT(d), 2, sg_drawn_button(GTK_GESTURE_SINGLE(g)), x, y);
}
static void sg_drawn_motion(GtkEventControllerMotion *c, double x, double y, gpointer d) {
    sg_drawn_pointer(GTK_EVENT_CONTROLLER(c), GPOINTER_TO_INT(d), 3,
        sg_drawn_held(gtk_event_controller_get_current_event_state(GTK_EVENT_CONTROLLER(c))), x, y);
}
static void sg_drawn_leave(GtkEventControllerMotion *c, gpointer d) {
    int id = GPOINTER_TO_INT(d);
    sg_push5(18, id, GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-px")),
        GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-py")),
        4 + sg_mods(gtk_event_controller_get_current_event_state(GTK_EVENT_CONTROLLER(c))) * 256);
}
static gboolean sg_drawn_scroll(GtkEventControllerScroll *c, double dx, double dy, gpointer d) {
    int id = GPOINTER_TO_INT(d), delta = (int) lround(-dy * 120.0);
    (void) c; (void) dx;
    if (delta != 0)
        sg_push5(19, id, GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-px")),
            GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-py")), delta);
    return TRUE;
}
static gboolean sg_drawn_key(GtkEventControllerKey *c, guint keyval, guint code, GdkModifierType m, gpointer d) {
    int id = GPOINTER_TO_INT(d);
    gunichar u = gdk_keyval_to_unicode(keyval);
    (void) c; (void) code;
    sg_push5(20, id, (int) keyval, 1, sg_mods(m) * 256);
    if (keyval == GDK_KEY_Return || keyval == GDK_KEY_KP_Enter) u = 13;
    else if (keyval == GDK_KEY_Tab || keyval == GDK_KEY_ISO_Left_Tab) u = 9;
    else if (keyval == GDK_KEY_BackSpace) u = 8;
    else if (keyval == GDK_KEY_Escape) u = 27;
    /* Control, Alt and Super keys are shortcuts, not text */
    if (u != 0 && !(m & (GDK_CONTROL_MASK | GDK_ALT_MASK | GDK_SUPER_MASK))) sg_push5(21, id, (int) u, 0, 0);
    return TRUE;
}
static void sg_drawn_key_up(GtkEventControllerKey *c, guint keyval, guint code, GdkModifierType m, gpointer d) {
    (void) c; (void) code;
    sg_push5(20, GPOINTER_TO_INT(d), (int) keyval, 0, sg_mods(m) * 256);
}
static void sg_drawn_focus_in(GtkEventControllerFocus *f, gpointer d) { (void) f; sg_push5(22, GPOINTER_TO_INT(d), 1, 0, 0); }
static void sg_drawn_focus_out(GtkEventControllerFocus *f, gpointer d) { (void) f; sg_push5(22, GPOINTER_TO_INT(d), 0, 0, 0); }
static gboolean sg_drawn_tick(gpointer d) { sg_push5(23, GPOINTER_TO_INT(d), 0, 0, 0); return G_SOURCE_CONTINUE; }
static gboolean sg_drawn_fast(gpointer d) { sg_push5(23, GPOINTER_TO_INT(d), 1, 0, 0); return G_SOURCE_CONTINUE; }
static void sg_drawn_stop(GtkWidget *w, const char *key) {
    guint s = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(w), key));
    if (s) { g_source_remove(s); g_object_set_data(G_OBJECT(w), key, NULL); }
}
static void sg_drawn_destroyed(GtkWidget *w, gpointer d) {
    int id = sg_id_of(w);
    (void) d;
    /* its slot goes empty: the drawn calls below ignore a view that is gone */
    if (id > 0 && sg_w[id] == w) sg_w[id] = NULL;
    sg_drawn_stop(w, "sg-tick");
    sg_drawn_stop(w, "sg-fast");
    sg_drawn_stop(w, "sg-dwell");
}
static int sg_drawn(int w, int h) {
    GtkWidget *a = g_object_new(GTK_TYPE_DRAWING_AREA, "accessible-role", GTK_ACCESSIBLE_ROLE_GROUP, NULL);
    GtkGesture *click = gtk_gesture_click_new();
    GtkEventController *motion = gtk_event_controller_motion_new();
    GtkEventController *scroll = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_VERTICAL);
    GtkEventController *keys = gtk_event_controller_key_new();
    GtkEventController *focus = gtk_event_controller_focus_new();
    int id = sg_reg(a, 50);
    g_object_set_data(G_OBJECT(a), "sg-drawn", GINT_TO_POINTER(1));
    gtk_drawing_area_set_content_width(GTK_DRAWING_AREA(a), w);
    gtk_drawing_area_set_content_height(GTK_DRAWING_AREA(a), h);
    gtk_widget_set_hexpand(a, TRUE);
    gtk_widget_set_vexpand(a, TRUE);
    gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(a), sg_canvas_draw, GINT_TO_POINTER(id), NULL);
    g_signal_connect(a, "resize", G_CALLBACK(sg_canvas_resized), GINT_TO_POINTER(id));
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(click), 0);
    g_signal_connect(click, "pressed", G_CALLBACK(sg_drawn_pressed), GINT_TO_POINTER(id));
    g_signal_connect(click, "released", G_CALLBACK(sg_drawn_released), GINT_TO_POINTER(id));
    gtk_widget_add_controller(a, GTK_EVENT_CONTROLLER(click));
    g_signal_connect(motion, "motion", G_CALLBACK(sg_drawn_motion), GINT_TO_POINTER(id));
    g_signal_connect(motion, "leave", G_CALLBACK(sg_drawn_leave), GINT_TO_POINTER(id));
    gtk_widget_add_controller(a, motion);
    g_signal_connect(scroll, "scroll", G_CALLBACK(sg_drawn_scroll), GINT_TO_POINTER(id));
    gtk_widget_add_controller(a, scroll);
    g_signal_connect(keys, "key-pressed", G_CALLBACK(sg_drawn_key), GINT_TO_POINTER(id));
    g_signal_connect(keys, "key-released", G_CALLBACK(sg_drawn_key_up), GINT_TO_POINTER(id));
    gtk_widget_add_controller(a, keys);
    g_signal_connect(focus, "enter", G_CALLBACK(sg_drawn_focus_in), GINT_TO_POINTER(id));
    g_signal_connect(focus, "leave", G_CALLBACK(sg_drawn_focus_out), GINT_TO_POINTER(id));
    gtk_widget_add_controller(a, focus);
    g_signal_connect(a, "destroy", G_CALLBACK(sg_drawn_destroyed), NULL);
    gtk_widget_set_focusable(a, TRUE);
    return id;
}
/* The top-left w by h device pixels of the hosted frame (which may be larger: it grows in
   steps), copied, so the next frame can be drawn while this one shows. */
static void sg_drawn_present(int id, void *surface, int w, int h) {
    cairo_surface_t *s = (cairo_surface_t *) surface, *copy;
    cairo_t *cr;
    if (!sg_w[id] || !s || w <= 0 || h <= 0 || cairo_surface_get_type(s) != CAIRO_SURFACE_TYPE_IMAGE) return;
    cairo_surface_flush(s);
    if (w > cairo_image_surface_get_width(s)) w = cairo_image_surface_get_width(s);
    if (h > cairo_image_surface_get_height(s)) h = cairo_image_surface_get_height(s);
    copy = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
    cr = cairo_create(copy);
    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
    cairo_set_source_surface(cr, s, 0, 0);
    cairo_paint(cr);
    cairo_destroy(cr);
    if (sg_canvas_image[id]) cairo_surface_destroy(sg_canvas_image[id]);
    sg_canvas_image[id] = copy;
    gtk_widget_queue_draw(sg_w[id]);
}
static void sg_drawn_set_cursor(int id, int kind) {
    static const char *names[] = {"default", "text", "pointer", "ew-resize", "ns-resize", "crosshair", "wait"};
    if (!sg_w[id]) return;
    gtk_widget_set_cursor_from_name(sg_w[id], names[kind >= 0 && kind <= 6 ? kind : 0]);
}
static void sg_drawn_set_ticks(int id, int tick_ms, int fast_ms) {
    GtkWidget *w = sg_w[id];
    if (!w) return;
    sg_drawn_stop(w, "sg-tick");
    sg_drawn_stop(w, "sg-fast");
    if (tick_ms > 0) g_object_set_data(G_OBJECT(w), "sg-tick", GUINT_TO_POINTER(g_timeout_add((guint) tick_ms, sg_drawn_tick, GINT_TO_POINTER(id))));
    if (fast_ms > 0) g_object_set_data(G_OBJECT(w), "sg-fast", GUINT_TO_POINTER(g_timeout_add((guint) fast_ms, sg_drawn_fast, GINT_TO_POINTER(id))));
}
static gboolean sg_drawn_dwell(gpointer d) {
    int id = GPOINTER_TO_INT(d);
    if (sg_w[id]) {
        g_object_set_data(G_OBJECT(sg_w[id]), "sg-dwell", NULL);
        sg_push5(23, id, 2, GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-dwell-serial")), 0);
    }
    return G_SOURCE_REMOVE;
}
static void sg_drawn_arm_dwell(int id, int ms, int serial) {
    GtkWidget *w = sg_w[id];
    if (!w) return;
    sg_drawn_stop(w, "sg-dwell");
    g_object_set_data(G_OBJECT(w), "sg-dwell-serial", GINT_TO_POINTER(serial));
    if (ms > 0) g_object_set_data(G_OBJECT(w), "sg-dwell", GUINT_TO_POINTER(g_timeout_add((guint) ms, sg_drawn_dwell, GINT_TO_POINTER(id))));
}
static void sg_drawn_set_description(int id, const char *text) {
    if (!sg_w[id]) return;
    g_object_set_data_full(G_OBJECT(sg_w[id]), "sg-drawn-tree", g_strdup(text ? text : ""), g_free);
}

/* ---------- menus ---------- */

/* Shortcut "primary+O" -> "<Control>o" (GTK has no Cmd); "" for none. */
/* The GDK key name for a key in the shared shortcut vocabulary (SW_SHORTCUT's names): "Enter"
   is GDK's "Return", "PageUp" its "Page_Up", "Backspace" its "BackSpace"; one character is
   lowercased; F1..F12 stay. Anything else passes through. */
static void sg_gdk_key_name(const char *part, char *out, size_t n) {
    static const char *pairs[][2] = {
        {"enter", "Return"}, {"return", "Return"}, {"esc", "Escape"}, {"escape", "Escape"},
        {"del", "Delete"}, {"delete", "Delete"}, {"ins", "Insert"}, {"insert", "Insert"},
        {"backspace", "BackSpace"}, {"pageup", "Page_Up"}, {"pgup", "Page_Up"},
        {"pagedown", "Page_Down"}, {"pgdn", "Page_Down"}, {"home", "Home"}, {"end", "End"},
        {"left", "Left"}, {"right", "Right"}, {"up", "Up"}, {"down", "Down"}, {"tab", "Tab"},
        {"space", "space"}, {"plus", "plus"}, {"equal", "equal"}, {"minus", "minus"},
        {"comma", "comma"}, {"period", "period"}, {NULL, NULL}};
    int i;
    for (i = 0; pairs[i][0]; i++)
        if (!g_ascii_strcasecmp(part, pairs[i][0])) { g_strlcat(out, pairs[i][1], n); return; }
    if ((part[0] == 'f' || part[0] == 'F') && part[1] >= '1' && part[1] <= '9') {
        char up[8]; g_snprintf(up, sizeof up, "F%s", part + 1); g_strlcat(out, up, n); return;
    }
    if (strlen(part) == 1) { char c[2] = { g_ascii_tolower(part[0]), 0 }; g_strlcat(out, c, n); return; }
    g_strlcat(out, part, n);
}
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
            if (!g_ascii_strcasecmp(part, "primary") || !g_ascii_strcasecmp(part, "ctrl")
                || !g_ascii_strcasecmp(part, "control")) g_strlcat(out, "<Control>", n);
            else if (!g_ascii_strcasecmp(part, "shift")) g_strlcat(out, "<Shift>", n);
            else if (!g_ascii_strcasecmp(part, "alt")) g_strlcat(out, "<Alt>", n);
            p = plus + 1;
        } else {
            sg_gdk_key_name(part, out, n);
            break;
        }
    }
}
__attribute__((weak)) GtkShortcutController *sg_shortcuts = NULL;

/* A top-level menu (returns its GMenu as an opaque handle). */
/* Where each item lives, so it can be relabeled (a GMenu item cannot change in place:
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
static void sg_menu_rebuild_item(int item_id, const char *text);
static void sg_menu_set_item_text(int item_id, const char *text) { sg_menu_rebuild_item(item_id, text); }
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
static const char *sg_edit_names[] = {"undo", "redo", "cut", "copy", "paste", "select_all"};
static void sg_menu_add_edit_role(void *menu, const char *text, int role, int item_id) {
    static const char *actions[] = {"text.undo", "text.redo", "clipboard.cut", "clipboard.copy", "clipboard.paste", "selection.select-all"};
    char name[32], detailed[40];
    if (role < 10 || role > 15) return;
    snprintf(name, sizeof name, "edit_%s", sg_edit_names[role - 10]);
    snprintf(detailed, sizeof detailed, "app.%s", name);
    if (!g_action_map_lookup_action(G_ACTION_MAP(sg_actions), name)) {
        GSimpleAction *a = g_simple_action_new(name, NULL);
        g_signal_connect(a, "activate", G_CALLBACK(sg_on_edit), (gpointer) actions[role - 10]);
        g_action_map_add_action(G_ACTION_MAP(sg_actions), G_ACTION(a));
    }
    sg_remember_item(item_id, G_MENU(menu), g_menu_model_get_n_items(G_MENU_MODEL(menu)), detailed, NULL);
    g_menu_append(G_MENU(menu), text, detailed);
}

/* ---------- the Edit roles' enabled state (1e). GTK 4 has no public query for whether a
   widget's own action (clipboard.copy and the rest) is enabled, so it is worked out here from
   the focused widget of the active window, and set on our six edit actions whenever the loop
   is pumped (only changes are applied). A disabled app action lets the key fall through to the
   field's own binding, so Ctrl+C still works there. ---------- */
static GtkWidget *sg_active_focus(void) {
    int i;
    GtkWidget *f = NULL;
    for (i = 1; i < sg_n; i++)
        if (sg_kind[i] == 1 && sg_w[i] && gtk_window_is_active(GTK_WINDOW(sg_w[i])))
            return gtk_root_get_focus(GTK_ROOT(sg_w[i]));
    /* no active window (a test run's window may never be activated): the first with a focus */
    for (i = 1; i < sg_n && !f; i++)
        if (sg_kind[i] == 1 && sg_w[i] && gtk_widget_get_visible(sg_w[i])) f = gtk_root_get_focus(GTK_ROOT(sg_w[i]));
    return f;
}
static int sg_clipboard_has_text(GtkWidget *w) {
    GdkContentFormats *f = gdk_clipboard_get_formats(gtk_widget_get_clipboard(w));
    return gdk_content_formats_contain_gtype(f, G_TYPE_STRING)
        || gdk_content_formats_contain_mime_type(f, "text/plain;charset=utf-8")
        || gdk_content_formats_contain_mime_type(f, "text/plain");
}
static int sg_edit_can(GtkWidget *f, int role) {
    if (!f) return 0;
    if (GTK_IS_TEXT_VIEW(f)) {
        GtkTextBuffer *b = gtk_text_view_get_buffer(GTK_TEXT_VIEW(f));
        int ed = gtk_text_view_get_editable(GTK_TEXT_VIEW(f));
        int sel = gtk_text_buffer_get_has_selection(b);
        switch (role) {
        case 10: return ed && gtk_text_buffer_get_can_undo(b);
        case 11: return ed && gtk_text_buffer_get_can_redo(b);
        case 12: return ed && sel;
        case 13: return sel;
        case 14: return ed && sg_clipboard_has_text(f);
        case 15: return gtk_text_buffer_get_char_count(b) > 0;
        }
    } else if (GTK_IS_EDITABLE(f)) {
        int s = 0, e = 0;
        int ed = gtk_editable_get_editable(GTK_EDITABLE(f));
        int sel = gtk_editable_get_selection_bounds(GTK_EDITABLE(f), &s, &e);
        const char *t = gtk_editable_get_text(GTK_EDITABLE(f));
        switch (role) {
        case 10: case 11: return ed && gtk_editable_get_enable_undo(GTK_EDITABLE(f));
        case 12: return ed && sel;
        case 13: return sel;
        case 14: return ed && sg_clipboard_has_text(f);
        case 15: return t != NULL && *t != 0;
        }
    }
    return 0;
}
static void sg_update_edit_enabled(void) {
    int r;
    char name[32];
    GtkWidget *f;
    if (!sg_actions) return;
    f = sg_active_focus();
    for (r = 10; r <= 15; r++) {
        GAction *a;
        snprintf(name, sizeof name, "edit_%s", sg_edit_names[r - 10]);
        a = g_action_map_lookup_action(G_ACTION_MAP(sg_actions), name);
        if (a) {
            gboolean on = sg_edit_can(f, r) != 0;
            if (g_action_get_enabled(a) != on) g_simple_action_set_enabled(G_SIMPLE_ACTION(a), on);
        }
    }
}
/* Test doors: focus a widget as a click would; is Edit role `role' enabled now? */
static void sg_test_focus(int id) { if (sg_w[id]) gtk_widget_grab_focus(sg_w[id]); }
static int sg_test_edit_enabled(int role) {
    char name[32];
    GAction *a;
    if (role < 10 || role > 15 || !sg_actions) return 0;
    sg_update_edit_enabled();
    snprintf(name, sizeof name, "edit_%s", sg_edit_names[role - 10]);
    a = g_action_map_lookup_action(G_ACTION_MAP(sg_actions), name);
    return a ? (g_action_get_enabled(a) ? 1 : 0) : sg_edit_can(sg_active_focus(), role);
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
    g_object_set_data(G_OBJECT(w), "sg-a11y-own", GINT_TO_POINTER(1));
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
/* The text of the first label below `w' (depth first), or NULL. */
static const char *sg_first_label_text(GtkWidget *w) {
    GtkWidget *c;
    for (c = gtk_widget_get_first_child(w); c; c = gtk_widget_get_next_sibling(c)) {
        const char *s = GTK_IS_LABEL(c) ? gtk_label_get_text(GTK_LABEL(c)) : sg_first_label_text(c);
        if (s && *s) return s;
    }
    return NULL;
}
/* ARIA's "name from content" roles: with no name of their own, a screen reader reads their text. */
static int sg_named_from_content(const char *role) {
    static const char *roles[] = {"tab", "column-header", "row-header", "grid-cell", "cell",
        "tree-item", "list-item", "row", "menu-item", NULL};
    int i;
    for (i = 0; roles[i]; i++) if (!strcmp(role, roles[i])) return 1;
    return 0;
}
static void sg_describe_walk(GtkWidget *w, int depth) {
    GtkWidget *c;
    const char *role;
    if (g_object_get_data(G_OBJECT(w), "sg-drawn")) {
        /* A drawn view (1i): a group named by its label, with the hosted window's own tree under
           it (its first line, the hosted window itself, left out), as on macOS. */
        const char *tree = g_object_get_data(G_OBJECT(w), "sg-drawn-tree");
        const char *label = g_object_get_data(G_OBJECT(w), "sg-a11y");
        gchar **lines = g_strsplit(tree ? tree : "", "\n", -1);
        int i, k;
        for (i = 0; i < depth; i++) g_string_append(sg_describe_buf, "  ");
        g_string_append_printf(sg_describe_buf, "group: %s\n", label ? label : "");
        for (k = 1; lines[k]; k++) {
            const char *s = lines[k];
            while (*s == ' ') s++;
            if (!*s) continue;
            for (i = 0; i <= depth; i++) g_string_append(sg_describe_buf, "  ");
            g_string_append_printf(sg_describe_buf, "%s\n", s);
        }
        g_strfreev(lines);
        return;
    }
    role = sg_role_nick(w);
    const char *name = g_object_get_data(G_OBJECT(w), "sg-a11y");
    if (!name && GTK_IS_LABEL(w)) name = gtk_label_get_text(GTK_LABEL(w));
    if (!name && GTK_IS_BUTTON(w)) name = gtk_button_get_label(GTK_BUTTON(w));
    if (!name && GTK_IS_CHECK_BUTTON(w)) name = gtk_check_button_get_label(GTK_CHECK_BUTTON(w));
    if (!name && sg_named_from_content(role)) name = sg_first_label_text(w);
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
__attribute__((weak)) int sg_auto_cancel_ms = 0;   /* tests: cancel each dialog this long after it opens */

static gboolean sg_cancel_now(gpointer c) { g_cancellable_cancel(G_CANCELLABLE(c)); return G_SOURCE_REMOVE; }
/* A cancellable for one dialog; with auto-cancel on, a timer cancels it (the timer holds a reference). */
static GCancellable *sg_dialog_cancellable(void) {
    GCancellable *c = g_cancellable_new();
    if (sg_auto_cancel_ms > 0) g_timeout_add_full(G_PRIORITY_DEFAULT, (guint) sg_auto_cancel_ms, sg_cancel_now, g_object_ref(c), g_object_unref);
    return c;
}
static void sg_test_auto_cancel_dialogs(int ms) { sg_auto_cancel_ms = ms > 0 ? ms : 0; }

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
    {
        GCancellable *c = sg_dialog_cancellable();
        if (save) gtk_file_dialog_save(dlg, win > 0 ? GTK_WINDOW(sg_w[win]) : NULL, c, sg_save_done, NULL);
        else gtk_file_dialog_open(dlg, win > 0 ? GTK_WINDOW(sg_w[win]) : NULL, c, sg_open_done, NULL);
        sg_wait_dialog();
        g_object_unref(c);
    }
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
    {
        GCancellable *c = sg_dialog_cancellable();
        gtk_alert_dialog_choose(dlg, win > 0 ? GTK_WINDOW(sg_w[win]) : NULL, c, sg_alert_done, NULL);
        sg_wait_dialog();
        g_object_unref(c);
    }
    g_object_unref(dlg);
    return confirm ? (sg_dialog_choice == 1 ? 1 : 0) : 1;
}

static void sg_calendar_set(int id, int v);
static int sg_calendar_value(int id);
/* ---------- 1h: radio group (20) and segmented control (21) - event 4, a = choice;
   slider (22) - 2, a = value, on every move; switch (23) - 12, a = 1 on; date (24) - 2,
   a = y*10000 + m*100 + d; time (25) - 2, a = h*60 + m; color (26) - 2, a = 0xRRGGBB;
   scroll area (27); image (28); separator (29); group box (30); expander (31) - 12,
   a = 1 open; editable combo (32) - 2 on a commit; tree table (33) - the tree's 4 and 15.
   Every setter is quiet; the sg_test_ hooks act as a user and emit. ---------- */

/* Radio group and segmented control: a box of grouped buttons, each carrying the group's id
   ("sg-id") and its 1-based place ("sg-index"); the box answers for the group. */
static void sg_on_choice(GtkWidget *b, gpointer d) {
    gboolean on;
    (void) d;
    on = GTK_IS_CHECK_BUTTON(b) ? gtk_check_button_get_active(GTK_CHECK_BUTTON(b))
                                : gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(b));
    if (on && !sg_quiet) sg_push(4, sg_id_of(b), GPOINTER_TO_INT(g_object_get_data(G_OBJECT(b), "sg-index")), 0);
}
static int sg_choices(int horizontal, int segmented) {
    GtkWidget *box = g_object_new(GTK_TYPE_BOX,
        "orientation", (horizontal || segmented) ? GTK_ORIENTATION_HORIZONTAL : GTK_ORIENTATION_VERTICAL,
        "spacing", segmented ? 0 : 4, "accessible-role", GTK_ACCESSIBLE_ROLE_RADIO_GROUP, NULL);
    if (segmented) gtk_widget_add_css_class(box, "linked");
    gtk_widget_set_halign(box, GTK_ALIGN_START);
    return sg_reg(box, segmented ? 21 : 20);
}
static int sg_radio_group(int horizontal) { return sg_choices(horizontal, 0); }
static int sg_segmented(void) { return sg_choices(1, 1); }
static int sg_choice_count(int id) {
    int n = 0; GtkWidget *c;
    for (c = gtk_widget_get_first_child(sg_w[id]); c; c = gtk_widget_get_next_sibling(c)) n++;
    return n;
}
static GtkWidget *sg_choice_at(int id, int i) {
    GtkWidget *c; int n = 1;
    for (c = gtk_widget_get_first_child(sg_w[id]); c; c = gtk_widget_get_next_sibling(c), n++) if (n == i) return c;
    return NULL;
}
static void sg_choice_set(GtkWidget *b, gboolean on) {
    if (GTK_IS_CHECK_BUTTON(b)) gtk_check_button_set_active(GTK_CHECK_BUTTON(b), on);
    else gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(b), on);
}
static void sg_choices_extend(int id, const char *t) {
    GtkWidget *first = gtk_widget_get_first_child(sg_w[id]), *b;
    int n = sg_choice_count(id) + 1;
    if (sg_kind[id] == 21) {
        b = g_object_new(GTK_TYPE_TOGGLE_BUTTON, "label", t, "accessible-role", GTK_ACCESSIBLE_ROLE_RADIO, NULL);
        if (first) gtk_toggle_button_set_group(GTK_TOGGLE_BUTTON(b), GTK_TOGGLE_BUTTON(first));
        g_signal_connect(b, "toggled", G_CALLBACK(sg_on_choice), NULL);
    } else {
        /* a radio from the start: the first button has no group yet and would read as a check box */
        b = g_object_new(GTK_TYPE_CHECK_BUTTON, "label", t, "accessible-role", GTK_ACCESSIBLE_ROLE_RADIO, NULL);
        if (first) gtk_check_button_set_group(GTK_CHECK_BUTTON(b), GTK_CHECK_BUTTON(first));
        g_signal_connect(b, "toggled", G_CALLBACK(sg_on_choice), NULL);
    }
    g_object_set_data(G_OBJECT(b), "sg-id", GINT_TO_POINTER(id));
    g_object_set_data(G_OBJECT(b), "sg-index", GINT_TO_POINTER(n));
    gtk_box_append(GTK_BOX(sg_w[id]), b);
    if (n == 1) { sg_quiet++; sg_choice_set(b, TRUE); sg_quiet--; }   /* the first is the choice */
}
static void sg_choices_wipe_out(int id) {
    GtkWidget *c;
    sg_quiet++;
    while ((c = gtk_widget_get_first_child(sg_w[id]))) gtk_box_remove(GTK_BOX(sg_w[id]), c);
    sg_quiet--;
}
static void sg_choices_select(int id, int i) {
    GtkWidget *b = sg_choice_at(id, i);
    sg_quiet++; if (b) sg_choice_set(b, TRUE); sg_quiet--;
}
static int sg_choices_selected(int id) {
    GtkWidget *c; int n = 1;
    for (c = gtk_widget_get_first_child(sg_w[id]); c; c = gtk_widget_get_next_sibling(c), n++) {
        gboolean on = GTK_IS_CHECK_BUTTON(c) ? gtk_check_button_get_active(GTK_CHECK_BUTTON(c))
                                             : gtk_toggle_button_get_active(GTK_TOGGLE_BUTTON(c));
        if (on) return n;
    }
    return 0;
}

/* Slider */
static void sg_on_slider(GtkRange *r, gpointer d) {
    (void) d;
    if (!sg_quiet) sg_push(2, sg_id_of(r), (int) gtk_range_get_value(r), 0);
}
/* The user's moves land on a step from the minimum ("sg-step", 1 by default); a value set from
   code is kept as given (gtk_range_set_value emits no change-value). */
static gboolean sg_on_slider_move(GtkRange *r, GtkScrollType s, double v, gpointer d) {
    int step = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(r), "sg-step"));
    GtkAdjustment *a = gtk_range_get_adjustment(r);
    double lo = gtk_adjustment_get_lower(a), hi = gtk_adjustment_get_upper(a);
    long k;
    (void) s; (void) d;
    if (step < 1) step = 1;
    k = lround((v - lo) / step);
    if (k < 0) k = 0;
    if (k > (long) ((hi - lo) / step)) k = (long) ((hi - lo) / step);
    gtk_range_set_value(r, lo + (double) k * step);
    return TRUE;
}
static int sg_slider(int lo, int hi) {
    GtkWidget *s = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, lo, hi, 1);
    int id = sg_reg(s, 22);
    gtk_scale_set_digits(GTK_SCALE(s), 0);
    gtk_scale_set_draw_value(GTK_SCALE(s), TRUE);
    gtk_range_set_round_digits(GTK_RANGE(s), 0);
    gtk_widget_set_hexpand(s, TRUE);
    sg_quiet++; gtk_range_set_value(GTK_RANGE(s), lo); sg_quiet--;
    g_signal_connect(s, "value-changed", G_CALLBACK(sg_on_slider), NULL);
    g_signal_connect(s, "change-value", G_CALLBACK(sg_on_slider_move), NULL);
    return id;
}
static void sg_slider_set_value(int id, int v) { sg_quiet++; gtk_range_set_value(GTK_RANGE(sg_w[id]), v); sg_quiet--; }
static int sg_slider_value(int id) { return (int) lround(gtk_range_get_value(GTK_RANGE(sg_w[id]))); }
static void sg_slider_set_step(int id, int step) {
    g_object_set_data(G_OBJECT(sg_w[id]), "sg-step", GINT_TO_POINTER(step));
    gtk_range_set_increments(GTK_RANGE(sg_w[id]), step, step * 10.0);
}

/* Switch */
static void sg_on_switch(GObject *o, GParamSpec *p, gpointer d) {
    (void) p; (void) d;
    if (!sg_quiet) sg_push(12, sg_id_of(o), gtk_switch_get_active(GTK_SWITCH(o)) ? 1 : 0, 0);
}
static int sg_switch(void) {
    GtkWidget *s = gtk_switch_new();
    int id = sg_reg(s, 23);
    gtk_widget_set_halign(s, GTK_ALIGN_START);
    gtk_widget_set_valign(s, GTK_ALIGN_CENTER);
    g_signal_connect(s, "notify::active", G_CALLBACK(sg_on_switch), NULL);
    return id;
}
static void sg_switch_set(int id, int on) { sg_quiet++; gtk_switch_set_active(GTK_SWITCH(sg_w[id]), on ? TRUE : FALSE); sg_quiet--; }
static int sg_switch_is_on(int id) { return gtk_switch_get_active(GTK_SWITCH(sg_w[id])) ? 1 : 0; }

/* Date picker: a menu button showing the date (ISO, 2026-12-25) whose popover holds a
   GtkCalendar; the value lives on the button as y*10000 + m*100 + d ("sg-date"). */
static void sg_date_show(int id) {
    int v = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-date"));
    char text[16];
    snprintf(text, sizeof text, "%04d-%02d-%02d", v / 10000, (v / 100) % 100, v % 100);
    gtk_menu_button_set_label(GTK_MENU_BUTTON(sg_w[id]), text);
}
static void sg_date_store(int id, int y, int m, int d) {
    GtkCalendar *cal = g_object_get_data(G_OBJECT(sg_w[id]), "sg-calendar");
    GDateTime *dt = g_date_time_new_local(y, m, d, 0, 0, 0);
    g_object_set_data(G_OBJECT(sg_w[id]), "sg-date", GINT_TO_POINTER(y * 10000 + m * 100 + d));
    sg_date_show(id);
    if (dt) { sg_quiet++; gtk_calendar_select_day(cal, dt); sg_quiet--; g_date_time_unref(dt); }
}
static void sg_on_day(GtkCalendar *cal, gpointer d) {
    int id = GPOINTER_TO_INT(d), v;
    GDateTime *dt;
    if (sg_quiet) return;
    dt = gtk_calendar_get_date(cal);
    v = g_date_time_get_year(dt) * 10000 + g_date_time_get_month(dt) * 100 + g_date_time_get_day_of_month(dt);
    g_date_time_unref(dt);
    if (v == GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-date"))) return;
    g_object_set_data(G_OBJECT(sg_w[id]), "sg-date", GINT_TO_POINTER(v));
    sg_date_show(id);
    gtk_menu_button_popdown(GTK_MENU_BUTTON(sg_w[id]));
    sg_push(2, id, v, 0);
}
static int sg_date_picker(int y, int m, int d) {
    /* a date that drops down a calendar: read as a combo box, as on Windows */
    GtkWidget *b = g_object_new(GTK_TYPE_MENU_BUTTON, "accessible-role", GTK_ACCESSIBLE_ROLE_COMBO_BOX, NULL);
    GtkWidget *pop = gtk_popover_new(), *cal = gtk_calendar_new();
    int id = sg_reg(b, 24);
    gtk_popover_set_child(GTK_POPOVER(pop), cal);
    gtk_menu_button_set_popover(GTK_MENU_BUTTON(b), pop);
    gtk_widget_set_halign(b, GTK_ALIGN_START);
    g_object_set_data(G_OBJECT(b), "sg-calendar", cal);
    g_signal_connect(cal, "day-selected", G_CALLBACK(sg_on_day), GINT_TO_POINTER(id));
    sg_date_store(id, y, m, d);
    return id;
}
static void sg_dt_put(int id, int date, int time);   /* 1p, below */
static void sg_date_set(int id, int y, int m, int d) {
    /* 1p's date and time picker (53) and month picker (54) are set as date pickers too: their
       own parts take the date, and the time stays */
    if (sg_kind[id] == 53 || sg_kind[id] == 54) { sg_dt_put(id, y * 10000 + m * 100 + d, GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-time"))); return; }
    sg_date_store(id, y, m, d);
}
static int sg_date_value(int id) { return GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-date")); }

/* Time picker: hour and minute spin buttons (wrapping, two digits) side by side. */
static gboolean sg_two_digits(GtkSpinButton *s, gpointer d) {
    char text[8];
    (void) d;
    snprintf(text, sizeof text, "%02d", gtk_spin_button_get_value_as_int(s));
    gtk_editable_set_text(GTK_EDITABLE(s), text);
    return TRUE;
}
static int sg_time_value(int id) {
    GtkWidget *h = gtk_widget_get_first_child(sg_w[id]);
    GtkWidget *m = gtk_widget_get_last_child(sg_w[id]);
    return gtk_spin_button_get_value_as_int(GTK_SPIN_BUTTON(h)) * 60 + gtk_spin_button_get_value_as_int(GTK_SPIN_BUTTON(m));
}
static void sg_on_time(GtkSpinButton *s, gpointer d) {
    int id = GPOINTER_TO_INT(d);
    (void) s;
    if (!sg_quiet) sg_push(2, id, sg_time_value(id), 0);
}
static GtkWidget *sg_time_part(int top, int id, const char *name) {
    GtkWidget *s = gtk_spin_button_new_with_range(0, top, 1);
    gtk_spin_button_set_wrap(GTK_SPIN_BUTTON(s), TRUE);
    gtk_spin_button_set_numeric(GTK_SPIN_BUTTON(s), TRUE);
    gtk_editable_set_width_chars(GTK_EDITABLE(s), 2);
    g_signal_connect(s, "output", G_CALLBACK(sg_two_digits), NULL);
    g_signal_connect(s, "value-changed", G_CALLBACK(sg_on_time), GINT_TO_POINTER(id));
    gtk_accessible_update_property(GTK_ACCESSIBLE(s), GTK_ACCESSIBLE_PROPERTY_LABEL, name, -1);
    return s;
}
static int sg_time_picker(int h, int m) {
    GtkWidget *box = g_object_new(GTK_TYPE_BOX, "orientation", GTK_ORIENTATION_HORIZONTAL, "spacing", 2,
                                  "accessible-role", GTK_ACCESSIBLE_ROLE_GROUP, NULL);
    int id = sg_reg(box, 25);
    GtkWidget *hs = sg_time_part(23, id, "Hour"), *ms = sg_time_part(59, id, "Minute");
    gtk_box_append(GTK_BOX(box), hs);
    gtk_box_append(GTK_BOX(box), gtk_label_new(":"));
    gtk_box_append(GTK_BOX(box), ms);
    gtk_widget_set_halign(box, GTK_ALIGN_START);
    sg_quiet++;
    gtk_spin_button_set_value(GTK_SPIN_BUTTON(hs), h);
    gtk_spin_button_set_value(GTK_SPIN_BUTTON(ms), m);
    sg_quiet--;
    return id;
}
static void sg_time_set(int id, int h, int m) {
    sg_quiet++;
    gtk_spin_button_set_value(GTK_SPIN_BUTTON(gtk_widget_get_first_child(sg_w[id])), h);
    gtk_spin_button_set_value(GTK_SPIN_BUTTON(gtk_widget_get_last_child(sg_w[id])), m);
    sg_quiet--;
}

/* Color chooser: GtkColorDialogButton; the value is 0xRRGGBB. */
static int sg_rgb_of(const GdkRGBA *c) {
    return ((int) (c->red * 255 + 0.5) << 16) | ((int) (c->green * 255 + 0.5) << 8) | (int) (c->blue * 255 + 0.5);
}
static void sg_on_color(GObject *o, GParamSpec *p, gpointer d) {
    (void) p; (void) d;
    if (!sg_quiet) sg_push(2, sg_id_of(o), sg_rgb_of(gtk_color_dialog_button_get_rgba(GTK_COLOR_DIALOG_BUTTON(o))), 0);
}
static void sg_color_put(int id, int rgb) {
    GdkRGBA c = { ((rgb >> 16) & 255) / 255.0f, ((rgb >> 8) & 255) / 255.0f, (rgb & 255) / 255.0f, 1.0f };
    gtk_color_dialog_button_set_rgba(GTK_COLOR_DIALOG_BUTTON(sg_w[id]), &c);
}
static int sg_color_chooser(int rgb) {
    GtkWidget *b = gtk_color_dialog_button_new(gtk_color_dialog_new());   /* takes the dialog */
    int id = sg_reg(b, 26);
    gtk_widget_set_halign(b, GTK_ALIGN_START);
    sg_quiet++; sg_color_put(id, rgb); sg_quiet--;
    g_signal_connect(b, "notify::rgba", G_CALLBACK(sg_on_color), NULL);
    return id;
}
static void sg_color_set(int id, int rgb) { sg_quiet++; sg_color_put(id, rgb); sg_quiet--; }
static int sg_color_value(int id) { return sg_rgb_of(gtk_color_dialog_button_get_rgba(GTK_COLOR_DIALOG_BUTTON(sg_w[id]))); }

/* Scroll area, group box, expander: one child each (sg_single_set_content). */
static int sg_scroll_area(void) {
    GtkWidget *s = gtk_scrolled_window_new();
    gtk_widget_set_vexpand(s, TRUE); gtk_widget_set_hexpand(s, TRUE);
    return sg_reg(s, 27);
}
/* A group box reads as a group named by its title (a GtkFrame's title is a child label, so
   the frame itself would have no name). */
/* A group box or expander is named by its title, unless the program named it itself
   (sg_set_a11y_label marks that with "sg-a11y-own"): then a new title leaves the name be. */
static void sg_group_box_name(GtkWidget *f, const char *title) {
    if (g_object_get_data(G_OBJECT(f), "sg-a11y-own")) return;
    g_object_set_data_full(G_OBJECT(f), "sg-a11y", g_strdup(title), g_free);
    gtk_accessible_update_property(GTK_ACCESSIBLE(f), GTK_ACCESSIBLE_PROPERTY_LABEL, title, -1);
}
static int sg_group_box(const char *title) {
    GtkWidget *f = g_object_new(GTK_TYPE_FRAME, "label", title, "accessible-role", GTK_ACCESSIBLE_ROLE_GROUP, NULL);
    sg_group_box_name(f, title);
    return sg_reg(f, 30);
}
static void sg_on_expander(GObject *o, GParamSpec *p, gpointer d) {
    (void) p; (void) d;
    if (!sg_quiet) sg_push(12, sg_id_of(o), gtk_expander_get_expanded(GTK_EXPANDER(o)) ? 1 : 0, 0);
}
static int sg_expander(const char *title) {
    GtkWidget *e = gtk_expander_new(title);
    int id = sg_reg(e, 31);
    sg_group_box_name(e, title);   /* read as a button named by its title, as on macOS */
    g_signal_connect(e, "notify::expanded", G_CALLBACK(sg_on_expander), NULL);
    return id;
}
static void sg_expander_set_expanded(int id, int on) { sg_quiet++; gtk_expander_set_expanded(GTK_EXPANDER(sg_w[id]), on ? TRUE : FALSE); sg_quiet--; }
static int sg_expander_is_expanded(int id) { return gtk_expander_get_expanded(GTK_EXPANDER(sg_w[id])) ? 1 : 0; }
static void sg_single_set_content(int id, int child) {
    switch (sg_kind[id]) {
    case 27: gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(sg_w[id]), sg_w[child]); break;
    case 30: gtk_frame_set_child(GTK_FRAME(sg_w[id]), sg_w[child]); break;
    case 31: gtk_expander_set_child(GTK_EXPANDER(sg_w[id]), sg_w[child]); break;
    default: break;
    }
}

/* Image: a GtkPicture scaled down to fit, never enlarged. The loaders answer 0 when the
   file or bytes are not a picture. */
static int sg_image(void) {
    GtkWidget *p = gtk_picture_new();
    gtk_picture_set_can_shrink(GTK_PICTURE(p), TRUE);
    gtk_picture_set_content_fit(GTK_PICTURE(p), GTK_CONTENT_FIT_SCALE_DOWN);
    return sg_reg(p, 28);
}
static int sg_image_set_file(int id, const char *path) {
    GdkTexture *t = gdk_texture_new_from_filename(path, NULL);
    if (!t) return 0;
    gtk_picture_set_paintable(GTK_PICTURE(sg_w[id]), GDK_PAINTABLE(t));
    g_object_unref(t);
    return 1;
}
static int sg_image_set_bytes(int id, const unsigned char *data, int count) {
    GBytes *b = g_bytes_new(data, (gsize) count);
    GdkTexture *t = gdk_texture_new_from_bytes(b, NULL);
    g_bytes_unref(b);
    if (!t) return 0;
    gtk_picture_set_paintable(GTK_PICTURE(sg_w[id]), GDK_PAINTABLE(t));
    g_object_unref(t);
    return 1;
}

/* Separator */
static int sg_separator(int vertical) {
    return sg_reg(gtk_separator_new(vertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL), 29);
}

/* Editable combo: an entry (read as a combo box) whose arrow opens a popover of the options.
   A commit - Return, leaving the box, or picking an option - sends 2 when it changed the text
   from the last commit (or `set_text'), and nothing when it did not. */
static void sg_combo_commit(int id) {
    const char *now = gtk_editable_get_text(GTK_EDITABLE(sg_w[id]));
    const char *was = g_object_get_data(G_OBJECT(sg_w[id]), "sg-committed");
    int differs = g_strcmp0(was ? was : "", now) != 0;
    if (differs) {
        g_object_set_data_full(G_OBJECT(sg_w[id]), "sg-committed", g_strdup(now), g_free);
        if (!sg_quiet) sg_push(2, id, 0, 0);
    }
}
static void sg_on_combo_activate(GtkEntry *e, gpointer d) { (void) e; sg_combo_commit(GPOINTER_TO_INT(d)); }
static void sg_on_combo_leave(GtkEventControllerFocus *f, gpointer d) { (void) f; sg_combo_commit(GPOINTER_TO_INT(d)); }
static void sg_on_combo_pick(GtkListBox *l, GtkListBoxRow *r, gpointer d) {
    int id = GPOINTER_TO_INT(d);
    (void) l;
    sg_quiet++;
    gtk_editable_set_text(GTK_EDITABLE(sg_w[id]), gtk_label_get_text(GTK_LABEL(gtk_list_box_row_get_child(r))));
    sg_quiet--;
    gtk_popover_popdown(GTK_POPOVER(g_object_get_data(G_OBJECT(sg_w[id]), "sg-popover")));
    sg_combo_commit(id);
}
static void sg_on_combo_arrow(GtkEntry *e, GtkEntryIconPosition pos, gpointer d) {
    (void) e; (void) pos;
    gtk_popover_popup(GTK_POPOVER(g_object_get_data(G_OBJECT(sg_w[GPOINTER_TO_INT(d)]), "sg-popover")));
}
static int sg_combo_box(void) {
    GtkWidget *e = g_object_new(GTK_TYPE_ENTRY, "accessible-role", GTK_ACCESSIBLE_ROLE_COMBO_BOX, NULL);
    GtkWidget *pop = gtk_popover_new(), *list = gtk_list_box_new();
    GtkEventController *focus = gtk_event_controller_focus_new();
    int id = sg_reg(e, 32);
    gtk_entry_set_icon_from_icon_name(GTK_ENTRY(e), GTK_ENTRY_ICON_SECONDARY, "pan-down-symbolic");
    gtk_editable_set_width_chars(GTK_EDITABLE(e), 12);   /* room for a word in a row of controls */
    gtk_popover_set_child(GTK_POPOVER(pop), list);
    gtk_widget_set_parent(pop, e);
    gtk_popover_set_has_arrow(GTK_POPOVER(pop), FALSE);
    gtk_list_box_set_activate_on_single_click(GTK_LIST_BOX(list), TRUE);
    g_object_set_data(G_OBJECT(e), "sg-popover", pop);
    g_object_set_data(G_OBJECT(e), "sg-options", list);
    g_object_set_data_full(G_OBJECT(e), "sg-committed", g_strdup(""), g_free);
    g_signal_connect(e, "activate", G_CALLBACK(sg_on_combo_activate), GINT_TO_POINTER(id));
    g_signal_connect(e, "icon-press", G_CALLBACK(sg_on_combo_arrow), GINT_TO_POINTER(id));
    g_signal_connect(list, "row-activated", G_CALLBACK(sg_on_combo_pick), GINT_TO_POINTER(id));
    g_signal_connect(focus, "leave", G_CALLBACK(sg_on_combo_leave), GINT_TO_POINTER(id));
    gtk_widget_add_controller(e, focus);
    return id;
}
static void sg_combo_extend(int id, const char *t) {
    GtkWidget *row = gtk_label_new(t);
    gtk_label_set_xalign(GTK_LABEL(row), 0.0);
    gtk_widget_set_margin_start(row, 6); gtk_widget_set_margin_end(row, 6);
    gtk_list_box_append(GTK_LIST_BOX(g_object_get_data(G_OBJECT(sg_w[id]), "sg-options")), row);
}
static void sg_combo_set_text(int id, const char *t) {
    sg_quiet++;
    gtk_editable_set_text(GTK_EDITABLE(sg_w[id]), t);
    sg_quiet--;
    g_object_set_data_full(G_OBJECT(sg_w[id]), "sg-committed", g_strdup(t), g_free);
}
static const char *sg_combo_text(int id) { return gtk_editable_get_text(GTK_EDITABLE(sg_w[id])); }
/* As a user: type the text and press Return (2). */
static void sg_test_type_combo(int id, const char *t) {
    gtk_editable_set_text(GTK_EDITABLE(sg_w[id]), t);
    sg_combo_commit(id);
}
/* As a user: open the options and pick option `i' (2). */
static void sg_test_pick_combo(int id, int i) {
    GtkListBox *l = GTK_LIST_BOX(g_object_get_data(G_OBJECT(sg_w[id]), "sg-options"));
    GtkListBoxRow *r = gtk_list_box_get_row_at_index(l, i - 1);
    if (r) sg_on_combo_pick(l, r, GINT_TO_POINTER(id));
}

/* Tree table: the tree's model (nodes, expanders, selection; the same sg_tree_ calls work on
   it) shown by a GtkColumnView, so it reads as a tree-grid with column headers like the
   table. Each node keeps its cells ("sg-cells", column 1 first) and, while bound, the label
   showing each one ("sg-label-<column>"), so a changed cell shows at once. */
static void sg_tt_cell_setup(GtkSignalListItemFactory *fa, GtkListItem *it, gpointer d) {
    GtkWidget *l = gtk_label_new(NULL);
    (void) fa; (void) d;
    gtk_label_set_xalign(GTK_LABEL(l), 0.0);
    gtk_list_item_set_child(it, l);
}
static const char *sg_tt_cell(GObject *o, int col) {
    GPtrArray *cells = g_object_get_data(o, "sg-cells");
    const char *s = (cells && (guint) col <= cells->len) ? g_ptr_array_index(cells, col - 1) : NULL;
    if (s && *s) return s;
    return col == 1 ? gtk_string_object_get_string(GTK_STRING_OBJECT(o)) : "";
}
static void sg_tt_label_key(char *key, size_t n, int col) { snprintf(key, n, "sg-label-%d", col); }
static void sg_tt_cell_bind(GtkSignalListItemFactory *fa, GtkListItem *it, gpointer d) {
    GtkTreeListRow *r = GTK_TREE_LIST_ROW(gtk_list_item_get_item(it));
    GObject *o = gtk_tree_list_row_get_item(r);
    int col = GPOINTER_TO_INT(d);
    char key[24];
    (void) fa;
    gtk_label_set_text(GTK_LABEL(gtk_list_item_get_child(it)), sg_tt_cell(o, col));
    sg_follow_view_direction(gtk_list_item_get_child(it));
    sg_tt_label_key(key, sizeof key, col);
    g_object_set_data(o, key, gtk_list_item_get_child(it));
    g_object_unref(o);
}
static void sg_tt_cell_unbind(GtkSignalListItemFactory *fa, GtkListItem *it, gpointer d) {
    GtkTreeListRow *r = GTK_TREE_LIST_ROW(gtk_list_item_get_item(it));
    GObject *o = r ? gtk_tree_list_row_get_item(r) : NULL;
    char key[24];
    (void) fa;
    if (!o) return;
    sg_tt_label_key(key, sizeof key, GPOINTER_TO_INT(d));
    if (g_object_get_data(o, key) == gtk_list_item_get_child(it)) g_object_set_data(o, key, NULL);
    g_object_unref(o);
}
static void sg_tt_first_bind(GtkSignalListItemFactory *fa, GtkListItem *it, gpointer d) {
    GtkTreeListRow *r = GTK_TREE_LIST_ROW(gtk_list_item_get_item(it));
    GtkWidget *x = gtk_list_item_get_child(it);
    GObject *o = gtk_tree_list_row_get_item(r);
    sg_tree_bind(fa, it, d);   /* the expander, its row's "expanded" watch, column 1's text */
    gtk_label_set_text(GTK_LABEL(gtk_tree_expander_get_child(GTK_TREE_EXPANDER(x))), sg_tt_cell(o, 1));
    g_object_set_data(o, "sg-label-1", gtk_tree_expander_get_child(GTK_TREE_EXPANDER(x)));
    g_object_unref(o);
}
static void sg_tt_first_unbind(GtkSignalListItemFactory *fa, GtkListItem *it, gpointer d) {
    GtkTreeListRow *r = GTK_TREE_LIST_ROW(gtk_list_item_get_item(it));
    GObject *o = r ? gtk_tree_list_row_get_item(r) : NULL;
    if (o) { g_object_set_data(o, "sg-label-1", NULL); g_object_unref(o); }
    sg_tree_unbind(fa, it, d);
}
static int sg_tree_table(const char *titles) {
    GListStore *roots = g_list_store_new(GTK_TYPE_STRING_OBJECT);
    GtkTreeListModel *m = gtk_tree_list_model_new(G_LIST_MODEL(roots), FALSE, FALSE, sg_tree_children, NULL, NULL);
    GtkSingleSelection *s = gtk_single_selection_new(G_LIST_MODEL(m));
    GtkWidget *v, *scroll = gtk_scrolled_window_new();
    GPtrArray *nodes = g_ptr_array_new();
    gchar **t = g_strsplit(titles, "\x1f", -1);
    int id, i;
    gtk_single_selection_set_autoselect(s, FALSE);
    gtk_single_selection_set_can_unselect(s, TRUE);
    v = gtk_column_view_new(GTK_SELECTION_MODEL(s));
    gtk_column_view_set_show_column_separators(GTK_COLUMN_VIEW(v), TRUE);
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scroll), v);
    gtk_widget_set_vexpand(scroll, TRUE);
    sg_natural_rows(scroll);
    id = sg_reg(scroll, 33);
    for (i = 0; t[i]; i++) {
        GtkListItemFactory *f = gtk_signal_list_item_factory_new();
        GtkColumnViewColumn *c;
        if (i == 0) {
            g_signal_connect(f, "setup", G_CALLBACK(sg_tree_setup), NULL);
            g_signal_connect(f, "bind", G_CALLBACK(sg_tt_first_bind), GINT_TO_POINTER(id));
            g_signal_connect(f, "unbind", G_CALLBACK(sg_tt_first_unbind), NULL);
        } else {
            g_signal_connect(f, "setup", G_CALLBACK(sg_tt_cell_setup), NULL);
            g_signal_connect(f, "bind", G_CALLBACK(sg_tt_cell_bind), GINT_TO_POINTER(i + 1));
            g_signal_connect(f, "unbind", G_CALLBACK(sg_tt_cell_unbind), GINT_TO_POINTER(i + 1));
        }
        c = gtk_column_view_column_new(t[i], f);   /* takes the factory */
        gtk_column_view_column_set_resizable(c, TRUE);
        if (i == 0) gtk_column_view_column_set_expand(c, TRUE);
        gtk_column_view_append_column(GTK_COLUMN_VIEW(v), c);
        g_object_unref(c);
    }
    g_strfreev(t);
    g_signal_connect(s, "selection-changed", G_CALLBACK(sg_on_tree_selection), GINT_TO_POINTER(id));
    g_object_set_data(G_OBJECT(scroll), "sg-view", v);
    g_object_set_data_full(G_OBJECT(scroll), "sg-roots", g_object_ref(roots), g_object_unref);
    g_object_set_data(G_OBJECT(scroll), "sg-tree-model", m);
    g_object_set_data(G_OBJECT(scroll), "sg-tree-selection", s);
    g_object_set_data_full(G_OBJECT(scroll), "sg-tree-nodes", nodes, (GDestroyNotify) g_ptr_array_unref);
    return id;
}
/* Add node `node' under `parent' (0: a root) with column 1's text; set other cells after. */
static void sg_tree_table_add(int id, int node, int parent, const char *text) {
    GPtrArray *nodes = g_object_get_data(G_OBJECT(sg_w[id]), "sg-tree-nodes");
    GPtrArray *cells = g_ptr_array_new_with_free_func(g_free);
    sg_tree_add(id, node, parent, text);
    g_ptr_array_add(cells, g_strdup(text));
    g_object_set_data_full(G_OBJECT(g_ptr_array_index(nodes, node - 1)), "sg-cells", cells, (GDestroyNotify) g_ptr_array_unref);
}
static void sg_tree_table_set_cell(int id, int node, int col, const char *text) {
    GPtrArray *nodes = g_object_get_data(G_OBJECT(sg_w[id]), "sg-tree-nodes");
    GObject *o;
    GPtrArray *cells;
    GtkWidget *shown;
    char key[24];
    if (node < 1 || (guint) node > nodes->len || col < 1) return;
    o = G_OBJECT(g_ptr_array_index(nodes, node - 1));
    cells = g_object_get_data(o, "sg-cells");
    if (!cells) {
        cells = g_ptr_array_new_with_free_func(g_free);
        g_object_set_data_full(o, "sg-cells", cells, (GDestroyNotify) g_ptr_array_unref);
    }
    while (cells->len < (guint) col) g_ptr_array_add(cells, g_strdup(""));
    g_free(g_ptr_array_index(cells, col - 1));
    g_ptr_array_index(cells, col - 1) = g_strdup(text);
    sg_tt_label_key(key, sizeof key, col);
    shown = g_object_get_data(o, key);
    if (shown) gtk_label_set_text(GTK_LABEL(shown), text);
}
static const char *sg_tree_table_cell(int id, int node, int col) {
    GPtrArray *nodes = g_object_get_data(G_OBJECT(sg_w[id]), "sg-tree-nodes");
    if (node < 1 || (guint) node > nodes->len) return "";
    return sg_tt_cell(G_OBJECT(g_ptr_array_index(nodes, node - 1)), col);
}

/* Tooltips */
static void sg_set_tooltip(int id, const char *t) { gtk_widget_set_tooltip_text(sg_w[id], (t && *t) ? t : NULL); }
static const char *sg_tooltip(int id) { const char *t = gtk_widget_get_tooltip_text(sg_w[id]); return t ? t : ""; }

/* As a user: set a value control (2 or 12 follow from the control's own signal). */
static void sg_test_set_value(int id, int v) {
    switch (sg_kind[id]) {
    case 16: gtk_spin_button_set_value(GTK_SPIN_BUTTON(sg_w[id]), v); break;
    case 22: gtk_range_set_value(GTK_RANGE(sg_w[id]), v); break;
    /* A date, a time or a color is one user change: set quietly, then report once. (A time
       is two spin buttons; setting both would report twice.) */
    case 24: if (sg_date_value(id) != v) { sg_date_set(id, v / 10000, (v / 100) % 100, v % 100); sg_push(2, id, v, 0); } break;
    case 25: if (sg_time_value(id) != v) { sg_time_set(id, v / 60, v % 60); sg_push(2, id, v, 0); } break;
    case 26: if (sg_color_value(id) != v) { sg_quiet++; sg_color_put(id, v); sg_quiet--; sg_push(2, id, v, 0); } break;
    case 40: if (sg_calendar_value(id) != v) { sg_calendar_set(id, v); sg_push(2, id, v, 0); } break;
    default: break;
    }
}

/* Dialogs: save with a suggested name, choose a folder, and ask yes / no / cancel. */
static void sg_folder_done(GObject *src, GAsyncResult *res, gpointer d) {
    GFile *f = gtk_file_dialog_select_folder_finish(GTK_FILE_DIALOG(src), res, NULL);
    (void) d;
    g_free(sg_dialog_path); sg_dialog_path = NULL;
    if (f) { sg_dialog_path = g_file_get_path(f); g_object_unref(f); }
    sg_dialog_done = 1;
}
static const char *sg_choose_folder(int win, const char *title) {
    GtkFileDialog *dlg = gtk_file_dialog_new();
    gtk_file_dialog_set_title(dlg, title);
    gtk_file_dialog_set_modal(dlg, TRUE);
    sg_dialog_done = 0;
    {
        GCancellable *c = sg_dialog_cancellable();
        gtk_file_dialog_select_folder(dlg, win > 0 ? GTK_WINDOW(sg_w[win]) : NULL, c, sg_folder_done, NULL);
        sg_wait_dialog();
        g_object_unref(c);
    }
    g_object_unref(dlg);
    return sg_dialog_path;
}
static const char *sg_save_file_named(int win, const char *title, const char *extensions, const char *name) {
    GtkFileDialog *dlg = gtk_file_dialog_new();
    gtk_file_dialog_set_title(dlg, title);
    if (name && *name) gtk_file_dialog_set_initial_name(dlg, name);
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
    {
        GCancellable *c = sg_dialog_cancellable();
        gtk_file_dialog_save(dlg, win > 0 ? GTK_WINDOW(sg_w[win]) : NULL, c, sg_save_done, NULL);
        sg_wait_dialog();
        g_object_unref(c);
    }
    g_object_unref(dlg);
    return sg_dialog_path;
}
/* 1 yes, 2 no, 0 cancel (Escape or closing the dialog). */
static int sg_ask(int win, const char *title, const char *text) {
    GtkAlertDialog *dlg = gtk_alert_dialog_new("%s", title);
    const char *buttons[] = {"Cancel", "No", "Yes", NULL};
    gtk_alert_dialog_set_detail(dlg, text);
    gtk_alert_dialog_set_buttons(dlg, buttons);
    gtk_alert_dialog_set_cancel_button(dlg, 0);
    gtk_alert_dialog_set_default_button(dlg, 2);
    sg_dialog_done = 0; sg_dialog_choice = -1;
    {
        GCancellable *c = sg_dialog_cancellable();
        gtk_alert_dialog_choose(dlg, win > 0 ? GTK_WINDOW(sg_w[win]) : NULL, c, sg_alert_done, NULL);
        sg_wait_dialog();
        g_object_unref(c);
    }
    g_object_unref(dlg);
    return sg_dialog_choice == 2 ? 1 : sg_dialog_choice == 1 ? 2 : 0;
}


/* ---------- 1h, the API's remaining calls ---------- */

static void sg_group_box_set_title(int id, const char *t) { gtk_frame_set_label(GTK_FRAME(sg_w[id]), t); sg_group_box_name(sg_w[id], t); }
static void sg_expander_set_title(int id, const char *t) { gtk_expander_set_label(GTK_EXPANDER(sg_w[id]), t); sg_group_box_name(sg_w[id], t); }
static void sg_combo_wipe_out(int id) {
    GtkListBox *l = GTK_LIST_BOX(g_object_get_data(G_OBJECT(sg_w[id]), "sg-options"));
    gtk_list_box_remove_all(l);
}
static void sg_scroll_area_scroll_to(int id, int x, int y) {
    GtkScrolledWindow *s = GTK_SCROLLED_WINDOW(sg_w[id]);
    gtk_adjustment_set_value(gtk_scrolled_window_get_hadjustment(s), x);
    gtk_adjustment_set_value(gtk_scrolled_window_get_vadjustment(s), y);
}
/* A date picker's value is y*10000 + m*100 + d; a time picker's h*60 + m. */
static void sg_date_or_time_set(int id, int v) {
    if (sg_kind[id] == 40) sg_calendar_set(id, v);
    else if (sg_kind[id] == 25) sg_time_set(id, v / 60, v % 60);
    else sg_date_set(id, v / 10000, (v / 100) % 100, v % 100);
}
static int sg_date_or_time_value(int id) { return sg_kind[id] == 40 ? sg_calendar_value(id) : sg_kind[id] == 25 ? sg_time_value(id) : sg_date_value(id); }

/* ---------- 1j: calendar (40), menu button (41) and split button (42), level bar (43),
   popover (44), search field (45), token field (46), path control (47), rating (48),
   rich text area (49); dialogs ask_text, confirm_with_check, choose_font, show_about.
   Setters are quiet; the sg_test_ hooks act as a user. ---------- */

/* Calendar: GtkCalendar read as a grid; its value y*10000 + m*100 + d (event 2). */
static int sg_calendar_value(int id) {
    GDateTime *dt = gtk_calendar_get_date(GTK_CALENDAR(sg_w[id]));
    int v = g_date_time_get_year(dt) * 10000 + g_date_time_get_month(dt) * 100 + g_date_time_get_day_of_month(dt);
    g_date_time_unref(dt);
    return v;
}
static void sg_on_calendar_day(GtkCalendar *c, gpointer d) {
    (void) d;
    if (!sg_quiet) sg_push(2, sg_id_of(c), sg_calendar_value(sg_id_of(c)), 0);
}
static int sg_calendar(void) {
    GtkWidget *c = g_object_new(GTK_TYPE_CALENDAR, "accessible-role", GTK_ACCESSIBLE_ROLE_GRID, NULL);
    int id = sg_reg(c, 40);
    gtk_widget_set_halign(c, GTK_ALIGN_START);
    g_signal_connect(c, "day-selected", G_CALLBACK(sg_on_calendar_day), NULL);
    return id;
}
static void sg_calendar_set(int id, int v) {
    GDateTime *dt = g_date_time_new_local(v / 10000, (v / 100) % 100, v % 100, 0, 0, 0);
    if (dt) { sg_quiet++; gtk_calendar_select_day(GTK_CALENDAR(sg_w[id]), dt); sg_quiet--; g_date_time_unref(dt); }
}

/* Menu button: a GtkMenuButton over a GMenu (the context menus' app.itemN actions). A split
   button is a linked pair: the main GtkButton (click, event 1, on the pair's id) and the
   arrow. Both read as buttons named by their text. */
static void sg_on_split_main(GtkButton *b, gpointer d) { (void) b; if (!sg_quiet) sg_push(1, GPOINTER_TO_INT(d), 0, 0); }
static void sg_name_widget(GtkWidget *w, const char *name) {
    g_object_set_data_full(G_OBJECT(w), "sg-a11y", g_strdup(name), g_free);
    gtk_accessible_update_property(GTK_ACCESSIBLE(w), GTK_ACCESSIBLE_PROPERTY_LABEL, name, -1);
}
static int sg_menu_button(const char *text, int split) {
    if (!split) {
        GtkWidget *m = g_object_new(GTK_TYPE_MENU_BUTTON, "label", text, "accessible-role", GTK_ACCESSIBLE_ROLE_BUTTON, NULL);
        int id = sg_reg(m, 41);
        sg_name_widget(m, text);
        gtk_widget_set_halign(m, GTK_ALIGN_START);
        return id;
    } else {
        GtkWidget *box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
        GtkWidget *main_part = gtk_button_new_with_label(text);
        GtkWidget *arrow = g_object_new(GTK_TYPE_MENU_BUTTON, "accessible-role", GTK_ACCESSIBLE_ROLE_BUTTON, NULL);
        int id = sg_reg(box, 42);
        gtk_widget_add_css_class(box, "linked");
        gtk_widget_set_halign(box, GTK_ALIGN_START);
        sg_name_widget(arrow, "More");
        gtk_box_append(GTK_BOX(box), main_part);
        gtk_box_append(GTK_BOX(box), arrow);
        g_object_set_data(G_OBJECT(box), "sg-main", main_part);
        g_object_set_data(G_OBJECT(box), "sg-arrow", arrow);
        g_signal_connect(main_part, "clicked", G_CALLBACK(sg_on_split_main), GINT_TO_POINTER(id));
        return id;
    }
}
static void sg_menu_button_set_menu(int id, void *menu) {
    GtkWidget *m = sg_kind[id] == 42 ? g_object_get_data(G_OBJECT(sg_w[id]), "sg-arrow") : sg_w[id];
    gtk_menu_button_set_menu_model(GTK_MENU_BUTTON(m), G_MENU_MODEL(menu));
}

/* Level bar: GtkLevelBar read as a meter. Offsets color it: up to the warning value the
   theme's normal fill, to the critical value amber, beyond it red. */
__attribute__((weak)) int sg_level_css_done = 0;
static void sg_level_css(void) {
    GtkCssProvider *p;
    if (sg_level_css_done) return;
    sg_level_css_done = 1;
    p = gtk_css_provider_new();
    gtk_css_provider_load_from_string(p,
        "levelbar block.sg-warning { background-color: #e5a50a; }\n"
        "levelbar block.sg-critical { background-color: #e01b24; }\n");
    gtk_style_context_add_provider_for_display(gdk_display_get_default(), GTK_STYLE_PROVIDER(p),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(p);
}
static void sg_level_offsets(int id) {
    GtkLevelBar *b = GTK_LEVEL_BAR(sg_w[id]);
    int hi = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(b), "sg-max"));
    int warn = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(b), "sg-warning"));
    int crit = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(b), "sg-critical"));
    gtk_level_bar_remove_offset_value(b, GTK_LEVEL_BAR_OFFSET_LOW);
    gtk_level_bar_remove_offset_value(b, GTK_LEVEL_BAR_OFFSET_HIGH);
    gtk_level_bar_remove_offset_value(b, GTK_LEVEL_BAR_OFFSET_FULL);
    gtk_level_bar_remove_offset_value(b, "sg-warning");
    gtk_level_bar_remove_offset_value(b, "sg-critical");
    /* the style is the first offset at or above the value: normal up to the first threshold
       set, amber past the warning value, red past the critical one (either may be unset) */
    gtk_level_bar_add_offset_value(b, GTK_LEVEL_BAR_OFFSET_HIGH, warn > 0 ? warn : crit > 0 ? crit : hi);
    if (warn > 0) gtk_level_bar_add_offset_value(b, "sg-warning", crit > warn ? crit : hi);
    if (crit > 0) gtk_level_bar_add_offset_value(b, "sg-critical", hi);
}
static int sg_level_bar(int lo, int hi) {
    GtkWidget *b = g_object_new(GTK_TYPE_LEVEL_BAR, "accessible-role", GTK_ACCESSIBLE_ROLE_METER, NULL);
    int id = sg_reg(b, 43);
    sg_level_css();
    gtk_level_bar_set_min_value(GTK_LEVEL_BAR(b), lo);
    gtk_level_bar_set_max_value(GTK_LEVEL_BAR(b), hi);
    gtk_level_bar_set_value(GTK_LEVEL_BAR(b), lo);
    gtk_widget_set_hexpand(b, TRUE);
    gtk_widget_set_valign(b, GTK_ALIGN_CENTER);
    g_object_set_data(G_OBJECT(b), "sg-max", GINT_TO_POINTER(hi));
    sg_level_offsets(id);
    return id;
}
static void sg_level_bar_set(int id, int v) { gtk_level_bar_set_value(GTK_LEVEL_BAR(sg_w[id]), v); }
static int sg_level_bar_value(int id) { return (int) (gtk_level_bar_get_value(GTK_LEVEL_BAR(sg_w[id])) + 0.5); }
static void sg_level_bar_set_warning(int id, int v) { g_object_set_data(G_OBJECT(sg_w[id]), "sg-warning", GINT_TO_POINTER(v)); sg_level_offsets(id); }
static void sg_level_bar_set_critical(int id, int v) { g_object_set_data(G_OBJECT(sg_w[id]), "sg-critical", GINT_TO_POINTER(v)); sg_level_offsets(id); }

/* Popover: a GtkPopover (read as a dialog) attached to its anchor when shown. The user's
   dismissal sends closed (17); hide is quiet. */
static void sg_on_popover_closed(GtkPopover *p, gpointer d) { (void) d; if (!sg_quiet) sg_push(17, sg_id_of(p), 0, 0); }
static int sg_popover(void) {
    GtkWidget *p = g_object_new(GTK_TYPE_POPOVER, "accessible-role", GTK_ACCESSIBLE_ROLE_DIALOG, NULL);
    int id = sg_reg(p, 44);
    g_object_ref_sink(p);   /* kept while it has no anchor */
    g_signal_connect(p, "closed", G_CALLBACK(sg_on_popover_closed), NULL);
    return id;
}
static void sg_popover_set_content(int id, int child) { gtk_popover_set_child(GTK_POPOVER(sg_w[id]), sg_w[child]); }
static void sg_popover_show_at(int id, int anchor) {
    GtkWidget *p = sg_w[id];
    if (gtk_widget_get_parent(p) != sg_w[anchor]) {
        if (gtk_widget_get_parent(p)) gtk_widget_unparent(p);
        gtk_widget_set_parent(p, sg_w[anchor]);
    }
    gtk_popover_popup(GTK_POPOVER(p));
}
static void sg_popover_hide(int id) { sg_quiet++; gtk_popover_popdown(GTK_POPOVER(sg_w[id])); sg_quiet--; }
static int sg_popover_is_shown(int id) { return gtk_widget_get_visible(sg_w[id]) ? 1 : 0; }
static void sg_test_dismiss_popover(int id) { gtk_popover_popdown(GTK_POPOVER(sg_w[id])); }   /* emits closed */

/* Search field: GtkSearchEntry; changed (2) on each edit as a field, activate (3) on Return. */
static int sg_search_field(void) {
    GtkWidget *e = gtk_search_entry_new();
    int id = sg_reg(e, 45);
    g_signal_connect(e, "changed", G_CALLBACK(sg_on_changed), NULL);
    g_signal_connect(e, "activate", G_CALLBACK(sg_on_activate), NULL);
    sg_field_hook_leave(e, id);
    return id;
}

/* Token field: chips (buttons named by their token) then an entry. A comma or Return makes a
   token; Backspace in the empty entry removes the last. The user's change sends 2. */
static GtkWidget *sg_token_entry(int id) { return g_object_get_data(G_OBJECT(sg_w[id]), "sg-entry"); }
static GPtrArray *sg_tokens(int id) { return g_object_get_data(G_OBJECT(sg_w[id]), "sg-tokens"); }
static void sg_token_rebuild(int id) {
    GtkWidget *box = sg_w[id], *c, *next, *entry = sg_token_entry(id);
    GPtrArray *tk = sg_tokens(id);
    guint i;
    for (c = gtk_widget_get_first_child(box); c; c = next) {
        next = gtk_widget_get_next_sibling(c);
        if (c != entry) gtk_box_remove(GTK_BOX(box), c);
    }
    for (i = 0; i < tk->len; i++) {
        GtkWidget *chip = gtk_button_new_with_label(g_ptr_array_index(tk, i));
        gtk_widget_add_css_class(chip, "pill");
        gtk_widget_set_focusable(chip, FALSE);
        gtk_box_insert_child_after(GTK_BOX(box), chip, gtk_widget_get_prev_sibling(entry));
    }
}
static int sg_token_add_text(int id, const char *text) {
    /* every comma-separated piece of `text', trimmed, as a token; answers how many */
    gchar **parts = g_strsplit(text, ",", -1);
    int i, n = 0;
    for (i = 0; parts[i]; i++) {
        gchar *t = g_strstrip(parts[i]);
        if (*t) { g_ptr_array_add(sg_tokens(id), g_strdup(t)); n++; }
    }
    g_strfreev(parts);
    if (n) sg_token_rebuild(id);
    return n;
}
static void sg_on_token_activate(GtkEntry *e, gpointer d) {
    int id = GPOINTER_TO_INT(d);
    const char *t = gtk_editable_get_text(GTK_EDITABLE(e));
    if (sg_token_add_text(id, t)) { sg_quiet++; gtk_editable_set_text(GTK_EDITABLE(e), ""); sg_quiet--; sg_push(2, id, 0, 0); }
}
static void sg_on_token_changed(GtkEditable *e, gpointer d) {
    int id = GPOINTER_TO_INT(d);
    const char *t = gtk_editable_get_text(e);
    if (sg_quiet || !strchr(t, ',')) return;
    {
        gchar *copy = g_strdup(t);
        int n = sg_token_add_text(id, copy);
        g_free(copy);
        sg_quiet++; gtk_editable_set_text(e, ""); sg_quiet--;
        if (n) sg_push(2, id, 0, 0);
    }
}
static gboolean sg_on_token_key(GtkEventControllerKey *k, guint key, guint code, GdkModifierType m, gpointer d) {
    int id = GPOINTER_TO_INT(d);
    GPtrArray *tk = sg_tokens(id);
    (void) k; (void) code; (void) m;
    if (key == GDK_KEY_BackSpace && *gtk_editable_get_text(GTK_EDITABLE(sg_token_entry(id))) == '\0' && tk->len > 0) {
        g_ptr_array_remove_index(tk, tk->len - 1);
        sg_token_rebuild(id);
        sg_push(2, id, 0, 0);
        return TRUE;
    }
    return FALSE;
}
static int sg_token_field(void) {
    GtkWidget *box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    GtkWidget *e = gtk_entry_new();
    GtkEventController *k = gtk_event_controller_key_new();
    int id = sg_reg(box, 46);
    gtk_widget_set_hexpand(e, TRUE);
    gtk_box_append(GTK_BOX(box), e);
    g_object_set_data(G_OBJECT(box), "sg-entry", e);
    g_object_set_data_full(G_OBJECT(box), "sg-tokens", g_ptr_array_new_with_free_func(g_free), (GDestroyNotify) g_ptr_array_unref);
    g_signal_connect(e, "activate", G_CALLBACK(sg_on_token_activate), GINT_TO_POINTER(id));
    g_signal_connect(e, "changed", G_CALLBACK(sg_on_token_changed), GINT_TO_POINTER(id));
    g_signal_connect(k, "key-pressed", G_CALLBACK(sg_on_token_key), GINT_TO_POINTER(id));
    gtk_widget_add_controller(e, k);
    return id;
}
static void sg_token_field_extend(int id, const char *t) { g_ptr_array_add(sg_tokens(id), g_strdup(t)); sg_token_rebuild(id); }
static void sg_token_field_remove(int id, int i) {
    if (i >= 1 && (guint) i <= sg_tokens(id)->len) { g_ptr_array_remove_index(sg_tokens(id), (guint) (i - 1)); sg_token_rebuild(id); }
}
static void sg_token_field_wipe_out(int id) { g_ptr_array_set_size(sg_tokens(id), 0); sg_token_rebuild(id); }
static int sg_token_field_count(int id) { return (int) sg_tokens(id)->len; }
static const char *sg_token_field_item(int id, int i) {
    return (i >= 1 && (guint) i <= sg_tokens(id)->len) ? g_ptr_array_index(sg_tokens(id), i - 1) : "";
}
/* As a user typing "a, b" then Return: one change (2). */
static void sg_test_type_tokens(int id, const char *text) {
    if (sg_token_add_text(id, text)) sg_push(2, id, 0, 0);
}

/* Path control: a navigation of flat link buttons, one per part ("/" first), separated by
   chevrons. A click sends selection (4, a = the part, 1 = the root). */
static GPtrArray *sg_path_parts(int id) { return g_object_get_data(G_OBJECT(sg_w[id]), "sg-parts"); }
static void sg_on_path_part(GtkButton *b, gpointer d) {
    (void) d;
    sg_push(4, sg_id_of(b), GPOINTER_TO_INT(g_object_get_data(G_OBJECT(b), "sg-index")), 0);
}
static int sg_path_control(void) {
    GtkWidget *box = g_object_new(GTK_TYPE_BOX, "orientation", GTK_ORIENTATION_HORIZONTAL, "spacing", 0,
                                  "accessible-role", GTK_ACCESSIBLE_ROLE_NAVIGATION, NULL);
    int id = sg_reg(box, 47);
    gtk_widget_set_halign(box, GTK_ALIGN_START);
    g_object_set_data_full(G_OBJECT(box), "sg-parts", g_ptr_array_new_with_free_func(g_free), (GDestroyNotify) g_ptr_array_unref);
    return id;
}
static void sg_path_control_set(int id, const char *path) {
    GtkWidget *box = sg_w[id], *c;
    GPtrArray *parts = sg_path_parts(id);
    gchar **pieces;
    guint i;
    int n = 0;
    while ((c = gtk_widget_get_first_child(box))) gtk_box_remove(GTK_BOX(box), c);
    g_ptr_array_set_size(parts, 0);
    if (path[0] == '/') g_ptr_array_add(parts, g_strdup("/"));
    pieces = g_strsplit_set(path, "/\\", -1);
    for (i = 0; pieces[i]; i++) if (*pieces[i]) g_ptr_array_add(parts, g_strdup(pieces[i]));
    g_strfreev(pieces);
    for (i = 0; i < parts->len; i++) {
        GtkWidget *b = g_object_new(GTK_TYPE_BUTTON, "label", (const char *) g_ptr_array_index(parts, i),
                                    "has-frame", FALSE, "accessible-role", GTK_ACCESSIBLE_ROLE_LINK, NULL);
        if (i > 0) gtk_box_append(GTK_BOX(box), gtk_label_new("\xe2\x80\xba"));   /* › */
        g_object_set_data(G_OBJECT(b), "sg-id", GINT_TO_POINTER(id));
        g_object_set_data(G_OBJECT(b), "sg-index", GINT_TO_POINTER(++n));
        g_signal_connect(b, "clicked", G_CALLBACK(sg_on_path_part), NULL);
        gtk_box_append(GTK_BOX(box), b);
    }
    g_object_set_data_full(G_OBJECT(box), "sg-path", g_strdup(path), g_free);
}
static int sg_path_control_count(int id) { return (int) sg_path_parts(id)->len; }
static const char *sg_path_control_part(int id, int i) {
    return (i >= 1 && (guint) i <= sg_path_parts(id)->len) ? g_ptr_array_index(sg_path_parts(id), i - 1) : "";
}

/* Rating: a row of star buttons read as a slider (value 0 .. maximum). Clicking star i rates
   i (2, a = i). */
static void sg_rating_show(int id) {
    GtkWidget *c;
    int v = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-value")), n = 1;
    int max = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-max"));
    for (c = gtk_widget_get_first_child(sg_w[id]); c; c = gtk_widget_get_next_sibling(c), n++)
        gtk_button_set_label(GTK_BUTTON(c), n <= v ? "\xe2\x98\x85" : "\xe2\x98\x86");   /* ★ ☆ */
    gtk_accessible_update_property(GTK_ACCESSIBLE(sg_w[id]), GTK_ACCESSIBLE_PROPERTY_VALUE_MIN, 0.0,
        GTK_ACCESSIBLE_PROPERTY_VALUE_MAX, (double) max, GTK_ACCESSIBLE_PROPERTY_VALUE_NOW, (double) v, -1);
}
static void sg_rating_put(int id, int v) { g_object_set_data(G_OBJECT(sg_w[id]), "sg-value", GINT_TO_POINTER(v)); sg_rating_show(id); }
static void sg_on_star(GtkButton *b, gpointer d) {
    int id = sg_id_of(b), i = GPOINTER_TO_INT(d);
    if (i != GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-value"))) { sg_rating_put(id, i); sg_push(2, id, i, 0); }
}
/* Rating stars: larger and gold, packed together, as on macOS and Windows. */
__attribute__((weak)) int sg_rating_css_done = 0;
static void sg_rating_css(void) {
    GtkCssProvider *p;
    if (sg_rating_css_done) return;
    sg_rating_css_done = 1;
    p = gtk_css_provider_new();
    gtk_css_provider_load_from_string(p,
        ".sg-rating button { font-size: 20px; color: #b07800; padding: 0 1px; min-width: 0; min-height: 0; }");
    gtk_style_context_add_provider_for_display(gdk_display_get_default(), GTK_STYLE_PROVIDER(p),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(p);
}
static int sg_rating(int max) {
    GtkWidget *box = g_object_new(GTK_TYPE_BOX, "orientation", GTK_ORIENTATION_HORIZONTAL, "spacing", 0,
                                  "accessible-role", GTK_ACCESSIBLE_ROLE_SLIDER, NULL);
    int id = sg_reg(box, 48), i;
    gtk_widget_set_halign(box, GTK_ALIGN_START);
    sg_rating_css();
    gtk_widget_add_css_class(box, "sg-rating");
    g_object_set_data(G_OBJECT(box), "sg-max", GINT_TO_POINTER(max));
    for (i = 1; i <= max; i++) {
        GtkWidget *b = g_object_new(GTK_TYPE_BUTTON, "has-frame", FALSE, "accessible-role", GTK_ACCESSIBLE_ROLE_PRESENTATION, NULL);
        g_object_set_data(G_OBJECT(b), "sg-id", GINT_TO_POINTER(id));
        g_signal_connect(b, "clicked", G_CALLBACK(sg_on_star), GINT_TO_POINTER(i));
        gtk_box_append(GTK_BOX(box), b);
    }
    sg_rating_put(id, 0);
    return id;
}
static void sg_rating_set(int id, int v) { sg_rating_put(id, v); }
static int sg_rating_value(int id) { return GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-value")); }
static void sg_test_rate(int id, int v) {
    if (v != sg_rating_value(id)) { sg_rating_put(id, v); sg_push(2, id, v, 0); }
}

/* Rich text area: the text area (its set and get work) with formatting tags. Positions are
   1-based characters, ranges inclusive; a GtkTextIter's offsets are characters already. */
static int sg_rich_text_area(void) {
    int id = sg_text_area();
    sg_kind[id] = 49;
    return id;
}
static GtkTextBuffer *sg_rich_buffer(int id) { return gtk_text_view_get_buffer(sg_view_of(id)); }
static GtkTextTag *sg_rich_tag(int id, const char *name) {
    GtkTextBuffer *b = sg_rich_buffer(id);
    GtkTextTag *t = gtk_text_tag_table_lookup(gtk_text_buffer_get_tag_table(b), name);
    if (t) return t;
    if (!strcmp(name, "sg-bold")) return gtk_text_buffer_create_tag(b, name, "weight", PANGO_WEIGHT_BOLD, NULL);
    if (!strcmp(name, "sg-italic")) return gtk_text_buffer_create_tag(b, name, "style", PANGO_STYLE_ITALIC, NULL);
    if (!strcmp(name, "sg-underline")) return gtk_text_buffer_create_tag(b, name, "underline", PANGO_UNDERLINE_SINGLE, NULL);
    if (g_str_has_prefix(name, "sg-fg-")) {
        char css[8]; GdkRGBA c;
        snprintf(css, sizeof css, "#%s", name + 6);
        gdk_rgba_parse(&c, css);
        return gtk_text_buffer_create_tag(b, name, "foreground-rgba", &c, NULL);
    }
    if (g_str_has_prefix(name, "sg-size-"))
        return gtk_text_buffer_create_tag(b, name, "size-points", g_ascii_strtod(name + 8, NULL) / 10.0, NULL);
    return NULL;
}
static void sg_rich_iters(int id, int s, int e, GtkTextIter *a, GtkTextIter *z) {
    gtk_text_buffer_get_iter_at_offset(sg_rich_buffer(id), a, s - 1);
    gtk_text_buffer_get_iter_at_offset(sg_rich_buffer(id), z, e);
}
/* Remove every tag of a family (color or size) from a range, before applying another. */
static void sg_rich_clear_family(int id, int s, int e, const char *prefix) {
    GtkTextIter a, z, i;
    GSList *tags, *l;
    sg_rich_iters(id, s, e, &a, &z);
    for (i = a; gtk_text_iter_compare(&i, &z) < 0; gtk_text_iter_forward_char(&i)) {
        tags = gtk_text_iter_get_tags(&i);
        for (l = tags; l; l = l->next) {
            char *name = NULL;
            g_object_get(l->data, "name", &name, NULL);
            if (name && g_str_has_prefix(name, prefix)) gtk_text_buffer_remove_tag(sg_rich_buffer(id), GTK_TEXT_TAG(l->data), &a, &z);
            g_free(name);
        }
        g_slist_free(tags);
    }
}
static void sg_rich_apply(int id, int s, int e, const char *name, int on) {
    GtkTextIter a, z;
    GtkTextTag *t = sg_rich_tag(id, name);
    sg_rich_iters(id, s, e, &a, &z);
    sg_quiet++;
    if (on) gtk_text_buffer_apply_tag(sg_rich_buffer(id), t, &a, &z);
    else gtk_text_buffer_remove_tag(sg_rich_buffer(id), t, &a, &z);
    sg_quiet--;
}
static const char *sg_trait_tag(int trait) { return trait == 1 ? "sg-bold" : trait == 2 ? "sg-italic" : "sg-underline"; }
static void sg_rich_text_set_trait(int id, int s, int e, int trait, int on) { sg_rich_apply(id, s, e, sg_trait_tag(trait), on); }
static void sg_rich_text_set_color(int id, int s, int e, int rgb) {
    char name[16];
    sg_rich_clear_family(id, s, e, "sg-fg-");
    snprintf(name, sizeof name, "sg-fg-%06X", rgb & 0xFFFFFF);
    sg_rich_apply(id, s, e, name, 1);
}
static void sg_rich_text_set_size(int id, int s, int e, double points) {
    char name[24];
    sg_rich_clear_family(id, s, e, "sg-size-");
    snprintf(name, sizeof name, "sg-size-%d", (int) (points * 10 + 0.5));
    sg_rich_apply(id, s, e, name, 1);
}
static int sg_rich_has(int id, int i, const char *name) {
    GtkTextIter it;
    GtkTextTag *t = gtk_text_tag_table_lookup(gtk_text_buffer_get_tag_table(sg_rich_buffer(id)), name);
    if (!t) return 0;
    gtk_text_buffer_get_iter_at_offset(sg_rich_buffer(id), &it, i - 1);
    return gtk_text_iter_has_tag(&it, t) ? 1 : 0;
}
static int sg_rich_text_trait_at(int id, int i, int trait) { return sg_rich_has(id, i, sg_trait_tag(trait)); }
/* The value of the family tag at position `i' (its name past `prefix'), or NULL. */
static char *sg_rich_family_at(int id, int i, const char *prefix) {
    GtkTextIter it;
    GSList *tags, *l;
    char *found = NULL;
    gtk_text_buffer_get_iter_at_offset(sg_rich_buffer(id), &it, i - 1);
    tags = gtk_text_iter_get_tags(&it);
    for (l = tags; l && !found; l = l->next) {
        char *name = NULL;
        g_object_get(l->data, "name", &name, NULL);
        if (name && g_str_has_prefix(name, prefix)) found = g_strdup(name + strlen(prefix));
        g_free(name);
    }
    g_slist_free(tags);
    return found;
}
static int sg_rich_text_color_at(int id, int i) {
    char *v = sg_rich_family_at(id, i, "sg-fg-");
    int rgb = v ? (int) strtol(v, NULL, 16) : -1;
    g_free(v);
    return rgb;
}
static double sg_rich_text_size_at(int id, int i) {
    char *v = sg_rich_family_at(id, i, "sg-size-");
    double pts;
    if (v) { pts = g_ascii_strtod(v, NULL) / 10.0; g_free(v); return pts; }
    {   /* the view's own size */
        PangoFontDescription *f = pango_context_get_font_description(gtk_widget_get_pango_context(GTK_WIDGET(sg_view_of(id))));
        return f ? pango_font_description_get_size(f) / (double) PANGO_SCALE : 0.0;
    }
}
static int sg_rich_text_selection_start(int id) {
    GtkTextIter a, z;
    if (gtk_text_buffer_get_selection_bounds(sg_rich_buffer(id), &a, &z)) return gtk_text_iter_get_offset(&a) + 1;
    gtk_text_buffer_get_iter_at_mark(sg_rich_buffer(id), &a, gtk_text_buffer_get_insert(sg_rich_buffer(id)));
    return gtk_text_iter_get_offset(&a) + 1;
}
static int sg_rich_text_selection_end(int id) {
    GtkTextIter a, z;
    if (gtk_text_buffer_get_selection_bounds(sg_rich_buffer(id), &a, &z)) return gtk_text_iter_get_offset(&z);
    return sg_rich_text_selection_start(id) - 1;
}
static void sg_rich_text_select(int id, int s, int e) {
    GtkTextIter a, z;
    sg_rich_iters(id, s, e, &a, &z);
    gtk_text_buffer_select_range(sg_rich_buffer(id), &a, &z);
}

/* ---------- 1j dialogs: built in a modal window, waited for; the test auto-cancel closes
   them as Cancel would. ---------- */

__attribute__((weak)) int sg_box_answer = 0;
__attribute__((weak)) int sg_box_timer_fired = 0;
static void sg_box_ok(GtkButton *b, gpointer w) { (void) b; sg_box_answer = 1; gtk_window_destroy(GTK_WINDOW(w)); }
static void sg_box_cancel(GtkButton *b, gpointer w) { (void) b; sg_box_answer = 0; gtk_window_destroy(GTK_WINDOW(w)); }
static void sg_box_gone(GtkWidget *w, gpointer d) { (void) w; (void) d; sg_dialog_done = 1; }
static gboolean sg_box_timeout(gpointer w) { sg_box_timer_fired = 1; sg_box_answer = 0; gtk_window_destroy(GTK_WINDOW(w)); return G_SOURCE_REMOVE; }
/* Start the test's auto-cancel for window `w' (0 when off). */
static guint sg_box_timer(GtkWidget *w) { sg_box_timer_fired = 0; return sg_auto_cancel_ms > 0 ? g_timeout_add((guint) sg_auto_cancel_ms, sg_box_timeout, w) : 0; }
/* After the wait: a timer that has not fired must not fire on the destroyed window. */
static void sg_box_timer_done(guint timer) { if (timer && !sg_box_timer_fired) g_source_remove(timer); }
/* A modal window holding `body' over Cancel and OK; waits until answered. 1 OK, 0 cancel. */
static int sg_run_box(int win, const char *title, GtkWidget *body, GtkWidget *ok_on_activate) {
    GtkWidget *w = gtk_window_new(), *outer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
    GtkWidget *row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    GtkWidget *cancel = gtk_button_new_with_label("Cancel"), *ok = gtk_button_new_with_label("OK");
    guint timer = 0;
    gtk_window_set_title(GTK_WINDOW(w), title);
    gtk_window_set_modal(GTK_WINDOW(w), TRUE);
    gtk_window_set_resizable(GTK_WINDOW(w), FALSE);
    if (win > 0 && sg_w[win]) gtk_window_set_transient_for(GTK_WINDOW(w), GTK_WINDOW(sg_w[win]));
    gtk_widget_set_margin_start(outer, 16); gtk_widget_set_margin_end(outer, 16);
    gtk_widget_set_margin_top(outer, 16); gtk_widget_set_margin_bottom(outer, 16);
    gtk_widget_add_css_class(ok, "suggested-action");
    gtk_widget_set_halign(row, GTK_ALIGN_END);
    gtk_box_append(GTK_BOX(row), cancel);
    gtk_box_append(GTK_BOX(row), ok);
    gtk_box_append(GTK_BOX(outer), body);
    gtk_box_append(GTK_BOX(outer), row);
    gtk_window_set_child(GTK_WINDOW(w), outer);
    gtk_window_set_default_widget(GTK_WINDOW(w), ok);
    g_signal_connect(ok, "clicked", G_CALLBACK(sg_box_ok), w);
    g_signal_connect(cancel, "clicked", G_CALLBACK(sg_box_cancel), w);
    g_signal_connect(w, "destroy", G_CALLBACK(sg_box_gone), NULL);
    if (ok_on_activate) g_signal_connect_swapped(ok_on_activate, "activate", G_CALLBACK(gtk_widget_activate), ok);
    sg_box_answer = 0; sg_dialog_done = 0;
    timer = sg_box_timer(w);
    gtk_window_present(GTK_WINDOW(w));
    sg_wait_dialog();
    sg_box_timer_done(timer);
    return sg_box_answer;
}
static const char *sg_ask_text(int win, const char *title, const char *prompt, const char *initial) {
    GtkWidget *body = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6), *label = gtk_label_new(prompt), *e = gtk_entry_new();
    static char *answer = NULL;
    gtk_label_set_xalign(GTK_LABEL(label), 0.0);
    gtk_editable_set_text(GTK_EDITABLE(e), initial);
    gtk_box_append(GTK_BOX(body), label);
    gtk_box_append(GTK_BOX(body), e);
    g_object_ref(e);
    g_free(answer); answer = NULL;
    if (sg_run_box(win, title, body, e)) answer = g_strdup(gtk_editable_get_text(GTK_EDITABLE(e)));
    g_object_unref(e);
    return answer;
}
/* Bit 0: OK; bit 1: the box was checked. */
static int sg_confirm_with_check(int win, const char *title, const char *text, const char *check) {
    GtkWidget *body = gtk_box_new(GTK_ORIENTATION_VERTICAL, 10), *label = gtk_label_new(text), *box = gtk_check_button_new_with_label(check);
    int ok, checked;
    gtk_label_set_xalign(GTK_LABEL(label), 0.0);
    gtk_label_set_wrap(GTK_LABEL(label), TRUE);
    gtk_box_append(GTK_BOX(body), label);
    gtk_box_append(GTK_BOX(body), box);
    g_object_ref(box);
    ok = sg_run_box(win, title, body, NULL);
    checked = gtk_check_button_get_active(GTK_CHECK_BUTTON(box)) ? 1 : 0;
    g_object_unref(box);
    return (ok ? 1 : 0) | (checked << 1);
}
__attribute__((weak)) PangoFontDescription *sg_font_answer = NULL;
static void sg_font_done(GObject *src, GAsyncResult *res, gpointer d) {
    (void) d;
    if (sg_font_answer) pango_font_description_free(sg_font_answer);
    sg_font_answer = gtk_font_dialog_choose_font_finish(GTK_FONT_DIALOG(src), res, NULL);
    sg_dialog_done = 1;
}
/* "family\x1fpoints\x1fbold\x1fitalic" (bold and italic 0 or 1), or NULL when cancelled. */
static const char *sg_choose_font(int win, const char *title, const char *family, double points, int bold, int italic) {
    GtkFontDialog *dlg = gtk_font_dialog_new();
    PangoFontDescription *initial = pango_font_description_new();
    static char *answer = NULL;
    GCancellable *c = sg_dialog_cancellable();
    gtk_font_dialog_set_title(dlg, title);
    gtk_font_dialog_set_modal(dlg, TRUE);
    pango_font_description_set_family(initial, family);
    if (points > 0) pango_font_description_set_size(initial, (int) (points * PANGO_SCALE));
    pango_font_description_set_weight(initial, bold ? PANGO_WEIGHT_BOLD : PANGO_WEIGHT_NORMAL);
    pango_font_description_set_style(initial, italic ? PANGO_STYLE_ITALIC : PANGO_STYLE_NORMAL);
    if (sg_font_answer) { pango_font_description_free(sg_font_answer); sg_font_answer = NULL; }
    sg_dialog_done = 0;
    gtk_font_dialog_choose_font(dlg, win > 0 ? GTK_WINDOW(sg_w[win]) : NULL, initial, c, sg_font_done, NULL);
    sg_wait_dialog();
    g_object_unref(c);
    g_object_unref(dlg);
    pango_font_description_free(initial);
    g_free(answer); answer = NULL;
    if (sg_font_answer) {
        const char *fam = pango_font_description_get_family(sg_font_answer);
        double size = pango_font_description_get_size(sg_font_answer) / (double) PANGO_SCALE;
        int b = pango_font_description_get_weight(sg_font_answer) >= PANGO_WEIGHT_BOLD;
        int i = pango_font_description_get_style(sg_font_answer) != PANGO_STYLE_NORMAL;
        char num[32];
        g_ascii_dtostr(num, sizeof num, size);
        answer = g_strdup_printf("%s\x1f%s\x1f%d\x1f%d", fam ? fam : "", num, b, i);
    }
    return answer;
}
static void sg_show_about(const char *name, const char *version, const char *copyright, const char *comments) {
    GtkWidget *a = gtk_about_dialog_new();
    guint timer = 0;
    gtk_about_dialog_set_program_name(GTK_ABOUT_DIALOG(a), name);
    gtk_about_dialog_set_version(GTK_ABOUT_DIALOG(a), version);
    gtk_about_dialog_set_copyright(GTK_ABOUT_DIALOG(a), copyright);
    gtk_about_dialog_set_comments(GTK_ABOUT_DIALOG(a), comments);
    gtk_window_set_modal(GTK_WINDOW(a), TRUE);
    gtk_window_set_hide_on_close(GTK_WINDOW(a), FALSE);
    g_signal_connect(a, "destroy", G_CALLBACK(sg_box_gone), NULL);
    sg_dialog_done = 0;
    timer = sg_box_timer(a);
    gtk_window_present(GTK_WINDOW(a));
    sg_wait_dialog();
    sg_box_timer_done(timer);
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

/* ---------- 1m: timers (event 24, id 0, a = timer id), the clipboard, window shortcuts
   (event 25, id = window, a = shortcut id), full screen, following the system's appearance,
   and scrolling a list or table row into view. ---------- */
__attribute__((weak)) GHashTable *sg_timer_sources = NULL;   /* timer id -> GLib source id */
typedef struct { int id; int repeat; } sg_timer_rec;
static gboolean sg_on_timer(gpointer d) {
    sg_timer_rec *r = d;
    sg_push(24, 0, r->id, 0);
    if (!r->repeat && sg_timer_sources) g_hash_table_remove(sg_timer_sources, GINT_TO_POINTER(r->id));
    return r->repeat ? G_SOURCE_CONTINUE : G_SOURCE_REMOVE;
}
static void sg_timer_start(int id, int ms, int repeat) {
    sg_timer_rec *r = g_new(sg_timer_rec, 1);
    guint src;
    if (!sg_timer_sources) sg_timer_sources = g_hash_table_new(g_direct_hash, g_direct_equal);
    r->id = id; r->repeat = repeat;
    src = g_timeout_add_full(G_PRIORITY_DEFAULT, (guint) ms, sg_on_timer, r, g_free);
    g_hash_table_insert(sg_timer_sources, GINT_TO_POINTER(id), GUINT_TO_POINTER(src));
}
static void sg_timer_stop(int id) {
    guint src;
    if (!sg_timer_sources) return;
    src = GPOINTER_TO_UINT(g_hash_table_lookup(sg_timer_sources, GINT_TO_POINTER(id)));
    if (src) { g_source_remove(src); g_hash_table_remove(sg_timer_sources, GINT_TO_POINTER(id)); }
}

/* The clipboard. GTK reads it asynchronously: the loop turns until the text arrives (at most
   a second), so the Eiffel query can answer at once. */
__attribute__((weak)) char *sg_clip_text = NULL;
__attribute__((weak)) int sg_clip_done = 0;
static void sg_clip_read_done(GObject *o, GAsyncResult *res, gpointer d) {
    char *t = gdk_clipboard_read_text_finish(GDK_CLIPBOARD(o), res, NULL);
    (void) d;
    g_free(sg_clip_text);
    sg_clip_text = t ? t : g_strdup("");
    sg_clip_done = 1;
}
static const char *sg_clipboard_text(void) {
    GdkClipboard *c = gdk_display_get_clipboard(gdk_display_get_default());
    gint64 until = g_get_monotonic_time() + G_USEC_PER_SEC;
    sg_clip_done = 0;
    gdk_clipboard_read_text_async(c, NULL, sg_clip_read_done, NULL);
    while (!sg_clip_done && g_get_monotonic_time() < until) g_main_context_iteration(NULL, TRUE);
    return sg_clip_done && sg_clip_text ? sg_clip_text : "";
}
static void sg_clipboard_set_text(const char *t) {
    gdk_clipboard_set_text(gdk_display_get_clipboard(gdk_display_get_default()), t ? t : "");
}

/* A window's own shortcuts: one GtkShortcutController, global in the window, each shortcut
   pushing 25; the window remembers each accelerator's shortcut id (for the test driver). */
static gboolean sg_on_window_shortcut(GtkWidget *w, GVariant *args, gpointer d) {
    (void) args;
    sg_push(25, sg_id_of(w), GPOINTER_TO_INT(d), 0);
    return TRUE;
}
static void sg_window_add_shortcut(int win, const char *spec, int shortcut_id) {
    GtkWidget *w = sg_w[win];
    GtkEventController *c = g_object_get_data(G_OBJECT(w), "sg-own-shortcuts");
    char accel[64], key[80];
    GtkShortcutTrigger *trigger;
    sg_accel(spec, accel, sizeof accel);
    if (!accel[0] || !(trigger = gtk_shortcut_trigger_parse_string(accel))) return;
    if (!c) {
        c = gtk_shortcut_controller_new();
        gtk_shortcut_controller_set_scope(GTK_SHORTCUT_CONTROLLER(c), GTK_SHORTCUT_SCOPE_GLOBAL);
        gtk_widget_add_controller(w, c);
        g_object_set_data(G_OBJECT(w), "sg-own-shortcuts", c);
    }
    gtk_shortcut_controller_add_shortcut(GTK_SHORTCUT_CONTROLLER(c),
        gtk_shortcut_new(trigger, gtk_callback_action_new(sg_on_window_shortcut, GINT_TO_POINTER(shortcut_id), NULL)));
    snprintf(key, sizeof key, "sg-sc:%s", accel);
    g_object_set_data(G_OBJECT(w), key, GINT_TO_POINTER(shortcut_id));
}
static void sg_test_press_shortcut(int win, const char *spec) {
    char accel[64], key[80];
    int sid;
    sg_accel(spec, accel, sizeof accel);
    snprintf(key, sizeof key, "sg-sc:%s", accel);
    sid = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[win]), key));
    if (sid > 0) sg_push(25, win, sid, 0);
}

static void sg_window_set_fullscreen(int win, int on) {
    if (on) gtk_window_fullscreen(GTK_WINDOW(sg_w[win])); else gtk_window_unfullscreen(GTK_WINDOW(sg_w[win]));
}
static int sg_window_is_fullscreen(int win) { return gtk_window_is_fullscreen(GTK_WINDOW(sg_w[win])) ? 1 : 0; }

/* Follow the system again: the setting goes back to its default (the dark handler reports a change). */
static void sg_follow_system_appearance(void) {
    gtk_settings_reset_property(gtk_settings_get_default(), "gtk-application-prefer-dark-theme");
}

/* A row into view: the list moves its adjustment to the row's bounds; the table asks the view. */
static void sg_list_scroll_to_row(int id, int row) {
    GtkListBoxRow *r = gtk_list_box_get_row_at_index(sg_list_box(id), row - 1);
    GtkAdjustment *v = gtk_scrolled_window_get_vadjustment(GTK_SCROLLED_WINDOW(sg_w[id]));
    graphene_rect_t b;
    double page, value;
    if (!r || !gtk_widget_compute_bounds(GTK_WIDGET(r), GTK_WIDGET(sg_list_box(id)), &b)) return;
    page = gtk_adjustment_get_page_size(v);
    value = gtk_adjustment_get_value(v);
    if (b.origin.y < value) gtk_adjustment_set_value(v, b.origin.y);
    else if (b.origin.y + b.size.height > value + page) gtk_adjustment_set_value(v, b.origin.y + b.size.height - page);
}

/* ---------- 1n: icons (GUI_ICON's names as Adwaita symbolic icons; "filter", which Adwaita
   lacks, is a funnel written once to the cache and found on the icon theme's search path),
   button styles, badges (in the pill overlay, always shown) and busy buttons. ---------- */
static const char *sg_icon_gtk(const char *name) {
    static const char *map[][2] = {
        {"add", "list-add-symbolic"}, {"remove", "list-remove-symbolic"}, {"close", "window-close-symbolic"},
        {"check", "object-select-symbolic"}, {"chevron-right", "go-next-symbolic"}, {"chevron-left", "go-previous-symbolic"},
        {"chevron-up", "go-up-symbolic"}, {"chevron-down", "go-down-symbolic"}, {"back", "go-previous-symbolic"},
        {"forward", "go-next-symbolic"}, {"search", "system-search-symbolic"}, {"settings", "emblem-system-symbolic"},
        {"delete", "user-trash-symbolic"}, {"edit", "document-edit-symbolic"}, {"folder", "folder-symbolic"},
        {"document", "text-x-generic-symbolic"}, {"open", "document-open-symbolic"}, {"save", "document-save-symbolic"},
        {"copy", "edit-copy-symbolic"}, {"cut", "edit-cut-symbolic"}, {"paste", "edit-paste-symbolic"},
        {"undo", "edit-undo-symbolic"}, {"redo", "edit-redo-symbolic"}, {"refresh", "view-refresh-symbolic"},
        {"play", "media-playback-start-symbolic"}, {"pause", "media-playback-pause-symbolic"},
        {"stop", "media-playback-stop-symbolic"}, {"more", "view-more-horizontal-symbolic"}, {"menu", "open-menu-symbolic"},
        {"info", "dialog-information-symbolic"}, {"warning", "dialog-warning-symbolic"}, {"error", "dialog-error-symbolic"},
        {"help", "help-browser-symbolic"}, {"star", "starred-symbolic"}, {"picture", "image-x-generic-symbolic"},
        {"home", "go-home-symbolic"}, {"user", "avatar-default-symbolic"}, {"mail", "mail-unread-symbolic"},
        {"calendar", "x-office-calendar-symbolic"}, {"clock", "preferences-system-time-symbolic"},
        {"lock", "changes-prevent-symbolic"}, {"bell", "preferences-system-notifications-symbolic"},
        {"download", "folder-download-symbolic"}, {"upload", "send-to-symbolic"}, {"print", "document-print-symbolic"},
        {"filter", "sg-filter-symbolic"}, {"sort", "view-sort-ascending-symbolic"}, {NULL, NULL}};
    int i;
    for (i = 0; map[i][0]; i++) if (!strcmp(map[i][0], name)) return map[i][1];
    return "image-missing";
}
__attribute__((weak)) int sg_icons_done = 0;
static void sg_icons_ready(void) {
    gchar *dir, *file;
    GtkCssProvider *p;
    if (sg_icons_done) return;
    sg_icons_done = 1;
    dir = g_build_filename(g_get_user_cache_dir(), "simple_gui", "icons", NULL);
    g_mkdir_with_parents(dir, 0755);
    file = g_build_filename(dir, "sg-filter-symbolic.svg", NULL);
    g_file_set_contents(file,
        "<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 16 16'>"
        "<path fill='#2e3436' d='M1 2h14l-5.5 6.5V14l-3-1.5V8.5z'/></svg>", -1, NULL);
    gtk_icon_theme_add_search_path(gtk_icon_theme_get_for_display(gdk_display_get_default()), dir);
    g_free(file);
    g_free(dir);
    p = gtk_css_provider_new();
    gtk_css_provider_load_from_string(p,
        "button.sg-pill { border-radius: 9999px; padding-left: 14px; padding-right: 14px; }"
        " label.sg-badge { background-color: #e01b24; color: #ffffff; border-radius: 9px;"
        " padding: 0 5px; font-size: 10px; font-weight: bold; min-height: 16px; }"
        " label.sg-badge.sg-badge-dot { min-width: 10px; min-height: 10px; padding: 0; border-radius: 5px; font-size: 1px; }");
    gtk_style_context_add_provider_for_display(gdk_display_get_default(), GTK_STYLE_PROVIDER(p),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(p);
}

/* A button's content, from what it holds: its text ("sg-text"), icon ("sg-icon") and busy
   state ("sg-busy"): a plain label, or a spinner or an icon beside the label. */
static void sg_button_build(int id) {
    GtkButton *b = GTK_BUTTON(sg_w[id]);
    const char *text = g_object_get_data(G_OBJECT(b), "sg-text");
    const char *icon = g_object_get_data(G_OBJECT(b), "sg-icon");
    int busy = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(b), "sg-busy"));
    GtkWidget *box, *lead;
    if (!busy && (!icon || !*icon)) { gtk_button_set_label(b, text ? text : ""); return; }
    sg_icons_ready();
    box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    if (busy) { lead = gtk_spinner_new(); gtk_spinner_start(GTK_SPINNER(lead)); }
    else lead = gtk_image_new_from_icon_name(sg_icon_gtk(icon));
    gtk_box_append(GTK_BOX(box), lead);
    if (text && *text) gtk_box_append(GTK_BOX(box), gtk_label_new(text));
    gtk_button_set_child(b, box);
}
static void sg_button_set_icon(int id, const char *name) {
    g_object_set_data_full(G_OBJECT(sg_w[id]), "sg-icon", g_strdup(name ? name : ""), g_free);
    sg_button_build(id);
}
static void sg_button_set_busy(int id, int on) {
    g_object_set_data(G_OBJECT(sg_w[id]), "sg-busy", GINT_TO_POINTER(on));
    sg_button_build(id);
}
static void sg_button_set_style(int id, int style) {
    GtkWidget *b = sg_w[id];
    sg_icons_ready();
    gtk_widget_remove_css_class(b, "suggested-action");
    gtk_widget_remove_css_class(b, "destructive-action");
    gtk_widget_remove_css_class(b, "flat");
    gtk_widget_remove_css_class(b, "sg-pill");
    if (style == 1) gtk_widget_add_css_class(b, "suggested-action");
    else if (style == 2) gtk_widget_add_css_class(b, "destructive-action");
    else if (style == 3) gtk_widget_add_css_class(b, "flat");
    else if (style == 4) gtk_widget_add_css_class(b, "sg-pill");
}
static const char *sg_test_button_icon(int id) {
    const char *icon = g_object_get_data(G_OBJECT(sg_w[id]), "sg-icon");
    return icon ? icon : "";
}

/* Badges: a label in the window's pill overlay at the widget's trailing top corner. */
__attribute__((weak)) GtkWidget *sg_badge_target[SG_MAX];
__attribute__((weak)) GtkWidget *sg_badge_label[SG_MAX] = {0};
static void sg_badge_sync(int id) {
    GtkWidget *t = sg_badge_target[id], *l = sg_badge_label[id];
    GtkOverlay *o;
    int kind = t ? GPOINTER_TO_INT(g_object_get_data(G_OBJECT(t), "sg-badge-kind")) : 0;
    if (l && (!kind || gtk_widget_get_parent(l) != (GtkWidget *) sg_pill_overlay(t))) {
        GtkWidget *parent = gtk_widget_get_parent(l);
        if (parent && GTK_IS_OVERLAY(parent)) gtk_overlay_remove_overlay(GTK_OVERLAY(parent), l);
        l = sg_badge_label[id];
    }
    if (!kind || !(o = sg_pill_overlay(t))) return;
    if (!l) {
        l = gtk_label_new("");
        gtk_widget_add_css_class(l, "sg-badge");
        gtk_widget_set_can_target(l, FALSE);
        g_object_set_data(G_OBJECT(l), "sg-badge-id", GINT_TO_POINTER(id));
        sg_badge_label[id] = l;
        g_object_add_weak_pointer(G_OBJECT(l), (gpointer *) &sg_badge_label[id]);
        gtk_overlay_add_overlay(o, l);
    }
    if (kind == 2) { gtk_label_set_text(GTK_LABEL(l), ""); gtk_widget_add_css_class(l, "sg-badge-dot"); }
    else {
        gtk_widget_remove_css_class(l, "sg-badge-dot");
        gtk_label_set_text(GTK_LABEL(l), g_object_get_data(G_OBJECT(t), "sg-badge-text"));
    }
    gtk_widget_set_visible(l, TRUE);
    gtk_widget_queue_allocate(GTK_WIDGET(o));
}
static void sg_badge_sync_all(void) {
    int i;
    for (i = 1; i < SG_MAX; i++) if (sg_badge_target[i]) sg_badge_sync(i);
}
static void sg_widget_set_badge(int id, const char *text, int kind) {
    GtkWidget *t = sg_w[id];
    if (!t) return;
    sg_icons_ready();
    if (sg_badge_target[id] != t) {
        sg_badge_target[id] = t;
        g_object_add_weak_pointer(G_OBJECT(t), (gpointer *) &sg_badge_target[id]);
    }
    g_object_set_data(G_OBJECT(t), "sg-badge-kind", GINT_TO_POINTER(kind));
    g_object_set_data_full(G_OBJECT(t), "sg-badge-text", g_strdup(text ? text : ""), g_free);
    sg_badge_sync(id);
}
static const char *sg_test_badge_shown(int id) {
    GtkWidget *l = id > 0 && id < SG_MAX ? sg_badge_label[id] : NULL;
    if (!l || !gtk_widget_get_mapped(l) || !sg_badge_target[id]) return "";
    if (GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_badge_target[id]), "sg-badge-kind")) == 2) return "\xE2\x80\xA2";
    return gtk_label_get_text(GTK_LABEL(l));
}

/* A tab with an icon or a badge: its label becomes a box (icon, title, badge); retitling
   then sets the box's title (see sg_tabs_set_title). */
static GtkWidget *sg_tab_box(int tabs, int page) {
    GtkNotebook *nb = GTK_NOTEBOOK(sg_w[tabs]);
    GtkWidget *p = gtk_notebook_get_nth_page(nb, page - 1), *box, *title;
    const char *text;
    if (!p) return NULL;
    if ((box = g_object_get_data(G_OBJECT(p), "sg-tab-box"))) return box;
    sg_icons_ready();
    text = gtk_notebook_get_tab_label_text(nb, p);
    box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    title = gtk_label_new(text ? text : "");
    gtk_box_append(GTK_BOX(box), title);
    g_object_set_data(G_OBJECT(p), "sg-tab-box", box);
    g_object_set_data(G_OBJECT(p), "sg-tab-title", title);
    gtk_notebook_set_tab_label(nb, p, box);
    return box;
}
static void sg_tabs_set_page_icon(int tabs, int page, const char *name) {
    GtkWidget *box = sg_tab_box(tabs, page), *p, *img;
    if (!box) return;
    p = gtk_notebook_get_nth_page(GTK_NOTEBOOK(sg_w[tabs]), page - 1);
    if ((img = g_object_get_data(G_OBJECT(p), "sg-tab-icon"))) gtk_box_remove(GTK_BOX(box), img);
    img = gtk_image_new_from_icon_name(sg_icon_gtk(name));
    gtk_box_prepend(GTK_BOX(box), img);
    g_object_set_data(G_OBJECT(p), "sg-tab-icon", img);
}
static void sg_tabs_set_page_badge(int tabs, int page, const char *text) {
    GtkWidget *box = sg_tab_box(tabs, page), *p, *b;
    if (!box) return;
    p = gtk_notebook_get_nth_page(GTK_NOTEBOOK(sg_w[tabs]), page - 1);
    b = g_object_get_data(G_OBJECT(p), "sg-tab-badge");
    if (!b) {
        b = gtk_label_new("");
        gtk_widget_add_css_class(b, "sg-badge");
        gtk_box_append(GTK_BOX(box), b);
        g_object_set_data(G_OBJECT(p), "sg-tab-badge", b);
    }
    gtk_label_set_text(GTK_LABEL(b), text ? text : "");
    gtk_widget_set_visible(b, text && *text);
}

/* A menu item's icon, kept so relabeling keeps it (sg_menu_set_item_text). */
__attribute__((weak)) char *sg_item_icon[SG_MAX_ITEMS] = {0};
static void sg_menu_rebuild_item(int item_id, const char *text) {
    GMenuItem *mi;
    if (item_id <= 0 || item_id >= SG_MAX_ITEMS || !sg_item_menu[item_id]) return;
    mi = g_menu_item_new(text, sg_item_action[item_id]);
    if (sg_item_accel[item_id]) g_menu_item_set_attribute(mi, "accel", "s", sg_item_accel[item_id]);
    if (sg_item_icon[item_id]) {
        GIcon *gi = g_themed_icon_new(sg_icon_gtk(sg_item_icon[item_id]));
        g_menu_item_set_icon(mi, gi);
        g_object_unref(gi);
    }
    g_menu_remove(sg_item_menu[item_id], sg_item_pos[item_id]);
    g_menu_insert_item(sg_item_menu[item_id], sg_item_pos[item_id], mi);
    g_object_unref(mi);
}
static void sg_menu_set_item_icon(int item_id, const char *name) {
    gchar *label;
    if (item_id <= 0 || item_id >= SG_MAX_ITEMS || !sg_item_menu[item_id]) return;
    sg_icons_ready();
    g_free(sg_item_icon[item_id]);
    sg_item_icon[item_id] = g_strdup(name);
    label = g_strdup(sg_menu_item_text(item_id));
    sg_menu_rebuild_item(item_id, label);
    g_free(label);
}

/* ---------- test driver ---------- */

/* A user's click is the "clicked" signal; gtk_widget_activate would emit it only after a 250 ms press animation. */
static void sg_test_click(int id) {
    if (sg_kind[id] == 9) gtk_check_button_set_active(GTK_CHECK_BUTTON(sg_w[id]), !gtk_check_button_get_active(GTK_CHECK_BUTTON(sg_w[id])));
    else if (sg_kind[id] == 42) g_signal_emit_by_name(g_object_get_data(G_OBJECT(sg_w[id]), "sg-main"), "clicked");   /* a split button's main part */
    else if (sg_kind[id] == 23) gtk_switch_set_active(GTK_SWITCH(sg_w[id]), !gtk_switch_get_active(GTK_SWITCH(sg_w[id])));
    else if (sg_kind[id] == 31) gtk_expander_set_expanded(GTK_EXPANDER(sg_w[id]), !gtk_expander_get_expanded(GTK_EXPANDER(sg_w[id])));
    else g_signal_emit_by_name(sg_w[id], "clicked");
}
static void sg_test_type(int id, const char *t) {   /* emits, like a user */
    GtkWidget *v = g_object_get_data(G_OBJECT(sg_w[id]), "sg-view");
    if (v) gtk_text_buffer_set_text(gtk_text_view_get_buffer(GTK_TEXT_VIEW(v)), t, -1);
    else gtk_editable_set_text(GTK_EDITABLE(sg_w[id]), t);
}
static void sg_test_choose(int id, int row) {
    if (sg_kind[id] == 14 || sg_kind[id] == 33) { sg_test_choose_node(id, row); return; }   /* a tree node, by its number */
    if (sg_kind[id] == 20 || sg_kind[id] == 21) { GtkWidget *b = sg_choice_at(id, row); if (b) sg_choice_set(b, TRUE); return; }   /* a click on the choice */
    if (sg_kind[id] == 32) { sg_test_pick_combo(id, row); return; }   /* an option picked */
    if (sg_kind[id] == 13) { gtk_selection_model_select_item(sg_table_model(id), (guint) (row - 1), TRUE); return; }   /* a table row, as a click */
    if (sg_kind[id] == 11) { gtk_notebook_set_current_page(GTK_NOTEBOOK(sg_w[id]), row - 1); return; }   /* a click on the tab */
    if (sg_kind[id] == 15) { gtk_drop_down_set_selected(GTK_DROP_DOWN(sg_w[id]), sg_dd_pos_of_choice(id, row)); return; }   /* choices only (1p) */   /* a pick from the popup */
    GtkListBoxRow *r = gtk_list_box_get_row_at_index(sg_list_box(id), row - 1);
    if (r && g_object_get_data(G_OBJECT(sg_list_box(id)), "sg-multiple")) {
        /* a plain click in a several-row list replaces the selection (1p) */
        sg_quiet++;
        gtk_list_box_unselect_all(sg_list_box(id));
        sg_quiet--;
    }
    if (r) gtk_list_box_select_row(sg_list_box(id), r);
}
static void sg_test_request_close(int win) { gtk_window_close(GTK_WINDOW(sg_w[win])); }   /* emits close-request */
static void sg_test_menu(int item_id) {
    /* the item's own action (an Edit role's is edit_cut and the like, not itemN); a disabled
       action does nothing, as a grayed item does */
    const char *detailed = (item_id > 0 && item_id < SG_MAX_ITEMS) ? sg_item_action[item_id] : NULL;
    char name[40];
    if (detailed && g_str_has_prefix(detailed, "app.")) snprintf(name, sizeof name, "%s", detailed + 4);
    else snprintf(name, sizeof name, "item%d", item_id);
    sg_update_edit_enabled();
    g_action_group_activate_action(G_ACTION_GROUP(sg_actions), name, NULL);
}
/* ---------- context menus: a GMenu outside the bar, shown by a GtkPopoverMenu where a
   secondary click lands. Its items are app.itemN actions like the bar's (event 5).
   (First pass by MACMINI, untested on GTK.) ---------- */
static void *sg_context_menu_new(void) { return g_menu_new(); }
static void sg_on_secondary(GtkGestureClick *g, int n, double x, double y, gpointer pop) {
    GdkRectangle r = { (int) x, (int) y, 1, 1 };
    (void) n;
    gtk_popover_set_pointing_to(GTK_POPOVER(pop), &r);
    gtk_popover_popup(GTK_POPOVER(pop));
    gtk_gesture_set_state(GTK_GESTURE(g), GTK_EVENT_SEQUENCE_CLAIMED);
}
static void sg_on_context_owner_destroy(GtkWidget *w, gpointer pop) { (void) w; gtk_widget_unparent(GTK_WIDGET(pop)); }
static void sg_widget_set_context_menu(int id, void *menu) {
    GtkWidget *w = sg_w[id];
    GtkWidget *pop = g_object_get_data(G_OBJECT(w), "sg-context-popover");
    GtkGesture *g;
    if (pop) {
        /* set again: the same popover shows the new menu (a second gesture and popover would
           stack, both opening on one right-click) */
        gtk_popover_menu_set_menu_model(GTK_POPOVER_MENU(pop), G_MENU_MODEL(menu));
        g_object_set_data(G_OBJECT(w), "sg-context", menu);
        return;
    }
    pop = gtk_popover_menu_new_from_model(G_MENU_MODEL(menu));
    g = gtk_gesture_click_new();
    gtk_widget_set_parent(pop, w);
    gtk_popover_set_has_arrow(GTK_POPOVER(pop), FALSE);
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(g), GDK_BUTTON_SECONDARY);
    g_signal_connect(g, "pressed", G_CALLBACK(sg_on_secondary), pop);
    gtk_widget_add_controller(w, GTK_EVENT_CONTROLLER(g));
    g_signal_connect(w, "destroy", G_CALLBACK(sg_on_context_owner_destroy), pop);
    g_object_set_data(G_OBJECT(w), "sg-context", menu);
    g_object_set_data(G_OBJECT(w), "sg-context-popover", pop);
}
/* Choose item `item_id' from widget `id''s context menu as a user would: 0 when that menu
   has no such item (or the widget has none). */
static int sg_test_context_menu(int id, int item_id) {
    GMenuModel *m = g_object_get_data(G_OBJECT(sg_w[id]), "sg-context");
    char want[32];
    int i, n;
    if (!m) return 0;
    snprintf(want, sizeof want, "app.item%d", item_id);
    n = g_menu_model_get_n_items(m);
    for (i = 0; i < n; i++) {
        gchar *a = NULL;
        if (g_menu_model_get_item_attribute(m, i, G_MENU_ATTRIBUTE_ACTION, "s", &a) && a && !strcmp(a, want)) {
            g_free(a);
            sg_test_menu(item_id);
            return 1;
        }
        g_free(a);
    }
    return 0;
}
/* A snapshot shows the window as its user sees it while using it. A window the desktop has
   not focused (WSLg gives a new window the focus or not, depending on what else is happening)
   wears GTK's "backdrop" style: gray title, every control grayed as if disabled. So the
   snapshot lifts the backdrop state, lets one frame restyle, draws, and puts it back. */
static int sg_snapshot(int id, const char *path) {
    GtkWidget *w = sg_w[id];
    int W = gtk_widget_get_width(w), H = gtk_widget_get_height(w), ok;
    gboolean backdrop = (gtk_widget_get_state_flags(w) & GTK_STATE_FLAG_BACKDROP) != 0;
    GdkPaintable *p; GtkSnapshot *s; GskRenderNode *n; GdkTexture *t;
    double k = sg_scale(id);   /* device pixels, as the screen shows it (2x at 200%) */
    graphene_rect_t vp;
    if (W <= 0 || H <= 0) { g_warning("simple_gui snapshot: widget %d has no size yet (%d x %d)", id, W, H); return 0; }
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
    gtk_snapshot_scale(s, (float) k, (float) k);   /* GSK redraws text and lines at that scale */
    gdk_paintable_snapshot(p, GDK_SNAPSHOT(s), W, H);
    n = gtk_snapshot_free_to_node(s);
    {
        /* A widget waiting for its allocation (something was just added, such as a toast in
           the overlay) paints nothing until the next frame lays it out: wait for frames, up to
           half a second, and draw again. */
        gint64 until = g_get_monotonic_time() + 500 * 1000;
        while (!n && g_get_monotonic_time() < until) {
            while (g_main_context_iteration(NULL, FALSE)) { }
            g_usleep(10000);
            s = gtk_snapshot_new();
            gtk_snapshot_scale(s, (float) k, (float) k);
            gdk_paintable_snapshot(p, GDK_SNAPSHOT(s), W, H);
            n = gtk_snapshot_free_to_node(s);
        }
    }
    if (!n) { g_warning("simple_gui snapshot: widget %d drew nothing", id); g_object_unref(p); return 0; }
    graphene_rect_init(&vp, 0, 0, (float) (W * k), (float) (H * k));
    t = gsk_renderer_render_texture(gtk_native_get_renderer(GTK_NATIVE(w)), n, &vp);
    ok = gdk_texture_save_to_png(t, path) ? 1 : 0;
    if (!ok) g_warning("simple_gui snapshot: could not write %s", path);
    g_object_unref(t); gsk_render_node_unref(n); g_object_unref(p);
    if (backdrop && (!GTK_IS_WINDOW(w) || !gtk_window_is_active(GTK_WINDOW(w)))) gtk_widget_set_state_flags(w, GTK_STATE_FLAG_BACKDROP, FALSE);
    return ok;
}
/* The tree table answers with its column view (a tree-grid), not the scroll window around it. */
static const char *sg_role(int id) { return sg_role_nick((sg_kind[id] == 33 || sg_kind[id] == 49) ? sg_a11y_target(id) : sg_w[id]); }

/* Drive the loop until the queue stays empty for one turn, or `ms' pass (tests). */
static void sg_pump_until_idle(int ms) {
    gint64 until = g_get_monotonic_time() + (gint64) ms * 1000;
    while (g_get_monotonic_time() < until) {
        while (g_main_context_iteration(NULL, FALSE)) { }
        if (!g_main_context_pending(NULL)) break;
    }
}

/* ---------- 1o: spinner (kind 51), info bar (kind 52, event 26), toasts (event 27) and
   desktop notifications (D-Bus org.freedesktop.Notifications, event 28). ---------- */
__attribute__((weak)) int sg_feedback_css_done = 0;
static void sg_feedback_css(void) {
    GtkCssProvider *p;
    if (sg_feedback_css_done) return;
    sg_feedback_css_done = 1;
    p = gtk_css_provider_new();
    gtk_css_provider_load_from_string(p,
        "box.sg-info-bar { padding: 6px 10px; border-radius: 6px; }"
        " box.sg-info-1 { background-color: #dbe9fb; color: #1a3a6b; }"
        " box.sg-info-2 { background-color: #def4e1; color: #1e5b2a; }"
        " box.sg-info-3 { background-color: #fff1c9; color: #6b4e00; }"
        " box.sg-info-4 { background-color: #fde0e0; color: #7a1d1d; }"
        " box.sg-toast { background-color: rgba(30,30,30,0.92); color: #ffffff; border-radius: 9999px;"
        " padding: 6px 16px; margin-bottom: 18px; }"
        " box.sg-toast button { color: #8ab4f8; }");
    gtk_style_context_add_provider_for_display(gdk_display_get_default(), GTK_STYLE_PROVIDER(p),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(p);
}

static int sg_spinner(void) {
    GtkWidget *s = gtk_spinner_new();
    gtk_widget_set_halign(s, GTK_ALIGN_START);
    gtk_widget_set_size_request(s, 20, 20);
    return sg_reg(s, 51);
}
static void sg_spinner_set(int id, int on) {
    if (on) gtk_spinner_start(GTK_SPINNER(sg_w[id])); else gtk_spinner_stop(GTK_SPINNER(sg_w[id]));
}

static const char *sg_info_icon(int kind) {
    return kind == 2 ? "object-select-symbolic" : kind == 3 ? "dialog-warning-symbolic"
        : kind == 4 ? "dialog-error-symbolic" : "dialog-information-symbolic";
}
static void sg_on_info_action(GtkButton *b, gpointer d) {
    GtkWidget *bar = g_object_get_data(G_OBJECT(b), "sg-bar");
    sg_push(26, sg_id_of(bar), GPOINTER_TO_INT(d), 0);
}
static int sg_info_bar(int kind, const char *message) {
    GtkWidget *bar = g_object_new(GTK_TYPE_BOX, "orientation", GTK_ORIENTATION_HORIZONTAL, "spacing", 8,
                                  "accessible-role", GTK_ACCESSIBLE_ROLE_ALERT, NULL);
    GtkWidget *icon = gtk_image_new_from_icon_name(sg_info_icon(kind));
    GtkWidget *label = gtk_label_new(message);
    GtkWidget *actions = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 4);
    GtkWidget *close = gtk_button_new_from_icon_name("window-close-symbolic");
    char cls[16];
    int id = sg_reg(bar, 52);
    sg_feedback_css();
    gtk_widget_add_css_class(bar, "sg-info-bar");
    snprintf(cls, sizeof cls, "sg-info-%d", kind);
    gtk_widget_add_css_class(bar, cls);
    g_object_set_data(G_OBJECT(bar), "sg-kind-class", GINT_TO_POINTER(kind));
    gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_NONE);
    gtk_label_set_xalign(GTK_LABEL(label), 0.0);
    gtk_widget_set_hexpand(label, TRUE);
    gtk_widget_add_css_class(close, "flat");
    gtk_widget_set_visible(close, FALSE);
    g_object_set_data(G_OBJECT(close), "sg-bar", bar);
    g_signal_connect(close, "clicked", G_CALLBACK(sg_on_info_action), GINT_TO_POINTER(0));
    gtk_box_append(GTK_BOX(bar), icon);
    gtk_box_append(GTK_BOX(bar), label);
    gtk_box_append(GTK_BOX(bar), actions);
    gtk_box_append(GTK_BOX(bar), close);
    g_object_set_data(G_OBJECT(bar), "sg-icon", icon);
    g_object_set_data(G_OBJECT(bar), "sg-label", label);
    g_object_set_data(G_OBJECT(bar), "sg-actions", actions);
    g_object_set_data(G_OBJECT(bar), "sg-close", close);
    gtk_accessible_update_property(GTK_ACCESSIBLE(bar), GTK_ACCESSIBLE_PROPERTY_LABEL, message, -1);
    g_object_set_data_full(G_OBJECT(bar), "sg-a11y", g_strdup(message), g_free);
    return id;
}
static void sg_info_bar_set(int id, int kind, const char *message) {
    GtkWidget *bar = sg_w[id];
    char cls[16];
    snprintf(cls, sizeof cls, "sg-info-%d", GPOINTER_TO_INT(g_object_get_data(G_OBJECT(bar), "sg-kind-class")));
    gtk_widget_remove_css_class(bar, cls);
    snprintf(cls, sizeof cls, "sg-info-%d", kind);
    gtk_widget_add_css_class(bar, cls);
    g_object_set_data(G_OBJECT(bar), "sg-kind-class", GINT_TO_POINTER(kind));
    gtk_image_set_from_icon_name(GTK_IMAGE(g_object_get_data(G_OBJECT(bar), "sg-icon")), sg_info_icon(kind));
    gtk_label_set_text(GTK_LABEL(g_object_get_data(G_OBJECT(bar), "sg-label")), message);
    gtk_accessible_update_property(GTK_ACCESSIBLE(bar), GTK_ACCESSIBLE_PROPERTY_LABEL, message, -1);
    g_object_set_data_full(G_OBJECT(bar), "sg-a11y", g_strdup(message), g_free);
}
static void sg_info_bar_add_action(int id, const char *text, int number) {
    GtkWidget *b = gtk_button_new_with_label(text);
    g_object_set_data(G_OBJECT(b), "sg-bar", sg_w[id]);
    g_signal_connect(b, "clicked", G_CALLBACK(sg_on_info_action), GINT_TO_POINTER(number));
    gtk_box_append(GTK_BOX(g_object_get_data(G_OBJECT(sg_w[id]), "sg-actions")), b);
}
static void sg_info_bar_set_closable(int id, int on) {
    gtk_widget_set_visible(g_object_get_data(G_OBJECT(sg_w[id]), "sg-close"), on);
}

/* A toast: a dark pill at the bottom of the window's overlay, gone after its life. */
static void sg_toast_remove(GtkWidget *win) {
    GtkWidget *t = g_object_get_data(G_OBJECT(win), "sg-toast");
    guint src = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(win), "sg-toast-src"));
    if (src) g_source_remove(src);
    g_object_set_data(G_OBJECT(win), "sg-toast-src", NULL);
    if (t) {
        GtkWidget *parent = gtk_widget_get_parent(t);
        if (parent && GTK_IS_OVERLAY(parent)) gtk_overlay_remove_overlay(GTK_OVERLAY(parent), t);
    }
    g_object_set_data(G_OBJECT(win), "sg-toast", NULL);
    g_object_set_data(G_OBJECT(win), "sg-toast-button", NULL);
    g_object_set_data(G_OBJECT(win), "sg-toast-id", NULL);
    g_object_set_data_full(G_OBJECT(win), "sg-toast-text", g_strdup(""), g_free);
}
static gboolean sg_toast_expired(gpointer d) {
    GtkWidget *win = d;
    g_object_set_data(G_OBJECT(win), "sg-toast-src", NULL);
    sg_toast_remove(win);
    return G_SOURCE_REMOVE;
}
static void sg_toast_on_destroy(GtkWidget *win, gpointer d) {
    guint src = GPOINTER_TO_UINT(g_object_get_data(G_OBJECT(win), "sg-toast-src"));
    (void) d;
    if (src) g_source_remove(src);
    g_object_set_data(G_OBJECT(win), "sg-toast-src", NULL);
}
static void sg_on_toast_action(GtkButton *b, gpointer d) {
    GtkWidget *win = d;
    int tid = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(win), "sg-toast-id"));
    (void) b;
    if (tid > 0) sg_push(27, sg_id_of(win), tid, 0);
    sg_toast_remove(win);
}
static void sg_window_show_toast(int win, const char *message, const char *action, int toast_id) {
    GtkWidget *w = sg_w[win], *box, *button;
    GtkOverlay *o = g_object_get_data(G_OBJECT(w), "sg-overlay");
    guint src;
    if (!o) { sg_window_outer(win); o = g_object_get_data(G_OBJECT(w), "sg-overlay"); }
    if (!o) return;
    sg_feedback_css();
    if (!g_object_get_data(G_OBJECT(w), "sg-toast-hooked")) {
        g_signal_connect(w, "destroy", G_CALLBACK(sg_toast_on_destroy), NULL);
        g_object_set_data(G_OBJECT(w), "sg-toast-hooked", GINT_TO_POINTER(1));
    }
    sg_toast_remove(w);
    box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12);
    gtk_widget_add_css_class(box, "sg-toast");
    gtk_widget_set_halign(box, GTK_ALIGN_CENTER);
    gtk_widget_set_valign(box, GTK_ALIGN_END);
    gtk_box_append(GTK_BOX(box), gtk_label_new(message));
    if (action && *action) {
        button = gtk_button_new_with_label(action);
        g_object_set_data(G_OBJECT(w), "sg-toast-button", button);
        gtk_widget_add_css_class(button, "flat");
        g_signal_connect(button, "clicked", G_CALLBACK(sg_on_toast_action), w);
        gtk_box_append(GTK_BOX(box), button);
    }
    gtk_overlay_add_overlay(o, box);
    g_object_set_data(G_OBJECT(w), "sg-toast", box);
    g_object_set_data(G_OBJECT(w), "sg-toast-id", GINT_TO_POINTER(toast_id));
    g_object_set_data_full(G_OBJECT(w), "sg-toast-text", g_strdup(message), g_free);
    src = g_timeout_add(toast_id > 0 ? 8000 : 4000, sg_toast_expired, w);
    g_object_set_data(G_OBJECT(w), "sg-toast-src", GUINT_TO_POINTER(src));
}
static const char *sg_test_toast_shown(int win) {
    const char *t = g_object_get_data(G_OBJECT(sg_w[win]), "sg-toast") ? g_object_get_data(G_OBJECT(sg_w[win]), "sg-toast-text") : NULL;
    return t ? t : "";
}
static void sg_test_toast_press(int win) {
    GtkWidget *b = g_object_get_data(G_OBJECT(sg_w[win]), "sg-toast-button");
    if (b) g_signal_emit_by_name(b, "clicked");
}
static void sg_test_info_bar_press(int id, int number) {
    GtkWidget *b = NULL;
    if (number == 0) b = g_object_get_data(G_OBJECT(sg_w[id]), "sg-close");
    else {
        GtkWidget *c = gtk_widget_get_first_child(g_object_get_data(G_OBJECT(sg_w[id]), "sg-actions"));
        int i;
        for (i = 1; c && i < number; i++) c = gtk_widget_get_next_sibling(c);
        b = c;
    }
    if (b) g_signal_emit_by_name(b, "clicked");
}

/* Desktop notifications over D-Bus (no new library): Notify, and ActionInvoked for a click.
   With no notification server (a bare session) the call fails quietly. */
__attribute__((weak)) GDBusConnection *sg_notify_bus = NULL;
__attribute__((weak)) GHashTable *sg_notify_ids = NULL;   /* server id -> our id */
static void sg_on_notify_action(GDBusConnection *c, const gchar *sender, const gchar *path, const gchar *iface,
                                const gchar *signal, GVariant *params, gpointer d) {
    guint32 server_id = 0;
    const gchar *key = NULL;
    int ours;
    (void) c; (void) sender; (void) path; (void) iface; (void) signal; (void) d;
    g_variant_get(params, "(u&s)", &server_id, &key);
    ours = sg_notify_ids ? GPOINTER_TO_INT(g_hash_table_lookup(sg_notify_ids, GUINT_TO_POINTER(server_id))) : 0;
    if (ours > 0) sg_push(28, 0, ours, 0);
}
static void sg_notify_done(GObject *src, GAsyncResult *res, gpointer d) {
    GVariant *r = g_dbus_connection_call_finish(G_DBUS_CONNECTION(src), res, NULL);
    if (r) {
        guint32 server_id = 0;
        g_variant_get(r, "(u)", &server_id);
        if (GPOINTER_TO_INT(d) > 0 && sg_notify_ids)
            g_hash_table_insert(sg_notify_ids, GUINT_TO_POINTER(server_id), d);
        g_variant_unref(r);
    }
}
static void sg_notify(const char *title, const char *body, int notification_id) {
    GVariantBuilder actions, hints;
    if (!sg_notify_bus) {
        sg_notify_bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, NULL);
        if (!sg_notify_bus) return;
        sg_notify_ids = g_hash_table_new(g_direct_hash, g_direct_equal);
        g_dbus_connection_signal_subscribe(sg_notify_bus, "org.freedesktop.Notifications",
            "org.freedesktop.Notifications", "ActionInvoked", "/org/freedesktop/Notifications",
            NULL, G_DBUS_SIGNAL_FLAGS_NONE, sg_on_notify_action, NULL, NULL);
    }
    g_variant_builder_init(&actions, G_VARIANT_TYPE("as"));
    if (notification_id > 0) { g_variant_builder_add(&actions, "s", "default"); g_variant_builder_add(&actions, "s", "Open"); }
    g_variant_builder_init(&hints, G_VARIANT_TYPE("a{sv}"));
    g_dbus_connection_call(sg_notify_bus, "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
        "org.freedesktop.Notifications", "Notify",
        g_variant_new("(susssasa{sv}i)", sg_app_name, (guint32) 0, "", title, body ? body : "", &actions, &hints, -1),
        G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, 2000, NULL, sg_notify_done, GINT_TO_POINTER(notification_id));
}

/* ---------- 1p: forms. Password field (an entry with an eye: 12, a = 1 revealed), editing
   ended (29, a field the user left), field errors (the error style and a note under the field,
   in the window overlay as the Mac has it), suggestions (a popover that never takes the focus
   or runs a loop), dropdown headers and separators (choices numbered without them), date and
   time picker (53; 2, a = date, b = h*60+m), month picker (54; 2, a = y*100+m), range slider
   (55; 2, a = low, b = high), several rows selected in a list. ---------- */

/* Editing ended: the field lost the focus. */
static void sg_on_field_leave(GtkEventControllerFocus *c, gpointer d) {
    /* Not as the window closes: the field is gone by the time the event is read (its sg_w
       slot dangles), and validating it touched freed memory. */
    GtkWidget *w = gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(c));
    GtkRoot *root = gtk_widget_get_root(w);
    if (sg_quiet || !root || !gtk_widget_get_mapped(w) || gtk_widget_in_destruction(GTK_WIDGET(root))
        || !gtk_widget_get_visible(GTK_WIDGET(root))) return;
    sg_push(29, GPOINTER_TO_INT(d), 0, 0);
}
static void sg_field_hook_leave(GtkWidget *e, int id) {
    GtkEventController *c = gtk_event_controller_focus_new();
    g_signal_connect(c, "leave", G_CALLBACK(sg_on_field_leave), GINT_TO_POINTER(id));
    gtk_widget_add_controller(e, c);
}
static void sg_test_end_editing(int id) { sg_push(29, id, 0, 0); }

/* Password field */
static void sg_password_show(GtkWidget *e, int on) {
    gtk_entry_set_visibility(GTK_ENTRY(e), on);
    gtk_entry_set_icon_from_icon_name(GTK_ENTRY(e), GTK_ENTRY_ICON_SECONDARY, on ? "view-conceal-symbolic" : "view-reveal-symbolic");
    gtk_entry_set_icon_tooltip_text(GTK_ENTRY(e), GTK_ENTRY_ICON_SECONDARY, on ? "Hide the password" : "Show the password");
}
static void sg_on_password_eye(GtkEntry *e, GtkEntryIconPosition pos, gpointer d) {
    int on = !gtk_entry_get_visibility(e);
    (void) d;
    if (pos != GTK_ENTRY_ICON_SECONDARY) return;
    sg_password_show(GTK_WIDGET(e), on);
    sg_push(12, sg_id_of(e), on, 0);
}
static int sg_password_field(void) {
    GtkWidget *e = gtk_entry_new();
    int id = sg_reg(e, 6);
    gtk_entry_set_input_purpose(GTK_ENTRY(e), GTK_INPUT_PURPOSE_PASSWORD);
    sg_password_show(e, 0);
    g_signal_connect(e, "icon-press", G_CALLBACK(sg_on_password_eye), NULL);
    g_signal_connect(e, "changed", G_CALLBACK(sg_on_changed), NULL);
    g_signal_connect(e, "activate", G_CALLBACK(sg_on_activate), NULL);
    sg_field_hook_leave(e, id);
    return id;
}
static void sg_password_set_revealed(int id, int on) { sg_password_show(sg_w[id], on); }
static int sg_password_is_revealed(int id) { return gtk_entry_get_visibility(GTK_ENTRY(sg_w[id])); }
static int sg_caps_lock_on(void) {
    GdkSeat *s = gdk_display_get_default_seat(gdk_display_get_default());
    GdkDevice *k = s ? gdk_seat_get_keyboard(s) : NULL;
    return k ? gdk_device_get_caps_lock_state(k) : 0;
}
static void sg_test_toggle_reveal(int id) { g_signal_emit_by_name(sg_w[id], "icon-press", GTK_ENTRY_ICON_SECONDARY); }

/* Field errors: the "error" style, and a red note just under the field in the window overlay. */
static gboolean sg_error_position(GtkOverlay *o, GtkWidget *child, GdkRectangle *a, gpointer d) {
    GtkWidget *t = g_object_get_data(G_OBJECT(child), "sg-error-for");
    graphene_rect_t r;
    int w, h;
    (void) d;
    if (!t || !gtk_widget_get_mapped(t) || !gtk_widget_compute_bounds(t, GTK_WIDGET(o), &r)) return FALSE;
    gtk_widget_measure(child, GTK_ORIENTATION_HORIZONTAL, -1, NULL, &w, NULL, NULL);
    gtk_widget_measure(child, GTK_ORIENTATION_VERTICAL, -1, NULL, &h, NULL, NULL);
    a->x = (int) r.origin.x + 2;
    if (gtk_widget_get_direction(t) == GTK_TEXT_DIR_RTL) a->x = (int) (r.origin.x + r.size.width) - w - 2;
    a->y = (int) (r.origin.y + r.size.height) + 1;
    a->width = w;
    a->height = h;
    return TRUE;
}
__attribute__((weak)) int sg_error_css_done = 0;
static void sg_error_place(int id) {
    GtkWidget *t = sg_w[id], *note = g_object_get_data(G_OBJECT(t), "sg-error-note");
    GtkRoot *root = gtk_widget_get_root(t);
    GtkOverlay *o = root ? g_object_get_data(G_OBJECT(root), "sg-overlay") : NULL;
    if (!note || !o || gtk_widget_get_parent(note)) return;
    if (!g_object_get_data(G_OBJECT(o), "sg-error-hooked")) {
        /* after the pills' handler, which leaves this child alone */
        g_signal_connect(o, "get-child-position", G_CALLBACK(sg_error_position), NULL);
        g_object_set_data(G_OBJECT(o), "sg-error-hooked", GINT_TO_POINTER(1));
    }
    gtk_overlay_add_overlay(o, note);
}
static void sg_on_error_owner_map(GtkWidget *t, gpointer d) { sg_error_place(GPOINTER_TO_INT(d)); }
static void sg_field_set_error(int id, const char *message) {
    GtkWidget *t = sg_w[id], *note = g_object_get_data(G_OBJECT(t), "sg-error-note");
    if (!sg_error_css_done) {
        GtkCssProvider *p = gtk_css_provider_new();
        sg_error_css_done = 1;
        gtk_css_provider_load_from_string(p, "label.sg-error-note { color: #c01c28; font-size: smaller; }");
        gtk_style_context_add_provider_for_display(gdk_display_get_default(), GTK_STYLE_PROVIDER(p), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
        g_object_unref(p);
    }
    if (message && *message) {
        gtk_widget_add_css_class(t, "error");
        if (!note) {
            note = gtk_label_new("");
            gtk_widget_add_css_class(note, "sg-error-note");
            gtk_widget_set_can_target(note, FALSE);
            g_object_set_data(G_OBJECT(note), "sg-error-for", t);
            g_object_set_data(G_OBJECT(t), "sg-error-note", note);
            g_signal_connect(t, "map", G_CALLBACK(sg_on_error_owner_map), GINT_TO_POINTER(id));
        }
        gtk_label_set_text(GTK_LABEL(note), message);
        gtk_widget_set_visible(note, TRUE);
        g_object_set_data_full(G_OBJECT(t), "sg-error-text", g_strdup(message), g_free);
        gtk_accessible_update_property(GTK_ACCESSIBLE(t), GTK_ACCESSIBLE_PROPERTY_DESCRIPTION, message, -1);
        gtk_accessible_update_state(GTK_ACCESSIBLE(t), GTK_ACCESSIBLE_STATE_INVALID, GTK_ACCESSIBLE_INVALID_TRUE, -1);
        sg_error_place(id);
    } else {
        gtk_widget_remove_css_class(t, "error");
        if (note) gtk_widget_set_visible(note, FALSE);
        g_object_set_data_full(G_OBJECT(t), "sg-error-text", g_strdup(""), g_free);
        gtk_accessible_reset_property(GTK_ACCESSIBLE(t), GTK_ACCESSIBLE_PROPERTY_DESCRIPTION);
        gtk_accessible_reset_state(GTK_ACCESSIBLE(t), GTK_ACCESSIBLE_STATE_INVALID);
    }
}
static const char *sg_field_error_shown(int id) {
    GtkWidget *note = g_object_get_data(G_OBJECT(sg_w[id]), "sg-error-note");
    const char *s = g_object_get_data(G_OBJECT(sg_w[id]), "sg-error-text");
    return (note && gtk_widget_get_visible(note) && s) ? s : "";
}

/* Suggestions: a popover under the field that never takes the focus (autohide off) and never
   runs a loop; Up and Down move, Return or a click chooses, Escape closes. */
static void sg_suggest_choose(int id, int i) {
    GtkWidget *list = g_object_get_data(G_OBJECT(sg_w[id]), "sg-suggest-list");
    GtkWidget *pop = g_object_get_data(G_OBJECT(sg_w[id]), "sg-suggest-pop");
    GtkListBoxRow *r = list ? gtk_list_box_get_row_at_index(GTK_LIST_BOX(list), i - 1) : NULL;
    if (!r) return;
    {
        gchar *text = g_strdup(gtk_label_get_text(GTK_LABEL(gtk_list_box_row_get_child(r))));
        gtk_popover_popdown(GTK_POPOVER(pop));
        gtk_editable_set_text(GTK_EDITABLE(sg_w[id]), text);   /* the user's fill: "changed" sends 2 */
        gtk_editable_set_position(GTK_EDITABLE(sg_w[id]), -1);
        g_free(text);
    }
}
static void sg_on_suggest_row(GtkListBox *l, GtkListBoxRow *r, gpointer d) {
    (void) l;
    sg_suggest_choose(GPOINTER_TO_INT(d), gtk_list_box_row_get_index(r) + 1);
}
static gboolean sg_on_suggest_key(GtkEventControllerKey *k, guint keyval, guint code, GdkModifierType m, gpointer d) {
    int id = GPOINTER_TO_INT(d);
    GtkWidget *pop = g_object_get_data(G_OBJECT(sg_w[id]), "sg-suggest-pop");
    GtkWidget *list = g_object_get_data(G_OBJECT(sg_w[id]), "sg-suggest-list");
    GtkListBoxRow *r;
    int at;
    (void) k; (void) code; (void) m;
    if (!pop || !gtk_widget_get_visible(pop)) return FALSE;
    r = gtk_list_box_get_selected_row(GTK_LIST_BOX(list));
    at = r ? gtk_list_box_row_get_index(r) : -1;
    if (keyval == GDK_KEY_Down || keyval == GDK_KEY_Up) {
        GtkListBoxRow *next = gtk_list_box_get_row_at_index(GTK_LIST_BOX(list), keyval == GDK_KEY_Down ? at + 1 : (at > 0 ? at - 1 : 0));
        if (next) gtk_list_box_select_row(GTK_LIST_BOX(list), next);
        return TRUE;
    }
    if ((keyval == GDK_KEY_Return || keyval == GDK_KEY_KP_Enter) && r) { sg_suggest_choose(id, at + 1); return TRUE; }
    if (keyval == GDK_KEY_Escape) { gtk_popover_popdown(GTK_POPOVER(pop)); return TRUE; }
    return FALSE;
}
static void sg_field_set_suggestions(int id, const char *joined) {
    GtkWidget *e = sg_w[id], *pop = g_object_get_data(G_OBJECT(e), "sg-suggest-pop"), *list;
    gchar **items;
    int i;
    if (!pop) {
        GtkEventController *k = gtk_event_controller_key_new();
        pop = gtk_popover_new();
        list = gtk_list_box_new();
        gtk_popover_set_autohide(GTK_POPOVER(pop), FALSE);
        gtk_popover_set_has_arrow(GTK_POPOVER(pop), FALSE);
        gtk_popover_set_position(GTK_POPOVER(pop), GTK_POS_BOTTOM);
        gtk_widget_set_can_focus(pop, FALSE);
        gtk_widget_set_can_focus(list, FALSE);
        gtk_popover_set_child(GTK_POPOVER(pop), list);
        gtk_widget_set_parent(pop, e);
        g_signal_connect(list, "row-activated", G_CALLBACK(sg_on_suggest_row), GINT_TO_POINTER(id));
        gtk_event_controller_set_propagation_phase(k, GTK_PHASE_CAPTURE);
        g_signal_connect(k, "key-pressed", G_CALLBACK(sg_on_suggest_key), GINT_TO_POINTER(id));
        gtk_widget_add_controller(e, k);
        g_object_set_data(G_OBJECT(e), "sg-suggest-pop", pop);
        g_object_set_data(G_OBJECT(e), "sg-suggest-list", list);
    }
    list = g_object_get_data(G_OBJECT(e), "sg-suggest-list");
    gtk_list_box_remove_all(GTK_LIST_BOX(list));
    items = g_strsplit(joined ? joined : "", "\x1f", -1);
    for (i = 0; items[i] && *items[i]; i++) {
        GtkWidget *l = gtk_label_new(items[i]);
        gtk_label_set_xalign(GTK_LABEL(l), 0.0);
        gtk_widget_set_margin_start(l, 6); gtk_widget_set_margin_end(l, 6);
        gtk_list_box_append(GTK_LIST_BOX(list), l);
    }
    g_strfreev(items);
    if (i > 0 && gtk_widget_get_mapped(e)) gtk_popover_popup(GTK_POPOVER(pop));
    else gtk_popover_popdown(GTK_POPOVER(pop));
}
static void sg_test_pick_suggestion(int id, int i) { sg_suggest_choose(id, i); }

/* Dropdown headers and separators: rows that are not choices. Choices are numbered without
   them ("sg-dd-kinds": per position, 0 choice, 1 header, 2 separator; none until the first). */
static GByteArray *sg_dd_kinds(int id) { return g_object_get_data(G_OBJECT(sg_w[id]), "sg-dd-kinds"); }
static int sg_dd_is_choice(int id, guint pos) {
    GByteArray *k = sg_dd_kinds(id);
    return !k || pos >= k->len || k->data[pos] == 0;
}
static guint sg_dd_pos_of_choice(int id, int choice) {   /* choice from 1; GTK_INVALID_LIST_POSITION when none */
    guint n = g_list_model_get_n_items(G_LIST_MODEL(sg_dropdown_model(id))), p;
    int c = 0;
    for (p = 0; p < n; p++) if (sg_dd_is_choice(id, p) && ++c == choice) return p;
    return GTK_INVALID_LIST_POSITION;
}
static int sg_dd_choice_of_pos(int id, guint pos) {
    guint p;
    int c = 0;
    if (pos == GTK_INVALID_LIST_POSITION || !sg_dd_is_choice(id, pos)) return 0;
    for (p = 0; p <= pos; p++) if (sg_dd_is_choice(id, p)) c++;
    return c;
}
static void sg_dd_bind(GtkSignalListItemFactory *f, GtkListItem *item, gpointer d) {
    GtkWidget *l = gtk_list_item_get_child(item);
    GtkStringObject *s = gtk_list_item_get_item(item);
    int id = GPOINTER_TO_INT(d);
    guint pos = gtk_list_item_get_position(item);
    GByteArray *k = sg_dd_kinds(id);
    int kind = (k && pos < k->len) ? k->data[pos] : 0;
    (void) f;
    gtk_label_set_text(GTK_LABEL(l), kind == 2 ? "" : gtk_string_object_get_string(s));
    gtk_widget_remove_css_class(l, "heading");
    gtk_widget_remove_css_class(l, "sg-dd-separator");
    if (kind == 1) gtk_widget_add_css_class(l, "heading");
    if (kind == 2) gtk_widget_add_css_class(l, "sg-dd-separator");
    gtk_list_item_set_selectable(item, kind == 0);
    gtk_list_item_set_activatable(item, kind == 0);
}
static void sg_dd_setup(GtkSignalListItemFactory *f, GtkListItem *item, gpointer d) {
    GtkWidget *l = gtk_label_new("");
    (void) f; (void) d;
    gtk_label_set_xalign(GTK_LABEL(l), 0.0);
    gtk_list_item_set_child(item, l);
}
static void sg_dd_add_other(int id, const char *text, int kind) {
    GByteArray *k = sg_dd_kinds(id);
    guint n = g_list_model_get_n_items(G_LIST_MODEL(sg_dropdown_model(id))), p;
    guint8 zero = 0, kb = (guint8) kind;
    if (!k) {
        GtkListItemFactory *f = gtk_signal_list_item_factory_new();
        GtkCssProvider *css = gtk_css_provider_new();
        k = g_byte_array_new();
        for (p = 0; p < n; p++) g_byte_array_append(k, &zero, 1);
        g_object_set_data_full(G_OBJECT(sg_w[id]), "sg-dd-kinds", k, (GDestroyNotify) g_byte_array_unref);
        g_signal_connect(f, "setup", G_CALLBACK(sg_dd_setup), NULL);
        g_signal_connect(f, "bind", G_CALLBACK(sg_dd_bind), GINT_TO_POINTER(id));
        gtk_drop_down_set_list_factory(GTK_DROP_DOWN(sg_w[id]), f);
        g_object_unref(f);
        gtk_css_provider_load_from_string(css, "label.sg-dd-separator { min-height: 1px; border-top: 1px solid alpha(currentColor, 0.2); margin: 3px 0; }");
        gtk_style_context_add_provider_for_display(gdk_display_get_default(), GTK_STYLE_PROVIDER(css), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
        g_object_unref(css);
    }
    while (k->len < n) g_byte_array_append(k, &zero, 1);   /* the choices added since */
    g_byte_array_append(k, &kb, 1);
    sg_quiet++;
    gtk_string_list_append(sg_dropdown_model(id), text);
    sg_quiet--;
}
static void sg_dropdown_add_header(int id, const char *text) { sg_dd_add_other(id, text, 1); }
static void sg_dropdown_add_separator(int id) { sg_dd_add_other(id, "", 2); }

/* Date and time picker (53) and month picker (54): "sg-date" y*10000+m*100+d, "sg-time" h*60+m. */
static void sg_dt_show(int id) {
    int v = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-date"));
    GtkWidget *b = g_object_get_data(G_OBJECT(sg_w[id]), "sg-dt-day");
    if (b && v > 0) {
        GDateTime *dt = g_date_time_new_local(v / 10000, v / 100 % 100, v % 100, 0, 0, 0);
        if (dt) {
            gchar *s = g_date_time_format(dt, "%x");
            gtk_menu_button_set_label(GTK_MENU_BUTTON(b), s);
            g_free(s);
            g_date_time_unref(dt);
        }
    }
}
static void sg_dt_report(int id) {
    int date = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-date"));
    if (sg_kind[id] == 54) sg_push(2, id, date / 100, 0);
    else sg_push(2, id, date, GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-time")));
}
static void sg_dt_put(int id, int date, int time) {   /* quietly, into every part */
    GtkWidget *w = sg_w[id];
    g_object_set_data(G_OBJECT(w), "sg-date", GINT_TO_POINTER(date));
    g_object_set_data(G_OBJECT(w), "sg-time", GINT_TO_POINTER(time));
    sg_quiet++;
    if (sg_kind[id] == 54) {
        gtk_drop_down_set_selected(GTK_DROP_DOWN(g_object_get_data(G_OBJECT(w), "sg-dt-month")), (guint) (date / 100 % 100 - 1));
        gtk_spin_button_set_value(GTK_SPIN_BUTTON(g_object_get_data(G_OBJECT(w), "sg-dt-year")), date / 10000);
    } else {
        GDateTime *dt = g_date_time_new_local(date / 10000, date / 100 % 100, date % 100, 0, 0, 0);
        if (dt) { gtk_calendar_select_day(GTK_CALENDAR(g_object_get_data(G_OBJECT(w), "sg-dt-cal")), dt); g_date_time_unref(dt); }
        gtk_spin_button_set_value(GTK_SPIN_BUTTON(g_object_get_data(G_OBJECT(w), "sg-dt-hour")), time / 60);
        gtk_spin_button_set_value(GTK_SPIN_BUTTON(g_object_get_data(G_OBJECT(w), "sg-dt-minute")), time % 60);
        sg_dt_show(id);
    }
    sg_quiet--;
}
static void sg_on_dt_day(GtkCalendar *cal, gpointer d) {
    int id = GPOINTER_TO_INT(d);
    GDateTime *dt;
    if (sg_quiet) return;
    dt = gtk_calendar_get_date(cal);
    g_object_set_data(G_OBJECT(sg_w[id]), "sg-date", GINT_TO_POINTER(g_date_time_get_year(dt) * 10000
        + g_date_time_get_month(dt) * 100 + g_date_time_get_day_of_month(dt)));
    g_date_time_unref(dt);
    sg_dt_show(id);
    gtk_menu_button_popdown(GTK_MENU_BUTTON(g_object_get_data(G_OBJECT(sg_w[id]), "sg-dt-day")));
    sg_dt_report(id);
}
static void sg_on_dt_time(GtkSpinButton *s, gpointer d) {
    int id = GPOINTER_TO_INT(d);
    GtkWidget *w = sg_w[id];
    (void) s;
    if (sg_quiet) return;
    g_object_set_data(G_OBJECT(w), "sg-time", GINT_TO_POINTER(
        gtk_spin_button_get_value_as_int(GTK_SPIN_BUTTON(g_object_get_data(G_OBJECT(w), "sg-dt-hour"))) * 60
        + gtk_spin_button_get_value_as_int(GTK_SPIN_BUTTON(g_object_get_data(G_OBJECT(w), "sg-dt-minute")))));
    sg_dt_report(id);
}
static void sg_on_dt_month(GObject *o, GParamSpec *p, gpointer d) {
    int id = GPOINTER_TO_INT(d);
    GtkWidget *w = sg_w[id];
    int y, m;
    (void) o; (void) p;
    if (sg_quiet) return;
    m = (int) gtk_drop_down_get_selected(GTK_DROP_DOWN(g_object_get_data(G_OBJECT(w), "sg-dt-month"))) + 1;
    y = gtk_spin_button_get_value_as_int(GTK_SPIN_BUTTON(g_object_get_data(G_OBJECT(w), "sg-dt-year")));
    g_object_set_data(G_OBJECT(w), "sg-date", GINT_TO_POINTER(y * 10000 + m * 100 + 1));
    sg_dt_report(id);
}
static void sg_on_dt_year(GtkSpinButton *s, gpointer d) { (void) s; sg_on_dt_month(NULL, NULL, d); }
static int sg_date_time_picker(int kind) {
    GDateTime *now = g_date_time_new_now_local();
    int date = g_date_time_get_year(now) * 10000 + g_date_time_get_month(now) * 100 + g_date_time_get_day_of_month(now);
    int time = g_date_time_get_hour(now) * 60 + g_date_time_get_minute(now);
    GtkWidget *box = g_object_new(GTK_TYPE_BOX, "orientation", GTK_ORIENTATION_HORIZONTAL, "spacing", 6,
                                  "accessible-role", GTK_ACCESSIBLE_ROLE_GROUP, NULL);
    int id = sg_reg(box, kind == 3 ? 54 : 53);
    g_date_time_unref(now);
    gtk_widget_set_halign(box, GTK_ALIGN_START);
    if (kind == 3) {
        const char *months[13];
        gchar *names[12];
        GtkWidget *dd, *year = gtk_spin_button_new_with_range(1, 9999, 1);
        int i;
        for (i = 0; i < 12; i++) {
            GDateTime *dt = g_date_time_new_local(2001, i + 1, 1, 0, 0, 0);
            names[i] = g_date_time_format(dt, "%B");
            months[i] = names[i];
            g_date_time_unref(dt);
        }
        months[12] = NULL;
        dd = gtk_drop_down_new_from_strings(months);
        for (i = 0; i < 12; i++) g_free(names[i]);
        gtk_accessible_update_property(GTK_ACCESSIBLE(dd), GTK_ACCESSIBLE_PROPERTY_LABEL, "Month", -1); g_object_set_data_full(G_OBJECT(dd), "sg-a11y", g_strdup("Month"), g_free);
        gtk_accessible_update_property(GTK_ACCESSIBLE(year), GTK_ACCESSIBLE_PROPERTY_LABEL, "Year", -1); g_object_set_data_full(G_OBJECT(year), "sg-a11y", g_strdup("Year"), g_free);
        gtk_box_append(GTK_BOX(box), dd);
        gtk_box_append(GTK_BOX(box), year);
        g_object_set_data(G_OBJECT(box), "sg-dt-month", dd);
        g_object_set_data(G_OBJECT(box), "sg-dt-year", year);
        g_signal_connect(dd, "notify::selected", G_CALLBACK(sg_on_dt_month), GINT_TO_POINTER(id));
        g_signal_connect(year, "value-changed", G_CALLBACK(sg_on_dt_year), GINT_TO_POINTER(id));
        sg_dt_put(id, date / 100 * 100 + 1, 0);
    } else {
        GtkWidget *day = g_object_new(GTK_TYPE_MENU_BUTTON, "accessible-role", GTK_ACCESSIBLE_ROLE_COMBO_BOX, NULL);
        GtkWidget *pop = gtk_popover_new(), *cal = gtk_calendar_new();
        GtkWidget *hs = gtk_spin_button_new_with_range(0, 23, 1), *ms = gtk_spin_button_new_with_range(0, 59, 1);
        gtk_popover_set_child(GTK_POPOVER(pop), cal);
        gtk_menu_button_set_popover(GTK_MENU_BUTTON(day), pop);
        gtk_accessible_update_property(GTK_ACCESSIBLE(day), GTK_ACCESSIBLE_PROPERTY_LABEL, "Date", -1); g_object_set_data_full(G_OBJECT(day), "sg-a11y", g_strdup("Date"), g_free);
        gtk_accessible_update_property(GTK_ACCESSIBLE(hs), GTK_ACCESSIBLE_PROPERTY_LABEL, "Hour", -1); g_object_set_data_full(G_OBJECT(hs), "sg-a11y", g_strdup("Hour"), g_free);
        gtk_accessible_update_property(GTK_ACCESSIBLE(ms), GTK_ACCESSIBLE_PROPERTY_LABEL, "Minute", -1); g_object_set_data_full(G_OBJECT(ms), "sg-a11y", g_strdup("Minute"), g_free);
        gtk_spin_button_set_wrap(GTK_SPIN_BUTTON(hs), TRUE);
        gtk_spin_button_set_wrap(GTK_SPIN_BUTTON(ms), TRUE);
        gtk_editable_set_width_chars(GTK_EDITABLE(hs), 2);
        gtk_editable_set_width_chars(GTK_EDITABLE(ms), 2);
        g_signal_connect(hs, "output", G_CALLBACK(sg_two_digits), NULL);
        g_signal_connect(ms, "output", G_CALLBACK(sg_two_digits), NULL);
        gtk_box_append(GTK_BOX(box), day);
        gtk_box_append(GTK_BOX(box), hs);
        gtk_box_append(GTK_BOX(box), gtk_label_new(":"));
        gtk_box_append(GTK_BOX(box), ms);
        g_object_set_data(G_OBJECT(box), "sg-dt-day", day);
        g_object_set_data(G_OBJECT(box), "sg-dt-cal", cal);
        g_object_set_data(G_OBJECT(box), "sg-dt-hour", hs);
        g_object_set_data(G_OBJECT(box), "sg-dt-minute", ms);
        g_signal_connect(cal, "day-selected", G_CALLBACK(sg_on_dt_day), GINT_TO_POINTER(id));
        g_signal_connect(hs, "value-changed", G_CALLBACK(sg_on_dt_time), GINT_TO_POINTER(id));
        g_signal_connect(ms, "value-changed", G_CALLBACK(sg_on_dt_time), GINT_TO_POINTER(id));
        sg_dt_put(id, date, time);
    }
    return id;
}
static void sg_date_time_set(int id, int date, int time) { sg_dt_put(id, date, time); }
static int sg_date_time_date(int id) { return GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-date")); }
static int sg_date_time_time(int id) { return GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), "sg-time")); }
static void sg_test_set_date_time(int id, int date, int time) {
    sg_dt_put(id, sg_kind[id] == 54 ? date / 100 * 100 + 1 : date, time);
    sg_dt_report(id);
}

/* Range slider (55): two scales, Low over High, kept in order; a user's change sends 2. */
static int sg_range_part(int id, const char *which) {
    return gtk_range_get_value(GTK_RANGE(g_object_get_data(G_OBJECT(sg_w[id]), which))) + 0.5;
}
static void sg_on_range(GtkRange *r, gpointer d) {
    int id = GPOINTER_TO_INT(d), step, low, high;
    GtkWidget *w = sg_w[id];
    GtkRange *lo = g_object_get_data(G_OBJECT(w), "sg-range-low"), *hi = g_object_get_data(G_OBJECT(w), "sg-range-high");
    if (sg_quiet) return;
    step = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(w), "sg-step"));
    sg_quiet++;
    if (step > 1) {
        double v = gtk_range_get_value(r), base = gtk_adjustment_get_lower(gtk_range_get_adjustment(r));
        gtk_range_set_value(r, base + step * floor((v - base) / step + 0.5));
    }
    if (gtk_range_get_value(lo) > gtk_range_get_value(hi)) {
        if (r == lo) gtk_range_set_value(lo, gtk_range_get_value(hi));
        else gtk_range_set_value(hi, gtk_range_get_value(lo));
    }
    sg_quiet--;
    low = sg_range_part(id, "sg-range-low");
    high = sg_range_part(id, "sg-range-high");
    if (low == GPOINTER_TO_INT(g_object_get_data(G_OBJECT(w), "sg-range-was-low"))
        && high == GPOINTER_TO_INT(g_object_get_data(G_OBJECT(w), "sg-range-was-high"))) return;
    g_object_set_data(G_OBJECT(w), "sg-range-was-low", GINT_TO_POINTER(low));
    g_object_set_data(G_OBJECT(w), "sg-range-was-high", GINT_TO_POINTER(high));
    sg_push(2, id, low, high);
}
static int sg_range_slider(int lo, int hi) {
    GtkWidget *box = g_object_new(GTK_TYPE_BOX, "orientation", GTK_ORIENTATION_VERTICAL, "spacing", 0,
                                  "accessible-role", GTK_ACCESSIBLE_ROLE_GROUP, NULL);
    GtkWidget *low = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, lo, hi, 1);
    GtkWidget *high = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, lo, hi, 1);
    int id = sg_reg(box, 55);
    GtkWidget *parts[2];
    int i;
    parts[0] = low; parts[1] = high;
    for (i = 0; i < 2; i++) {
        gtk_scale_set_digits(GTK_SCALE(parts[i]), 0);
        gtk_scale_set_draw_value(GTK_SCALE(parts[i]), TRUE);
        gtk_scale_set_value_pos(GTK_SCALE(parts[i]), GTK_POS_LEFT);
        gtk_range_set_round_digits(GTK_RANGE(parts[i]), 0);
        gtk_widget_set_hexpand(parts[i], TRUE);
        gtk_box_append(GTK_BOX(box), parts[i]);
        g_signal_connect(parts[i], "value-changed", G_CALLBACK(sg_on_range), GINT_TO_POINTER(id));
    }
    gtk_accessible_update_property(GTK_ACCESSIBLE(low), GTK_ACCESSIBLE_PROPERTY_LABEL, "Minimum", -1); g_object_set_data_full(G_OBJECT(low), "sg-a11y", g_strdup("Minimum"), g_free);
    gtk_accessible_update_property(GTK_ACCESSIBLE(high), GTK_ACCESSIBLE_PROPERTY_LABEL, "Maximum", -1); g_object_set_data_full(G_OBJECT(high), "sg-a11y", g_strdup("Maximum"), g_free);
    gtk_widget_set_hexpand(box, TRUE);
    g_object_set_data(G_OBJECT(box), "sg-range-low", low);
    g_object_set_data(G_OBJECT(box), "sg-range-high", high);
    sg_quiet++;
    gtk_range_set_value(GTK_RANGE(low), lo);
    gtk_range_set_value(GTK_RANGE(high), hi);
    sg_quiet--;
    g_object_set_data(G_OBJECT(box), "sg-range-was-low", GINT_TO_POINTER(lo));
    g_object_set_data(G_OBJECT(box), "sg-range-was-high", GINT_TO_POINTER(hi));
    return id;
}
static void sg_range_slider_set(int id, int low, int high) {
    GtkWidget *w = sg_w[id];
    sg_quiet++;
    gtk_range_set_value(GTK_RANGE(g_object_get_data(G_OBJECT(w), "sg-range-low")), low);
    gtk_range_set_value(GTK_RANGE(g_object_get_data(G_OBJECT(w), "sg-range-high")), high);
    sg_quiet--;
    g_object_set_data(G_OBJECT(w), "sg-range-was-low", GINT_TO_POINTER(low));
    g_object_set_data(G_OBJECT(w), "sg-range-was-high", GINT_TO_POINTER(high));
}
static int sg_range_slider_low(int id) { return sg_range_part(id, "sg-range-low"); }
static int sg_range_slider_high(int id) { return sg_range_part(id, "sg-range-high"); }
static void sg_range_slider_set_step(int id, int step) {
    GtkWidget *w = sg_w[id];
    g_object_set_data(G_OBJECT(w), "sg-step", GINT_TO_POINTER(step));
    gtk_range_set_increments(GTK_RANGE(g_object_get_data(G_OBJECT(w), "sg-range-low")), step, step * 10.0);
    gtk_range_set_increments(GTK_RANGE(g_object_get_data(G_OBJECT(w), "sg-range-high")), step, step * 10.0);
}
static void sg_test_slide_range(int id, int low, int high) {
    GtkWidget *w = sg_w[id];
    gtk_range_set_value(GTK_RANGE(g_object_get_data(G_OBJECT(w), "sg-range-low")), low);
    gtk_range_set_value(GTK_RANGE(g_object_get_data(G_OBJECT(w), "sg-range-high")), high);
}

/* Several rows at once: selected-rows-changed reports the first selected row (4). */
static void sg_on_rows(GtkListBox *l, gpointer d) {
    GtkListBoxRow *first = NULL;
    GList *rows, *it;
    (void) d;
    if (sg_quiet) return;
    rows = gtk_list_box_get_selected_rows(l);
    for (it = rows; it; it = it->next)
        if (!first || gtk_list_box_row_get_index(it->data) < gtk_list_box_row_get_index(first)) first = it->data;
    g_list_free(rows);
    sg_push(4, sg_id_of(l), first ? gtk_list_box_row_get_index(first) + 1 : 0, 0);
}
static void sg_list_set_multiple(int id, int on) {
    GtkListBox *l = sg_list_box(id);
    if (!g_object_get_data(G_OBJECT(l), "sg-rows-hooked")) {
        g_signal_connect(l, "selected-rows-changed", G_CALLBACK(sg_on_rows), NULL);
        g_signal_handlers_block_by_func(l, sg_on_rows, NULL);
        g_object_set_data(G_OBJECT(l), "sg-rows-hooked", GINT_TO_POINTER(1));
    }
    if (on && !g_object_get_data(G_OBJECT(l), "sg-multiple")) {
        gtk_list_box_set_selection_mode(l, GTK_SELECTION_MULTIPLE);
        sg_quiet++;
        gtk_list_box_unselect_all(l);
        sg_quiet--;
        g_signal_handlers_block_by_func(l, sg_on_row, NULL);
        g_signal_handlers_unblock_by_func(l, sg_on_rows, NULL);
        g_object_set_data(G_OBJECT(l), "sg-multiple", GINT_TO_POINTER(1));
    } else if (!on && g_object_get_data(G_OBJECT(l), "sg-multiple")) {
        sg_quiet++;
        gtk_list_box_set_selection_mode(l, GTK_SELECTION_SINGLE);
        sg_quiet--;
        g_signal_handlers_block_by_func(l, sg_on_rows, NULL);
        g_signal_handlers_unblock_by_func(l, sg_on_row, NULL);
        g_object_set_data(G_OBJECT(l), "sg-multiple", NULL);
    }
}
static gint sg_by_index(gconstpointer a, gconstpointer b) {
    return gtk_list_box_row_get_index((GtkListBoxRow *) a) - gtk_list_box_row_get_index((GtkListBoxRow *) b);
}
static int sg_list_selected_count(int id) {
    GList *rows = gtk_list_box_get_selected_rows(sg_list_box(id));
    int n = (int) g_list_length(rows);
    g_list_free(rows);
    return n;
}
static int sg_list_selected_at(int id, int i) {
    GList *rows = g_list_sort(gtk_list_box_get_selected_rows(sg_list_box(id)), sg_by_index);
    GtkListBoxRow *r = g_list_nth_data(rows, (guint) (i - 1));
    int v = r ? gtk_list_box_row_get_index(r) + 1 : 0;
    g_list_free(rows);
    return v;
}
static void sg_test_extend_list_selection(int id, int row) {
    GtkListBoxRow *r = gtk_list_box_get_row_at_index(sg_list_box(id), row - 1);
    if (r) gtk_list_box_select_row(sg_list_box(id), r);
}

/* ---------- 1q-a: pick and drop. A pick start pushes 30 (source, row); Eiffel answers with
   sg_pick_targets (the widgets that take the pebble, and their labels) or sg_pick_cancel. Only
   those targets light (CSS sg-drop-ok) and take a drop, which pushes 31 (target, row); a cancel
   pushes 32. Nothing here calls into Eiffel. Modes: 1 drag (GtkDragSource / GtkDropTarget,
   the content a token, the pebble stays in Eiffel), 2 click (a secondary click picks, a line in
   the window overlay follows the pointer, the next click drops), 3 menu (a popover of the
   targets). ---------- */
__attribute__((weak)) unsigned char sg_pick_ok[SG_MAX] = {0};
__attribute__((weak)) int sg_pick_on = 0, sg_pick_source = 0, sg_pick_mode = 0;
__attribute__((weak)) double sg_pick_x0 = 0, sg_pick_y0 = 0, sg_pick_x1 = 0, sg_pick_y1 = 0;
__attribute__((weak)) GtkWidget *sg_pick_window = NULL;
__attribute__((weak)) GtkWidget *sg_pick_menu = NULL;
__attribute__((weak)) GdkDrag *sg_pick_drag = NULL;
__attribute__((weak)) int sg_pick_css_done = 0;

/* The widget that takes the gestures: a list's GtkListBox, else the registered widget. */
static GtkWidget *sg_pick_widget(int id) {
    GtkWidget *l = g_object_get_data(G_OBJECT(sg_w[id]), "sg-list");
    return l ? l : sg_w[id];
}
/* The row (from 1) of widget `id' at (x, y) in sg_pick_widget's coordinates; 0 for none. */
static int sg_pick_row_at(int id, double x, double y) {
    GtkWidget *l = g_object_get_data(G_OBJECT(sg_w[id]), "sg-list");
    GtkListBoxRow *r;
    (void) x;
    if (l && (r = gtk_list_box_get_row_at_y(GTK_LIST_BOX(l), (int) y))) return gtk_list_box_row_get_index(r) + 1;
    return 0;
}
static void sg_pick_css(void) {
    GtkCssProvider *p;
    if (sg_pick_css_done) return;
    sg_pick_css_done = 1;
    p = gtk_css_provider_new();
    gtk_css_provider_load_from_string(p,
        ".sg-drop-ok { outline: 2px dashed #3584e4; outline-offset: -2px; }"
        " .sg-drop-hover { outline: 2px solid #3584e4; outline-offset: -2px; background-color: rgba(53,132,228,0.10); }");
    gtk_style_context_add_provider_for_display(gdk_display_get_default(), GTK_STYLE_PROVIDER(p),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(p);
}
/* Back to rest: no target lit, no line, no menu. */
static void sg_pick_clear(void) {
    int i;
    for (i = 1; i < SG_MAX; i++) {
        if (sg_pick_ok[i]) {
            sg_pick_ok[i] = 0;
            if (sg_w[i]) {
                gtk_widget_remove_css_class(sg_pick_widget(i), "sg-drop-ok");
                gtk_widget_remove_css_class(sg_pick_widget(i), "sg-drop-hover");
            }
        }
    }
    if (sg_pick_window) {
        GtkWidget *line = g_object_get_data(G_OBJECT(sg_pick_window), "sg-pick-line");
        if (line) gtk_widget_set_visible(line, FALSE);
    }
    if (sg_pick_menu) {
        GtkWidget *m = sg_pick_menu;
        sg_pick_menu = NULL;
        gtk_popover_popdown(GTK_POPOVER(m));
    }
    sg_pick_on = 0;
    sg_pick_source = 0;
    sg_pick_drag = NULL;
}
/* The registered widget (and row) under window point (x, y), if it takes the pebble; 0 if none. */
static int sg_pick_target_at(GtkWidget *win, double x, double y, int *row) {
    GtkWidget *w = gtk_widget_pick(win, x, y, GTK_PICK_DEFAULT);
    *row = 0;
    for (; w; w = gtk_widget_get_parent(w)) {
        int id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(w), "sg-id"));
        if (id > 0 && id < SG_MAX && sg_pick_ok[id]) {
            graphene_point_t p = GRAPHENE_POINT_INIT((float) x, (float) y), q;
            if (gtk_widget_compute_point(win, sg_pick_widget(id), &p, &q)) *row = sg_pick_row_at(id, q.x, q.y);
            return id;
        }
    }
    return 0;
}
static void sg_pick_start(int id, int row, int mode) {
    sg_pick_clear();
    sg_pick_css();
    sg_pick_on = 1;
    sg_pick_source = id;
    sg_pick_mode = mode;
    sg_push(30, id, row, 0);
}

/* --- click mode: the line, and the window's next click --- */
static void sg_pick_line_draw(GtkDrawingArea *a, cairo_t *cr, int w, int h, gpointer d) {
    (void) a; (void) w; (void) h; (void) d;
    if (!sg_pick_on) return;
    cairo_set_source_rgba(cr, 0.21, 0.52, 0.89, 0.9);
    cairo_set_line_width(cr, 2.0);
    cairo_move_to(cr, sg_pick_x0, sg_pick_y0);
    cairo_line_to(cr, sg_pick_x1, sg_pick_y1);
    cairo_stroke(cr);
    cairo_arc(cr, sg_pick_x0, sg_pick_y0, 4.0, 0, 2 * G_PI);
    cairo_fill(cr);
}
static void sg_pick_on_motion(GtkEventControllerMotion *c, double x, double y, gpointer d) {
    GtkWidget *line = d;
    (void) c;
    if (sg_pick_on && sg_pick_mode == 2) {
        sg_pick_x1 = x; sg_pick_y1 = y;
        gtk_widget_queue_draw(line);
    }
}
static void sg_pick_on_window_press(GtkGestureClick *g, int n, double x, double y, gpointer d) {
    GtkWidget *win = d;
    int target, row;
    (void) n;
    if (!sg_pick_on || sg_pick_mode != 2 || win != sg_pick_window) return;
    if (gtk_gesture_single_get_current_button(GTK_GESTURE_SINGLE(g)) == GDK_BUTTON_PRIMARY
        && (target = sg_pick_target_at(win, x, y, &row)) > 0) {
        sg_push(31, target, row, 0);
    } else {
        sg_push(32, sg_pick_source, 0, 0);
    }
    gtk_gesture_set_state(GTK_GESTURE(g), GTK_EVENT_SEQUENCE_CLAIMED);
    sg_pick_clear();
}
static gboolean sg_pick_on_key(GtkEventControllerKey *k, guint keyval, guint code, GdkModifierType m, gpointer d) {
    (void) k; (void) code; (void) m; (void) d;
    if (sg_pick_on && keyval == GDK_KEY_Escape) {
        sg_push(32, sg_pick_source, 0, 0);
        sg_pick_clear();
        return TRUE;
    }
    return FALSE;
}
/* The window a click-mode pick runs in: a line over its content, and its gestures (made once). */
static void sg_pick_hook_window(GtkWidget *win) {
    GtkOverlay *o = g_object_get_data(G_OBJECT(win), "sg-overlay");
    GtkWidget *line;
    GtkGesture *g;
    GtkEventController *c;
    if (!o || g_object_get_data(G_OBJECT(win), "sg-pick-line")) return;
    line = gtk_drawing_area_new();
    gtk_widget_set_can_target(line, FALSE);
    gtk_widget_set_halign(line, GTK_ALIGN_FILL);
    gtk_widget_set_valign(line, GTK_ALIGN_FILL);
    gtk_drawing_area_set_draw_func(GTK_DRAWING_AREA(line), sg_pick_line_draw, NULL, NULL);
    gtk_widget_set_visible(line, FALSE);
    gtk_overlay_add_overlay(o, line);
    g_object_set_data(G_OBJECT(win), "sg-pick-line", line);
    g = gtk_gesture_click_new();
    gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(g), 0);
    gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(g), GTK_PHASE_CAPTURE);
    g_signal_connect(g, "pressed", G_CALLBACK(sg_pick_on_window_press), win);
    gtk_widget_add_controller(win, GTK_EVENT_CONTROLLER(g));
    c = gtk_event_controller_motion_new();
    g_signal_connect(c, "motion", G_CALLBACK(sg_pick_on_motion), line);
    gtk_widget_add_controller(win, c);
    c = gtk_event_controller_key_new();
    gtk_event_controller_set_propagation_phase(c, GTK_PHASE_CAPTURE);
    g_signal_connect(c, "key-pressed", G_CALLBACK(sg_pick_on_key), NULL);
    gtk_widget_add_controller(win, c);
}
/* A secondary click on a click- or menu-mode source starts the pick (before any context menu). */
static void sg_pick_on_secondary(GtkGestureClick *g, int n, double x, double y, gpointer d) {
    int id = GPOINTER_TO_INT(d), mode;
    GtkWidget *src = sg_w[id], *win;
    (void) n;
    if (!src || !GPOINTER_TO_INT(g_object_get_data(G_OBJECT(src), "sg-pick-src"))) return;
    mode = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(src), "sg-pick-mode"));
    if (mode != 2 && mode != 3) return;
    if (sg_pick_on) return;   /* the window's press handler takes the second click */
    gtk_gesture_set_state(GTK_GESTURE(g), GTK_EVENT_SEQUENCE_CLAIMED);
    win = GTK_WIDGET(gtk_widget_get_root(src));
    sg_pick_start(id, GPOINTER_TO_INT(g_object_get_data(G_OBJECT(src), "sg-pick-row")) ? sg_pick_row_at(id, x, y) : 0, mode);
    sg_pick_window = win;
    {
        graphene_point_t p = GRAPHENE_POINT_INIT((float) x, (float) y), q;
        if (win && gtk_widget_compute_point(sg_pick_widget(id), win, &p, &q)) {
            sg_pick_x0 = sg_pick_x1 = q.x; sg_pick_y0 = sg_pick_y1 = q.y;
        }
    }
    g_object_set_data(G_OBJECT(src), "sg-pick-at-x", GINT_TO_POINTER((int) x));
    g_object_set_data(G_OBJECT(src), "sg-pick-at-y", GINT_TO_POINTER((int) y));
}

/* 1q-c: what a drag out of the widget carries ("sg-drag-text", "sg-drag-paths" newline-separated),
   kept current by the program. A drop on one of our own widgets sets sg_drag_inside, so the drag's
   end pushes 34 (source, a = 1 copied, 0 refused) only for a drag that left for another program. */
__attribute__((weak)) int sg_drag_inside = 0, sg_drag_canceled = 0;
static const char *sg_drag_str(int id, const char *key) {
    const char *s = sg_w[id] ? g_object_get_data(G_OBJECT(sg_w[id]), key) : NULL;
    return s ? s : "";
}
static int sg_has_drag_out(int id) { return *sg_drag_str(id, "sg-drag-text") || *sg_drag_str(id, "sg-drag-paths"); }
static GdkContentProvider *sg_drag_out_content(int id) {
    const char *t = sg_drag_str(id, "sg-drag-text"), *p = sg_drag_str(id, "sg-drag-paths");
    GdkContentProvider *parts[2];
    int n = 0;
    if (*p) {
        GSList *files = NULL;
        char **lines = g_strsplit(p, "\n", -1), **it;
        for (it = lines; *it; it++) if (**it) files = g_slist_append(files, g_file_new_for_path(*it));
        g_strfreev(lines);
        if (files) {
            parts[n++] = gdk_content_provider_new_typed(GDK_TYPE_FILE_LIST, files);
            g_slist_free_full(files, g_object_unref);
        }
    }
    if (*t) parts[n++] = gdk_content_provider_new_typed(G_TYPE_STRING, t);
    if (n == 0) return NULL;
    if (n == 1) return parts[0];
    return gdk_content_provider_new_union(parts, 2);
}

/* --- drag mode (and 1q-c drags out: one GtkDragSource serves both) --- */
static GdkContentProvider *sg_pick_on_prepare(GtkDragSource *s, double x, double y, gpointer d) {
    int id = GPOINTER_TO_INT(d), pick;
    GtkWidget *src = sg_w[id];
    (void) s;
    if (!src) return NULL;
    pick = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(src), "sg-pick-src"))
        && GPOINTER_TO_INT(g_object_get_data(G_OBJECT(src), "sg-pick-mode")) == 1;
    if (!pick && !sg_has_drag_out(id)) return NULL;
    sg_drag_inside = 0; sg_drag_canceled = 0;
    if (pick) {
        sg_pick_start(id, GPOINTER_TO_INT(g_object_get_data(G_OBJECT(src), "sg-pick-row")) ? sg_pick_row_at(id, x, y) : 0, 1);
        sg_pick_window = GTK_WIDGET(gtk_widget_get_root(src));
    }
    /* With data to drag out, the drag carries it: our own targets take the pebble while the
       pick is on and ignore the content; another program gets the data. */
    if (sg_has_drag_out(id)) return sg_drag_out_content(id);
    return gdk_content_provider_new_typed(G_TYPE_STRING, "sg-pebble");
}
static void sg_pick_on_drag_begin(GtkDragSource *s, GdkDrag *drag, gpointer d) {
    (void) s; (void) d;
    sg_pick_drag = drag;
}
static gboolean sg_drag_on_cancel(GtkDragSource *s, GdkDrag *drag, GdkDragCancelReason r, gpointer d) {
    (void) s; (void) drag; (void) r; (void) d;
    sg_drag_canceled = 1;
    return FALSE;
}
static void sg_pick_on_drag_end(GtkDragSource *s, GdkDrag *drag, gboolean del, gpointer d) {
    int id = GPOINTER_TO_INT(d);
    (void) s; (void) drag;
    if (sg_pick_on && sg_pick_mode == 1) {   /* not taken by one of our targets */
        sg_push(32, sg_pick_source, 0, 0);
        sg_pick_clear();
    }
    if (!sg_drag_inside && sg_has_drag_out(id)) sg_push(34, id, sg_drag_canceled ? 0 : (del ? 2 : 1), 0);
}
static void sg_drag_source_hook(int id) {
    GtkWidget *w = sg_w[id];
    GtkDragSource *s;
    if (g_object_get_data(G_OBJECT(w), "sg-drag-hooked")) return;
    s = gtk_drag_source_new();
    gtk_drag_source_set_actions(s, GDK_ACTION_COPY);
    g_signal_connect(s, "prepare", G_CALLBACK(sg_pick_on_prepare), GINT_TO_POINTER(id));
    g_signal_connect(s, "drag-begin", G_CALLBACK(sg_pick_on_drag_begin), NULL);
    g_signal_connect(s, "drag-cancel", G_CALLBACK(sg_drag_on_cancel), NULL);
    g_signal_connect(s, "drag-end", G_CALLBACK(sg_pick_on_drag_end), GINT_TO_POINTER(id));
    gtk_widget_add_controller(sg_pick_widget(id), GTK_EVENT_CONTROLLER(s));
    g_object_set_data(G_OBJECT(w), "sg-drag-hooked", GINT_TO_POINTER(1));
}
static void sg_widget_set_drag_out(int id, const char *text, const char *paths) {
    GtkWidget *w = sg_w[id];
    if (!w) return;
    g_object_set_data_full(G_OBJECT(w), "sg-drag-text", g_strdup(text), g_free);
    g_object_set_data_full(G_OBJECT(w), "sg-drag-paths", g_strdup(paths), g_free);
    if (*text || *paths) sg_drag_source_hook(id);
}
/* What a drag out of `id' would carry now: text, a line feed, the paths; "" for nothing. */
static const char *sg_test_drag_out(int id) {
    if (!sg_has_drag_out(id)) return "";
    g_object_set_data_full(G_OBJECT(sg_w[id]), "sg-drag-shown",
        g_strconcat(sg_drag_str(id, "sg-drag-text"), "\n", sg_drag_str(id, "sg-drag-paths"), NULL), g_free);
    return g_object_get_data(G_OBJECT(sg_w[id]), "sg-drag-shown");
}
static void sg_test_drag_out_ended(int id, int how) { if (sg_has_drag_out(id)) sg_push(34, id, how, 0); }
/* 1q-b: what the widget takes from other programs ("sg-take-files", "sg-take-text"); a string
   that arrives while one of our picks is on is the pick's token, otherwise outside text. */
static int sg_takes(int id, const char *what) { return sg_w[id] && GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[id]), what)); }
static int sg_outside_ok(int id, GdkDrop *drop) {
    GdkContentFormats *f = drop ? gdk_drop_get_formats(drop) : NULL;
    if (!f) return 0;
    return (sg_takes(id, "sg-take-files") && gdk_content_formats_contain_gtype(f, GDK_TYPE_FILE_LIST))
        || (sg_takes(id, "sg-take-text") && gdk_content_formats_contain_gtype(f, G_TYPE_STRING));
}
static gboolean sg_pick_on_accept(GtkDropTarget *t, GdkDrop *drop, gpointer d) {
    int id = GPOINTER_TO_INT(d);
    (void) t;
    if (sg_pick_on) return sg_pick_mode == 1;
    return sg_outside_ok(id, drop);
}
static GdkDragAction sg_pick_on_enter(GtkDropTarget *t, double x, double y, gpointer d) {
    int id = GPOINTER_TO_INT(d);
    (void) x; (void) y;
    if ((sg_pick_on && sg_pick_ok[id]) || (!sg_pick_on && sg_outside_ok(id, gtk_drop_target_get_current_drop(t)))) {
        gtk_widget_add_css_class(sg_pick_widget(id), "sg-drop-hover");
        return GDK_ACTION_COPY;
    }
    return 0;
}
/* Keep what was dropped from outside until the next drop, and tell Eiffel (33, a = 1 files, 2 text). */
static void sg_outside_files(int id, const char *joined) {
    g_object_set_data_full(G_OBJECT(sg_w[id]), "sg-dropped-paths", g_strdup(joined), g_free);
    sg_push(33, id, 1, 0);
}
static void sg_outside_text(int id, const char *text) {
    g_object_set_data_full(G_OBJECT(sg_w[id]), "sg-dropped-text", g_strdup(text), g_free);
    sg_push(33, id, 2, 0);
}
static const char *sg_take_dropped_paths(int id) {
    const char *s = sg_w[id] ? g_object_get_data(G_OBJECT(sg_w[id]), "sg-dropped-paths") : NULL;
    return s ? s : "";
}
static const char *sg_take_dropped_text(int id) {
    const char *s = sg_w[id] ? g_object_get_data(G_OBJECT(sg_w[id]), "sg-dropped-text") : NULL;
    return s ? s : "";
}
static void sg_test_drop_files(int id, const char *joined) { if (sg_takes(id, "sg-take-files")) sg_outside_files(id, joined); }
static void sg_test_drop_text(int id, const char *text) { if (sg_takes(id, "sg-take-text")) sg_outside_text(id, text); }
static void sg_pick_on_leave(GtkDropTarget *t, gpointer d) {
    (void) t;
    gtk_widget_remove_css_class(sg_pick_widget(GPOINTER_TO_INT(d)), "sg-drop-hover");
}
static gboolean sg_pick_on_drop(GtkDropTarget *t, const GValue *v, double x, double y, gpointer d) {
    int id = GPOINTER_TO_INT(d);
    (void) t;
    sg_drag_inside = 1;
    gtk_widget_remove_css_class(sg_pick_widget(id), "sg-drop-hover");
    if (sg_pick_on) {
        if (!sg_pick_ok[id]) return FALSE;
        sg_push(31, id, sg_pick_row_at(id, x, y), 0);
        sg_pick_clear();
        return TRUE;
    }
    if (G_VALUE_HOLDS(v, GDK_TYPE_FILE_LIST) && sg_takes(id, "sg-take-files")) {
        GString *joined = g_string_new(NULL);
        GSList *it;
        for (it = g_value_get_boxed(v); it; it = it->next) {
            char *path = g_file_get_path(G_FILE(it->data));
            if (path) {
                if (joined->len) g_string_append_c(joined, '\n');
                g_string_append(joined, path);
                g_free(path);
            }
        }
        if (joined->len) sg_outside_files(id, joined->str);
        g_string_free(joined, TRUE);
        return TRUE;
    }
    if (G_VALUE_HOLDS(v, G_TYPE_STRING) && sg_takes(id, "sg-take-text")) {
        sg_outside_text(id, g_value_get_string(v));
        return TRUE;
    }
    return FALSE;
}

static void sg_widget_set_pick(int id, int mode, int is_source, int by_row) {
    GtkWidget *w = sg_w[id], *e = sg_pick_widget(id);
    g_object_set_data(G_OBJECT(w), "sg-pick-mode", GINT_TO_POINTER(mode));
    g_object_set_data(G_OBJECT(w), "sg-pick-src", GINT_TO_POINTER(is_source));
    g_object_set_data(G_OBJECT(w), "sg-pick-row", GINT_TO_POINTER(by_row));
    if (is_source && !g_object_get_data(G_OBJECT(w), "sg-pick-hooked")) {
        GtkGesture *g = gtk_gesture_click_new();
        sg_drag_source_hook(id);
        gtk_gesture_single_set_button(GTK_GESTURE_SINGLE(g), GDK_BUTTON_SECONDARY);
        gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(g), GTK_PHASE_CAPTURE);
        g_signal_connect(g, "pressed", G_CALLBACK(sg_pick_on_secondary), GINT_TO_POINTER(id));
        gtk_widget_add_controller(e, GTK_EVENT_CONTROLLER(g));
        g_object_set_data(G_OBJECT(w), "sg-pick-hooked", GINT_TO_POINTER(1));
    }
}
static void sg_widget_set_drop_target(int id, int internal, int files, int text) {
    GtkWidget *w = sg_w[id];
    g_object_set_data(G_OBJECT(w), "sg-take-files", GINT_TO_POINTER(files));
    g_object_set_data(G_OBJECT(w), "sg-take-text", GINT_TO_POINTER(text));
    if ((internal || files || text) && !g_object_get_data(G_OBJECT(w), "sg-drop-hooked")) {
        /* one target for pebbles (a string token), files and text from other programs */
        GtkDropTarget *t = gtk_drop_target_new(G_TYPE_INVALID, GDK_ACTION_COPY);
        GType types[2];
        types[0] = GDK_TYPE_FILE_LIST; types[1] = G_TYPE_STRING;
        gtk_drop_target_set_gtypes(t, types, 2);
        g_signal_connect(t, "accept", G_CALLBACK(sg_pick_on_accept), GINT_TO_POINTER(id));
        g_signal_connect(t, "enter", G_CALLBACK(sg_pick_on_enter), GINT_TO_POINTER(id));
        g_signal_connect(t, "motion", G_CALLBACK(sg_pick_on_enter), GINT_TO_POINTER(id));
        g_signal_connect(t, "leave", G_CALLBACK(sg_pick_on_leave), GINT_TO_POINTER(id));
        g_signal_connect(t, "drop", G_CALLBACK(sg_pick_on_drop), GINT_TO_POINTER(id));
        gtk_widget_add_controller(sg_pick_widget(id), GTK_EVENT_CONTROLLER(t));
        g_object_set_data(G_OBJECT(w), "sg-drop-hooked", GINT_TO_POINTER(1));
    }
}

/* --- menu mode --- */
static void sg_pick_on_menu_choice(GtkButton *b, gpointer d) {
    int target = GPOINTER_TO_INT(d);
    (void) b;
    if (sg_pick_on) {
        sg_push(31, target, 0, 0);
        sg_pick_clear();
    }
}
static gboolean sg_pick_unparent_later(gpointer d) {
    gtk_widget_unparent(GTK_WIDGET(d));
    g_object_unref(d);
    return G_SOURCE_REMOVE;
}
static void sg_pick_on_menu_closed(GtkPopover *p, gpointer d) {
    (void) d;
    if (sg_pick_menu == GTK_WIDGET(p) && sg_pick_on) {   /* closed with no choice */
        sg_pick_menu = NULL;
        sg_push(32, sg_pick_source, 0, 0);
        sg_pick_clear();
    }
    /* not inside its own `closed': GTK still uses the popover after the signal */
    g_idle_add(sg_pick_unparent_later, g_object_ref(p));
}
static void sg_pick_show_menu(int count, const int *ids, const char *labels) {
    GtkWidget *src = sg_pick_widget(sg_pick_source), *pop = gtk_popover_new(),
              *box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2);
    gchar **names = g_strsplit(labels ? labels : "", "\n", -1);
    GdkRectangle at;
    int i;
    for (i = 0; i < count; i++) {
        GtkWidget *b = gtk_button_new_with_label(names[i] && *names[i] ? names[i] : "?");
        gtk_widget_add_css_class(b, "flat");
        g_signal_connect(b, "clicked", G_CALLBACK(sg_pick_on_menu_choice), GINT_TO_POINTER(ids[i]));
        gtk_box_append(GTK_BOX(box), b);
    }
    g_strfreev(names);
    gtk_popover_set_child(GTK_POPOVER(pop), box);
    gtk_widget_set_parent(pop, src);
    at.x = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[sg_pick_source]), "sg-pick-at-x"));
    at.y = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[sg_pick_source]), "sg-pick-at-y"));
    at.width = at.height = 1;
    gtk_popover_set_pointing_to(GTK_POPOVER(pop), &at);
    g_signal_connect(pop, "closed", G_CALLBACK(sg_pick_on_menu_closed), NULL);
    sg_pick_menu = pop;
    gtk_popover_popup(GTK_POPOVER(pop));
}

/* Eiffel's answer to 30. */
static void sg_pick_targets(int source, const int *ids, int count, const char *labels) {
    int i;
    if (!sg_pick_on || source != sg_pick_source) return;
    for (i = 0; i < count; i++) {
        if (ids[i] > 0 && ids[i] < SG_MAX && sg_w[ids[i]]) {
            sg_pick_ok[ids[i]] = 1;
            gtk_widget_add_css_class(sg_pick_widget(ids[i]), "sg-drop-ok");
        }
    }
    if (sg_pick_mode == 2 && sg_pick_window) {
        sg_pick_hook_window(sg_pick_window);
        {
            GtkWidget *line = g_object_get_data(G_OBJECT(sg_pick_window), "sg-pick-line");
            if (line) { gtk_widget_set_visible(line, TRUE); gtk_widget_queue_draw(line); }
        }
    } else if (sg_pick_mode == 3) {
        sg_pick_show_menu(count, ids, labels);
    }
}
static void sg_pick_cancel(void) {
    if (sg_pick_drag) gdk_drag_drop_done(sg_pick_drag, FALSE);
    sg_pick_clear();
}

/* --- as a user would (tests) --- */
static void sg_test_pick(int source, int row) {
    int mode = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(sg_w[source]), "sg-pick-mode"));
    sg_pick_start(source, row, mode > 0 ? mode : 1);
    sg_pick_window = GTK_WIDGET(gtk_widget_get_root(sg_w[source]));
}
static void sg_test_drop(int target, int row) {
    if (!sg_pick_on) return;
    if (target > 0 && target < SG_MAX && sg_pick_ok[target]) sg_push(31, target, row, 0);
    else sg_push(32, sg_pick_source, 0, 0);
    sg_pick_clear();
}
static void sg_test_cancel_pick(void) {
    if (sg_pick_on) {
        sg_push(32, sg_pick_source, 0, 0);
        sg_pick_clear();
    }
}
static int sg_test_is_accepting(int target) {
    return sg_pick_on && target > 0 && target < SG_MAX && sg_pick_ok[target]
        && gtk_widget_has_css_class(sg_pick_widget(target), "sg-drop-ok");
}

#endif
