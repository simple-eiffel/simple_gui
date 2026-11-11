/* simple_gui_appkit.m - simple_gui's macOS backend. See simple_gui_appkit.h.
   Controls push events into a C queue; Eiffel drains it after sga_pump. Nothing
   calls into Eiffel. Lessons kept from the spikes (port-coordination #15):
   - accessibility labels go on a simple control's CELL, which is what VoiceOver reads;
   - a programmatic table selection notifies, so it is suppressed here;
   - margins are leading/trailing constraints, which mirror under right to left;
   - the content view paints the window background, so snapshots match the screen;
   - the wake is a main-queue block, so it also lands inside modal loops. */
#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <UserNotifications/UserNotifications.h>
#include <cairo.h>
#include <pthread.h>
#include <stdatomic.h>
#include <string.h>
#include "simple_gui_appkit.h"

/* ------------------------------------------------------------------ queue */

#define SGA_QUEUE 2048
typedef struct { int type, id, a, b, c; } sga_event;
static sga_event s_events[SGA_QUEUE];
static int s_head, s_tail;
static atomic_int s_wake_pending;

static void sga_push(int a_type, int a_id, int a, int b, int c)
{
	int next = (s_tail + 1) % SGA_QUEUE;
	if (next != s_head) {
		s_events[s_tail] = (sga_event){a_type, a_id, a, b, c};
		s_tail = next;
	}
}

/* ---------------------------------------------------------------- handles */

#define SGA_MAX 8192
static id s_objects[SGA_MAX];      /* id -> NSWindow or NSView (a list: its scroll view; a container: its wrapper) */
static id s_inner[SGA_MAX];        /* a container's NSStackView or NSGridView; a list's NSTableView */
static NSLayoutConstraint *s_margins[SGA_MAX][4];
static NSLayoutConstraint *s_contain[SGA_MAX][2];   /* a wrapper always holds its content */
static int s_count;

static int sga_keep(id a_object)
{
	if (s_count + 1 >= SGA_MAX) return 0;
	s_count++;
	s_objects[s_count] = a_object;
	return s_count;
}

static id sga_get(int a_id) { return (a_id > 0 && a_id <= s_count) ? s_objects[a_id] : nil; }
static id sga_core(int a_id) { return (a_id > 0 && a_id <= s_count) ? (s_inner[a_id] ?: s_objects[a_id]) : nil; }

static int sga_id_of(id a_object)
{
	for (int i = s_count; i >= 1; i--) if (s_objects[i] == a_object || s_inner[i] == a_object) return i;
	return 0;
}

static NSString *sga_string(const char *a_text) { return [NSString stringWithUTF8String:a_text ? a_text : ""] ?: @""; }

/* Returned strings stay valid until the next call of the same kind. */
enum { Kind_label, Kind_button, Kind_field, Kind_role, Kind_path, Kind_tree, Kind_check, Kind_menu, Kind_area, Kind_count };
static NSString *s_returned[Kind_count];
static const char *sga_return(int a_kind, NSString *a_text)
{
	s_returned[a_kind] = [a_text copy] ?: @"";
	return [s_returned[a_kind] UTF8String];
}

static int sga_modifiers(NSEventModifierFlags a_flags)
{
	int m = 0;
	if (a_flags & NSEventModifierFlagShift) m |= 1;
	if (a_flags & NSEventModifierFlagControl) m |= 2;
	if (a_flags & NSEventModifierFlagOption) m |= 4;
	if (a_flags & NSEventModifierFlagCommand) m |= 8;
	return m;
}

/* A key as a GDK key value, the shared vocabulary (SIMPLE_GUI_SPEC.md): named keys
   by their GDK values, anything else by the character it types. */
static int sga_gdk_key(NSEvent *e)
{
	NSString *s = [e charactersIgnoringModifiers];
	unichar k = [s length] ? [s characterAtIndex:0] : 0;
	switch (k) {
		case NSLeftArrowFunctionKey: return 0xff51;
		case NSUpArrowFunctionKey: return 0xff52;
		case NSRightArrowFunctionKey: return 0xff53;
		case NSDownArrowFunctionKey: return 0xff54;
		case NSHomeFunctionKey: return 0xff50;
		case NSPageUpFunctionKey: return 0xff55;
		case NSPageDownFunctionKey: return 0xff56;
		case NSEndFunctionKey: return 0xff57;
		case NSDeleteFunctionKey: return 0xffff;
		case 0x7f: return 0xff08;          /* the Mac's delete key is BackSpace */
		case '\r': case 0x03: return 0xff0d;   /* Return, and Enter on the keypad */
		case '\t': case 0x19: return 0xff09;
		case 0x1b: return 0xff1b;
	}
	if (k >= NSF1FunctionKey && k <= NSF12FunctionKey) return 0xffbe + (k - NSF1FunctionKey);
	/* Letters and digits as the character typed, shift included, as GDK reports them. */
	s = [e characters];
	return [s length] ? (int)[s characterAtIndex:0] : (int)k;
}

/* ------------------------------------------------------------------ views */

/* With a status bar (1g) the window draws its bottom bar under the content view, so the
   content view leaves that strip unpainted. */
@interface SGAContent : NSView
{
@public
	CGFloat bottom_bar;
}
@end
@implementation SGAContent
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return bottom_bar <= 0; }
- (void)drawRect:(NSRect)a_rect
{
	NSRect l_painted = [self bounds];
	l_painted.size.height -= bottom_bar;
	[[NSColor windowBackgroundColor] setFill];
	NSRectFill(NSIntersectionRect(a_rect, l_painted));
}
@end

@interface SGAWrapper : NSView
@end
@implementation SGAWrapper
- (BOOL)isFlipped { return YES; }
@end

@interface SGACanvas : NSView
{
@public
	CGImageRef image;
	NSSize wanted;
}
@end

@implementation SGACanvas
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { (void)e; return YES; }
- (NSSize)intrinsicContentSize { return wanted; }
- (void)dealloc { if (image) CGImageRelease(image); }
- (void)drawRect:(NSRect)a_rect
{
	(void)a_rect;
	[[NSColor windowBackgroundColor] setFill];
	NSRectFill([self bounds]);
	if (image) {
		CGContextRef l_cg = [[NSGraphicsContext currentContext] CGContext];
		NSRect b = [self bounds];
		CGContextSaveGState(l_cg);
		CGContextTranslateCTM(l_cg, 0, b.size.height);
		CGContextScaleCTM(l_cg, 1, -1);
		if ([self inLiveResize]) {
			/* While the user drags a window edge AppKit runs its own loop and the program cannot
			   draw (it hears the final size when the drag ends): show the last picture at its own
			   size, anchored at the top left, rather than stretched out of shape. */
			CGFloat l_scale = [[self window] backingScaleFactor] > 0 ? [[self window] backingScaleFactor] : 1;
			CGFloat w = (CGFloat)CGImageGetWidth(image) / l_scale, h = (CGFloat)CGImageGetHeight(image) / l_scale;
			CGContextDrawImage(l_cg, CGRectMake(0, b.size.height - h, w, h), image);
		}
		else CGContextDrawImage(l_cg, CGRectMake(0, 0, b.size.width, b.size.height), image);
		CGContextRestoreGState(l_cg);
	}
}
- (void)pointer:(NSEvent *)e kind:(int)a_kind
{
	NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
	int l_button = (int)[e buttonNumber] + 1;
	if (a_kind == 3 && [NSEvent pressedMouseButtons] == 0) l_button = 0;
	sga_push(7, sga_id_of(self), (int)p.x, (int)p.y, a_kind + l_button * 16 + sga_modifiers([e modifierFlags]) * 256);
}
- (void)mouseDown:(NSEvent *)e { [[self window] makeFirstResponder:self]; [self pointer:e kind:1]; }
- (void)mouseUp:(NSEvent *)e { [self pointer:e kind:2]; }
- (void)mouseDragged:(NSEvent *)e { [self pointer:e kind:3]; }
- (void)rightMouseDown:(NSEvent *)e { [self pointer:e kind:1]; }
- (void)rightMouseUp:(NSEvent *)e { [self pointer:e kind:2]; }
- (void)otherMouseDown:(NSEvent *)e { [self pointer:e kind:1]; }
- (void)otherMouseUp:(NSEvent *)e { [self pointer:e kind:2]; }
- (void)keyDown:(NSEvent *)e
{
	NSString *s = [e characters];
	unichar l_char = [s length] ? [s characterAtIndex:0] : 0;
	/* The character as GTK's gdk_keyval_to_unicode gives it: the Mac's delete key is
	   BackSpace (8), forward delete is 0x7F, keypad Enter is Return (13), Shift-Tab is Tab. */
	switch (l_char) {
		case 0x7f: l_char = 0x08; break;
		case NSDeleteFunctionKey: l_char = 0x7f; break;
		case 0x03: l_char = 0x0d; break;
		case 0x19: l_char = 0x09; break;
		default: if (l_char >= 0xF700 && l_char <= 0xF8FF) l_char = 0;
	}
	sga_push(8, sga_id_of(self), sga_gdk_key(e), l_char, sga_modifiers([e modifierFlags]) * 256);
}
- (void)setFrameSize:(NSSize)a_size
{
	NSSize l_old = [self frame].size;
	[super setFrameSize:a_size];
	if (!NSEqualSizes(l_old, a_size) && ![self inLiveResize]) sga_push(9, sga_id_of(self), (int)a_size.width, (int)a_size.height, 0);
}
/* One resize event for a whole live resize: the final size, when the drag ends (the program
   could not draw during it, and would otherwise redraw once per frame afterwards). */
- (void)viewDidEndLiveResize
{
	[super viewDidEndLiveResize];
	NSSize s = [self bounds].size;
	sga_push(9, sga_id_of(self), (int)s.width, (int)s.height, 0);
	[self setNeedsDisplay:YES];
}
@end

/* ------------------------------------------------ targets and delegates */

static int s_suppress;
static void sga_colors_flush(void);   /* 1v-b: the colors that wait go to their text (see its definition) */
static int s_setting_dark;

@interface SGATarget : NSObject <NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSTabViewDelegate>
{
@public
	NSMutableDictionary<NSValue *, NSMutableArray *> *rows;   /* a list's rows: NSString, or SGARichRow (1s) */
}
@end

/* 1s: a filtered list or table shows some of its model's rows. The shown map lists the
   model rows (from 0) on screen in order; none means every row shows. Every row number the
   program sees is the model's: the map turns screen rows into model rows and back. */
static NSMutableDictionary<NSValue *, NSArray<NSNumber *> *> *s_shown;
static NSArray<NSNumber *> *sga_shown_map(NSTableView *t) { return s_shown[[NSValue valueWithNonretainedObject:t]]; }
static void sga_set_shown_map(NSTableView *t, NSArray<NSNumber *> *a_map)
{
	if (!s_shown) s_shown = [NSMutableDictionary dictionary];
	if (a_map) s_shown[[NSValue valueWithNonretainedObject:t]] = a_map; else [s_shown removeObjectForKey:[NSValue valueWithNonretainedObject:t]];
}
/* The model row (from 0) on screen row `a_view', and the screen row of model row `a_model' (-1: hidden). */
static NSInteger sga_model_row(NSTableView *t, NSInteger a_view)
{
	NSArray<NSNumber *> *m = sga_shown_map(t);
	return !m || a_view < 0 ? a_view : (a_view < (NSInteger)[m count] ? [m[(NSUInteger)a_view] integerValue] : -1);
}
static NSInteger sga_view_row(NSTableView *t, NSInteger a_model)
{
	NSArray<NSNumber *> *m = sga_shown_map(t);
	if (!m || a_model < 0) return a_model;
	NSUInteger i = [m indexOfObject:@(a_model)];
	return i == NSNotFound ? -1 : (NSInteger)i;
}

/* 1s: a rich list row: a title, a dimmer subtitle, an icon, a badge, a check box at the
   leading edge, a close button at the trailing edge. */
@interface SGARichRow : NSObject
{
@public
	NSString *title, *subtitle, *icon;
	int badge;
	BOOL checkable, checked, closable;
}
@end
@implementation SGARichRow
@end
static NSString *sga_row_title(id a_row) { return [a_row isKindOfClass:[SGARichRow class]] ? ((SGARichRow *)a_row)->title : (NSString *)a_row; }

static int sga_tab_page(NSTabView *t, NSInteger an_item);
static void sga_grid_user_select(int a_id, int i, BOOL an_extend);   /* 1v-a */
static void sga_tabs_titles_follow(NSTabView *t);   /* 1t: a side strip follows its tab view */
static NSView *sga_rich_cell(NSTableView *t, SGARichRow *a_row, NSInteger a_model);
static BOOL sga_suggest_key(int a_id, SEL a_command);   /* 1p */
static void sga_suggest_end(int a_id);   /* 1p */

/* A cell's text starts at the leading edge: the right one under right to left, as GTK mirrors
   a label's alignment. */
static NSTextAlignment sga_start_alignment(NSView *a_view)
{
	return [a_view userInterfaceLayoutDirection] == NSUserInterfaceLayoutDirectionRightToLeft ? NSTextAlignmentRight : NSTextAlignmentNatural;
}

@implementation SGATarget
- (instancetype)init { if ((self = [super init])) rows = [NSMutableDictionary dictionary]; return self; }
- (void)clicked:(id)a_sender { sga_push(1, sga_id_of(a_sender), 0, 0, 0); }
- (void)activated:(id)a_sender { sga_push(3, sga_id_of(a_sender), 0, 0, 0); }
- (void)menuItem:(NSMenuItem *)a_item { sga_push(5, 0, (int)[a_item tag], 0, 0); }
- (void)toggled:(NSButton *)a_box { sga_push(12, sga_id_of(a_box), [a_box state] == NSControlStateValueOn ? 1 : 0, 0, 0); }
- (void)tabView:(NSTabView *)a_tabs didSelectTabViewItem:(NSTabViewItem *)an_item { sga_tabs_titles_follow(a_tabs); if (!s_suppress) sga_push(13, sga_id_of(a_tabs), sga_tab_page(a_tabs, [a_tabs indexOfTabViewItem:an_item]), 0, 0); }
- (void)controlTextDidChange:(NSNotification *)n { if (!s_suppress) sga_push(2, sga_id_of([n object]), 0, 0, 0); }
/* 1p: leaving a field ends its editing (29), when validation on commit checks it. */
- (void)controlTextDidEndEditing:(NSNotification *)n { sga_suggest_end(sga_id_of([n object])); if (!s_suppress) sga_push(29, sga_id_of([n object]), 0, 0, 0); }
/* 1p: Up, Down, Return and Escape go to the field's suggestion list while it shows. */
- (BOOL)control:(NSControl *)c textView:(NSTextView *)tv doCommandBySelector:(SEL)a_command
{
	(void)tv;
	/* 1p-b: Escape on a field closes its suggestion list and sends 55, in one press as on
	   GTK and Windows; a search field and a combo box keep their own Escape */
	if (a_command == @selector(cancelOperation:) && [c isKindOfClass:[NSTextField class]] && ![c isKindOfClass:[NSSearchField class]] && ![c isKindOfClass:[NSComboBox class]]) {
		sga_suggest_end(sga_id_of(c));
		if (!s_suppress) { sga_push(55, sga_id_of(c), 0, 0, 0); sga_wake(); }
		return YES;
	}
	return sga_suggest_key(sga_id_of(c), a_command);
}
- (void)textDidChange:(NSNotification *)n { if (!s_suppress) sga_push(2, sga_id_of([n object]), 0, 0, 0); }
/* 1v-b: before a text view changes its characters (typing, paste, undo, a replace), the colors that wait go in */
- (BOOL)textView:(NSTextView *)t shouldChangeTextInRange:(NSRange)r replacementString:(NSString *)s { (void)t; (void)r; (void)s; sga_colors_flush(); return YES; }
- (NSMutableArray *)rowsOf:(NSTableView *)t { return rows[[NSValue valueWithNonretainedObject:t]]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t
{
	NSArray *m = sga_shown_map(t);
	return (NSInteger)(m ? [m count] : [[self rowsOf:t] count]);
}
- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)r
{
	(void)c;
	NSInteger l_model = sga_model_row(t, r);
	id l_row = l_model >= 0 && l_model < (NSInteger)[[self rowsOf:t] count] ? [self rowsOf:t][(NSUInteger)l_model] : @"";
	if ([l_row isKindOfClass:[SGARichRow class]]) return sga_rich_cell(t, l_row, l_model);
	NSTextField *l_cell = [t makeViewWithIdentifier:@"sga_cell" owner:self];
	if (!l_cell) { l_cell = [NSTextField labelWithString:@""]; l_cell.identifier = @"sga_cell"; }
	l_cell.stringValue = l_row;
	l_cell.alignment = sga_start_alignment(t);
	return l_cell;
}
- (void)tableViewSelectionDidChange:(NSNotification *)n
{
	NSTableView *t = [n object];
	/* A user's emptying of the selection is a selection too: row 0. With several rows (1p), the
	   first. Rows are the model's (1s). */
	NSUInteger l_first = [[t selectedRowIndexes] firstIndex];
	if (!s_suppress) sga_push(4, sga_id_of(t), l_first == NSNotFound ? 0 : (int)sga_model_row(t, (NSInteger)l_first) + 1, 0, 0);
}
- (BOOL)windowShouldClose:(NSWindow *)w { sga_push(6, sga_id_of(w), 0, 0, 0); return NO; }
- (void)observeValueForKeyPath:(NSString *)p ofObject:(id)o change:(NSDictionary *)ch context:(void *)ctx
{
	(void)p; (void)o; (void)ch; (void)ctx;
	if (!s_setting_dark) sga_push(10, 0, sga_is_dark(), 0, 0);
}
- (void)heartbeat:(NSTimer *)t { (void)t; }
@end

static SGATarget *s_target;
static NSString *s_app_name;
static NSTimer *s_heartbeat;

/* ------------------------------------------------------------------- loop */

int sga_is_gui_thread(void) { return pthread_main_np() ? 1 : 0; }

/* ------------------------------------------- the menus every Mac app has */

/* The application menu a Mac user expects, before the program adds its own items:
   Services, Hide, Hide Others, Show All. About and Settings are placed above Services and
   Quit below the hiding items as the program adds them (sga_menu_add_item). */
static NSMenuItem *s_services_item;
/* The Window menu (Minimize, Zoom, Enter Full Screen, Bring All to Front; AppKit lists the
   open windows itself). It stays after the program's menus and before Help. */
static NSMenuItem *s_window_item;

static NSMenu *sga_standard_app_menu(void)
{
	NSMenu *m = [[NSMenu alloc] initWithTitle:s_app_name];
	NSMenu *l_services = [[NSMenu alloc] initWithTitle:@"Services"];
	NSMenuItem *i;
	s_services_item = [[NSMenuItem alloc] initWithTitle:@"Services" action:nil keyEquivalent:@""];
	[s_services_item setSubmenu:l_services];
	[NSApp setServicesMenu:l_services];
	[m addItem:s_services_item];
	[m addItem:[NSMenuItem separatorItem]];
	[m addItem:[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Hide %@", s_app_name] action:@selector(hide:) keyEquivalent:@"h"]];
	i = [[NSMenuItem alloc] initWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
	[i setKeyEquivalentModifierMask:NSEventModifierFlagCommand | NSEventModifierFlagOption];
	[m addItem:i];
	[m addItem:[[NSMenuItem alloc] initWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""]];
	return m;
}

static NSMenuItem *sga_standard_window_menu(void)
{
	NSMenu *m = [[NSMenu alloc] initWithTitle:@"Window"];
	NSMenuItem *l_top = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
	[m addItem:[[NSMenuItem alloc] initWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"]];
	[m addItem:[[NSMenuItem alloc] initWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""]];
	/* Enter Full Screen, with the Globe-F shortcut macOS uses (AppKit retitles it Exit Full
	   Screen while the key window is full screen). */
	NSMenuItem *l_full = [[NSMenuItem alloc] initWithTitle:@"Enter Full Screen" action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
	[l_full setKeyEquivalentModifierMask:NSEventModifierFlagFunction];
	[m addItem:l_full];
	[m addItem:[NSMenuItem separatorItem]];
	[m addItem:[[NSMenuItem alloc] initWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""]];
	[l_top setSubmenu:m];
	return l_top;
}

int sga_init(const char *a_name, const char *a_id)
{
	(void)a_id;   /* a .app bundle supplies the identifier; a plain executable has none to set */
	if (!pthread_main_np()) return 0;
	[NSApplication sharedApplication];
	/* A regular app (Dock icon, menu bar when active) that does not take focus on
	   its own: the person at the keyboard decides when it comes forward. */
	[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
	s_target = [[SGATarget alloc] init];
	s_app_name = sga_string(a_name);
	NSMenu *l_bar = [[NSMenu alloc] init];
	NSMenuItem *l_app = [[NSMenuItem alloc] init];
	[l_app setSubmenu:sga_standard_app_menu()];
	[l_bar addItem:l_app];
	s_window_item = sga_standard_window_menu();
	[l_bar addItem:s_window_item];
	[NSApp setMainMenu:l_bar];
	[NSApp setWindowsMenu:[s_window_item submenu]];
	[NSApp addObserver:s_target forKeyPath:@"effectiveAppearance" options:0 context:NULL];
	[NSApp finishLaunching];
	return NSApp != nil;
}

static NSWindow *s_modal_window;   /* 1u: the app-modal dialog up, nil none */
static int sga_run_once(NSDate *a_until)
{
	int n = 0;
	sga_colors_flush();
	@autoreleasepool {
		NSEvent *e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:a_until inMode:NSDefaultRunLoopMode dequeue:YES];
		if (e) {
			/* 1u: while an app-modal dialog is up, the user's clicks and keys reach it alone */
			BOOL l_blocked = s_modal_window && [e window] && [e window] != s_modal_window && ![[e window] isKindOfClass:[NSPanel class]]
				&& ([e type] == NSEventTypeLeftMouseDown || [e type] == NSEventTypeRightMouseDown || [e type] == NSEventTypeKeyDown || [e type] == NSEventTypeOtherMouseDown);
			if (l_blocked) NSBeep();
			else if ([e type] != NSEventTypeApplicationDefined) [NSApp sendEvent:e];
			n = 1;
		}
	}
	return n;
}

void sga_pump(int a_ms)
{
	NSDate *l_until = [NSDate dateWithTimeIntervalSinceNow:a_ms / 1000.0];
	while (s_head == s_tail && [l_until timeIntervalSinceNow] > 0) {
		if (!sga_run_once(l_until)) break;
	}
	/* Whatever else is already waiting goes through too. */
	while (sga_run_once([NSDate distantPast])) {}
}

/* Time-based: a new window needs its first layout and drawing passes, which an
   "until no event is waiting" loop can return before (PROD's GTK lesson). */
void sga_pump_until_idle(int a_ms)
{
	NSDate *l_until = [NSDate dateWithTimeIntervalSinceNow:a_ms / 1000.0];
	while ([l_until timeIntervalSinceNow] > 0) sga_run_once(l_until);
	sga_colors_flush();
	for (NSWindow *w in [NSApp windows]) { [[w contentView] layoutSubtreeIfNeeded]; [w displayIfNeeded]; }
}

void sga_start_heartbeat(int a_ms)
{
	[s_heartbeat invalidate];
	s_heartbeat = [NSTimer scheduledTimerWithTimeInterval:a_ms / 1000.0 target:s_target selector:@selector(heartbeat:) userInfo:nil repeats:YES];
}

/* Any thread. Coalesces: while one wake waits in the queue, more add nothing. */
void sga_wake(void)
{
	int l_expected = 0;
	if (!atomic_compare_exchange_strong(&s_wake_pending, &l_expected, 1)) return;
	dispatch_async(dispatch_get_main_queue(), ^{
		sga_push(11, 0, 0, 0, 0);
		NSEvent *e = [NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint
			modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0];
		[NSApp postEvent:e atStart:NO];
	});
}

int sga_next(int *a_type, int *a_id, int *a, int *b, int *c)
{
	if (s_head == s_tail) return 0;
	*a_type = s_events[s_head].type; *a_id = s_events[s_head].id;
	*a = s_events[s_head].a; *b = s_events[s_head].b; *c = s_events[s_head].c;
	if (*a_type == 11) atomic_store(&s_wake_pending, 0);
	s_head = (s_head + 1) % SGA_QUEUE;
	return 1;
}

/* ------------------------------------------------------ 1l: reference pills */

/* A reference pill: a small burnt-orange label centered on a corner of its widget (half
   outside it, as simple_bible's are), over everything in the window's content view, held
   there by constraints so it follows layout, resizing and right to left (the leading and
   trailing anchors mirror by themselves). Its toolTip is the tip Eiffel wrote. Pills stay
   out of the accessibility tree: the tip is help, not content. */
@interface SGAPill : NSTextField
{
@public
	int target;   /* the widget's id */
	int corner;   /* 1 top-left, 2 top-right, 3 bottom-left, 4 bottom-right (left and right: leading and trailing) */
	NSArray<NSLayoutConstraint *> *placing;
}
@end
@implementation SGAPill
- (BOOL)isAccessibilityElement { return NO; }
@end

static NSMutableDictionary<NSNumber *, SGAPill *> *s_pills;   /* widget id -> its pill */
static BOOL s_pills_shown;

/* Put `p' over its widget's window content, at its corner, when the widget is in a window. */
static void sga_pill_place(SGAPill *p)
{
	/* A container's pill sits on the stack or grid inside its margins, as its size and place do. */
	NSView *t = s_margins[p->target][0] ? s_inner[p->target] : sga_get(p->target);
	NSView *c = [[t window] contentView];
	if (![t isKindOfClass:[NSView class]] || !c || ![t isDescendantOf:c]) return;
	if ([p superview] != c) {
		[p removeFromSuperview];
		[c addSubview:p positioned:NSWindowAbove relativeTo:nil];
	}
	if (p->placing) [NSLayoutConstraint deactivateConstraints:p->placing];
	BOOL l_leading = p->corner == 1 || p->corner == 3, l_top = p->corner == 1 || p->corner == 2;
	p->placing = @[
		[p.centerXAnchor constraintEqualToAnchor:l_leading ? t.leadingAnchor : t.trailingAnchor],
		[p.centerYAnchor constraintEqualToAnchor:l_top ? t.topAnchor : t.bottomAnchor]];
	[NSLayoutConstraint activateConstraints:p->placing];
	[p setHidden:!s_pills_shown];
}

/* Pills whose widget joined a window since: placed now (window shown, content set). */
static void sga_error_notes_sync(void);   /* 1p */
static void sga_badges_sync(void);   /* 1n */

static void sga_pills_sync(void)
{
	for (SGAPill *p in [s_pills allValues]) if (![p superview]) sga_pill_place(p);
	sga_error_notes_sync();
	sga_badges_sync();
}

void sga_pill_set(int a_id, const char *a_code, const char *a_tip, int a_corner)
{
	if (!s_pills) s_pills = [NSMutableDictionary dictionary];
	SGAPill *p = s_pills[@(a_id)];
	if (!p) {
		p = [SGAPill labelWithString:@""];
		[p setTranslatesAutoresizingMaskIntoConstraints:NO];
		[p setFont:[NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize] - 1]];
		[p setTextColor:[NSColor whiteColor]];
		[p setAlignment:NSTextAlignmentCenter];
		[p setDrawsBackground:YES];
		[p setBackgroundColor:[NSColor colorWithSRGBRed:0xCC / 255.0 green:0x55 / 255.0 blue:0x00 / 255.0 alpha:1]];
		[p setWantsLayer:YES];
		[[p layer] setCornerRadius:7];
		[[p layer] setMasksToBounds:YES];
		[p setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
		[NSLayoutConstraint activateConstraints:@[[p.heightAnchor constraintEqualToConstant:15]]];
		p->target = a_id;
		s_pills[@(a_id)] = p;
	}
	[p setStringValue:[NSString stringWithFormat:@" %@ ", sga_string(a_code)]];
	[p setToolTip:sga_string(a_tip)];
	p->corner = a_corner;
	sga_pill_place(p);
}

void sga_pill_clear(int a_id)
{
	SGAPill *p = s_pills[@(a_id)];
	if (p) {
		if (p->placing) [NSLayoutConstraint deactivateConstraints:p->placing];
		[p removeFromSuperview];
		[s_pills removeObjectForKey:@(a_id)];
	}
}

void sga_pills_show(int a_on)
{
	s_pills_shown = a_on != 0;
	sga_pills_sync();
	for (SGAPill *p in [s_pills allValues]) [p setHidden:!s_pills_shown];
}

/* For tests: the tip a user would read now (shown, placed, in a visible window), else "". */
const char *sga_pill_tip_shown(int a_id)
{
	SGAPill *p = s_pills[@(a_id)];
	BOOL l_up = p && s_pills_shown && [p superview] && ![p isHidden] && [[p window] isVisible];
	return sga_return(Kind_label, l_up ? ([p toolTip] ?: @"") : @"");
}

/* ------------------------------------------------------- windows, layout */

static void sga_help_watch(void);   /* 1u: F1 and Command+? */
int sga_window(const char *a_title, int a_width, int a_height)
{
	sga_help_watch();
	NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(160, 160, a_width, a_height)
		styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
		backing:NSBackingStoreBuffered defer:NO];
	[w setReleasedWhenClosed:NO];
	[w setTitle:sga_string(a_title)];
	[w setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];   /* the green button, and Window > Enter Full Screen */
	[w setContentView:[[SGAContent alloc] initWithFrame:NSMakeRect(0, 0, a_width, a_height)]];
	[[w contentView] registerForDraggedTypes:@[NSPasteboardTypeFileURL, NSPasteboardTypeString]];   /* 1q-b */
	[w setDelegate:s_target];
	return sga_keep(w);
}

@interface SGAStatus : NSTextField
@end
@implementation SGAStatus
@end

/* Each window's content bottom constraint, by window id: it ends above a status bar. */
static NSMutableDictionary<NSNumber *, NSLayoutConstraint *> *s_content_bottom;

void sga_window_set_content(int a_window, int a_child)
{
	NSWindow *w = sga_get(a_window);
	SGAContent *l_content = [w contentView];
	NSView *v = sga_get(a_child);
	for (NSView *l_old in [[l_content subviews] copy]) if (![l_old isKindOfClass:[SGAStatus class]]) [l_old removeFromSuperview];
	[v setTranslatesAutoresizingMaskIntoConstraints:NO];
	/* The window keeps the size the program asked for: a lone control (a button, a label) must
	   not pull it down to its own natural size. */
	for (NSInteger o = 0; o < 2; o++)
		if ([v contentHuggingPriorityForOrientation:o] >= NSLayoutPriorityWindowSizeStayPut)
			[v setContentHuggingPriority:NSLayoutPriorityWindowSizeStayPut - 1 forOrientation:o];
	[l_content addSubview:v];
	/* a group box as the whole content keeps the containers' 12 from the window's edges */
	CGFloat m = [v isKindOfClass:[NSBox class]] ? 12 : 0;
	NSLayoutConstraint *l_bottom = [v.bottomAnchor constraintEqualToAnchor:l_content.bottomAnchor constant:-l_content->bottom_bar - m];
	[NSLayoutConstraint activateConstraints:@[
		[v.leadingAnchor constraintEqualToAnchor:l_content.leadingAnchor constant:m],
		[v.trailingAnchor constraintEqualToAnchor:l_content.trailingAnchor constant:-m],
		[v.topAnchor constraintEqualToAnchor:l_content.topAnchor constant:m],
		l_bottom]];
	if (!s_content_bottom) s_content_bottom = [NSMutableDictionary dictionary];
	s_content_bottom[@(a_window)] = l_bottom;
	sga_pills_sync();
}

void sga_window_show(int a_window) { [(NSWindow *)sga_get(a_window) orderFront:nil]; sga_pills_sync(); }
void sga_window_close(int a_window) { [(NSWindow *)sga_get(a_window) orderOut:nil]; }
void sga_window_set_title(int a_window, const char *a_title) { [(NSWindow *)sga_get(a_window) setTitle:sga_string(a_title)]; }

/* A container: a flipped wrapper holding a stack or grid inside leading, top,
   trailing and bottom margin constraints (12 px, as the API states). */
static NSLayoutConstraint *sga_end_margin(int a_stack);

/* Pins a wrapper's content at the given margins and priorities (0 leading, 1 top, 2 trailing,
   3 bottom). Whatever the margins' priority, the wrapper always contains its content: weakening
   an end margin may leave room at the end, never let the content spill past it. */
static void sga_pin(int a_id, const CGFloat a_margin[4], const NSLayoutPriority a_priority[4])
{
	NSView *w = s_objects[a_id], *l_inner = s_inner[a_id];
	s_margins[a_id][0] = [l_inner.leadingAnchor constraintEqualToAnchor:w.leadingAnchor constant:a_margin[0]];
	s_margins[a_id][1] = [l_inner.topAnchor constraintEqualToAnchor:w.topAnchor constant:a_margin[1]];
	s_margins[a_id][2] = [w.trailingAnchor constraintEqualToAnchor:l_inner.trailingAnchor constant:a_margin[2]];
	s_margins[a_id][3] = [w.bottomAnchor constraintEqualToAnchor:l_inner.bottomAnchor constant:a_margin[3]];
	for (int i = 0; i < 4; i++) [s_margins[a_id][i] setPriority:a_priority[i]];
	s_contain[a_id][0] = [w.trailingAnchor constraintGreaterThanOrEqualToAnchor:l_inner.trailingAnchor constant:a_margin[2]];
	s_contain[a_id][1] = [w.bottomAnchor constraintGreaterThanOrEqualToAnchor:l_inner.bottomAnchor constant:a_margin[3]];
	[NSLayoutConstraint activateConstraints:@[s_contain[a_id][0], s_contain[a_id][1]]];
	[NSLayoutConstraint activateConstraints:@[s_margins[a_id][0], s_margins[a_id][1], s_margins[a_id][2], s_margins[a_id][3]]];
}

static int sga_wrap(NSView *a_inner, CGFloat a_margin)
{
	SGAWrapper *w = [[SGAWrapper alloc] init];
	[a_inner setTranslatesAutoresizingMaskIntoConstraints:NO];
	[w addSubview:a_inner];
	int l_id = sga_keep(w);
	s_inner[l_id] = a_inner;
	/* Just below required, so a stack can later weaken its end margin (AppKit will not move an
	   active constraint between required and optional). */
	const CGFloat l_margin[4] = {a_margin, a_margin, a_margin, a_margin};
	const NSLayoutPriority l_priority[4] = {NSLayoutPriorityRequired - 1, NSLayoutPriorityRequired - 1,
		NSLayoutPriorityRequired - 1, NSLayoutPriorityRequired - 1};
	sga_pin(l_id, l_margin, l_priority);
	return l_id;
}

/* A leading or trailing constraint takes its direction when it is made, and NSGridView reads
   its own only when it is put in a view; neither follows a later change. So on a change the
   wrapper's margins are made again, and a grid is first taken out of its wrapper and put back
   (keeping the keyboard focus if it was inside). */
static void sga_reattach(int a_id)
{
	NSView *w = s_objects[a_id], *l_inner = s_inner[a_id];
	CGFloat l_margin[4];
	NSLayoutPriority l_priority[4];
	for (int i = 0; i < 4; i++) { l_margin[i] = s_margins[a_id][i].constant; l_priority[i] = s_margins[a_id][i].priority; }
	if ([l_inner isKindOfClass:[NSGridView class]]) {
		NSResponder *l_focus = [[w window] firstResponder];
		if ([l_focus isKindOfClass:[NSTextView class]] && [(NSTextView *)l_focus isFieldEditor]) l_focus = (NSResponder *)[(NSTextView *)l_focus delegate];
		BOOL l_inside = [l_focus isKindOfClass:[NSView class]] && [(NSView *)l_focus isDescendantOf:l_inner];
		[l_inner removeFromSuperview];
		[w addSubview:l_inner];
		if (l_inside) [[w window] makeFirstResponder:l_focus];
	} else {
		[NSLayoutConstraint deactivateConstraints:@[s_margins[a_id][0], s_margins[a_id][1], s_margins[a_id][2], s_margins[a_id][3],
			s_contain[a_id][0], s_contain[a_id][1]]];
	}
	sga_pin(a_id, l_margin, l_priority);
}

/* A control is never squeezed below its natural size: AppKit would cut a button's
   label to "Zoom\u2026" where GTK keeps the button whole, and the window grows
   instead. */
static void sga_keep_natural_size(NSView *a_view, int a_stretch)
{
	/* A stretching child keeps AppKit's default: lowering it ties with the stack's own
	   priorities and hands the spare room to the wrong child. */
	if (a_stretch) return;
	NSLayoutPriority l_priority = NSLayoutPriorityRequired - 1;
	/* A label may narrow: it truncates instead (SGALabel). */
	if (![a_view isKindOfClass:NSClassFromString(@"SGALabel")])
		[a_view setContentCompressionResistancePriority:l_priority forOrientation:NSLayoutConstraintOrientationHorizontal];
	[a_view setContentCompressionResistancePriority:l_priority forOrientation:NSLayoutConstraintOrientationVertical];
}

/* The margin at the end of a stack's main axis: bottom when vertical, trailing when not. */
static NSLayoutConstraint *sga_end_margin(int a_stack)
{
	NSStackView *s = s_inner[a_stack];
	return s_margins[a_stack][[s orientation] == NSUserInterfaceLayoutOrientationVertical ? 3 : 2];
}

int sga_stack(int a_vertical, int a_spacing)
{
	NSStackView *s = [[NSStackView alloc] init];
	[s setOrientation:a_vertical ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal];
	[s setDistribution:NSStackViewDistributionFill];
	[s setAlignment:a_vertical ? NSLayoutAttributeLeading : NSLayoutAttributeTop];
	[s setSpacing:a_spacing];
	int l_id = sga_wrap(s, 12);
	/* Like a GTK box, a stack packs its children at the start and leaves the spare room at
	   the end, until a child stretches: its end margin holds only weakly till then. */
	[sga_end_margin(l_id) setPriority:NSLayoutPriorityDefaultLow - 2];
	[s setHuggingPriority:NSLayoutPriorityDefaultLow - 1 forOrientation:a_vertical ? NSLayoutConstraintOrientationVertical : NSLayoutConstraintOrientationHorizontal];
	return l_id;
}

/* Each child sits in a slot: the slot fills the stack across, and the child is placed
   inside it by alignment (0 fill, 1 start, 2 center, 3 end). NSStackView applies one
   alignment to all its children, and extra constraints fight its own, so per-child
   alignment lives in the slot. Main axis: the child fills its slot, and a stretching
   child's slot takes the spare room. */
@interface SGASlot : NSView
{
@public
	NSView *child;
	NSMutableArray<NSLayoutConstraint *> *placing;   /* every constraint between child and slot */
	int alignment;
	BOOL vertical;
	BOOL natural;   /* a button: keeps its natural size on the main axis too */
	BOOL stretches; /* takes a share of the stack's spare room */
}
@end
@implementation SGASlot
- (BOOL)isFlipped { return YES; }
@end

static NSMutableDictionary<NSValue *, SGASlot *> *s_slots;   /* child view -> its slot */
static int s_stack_alignment[SGA_MAX];                        /* -1: per-child defaults */

static SGASlot *sga_slot_of(NSView *a_child)
{
	return s_slots ? s_slots[[NSValue valueWithNonretainedObject:a_child]] : nil;
}

static void sga_place(SGASlot *a_slot, int a_alignment)
{
	NSView *c = a_slot->child;
	[NSLayoutConstraint deactivateConstraints:a_slot->placing];
	[a_slot->placing removeAllObjects];
	a_slot->alignment = a_alignment;
	/* Main axis: the child fills its slot, except a button, which keeps its natural size
	   while its slot takes the room (GTK: hexpand with halign START). */
	if (a_slot->natural) {
		NSLayoutConstraint *l_hug = a_slot->vertical ? [c.heightAnchor constraintEqualToAnchor:a_slot.heightAnchor]
			: [c.widthAnchor constraintEqualToAnchor:a_slot.widthAnchor];
		[l_hug setPriority:NSLayoutPriorityDefaultLow - 1];
		if (a_slot->vertical) [a_slot->placing addObjectsFromArray:@[[c.topAnchor constraintEqualToAnchor:a_slot.topAnchor],
			[c.bottomAnchor constraintLessThanOrEqualToAnchor:a_slot.bottomAnchor], l_hug]];
		else [a_slot->placing addObjectsFromArray:@[[c.leadingAnchor constraintEqualToAnchor:a_slot.leadingAnchor],
			[c.trailingAnchor constraintLessThanOrEqualToAnchor:a_slot.trailingAnchor], l_hug]];
	} else if (a_slot->vertical) [a_slot->placing addObjectsFromArray:@[[c.topAnchor constraintEqualToAnchor:a_slot.topAnchor],
		[c.bottomAnchor constraintEqualToAnchor:a_slot.bottomAnchor]]];
	else [a_slot->placing addObjectsFromArray:@[[c.leadingAnchor constraintEqualToAnchor:a_slot.leadingAnchor],
		[c.trailingAnchor constraintEqualToAnchor:a_slot.trailingAnchor]]];
	/* Across: by alignment. */
	if (a_slot->vertical) {
		switch (a_alignment) {
			case 0: [a_slot->placing addObjectsFromArray:@[[c.leadingAnchor constraintEqualToAnchor:a_slot.leadingAnchor],
				[c.trailingAnchor constraintEqualToAnchor:a_slot.trailingAnchor]]]; break;
			case 1: [a_slot->placing addObjectsFromArray:@[[c.leadingAnchor constraintEqualToAnchor:a_slot.leadingAnchor],
				[c.trailingAnchor constraintLessThanOrEqualToAnchor:a_slot.trailingAnchor]]]; break;
			case 2: [a_slot->placing addObjectsFromArray:@[[c.centerXAnchor constraintEqualToAnchor:a_slot.centerXAnchor],
				[c.leadingAnchor constraintGreaterThanOrEqualToAnchor:a_slot.leadingAnchor]]]; break;
			default: [a_slot->placing addObjectsFromArray:@[[c.trailingAnchor constraintEqualToAnchor:a_slot.trailingAnchor],
				[c.leadingAnchor constraintGreaterThanOrEqualToAnchor:a_slot.leadingAnchor]]]; break;
		}
	} else {
		switch (a_alignment) {
			case 0: [a_slot->placing addObjectsFromArray:@[[c.topAnchor constraintEqualToAnchor:a_slot.topAnchor],
				[c.bottomAnchor constraintEqualToAnchor:a_slot.bottomAnchor]]]; break;
			case 1: [a_slot->placing addObjectsFromArray:@[[c.topAnchor constraintEqualToAnchor:a_slot.topAnchor],
				[c.bottomAnchor constraintLessThanOrEqualToAnchor:a_slot.bottomAnchor]]]; break;
			case 2: [a_slot->placing addObjectsFromArray:@[[c.centerYAnchor constraintEqualToAnchor:a_slot.centerYAnchor],
				[c.topAnchor constraintGreaterThanOrEqualToAnchor:a_slot.topAnchor]]]; break;
			default: [a_slot->placing addObjectsFromArray:@[[c.bottomAnchor constraintEqualToAnchor:a_slot.bottomAnchor],
				[c.topAnchor constraintGreaterThanOrEqualToAnchor:a_slot.topAnchor]]]; break;
		}
	}
	/* Unless it fills, the child does not reach across the whole slot; this weak pull makes
	   the stack hug its tallest (or widest) child instead of growing without limit. */
	if (a_alignment != 0) {
		NSLayoutConstraint *k = a_slot->vertical ? [c.widthAnchor constraintEqualToAnchor:a_slot.widthAnchor]
			: [c.heightAnchor constraintEqualToAnchor:a_slot.heightAnchor];
		[k setPriority:NSLayoutPriorityDefaultLow - 1];
		[a_slot->placing addObject:k];
	}
	[NSLayoutConstraint activateConstraints:a_slot->placing];
}

/* Buttons (a dropdown and a split button too), spin boxes, segmented controls and spinners keep their natural width
   (GTK: halign START); everything else fills. */
static int sga_default_alignment(NSView *a_child)
{
	return [a_child isKindOfClass:[NSButton class]] || [a_child isKindOfClass:NSClassFromString(@"SGASpin")]
		|| [a_child isKindOfClass:[NSSegmentedControl class]] || [a_child isKindOfClass:[NSComboButton class]]
		|| ([a_child isKindOfClass:[NSProgressIndicator class]] && [(NSProgressIndicator *)a_child style] == NSProgressIndicatorStyleSpinning) ? 1 : 0;
}

void sga_stack_extend(int a_stack, int a_child, int a_stretch)
{
	NSStackView *s = s_inner[a_stack];
	NSView *v = sga_get(a_child);
	BOOL l_vertical = [s orientation] == NSUserInterfaceLayoutOrientationVertical;
	NSLayoutConstraintOrientation l_main = l_vertical ? NSLayoutConstraintOrientationVertical : NSLayoutConstraintOrientationHorizontal;
	SGASlot *l_slot = [[SGASlot alloc] init];
	if (!s_slots) s_slots = [NSMutableDictionary dictionary];
	l_slot->child = v;
	l_slot->placing = [NSMutableArray array];
	l_slot->vertical = l_vertical;
	[v setTranslatesAutoresizingMaskIntoConstraints:NO];
	[l_slot addSubview:v];
	sga_keep_natural_size(v, a_stretch);
	[v setContentHuggingPriority:a_stretch ? 1 : NSLayoutPriorityDefaultHigh forOrientation:l_main];
	[l_slot setContentHuggingPriority:a_stretch ? 1 : NSLayoutPriorityDefaultHigh forOrientation:l_main];
	l_slot->natural = [v isKindOfClass:[NSButton class]];
	s_slots[[NSValue valueWithNonretainedObject:v]] = l_slot;
	[s addArrangedSubview:l_slot];
	/* Stretching children share the spare room, as in a GTK box: tie each to the first one
	   along the axis, just above their hugging, or Auto Layout gives all of it to one. */
	l_slot->stretches = a_stretch != 0;
	if (a_stretch)
		for (NSView *l_other in [s arrangedSubviews])
			if (l_other != l_slot && [l_other isKindOfClass:[SGASlot class]] && ((SGASlot *)l_other)->stretches) {
				NSLayoutConstraint *l_share = l_vertical ? [l_slot.heightAnchor constraintEqualToAnchor:l_other.heightAnchor]
					: [l_slot.widthAnchor constraintEqualToAnchor:l_other.widthAnchor];
				[l_share setPriority:2];
				[l_share setActive:YES];
				break;
			}
	/* The slot fills the stack across. */
	if (l_vertical) [[l_slot.widthAnchor constraintEqualToAnchor:s.widthAnchor] setActive:YES];
	else [[l_slot.heightAnchor constraintEqualToAnchor:s.heightAnchor] setActive:YES];
	sga_place(l_slot, s_stack_alignment[a_stack] > 0 ? s_stack_alignment[a_stack] - 1 : sga_default_alignment(v));
	if (a_stretch) [sga_end_margin(a_stack) setPriority:NSLayoutPriorityRequired - 1];
}

/* Applies to the existing children and to later ones (stored as alignment + 1; 0 = defaults). */
void sga_stack_set_alignment(int a_stack, int a_alignment)
{
	NSStackView *s = s_inner[a_stack];
	s_stack_alignment[a_stack] = a_alignment + 1;
	for (NSView *l_slot in [s arrangedSubviews]) if ([l_slot isKindOfClass:[SGASlot class]]) sga_place((SGASlot *)l_slot, a_alignment);
}

void sga_stack_align_child(int a_stack, int a_child, int a_alignment)
{
	(void)a_stack;
	SGASlot *l_slot = sga_slot_of(sga_get(a_child));
	if (l_slot) sga_place(l_slot, a_alignment);
}

void sga_stack_set_spacing(int a_stack, int a_spacing) { [(NSStackView *)s_inner[a_stack] setSpacing:a_spacing]; }

int sga_grid(void)
{
	NSGridView *g = [NSGridView gridViewWithNumberOfColumns:0 rows:0];
	[g setRowSpacing:6];
	[g setColumnSpacing:12];
	int l_id = sga_wrap(g, 12);
	/* Like a GTK grid, columns take their natural widths from the start and the spare room
	   is left at the end, unless a column stretches: NSGridView would otherwise hand it to
	   a column of its own choosing (the calculator's keypad split apart). */
	[s_margins[l_id][2] setPriority:NSLayoutPriorityDefaultLow - 2];
	[g setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];
	return l_id;
}

static void sga_grid_columns(int a_grid);

void sga_grid_put(int a_grid, int a_child, int a_row, int a_column, int a_rows, int a_columns)
{
	NSGridView *g = s_inner[a_grid];
	NSInteger l_last_row = a_row + a_rows - 1, l_last_column = a_column + a_columns - 1;
	while ([g numberOfColumns] < l_last_column) {
		NSMutableArray *l_empty = [NSMutableArray array];
		for (NSInteger i = 0; i < [g numberOfRows]; i++) [l_empty addObject:[NSGridCell emptyContentView]];
		[g addColumnWithViews:l_empty];
	}
	while ([g numberOfRows] < l_last_row) {
		NSMutableArray *l_empty = [NSMutableArray array];
		for (NSInteger i = 0; i < [g numberOfColumns]; i++) [l_empty addObject:[NSGridCell emptyContentView]];
		[g addRowWithViews:l_empty];
	}
	sga_keep_natural_size(sga_get(a_child), 0);
	/* A label in a grid is a caption: it keeps its whole width (GTK sizes grid columns the same way). */
	if ([sga_get(a_child) isKindOfClass:NSClassFromString(@"SGALabel")])
		[(NSView *)sga_get(a_child) setContentCompressionResistancePriority:NSLayoutPriorityRequired - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];
	[[g cellAtColumnIndex:a_column - 1 rowIndex:a_row - 1] setContentView:sga_get(a_child)];
	if (a_rows > 1 || a_columns > 1) {
		[g mergeCellsInHorizontalRange:NSMakeRange((NSUInteger)(a_column - 1), (NSUInteger)a_columns)
			verticalRange:NSMakeRange((NSUInteger)(a_row - 1), (NSUInteger)a_rows)];
	}
	sga_grid_columns(a_grid);
}

static int s_grid_homogeneous[SGA_MAX];
static int s_grid_stretching[SGA_MAX];
static NSMutableArray<NSLayoutConstraint *> *s_grid_equal[SGA_MAX];

/* Column widths. Homogeneous columns are kept equal by constraints between one content
   view per column, cells fill their columns, and the grid fills its wrapper: the spare width
   is shared equally (as GTK does), and the grid can still shrink back to the widest natural
   width (fixed column widths would hold a window wide). Homogeneous takes precedence over a
   stretching column. With a stretching column, the others are fixed at their natural width
   and it alone takes the spare width. Recomputed whenever a cell is put. */
static void sga_grid_columns(int a_grid)
{
	NSGridView *g = s_inner[a_grid];
	NSInteger n = [g numberOfColumns];
	CGFloat l_natural[256] = {0};
	if (n > 256) n = 256;
	if (s_grid_equal[a_grid]) { [NSLayoutConstraint deactivateConstraints:s_grid_equal[a_grid]]; [s_grid_equal[a_grid] removeAllObjects]; }
	if (!s_grid_homogeneous[a_grid] && !s_grid_stretching[a_grid]) return;
	if (s_grid_homogeneous[a_grid]) {
		NSView *l_first = nil;
		if (!s_grid_equal[a_grid]) s_grid_equal[a_grid] = [NSMutableArray array];
		for (NSInteger c = 0; c < n; c++) {
			NSGridColumn *k = [g columnAtIndex:c];
			[k setWidth:NSGridViewSizeForContent];
			[k setXPlacement:NSGridCellPlacementFill];
			/* One single-column cell's view stands for the column (a merged cell's view
			   also sits in its neighbors, so it is skipped). */
			NSView *l_view = nil;
			for (NSInteger r = 0; r < [g numberOfRows] && !l_view; r++) {
				NSView *v = [[g cellAtColumnIndex:c rowIndex:r] contentView];
				BOOL l_merged = (c > 0 && [[g cellAtColumnIndex:c - 1 rowIndex:r] contentView] == v)
					|| (c + 1 < [g numberOfColumns] && [[g cellAtColumnIndex:c + 1 rowIndex:r] contentView] == v);
				if (v && v != [NSGridCell emptyContentView] && !l_merged) l_view = v;
			}
			if (l_view && l_first) [s_grid_equal[a_grid] addObject:[l_view.widthAnchor constraintEqualToAnchor:l_first.widthAnchor]];
			else if (l_view) l_first = l_view;
		}
		[NSLayoutConstraint activateConstraints:s_grid_equal[a_grid]];
		return;
	}
	for (NSInteger c = 0; c < n; c++)
		for (NSInteger r = 0; r < [g numberOfRows]; r++) {
			NSView *v = [[g cellAtColumnIndex:c rowIndex:r] contentView];
			if (v && v != [NSGridCell emptyContentView]) l_natural[c] = MAX(l_natural[c], [v fittingSize].width);
		}
	for (NSInteger c = 0; c < n; c++) {
		NSGridColumn *k = [g columnAtIndex:c];
		if (c + 1 == s_grid_stretching[a_grid]) { [k setWidth:NSGridViewSizeForContent]; [k setXPlacement:NSGridCellPlacementFill]; }
		else [k setWidth:ceil(l_natural[c])];
	}
}

/* A grid fills its wrapper (its end margin holds) while it has homogeneous or stretching
   columns; otherwise it packs at the start, as a GTK grid does. */
static void sga_grid_fill(int a_grid)
{
	BOOL l_fill = s_grid_homogeneous[a_grid] || s_grid_stretching[a_grid] > 0;
	[s_margins[a_grid][2] setPriority:l_fill ? NSLayoutPriorityRequired - 1 : NSLayoutPriorityDefaultLow - 2];
}

void sga_grid_set_homogeneous_columns(int a_grid, int a_on)
{
	s_grid_homogeneous[a_grid] = a_on != 0;
	if (!a_on) for (NSInteger c = 0; c < [(NSGridView *)s_inner[a_grid] numberOfColumns]; c++)
		[[(NSGridView *)s_inner[a_grid] columnAtIndex:c] setWidth:NSGridViewSizeForContent];
	sga_grid_fill(a_grid);
	sga_grid_columns(a_grid);
}

void sga_grid_set_stretching_column(int a_grid, int a_column)
{
	s_grid_stretching[a_grid] = a_column;
	sga_grid_fill(a_grid);
	sga_grid_columns(a_grid);
}

void sga_grid_set_spacing(int a_grid, int a_row_gap, int a_column_gap)
{
	NSGridView *g = s_inner[a_grid];
	[g setRowSpacing:a_row_gap];
	[g setColumnSpacing:a_column_gap];
}

/* Splitter: an NSSplitView with two holder panes made up front, so pane 1 is always the
   leading (or top) one whichever is filled first; each widget is pinned inside its holder.
   The first pane holds its size when the splitter grows. A position set before the view
   has a size is kept and applied at the first layout (NSSplitView clamps it to nothing
   otherwise). Positions count from the leading edge, which NSSplitView itself puts on the right
   under right-to-left layout. */
static void sga_split_apply(NSSplitView *s, NSInteger a_position);

@interface SGASplit : NSSplitView <NSSplitViewDelegate>
{
@public
	NSInteger pending;   /* -1: none; -2: halfway, at the first layout (until set_position) */
	/* 1r-c: collapsible panes. A collapsed pane is a hidden subview (NSSplitView's own
	   collapse), its divider staying; expanding puts the divider back where it was. Only the
	   divider's button and a double click on it collapse; a drag can open a collapsed pane. */
	BOOL collapsible[3];
	int collapsed;               /* 0 none, else the collapsed pane */
	NSInteger kept;              /* the position before collapsing */
	NSButton *arrow[3];          /* on the divider, pointing toward its pane */
}
- (void)userToggle:(int)a_pane;
@end
static void sga_split_collapse(SGASplit *s, int a_pane, BOOL a_on);
@implementation SGASplit
- (void)layout
{
	[super layout];
	if (pending != -1 && NSWidth([self bounds]) > 0 && NSHeight([self bounds]) > 0) {
		NSInteger p = pending >= 0 ? pending : (NSInteger)(([self isVertical] ? NSWidth([self bounds]) : NSHeight([self bounds])) / 2);
		pending = -1;
		sga_split_apply(self, p);
	}
	[self placeArrows];
}
/* The buttons sit centered on the divider, one per collapsible pane; while one pane is
   collapsed only its button shows, pointing back toward where it opens. */
- (void)placeArrows
{
	NSRect d = NSZeroRect;
	NSView *l_first = [self arrangedSubviews][0];
	BOOL v = [self isVertical];
	CGFloat at = [l_first isHidden] ? 0 : (v ? NSMaxX([l_first frame]) : NSMaxY([l_first frame]));
	d = v ? NSMakeRect(at, 0, [self dividerThickness], NSHeight([self bounds])) : NSMakeRect(0, at, NSWidth([self bounds]), [self dividerThickness]);
	int l_shown = 0;
	for (int k = 1; k <= 2; k++) {
		NSButton *b = arrow[k];
		BOOL l_show = collapsible[k] && (!collapsed || collapsed == k);
		[b setHidden:!l_show];
		if (!l_show) continue;
		/* toward the pane when it is open, away from it when collapsed */
		BOOL l_toward_first = (k == 1) != (collapsed == k);
		NSString *l_name = v ? (l_toward_first ? @"chevron.left" : @"chevron.right") : (l_toward_first ? @"chevron.up" : @"chevron.down");
		[b setImage:[NSImage imageWithSystemSymbolName:l_name accessibilityDescription:collapsed == k ? @"Expand" : @"Collapse"]];
		CGFloat c = (v ? NSMidY(d) : NSMidX(d)) + (l_shown ? 16 : 0) - (collapsible[1] && collapsible[2] && !collapsed ? 8 : 0);
		[b setFrame:v ? NSMakeRect(NSMidX(d) - 7, c - 7, 14, 14) : NSMakeRect(c - 7, NSMidY(d) - 7, 14, 14)];
		l_shown++;
	}
}
- (void)arrowPressed:(NSButton *)b { [self userToggle:(int)[b tag]]; }
- (void)userToggle:(int)a_pane
{
	if (!collapsible[a_pane] || (collapsed && collapsed != a_pane)) return;
	BOOL l_on = collapsed != a_pane;
	sga_split_collapse(self, a_pane, l_on);
	sga_push(42, sga_id_of(self), a_pane, l_on ? 1 : 0, 0);
	sga_wake();
}
/* Only the collapsed pane may be collapsed in NSSplitView's eyes: a drag can then open it,
   and no drag can collapse a pane. */
- (BOOL)splitView:(NSSplitView *)v canCollapseSubview:(NSView *)a_sub
{
	(void)v;
	return collapsed && a_sub == [self arrangedSubviews][(NSUInteger)collapsed - 1];
}
/* A double click on the divider: the collapsible pane (the first when both are), ours. */
- (BOOL)splitView:(NSSplitView *)v shouldCollapseSubview:(NSView *)a_sub forDoubleClickOnDividerAtIndex:(NSInteger)i
{
	(void)v; (void)a_sub; (void)i;
	if ([[NSApp currentEvent] type] == NSEventTypeLeftMouseDown || [[NSApp currentEvent] clickCount] == 2) {
		int k = collapsed ? collapsed : collapsible[1] ? 1 : collapsible[2] ? 2 : 0;
		if (k) [self userToggle:k];
	}
	return NO;
}
/* A drag that opened a collapsed pane: it is expanded now (42, b = 0). */
- (void)splitViewDidResizeSubviews:(NSNotification *)n
{
	if (collapsed && ![[self arrangedSubviews][(NSUInteger)collapsed - 1] isHidden] && [n userInfo][@"NSSplitViewDividerIndex"]) {
		int k = collapsed;
		collapsed = 0;
		sga_push(42, sga_id_of(self), k, 0, 0);
		sga_wake();
	}
	[self placeArrows];
}
@end

/* Silent: collapse pane `a_pane' (keeping the position) or expand it back. A pane cannot
   collapse while the other is. */
static void sga_split_collapse(SGASplit *s, int a_pane, BOOL a_on)
{
	NSView *h = [s arrangedSubviews][(NSUInteger)a_pane - 1];
	if (a_on) {
		if (s->collapsed) return;
		NSView *l_first = [s arrangedSubviews][0];
		s->kept = (NSInteger)lround([s isVertical] ? NSWidth([l_first frame]) : NSHeight([l_first frame]));
		s->collapsed = a_pane;
		[h setHidden:YES];
		[s adjustSubviews];
	} else if (s->collapsed == a_pane) {
		s->collapsed = 0;
		[h setHidden:NO];
		[s adjustSubviews];
		sga_split_apply(s, s->kept);
	}
	[s placeArrows];
}

static void sga_split_apply(NSSplitView *s, NSInteger a_position)
{
	[s setPosition:(CGFloat)a_position ofDividerAtIndex:0];   /* NSSplitView counts from the leading edge itself under right to left */
}

int sga_splitter(int a_vertical)
{
	SGASplit *s = [[SGASplit alloc] init];
	s->pending = -2;   /* the divider starts halfway, as GUI_SPLITTER's note says */
	[s setVertical:a_vertical == 0];   /* NSSplitView's "vertical" means vertical dividers: side by side */
	[s setDividerStyle:NSSplitViewDividerStyleThin];
	[s setArrangesAllSubviews:NO];   /* 1r-c: the divider's buttons are subviews, not panes */
	[s setDelegate:s];
	[s addArrangedSubview:[[NSView alloc] init]];
	[s addArrangedSubview:[[NSView alloc] init]];
	for (int k = 1; k <= 2; k++) {
		s->arrow[k] = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"chevron.left" accessibilityDescription:@"Collapse"] target:s action:@selector(arrowPressed:)];
		[s->arrow[k] setBordered:NO];
		[s->arrow[k] setTag:k];
		[s->arrow[k] setHidden:YES];
		[s->arrow[k] setTranslatesAutoresizingMaskIntoConstraints:YES];
		[s addSubview:s->arrow[k]];
	}
	[s setHoldingPriority:NSLayoutPriorityDefaultLow + 1 forSubviewAtIndex:0];
	[s setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:1];
	return sga_keep(s);
}

void sga_splitter_set_pane(int a_splitter, int a_pane, int a_child)
{
	NSSplitView *s = sga_get(a_splitter);
	NSView *l_holder = [s arrangedSubviews][(NSUInteger)(a_pane - 1)];
	NSView *v = sga_get(a_child);
	[v setTranslatesAutoresizingMaskIntoConstraints:NO];
	/* as a window's content: a lone label in a pane must not pull the window to its height */
	for (NSInteger o = 0; o < 2; o++)
		if ([v contentHuggingPriorityForOrientation:o] >= NSLayoutPriorityWindowSizeStayPut)
			[v setContentHuggingPriority:NSLayoutPriorityWindowSizeStayPut - 1 forOrientation:o];
	[l_holder addSubview:v];
	[NSLayoutConstraint activateConstraints:@[
		[v.leadingAnchor constraintEqualToAnchor:l_holder.leadingAnchor], [v.trailingAnchor constraintEqualToAnchor:l_holder.trailingAnchor],
		[v.topAnchor constraintEqualToAnchor:l_holder.topAnchor], [v.bottomAnchor constraintEqualToAnchor:l_holder.bottomAnchor]]];
}

int sga_splitter_position(int a_splitter)
{
	NSSplitView *s = sga_get(a_splitter);
	NSView *l_first = [s arrangedSubviews][0];
	[[[s window] contentView] layoutSubtreeIfNeeded];
	return (int)lround([s isVertical] ? NSWidth([l_first frame]) : NSHeight([l_first frame]));
}

void sga_splitter_set_position(int a_splitter, int a_position)
{
	SGASplit *s = sga_get(a_splitter);
	if (NSWidth([s bounds]) > 0 && NSHeight([s bounds]) > 0) { s->pending = -1; sga_split_apply(s, a_position); }
	else { s->pending = a_position; [s setNeedsLayout:YES]; }
}

/* --------------------------------------------------------------- controls */

/* A label is one line in 0.1 (wrapping comes in 0.2) and gives way before anything
   else, a canvas included: a long label ends in "\u2026" instead of widening its
   container. */
@interface SGALabel : NSTextField
@end
@implementation SGALabel
@end

int sga_label(const char *a_text)
{
	SGALabel *l = [SGALabel labelWithString:sga_string(a_text)];
	[l setLineBreakMode:NSLineBreakByTruncatingTail];
	[l setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 2 forOrientation:NSLayoutConstraintOrientationHorizontal];
	return sga_keep(l);
}
/* Wrapping at about `a_characters' wide: an explicit width, from the font's average
   character width, so Auto Layout cannot collapse the label to one character per line
   (what an automatic preferredMaxLayoutWidth did in a grid). 0 goes back to one line
   ending in "\u2026". */
void sga_label_set_wrap_width(int a_id, int a_characters)
{
	NSTextField *l = sga_get(a_id);
	if (a_characters > 0) {
		NSString *l_sample = @"abcdefghijklmnopqrstuvwxyz0123456789";
		CGFloat l_average = [l_sample sizeWithAttributes:@{NSFontAttributeName: [l font]}].width / [l_sample length];
		[l setLineBreakMode:NSLineBreakByWordWrapping];
		[[l cell] setWraps:YES];
		[l setUsesSingleLineMode:NO];
		[l setMaximumNumberOfLines:0];
		[l setPreferredMaxLayoutWidth:ceil(l_average * a_characters)];
		[l setContentCompressionResistancePriority:NSLayoutPriorityRequired - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];
	} else {
		[l setLineBreakMode:NSLineBreakByTruncatingTail];
		[[l cell] setWraps:NO];
		[l setUsesSingleLineMode:YES];
		[l setMaximumNumberOfLines:1];
		[l setPreferredMaxLayoutWidth:0];
		[l setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 2 forOrientation:NSLayoutConstraintOrientationHorizontal];
	}
	[l invalidateIntrinsicContentSize];
}

void sga_label_set(int a_id, const char *a_text) { [(NSTextField *)sga_get(a_id) setStringValue:sga_string(a_text)]; }
const char *sga_label_get(int a_id) { return sga_return(Kind_label, [(NSTextField *)sga_get(a_id) stringValue]); }

/* A toolbar button's item, by button: its label (the overflow menu's text) and enabled state follow the button. */
static NSMapTable<NSButton *, NSToolbarItem *> *s_toolbar_item;

int sga_button(const char *a_text)
{
	return sga_keep([NSButton buttonWithTitle:sga_string(a_text) target:s_target action:@selector(clicked:)]);
}
void sga_button_set(int a_id, const char *a_text)
{
	NSButton *b = sga_get(a_id);
	[b setTitle:sga_string(a_text)];
	[[s_toolbar_item objectForKey:b] setLabel:[b title]];
}
const char *sga_button_get(int a_id) { return sga_return(Kind_button, [(NSButton *)sga_get(a_id) title]); }

/* A check box: a switch button. Setting its state from code sends no action (silent); a
   click, by a user or the test driver, toggles it and sends toggled (12). */
int sga_check_box(const char *a_text)
{
	return sga_keep([NSButton checkboxWithTitle:sga_string(a_text) target:s_target action:@selector(toggled:)]);
}
void sga_check_box_set(int a_id, int a_on) { [(NSButton *)sga_get(a_id) setState:a_on ? NSControlStateValueOn : NSControlStateValueOff]; }
int sga_check_box_is_checked(int a_id) { return [(NSButton *)sga_get(a_id) state] == NSControlStateValueOn; }
void sga_check_box_set_text(int a_id, const char *a_text) { [(NSButton *)sga_get(a_id) setTitle:sga_string(a_text)]; }
const char *sga_check_box_text(int a_id) { return sga_return(Kind_check, [(NSButton *)sga_get(a_id) title]); }

/* Tabs: an NSTabView. Each page sits in a holder view the tab view sizes; the page is pinned
   inside it, and the tab view is held at least as large as the page needs (its own inset
   around the tallest and widest page), so a stack can lay it out like any other widget.
   Choosing a tab sends page changed (13); selecting from code sends nothing. */
/* NSTabView lays its tabs out left to right whatever its own direction (it follows the
   application's language only), so under right to left the backend keeps the items in
   reverse order itself: page p (1-based, the program's numbering) is item count - p. */
static BOOL sga_tabs_reversed(NSTabView *t) { return [t userInterfaceLayoutDirection] == NSUserInterfaceLayoutDirectionRightToLeft; }
static NSInteger sga_tab_item(NSTabView *t, int a_page) { return sga_tabs_reversed(t) ? (NSInteger)[t numberOfTabViewItems] - a_page : a_page - 1; }
static int sga_tab_page(NSTabView *t, NSInteger an_item) { return sga_tabs_reversed(t) ? (int)([t numberOfTabViewItems] - an_item) : (int)an_item + 1; }

@class SGANavList;
static SGANavList *sga_nav_list_new(int a_owner, BOOL a_full);
static void sga_nav_list_reload(SGANavList *l);
/* 1t: tabs placed left or right: a tabless NSTabView with a strip of its titles inside it,
   on that side (AppKit's own left and right tabs draw rotated, dated tabs). */
@interface SGATabs : NSTabView
{
@public
	int position;          /* 1 top, 2 bottom, 3 left, 4 right, 0 none */
	NSScrollView *strip;   /* left and right: the titles */
	SGANavList *titles;
}
@end
@implementation SGATabs
- (NSRect)contentRect
{
	NSRect r = [super contentRect];
	if (position == 3 || position == 4) {
		CGFloat w = 140, m = 12;   /* the strip, then a margin around the page, as top tabs leave */
		r = NSInsetRect([self bounds], m, m);
		r.size.width -= w;
		if (position == 3) r.origin.x += w;
	}
	return r;
}
- (void)layout
{
	[super layout];
	if (strip) {
		NSRect b = [self bounds];
		[strip setFrame:position == 3 ? NSMakeRect(0, 0, 140, b.size.height) : NSMakeRect(b.size.width - 140, 0, 140, b.size.height)];
	}
}
@end

/* A page in its holder (a tab's or a sidebar's): it fills the holder, but its own wish to be
   small (a label's hugging) must not pull the holder, the tab view and the window down with it,
   so the trailing and bottom edges hold just below the window's keep-its-size priority. */
static void sga_pin_page(NSView *v, NSView *a_holder)
{
	NSLayoutConstraint *l_trailing = [v.trailingAnchor constraintEqualToAnchor:a_holder.trailingAnchor];
	NSLayoutConstraint *l_bottom = [v.bottomAnchor constraintEqualToAnchor:a_holder.bottomAnchor];
	[l_trailing setPriority:NSLayoutPriorityWindowSizeStayPut - 1];
	[l_bottom setPriority:NSLayoutPriorityWindowSizeStayPut - 1];
	[NSLayoutConstraint activateConstraints:@[
		[v.leadingAnchor constraintEqualToAnchor:a_holder.leadingAnchor], [v.topAnchor constraintEqualToAnchor:a_holder.topAnchor],
		[v.trailingAnchor constraintLessThanOrEqualToAnchor:a_holder.trailingAnchor], [v.bottomAnchor constraintLessThanOrEqualToAnchor:a_holder.bottomAnchor],
		l_trailing, l_bottom]];
}

int sga_tabs(void)
{
	NSTabView *t = [[SGATabs alloc] init];
	((SGATabs *)t)->position = 1;
	[t setDelegate:(id<NSTabViewDelegate>)s_target];
	return sga_keep(t);
}
void sga_tabs_extend(int a_tabs, int a_page, const char *a_title)
{
	NSTabView *t = sga_get(a_tabs);
	NSView *v = sga_get(a_page);
	NSView *l_holder = [[NSView alloc] init];
	NSTabViewItem *i = [[NSTabViewItem alloc] initWithIdentifier:nil];
	[v setTranslatesAutoresizingMaskIntoConstraints:NO];
	[l_holder addSubview:v];
	sga_pin_page(v, l_holder);
	[i setLabel:sga_string(a_title)];
	[i setView:l_holder];
	s_suppress++;
	if (sga_tabs_reversed(t)) [t insertTabViewItem:i atIndex:0]; else [t addTabViewItem:i];
	s_suppress--;
	sga_tabs_titles_follow(t);
	/* The tab view keeps room for this page: its content rect is inset from its bounds by the
	   tab row and border, so the page's fitting size plus that inset is a minimum. */
	NSSize l_fit = [v fittingSize];
	NSRect l_content = [t contentRect], l_bounds = [t bounds];
	CGFloat l_dw = NSWidth(l_bounds) - NSWidth(l_content), l_dh = NSHeight(l_bounds) - NSHeight(l_content);
	if (l_dw <= 0) l_dw = 14;
	if (l_dh <= 0) l_dh = 36;
	[[t.widthAnchor constraintGreaterThanOrEqualToConstant:l_fit.width + l_dw] setActive:YES];
	[[t.heightAnchor constraintGreaterThanOrEqualToConstant:l_fit.height + l_dh] setActive:YES];
}
void sga_tabs_select(int a_tabs, int a_page)
{
	s_suppress++;
	NSTabView *t = sga_get(a_tabs);
	[t selectTabViewItemAtIndex:sga_tab_item(t, a_page)];
	s_suppress--;
}
int sga_tabs_selected(int a_tabs)
{
	NSTabView *t = sga_get(a_tabs);
	NSTabViewItem *i = [t selectedTabViewItem];
	NSInteger n = i ? [t indexOfTabViewItem:i] : NSNotFound;
	return n == NSNotFound ? 0 : sga_tab_page(t, n);
}
void sga_tabs_set_title(int a_tabs, int a_page, const char *a_title)
{
	{ NSTabView *t = sga_get(a_tabs); [[t tabViewItemAtIndex:sga_tab_item(t, a_page)] setLabel:sga_string(a_title)]; sga_tabs_titles_follow(t); }
}

int sga_field(void)
{
	NSTextField *f = [NSTextField textFieldWithString:@""];
	[f setDelegate:s_target];
	[f setTarget:s_target];
	[f setAction:@selector(activated:)];
	return sga_keep(f);
}

/* A text area: an NSTextView in a bordered scroll view. The scroll view is the widget (it is
   what a stack places and what x/y measure); the text view is its core, so the accessible
   label and the role are the text view's. Typing sends text changed (2); setting the text
   from code sends nothing (AppKit sends textDidChange only for the user's edits). */
int sga_text_area(void)
{
	NSScrollView *l_scroll = [NSTextView scrollableTextView];
	NSTextView *t = [l_scroll documentView];
	[l_scroll setBorderType:NSBezelBorder];
	[l_scroll setHasVerticalScroller:YES];
	[l_scroll setAutohidesScrollers:YES];
	[t setFont:[NSFont systemFontOfSize:0]];
	[t setRichText:NO];
	[t setAllowsUndo:YES];
	[t setAutomaticQuoteSubstitutionEnabled:NO];
	[t setAutomaticDashSubstitutionEnabled:NO];
	[t setDelegate:(id<NSTextViewDelegate>)s_target];
	/* No natural height of its own: ask for a few lines, weakly, so a stack can give it more. */
	NSLayoutConstraint *k = [l_scroll.heightAnchor constraintGreaterThanOrEqualToConstant:64];
	[k setPriority:NSLayoutPriorityDefaultHigh];
	[k setActive:YES];
	int l_id = sga_keep(l_scroll);
	s_inner[l_id] = t;
	return l_id;
}
void sga_text_area_set(int a_id, const char *a_text)
{
	sga_colors_flush();
	s_suppress++;
	[(NSTextView *)sga_core(a_id) setString:sga_string(a_text)];
	s_suppress--;
}
const char *sga_text_area_get(int a_id) { return sga_return(Kind_area, [(NSTextView *)sga_core(a_id) string]); }
void sga_text_area_set_read_only(int a_id, int a_on) { [(NSTextView *)sga_core(a_id) setEditable:a_on == 0]; }

static NSTextField *sga_text_field(int a_id);   /* 1p: a password field's shown field */

void sga_field_set(int a_id, const char *a_text)
{
	s_suppress++;
	[sga_text_field(a_id) setStringValue:sga_string(a_text)];
	s_suppress--;
}

const char *sga_field_get(int a_id) { return sga_return(Kind_field, [sga_text_field(a_id) stringValue]); }
void sga_field_set_placeholder(int a_id, const char *a_text)
{
	id o = sga_get(a_id);
	if ([o isKindOfClass:NSClassFromString(@"SGAPassword")]) for (NSView *v in [o subviews]) { if ([v isKindOfClass:[NSTextField class]]) [(NSTextField *)v setPlaceholderString:sga_string(a_text)]; }
	else [(NSTextField *)o setPlaceholderString:sga_string(a_text)];
}

/* A list's, table's or tree's scroll view: its natural height is its rows' (as a GTK list's
   is), so a stack placing it at its natural size gives it room for them; it gives way before
   the window grows (low compression resistance), and follows its rows as they change. */
@interface SGARowsScroll : NSScrollView
@end
@implementation SGARowsScroll
- (instancetype)init
{
	if ((self = [super init])) [self setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationVertical];
	return self;
}
- (void)setDocumentView:(NSView *)v
{
	[super setDocumentView:v];
	[v setPostsFrameChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rowsChanged:) name:NSViewFrameDidChangeNotification object:v];
}
- (void)rowsChanged:(NSNotification *)n { (void)n; [self invalidateIntrinsicContentSize]; }
- (NSSize)intrinsicContentSize
{
	NSTableView *t = [self documentView];
	if (![t isKindOfClass:[NSTableView class]]) return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric);
	CGFloat h = [t numberOfRows] > 0 ? NSMaxY([t rectOfRow:[t numberOfRows] - 1]) : [t rowHeight];
	h += [[t headerView] frame].size.height + 4;   /* the header, and the bezel and insets */
	return NSMakeSize(NSViewNoIntrinsicMetric, ceil(h));
}
@end

/* A list's table (1s): Space toggles the selected row's check box (43); Delete, or
   Command+Backspace, closes it (44), as their buttons do. */
static void sga_list_user_check(NSTableView *t, NSInteger a_model);
static void sga_list_user_close(NSTableView *t, NSInteger a_model);
@interface SGAListTable : NSTableView
@end
@implementation SGAListTable
- (void)keyDown:(NSEvent *)e
{
	NSInteger m = sga_model_row(self, [self selectedRow]);
	id l_row = m >= 0 ? [s_target rowsOf:self][(NSUInteger)m] : nil;
	if ([l_row isKindOfClass:[SGARichRow class]]) {
		SGARichRow *r = l_row;
		BOOL l_space = [[e charactersIgnoringModifiers] isEqualToString:@" "];
		BOOL l_delete = [e keyCode] == 117 || ([e keyCode] == 51 && ([e modifierFlags] & NSEventModifierFlagCommand));
		if (l_space && r->checkable) { sga_list_user_check(self, m); return; }
		if (l_delete && r->closable) { sga_list_user_close(self, m); return; }
	}
	[super keyDown:e];
}
@end

int sga_list(void)
{
	NSScrollView *l_scroll = [[SGARowsScroll alloc] init];
	NSTableView *t = [[SGAListTable alloc] init];
	NSTableColumn *k = [[NSTableColumn alloc] initWithIdentifier:@"sga_column"];
	[k setResizingMask:NSTableColumnAutoresizingMask];
	[t addTableColumn:k];
	[t setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
	[t setHeaderView:nil];
	[t setStyle:NSTableViewStyleInset];
	s_target->rows[[NSValue valueWithNonretainedObject:t]] = [NSMutableArray array];
	[t setDataSource:s_target];
	[t setDelegate:s_target];
	[l_scroll setDocumentView:t];
	[l_scroll setHasVerticalScroller:YES];
	[l_scroll setBorderType:NSBezelBorder];
	int l_id = sga_keep(l_scroll);
	s_inner[l_id] = t;
	return l_id;
}

static void sga_list_refilter(NSTableView *t);

void sga_list_extend(int a_id, const char *a_text)
{
	NSTableView *t = s_inner[a_id];
	[[s_target rowsOf:t] addObject:sga_string(a_text)];
	sga_list_refilter(t);
}

void sga_list_wipe_out(int a_id)
{
	NSTableView *t = s_inner[a_id];
	[[s_target rowsOf:t] removeAllObjects];
	sga_list_refilter(t);
}

void sga_list_select(int a_id, int a_row)
{
	NSTableView *t = s_inner[a_id];
	NSInteger v = a_row > 0 ? sga_view_row(t, a_row - 1) : -1;
	s_suppress++;
	if (v < 0) [t deselectAll:nil];
	else [t selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)v] byExtendingSelection:NO];
	s_suppress--;
}

int sga_list_selected(int a_id) { NSTableView *t = s_inner[a_id]; return (int)sga_model_row(t, [t selectedRow]) + 1; }

/* Tables: an NSTableView subclass that is its own data source and delegate, holding its rows
   (one NSArray of cell texts each). Columns cannot be reordered, so indices stay those of the
   program. A user's selection sends selection (4, a = the first selected row); a click on a
   header sends header clicked (14, a = column); the program sorts and refills, and the
   sort indicator is set from code. Programmatic changes send nothing. */
@interface SGAGridTable : NSTableView <NSTableViewDataSource, NSTableViewDelegate>
{
@public
	NSMutableArray<NSArray<NSString *> *> *data;
	/* Lazy rows (1f): the count, the rows held (a bounded cache by row index from 0), and
	   the rows asked for but not yet answered. */
	BOOL source_on;
	NSInteger source_count;
	NSMutableDictionary<NSNumber *, NSArray<NSString *> *> *cache;
	NSMutableIndexSet *pending;
	/* 1s: editing and filtering */
	NSMutableDictionary<NSNumber *, NSNumber *> *editor;          /* column (from 1) -> 1 text, 2 check, 3 choice */
	NSMutableDictionary<NSNumber *, NSArray<NSString *> *> *choices;
	NSString *filter;      /* a held table's filter text, and the columns it reads (a mask; 0 all) */
	int filter_columns;
	NSString *edit_text;   /* the last committed edit, for table_take_edit */
	NSInteger edit_row, edit_column;   /* model row (from 0), column (from 1) */
	NSString *edit_old;
	BOOL editing_allowed;  /* a text cell edits only after a double click, Return or F2 */
	NSTextField *note;     /* a refused edit's message, until the next edit in this table */
}
- (void)wantRowsNear:(NSInteger)a_row;
@end
static void sga_table_commit(SGAGridTable *t, NSInteger a_model, NSInteger a_column, NSString *a_text);
@implementation SGAGridTable
- (NSInteger)numberOfRowsInTableView:(NSTableView *)a_table
{
	NSArray *m = sga_shown_map(a_table);
	return m ? (NSInteger)[m count] : (source_on ? source_count : (NSInteger)[data count]);
}

/* Rows wanted (16) for the rows in view plus a viewful either side, those neither held nor
   already asked for; once per range, never for a count of 0. Rows far from the view are
   dropped from the cache. */
- (void)wantRowsNear:(NSInteger)a_row
{
	if (!source_on || source_count <= 0) return;
	NSRange v = [self rowsInRect:[self visibleRect]];
	if (v.length == 0) v = NSMakeRange((NSUInteger)a_row, 40);
	NSInteger l_margin = (NSInteger)MAX(v.length, (NSUInteger)20);
	if (sga_shown_map(self)) {
		/* 1s: filtered, the rows near the view are model rows, maybe far apart: ask for each run */
		NSInteger l_lo = MAX((NSInteger)0, (NSInteger)v.location - l_margin), l_hi = MIN([self numberOfRows] - 1, (NSInteger)NSMaxRange(v) + l_margin - 1);
		NSInteger lo = -1, hi = -1, l_runs = 0;
		for (NSInteger s = l_lo; s <= l_hi + 1 && l_runs < 50; s++) {
			NSInteger m = s <= l_hi ? sga_model_row(self, s) : -1;
			BOOL l_want = m >= 0 && !cache[@(m)] && ![pending containsIndex:(NSUInteger)m];
			if (l_want && lo >= 0 && m == hi + 1) { hi = m; continue; }
			if (lo >= 0) { [pending addIndexesInRange:NSMakeRange((NSUInteger)lo, (NSUInteger)(hi - lo + 1))]; sga_push(16, sga_id_of(self), (int)lo + 1, (int)hi + 1, 0); l_runs++; }
			lo = l_want ? m : -1; hi = lo;
		}
		return;
	}
	NSInteger l_first = MAX((NSInteger)0, (NSInteger)v.location - l_margin);
	NSInteger l_last = MIN(source_count - 1, (NSInteger)NSMaxRange(v) + l_margin - 1);
	NSInteger lo = -1, hi = -1;
	for (NSInteger r = l_first; r <= l_last; r++) {
		if (cache[@(r)] || [pending containsIndex:(NSUInteger)r]) continue;
		if (lo < 0) lo = r;
		hi = r;
	}
	if (lo < 0) return;
	[pending addIndexesInRange:NSMakeRange((NSUInteger)lo, (NSUInteger)(hi - lo + 1))];
	sga_push(16, sga_id_of(self), (int)lo + 1, (int)hi + 1, 0);
	if ([cache count] > 2000) {   /* the bound every backend keeps (docs/lazy-tables.md) */
		NSInteger l_keep_lo = l_first - 4 * l_margin, l_keep_hi = l_last + 4 * l_margin;
		for (NSNumber *k in [cache allKeys]) if ([k integerValue] < l_keep_lo || [k integerValue] > l_keep_hi) [cache removeObjectForKey:k];
	}
}
- (NSView *)tableView:(NSTableView *)a_table viewForTableColumn:(NSTableColumn *)a_column row:(NSInteger)a_row
{
	NSUInteger k = [[a_table tableColumns] indexOfObject:a_column];
	NSInteger l_model = sga_model_row(a_table, a_row);
	NSArray<NSString *> *l_row = l_model < 0 ? nil : source_on ? cache[@(l_model)] : (l_model < (NSInteger)[data count] ? data[(NSUInteger)l_model] : nil);
	if (source_on && !l_row) [self wantRowsNear:a_row];
	NSString *l_text = k < [l_row count] ? l_row[k] : @"";
	int l_kind = [editor[@(k + 1)] intValue];
	if (l_kind == 2) {   /* 1s: a check cell, toggled by a click: commits at once */
		NSButton *b = [a_table makeViewWithIdentifier:@"sga_grid_check" owner:self];
		if (!b) { b = [NSButton checkboxWithTitle:@"" target:self action:@selector(cellChecked:)]; [b setIdentifier:@"sga_grid_check"]; }
		[b setState:[l_text isEqualToString:@"1"] ? NSControlStateValueOn : NSControlStateValueOff];
		[b setTag:(NSInteger)k + 1];
		return b;
	}
	if (l_kind == 3) {   /* a choice cell: commits on change */
		NSPopUpButton *b = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
		[b setBordered:NO];
		[b addItemsWithTitles:choices[@(k + 1)] ?: @[]];
		if (![b itemWithTitle:l_text] && [l_text length]) [b addItemWithTitle:l_text];
		[b selectItemWithTitle:l_text];
		[b setTarget:self];
		[b setAction:@selector(cellChosen:)];
		[b setTag:(NSInteger)k + 1];
		return b;
	}
	NSTextField *f = [a_table makeViewWithIdentifier:l_kind == 1 ? @"sga_grid_edit" : @"sga_grid_cell" owner:self];
	if (!f) {
		f = [NSTextField labelWithString:@""];
		[f setIdentifier:l_kind == 1 ? @"sga_grid_edit" : @"sga_grid_cell"];
		[f setLineBreakMode:NSLineBreakByTruncatingTail];
		if (l_kind == 1) { [f setEditable:YES]; [f setDelegate:(id<NSTextFieldDelegate>)self]; [f setTag:(NSInteger)k + 1]; }
	}
	[f setStringValue:l_text];
	[f setAlignment:sga_start_alignment(a_table)];
	return f;
}
- (void)tableViewSelectionDidChange:(NSNotification *)n
{
	if (s_suppress) return;
	NSUInteger l_first = [[self selectedRowIndexes] firstIndex];
	sga_push(4, sga_id_of(self), l_first == NSNotFound ? 0 : (int)sga_model_row(self, (NSInteger)l_first) + 1, 0, 0);
}
/* 1s editing: a text cell takes the focus only after a double click, Return or F2. */
- (BOOL)validateProposedFirstResponder:(NSResponder *)r forEvent:(NSEvent *)e
{
	if ([r isKindOfClass:[NSTextField class]] && [[(NSTextField *)r identifier] isEqualToString:@"sga_grid_edit"] && !editing_allowed) return NO;
	return [super validateProposedFirstResponder:r forEvent:e];
}
- (void)editAt:(NSInteger)a_view column:(NSInteger)a_column
{
	if (a_view < 0 || a_column < 1) return;
	int l_kind = [editor[@(a_column)] intValue];
	[note removeFromSuperview];
	note = nil;
	if (l_kind == 1) { editing_allowed = YES; [self editColumn:a_column - 1 row:a_view withEvent:nil select:YES]; }
	else if (l_kind == 2) { NSButton *b = [self viewAtColumn:a_column - 1 row:a_view makeIfNecessary:YES]; [b performClick:nil]; }
	else if (l_kind == 3) { NSPopUpButton *b = [self viewAtColumn:a_column - 1 row:a_view makeIfNecessary:YES]; [b performClick:nil]; }
}
- (void)doubleClicked:(id)s
{
	(void)s;
	NSInteger c = [self clickedColumn] + 1;
	if ([editor[@(c)] intValue]) [self editAt:[self clickedRow] column:c];
}
- (NSInteger)firstEditableColumn
{
	for (NSInteger c = 1; c <= (NSInteger)[[self tableColumns] count]; c++) if ([editor[@(c)] intValue]) return c;
	return 0;
}
/* Return or F2 on the selected row edits its first editable column. */
- (void)keyDown:(NSEvent *)e
{
	BOOL l_edit_key = [e keyCode] == 36 || [e keyCode] == 76 || [e keyCode] == 120;
	if (l_edit_key && [self selectedRow] >= 0 && [self firstEditableColumn]) { [self editAt:[self selectedRow] column:[self firstEditableColumn]]; return; }
	[super keyDown:e];
}
/* A text cell's editing ended: Escape cancels; Return or leaving commits. */
- (void)controlTextDidEndEditing:(NSNotification *)n
{
	NSTextField *f = [n object];
	editing_allowed = NO;
	NSInteger v = [self rowForView:f], c = [f tag];
	if (v < 0) return;
	if ([[n userInfo][@"NSTextMovement"] integerValue] == NSTextMovementCancel) { [self reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)v] columnIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)c - 1]]; return; }
	sga_table_commit(self, sga_model_row(self, v), c, [f stringValue]);
}
- (BOOL)control:(NSControl *)c textView:(NSTextView *)tv doCommandBySelector:(SEL)a_command
{
	(void)tv;
	if (a_command == @selector(cancelOperation:)) {   /* Escape: put the old text back, end editing */
		NSInteger v = [self rowForView:c];
		editing_allowed = NO;
		[[self window] makeFirstResponder:self];
		if (v >= 0) [self reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)v] columnIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[c tag] - 1]];
		return YES;
	}
	return NO;
}
- (void)cellChecked:(NSButton *)b
{
	NSInteger v = [self rowForView:b];
	if (v >= 0) sga_table_commit(self, sga_model_row(self, v), [b tag], [b state] == NSControlStateValueOn ? @"1" : @"0");
}
- (void)cellChosen:(NSPopUpButton *)b
{
	NSInteger v = [self rowForView:b];
	if (v >= 0) sga_table_commit(self, sga_model_row(self, v), [b tag], [b titleOfSelectedItem] ?: @"");
}
- (void)tableView:(NSTableView *)a_table didClickTableColumn:(NSTableColumn *)a_column
{
	sga_push(14, sga_id_of(self), (int)[[a_table tableColumns] indexOfObject:a_column] + 1, 0, 0);
}
@end

static NSArray<NSString *> *sga_fields(const char *a_joined)
{
	return [sga_string(a_joined) componentsSeparatedByString:@"\x1f"];
}

int sga_table(const char *a_titles)
{
	NSScrollView *l_scroll = [[SGARowsScroll alloc] init];
	SGAGridTable *t = [[SGAGridTable alloc] init];
	NSUInteger k = 0;
	t->data = [NSMutableArray array];
	for (NSString *l_title in sga_fields(a_titles)) {
		NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"c%lu", (unsigned long)++k]];
		[c setTitle:l_title];
		[c setResizingMask:NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask];
		[t addTableColumn:c];
	}
	[t setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
	[t setAllowsColumnReordering:NO];
	[t setUsesAlternatingRowBackgroundColors:YES];
	[t setStyle:NSTableViewStyleFullWidth];
	[t setDataSource:t];
	[t setDelegate:t];
	[t setTarget:t];
	[t setDoubleAction:@selector(doubleClicked:)];
	t->editor = [NSMutableDictionary dictionary];
	t->choices = [NSMutableDictionary dictionary];
	[l_scroll setDocumentView:t];
	[l_scroll setHasVerticalScroller:YES];
	[l_scroll setBorderType:NSBezelBorder];
	int l_id = sga_keep(l_scroll);
	s_inner[l_id] = t;
	return l_id;
}

static void sga_table_refilter(SGAGridTable *t);

void sga_table_extend(int a_id, const char *a_cells)
{
	SGAGridTable *t = s_inner[a_id];
	[t->data addObject:sga_fields(a_cells)];
	if ([t->filter length]) sga_table_refilter(t);
	else { s_suppress++; [t reloadData]; s_suppress--; }
}

void sga_table_wipe_out(int a_id)
{
	SGAGridTable *t = s_inner[a_id];
	[t->data removeAllObjects];
	sga_set_shown_map(t, nil);
	t->source_on = NO;
	t->source_count = 0;
	[t->cache removeAllObjects];
	[t->pending removeAllIndexes];
	s_suppress++;
	[t deselectAll:nil];
	[t reloadData];
	s_suppress--;
}

/* ---- lazy rows (1f) */

void sga_table_set_source(int a_id, int a_count)
{
	SGAGridTable *t = s_inner[a_id];
	[t->data removeAllObjects];
	sga_set_shown_map(t, nil);
	t->filter = nil;
	t->source_on = YES;
	t->source_count = MAX(a_count, 0);
	if (!t->cache) t->cache = [NSMutableDictionary dictionary];
	if (!t->pending) t->pending = [NSMutableIndexSet indexSet];
	[t->cache removeAllObjects];
	[t->pending removeAllIndexes];
	s_suppress++;
	[t deselectAll:nil];
	[t reloadData];
	s_suppress--;
}

void sga_table_set_row(int a_id, int a_row, const char *a_cells)
{
	SGAGridTable *t = s_inner[a_id];
	NSInteger r = a_row - 1;
	if (!t->source_on || r < 0 || r >= t->source_count) return;
	t->cache[@(r)] = sga_fields(a_cells);
	[t->pending removeIndex:(NSUInteger)r];
	NSInteger v = sga_view_row(t, r);
	s_suppress++;
	if (v >= 0) [t reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)v] columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [[t tableColumns] count])]];
	s_suppress--;
}

void sga_table_set_row_count(int a_id, int a_count)
{
	SGAGridTable *t = s_inner[a_id];
	if (!t->source_on) return;
	t->source_count = MAX(a_count, 0);
	for (NSNumber *k in [t->cache allKeys]) if ([k integerValue] >= t->source_count) [t->cache removeObjectForKey:k];
	[t->pending removeIndexesInRange:NSMakeRange((NSUInteger)t->source_count, NSUIntegerMax - (NSUInteger)t->source_count)];
	NSMutableIndexSet *l_keep = [[t selectedRowIndexes] mutableCopy];
	[l_keep removeIndexesInRange:NSMakeRange((NSUInteger)t->source_count, NSUIntegerMax - (NSUInteger)t->source_count)];
	s_suppress++;
	[t reloadData];
	[t selectRowIndexes:l_keep byExtendingSelection:NO];
	s_suppress--;
}

void sga_table_forget_rows(int a_id)
{
	SGAGridTable *t = s_inner[a_id];
	if (!t->source_on) return;
	[t->cache removeAllObjects];
	[t->pending removeAllIndexes];
	NSIndexSet *l_selected = [[t selectedRowIndexes] copy];
	s_suppress++;
	[t reloadData];
	[t selectRowIndexes:l_selected byExtendingSelection:NO];
	s_suppress--;
}

void sga_table_forget_row(int a_id, int a_row)
{
	SGAGridTable *t = s_inner[a_id];
	NSInteger r = a_row - 1;
	if (!t->source_on || r < 0 || r >= t->source_count) return;
	[t->cache removeObjectForKey:@(r)];
	[t->pending removeIndex:(NSUInteger)r];
	NSInteger v = sga_view_row(t, r);
	s_suppress++;
	if (v >= 0) [t reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)v] columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [[t tableColumns] count])]];
	s_suppress--;
}

void sga_table_scroll_to(int a_id, int a_row)
{
	NSTableView *t = s_inner[a_id];
	NSInteger v = a_row >= 1 ? sga_view_row(t, a_row - 1) : -1;
	if (v >= 0 && v < [t numberOfRows]) [t scrollRowToVisible:v];
}

void sga_table_set_multiple(int a_id, int a_on) { [(NSTableView *)s_inner[a_id] setAllowsMultipleSelection:a_on != 0]; }

void sga_table_select(int a_id, int a_row, int a_extend)
{
	NSTableView *t = s_inner[a_id];
	NSInteger v = a_row >= 1 ? sga_view_row(t, a_row - 1) : -1;
	s_suppress++;
	if (a_row <= 0) [t deselectAll:nil];
	else if (v >= 0) [t selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)v] byExtendingSelection:a_extend != 0];
	s_suppress--;
}

int sga_table_selected_count(int a_id) { return (int)[[(NSTableView *)s_inner[a_id] selectedRowIndexes] count]; }

int sga_table_selected_at(int a_id, int i)
{
	__block int l_seen = 0, l_row = 0;
	NSTableView *t = s_inner[a_id];
	[[t selectedRowIndexes] enumerateIndexesUsingBlock:^(NSUInteger r, BOOL *a_stop) {
		if (++l_seen == i) { l_row = (int)sga_model_row(t, (NSInteger)r) + 1; *a_stop = YES; }
	}];
	return l_row;
}

void sga_table_set_sort_indicator(int a_id, int a_column, int a_ascending)
{
	NSTableView *t = s_inner[a_id];
	NSArray<NSTableColumn *> *l_columns = [t tableColumns];
	for (NSTableColumn *c in l_columns) [t setIndicatorImage:nil inTableColumn:c];
	if (a_column >= 1 && a_column <= (int)[l_columns count]) {
		NSTableColumn *c = l_columns[(NSUInteger)(a_column - 1)];
		[t setIndicatorImage:[NSImage imageNamed:a_ascending ? @"NSAscendingSortIndicator" : @"NSDescendingSortIndicator"] inTableColumn:c];
		[t setHighlightedTableColumn:c];
	} else [t setHighlightedTableColumn:nil];
}

/* A click on column `a_column''s header, as AppKit reports one to the table's delegate. */
void sga_test_click_header(int a_id, int a_column)
{
	SGAGridTable *t = s_inner[a_id];
	[t tableView:t didClickTableColumn:[t tableColumns][(NSUInteger)(a_column - 1)]];
}

/* Trees: an NSOutlineView subclass that is its own data source and delegate, over node
   objects (identity is what an outline view tracks items by). Nodes are numbered by the
   caller, 1, 2, 3... A user's selection sends selection (4, a = node); a user's expanding or
   collapsing sends expansion (15, a = node, b = 1 expanded). Programmatic changes send nothing. */
@interface SGANode : NSObject
{
@public
	int number;
	NSString *text;
	NSMutableArray<NSString *> *cells;   /* a tree table's columns 2 .. n (1h); empty in a plain tree */
	NSMutableArray<SGANode *> *children;
	SGANode *parent;
}
@end
@implementation SGANode
@end

@interface SGATree : NSOutlineView <NSOutlineViewDataSource, NSOutlineViewDelegate>
{
@public
	NSMutableArray<SGANode *> *roots;
	NSMutableArray<SGANode *> *nodes;   /* node n at index n - 1 */
	BOOL is_table;   /* a tree table (1h): read as a tree grid, as GUI_TABLE is */
}
@end
@implementation SGATree
- (NSInteger)outlineView:(NSOutlineView *)o numberOfChildrenOfItem:(id)an_item
{
	return (NSInteger)[(an_item ? ((SGANode *)an_item)->children : roots) count];
}
- (id)outlineView:(NSOutlineView *)o child:(NSInteger)i ofItem:(id)an_item
{
	return (an_item ? ((SGANode *)an_item)->children : roots)[(NSUInteger)i];
}
- (BOOL)outlineView:(NSOutlineView *)o isItemExpandable:(id)an_item { return [((SGANode *)an_item)->children count] > 0; }
- (NSView *)outlineView:(NSOutlineView *)o viewForTableColumn:(NSTableColumn *)c item:(id)an_item
{
	NSTextField *f = [o makeViewWithIdentifier:@"sga_tree_cell" owner:self];
	if (!f) {
		f = [NSTextField labelWithString:@""];
		[f setIdentifier:@"sga_tree_cell"];
		[f setLineBreakMode:NSLineBreakByTruncatingTail];
	}
	/* Column 1 is the node's text; a tree table's other columns are its cells. */
	SGANode *n = an_item;
	NSUInteger k = [[o tableColumns] indexOfObject:c];
	[f setStringValue:k == 0 || k == NSNotFound ? n->text : (k <= [n->cells count] ? n->cells[k - 1] : @"")];
	return f;
}
- (void)outlineViewSelectionDidChange:(NSNotification *)n
{
	if (s_suppress) return;
	SGANode *l_node = [self selectedRow] >= 0 ? [self itemAtRow:[self selectedRow]] : nil;
	sga_push(4, sga_id_of(self), l_node ? l_node->number : 0, 0, 0);
}
- (void)outlineViewItemDidExpand:(NSNotification *)n
{
	if (!s_suppress) sga_push(15, sga_id_of(self), ((SGANode *)n.userInfo[@"NSObject"])->number, 1, 0);
}
- (void)outlineViewItemDidCollapse:(NSNotification *)n
{
	if (!s_suppress) sga_push(15, sga_id_of(self), ((SGANode *)n.userInfo[@"NSObject"])->number, 0, 0);
}
@end

int sga_tree(void)
{
	NSScrollView *l_scroll = [[SGARowsScroll alloc] init];
	SGATree *t = [[SGATree alloc] init];
	NSTableColumn *k = [[NSTableColumn alloc] initWithIdentifier:@"sga_tree_column"];
	t->roots = [NSMutableArray array];
	t->nodes = [NSMutableArray array];
	[k setResizingMask:NSTableColumnAutoresizingMask];
	[t addTableColumn:k];
	[t setOutlineTableColumn:k];
	[t setColumnAutoresizingStyle:NSTableViewUniformColumnAutoresizingStyle];
	[t setHeaderView:nil];
	[t setStyle:NSTableViewStyleInset];
	[t setDataSource:t];
	[t setDelegate:t];
	[l_scroll setDocumentView:t];
	[l_scroll setHasVerticalScroller:YES];
	[l_scroll setBorderType:NSBezelBorder];
	int l_id = sga_keep(l_scroll);
	s_inner[l_id] = t;
	return l_id;
}

static SGANode *sga_tree_node(SGATree *t, int a_node)
{
	return (a_node >= 1 && a_node <= (int)[t->nodes count]) ? t->nodes[(NSUInteger)(a_node - 1)] : nil;
}

static NSArray<NSString *> *sga_fields(const char *a_joined);

/* A tree table (1h): a tree with titled columns, the first holding the outline. Nodes come
   and go as in a tree; `sga_tree_table_set_cell' gives a node's text in another column. */
int sga_tree_table(const char *a_titles)
{
	int l_id = sga_tree();
	SGATree *t = s_inner[l_id];
	NSArray<NSString *> *l_titles = sga_fields(a_titles);
	NSTableColumn *l_first = [[t tableColumns] firstObject];
	[l_first setTitle:[l_titles count] ? l_titles[0] : @""];
	[l_first setResizingMask:NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask];
	for (NSUInteger k = 1; k < [l_titles count]; k++) {
		NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"sga_tree_c%lu", (unsigned long)k + 1]];
		[c setTitle:l_titles[k]];
		[c setResizingMask:NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask];
		[t addTableColumn:c];
	}
	t->is_table = YES;
	[t setHeaderView:[[NSTableHeaderView alloc] init]];
	[t setAllowsColumnReordering:NO];
	[t setUsesAlternatingRowBackgroundColors:YES];
	[t setStyle:NSTableViewStyleFullWidth];
	return l_id;
}

void sga_tree_table_set_cell(int a_id, int a_node, int a_column, const char *a_text)
{
	SGATree *t = s_inner[a_id];
	SGANode *n = sga_tree_node(t, a_node);
	if (!n || a_column < 1) return;
	if (a_column == 1) n->text = sga_string(a_text);
	else {
		while ((int)[n->cells count] < a_column - 1) [n->cells addObject:@""];
		n->cells[(NSUInteger)(a_column - 2)] = sga_string(a_text);
	}
	s_suppress++;
	[t reloadItem:n];
	s_suppress--;
}

void sga_tree_add(int a_id, int a_node, int a_parent, const char *a_text)
{
	SGATree *t = s_inner[a_id];
	SGANode *n = [[SGANode alloc] init];
	SGANode *p = sga_tree_node(t, a_parent);
	n->number = a_node;
	n->text = sga_string(a_text);
	n->cells = [NSMutableArray array];
	n->children = [NSMutableArray array];
	n->parent = p;
	[t->nodes addObject:n];
	[(p ? p->children : t->roots) addObject:n];
	s_suppress++;
	[t reloadItem:p reloadChildren:YES];
	s_suppress--;
}

/* 1q-c: move `a_node' with its subtree under `a_parent' (0: the top level) as child number
   `a_position' there (1-based, counted after taking it out); silent. Never under itself. */
void sga_tree_move(int a_id, int a_node, int a_parent, int a_position)
{
	SGATree *t = s_inner[a_id];
	SGANode *n = sga_tree_node(t, a_node), *p = sga_tree_node(t, a_parent);
	if (!n) return;
	for (SGANode *q = p; q; q = q->parent) if (q == n) return;
	NSMutableArray<SGANode *> *l_from = n->parent ? n->parent->children : t->roots, *l_to = p ? p->children : t->roots;
	NSUInteger l_old = [l_from indexOfObjectIdenticalTo:n];
	if (l_old == NSNotFound) return;
	SGANode *l_old_parent = n->parent;
	[l_from removeObjectAtIndex:l_old];
	NSUInteger l_new = (NSUInteger)MAX(0, MIN(a_position - 1, (int)[l_to count]));
	[l_to insertObject:n atIndex:l_new];
	n->parent = p;
	s_suppress++;
	[t beginUpdates];
	[t moveItemAtIndex:(NSInteger)l_old inParent:l_old_parent toIndex:(NSInteger)l_new inParent:p];
	[t endUpdates];
	s_suppress--;
}

void sga_tree_set_expanded(int a_id, int a_node, int a_on)
{
	SGATree *t = s_inner[a_id];
	s_suppress++;
	if (a_on) [t expandItem:sga_tree_node(t, a_node)]; else [t collapseItem:sga_tree_node(t, a_node)];
	s_suppress--;
}

int sga_tree_is_expanded(int a_id, int a_node)
{
	SGATree *t = s_inner[a_id];
	return [t isItemExpanded:sga_tree_node(t, a_node)] ? 1 : 0;
}

/* Expand every ancestor of `a_node', root first, so its row exists (silently). */
static void sga_tree_reveal(SGATree *t, SGANode *a_node)
{
	NSMutableArray<SGANode *> *l_chain = [NSMutableArray array];
	for (SGANode *p = a_node->parent; p; p = p->parent) [l_chain insertObject:p atIndex:0];
	s_suppress++;
	for (SGANode *p in l_chain) [t expandItem:p];
	s_suppress--;
}

void sga_tree_select(int a_id, int a_node)
{
	SGATree *t = s_inner[a_id];
	SGANode *n = sga_tree_node(t, a_node);
	s_suppress++;
	if (!n) [t deselectAll:nil];
	else {
		sga_tree_reveal(t, n);
		[t selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[t rowForItem:n]] byExtendingSelection:NO];
	}
	s_suppress--;
}

int sga_tree_selected(int a_id)
{
	SGATree *t = s_inner[a_id];
	SGANode *n = [t selectedRow] >= 0 ? [t itemAtRow:[t selectedRow]] : nil;
	return n ? n->number : 0;
}

/* As a user: a click on the node's disclosure triangle. */
void sga_test_expand(int a_id, int a_node, int a_on)
{
	SGATree *t = s_inner[a_id];
	SGANode *n = sga_tree_node(t, a_node);
	if (!n) return;
	sga_tree_reveal(t, n);
	if (a_on) [t expandItem:n]; else [t collapseItem:n];
}

/* ---------------------------------------------------- 1g: five more controls */

/* A dropdown: an NSPopUpButton. Items go in through its menu, which keeps duplicate texts
   (addItemWithTitle: drops an earlier item with the same title). The first item is selected
   without an event, as on GTK. A user's choice of another row sends selection (4, a = row);
   choosing the shown row again, or selecting from code, sends nothing. */
@interface SGADropdown : NSPopUpButton
{
@public
	NSInteger shown;   /* the row last reported or set; 0 = none */
	NSMutableArray<NSMenuItem *> *choices;   /* the choices, apart from group headers and separators (1p) */
}
@end
@implementation SGADropdown
- (NSInteger)choice
{
	NSUInteger k = [self selectedItem] ? [choices indexOfObjectIdenticalTo:[self selectedItem]] : NSNotFound;
	return k == NSNotFound ? 0 : (NSInteger)k + 1;
}
- (void)chosen:(id)a_sender
{
	NSInteger r = [self choice];
	(void)a_sender;
	if (r != shown) {
		shown = r;
		if (!s_suppress) sga_push(4, sga_id_of(self), (int)r, 0, 0);
	}
}
@end

int sga_dropdown(void)
{
	SGADropdown *d = [[SGADropdown alloc] initWithFrame:NSZeroRect pullsDown:NO];
	d->choices = [NSMutableArray array];
	[d setAutoenablesItems:NO];
	[d setTarget:d];
	[d setAction:@selector(chosen:)];
	return sga_keep(d);
}

void sga_dropdown_extend(int a_id, const char *a_text)
{
	SGADropdown *d = sga_get(a_id);
	NSMenuItem *i = [[d menu] addItemWithTitle:sga_string(a_text) action:NULL keyEquivalent:@""];
	[d->choices addObject:i];
	if ([d->choices count] == 1) [d selectItem:i];
	d->shown = [d choice];
}

/* 1p: a group header (a section header on macOS 14 and later) and a separator; neither is a choice. */
void sga_dropdown_add_header(int a_id, const char *a_text)
{
	SGADropdown *d = sga_get(a_id);
	NSMenuItem *i;
	if (@available(macOS 14.0, *)) i = [NSMenuItem sectionHeaderWithTitle:sga_string(a_text)];
	else {
		i = [[NSMenuItem alloc] initWithTitle:sga_string(a_text) action:NULL keyEquivalent:@""];
		[i setEnabled:NO];
	}
	[[d menu] addItem:i];
	if ([d->choices count] == 0) [d selectItem:nil];
}

void sga_dropdown_add_separator(int a_id) { [[(SGADropdown *)sga_get(a_id) menu] addItem:[NSMenuItem separatorItem]]; }

void sga_dropdown_wipe_out(int a_id)
{
	SGADropdown *d = sga_get(a_id);
	[d removeAllItems];
	[d->choices removeAllObjects];
	d->shown = 0;
}

void sga_dropdown_select(int a_id, int a_row)
{
	SGADropdown *d = sga_get(a_id);
	[d selectItem:d->choices[(NSUInteger)(a_row - 1)]];
	d->shown = [d choice];
}

int sga_dropdown_selected(int a_id) { return (int)[(SGADropdown *)sga_get(a_id) choice]; }

/* As a user: the row chosen from the menu, then the button's action. */
static void sga_test_choose_option(int a_id, int a_row)
{
	SGADropdown *d = sga_get(a_id);
	[d selectItem:d->choices[(NSUInteger)(a_row - 1)]];
	[d sendAction:[d action] to:[d target]];
}

/* A spin box: a text field with an NSStepper beside it, in one view. `value' is the last
   committed number. The user commits with a stepper click, Return, or by leaving the field:
   the text is read as a whole number and clamped to the range (text that is not a number
   goes back to `value'); a change sends text changed (2, a = the new value). Typed numbers
   are not snapped to the step, as GtkSpinButton's are not by default. Setting the value from
   code sends nothing. For assistive tools the view is one group, read as "spin-button". */
@interface SGASpin : NSView <NSTextFieldDelegate>
{
@public
	NSTextField *field;
	NSStepper *stepper;
	NSInteger value, minimum, maximum;
}
@end
@implementation SGASpin
- (BOOL)isAccessibilityElement { return YES; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityGroupRole; }
- (id)accessibilityValue { return [NSString stringWithFormat:@"%ld", (long)value]; }
- (void)show
{
	[field setStringValue:[NSString stringWithFormat:@"%ld", (long)value]];
	[stepper setIntegerValue:value];
}
- (void)commit:(NSInteger)a_value
{
	NSInteger v = MAX(minimum, MIN(maximum, a_value));
	BOOL l_changed = v != value;
	value = v;
	[self show];
	if (l_changed && !s_suppress) sga_push(2, sga_id_of(self), (int)v, 0, 0);
}
- (void)commitText
{
	NSScanner *l_scan = [NSScanner scannerWithString:[[field stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
	NSInteger v;
	if ([l_scan scanInteger:&v] && [l_scan isAtEnd]) [self commit:v];
	else [self show];
}
- (void)stepped:(id)a_sender { (void)a_sender; [self commit:[stepper integerValue]]; }
- (void)entered:(id)a_sender { (void)a_sender; [self commitText]; }
- (void)controlTextDidEndEditing:(NSNotification *)n { (void)n; [self commitText]; }
@end

int sga_spin_box(int a_min, int a_max)
{
	SGASpin *s = [[SGASpin alloc] initWithFrame:NSZeroRect];
	s->minimum = a_min;
	s->maximum = a_max;
	s->value = a_min;
	s->field = [NSTextField textFieldWithString:@""];
	s->stepper = [[NSStepper alloc] init];
	[s->stepper setValueWraps:NO];   /* AppKit's default wraps from the maximum to the minimum */
	[s->stepper setAutorepeat:YES];
	[s->stepper setMinValue:a_min];
	[s->stepper setMaxValue:a_max];
	[s->stepper setIncrement:1];
	[s->stepper setTarget:s];
	[s->stepper setAction:@selector(stepped:)];
	[s->field setDelegate:s];
	[s->field setTarget:s];
	[s->field setAction:@selector(entered:)];
	[s->field setAlignment:NSTextAlignmentRight];
	[s->field setBaseWritingDirection:NSWritingDirectionLeftToRight];   /* a number reads left to right */
	for (NSView *v in @[s->field, s->stepper]) {
		[v setTranslatesAutoresizingMaskIntoConstraints:NO];
		[s addSubview:v];
	}
	NSUInteger l_min_digits = [[NSString stringWithFormat:@"%d", a_min] length];
	NSUInteger l_max_digits = [[NSString stringWithFormat:@"%d", a_max] length];
	NSUInteger l_digits = MAX(l_min_digits, l_max_digits);
	CGFloat l_width = ceil([@"0" sizeWithAttributes:@{NSFontAttributeName: [s->field font]}].width * l_digits) + 16;
	[NSLayoutConstraint activateConstraints:@[
		[s->field.leadingAnchor constraintEqualToAnchor:s.leadingAnchor],
		[s->stepper.leadingAnchor constraintEqualToAnchor:s->field.trailingAnchor constant:4],
		[s->stepper.trailingAnchor constraintEqualToAnchor:s.trailingAnchor],
		[s->field.centerYAnchor constraintEqualToAnchor:s.centerYAnchor],
		[s->stepper.centerYAnchor constraintEqualToAnchor:s.centerYAnchor],
		[s->field.topAnchor constraintGreaterThanOrEqualToAnchor:s.topAnchor],
		[s->stepper.topAnchor constraintGreaterThanOrEqualToAnchor:s.topAnchor],
		[s.heightAnchor constraintEqualToConstant:MAX([s->field fittingSize].height, [s->stepper fittingSize].height)]]];
	/* Wide enough for the range; a filling alignment may widen the field. */
	NSLayoutConstraint *l_wide = [s->field.widthAnchor constraintEqualToConstant:MAX(l_width, 48)];
	[l_wide setPriority:NSLayoutPriorityDefaultLow];   /* below the window's own size: alone in a window, the field widens instead */
	[[s->field.widthAnchor constraintGreaterThanOrEqualToConstant:MAX(l_width, 48)] setActive:YES];
	[l_wide setActive:YES];
	[s show];
	return sga_keep(s);
}

void sga_spin_box_set_value(int a_id, int a_value)
{
	SGASpin *s = sga_get(a_id);
	s->value = a_value;
	[s show];
}

int sga_spin_box_value(int a_id) { return (int)((SGASpin *)sga_get(a_id))->value; }
void sga_spin_box_set_step(int a_id, int a_step) { [((SGASpin *)sga_get(a_id))->stepper setIncrement:a_step]; }

/* As a user: the number typed into the field, then Return. */
void sga_test_set_number(int a_id, int a_value)
{
	SGASpin *s = sga_get(a_id);
	[s->field setStringValue:[NSString stringWithFormat:@"%d", a_value]];
	[s commitText];
}

/* A progress bar: a determinate NSProgressIndicator from 0 to 100. */
int sga_progress_bar(void)
{
	NSProgressIndicator *p = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
	[p setStyle:NSProgressIndicatorStyleBar];
	[p setIndeterminate:NO];
	[p setMinValue:0];
	[p setMaxValue:100];
	[p setDoubleValue:0];
	[p setTranslatesAutoresizingMaskIntoConstraints:NO];
	[[p.widthAnchor constraintGreaterThanOrEqualToConstant:100] setActive:YES];   /* a bar has no natural width */
	return sga_keep(p);
}

void sga_progress_bar_set(int a_id, int a_value) { [(NSProgressIndicator *)sga_get(a_id) setDoubleValue:a_value]; }
int sga_progress_bar_value(int a_id) { return (int)lround([(NSProgressIndicator *)sga_get(a_id) doubleValue]); }

/* A status bar: one line of small text in the window's bottom bar (the content border on the
   bottom edge, which AppKit draws as on Finder's windows). The label is in the content view,
   so snapshots and assistive tools see it, and the program's content ends above the bar.
   Read as "status": AppKit has no such role. */
static const CGFloat Sga_status_height = 24;

int sga_status_bar(void)
{
	SGAStatus *l = [SGAStatus labelWithString:@""];
	[l setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[l setTextColor:[NSColor secondaryLabelColor]];
	[l setLineBreakMode:NSLineBreakByTruncatingTail];
	[l setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 2 forOrientation:NSLayoutConstraintOrientationHorizontal];
	return sga_keep(l);
}

void sga_status_bar_set_text(int a_id, const char *a_text) { [(NSTextField *)sga_get(a_id) setStringValue:sga_string(a_text)]; }
const char *sga_status_bar_text(int a_id) { return sga_return(Kind_label, [(NSTextField *)sga_get(a_id) stringValue]); }

void sga_window_set_status_bar(int a_window, int a_bar)
{
	NSWindow *w = sga_get(a_window);
	SGAContent *c = [w contentView];
	SGAStatus *l = sga_get(a_bar);
	for (NSView *l_old in [[c subviews] copy]) if ([l_old isKindOfClass:[SGAStatus class]]) [l_old removeFromSuperview];
	[l setTranslatesAutoresizingMaskIntoConstraints:NO];
	[c addSubview:l];
	[NSLayoutConstraint activateConstraints:@[
		[l.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:10],
		[l.trailingAnchor constraintLessThanOrEqualToAnchor:c.trailingAnchor constant:-10],
		[l.centerYAnchor constraintEqualToAnchor:c.bottomAnchor constant:-Sga_status_height / 2]]];
	[w setAutorecalculatesContentBorderThickness:NO forEdge:NSMinYEdge];
	[w setContentBorderThickness:Sga_status_height forEdge:NSMinYEdge];
	c->bottom_bar = Sga_status_height;
	[s_content_bottom[@(a_window)] setConstant:-Sga_status_height];
	[c setNeedsDisplay:YES];
}

/* A toolbar: an NSToolbar in the window's title bar, as Mac programs have. Its buttons are the
   program's own NSButtons, each the view of an item; a separator is an item holding a thin
   vertical line (NSToolbar has drawn no separator of its own since macOS 11). Users cannot
   customize it, and each has its own identifier, so two windows' toolbars never share items.
   The widget is a view outside any window, standing for the toolbar: hiding it hides the
   toolbar. */
@interface SGAToolbar : NSView <NSToolbarDelegate>
{
@public
	NSToolbar *toolbar;
	NSMutableArray<NSToolbarItem *> *items;
}
@end
@implementation SGAToolbar
- (NSArray<NSToolbarItemIdentifier> *)identifiers
{
	NSMutableArray *a = [NSMutableArray array];
	for (NSToolbarItem *i in items) [a addObject:[i itemIdentifier]];
	return a;
}
- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)t { (void)t; return [self identifiers]; }
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)t { (void)t; return [self identifiers]; }
- (NSToolbarItem *)toolbar:(NSToolbar *)t itemForItemIdentifier:(NSToolbarItemIdentifier)an_id willBeInsertedIntoToolbar:(BOOL)f
{
	(void)t; (void)f;
	for (NSToolbarItem *i in items) if ([[i itemIdentifier] isEqualToString:an_id]) return i;
	return nil;
}
/* The toolbar loads its default items when first asked for them; an item added after that is
   inserted at the end. */
- (void)add:(NSToolbarItem *)an_item
{
	[items addObject:an_item];
	NSUInteger l_shown = [[toolbar items] count];
	if (l_shown < [items count]) [toolbar insertItemWithItemIdentifier:[an_item itemIdentifier] atIndex:(NSInteger)l_shown];
}
- (void)setHidden:(BOOL)a_hidden { [super setHidden:a_hidden]; [toolbar setVisible:!a_hidden]; }
@end

int sga_toolbar(void)
{
	SGAToolbar *h = [[SGAToolbar alloc] initWithFrame:NSZeroRect];
	int l_id = sga_keep(h);
	h->items = [NSMutableArray array];
	h->toolbar = [[NSToolbar alloc] initWithIdentifier:[NSString stringWithFormat:@"sga_toolbar_%d", l_id]];
	[h->toolbar setDelegate:h];
	[h->toolbar setAllowsUserCustomization:NO];
	[h->toolbar setAutosavesConfiguration:NO];
	[h->toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
	return l_id;
}

void sga_toolbar_extend(int a_toolbar, int a_button)
{
	SGAToolbar *h = sga_get(a_toolbar);
	NSButton *b = sga_get(a_button);
	NSToolbarItem *i = [[NSToolbarItem alloc] initWithItemIdentifier:[NSString stringWithFormat:@"sga_item_%d", a_button]];
	[i setView:b];
	[i setLabel:[b title]];
	[i setAutovalidates:NO];
	[i setEnabled:[b isEnabled]];
	if (!s_toolbar_item) s_toolbar_item = [NSMapTable weakToStrongObjectsMapTable];
	[s_toolbar_item setObject:i forKey:b];
	[h add:i];
}

void sga_toolbar_add_separator(int a_toolbar)
{
	static int s_separators;
	SGAToolbar *h = sga_get(a_toolbar);
	NSBox *l_line = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 1, 20)];
	[l_line setBoxType:NSBoxSeparator];
	[l_line setAccessibilityElement:NO];
	[l_line setTranslatesAutoresizingMaskIntoConstraints:NO];
	[NSLayoutConstraint activateConstraints:@[[l_line.widthAnchor constraintEqualToConstant:1], [l_line.heightAnchor constraintEqualToConstant:20]]];
	NSToolbarItem *i = [[NSToolbarItem alloc] initWithItemIdentifier:[NSString stringWithFormat:@"sga_separator_%d", ++s_separators]];
	[i setView:l_line];
	[i setLabel:@""];
	[i setAutovalidates:NO];
	[h add:i];
}

/* The content keeps the size the program asked for: the toolbar adds to the title bar. */
void sga_window_set_toolbar(int a_window, int a_toolbar)
{
	NSWindow *w = sga_get(a_window);
	SGAToolbar *h = sga_get(a_toolbar);
	NSSize l_size = [[w contentView] frame].size;
	[w setToolbar:h->toolbar];
	[w setContentSize:l_size];
}

/* ------------------------------------------------- 1h: the standard controls */

/* Events (spec 1h): a radio group's or segmented control's pick sends selection (4, a = the
   1-based choice); a slider's every move, and a committed date, time, color or combo box
   text, send text changed (2, a = the value); a switch and an expander send toggled (12,
   a = 1 on). Setting from code sends nothing. */

/* A radio group: radio buttons in a stack. AppKit makes radios that share a superview and
   an action exclusive, so the group's stack is all it takes. */
@interface SGARadioGroup : NSStackView
{
@public
	NSInteger chosen;   /* 1-based; 0 = none */
}
@end
@implementation SGARadioGroup
- (void)picked:(NSButton *)a_radio
{
	NSInteger i = (NSInteger)[[self arrangedSubviews] indexOfObject:a_radio] + 1;
	if (i != chosen) {
		chosen = i;
		if (!s_suppress) sga_push(4, sga_id_of(self), (int)i, 0, 0);
	}
}
@end

int sga_radio_group(int a_vertical)
{
	SGARadioGroup *g = [[SGARadioGroup alloc] init];
	[g setOrientation:a_vertical ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal];
	[g setAlignment:a_vertical ? NSLayoutAttributeLeading : NSLayoutAttributeCenterY];
	[g setSpacing:a_vertical ? 6 : 16];
	return sga_keep(g);
}

/* The first radio added is chosen, without an event (one is always on, as on GTK). */
void sga_radio_group_extend(int a_id, const char *a_text)
{
	SGARadioGroup *g = sga_get(a_id);
	NSButton *b = [NSButton radioButtonWithTitle:sga_string(a_text) target:g action:@selector(picked:)];
	[g addArrangedSubview:b];
	if (g->chosen == 0) {
		[b setState:NSControlStateValueOn];
		g->chosen = 1;
	}
}

void sga_radio_group_select(int a_id, int i)
{
	SGARadioGroup *g = sga_get(a_id);
	NSArray<NSView *> *l_radios = [g arrangedSubviews];
	for (NSUInteger k = 0; k < [l_radios count]; k++)
		[(NSButton *)l_radios[k] setState:(NSInteger)k == i - 1 ? NSControlStateValueOn : NSControlStateValueOff];
	g->chosen = i;
}

int sga_radio_group_selected(int a_id) { return (int)((SGARadioGroup *)sga_get(a_id))->chosen; }

/* A slider: an NSSlider over whole numbers that reports every move, as GtkScale does. */
@interface SGASlider : NSSlider
{
@public
	NSInteger last;
}
@end
@implementation SGASlider
- (void)moved:(id)a_sender
{
	NSInteger v = (NSInteger)lround([self doubleValue]);
	(void)a_sender;
	if (v != last) {
		last = v;
		if (!s_suppress) sga_push(2, sga_id_of(self), (int)v, 0, 0);
	}
}
@end

int sga_slider(int a_min, int a_max, int a_vertical)
{
	SGASlider *s = [SGASlider sliderWithValue:a_min minValue:a_min maxValue:a_max target:nil action:NULL];
	[s setTarget:s];
	[s setAction:@selector(moved:)];
	[s setContinuous:YES];
	[s setVertical:a_vertical != 0];
	s->last = a_min;
	[s setTranslatesAutoresizingMaskIntoConstraints:NO];
	if (a_vertical) [[s.heightAnchor constraintGreaterThanOrEqualToConstant:100] setActive:YES];
	else [[s.widthAnchor constraintGreaterThanOrEqualToConstant:100] setActive:YES];
	return sga_keep(s);
}

void sga_slider_set_value(int a_id, int a_value) { SGASlider *s = sga_get(a_id); [s setIntegerValue:a_value]; s->last = a_value; }
int sga_slider_value(int a_id) { return (int)lround([(NSSlider *)sga_get(a_id) doubleValue]); }

/* Tick marks every `a_step' (0: none); with ticks the knob stops on them. */
void sga_slider_set_step(int a_id, int a_step)
{
	NSSlider *s = sga_get(a_id);
	NSInteger l_span = (NSInteger)([s maxValue] - [s minValue]);
	if (a_step > 0 && l_span > 0 && l_span / a_step <= 100) {
		[s setNumberOfTickMarks:l_span / a_step + 1];
		[s setAllowsTickMarkValuesOnly:YES];
	} else {
		[s setNumberOfTickMarks:0];
		[s setAllowsTickMarkValuesOnly:NO];
	}
}

/* As a user: the knob moved to `a_value', then the action. */
void sga_test_slide(int a_id, int a_value)
{
	SGASlider *s = sga_get(a_id);
	[s setIntegerValue:a_value];
	[s sendAction:[s action] to:[s target]];
}

/* A switch: an NSSwitch. Flipping it sends toggled (12, a = 1 on). */
@interface SGASwitch : NSSwitch
@end
@implementation SGASwitch
- (void)flipped:(id)a_sender { (void)a_sender; if (!s_suppress) sga_push(12, sga_id_of(self), [self state] == NSControlStateValueOn ? 1 : 0, 0, 0); }
@end

int sga_switch(void)
{
	SGASwitch *s = [[SGASwitch alloc] init];
	[s setTarget:s];
	[s setAction:@selector(flipped:)];
	return sga_keep(s);
}

void sga_switch_set(int a_id, int a_on) { [(NSSwitch *)sga_get(a_id) setState:a_on ? NSControlStateValueOn : NSControlStateValueOff]; }
int sga_switch_is_on(int a_id) { return [(NSSwitch *)sga_get(a_id) state] == NSControlStateValueOn ? 1 : 0; }

/* A segmented control: one segment selected at a time; the first added is selected. */
@interface SGASegmented : NSSegmentedControl
{
@public
	NSInteger chosen;
}
@end
@implementation SGASegmented
- (void)picked:(id)a_sender
{
	NSInteger i = [self selectedSegment] + 1;
	(void)a_sender;
	if (i != chosen) {
		chosen = i;
		if (!s_suppress) sga_push(4, sga_id_of(self), (int)i, 0, 0);
	}
}
@end

int sga_segmented(void)
{
	SGASegmented *s = [[SGASegmented alloc] init];
	[s setTrackingMode:NSSegmentSwitchTrackingSelectOne];
	[s setSegmentCount:0];
	[s setTarget:s];
	[s setAction:@selector(picked:)];
	return sga_keep(s);
}

void sga_segmented_extend(int a_id, const char *a_text)
{
	SGASegmented *s = sga_get(a_id);
	NSInteger n = [s segmentCount];
	[s setSegmentCount:n + 1];
	[s setLabel:sga_string(a_text) forSegment:n];
	[s setWidth:0 forSegment:n];   /* sized to its label */
	if (s->chosen == 0) { [s setSelectedSegment:0]; s->chosen = 1; }
	[s invalidateIntrinsicContentSize];
}

void sga_segmented_select(int a_id, int i) { SGASegmented *s = sga_get(a_id); [s setSelectedSegment:i - 1]; s->chosen = i; }
int sga_segmented_selected(int a_id) { return (int)((SGASegmented *)sga_get(a_id))->chosen; }

/* A date or a time: an NSDatePicker, text with a stepper, in the Gregorian calendar and
   the local time zone. A date is given as year * 10000 + month * 100 + day, a time as
   hour * 60 + minute. */
@interface SGADatePicker : NSDatePicker
{
@public
	BOOL is_time;
	NSInteger last;
	int kind;   /* 1p: 0 date or time (is_time), 2 date and time, 3 month */
}
@end
static NSInteger sga_date_value(SGADatePicker *p)
{
	NSCalendar *c = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
	NSDateComponents *k = [c components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute fromDate:[p dateValue]];
	return p->is_time ? [k hour] * 60 + [k minute] : [k year] * 10000 + [k month] * 100 + [k day];
}
@implementation SGADatePicker
- (void)changed:(id)a_sender
{
	NSInteger v = sga_date_value(self);
	(void)a_sender;
	if (kind == 2) {   /* the date in a, the time in b */
		NSCalendar *c = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
		NSDateComponents *k = [c components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:[self dateValue]];
		NSInteger l_time = [k hour] * 60 + [k minute];
		if (v * 10000 + l_time != last) { last = v * 10000 + l_time; if (!s_suppress) sga_push(2, sga_id_of(self), (int)v, (int)l_time, 0); }
	}
	else if (kind == 3) {   /* year * 100 + month */
		if (v / 100 != last) { last = v / 100; if (!s_suppress) sga_push(2, sga_id_of(self), (int)(v / 100), 0, 0); }
	}
	else if (v != last) {
		last = v;
		if (!s_suppress) sga_push(2, sga_id_of(self), (int)v, 0, 0);
	}
}
@end

static int sga_new_date_picker(BOOL a_time)
{
	SGADatePicker *p = [[SGADatePicker alloc] init];
	p->is_time = a_time;
	[p setDatePickerStyle:NSDatePickerStyleTextFieldAndStepper];
	[p setDatePickerElements:a_time ? NSDatePickerElementFlagHourMinute : NSDatePickerElementFlagYearMonthDay];
	[p setCalendar:[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]];
	[p setTimeZone:[NSTimeZone localTimeZone]];
	[p setDateValue:[NSDate date]];
	[p setTarget:p];
	[p setAction:@selector(changed:)];
	p->last = sga_date_value(p);
	return sga_keep(p);
}

int sga_date_picker(void) { return sga_new_date_picker(NO); }
int sga_time_picker(void) { return sga_new_date_picker(YES); }

static NSDate *sga_date_of(SGADatePicker *p, int a_value)
{
	NSCalendar *c = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
	NSDateComponents *k = [c components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute fromDate:[p dateValue]];
	if (p->is_time) { [k setHour:a_value / 60]; [k setMinute:a_value % 60]; }
	else { [k setYear:a_value / 10000]; [k setMonth:a_value / 100 % 100]; [k setDay:a_value % 100]; }
	return [c dateFromComponents:k];
}

void sga_date_picker_set(int a_id, int a_value)
{
	SGADatePicker *p = sga_get(a_id);
	[p setDateValue:sga_date_of(p, a_value)];
	p->last = sga_date_value(p);
	if (p->kind == 2) {   /* 1p: date and time keep date * 10000 + time */
		NSDateComponents *k = [[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian] components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:[p dateValue]];
		p->last = p->last * 10000 + [k hour] * 60 + [k minute];
	}
	else if (p->kind == 3) p->last = p->last / 100;
}

int sga_date_picker_value(int a_id) { return (int)sga_date_value(sga_get(a_id)); }

/* As a user: the date or time entered, then the action. */
void sga_test_set_date(int a_id, int a_value)
{
	SGADatePicker *p = sga_get(a_id);
	[p setDateValue:sga_date_of(p, a_value)];
	[p sendAction:[p action] to:[p target]];
}

/* A color chooser: an NSColorWell; choosing opens the shared color panel. Colors are 0xRRGGBB in sRGB. */
@interface SGAColorWell : NSColorWell
{
@public
	int last;
}
@end
static int sga_color_rgb(NSColor *a_color)
{
	NSColor *c = [a_color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
	int r = (int)lround([c redComponent] * 255), g = (int)lround([c greenComponent] * 255), b = (int)lround([c blueComponent] * 255);
	return (r << 16) | (g << 8) | b;
}
static NSColor *sga_rgb_color(int a_rgb)
{
	return [NSColor colorWithSRGBRed:((a_rgb >> 16) & 0xff) / 255.0 green:((a_rgb >> 8) & 0xff) / 255.0 blue:(a_rgb & 0xff) / 255.0 alpha:1];
}
@implementation SGAColorWell
- (id)accessibilityValue { return [NSString stringWithFormat:@"#%06X", sga_color_rgb([self color])]; }
- (void)changed:(id)a_sender
{
	int v = sga_color_rgb([self color]);
	(void)a_sender;
	if (v != last) {
		last = v;
		if (!s_suppress) sga_push(2, sga_id_of(self), v, 0, 0);
	}
}
@end

int sga_color_chooser(void)
{
	SGAColorWell *w = [[SGAColorWell alloc] initWithFrame:NSMakeRect(0, 0, 44, 24)];
	[w setColorWellStyle:NSColorWellStyleDefault];
	[w setColor:sga_rgb_color(0)];
	w->last = 0;
	[w setTarget:w];
	[w setAction:@selector(changed:)];
	return sga_keep(w);
}

void sga_color_chooser_set(int a_id, int a_rgb) { SGAColorWell *w = sga_get(a_id); [w setColor:sga_rgb_color(a_rgb)]; w->last = sga_color_rgb([w color]); }
int sga_color_chooser_value(int a_id) { return sga_color_rgb([(NSColorWell *)sga_get(a_id) color]); }

/* As a user: the color chosen in the panel, then the well's action. */
void sga_test_set_color(int a_id, int a_rgb)
{
	SGAColorWell *w = sga_get(a_id);
	[w setColor:sga_rgb_color(a_rgb)];
	[w sendAction:[w action] to:[w target]];
}

/* A scroll area: an NSScrollView whose document is a flipped wrapper holding the child at
   its natural size, at least as large as the visible area; scrollers come as needed. */
int sga_scroll_area(void)
{
	NSScrollView *s = [[NSScrollView alloc] init];
	[s setHasVerticalScroller:YES];
	[s setHasHorizontalScroller:YES];
	[s setAutohidesScrollers:YES];
	[s setDrawsBackground:NO];
	SGAWrapper *w = [[SGAWrapper alloc] init];
	[w setTranslatesAutoresizingMaskIntoConstraints:NO];
	[s setDocumentView:w];
	NSClipView *c = [s contentView];
	[NSLayoutConstraint activateConstraints:@[
		[w.leadingAnchor constraintEqualToAnchor:c.leadingAnchor],
		[w.topAnchor constraintEqualToAnchor:c.topAnchor],
		[w.widthAnchor constraintGreaterThanOrEqualToAnchor:c.widthAnchor],
		[w.heightAnchor constraintGreaterThanOrEqualToAnchor:c.heightAnchor]]];
	int l_id = sga_keep(s);
	s_inner[l_id] = w;
	return l_id;
}

void sga_scroll_area_set_content(int a_id, int a_child)
{
	SGAWrapper *w = s_inner[a_id];
	NSView *v = sga_get(a_child);
	for (NSView *l_old in [[w subviews] copy]) [l_old removeFromSuperview];
	[v setTranslatesAutoresizingMaskIntoConstraints:NO];
	[w addSubview:v];
	NSLayoutConstraint *l_fill_w = [v.widthAnchor constraintEqualToAnchor:w.widthAnchor];
	NSLayoutConstraint *l_fill_h = [v.heightAnchor constraintEqualToAnchor:w.heightAnchor];
	[l_fill_w setPriority:NSLayoutPriorityDefaultLow];
	[l_fill_h setPriority:NSLayoutPriorityDefaultLow];
	[NSLayoutConstraint activateConstraints:@[
		[v.leadingAnchor constraintEqualToAnchor:w.leadingAnchor],
		[v.topAnchor constraintEqualToAnchor:w.topAnchor],
		[v.trailingAnchor constraintLessThanOrEqualToAnchor:w.trailingAnchor],
		[v.bottomAnchor constraintLessThanOrEqualToAnchor:w.bottomAnchor],
		[w.widthAnchor constraintGreaterThanOrEqualToAnchor:v.widthAnchor],
		[w.heightAnchor constraintGreaterThanOrEqualToAnchor:v.heightAnchor],
		l_fill_w, l_fill_h]];
}

/* Scroll so that the point (x, y) of the content is at the top left, as far as it goes. */
void sga_scroll_area_scroll_to(int a_id, int a_x, int a_y)
{
	NSScrollView *s = sga_get(a_id);
	[[s documentView] scrollPoint:NSMakePoint(a_x, a_y)];
}

/* An image: an NSImageView that scales the picture down to fit, keeping its proportions. */
int sga_image(void)
{
	NSImageView *v = [[NSImageView alloc] init];
	[v setImageScaling:NSImageScaleProportionallyDown];
	[v setEditable:NO];
	[v setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];
	[v setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationVertical];
	return sga_keep(v);
}

/* 1 when the file held a picture AppKit reads (PNG, JPEG, GIF, TIFF, HEIC, PDF and more). */
int sga_image_set_file(int a_id, const char *a_path)
{
	NSImage *i = [[NSImage alloc] initWithContentsOfFile:sga_string(a_path)];
	[(NSImageView *)sga_get(a_id) setImage:i];
	return i ? 1 : 0;
}

int sga_image_set_bytes(int a_id, const void *a_bytes, int a_count)
{
	NSImage *i = a_count > 0 ? [[NSImage alloc] initWithData:[NSData dataWithBytes:a_bytes length:(NSUInteger)a_count]] : nil;
	[(NSImageView *)sga_get(a_id) setImage:i];
	return i ? 1 : 0;
}

/* A separator: a thin line across (horizontal) or down (vertical). */
int sga_separator(int a_vertical)
{
	NSBox *b = [[NSBox alloc] initWithFrame:a_vertical ? NSMakeRect(0, 0, 1, 20) : NSMakeRect(0, 0, 20, 1)];
	[b setBoxType:NSBoxSeparator];
	[b setTranslatesAutoresizingMaskIntoConstraints:NO];
	[[a_vertical ? b.widthAnchor : b.heightAnchor constraintEqualToConstant:1] setActive:YES];
	return sga_keep(b);
}

/* A group box: an NSBox with a title, its content inside with the box's own margins. */
int sga_group_box(const char *a_title)
{
	NSBox *b = [[NSBox alloc] init];
	[b setBoxType:NSBoxPrimary];
	[b setTitle:sga_string(a_title)];
	[b setTitlePosition:NSAtTop];
	[b setContentViewMargins:NSMakeSize(8, 8)];
	return sga_keep(b);
}

/* An NSBox places its content view by frame and does not size itself from that view's
   constraints, so a box given no height by its container (a window's whole content, say)
   came out as tall as its content alone, its title drawn over it. The child is pinned to
   the box itself instead, by the insets the box's own layout gives (title, border and
   content margins, measured on a sample frame), plus 4. */
static void sga_group_box_pin(NSBox *b)
{
	NSView *c = [b contentView];
	NSView *v = [[c subviews] firstObject];
	if (!v) return;
	NSRect l_was = [b frame];
	[b setFrame:NSMakeRect(0, 0, 400, 400)];
	NSRect f = [c frame];   /* in the box's (unflipped) coordinates */
	[b setFrame:l_was];
	CGFloat l_top = 400 - NSMaxY(f), l_bottom = NSMinY(f), l_start = NSMinX(f), l_end = 400 - NSMaxX(f);
	for (NSLayoutConstraint *k in [[b constraints] copy]) if ([[k identifier] isEqualToString:@"sga_group_pin"]) [k setActive:NO];
	NSArray<NSLayoutConstraint *> *l_pins = @[
		[v.leadingAnchor constraintEqualToAnchor:b.leadingAnchor constant:l_start + 4],
		[v.trailingAnchor constraintEqualToAnchor:b.trailingAnchor constant:-(l_end + 4)],
		[v.topAnchor constraintEqualToAnchor:b.topAnchor constant:l_top + 4],
		/* the box may be taller than its content (a window or stack gives it room) */
		[v.bottomAnchor constraintLessThanOrEqualToAnchor:b.bottomAnchor constant:-(l_bottom + 4)]];
	NSLayoutConstraint *l_snug = [v.bottomAnchor constraintEqualToAnchor:b.bottomAnchor constant:-(l_bottom + 4)];
	[l_snug setPriority:NSLayoutPriorityDefaultLow];
	l_pins = [l_pins arrayByAddingObject:l_snug];
	for (NSLayoutConstraint *k in l_pins) [k setIdentifier:@"sga_group_pin"];
	[NSLayoutConstraint activateConstraints:l_pins];
}

void sga_group_box_set_title(int a_id, const char *a_title) { NSBox *b = sga_get(a_id); [b setTitle:sga_string(a_title)]; sga_group_box_pin(b); }

void sga_group_box_set_content(int a_id, int a_child)
{
	NSBox *b = sga_get(a_id);
	NSView *c = [b contentView];
	NSView *v = sga_get(a_child);
	for (NSView *l_old in [[c subviews] copy]) [l_old removeFromSuperview];
	[v setTranslatesAutoresizingMaskIntoConstraints:NO];
	[c addSubview:v];
	sga_group_box_pin(b);
}

/* An expander: a disclosure triangle with a title, and the content it shows or hides
   below (AppKit has no one control for this; Finder's info window uses this pair). The
   whole header is the button, so a click on the title works too. Collapsed, the content
   takes no room. Toggling it sends toggled (12, a = 1 expanded). */
@interface SGAExpander : NSStackView
{
@public
	NSButton *triangle;
	NSButton *title;
	NSView *content;
}
@end
@implementation SGAExpander
- (void)show:(BOOL)a_on
{
	[triangle setState:a_on ? NSControlStateValueOn : NSControlStateValueOff];
	[content setHidden:!a_on];
}
- (void)toggled:(id)a_sender
{
	BOOL l_on = a_sender == title ? [triangle state] != NSControlStateValueOn : [triangle state] == NSControlStateValueOn;
	[self show:l_on];
	if (!s_suppress) sga_push(12, sga_id_of(self), l_on ? 1 : 0, 0, 0);
}
@end

int sga_expander(const char *a_title)
{
	SGAExpander *e = [[SGAExpander alloc] init];
	[e setOrientation:NSUserInterfaceLayoutOrientationVertical];
	[e setAlignment:NSLayoutAttributeLeading];
	[e setSpacing:6];
	e->triangle = [[NSButton alloc] init];
	[e->triangle setBezelStyle:NSBezelStyleDisclosure];
	[e->triangle setButtonType:NSButtonTypePushOnPushOff];
	[e->triangle setTitle:@""];
	[e->triangle setTarget:e];
	[e->triangle setAction:@selector(toggled:)];
	e->title = [NSButton buttonWithTitle:sga_string(a_title) target:e action:@selector(toggled:)];
	[e->title setBordered:NO];
	[e->title setAccessibilityElement:NO];   /* the triangle is the control; it carries the title */
	[[e->title cell] setAccessibilityElement:NO];
	[e->triangle setAccessibilityLabel:sga_string(a_title)];
	[[e->triangle cell] setAccessibilityLabel:sga_string(a_title)];
	NSStackView *l_header = [NSStackView stackViewWithViews:@[e->triangle, e->title]];
	[l_header setSpacing:2];
	[e addArrangedSubview:l_header];
	[e show:NO];
	return sga_keep(e);
}

void sga_expander_set_content(int a_id, int a_child)
{
	SGAExpander *e = sga_get(a_id);
	NSView *v = sga_get(a_child);
	BOOL l_on = [e->triangle state] == NSControlStateValueOn;
	if (e->content) [e removeArrangedSubview:e->content], [e->content removeFromSuperview];
	e->content = v;
	[e addArrangedSubview:v];
	[[v.trailingAnchor constraintLessThanOrEqualToAnchor:e.trailingAnchor] setActive:YES];
	[e show:l_on];
}

void sga_expander_set_expanded(int a_id, int a_on) { [(SGAExpander *)sga_get(a_id) show:a_on != 0]; }
int sga_expander_is_expanded(int a_id) { return [((SGAExpander *)sga_get(a_id))->triangle state] == NSControlStateValueOn ? 1 : 0; }
void sga_expander_set_title(int a_id, const char *a_title)
{
	SGAExpander *e = sga_get(a_id);
	[e->title setTitle:sga_string(a_title)];
	[e->triangle setAccessibilityLabel:sga_string(a_title)];
	[[e->triangle cell] setAccessibilityLabel:sga_string(a_title)];
}

/* As a user: a click on the triangle. */
void sga_test_toggle_expander(int a_id) { [((SGAExpander *)sga_get(a_id))->triangle performClick:nil]; }

/* An editable combo box: an NSComboBox. The text is committed by Return, by leaving the
   box, or by picking an option from its list; a commit that changes the text sends text
   changed (2). */
@interface SGAComboBox : NSComboBox <NSComboBoxDelegate>
{
@public
	NSString *committed;
}
@end
@implementation SGAComboBox
- (void)commit
{
	NSString *t = [self stringValue] ?: @"";
	if (![t isEqualToString:committed ?: @""]) {
		committed = [t copy];
		if (!s_suppress) sga_push(2, sga_id_of(self), 0, 0, 0);
	}
}
- (void)entered:(id)a_sender { (void)a_sender; [self commit]; }
- (void)controlTextDidEndEditing:(NSNotification *)n { (void)n; [self commit]; }
- (void)comboBoxSelectionDidChange:(NSNotification *)n
{
	(void)n;
	NSInteger i = [self indexOfSelectedItem];
	if (i >= 0) {
		/* The text follows the pick only after this notification: set it now, then commit. */
		[self setStringValue:[self itemObjectValueAtIndex:i]];
		[self commit];
	}
}
@end

int sga_combo_box(void)
{
	SGAComboBox *c = [[SGAComboBox alloc] init];
	[c setUsesDataSource:NO];
	[c setCompletes:YES];
	[c setDelegate:c];
	[c setTarget:c];
	[c setAction:@selector(entered:)];
	c->committed = @"";
	return sga_keep(c);
}

void sga_combo_box_extend(int a_id, const char *a_text) { [(NSComboBox *)sga_get(a_id) addItemWithObjectValue:sga_string(a_text)]; }
void sga_combo_box_wipe_out(int a_id) { [(NSComboBox *)sga_get(a_id) removeAllItems]; }
void sga_combo_box_set_text(int a_id, const char *a_text)
{
	SGAComboBox *c = sga_get(a_id);
	[c setStringValue:sga_string(a_text)];
	c->committed = [[c stringValue] copy];
}
const char *sga_combo_box_text(int a_id) { return sga_return(Kind_field, [(NSComboBox *)sga_get(a_id) stringValue]); }

/* As a user: text typed, then Return. */
void sga_test_type_combo(int a_id, const char *a_text)
{
	SGAComboBox *c = sga_get(a_id);
	[c setStringValue:sga_string(a_text)];
	[c commit];
}

/* ---------------------------------------------- 1j: the remaining controls */

/* A calendar: an NSDatePicker in its month-grid style, dates only. Its value and events are
   a date picker's (2, a = year * 10000 + month * 100 + day). */
int sga_calendar(void)
{
	int l_id = sga_date_picker();
	SGADatePicker *p = sga_get(l_id);
	[p setDatePickerStyle:NSDatePickerStyleClockAndCalendar];
	[p setDatePickerElements:NSDatePickerElementFlagYearMonthDay];
	[p setBezeled:NO];
	[p setDrawsBackground:NO];
	return l_id;
}

/* A menu button: a pull-down NSPopUpButton whose first item is the title; its menu is the
   program's (items send menu, 5). Split: an NSComboButton, whose main part sends click (1). */
/* The button's own menu is rebuilt from the program's menu each time it opens, so items
   the program adds later are there too (the program's menu itself is never changed). */
@interface SGAMenuSource : NSObject <NSMenuDelegate>
{
@public
	NSMenu *source;
	NSString *title;   /* a pull-down's first item, its title; nil for a split button */
}
@end
@implementation SGAMenuSource
- (void)menuNeedsUpdate:(NSMenu *)a_menu
{
	[a_menu removeAllItems];
	if (title) [a_menu addItemWithTitle:title action:NULL keyEquivalent:@""];
	for (NSMenuItem *i in [source itemArray]) [a_menu addItem:[i copy]];
}
@end

static NSMapTable<id, SGAMenuSource *> *s_menu_sources;   /* button -> its menu's source */

@interface SGAMenuButton : NSPopUpButton
@end
@implementation SGAMenuButton
@end

int sga_menu_button(const char *a_text, int a_split)
{
	if (a_split) {
		NSComboButton *b = [NSComboButton comboButtonWithTitle:sga_string(a_text) menu:[[NSMenu alloc] init] target:s_target action:@selector(clicked:)];
		[b setStyle:NSComboButtonStyleSplit];
		return sga_keep(b);
	}
	SGAMenuButton *b = [[SGAMenuButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
	[[b menu] addItemWithTitle:sga_string(a_text) action:NULL keyEquivalent:@""];
	return sga_keep(b);
}

/* The program's menu (a GUI_MENU's NSMenu) behind the button. A pull-down keeps its title item first. */
void sga_menu_button_set_menu(int a_id, void *a_menu)
{
	id b = sga_get(a_id);
	SGAMenuSource *l_source = [[SGAMenuSource alloc] init];
	NSMenu *l_shown = [[NSMenu alloc] init];
	l_source->source = (__bridge NSMenu *)a_menu;
	if (![b isKindOfClass:[NSComboButton class]]) l_source->title = [[(NSPopUpButton *)b itemAtIndex:0] title] ?: @"";
	[l_shown setDelegate:l_source];
	[l_source menuNeedsUpdate:l_shown];
	if (!s_menu_sources) s_menu_sources = [NSMapTable weakToStrongObjectsMapTable];
	[s_menu_sources setObject:l_source forKey:b];   /* a menu's delegate is weak: the button keeps it */
	if ([b isKindOfClass:[NSComboButton class]]) [(NSComboButton *)b setMenu:l_shown];
	else [(NSPopUpButton *)b setMenu:l_shown];
}

/* A level bar: an NSLevelIndicator in its continuous capacity style, with warning and
   critical values (yellow and red, as AppKit draws them). */
int sga_level_bar(int a_min, int a_max)
{
	NSLevelIndicator *l = [[NSLevelIndicator alloc] init];
	[l setLevelIndicatorStyle:NSLevelIndicatorStyleContinuousCapacity];
	[l setMinValue:a_min];
	[l setMaxValue:a_max];
	[l setIntegerValue:a_min];
	[l setEditable:NO];
	[l setTranslatesAutoresizingMaskIntoConstraints:NO];
	[[l.widthAnchor constraintGreaterThanOrEqualToConstant:100] setActive:YES];
	return sga_keep(l);
}

void sga_level_bar_set(int a_id, int a_value) { [(NSLevelIndicator *)sga_get(a_id) setIntegerValue:a_value]; }
int sga_level_bar_value(int a_id) { return (int)[(NSLevelIndicator *)sga_get(a_id) integerValue]; }
void sga_level_bar_set_warning(int a_id, int a_value) { [(NSLevelIndicator *)sga_get(a_id) setWarningValue:a_value]; }
void sga_level_bar_set_critical(int a_id, int a_value) { [(NSLevelIndicator *)sga_get(a_id) setCriticalValue:a_value]; }

/* A popover: an NSPopover, transient (a click outside or Escape closes it). The widget is a
   holder view that is the popover's content. The user's dismissal sends closed (17); `hide'
   from code sends nothing. */
@interface SGAPopover : SGAWrapper <NSPopoverDelegate>
{
@public
	NSPopover *popover;
	BOOL hiding;
}
@end
@implementation SGAPopover
- (void)popoverDidClose:(NSNotification *)n
{
	(void)n;
	if (!hiding && !s_suppress) sga_push(17, sga_id_of(self), 0, 0, 0);
	hiding = NO;
}
@end

/* The widest natural width in a view's tree (labels may shrink in a window, so a popover's
   fitted size alone would cut them short). */
static CGFloat sga_natural_width(NSView *v)
{
	CGFloat w = [v intrinsicContentSize].width > 0 ? [v intrinsicContentSize].width : 0;
	for (NSView *c in [v subviews]) w = MAX(w, sga_natural_width(c));
	return w;
}

/* The popover's size: its content at natural width (plus the holder's and a stack's margins). */
static NSSize sga_popover_size(SGAPopover *h)
{
	NSSize l_fit = [h fittingSize];
	return NSMakeSize(MAX(l_fit.width, sga_natural_width(h) + 48), l_fit.height);
}

int sga_popover(void)
{
	SGAPopover *h = [[SGAPopover alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
	NSViewController *c = [[NSViewController alloc] init];
	[c setView:h];
	h->popover = [[NSPopover alloc] init];
	[h->popover setContentViewController:c];
	[h->popover setBehavior:NSPopoverBehaviorTransient];
	[h->popover setAnimates:NO];   /* shown and closed at once: an inactive program's animation can stall */
	[h->popover setDelegate:h];
	return sga_keep(h);
}

void sga_popover_set_content(int a_id, int a_child)
{
	SGAPopover *h = sga_get(a_id);
	NSView *v = sga_get(a_child);
	for (NSView *l_old in [[h subviews] copy]) [l_old removeFromSuperview];
	[v setTranslatesAutoresizingMaskIntoConstraints:NO];
	[h addSubview:v];
	[NSLayoutConstraint activateConstraints:@[
		[v.leadingAnchor constraintEqualToAnchor:h.leadingAnchor constant:12],
		[v.trailingAnchor constraintEqualToAnchor:h.trailingAnchor constant:-12],
		[v.topAnchor constraintEqualToAnchor:h.topAnchor constant:12],
		[v.bottomAnchor constraintEqualToAnchor:h.bottomAnchor constant:-12]]];
	[h->popover setContentSize:sga_popover_size(h)];
}

void sga_popover_show_at(int a_id, int an_anchor)
{
	SGAPopover *h = sga_get(a_id);
	NSView *a = sga_get(an_anchor);
	[h->popover setContentSize:sga_popover_size(h)];
	[h->popover showRelativeToRect:[a bounds] ofView:a preferredEdge:NSRectEdgeMaxY];
}

void sga_popover_hide(int a_id)
{
	SGAPopover *h = sga_get(a_id);
	if ([h->popover isShown]) { h->hiding = YES; [h->popover performClose:nil]; [h->popover close]; }
}

int sga_popover_is_shown(int a_id) { return [((SGAPopover *)sga_get(a_id))->popover isShown] ? 1 : 0; }

/* As a user: Escape, or a click outside. */
void sga_test_dismiss_popover(int a_id)
{
	SGAPopover *h = sga_get(a_id);
	if ([h->popover isShown]) [h->popover performClose:nil];
}

/* A search field: an NSSearchField. Typing (and its clear button) sends text changed (2),
   as a field does; Return sends activate (3). */
@interface SGASearchField : NSSearchField <NSSearchFieldDelegate>
@end
@implementation SGASearchField
- (void)controlTextDidChange:(NSNotification *)n { (void)n; if (!s_suppress) sga_push(2, sga_id_of(self), 0, 0, 0); }
- (void)searched:(id)a_sender
{
	(void)a_sender;
	/* The action comes on Return and when the clear button empties the field. */
	if ([[self stringValue] length] == 0) { if (!s_suppress) sga_push(2, sga_id_of(self), 0, 0, 0); }
	else if (!s_suppress) sga_push(3, sga_id_of(self), 0, 0, 0);
}
@end

int sga_search_field(void)
{
	SGASearchField *f = [[SGASearchField alloc] init];
	[f setSendsSearchStringImmediately:NO];
	[f setSendsWholeSearchString:YES];
	[f setDelegate:f];
	[f setTarget:f];
	[f setAction:@selector(searched:)];
	return sga_keep(f);
}

/* A token field: an NSTokenField; a comma or Return makes a token. The tokens are its
   object value, an array of strings. A change in the tokens sends text changed (2). */
@interface SGATokenField : NSTokenField <NSTokenFieldDelegate>
{
@public
	NSArray *last;
}
@end
@implementation SGATokenField
- (NSArray<NSString *> *)tokens
{
	NSMutableArray *a = [NSMutableArray array];
	id v = [self objectValue];
	if ([v isKindOfClass:[NSArray class]]) for (id t in v) if ([t isKindOfClass:[NSString class]] && [t length]) [a addObject:t];
	return a;
}
- (void)check
{
	NSArray *t = [self tokens];
	if (![t isEqualToArray:last ?: @[]]) {
		last = [t copy];
		if (!s_suppress) sga_push(2, sga_id_of(self), (int)[t count], 0, 0);
	}
}
- (void)controlTextDidEndEditing:(NSNotification *)n { (void)n; [self check]; }
- (void)controlTextDidChange:(NSNotification *)n { (void)n; [self check]; }
- (void)entered:(id)a_sender { (void)a_sender; [self check]; }
@end

/* The chips' rectangles (field coordinates), in token order: the field's attributed string
   holds one attachment per token, laid out at the field's text width (AppKit has no public
   rectangle for a token). */
static NSArray<NSValue *> *sga_token_rects(SGATokenField *f)
{
	NSMutableArray<NSValue *> *r = [NSMutableArray array];
	NSAttributedString *a = [f attributedStringValue];
	NSRect l_text = [[f cell] drawingRectForBounds:[f bounds]];
	NSTextStorage *l_store = [[NSTextStorage alloc] initWithAttributedString:a];
	NSLayoutManager *l_layout = [[NSLayoutManager alloc] init];
	NSTextContainer *l_box = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(l_text.size.width, CGFLOAT_MAX)];
	[l_box setLineFragmentPadding:0];
	[l_layout addTextContainer:l_box];
	[l_store addLayoutManager:l_layout];
	[l_layout ensureLayoutForTextContainer:l_box];
	for (NSUInteger i = 0; i < [a length]; i++) {
		if ([a attribute:NSAttachmentAttributeName atIndex:i effectiveRange:NULL]) {
			NSRect g = [l_layout boundingRectForGlyphRange:[l_layout glyphRangeForCharacterRange:NSMakeRange(i, 1) actualCharacterRange:NULL] inTextContainer:l_box];
			g = NSOffsetRect(g, NSMinX(l_text), NSMinY(l_text));
			if (![f isFlipped]) g.origin.y = NSMaxY([f bounds]) - NSMaxY(g);
			[r addObject:[NSValue valueWithRect:g]];
		}
	}
	return r;
}

/* The token (from 1) whose chip holds `p' (field coordinates); past the last chip, the count + 1. */
static int sga_token_at(SGATokenField *f, NSPoint p)
{
	NSArray<NSValue *> *l_rects = sga_token_rects(f);
	for (NSUInteger i = 0; i < [l_rects count]; i++) {
		NSRect g = [l_rects[i] rectValue];
		if (p.x < NSMaxX(g) && p.y >= NSMinY(g) - 2 && p.y <= NSMaxY(g) + 2) return (int)i + 1;
	}
	return (int)[l_rects count] + 1;
}

int sga_token_field(void)
{
	SGATokenField *f = [[SGATokenField alloc] init];
	[f setTokenizingCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@",\n"]];
	[f setTokenStyle:NSTokenStyleRounded];
	[f setDelegate:f];
	[f setTarget:f];
	[f setAction:@selector(entered:)];
	f->last = @[];
	return sga_keep(f);
}

static void sga_token_field_put(SGATokenField *f, NSArray *a_tokens)
{
	[f setObjectValue:a_tokens];
	f->last = [[f tokens] copy];
}

void sga_token_field_extend(int a_id, const char *a_text) { SGATokenField *f = sga_get(a_id); sga_token_field_put(f, [[f tokens] arrayByAddingObject:sga_string(a_text)]); }
void sga_token_field_remove(int a_id, int i) { SGATokenField *f = sga_get(a_id); NSMutableArray *a = [[f tokens] mutableCopy]; if (i >= 1 && i <= (int)[a count]) [a removeObjectAtIndex:(NSUInteger)(i - 1)]; sga_token_field_put(f, a); }
void sga_token_field_wipe_out(int a_id) { sga_token_field_put(sga_get(a_id), @[]); }
int sga_token_field_count(int a_id) { return (int)[[(SGATokenField *)sga_get(a_id) tokens] count]; }
const char *sga_token_field_item(int a_id, int i) { return sga_return(Kind_label, [(SGATokenField *)sga_get(a_id) tokens][(NSUInteger)(i - 1)]); }

/* As a user: `a_text' typed, then Return. */
void sga_test_type_tokens(int a_id, const char *a_text)
{
	SGATokenField *f = sga_get(a_id);
	NSMutableArray *a = [[f tokens] mutableCopy];
	for (NSString *t in [sga_string(a_text) componentsSeparatedByCharactersInSet:[f tokenizingCharacterSet]]) {
		NSString *l_trim = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if ([l_trim length]) [a addObject:l_trim];
	}
	[f setObjectValue:a];
	[f check];
}

/* A path control: an NSPathControl, standard style. A click on a part sends selection (4,
   a = the part, 1 = the root). The control does not navigate; the program does.
   1p-b: with chevrons on, the standard style's own "›" after each part is a button (53,
   a = the part before it), and one more "›" is drawn after the last part. A click on the
   empty space after them, or Command+L with the control focused, sends 54. */
@interface SGAPathControl : NSPathControl
{
@public
	BOOL chevrons;
	NSString *root_icon;
}
@end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
/* Each part's rectangle (its "›" included, at its trailing end), in the control's bounds. */
static NSArray<NSValue *> *sga_path_part_rects(NSPathControl *c)
{
	NSPathCell *l_cell = [c cell];
	NSMutableArray *a = [NSMutableArray array];
	for (NSPathComponentCell *k in [l_cell pathComponentCells]) [a addObject:[NSValue valueWithRect:[l_cell rectOfPathComponentCell:k withFrame:[c bounds] inView:c]]];
	return a;
}
#pragma clang diagnostic pop

static const CGFloat Path_chevron = 14;   /* the width of a "›" and its gaps */

/* Where `x' falls: the part (> 0), the "›" after part k (-k), or the empty space (0). */
static NSInteger sga_path_hit(SGAPathControl *c, CGFloat x)
{
	NSArray<NSValue *> *r = sga_path_part_rects(c);
	NSUInteger n = [r count];
	for (NSUInteger k = 0; k < n; k++) {
		NSRect f = [r[k] rectValue];
		if (x >= NSMinX(f) && x < NSMaxX(f)) return (k + 1 < n && x >= NSMaxX(f) - Path_chevron) ? -(NSInteger)(k + 1) : (NSInteger)(k + 1);
	}
	CGFloat l_end = n ? NSMaxX([r[n - 1] rectValue]) : 0;
	if (x >= l_end && x < l_end + Path_chevron) return -(NSInteger)MAX(n, (NSUInteger)1);
	return 0;
}

@implementation SGAPathControl
- (BOOL)acceptsFirstResponder { return chevrons || [super acceptsFirstResponder]; }
- (void)mouseDown:(NSEvent *)e
{
	if (!chevrons) { [super mouseDown:e]; return; }
	NSInteger h = sga_path_hit(self, [self convertPoint:[e locationInWindow] fromView:nil].x);
	if (h > 0) [super mouseDown:e];
	else if (!s_suppress) { sga_push(h < 0 ? 53 : 54, sga_id_of(self), h < 0 ? (int)-h : 0, 0, 0); sga_wake(); }
}
- (BOOL)performKeyEquivalent:(NSEvent *)e
{
	NSEventModifierFlags m = [e modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
	if (chevrons && [[self window] firstResponder] == self && m == NSEventModifierFlagCommand && [[e charactersIgnoringModifiers] isEqualToString:@"l"]) {
		sga_push(54, sga_id_of(self), 0, 0, 0); sga_wake();
		return YES;
	}
	return [super performKeyEquivalent:e];
}
- (void)keyDown:(NSEvent *)e
{
	if (chevrons && [e keyCode] == 118) { sga_push(54, sga_id_of(self), 0, 0, 0); sga_wake(); return; }   /* F4 */
	[super keyDown:e];
}
- (void)drawRect:(NSRect)a_dirty
{
	[super drawRect:a_dirty];
	if (!chevrons) return;
	/* the "›" after the last part, as the standard style draws the others */
	NSArray<NSValue *> *r = sga_path_part_rects(self);
	CGFloat x = [r count] ? NSMaxX([[r lastObject] rectValue]) : 0;
	NSDictionary *a = @{NSFontAttributeName: [self font] ?: [NSFont systemFontOfSize:0], NSForegroundColorAttributeName: [NSColor secondaryLabelColor]};
	NSSize z = [@"›" sizeWithAttributes:a];
	[@"›" drawAtPoint:NSMakePoint(x - 2, NSMidY([self bounds]) - z.height / 2) withAttributes:a];
}
- (NSSize)intrinsicContentSize
{
	NSSize z = [super intrinsicContentSize];
	if (chevrons && z.width != NSViewNoIntrinsicMetric) z.width += Path_chevron;
	return z;
}
- (void)picked:(id)a_sender
{
	(void)a_sender;
	NSPathControlItem *i = [self clickedPathItem];
	NSUInteger k = i ? [[self pathItems] indexOfObject:i] : NSNotFound;
	if (k != NSNotFound && !s_suppress) sga_push(4, sga_id_of(self), (int)k + 1, 0, 0);
}
@end

int sga_path_control(void)
{
	SGAPathControl *p = [[SGAPathControl alloc] init];
	[p setPathStyle:NSPathStyleStandard];
	[p setTarget:p];
	[p setAction:@selector(picked:)];
	[p setEditable:NO];
	return sga_keep(p);
}

static NSString *sga_symbol_of(NSString *a_name);
/* 1p-b: the root icon in front of part 1 (an SF Symbol for a GUI_ICON name). */
static void sga_path_apply_root(SGAPathControl *c)
{
	NSArray<NSPathControlItem *> *l_items = [c pathItems];
	if (![l_items count] || ![c->root_icon length]) return;
	NSImage *i = [[NSImage imageWithSystemSymbolName:sga_symbol_of(c->root_icon) accessibilityDescription:nil]
		imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:[NSFont smallSystemFontSize] weight:NSFontWeightRegular]];
	if (i) {
		/* centered in a square the size of a path's folder icons: the cell squeezes other shapes */
		NSSize z = [i size];
		CGFloat k = 13 / MAX(z.width, z.height);
		NSSize l_fit = NSMakeSize(z.width * k, z.height * k);
		NSImage *q = [NSImage imageWithSize:NSMakeSize(16, 16) flipped:NO drawingHandler:^BOOL(NSRect a_rect) {
			[i drawInRect:NSMakeRect((NSWidth(a_rect) - l_fit.width) / 2, (NSHeight(a_rect) - l_fit.height) / 2, l_fit.width, l_fit.height)];
			return YES;
		}];
		[q setTemplate:YES];
		[l_items[0] setImage:q];
	}
	[c setNeedsDisplay:YES];
}
void sga_path_control_set(int a_id, const char *a_path) { [(NSPathControl *)sga_get(a_id) setURL:[NSURL fileURLWithPath:sga_string(a_path)]]; sga_path_apply_root(sga_get(a_id)); }
/* 1t: breadcrumbs for anything: one item per part, titled exactly (separated by 0x1F). */
void sga_path_control_set_parts(int a_id, const char *a_parts)
{
	NSMutableArray<NSPathControlItem *> *l_items = [NSMutableArray array];
	for (NSString *l_part in [sga_string(a_parts) componentsSeparatedByString:@"\x1f"]) {
		if (![l_part length]) continue;
		NSPathControlItem *i = [[NSPathControlItem alloc] init];
		[i setTitle:l_part];
		[l_items addObject:i];
	}
	[(NSPathControl *)sga_get(a_id) setPathItems:l_items];
	sga_path_apply_root(sga_get(a_id));
}

void sga_path_control_set_chevrons(int a_id, int a_on)
{
	SGAPathControl *c = sga_get(a_id);
	c->chevrons = a_on != 0;
	[c invalidateIntrinsicContentSize];
	[c setNeedsDisplay:YES];
}

void sga_path_control_set_root_icon(int a_id, const char *a_name)
{
	SGAPathControl *c = sga_get(a_id);
	NSString *l_old = c->root_icon;
	c->root_icon = sga_string(a_name);
	if ([c->root_icon length]) sga_path_apply_root(c);
	else if ([l_old length] && [[c pathItems] count]) {
		/* back to the part's own image: a path's folder icon, or none */
		if ([c URL]) [c setURL:[c URL]]; else [[c pathItems][0] setImage:nil];
	}
}

void sga_test_press_chevron(int a_id, int a_part) { sga_push(53, a_id, a_part, 0, 0); sga_wake(); }
void sga_test_press_path_space(int a_id) { sga_push(54, a_id, 0, 0, 0); sga_wake(); }
int sga_path_control_count(int a_id) { return (int)[[(NSPathControl *)sga_get(a_id) pathItems] count]; }
const char *sga_path_control_part(int a_id, int i) { return sga_return(Kind_label, [[(NSPathControl *)sga_get(a_id) pathItems][(NSUInteger)(i - 1)] title]); }

/* A rating: an NSLevelIndicator in its rating style, editable; a user's click sends text
   changed (2, a = the stars). */
@interface SGARating : NSLevelIndicator
{
@public
	NSInteger last;
}
@end
@implementation SGARating
- (void)rated:(id)a_sender
{
	NSInteger v = [self integerValue];
	(void)a_sender;
	if (v != last) { last = v; if (!s_suppress) sga_push(2, sga_id_of(self), (int)v, 0, 0); }
}
@end

int sga_rating(int a_maximum)
{
	SGARating *r = [[SGARating alloc] init];
	[r setLevelIndicatorStyle:NSLevelIndicatorStyleRating];
	[r setMinValue:0];
	[r setMaxValue:a_maximum];
	[r setIntegerValue:0];
	[r setEditable:YES];
	[r setTarget:r];
	[r setAction:@selector(rated:)];
	return sga_keep(r);
}

void sga_rating_set(int a_id, int a_value) { SGARating *r = sga_get(a_id); [r setIntegerValue:a_value]; r->last = a_value; }
int sga_rating_value(int a_id) { return (int)[(NSLevelIndicator *)sga_get(a_id) integerValue]; }

/* As a user: a click on star `a_value'. */
void sga_test_rate(int a_id, int a_value) { SGARating *r = sga_get(a_id); [r setIntegerValue:a_value]; [r sendAction:[r action] to:[r target]]; }

/* A rich text area (1j): a text area whose NSTextView keeps attributes. Positions are
   1-based characters (code points, as an Eiffel STRING_32 counts them); a range is
   `a_start' .. `an_end', inclusive. Formatting from code is silent: AppKit sends
   textDidChange only for the user's edits. */
int sga_rich_text_area(void)
{
	int l_id = sga_text_area();
	NSTextView *t = s_inner[l_id];
	[t setRichText:YES];
	[t setImportsGraphics:NO];
	[t setUsesFontPanel:YES];
	return l_id;
}

/* The UTF-16 offset of code point `a_index' (0-based) in `s'. */
static NSUInteger sga_utf16_offset(NSString *s, NSInteger a_index)
{
	NSUInteger k = 0, n = [s length];
	for (NSInteger i = 0; i < a_index && k < n; i++) {
		unichar c = [s characterAtIndex:k];
		k += (CFStringIsSurrogateHighCharacter(c) && k + 1 < n) ? 2 : 1;
	}
	return k;
}

/* The code-point index (0-based) of UTF-16 offset `an_offset' in `s'. */
static NSInteger sga_code_point_index(NSString *s, NSUInteger an_offset)
{
	NSInteger i = 0;
	for (NSUInteger k = 0; k < an_offset && k < [s length]; i++) {
		unichar c = [s characterAtIndex:k];
		k += (CFStringIsSurrogateHighCharacter(c) && k + 1 < [s length]) ? 2 : 1;
	}
	return i;
}

/* Colors wait, and go to their text in one edit.
   A text storage tells its layout manager of every edit that is not inside a group, and
   for a text already on screen that costs time that grows with the text: the 60,000 color
   runs of a 10,000-line text, each its own edit, took 44 seconds; in one edit they take
   some 12 milliseconds. The Eiffel side sends one color at a time, so the colors wait
   here and `sga_colors_flush' applies them, in the order they came, grouped. It runs
   before anything can tell the difference: before the run loop turns (events, drawing),
   before an attribute is read or another one set, before a view is drawn into an image,
   and before the characters change (a waiting range is that of the text as it was when
   the color came). Should characters change with colors still waiting all the same,
   `sga_colors_moved' moves the ranges as the text moved. */
typedef struct { NSUInteger from, length; int rgb; } sga_color_run;
static NSTextStorage *s_color_storage;   /* the text the waiting colors are for */
static sga_color_run *s_color_runs;
static NSUInteger s_color_count, s_color_room;
#define SGA_COLOR_MOST 65536             /* no more than these wait */
#define SGA_COLOR_GAP 4096               /* runs farther apart than this get edits of their own */

static void sga_colors_flush(void)
{
	if (!s_color_count) return;
	NSTextStorage *m = s_color_storage;
	NSUInteger l_count = s_color_count, l_length = [m length], l_low = 0, l_high = 0;
	s_color_count = 0;
	s_color_storage = nil;
	NSColor *l_color = nil;
	int l_rgb = -1;
	BOOL l_open = NO;
	for (NSUInteger i = 0; i < l_count; i++) {
		sga_color_run r = s_color_runs[i];
		if (r.from >= l_length || !r.length) continue;
		r.length = MIN(r.length, l_length - r.from);
		/* One edit tells the layout manager one range, from its first run to its last. Runs
		   far from the others get an edit of their own, so that two changed lines do not
		   cost all the text between them. */
		if (l_open && (r.from > l_high + SGA_COLOR_GAP || r.from + r.length + SGA_COLOR_GAP < l_low)) { [m endEditing]; l_open = NO; }
		if (!l_open) { [m beginEditing]; l_open = YES; l_low = r.from; l_high = r.from + r.length; }
		l_low = MIN(l_low, r.from);
		l_high = MAX(l_high, r.from + r.length);
		/* -1 is the default color: the attribute goes, so the text follows the appearance */
		if (r.rgb < 0) [m removeAttribute:NSForegroundColorAttributeName range:NSMakeRange(r.from, r.length)];
		else {
			if (!l_color || r.rgb != l_rgb) { l_color = sga_rgb_color(r.rgb); l_rgb = r.rgb; }
			[m addAttribute:NSForegroundColorAttributeName value:l_color range:NSMakeRange(r.from, r.length)];
		}
	}
	if (l_open) [m endEditing];
}

/* The characters of the text changed with colors waiting: `a_new' is the changed range as
   it is now, `a_delta' what it grew by. A run before the change stays, a run after it
   moves, and a run across it keeps what lies outside the change (with the new text, when
   it reaches out on both sides). */
static void sga_colors_moved(NSRange a_new, NSInteger a_delta)
{
	NSUInteger l_from = a_new.location, l_new_end = NSMaxRange(a_new);
	NSUInteger l_old_end = (NSUInteger)MAX((NSInteger)l_new_end - a_delta, (NSInteger)l_from);
	for (NSUInteger i = 0; i < s_color_count; i++) {
		sga_color_run *r = &s_color_runs[i];
		NSUInteger a = r->from, b = a + r->length;
		if (b <= l_from) continue;
		if (a >= l_old_end) { r->from = (NSUInteger)((NSInteger)a + a_delta); continue; }
		NSUInteger l_a = a < l_from ? a : l_new_end;
		NSUInteger l_b = b > l_old_end ? (NSUInteger)((NSInteger)b + a_delta) : l_from;
		r->from = l_a;
		r->length = l_b > l_a ? l_b - l_a : 0;
	}
}

/* Positions in a text view's own text, without a walk from its start.
   The two functions above walk the string for every answer, one characterAtIndex: call
   for each character. That is right for one line. For the text of a view it is not: a
   code editor colors a 10,000-line text in some 60,000 runs, two positions each, and
   those walks took 158 seconds. So for a text storage the answers are kept:
   - `s_pos_table': the offset of every `SGA_POS_STEP'th code point, made in one pass
     over the text, so a position is a look in the table and a walk of less than one step;
   - `s_pos_pairs': whether the text holds a surrogate pair at all. Mostly it does not,
     and then a position is its offset.
   They stand until the characters of a text storage change, which every storage tells
   in its notification (a change of attributes alone leaves them). The answers are those
   of the two functions above, for every text. */
#define SGA_POS_STEP 256
static NSUInteger s_text_generation;          /* goes up when the characters of any text storage change */
static __weak NSTextStorage *s_pos_storage;   /* the text the answers below are for */
static NSUInteger s_pos_generation, s_pos_length;
static BOOL s_pos_pairs;
static NSUInteger *s_pos_table;
static NSUInteger s_pos_slots, s_pos_room;
static NSInteger s_pos_count;                 /* its code points */

/* Make the kept answers those of `m' as it is now. */
static void sga_pos_sync(NSTextStorage *m)
{
	static BOOL l_watching;
	if (!l_watching) {
		l_watching = YES;
		[[NSNotificationCenter defaultCenter] addObserverForName:NSTextStorageDidProcessEditingNotification object:nil queue:nil usingBlock:^(NSNotification *n) {
			NSTextStorage *l_edited = [n object];
			if ([l_edited editedMask] & NSTextStorageEditedCharacters) {
				s_text_generation++;
				if (s_color_count && l_edited == s_color_storage) sga_colors_moved([l_edited editedRange], [l_edited changeInLength]);
			}
		}];
	}
	NSString *s = [m string];
	NSUInteger n = [s length];
	if (m && s_pos_storage == m && s_pos_generation == s_text_generation && s_pos_length == n) return;
	s_pos_storage = m; s_pos_generation = s_text_generation; s_pos_length = n;
	s_pos_pairs = NO; s_pos_slots = 0;
	unichar l_buffer[1024];
	NSInteger i = 0;      /* the code points before unit `k' */
	BOOL l_second = NO;   /* is unit `k' the second half of a pair? */
	for (NSUInteger k = 0; k < n; ) {
		NSUInteger c = MIN((NSUInteger)1024, n - k);
		[s getCharacters:l_buffer range:NSMakeRange(k, c)];
		for (NSUInteger j = 0; j < c; j++, k++) {
			if (l_second) { l_second = NO; continue; }
			if (i % SGA_POS_STEP == 0) {
				if (s_pos_slots == s_pos_room) {
					s_pos_room = s_pos_room ? 2 * s_pos_room : 1024;
					s_pos_table = realloc(s_pos_table, s_pos_room * sizeof(NSUInteger));
				}
				s_pos_table[s_pos_slots++] = k;
			}
			if (CFStringIsSurrogateHighCharacter(l_buffer[j]) && k + 1 < n) { l_second = YES; s_pos_pairs = YES; }
			i++;
		}
	}
	s_pos_count = i;
}

/* The UTF-16 offset of code point `a_index' (0-based) in the text of `m'. */
static NSUInteger sga_text_offset(NSTextStorage *m, NSInteger a_index)
{
	if (a_index <= 0) return 0;
	sga_pos_sync(m);
	if (a_index >= s_pos_count) return s_pos_length;
	if (!s_pos_pairs) return (NSUInteger)a_index;
	NSUInteger k = s_pos_table[a_index / SGA_POS_STEP], n = s_pos_length, j = 0;
	NSInteger l_left = a_index % SGA_POS_STEP;
	unichar l_buffer[2 * SGA_POS_STEP];
	NSUInteger c = MIN((NSUInteger)(2 * l_left), n - k);
	[[m string] getCharacters:l_buffer range:NSMakeRange(k, c)];
	for (; l_left > 0 && j < c; l_left--) j += (CFStringIsSurrogateHighCharacter(l_buffer[j]) && k + j + 1 < n) ? 2 : 1;
	return MIN(k + j, n);
}

/* The code-point index (0-based) of UTF-16 offset `an_offset' in the text of `m'. */
static NSInteger sga_text_index(NSTextStorage *m, NSUInteger an_offset)
{
	sga_pos_sync(m);
	if (an_offset >= s_pos_length) return s_pos_count;
	if (!s_pos_pairs) return (NSInteger)an_offset;
	/* the last entry of the table at or before the offset */
	NSUInteger l_low = 0, l_high = s_pos_slots;
	while (l_high - l_low > 1) {
		NSUInteger l_mid = (l_low + l_high) / 2;
		if (s_pos_table[l_mid] <= an_offset) l_low = l_mid; else l_high = l_mid;
	}
	NSUInteger k = s_pos_table[l_low], n = s_pos_length;
	NSInteger i = (NSInteger)(l_low * SGA_POS_STEP);
	unichar l_buffer[2 * SGA_POS_STEP];
	NSUInteger c = MIN(an_offset - k, (NSUInteger)(2 * SGA_POS_STEP));
	[[m string] getCharacters:l_buffer range:NSMakeRange(k, c)];
	for (NSUInteger j = 0; j < c; i++) j += (CFStringIsSurrogateHighCharacter(l_buffer[j]) && k + j + 1 < n) ? 2 : 1;
	return i;
}

/* The line breaks in units `a_from' up to (not with) `a_to' of `s'; `a_start', when given, gets
   where the last line among them starts (`a_from' when there is no break). Read in
   blocks, not with one characterAtIndex: call for each character. */
static NSUInteger sga_line_breaks(NSString *s, NSUInteger a_from, NSUInteger a_to, NSUInteger *a_start)
{
	unichar l_buffer[1024];
	NSUInteger l_count = 0, l_start = a_from;
	a_to = MIN(a_to, [s length]);
	for (NSUInteger k = a_from; k < a_to; ) {
		NSUInteger c = MIN((NSUInteger)1024, a_to - k);
		[s getCharacters:l_buffer range:NSMakeRange(k, c)];
		for (NSUInteger j = 0; j < c; j++) if (l_buffer[j] == '\n') { l_count++; l_start = k + j + 1; }
		k += c;
	}
	if (a_start) *a_start = l_start;
	return l_count;
}

static NSRange sga_rich_range(NSTextView *t, int a_start, int an_end)
{
	NSTextStorage *m = [t textStorage];
	NSUInteger l_from = sga_text_offset(m, a_start - 1), l_to = sga_text_offset(m, an_end);
	return NSMakeRange(l_from, l_to > l_from ? l_to - l_from : 0);
}

/* Bold (1), italic (2) or underline (3), on or off, over a range. */
void sga_rich_text_set_trait(int a_id, int a_start, int an_end, int a_trait, int a_on)
{
	NSTextView *t = s_inner[a_id];
	NSTextStorage *m = [t textStorage];
	NSRange r = sga_rich_range(t, a_start, an_end);
	if (r.length == 0) return;
	sga_colors_flush();
	[m beginEditing];
	if (a_trait == 3) {
		if (a_on) [m addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:r];
		else [m removeAttribute:NSUnderlineStyleAttributeName range:r];
	} else {
		NSFontManager *f = [NSFontManager sharedFontManager];
		NSFontTraitMask l_trait = a_trait == 1 ? NSBoldFontMask : NSItalicFontMask;
		[m enumerateAttribute:NSFontAttributeName inRange:r options:0 usingBlock:^(id a_font, NSRange a_run, BOOL *a_stop) {
			(void)a_stop;
			NSFont *l_font = a_font ?: [t font] ?: [NSFont systemFontOfSize:0];
			l_font = a_on ? [f convertFont:l_font toHaveTrait:l_trait] : [f convertFont:l_font toNotHaveTrait:l_trait];
			[m addAttribute:NSFontAttributeName value:l_font range:a_run];
		}];
	}
	[m endEditing];
}

void sga_rich_text_set_color(int a_id, int a_start, int an_end, int a_rgb)
{
	NSTextView *t = s_inner[a_id];
	NSTextStorage *m = [t textStorage];
	NSRange r = sga_rich_range(t, a_start, an_end);
	if (!r.length || !m) return;
	/* The color waits (see `sga_colors_flush'). Every run loop of the main thread, whichever
	   mode it runs in (a dialog's, a menu's, a drag's), applies what waits before it does
	   anything else. */
	static CFRunLoopObserverRef l_observer;
	if (!l_observer) {
		l_observer = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopEntry | kCFRunLoopBeforeTimers | kCFRunLoopBeforeSources | kCFRunLoopBeforeWaiting, true, 0,
			^(CFRunLoopObserverRef an_observer, CFRunLoopActivity an_activity) { (void)an_observer; (void)an_activity; sga_colors_flush(); });
		CFRunLoopAddObserver(CFRunLoopGetMain(), l_observer, kCFRunLoopCommonModes);
	}
	if (s_color_count && (s_color_storage != m || s_color_count >= SGA_COLOR_MOST)) sga_colors_flush();
	if (s_color_count == s_color_room) {
		s_color_room = s_color_room ? s_color_room * 2 : 256;
		s_color_runs = realloc(s_color_runs, s_color_room * sizeof(sga_color_run));
	}
	s_color_storage = m;
	s_color_runs[s_color_count++] = (sga_color_run){r.location, r.length, a_rgb < 0 ? -1 : a_rgb};
}

void sga_rich_text_set_size(int a_id, int a_start, int an_end, double a_points)
{
	NSTextView *t = s_inner[a_id];
	NSTextStorage *m = [t textStorage];
	NSRange r = sga_rich_range(t, a_start, an_end);
	if (r.length == 0 || a_points <= 0) return;
	sga_colors_flush();
	[m beginEditing];
	[m enumerateAttribute:NSFontAttributeName inRange:r options:0 usingBlock:^(id a_font, NSRange a_run, BOOL *a_stop) {
		(void)a_stop;
		NSFont *l_font = a_font ?: [t font] ?: [NSFont systemFontOfSize:0];
		[m addAttribute:NSFontAttributeName value:[[NSFontManager sharedFontManager] convertFont:l_font toSize:a_points] range:a_run];
	}];
	[m endEditing];
}

static NSDictionary *sga_rich_attributes_at(int a_id, int i)
{
	NSTextView *t = s_inner[a_id];
	sga_colors_flush();
	NSUInteger k = sga_text_offset([t textStorage], i - 1);
	return k < [[t textStorage] length] ? [[t textStorage] attributesAtIndex:k effectiveRange:NULL] : @{};
}

/* 1 when character `i' has the trait (1 bold, 2 italic, 3 underline). */
int sga_rich_text_trait_at(int a_id, int i, int a_trait)
{
	NSDictionary *d = sga_rich_attributes_at(a_id, i);
	if (a_trait == 3) return [d[NSUnderlineStyleAttributeName] integerValue] != 0 ? 1 : 0;
	NSFont *f = d[NSFontAttributeName];
	NSFontDescriptorSymbolicTraits l_traits = f ? [[f fontDescriptor] symbolicTraits] : 0;
	return (l_traits & (a_trait == 1 ? NSFontDescriptorTraitBold : NSFontDescriptorTraitItalic)) ? 1 : 0;
}

/* Character `i''s color as 0xRRGGBB; -1 when it has the default (the theme's text color). */
int sga_rich_text_color_at(int a_id, int i)
{
	NSColor *c = sga_rich_attributes_at(a_id, i)[NSForegroundColorAttributeName];
	/* A rich text view gives new text its own text color as an attribute: that is the default.
	   (Not [t textColor]: NSTextView answers the first character's color there, so a colored
	   first character would read as the default.) */
	BOOL l_default = !c || [c isEqual:[NSColor textColor]] || [c isEqual:[NSColor labelColor]];
	return l_default ? -1 : sga_color_rgb(c);
}

double sga_rich_text_size_at(int a_id, int i)
{
	NSFont *f = sga_rich_attributes_at(a_id, i)[NSFontAttributeName] ?: [(NSTextView *)s_inner[a_id] font];
	return f ? (double)[f pointSize] : 0;
}

/* The selection, 1-based: start, and end (start - 1 when nothing is selected, at the caret). */
int sga_rich_text_selection_start(int a_id)
{
	NSTextView *t = s_inner[a_id];
	return (int)sga_text_index([t textStorage], [t selectedRange].location) + 1;
}

int sga_rich_text_selection_end(int a_id)
{
	NSTextView *t = s_inner[a_id];
	NSRange r = [t selectedRange];
	return (int)sga_text_index([t textStorage], NSMaxRange(r));
}

static BOOL sga_is_code_view(id t);   /* 1v-e-2: defined after SGACodeView */

/* In a code editor this is the program's own move (1v-e-2): no caret event (52), and the
   caret comes into view, as go to line does. */
void sga_rich_text_select(int a_id, int a_start, int an_end)
{
	NSTextView *t = s_inner[a_id];
	NSRange r = sga_rich_range(t, a_start, an_end);
	sga_colors_flush();
	if (sga_is_code_view(t)) {
		s_suppress++;
		[t setSelectedRange:r];
		[t scrollRangeToVisible:NSMakeRange(r.location, 0)];
		s_suppress--;
		return;
	}
	[t setSelectedRange:r];
}

/* ------------------------------------------------- 1i: the drawn-widget view */

/* The view a GUI_DRAWN hosts a simple_widgets window in: a canvas with the whole input SW
   needs (spec 1i). Positions are logical pixels; GUI_DRAWN converts to device pixels.
   18 pointer (c = kind + button * 16 + modifiers * 256; kind 1 press, 2 release, 3 move,
   4 leave, 5 double press, 6 triple press; button 1 primary, 2 secondary, 3 middle),
   19 wheel (c = delta, 120 a notch, positive away from the user), 20 key (a = GDK keyval,
   b = 1 down or 0 up), 21 character (a = code point), 22 focus (a = 1 in), 23 timers
   (a = 0 the tick, 1 the fast tick, 2 the dwell shot with b = its serial). */
@interface SGADrawn : SGACanvas <NSTextInputClient>
{
@public
	int cursor_kind;
	NSString *description;   /* the hosted window's accessibility tree, as GUI_DRAWN last gave it */
	NSTimer *tick, *fast;
	BOOL inserted;   /* insertText: ran for the key being handled */
}
@end

@implementation SGADrawn
- (void)updateTrackingAreas
{
	for (NSTrackingArea *t in [[self trackingAreas] copy]) [self removeTrackingArea:t];
	[self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
		options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
		owner:self userInfo:nil]];
	[super updateTrackingAreas];
}
- (void)push:(NSEvent *)e kind:(int)a_kind button:(int)a_button
{
	NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
	sga_push(18, sga_id_of(self), (int)lround(p.x), (int)lround(p.y), a_kind + a_button * 16 + sga_modifiers([e modifierFlags]) * 256);
}
- (int)pressKind:(NSEvent *)e { return [e clickCount] == 2 ? 5 : [e clickCount] >= 3 ? 6 : 1; }
- (void)mouseDown:(NSEvent *)e { [[self window] makeFirstResponder:self]; [self push:e kind:[self pressKind:e] button:1]; }
- (void)mouseUp:(NSEvent *)e { [self push:e kind:2 button:1]; }
- (void)mouseDragged:(NSEvent *)e { [self push:e kind:3 button:1]; }
- (void)mouseMoved:(NSEvent *)e { [self push:e kind:3 button:0]; }
- (void)mouseExited:(NSEvent *)e { [self push:e kind:4 button:0]; }
- (void)rightMouseDown:(NSEvent *)e { [[self window] makeFirstResponder:self]; [self push:e kind:1 button:2]; }
- (void)rightMouseUp:(NSEvent *)e { [self push:e kind:2 button:2]; }
- (void)rightMouseDragged:(NSEvent *)e { [self push:e kind:3 button:2]; }
- (void)otherMouseDown:(NSEvent *)e { [self push:e kind:1 button:3]; }
- (void)otherMouseUp:(NSEvent *)e { [self push:e kind:2 button:3]; }
- (void)otherMouseDragged:(NSEvent *)e { [self push:e kind:3 button:3]; }
/* A trackpad gives points, a mouse wheel lines: both become SW's 120 a notch (one line, about 10 points). */
- (void)scrollWheel:(NSEvent *)e
{
	CGFloat d = [e hasPreciseScrollingDeltas] ? [e scrollingDeltaY] * 12 : [e scrollingDeltaY] * 120;
	NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
	if (lround(d) != 0) sga_push(19, sga_id_of(self), (int)lround(p.x), (int)lround(p.y), (int)lround(d));
}
- (void)keyDown:(NSEvent *)e
{
	sga_push(20, sga_id_of(self), sga_gdk_key(e), 1, sga_modifiers([e modifierFlags]) * 256);
	inserted = NO;
	/* Command keys are shortcuts, not text. */
	if (!([e modifierFlags] & NSEventModifierFlagCommand)) [self interpretKeyEvents:@[e]];
}
- (void)keyUp:(NSEvent *)e { sga_push(20, sga_id_of(self), sga_gdk_key(e), 0, sga_modifiers([e modifierFlags]) * 256); }
/* Text, as Windows' WM_CHAR gives it: each character, and the control characters Return,
   Tab, Backspace and Escape, which SW also hears as characters. */
- (void)insertText:(id)a_text replacementRange:(NSRange)r
{
	(void)r;
	NSString *s = [a_text isKindOfClass:[NSAttributedString class]] ? [a_text string] : a_text;
	inserted = YES;
	[s enumerateSubstringsInRange:NSMakeRange(0, [s length]) options:NSStringEnumerationByComposedCharacterSequences
		usingBlock:^(NSString *a_char, NSRange a, NSRange b, BOOL *a_stop) {
			(void)a; (void)b; (void)a_stop;
			UTF32Char c = 0;
			if ([a_char getBytes:&c maxLength:4 usedLength:NULL encoding:NSUTF32LittleEndianStringEncoding options:0
				range:NSMakeRange(0, [a_char length]) remainingRange:NULL]) sga_push(21, sga_id_of(self), (int)c, 0, 0);
		}];
}
- (void)doCommandBySelector:(SEL)a_selector
{
	int c = a_selector == @selector(insertNewline:) ? 13 : a_selector == @selector(insertTab:) ? 9
		: a_selector == @selector(deleteBackward:) ? 8 : a_selector == @selector(cancelOperation:) ? 27 : 0;
	if (c) sga_push(21, sga_id_of(self), c, 0, 0);
}
/* NSTextInputClient: committed text only (no marked text, as SW has it). */
- (void)setMarkedText:(id)s selectedRange:(NSRange)a replacementRange:(NSRange)b { (void)s; (void)a; (void)b; }
- (void)unmarkText {}
- (NSRange)selectedRange { return NSMakeRange(NSNotFound, 0); }
- (NSRange)markedRange { return NSMakeRange(NSNotFound, 0); }
- (BOOL)hasMarkedText { return NO; }
- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)r actualRange:(NSRangePointer)a { (void)r; (void)a; return nil; }
- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText { return @[]; }
- (NSRect)firstRectForCharacterRange:(NSRange)r actualRange:(NSRangePointer)a
{
	(void)r; (void)a;
	return [[self window] convertRectToScreen:[self convertRect:[self bounds] toView:nil]];
}
- (NSUInteger)characterIndexForPoint:(NSPoint)p { (void)p; return NSNotFound; }
- (BOOL)becomeFirstResponder { sga_push(22, sga_id_of(self), 1, 0, 0); return YES; }
- (BOOL)resignFirstResponder { sga_push(22, sga_id_of(self), 0, 0, 0); return YES; }
- (void)resetCursorRects
{
	NSCursor *c;
	switch (cursor_kind) {
		case 1: c = [NSCursor IBeamCursor]; break;
		case 2: c = [NSCursor pointingHandCursor]; break;
		case 3: c = [NSCursor resizeLeftRightCursor]; break;
		case 4: c = [NSCursor resizeUpDownCursor]; break;
		case 5: c = [NSCursor crosshairCursor]; break;
		default: c = [NSCursor arrowCursor];   /* 0, and 6 (AppKit has no public wait cursor) */
	}
	[self addCursorRect:[self visibleRect] cursor:c];
}
- (BOOL)isAccessibilityElement { return YES; }
- (NSAccessibilityRole)accessibilityRole { return NSAccessibilityGroupRole; }
- (void)ticked:(NSTimer *)t { sga_push(23, sga_id_of(self), t == fast ? 1 : 0, 0, 0); }
- (void)removeFromSuperview { [tick invalidate]; [fast invalidate]; tick = nil; fast = nil; [super removeFromSuperview]; }
@end

int sga_drawn(int a_width, int a_height)
{
	SGADrawn *d = [[SGADrawn alloc] initWithFrame:NSMakeRect(0, 0, a_width, a_height)];
	d->wanted = NSMakeSize(a_width, a_height);
	[d setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];
	[d setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationVertical];
	return sga_keep(d);
}

/* The top-left `a_width' by `a_height' device pixels of a Cairo image surface (the hosted
   frame may be larger: it grows in steps), copied, tagged sRGB, shown at the view's size. */
void sga_drawn_present(int a_id, void *a_cairo_surface, int a_width, int a_height)
{
	SGACanvas *c = sga_get(a_id);
	cairo_surface_t *s = (cairo_surface_t *)a_cairo_surface;
	if (!c || !s || cairo_surface_get_type(s) != CAIRO_SURFACE_TYPE_IMAGE) return;
	cairo_surface_flush(s);
	int w = MIN(a_width, cairo_image_surface_get_width(s)), h = MIN(a_height, cairo_image_surface_get_height(s));
	int l_stride = cairo_image_surface_get_stride(s);
	if (w <= 0 || h <= 0) return;
	CGColorSpaceRef l_srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CFDataRef l_data = CFDataCreate(NULL, cairo_image_surface_get_data(s), (CFIndex)l_stride * h);
	CGDataProviderRef l_provider = CGDataProviderCreateWithCFData(l_data);
	CGImageRef l_image = CGImageCreate((size_t)w, (size_t)h, 8, 32, (size_t)l_stride, l_srgb,
		kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, l_provider, NULL, false, kCGRenderingIntentDefault);
	CGDataProviderRelease(l_provider);
	CFRelease(l_data);
	CGColorSpaceRelease(l_srgb);
	if (c->image) CGImageRelease(c->image);
	c->image = l_image;
	[c setNeedsDisplay:YES];
}

void sga_drawn_set_cursor(int a_id, int a_kind)
{
	SGADrawn *d = sga_get(a_id);
	if (d->cursor_kind != a_kind) { d->cursor_kind = a_kind; [[d window] invalidateCursorRectsForView:d]; }
}

/* The tick every `a_tick_ms' and the fast tick every `a_fast_ms' (0: off), as events 23. */
void sga_drawn_set_ticks(int a_id, int a_tick_ms, int a_fast_ms)
{
	SGADrawn *d = sga_get(a_id);
	[d->tick invalidate]; d->tick = nil;
	[d->fast invalidate]; d->fast = nil;
	if (a_tick_ms > 0) {
		d->tick = [NSTimer timerWithTimeInterval:a_tick_ms / 1000.0 target:d selector:@selector(ticked:) userInfo:nil repeats:YES];
		[[NSRunLoop currentRunLoop] addTimer:d->tick forMode:NSRunLoopCommonModes];
	}
	if (a_fast_ms > 0) {
		d->fast = [NSTimer timerWithTimeInterval:a_fast_ms / 1000.0 target:d selector:@selector(ticked:) userInfo:nil repeats:YES];
		[[NSRunLoop currentRunLoop] addTimer:d->fast forMode:NSRunLoopCommonModes];
	}
}

/* The dwell shot: event 23 with a = 2 and b = `a_serial', once, `a_ms' from now. */
void sga_drawn_arm_dwell(int a_id, int a_ms, int a_serial)
{
	int l_id = a_id;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)a_ms * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
		sga_push(23, l_id, 2, a_serial, 0);
		sga_wake();
	});
}

/* The hosted window's accessibility tree ("role: name" lines), which describe_accessibility
   shows under the view's group. */
void sga_drawn_set_description(int a_id, const char *a_text)
{
	((SGADrawn *)sga_get(a_id))->description = sga_string(a_text);
}

/* As the view would: an event put on the queue for the drawn view `a_id'. */
void sga_test_drawn_event(int a_id, int a_type, int a, int b, int c) { sga_push(a_type, a_id, a, b, c); }

/* ------------------------------------------------------ 1m: the small basics */

/* Timers: NSTimers in the common run-loop modes (so they fire during menus and live resize).
   Each fire puts event 24 (id 0, a = the timer's id) on the queue and wakes the loop. */
@interface SGATimerTarget : NSObject
@end
@implementation SGATimerTarget
- (void)fired:(NSTimer *)t
{
	NSNumber *l_id = [t userInfo];
	sga_push(24, 0, [l_id intValue], 0, 0);
	if (![t isValid]) { }
	sga_wake();
}
@end

static NSMutableDictionary<NSNumber *, NSTimer *> *s_timers;
static SGATimerTarget *s_timer_target;

void sga_timer_start(int a_timer_id, int a_ms, int a_repeat)
{
	if (!s_timers) { s_timers = [NSMutableDictionary dictionary]; s_timer_target = [[SGATimerTarget alloc] init]; }
	[s_timers[@(a_timer_id)] invalidate];
	NSTimer *t = [NSTimer timerWithTimeInterval:MAX(a_ms, 1) / 1000.0 target:s_timer_target selector:@selector(fired:)
		userInfo:@(a_timer_id) repeats:a_repeat != 0];
	[t setTolerance:MIN(a_ms / 10000.0, 0.01)];
	[[NSRunLoop currentRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
	s_timers[@(a_timer_id)] = t;
}

void sga_timer_stop(int a_timer_id)
{
	[s_timers[@(a_timer_id)] invalidate];
	[s_timers removeObjectForKey:@(a_timer_id)];
}

/* The clipboard: the general pasteboard's plain text. */
const char *sga_clipboard_text(void)
{
	return sga_return(Kind_field, [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] ?: @"");
}

void sga_clipboard_set_text(const char *a_text)
{
	NSPasteboard *p = [NSPasteboard generalPasteboard];
	[p clearContents];
	[p setString:sga_string(a_text) forType:NSPasteboardTypeString];
}

/* Window shortcuts: a neutral spec ("primary+K") as a key and modifier mask, per window. A
   local key monitor catches them while their window is key, wherever the focus is, before
   the focused control and the menus; a match sends event 25 (id = window, a = shortcut). */
static NSString *sga_key_of(NSString *a_shortcut, NSEventModifierFlags *a_mask);
static NSMutableDictionary<NSNumber *, NSMutableArray<NSArray *> *> *s_shortcuts;   /* window id -> [key, mask, id] */
static id s_shortcut_monitor;

static const NSEventModifierFlags Sga_shortcut_mask = NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl;

static int sga_shortcut_match(int a_window, NSString *a_key, NSEventModifierFlags a_mask)
{
	for (NSArray *s in s_shortcuts[@(a_window)])
		if ([[s[0] lowercaseString] isEqualToString:[a_key lowercaseString]] && [s[1] unsignedIntegerValue] == (a_mask & Sga_shortcut_mask))
			return [s[2] intValue];
	return 0;
}

void sga_window_add_shortcut(int a_window, const char *a_shortcut, int a_shortcut_id)
{
	NSEventModifierFlags l_mask;
	NSString *l_key = sga_key_of(sga_string(a_shortcut), &l_mask);
	if (![l_key length]) return;
	if (!s_shortcuts) s_shortcuts = [NSMutableDictionary dictionary];
	if (!s_shortcuts[@(a_window)]) s_shortcuts[@(a_window)] = [NSMutableArray array];
	[s_shortcuts[@(a_window)] addObject:@[l_key, @(l_mask & Sga_shortcut_mask), @(a_shortcut_id)]];
	if (!s_shortcut_monitor)
		s_shortcut_monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) {
			int l_window = sga_id_of([e window]);
			int l_id = l_window ? sga_shortcut_match(l_window, [e charactersIgnoringModifiers] ?: @"", [e modifierFlags]) : 0;
			if (l_id) { sga_push(25, l_window, l_id, 0, 0); return nil; }
			return e;
		}];
}

/* As the user pressing `a_shortcut' in `a_window': event 25 only when it is one of its own. */
void sga_test_press_shortcut(int a_window, const char *a_shortcut)
{
	NSEventModifierFlags l_mask;
	NSString *l_key = sga_key_of(sga_string(a_shortcut), &l_mask);
	int l_id = sga_shortcut_match(a_window, l_key, l_mask);
	if (l_id) sga_push(25, a_window, l_id, 0, 0);
}

/* Full screen: AppKit animates into its own Space; this turns the loop until AppKit says the
   transition is over (at most 5 seconds), so `is_fullscreen' answers the new state on return.
   AppKit refuses full screen to an application that cannot become active (no one logged in). */
static int sga_run_once(NSDate *a_until);

int sga_window_is_fullscreen(int a_window)
{
	return ([(NSWindow *)sga_get(a_window) styleMask] & NSWindowStyleMaskFullScreen) ? 1 : 0;
}

void sga_window_set_fullscreen(int a_window, int a_on)
{
	NSWindow *w = sga_get(a_window);
	if (sga_window_is_fullscreen(a_window) == (a_on != 0)) return;
	/* Wait for AppKit's own word that the transition is over: leaving before it has finished
	   entering is refused ("not in fullscreen state"). */
	__block BOOL l_done = NO;
	NSNotificationName l_name = a_on ? NSWindowDidEnterFullScreenNotification : NSWindowDidExitFullScreenNotification;
	id l_observer = [[NSNotificationCenter defaultCenter] addObserverForName:l_name object:w queue:nil
		usingBlock:^(NSNotification *n) { (void)n; l_done = YES; }];
	id l_failed = [[NSNotificationCenter defaultCenter] addObserverForName:@"NSWindowDidFailToEnterFullScreenNotification" object:w queue:nil
		usingBlock:^(NSNotification *n) { (void)n; l_done = YES; }];
	[w toggleFullScreen:nil];
	NSDate *l_limit = [NSDate dateWithTimeIntervalSinceNow:5];
	while (!l_done && [l_limit timeIntervalSinceNow] > 0) sga_run_once([NSDate dateWithTimeIntervalSinceNow:0.05]);
	[[NSNotificationCenter defaultCenter] removeObserver:l_observer];
	[[NSNotificationCenter defaultCenter] removeObserver:l_failed];
}

/* Follow the system's light or dark again (event 10 when that changes what is shown). */
int sga_is_dark(void);
void sga_follow_system_appearance(void)
{
	int l_before = sga_is_dark();
	s_setting_dark++;
	[NSApp setAppearance:nil];
	s_setting_dark--;
	if (sga_is_dark() != l_before) sga_push(10, 0, sga_is_dark(), 0, 0);
}

/* A list's or table's row brought into view, quietly (the selection stays). */
void sga_list_scroll_to_row(int a_id, int a_row) { NSTableView *t = s_inner[a_id]; NSInteger v = sga_view_row(t, a_row - 1); if (v >= 0) [t scrollRowToVisible:v]; }
void sga_table_scroll_to_row(int a_id, int a_row) { [(NSTableView *)s_inner[a_id] scrollRowToVisible:a_row - 1]; }

/* ------------------------------------------------- 1q-a: pick and drop */

/* Picks follow spec 1q's protocol: the gesture's start sends event 30 (id = source, a = row
   or node, 0 for the widget); Eiffel answers with `sga_pick_targets' (only those widgets
   light as taking the pebble) or `sga_pick_cancel'; a drop sends 31 (id = target, a = row),
   a cancel 32. AppKit's drag session must be begun inside the mouse event with its data in
   hand, and the targets come back later through the queue, so an in-application pick is
   tracked here with a local event monitor:
   - drag (1): a press on a source and a move of 4 points picks; the release drops on the
     accepting widget under the pointer, anywhere else it cancels;
   - click (2): a right click picks; a line follows the pointer; a click drops; Escape or a
     right click cancels;
   - menu (3): a right click picks; a menu of the accepting targets' labels opens; choosing
     one drops there, dismissing it cancels. */
@interface SGAPickLine : NSView
{
@public
	NSPoint from, to;
}
@end
@implementation SGAPickLine
- (BOOL)isFlipped { return YES; }
- (NSView *)hitTest:(NSPoint)p { (void)p; return nil; }
- (void)drawRect:(NSRect)r
{
	(void)r;
	NSBezierPath *l = [NSBezierPath bezierPath];
	[l moveToPoint:from]; [l lineToPoint:to]; [l setLineWidth:2];
	CGFloat l_dash[] = {6, 4}; [l setLineDash:l_dash count:2 phase:0];
	[[NSColor controlAccentColor] setStroke]; [l stroke];
	[[NSColor controlAccentColor] setFill];
	[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(from.x - 4, from.y - 4, 8, 8)] fill];
}
@end

static NSMutableDictionary<NSNumber *, NSNumber *> *s_pick_sources;   /* id -> mode + 4 * by_row */
static NSMutableSet<NSNumber *> *s_drop_targets;
static id s_pick_monitor;
static int s_pick_state;   /* 0 idle, 1 asked (30 sent), 2 in flight */
static int s_pick_source, s_pick_mode;
static BOOL s_pick_test;   /* started by test_pick: no menu, no line */
static NSArray<NSNumber *> *s_pick_targets;
static NSArray<NSString *> *s_pick_labels;
static NSPoint s_press_point;
static int s_press_source, s_press_row;
static SGAPickLine *s_pick_line;

/* 1q-c: dragging out to other programs. A widget with drag-out data starts an AppKit
   dragging session when a press on it moves 4 points; the session carries the text and
   the files (as file URLs) and offers copy only. When the widget is also a drag-mode pick
   source, the same drag starts the pick: our own windows (the content view as destination)
   take it as the pick, everything else gets the data. The session runs AppKit's own
   tracking, so Eiffel's answer to the pick (the targets) may come only after the drop; a
   drop on one of our widgets before then is kept and done when the answer comes. The
   session's end sends 34 (a = 1 taken, 0 not) unless it ended on one of our widgets. */
static NSMutableDictionary<NSNumber *, NSArray<NSString *> *> *s_drag_out;   /* id -> @[text, paths] */
static int s_out_source;        /* the widget a dragging session left from, 0 none */
static BOOL s_out_with_pick;    /* that session also carries a pick */
static BOOL s_out_landed;       /* it ended on one of our widgets */
static int s_pending_drop;      /* a drop waiting for the pick's targets: the target, -1 a cancel, 0 none */
static int s_pending_row;

@interface SGADragOutSource : NSObject <NSDraggingSource>
@end
static SGADragOutSource *s_out_object;

static NSImage *sga_drag_image(NSView *v, NSRect r)
{
	sga_colors_flush();
	NSBitmapImageRep *l_rep = [v bitmapImageRepForCachingDisplayInRect:r];
	if (!l_rep) return nil;
	[v cacheDisplayInRect:r toBitmapImageRep:l_rep];
	NSImage *i = [[NSImage alloc] initWithSize:r.size];
	[i addRepresentation:l_rep];
	return i;
}

/* Begin the dragging session for `a_source' (row `a_row'), inside drag event `e'. */
static BOOL sga_drag_out_begin(int a_source, int a_row, NSEvent *e)
{
	NSArray<NSString *> *d = s_drag_out[@(a_source)];
	NSView *v = sga_core(a_source);
	if (!d || ![v isKindOfClass:[NSView class]]) return NO;
	NSRect r = [v bounds];
	if (a_row > 0 && [v isKindOfClass:[NSTableView class]] && ![v isKindOfClass:[SGATree class]] && a_row <= [(NSTableView *)v numberOfRows])
		r = [(NSTableView *)v rectOfRow:a_row - 1];
	r = NSIntersectionRect(r, [v visibleRect]);
	if (NSIsEmptyRect(r)) r = NSMakeRect(0, 0, 40, 20);
	NSImage *l_image = sga_drag_image(v, r);
	NSMutableArray<NSDraggingItem *> *l_items = [NSMutableArray array];
	if ([d[0] length]) [l_items addObject:[[NSDraggingItem alloc] initWithPasteboardWriter:d[0]]];
	for (NSString *l_path in [d[1] componentsSeparatedByString:@"\n"])
		if ([l_path length]) [l_items addObject:[[NSDraggingItem alloc] initWithPasteboardWriter:[NSURL fileURLWithPath:l_path]]];
	if (![l_items count]) return NO;
	for (NSUInteger k = 0; k < [l_items count]; k++) [l_items[k] setDraggingFrame:r contents:k == 0 ? l_image : nil];
	if (!s_out_object) s_out_object = [[SGADragOutSource alloc] init];
	s_out_source = a_source;
	s_out_landed = NO;
	[v beginDraggingSessionWithItems:l_items event:e source:s_out_object];
	return YES;
}

/* The registered widget at window point `p' (walking up from the view hit), and the row or
   node under it when it is a list, table or tree. */
static int sga_widget_at(NSWindow *w, NSPoint p, int *a_row)
{
	NSView *v = [[[w contentView] superview] hitTest:p];
	*a_row = 0;
	while (v) {
		int l_id = sga_id_of(v);
		if (l_id) {
			id c = sga_core(l_id);
			if ([c isKindOfClass:[NSTableView class]]) {
				NSInteger r = [(NSTableView *)c rowAtPoint:[(NSView *)c convertPoint:p fromView:nil]];
				if (r >= 0) *a_row = [c isKindOfClass:[SGATree class]] ? ((SGANode *)[(SGATree *)c itemAtRow:r])->number : (int)sga_model_row((NSTableView *)c, r) + 1;
			}
			if ([c isKindOfClass:[SGATokenField class]]) *a_row = sga_token_at((SGATokenField *)c, [(NSView *)c convertPoint:p fromView:nil]);
			return l_id;
		}
		v = [v superview];
	}
	return 0;
}

static void sga_pick_light(BOOL a_on)
{
	for (NSNumber *k in s_pick_targets) {
		NSView *v = sga_get([k intValue]);
		if (![v isKindOfClass:[NSView class]]) continue;
		[v setWantsLayer:YES];
		[[v layer] setBorderColor:[[NSColor systemGreenColor] CGColor]];
		[[v layer] setBorderWidth:a_on ? 2 : 0];
	}
}

static void sga_pick_end(void)
{
	sga_pick_light(NO);
	[s_pick_line removeFromSuperview];
	s_pick_state = 0;
	s_pick_targets = nil;
	s_pick_labels = nil;
	s_pick_test = NO;
	[[NSCursor arrowCursor] set];
}

static void sga_pick_drop_at(int a_target, int a_row)
{
	BOOL l_takes = [s_pick_targets containsObject:@(a_target)];
	sga_pick_end();
	sga_push(l_takes ? 31 : 32, l_takes ? a_target : 0, l_takes ? a_row : 0, 0, 0);
}

static void sga_pick_start(int a_source, int a_row, NSPoint a_from, NSWindow *w)
{
	NSNumber *k = s_pick_sources[@(a_source)];
	s_pick_source = a_source;
	s_pick_mode = k ? [k intValue] % 4 : 1;
	s_pick_state = 1;
	if (!s_pick_test && s_pick_mode == 2 && w) {
		if (!s_pick_line) s_pick_line = [[SGAPickLine alloc] initWithFrame:NSZeroRect];
		NSView *c = [[w contentView] superview];
		[s_pick_line setFrame:[c bounds]];
		s_pick_line->from = [c convertPoint:a_from fromView:nil];
		s_pick_line->to = s_pick_line->from;
		[c addSubview:s_pick_line positioned:NSWindowAbove relativeTo:nil];
	}
	sga_push(30, a_source, a_row, 0, 0);
}

static NSEvent *sga_pick_watch(NSEvent *e)
{
	NSWindow *w = [e window];
	if (!w) return e;
	NSPoint p = [e locationInWindow];
	int l_row = 0, l_id;
	NSEventType t = [e type];
	if (s_pick_state == 0) {
		if (t == NSEventTypeLeftMouseDown) {
			l_id = sga_widget_at(w, p, &l_row);
			NSNumber *k = s_pick_sources[@(l_id)];
			BOOL l_out = s_drag_out[@(l_id)] != nil;
			s_press_source = (k && [k intValue] % 4 == 1) || l_out ? l_id : 0;
			s_press_row = [k intValue] / 4 || (l_out && [sga_core(l_id) isKindOfClass:[NSTableView class]]) ? l_row : 0;
			s_press_point = p;
			/* A list, a tree or a control tracks the mouse itself once pressed, and its loop
			   keeps the moves from this monitor. So look ahead without taking: a release first
			   is an ordinary click (the press goes on to the view); a move past 4 points picks
			   or drags out, and the view never sees the press. */
			id l_core = s_press_source ? sga_core(s_press_source) : nil;
			if ([l_core isKindOfClass:[NSTableView class]] || [l_core isKindOfClass:[NSControl class]]) {
				for (;;) {
					NSEvent *n = [NSApp nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp
						untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:NO];
					if (!n || [n type] == NSEventTypeLeftMouseUp) break;
					[NSApp nextEventMatchingMask:NSEventMaskLeftMouseDragged untilDate:[NSDate distantPast] inMode:NSEventTrackingRunLoopMode dequeue:YES];
					NSPoint q = [n locationInWindow];
					if (hypot(q.x - p.x, q.y - p.y) > 4) return sga_pick_watch(n) ? e : nil;
				}
			}
		} else if (t == NSEventTypeLeftMouseDragged && s_press_source && hypot(p.x - s_press_point.x, p.y - s_press_point.y) > 4) {
			int l_source = s_press_source;
			NSNumber *k = s_pick_sources[@(l_source)];
			BOOL l_pick = k && [k intValue] % 4 == 1;
			s_press_source = 0;
			if (s_drag_out[@(l_source)]) {
				/* 1q-c: one AppKit drag serves both the pick (our widgets) and other programs. */
				s_out_with_pick = l_pick;
				s_pending_drop = 0;
				if (l_pick) { s_pick_test = YES; sga_pick_start(l_source, [k intValue] / 4 ? s_press_row : 0, s_press_point, w); s_pick_test = NO; }
				if (!sga_drag_out_begin(l_source, s_press_row, e) && l_pick) { sga_pick_end(); sga_push(32, 0, 0, 0, 0); }
				return nil;
			}
			sga_pick_start(l_source, s_press_row, s_press_point, w);
			return nil;
		} else if (t == NSEventTypeRightMouseDown) {
			l_id = sga_widget_at(w, p, &l_row);
			NSNumber *k = s_pick_sources[@(l_id)];
			if (k && [k intValue] % 4 >= 2) { sga_pick_start(l_id, [k intValue] / 4 ? l_row : 0, p, w); return nil; }
		}
		return e;
	}
	/* A pick is on: the pointer, the drop, the cancel. */
	if (t == NSEventTypeLeftMouseDragged || t == NSEventTypeMouseMoved) {
		if (s_pick_line && [s_pick_line superview]) { s_pick_line->to = [s_pick_line convertPoint:p fromView:nil]; [s_pick_line setNeedsDisplay:YES]; }
		l_id = sga_widget_at(w, p, &l_row);
		[([s_pick_targets containsObject:@(l_id)] ? [NSCursor dragCopyCursor] : [NSCursor operationNotAllowedCursor]) set];
		return nil;
	}
	if ((t == NSEventTypeLeftMouseUp && s_pick_mode == 1) || (t == NSEventTypeLeftMouseDown && s_pick_mode == 2)) {
		l_id = sga_widget_at(w, p, &l_row);
		sga_pick_drop_at(l_id, l_row);
		return nil;
	}
	if ((t == NSEventTypeRightMouseDown && s_pick_mode == 2) || (t == NSEventTypeKeyDown && [e keyCode] == 53)) {
		sga_pick_end();
		sga_push(32, 0, 0, 0, 0);
		return nil;
	}
	return t == NSEventTypeLeftMouseUp || t == NSEventTypeLeftMouseDown ? nil : e;
}

static void sga_pick_watch_start(void)
{
	if (!s_pick_monitor)
		s_pick_monitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskLeftMouseDragged
			| NSEventMaskLeftMouseUp | NSEventMaskRightMouseDown | NSEventMaskMouseMoved | NSEventMaskKeyDown
			handler:^NSEvent *(NSEvent *e) { return sga_pick_watch(e); }];
}

void sga_widget_set_pick(int a_id, int a_mode, int a_is_source, int a_by_row)
{
	if (!s_pick_sources) s_pick_sources = [NSMutableDictionary dictionary];
	if (a_is_source) s_pick_sources[@(a_id)] = @(a_mode + 4 * (a_by_row ? 1 : 0)); else [s_pick_sources removeObjectForKey:@(a_id)];
	sga_pick_watch_start();
}

/* 1q-b: files and text other programs drop. Each window's content view is the dragging
   destination (an ancestor of every widget); it walks up from the view under the pointer
   to the first widget that takes the kind on the pasteboard, lights it while hovering, and
   on the drop keeps the paths (newline-separated) or the text for `take_dropped_*', then
   sends 33 (a = 1 files, 2 text). An editable field takes dragged text itself, natively. */
static NSMutableSet<NSNumber *> *s_file_targets, *s_text_targets;
static NSMutableDictionary<NSNumber *, NSString *> *s_dropped_paths, *s_dropped_text;
static int s_drag_hover;

void sga_widget_set_drop_target(int a_id, int an_internal, int a_files, int a_text)
{
	if (!s_drop_targets) s_drop_targets = [NSMutableSet set];
	if (!s_file_targets) { s_file_targets = [NSMutableSet set]; s_text_targets = [NSMutableSet set]; }
	if (an_internal) [s_drop_targets addObject:@(a_id)]; else [s_drop_targets removeObject:@(a_id)];
	if (a_files) [s_file_targets addObject:@(a_id)]; else [s_file_targets removeObject:@(a_id)];
	if (a_text) [s_text_targets addObject:@(a_id)]; else [s_text_targets removeObject:@(a_id)];
	sga_pick_watch_start();
}

static NSArray<NSURL *> *sga_drag_files(NSPasteboard *pb)
{
	return [pb readObjectsForClasses:@[[NSURL class]] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}] ?: @[];
}

/* The widget that takes this drag at window point `p', and the kind it takes (1 or 2). */
static int sga_drag_target(NSWindow *w, NSPoint p, NSPasteboard *pb, int *a_kind)
{
	BOOL l_files = [sga_drag_files(pb) count] > 0;
	BOOL l_text = !l_files && [pb stringForType:NSPasteboardTypeString] != nil;
	NSView *v = [[[w contentView] superview] hitTest:p];
	*a_kind = 0;
	while (v) {
		int l_id = sga_id_of(v);
		if (l_id) {
			if (l_files && [s_file_targets containsObject:@(l_id)]) { *a_kind = 1; return l_id; }
			if (l_text && [s_text_targets containsObject:@(l_id)]) { *a_kind = 2; return l_id; }
		}
		v = [v superview];
	}
	return 0;
}

static void sga_drag_light(int a_id)
{
	if (a_id == s_drag_hover) return;
	NSView *v = s_drag_hover ? sga_get(s_drag_hover) : nil;
	if ([v isKindOfClass:[NSView class]] && ![s_pick_targets containsObject:@(s_drag_hover)]) [[v layer] setBorderWidth:0];
	s_drag_hover = a_id;
	v = a_id ? sga_get(a_id) : nil;
	if ([v isKindOfClass:[NSView class]]) {
		[v setWantsLayer:YES];
		[[v layer] setBorderColor:[[NSColor systemGreenColor] CGColor]];
		[[v layer] setBorderWidth:2];
	}
}

static void sga_drop_files(int a_id, NSString *a_joined)
{
	if (!s_dropped_paths) s_dropped_paths = [NSMutableDictionary dictionary];
	s_dropped_paths[@(a_id)] = a_joined;
	sga_push(33, a_id, 1, 0, 0);
	sga_wake();
}

static void sga_drop_text(int a_id, NSString *a_text)
{
	if (!s_dropped_text) s_dropped_text = [NSMutableDictionary dictionary];
	s_dropped_text[@(a_id)] = a_text;
	sga_push(33, a_id, 2, 0, 0);
	sga_wake();
}

/* 1q-c: our own drag carrying a pick, over our window: the pick target under the pointer
   (any internal drop target while the targets are not known yet), and its row. */
static int sga_drag_pick_target(NSWindow *w, NSPoint p, int *a_row)
{
	int l_id = sga_widget_at(w, p, a_row);
	if (s_pick_state == 2) return [s_pick_targets containsObject:@(l_id)] ? l_id : 0;
	return [s_drop_targets containsObject:@(l_id)] ? l_id : 0;
}

@implementation SGAContent (SGADropIn)
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)a_info
{
	int l_kind;
	if ([a_info draggingSource] == s_out_object && s_out_with_pick) {
		int l_row, l_target = sga_drag_pick_target([self window], [a_info draggingLocation], &l_row);
		sga_drag_light(s_pick_state == 2 ? 0 : l_target);
		return l_target ? NSDragOperationCopy : NSDragOperationNone;
	}
	int l_id = sga_drag_target([self window], [a_info draggingLocation], [a_info draggingPasteboard], &l_kind);
	sga_drag_light(l_id);
	return l_id ? NSDragOperationCopy : NSDragOperationNone;
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)a_info { return [self draggingUpdated:a_info]; }
- (void)draggingExited:(id<NSDraggingInfo>)a_info { (void)a_info; sga_drag_light(0); }
- (void)draggingEnded:(id<NSDraggingInfo>)a_info { (void)a_info; sga_drag_light(0); }
- (BOOL)performDragOperation:(id<NSDraggingInfo>)a_info
{
	int l_kind;
	NSPasteboard *pb = [a_info draggingPasteboard];
	if ([a_info draggingSource] == s_out_object && s_out_with_pick) {
		int l_row, l_target = sga_drag_pick_target([self window], [a_info draggingLocation], &l_row);
		sga_drag_light(0);
		if (!l_target) return NO;
		s_out_landed = YES;
		if (s_pick_state == 2) sga_pick_drop_at(l_target, l_row); else { s_pending_drop = l_target; s_pending_row = l_row; }
		return YES;
	}
	int l_id = sga_drag_target([self window], [a_info draggingLocation], pb, &l_kind);
	sga_drag_light(0);
	if (l_kind && [a_info draggingSource] == s_out_object) s_out_landed = YES;
	if (l_kind == 1) {
		NSMutableArray *l_paths = [NSMutableArray array];
		for (NSURL *u in sga_drag_files(pb)) [l_paths addObject:[u path]];
		sga_drop_files(l_id, [l_paths componentsJoinedByString:@"\n"]);
	}
	else if (l_kind == 2) sga_drop_text(l_id, [pb stringForType:NSPasteboardTypeString]);
	return l_kind != 0;
}
@end

const char *sga_take_dropped_paths(int a_id) { return sga_return(Kind_path, s_dropped_paths[@(a_id)] ?: @""); }
const char *sga_take_dropped_text(int a_id) { return sga_return(Kind_area, s_dropped_text[@(a_id)] ?: @""); }

/* As another program: files (newline-separated) or text dropped on `a_id'; nothing unless
   it takes that kind. */
void sga_test_drop_files(int a_id, const char *a_paths) { if ([s_file_targets containsObject:@(a_id)]) sga_drop_files(a_id, sga_string(a_paths)); }
void sga_test_drop_text(int a_id, const char *a_text) { if ([s_text_targets containsObject:@(a_id)]) sga_drop_text(a_id, sga_string(a_text)); }

@implementation SGADragOutSource
- (NSDragOperation)draggingSession:(NSDraggingSession *)a_session sourceOperationMaskForDraggingContext:(NSDraggingContext)a_context
{
	(void)a_session; (void)a_context;
	return NSDragOperationCopy;
}
- (void)draggingSession:(NSDraggingSession *)a_session endedAtPoint:(NSPoint)p operation:(NSDragOperation)an_op
{
	(void)a_session; (void)p;
	int l_source = s_out_source;
	s_out_source = 0;
	sga_drag_light(0);
	if (s_out_with_pick && !s_out_landed) {   /* the pick ended outside our widgets: cancelled */
		if (s_pick_state == 2) { sga_pick_end(); sga_push(32, 0, 0, 0, 0); }
		else if (s_pick_state == 1) s_pending_drop = -1;
	}
	s_out_with_pick = NO;
	if (!s_out_landed && l_source && s_drag_out[@(l_source)]) sga_push(34, l_source, an_op != NSDragOperationNone ? 1 : 0, 0, 0);
	sga_wake();
}
@end

void sga_widget_set_drag_out(int a_id, const char *a_text, const char *a_paths)
{
	NSString *l_text = sga_string(a_text), *l_paths = sga_string(a_paths);
	if (!s_drag_out) s_drag_out = [NSMutableDictionary dictionary];
	if ([l_text length] || [l_paths length]) s_drag_out[@(a_id)] = @[l_text, l_paths]; else [s_drag_out removeObjectForKey:@(a_id)];
	sga_pick_watch_start();
}

/* As another program: what a drag out of `a_id' carries (the text, a line feed, the paths;
   "" for nothing), and the end of one (34, only while it has data). */
const char *sga_test_drag_out(int a_id)
{
	NSArray<NSString *> *d = s_drag_out[@(a_id)];
	return sga_return(Kind_path, d ? [NSString stringWithFormat:@"%@\n%@", d[0], d[1]] : @"");
}

void sga_test_drag_out_ended(int a_id, int a_how) { if (s_drag_out[@(a_id)]) sga_push(34, a_id, a_how, 0, 0); }

@interface SGAPickMenuTarget : NSObject
@end
@implementation SGAPickMenuTarget
- (void)chosen:(NSMenuItem *)i { sga_pick_drop_at((int)[i tag], 0); }
@end

void sga_pick_targets(int a_source, const int *a_ids, int a_count, const char *a_labels)
{
	(void)a_source;
	NSMutableArray *l_ids = [NSMutableArray array];
	for (int i = 0; i < a_count; i++) [l_ids addObject:@(a_ids[i])];
	s_pick_targets = l_ids;
	s_pick_labels = a_labels && strlen(a_labels) ? [sga_string(a_labels) componentsSeparatedByString:@"\n"] : @[];
	s_pick_state = 2;
	if (s_pending_drop) {   /* 1q-c: the drag's drop came before the targets */
		int l_target = s_pending_drop;
		s_pending_drop = 0;
		if (l_target > 0) sga_pick_drop_at(l_target, s_pending_row); else { sga_pick_end(); sga_push(32, 0, 0, 0, 0); }
		return;
	}
	sga_pick_light(YES);
	if (s_pick_mode == 3 && !s_pick_test) {
		/* The target menu, at the pointer: choosing drops there; dismissing it cancels. */
		static SGAPickMenuTarget *s_menu_target;
		if (!s_menu_target) s_menu_target = [[SGAPickMenuTarget alloc] init];
		NSMenu *m = [[NSMenu alloc] init];
		for (NSUInteger k = 0; k < [l_ids count]; k++) {
			NSString *l_label = k < [s_pick_labels count] && [s_pick_labels[k] length] ? s_pick_labels[k] : [NSString stringWithFormat:@"Target %lu", (unsigned long)k + 1];
			NSMenuItem *i = [m addItemWithTitle:l_label action:@selector(chosen:) keyEquivalent:@""];
			[i setTarget:s_menu_target];
			[i setTag:[l_ids[k] integerValue]];
		}
		BOOL l_chosen = [m popUpMenuPositioningItem:nil atLocation:[NSEvent mouseLocation] inView:nil];
		if (!l_chosen && s_pick_state == 2) { sga_pick_end(); sga_push(32, 0, 0, 0, 0); }
	}
}

void sga_pick_cancel(void) { sga_pick_end(); }

/* As a user: a pick started on `a_source' (row `a_row'); a drop on `a_target'; a cancel. */
void sga_test_pick(int a_source, int a_row)
{
	s_pick_test = YES;
	sga_pick_start(a_source, a_row, NSZeroPoint, nil);
}

void sga_test_drop(int a_target, int a_row) { if (s_pick_state == 2) sga_pick_drop_at(a_target, a_row); }
void sga_test_cancel_pick(void) { if (s_pick_state) { sga_pick_end(); sga_push(32, 0, 0, 0, 0); } }
int sga_test_is_accepting(int a_target) { return s_pick_state == 2 && [s_pick_targets containsObject:@(a_target)] ? 1 : 0; }

/* ---------------------------------------------------------------- 1p: forms */

/* A password field: an NSSecureTextField, and a plain field holding the same text that the
   eye button swaps in (AppKit's secure field has no reveal of its own; it shows the caps-lock
   symbol itself). Typing sends text changed (2), Return activate (3), the eye toggled (12,
   a = 1 revealed). */
@interface SGAPassword : NSView <NSTextFieldDelegate>
{
@public
	NSSecureTextField *secure;
	NSTextField *plain;
	NSButton *eye;
	BOOL revealed;
}
@end
@implementation SGAPassword
- (NSTextField *)shown { return revealed ? plain : secure; }
- (void)reveal:(BOOL)a_on
{
	NSString *l_text = [[self shown] stringValue] ?: @"";
	BOOL l_focused = [[self window] firstResponder] == [[self shown] currentEditor];
	revealed = a_on;
	[plain setStringValue:l_text];
	[secure setStringValue:l_text];
	[plain setHidden:!a_on];
	[secure setHidden:a_on];
	[eye setImage:[NSImage imageWithSystemSymbolName:a_on ? @"eye.slash" : @"eye" accessibilityDescription:a_on ? @"Hide password" : @"Show password"]];
	if (l_focused) [[self window] makeFirstResponder:[self shown]];
}
- (void)eyed:(id)a_sender { (void)a_sender; [self reveal:!revealed]; if (!s_suppress) sga_push(12, sga_id_of(self), revealed ? 1 : 0, 0, 0); }
- (void)controlTextDidChange:(NSNotification *)n { (void)n; if (!s_suppress) sga_push(2, sga_id_of(self), 0, 0, 0); }
- (void)controlTextDidEndEditing:(NSNotification *)n { (void)n; if (!s_suppress) sga_push(29, sga_id_of(self), 0, 0, 0); }
- (void)entered:(id)a_sender { (void)a_sender; if (!s_suppress) sga_push(3, sga_id_of(self), 0, 0, 0); }
- (BOOL)isAccessibilityElement { return NO; }
@end

int sga_password_field(void)
{
	SGAPassword *p = [[SGAPassword alloc] initWithFrame:NSZeroRect];
	p->secure = [[NSSecureTextField alloc] init];
	p->plain = [NSTextField textFieldWithString:@""];
	p->eye = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"eye" accessibilityDescription:@"Show password"] target:p action:@selector(eyed:)];
	[p->eye setBordered:NO];
	for (NSTextField *f in @[p->secure, p->plain]) {
		[f setDelegate:p];
		[f setTarget:p];
		[f setAction:@selector(entered:)];
	}
	for (NSView *v in @[p->secure, p->plain, p->eye]) { [v setTranslatesAutoresizingMaskIntoConstraints:NO]; [p addSubview:v]; }
	NSMutableArray *k = [NSMutableArray array];
	for (NSTextField *f in @[p->secure, p->plain]) [k addObjectsFromArray:@[
		[f.leadingAnchor constraintEqualToAnchor:p.leadingAnchor], [f.trailingAnchor constraintEqualToAnchor:p->eye.leadingAnchor constant:-4],
		[f.topAnchor constraintEqualToAnchor:p.topAnchor], [f.bottomAnchor constraintEqualToAnchor:p.bottomAnchor]]];
	[k addObjectsFromArray:@[[p->eye.trailingAnchor constraintEqualToAnchor:p.trailingAnchor], [p->eye.centerYAnchor constraintEqualToAnchor:p.centerYAnchor],
		[p->eye.widthAnchor constraintEqualToConstant:22]]];
	[NSLayoutConstraint activateConstraints:k];
	[p reveal:NO];
	return sga_keep(p);
}

void sga_password_set_revealed(int a_id, int a_on) { [(SGAPassword *)sga_get(a_id) reveal:a_on != 0]; }
int sga_password_is_revealed(int a_id) { return ((SGAPassword *)sga_get(a_id))->revealed ? 1 : 0; }
int sga_caps_lock_on(void) { return ([NSEvent modifierFlags] & NSEventModifierFlagCapsLock) ? 1 : 0; }
void sga_test_toggle_reveal(int a_id) { [((SGAPassword *)sga_get(a_id))->eye performClick:nil]; }

/* The text field a widget id names: a field's own, a password field's shown one. */
static NSTextField *sga_text_field(int a_id)
{
	id o = sga_get(a_id);
	return [o isKindOfClass:[SGAPassword class]] ? [(SGAPassword *)o shown] : o;
}

/* Validation's look: a red border on the field and a small red note under it (placed as the
   pills are, over the content, so the layout does not move); an empty message clears both. */
static NSMutableDictionary<NSNumber *, NSTextField *> *s_error_notes;

static void sga_error_place(int a_id)
{
	NSTextField *l_note = s_error_notes[@(a_id)];
	NSView *t = sga_get(a_id);
	NSView *c = [[t window] contentView];
	if (!l_note || !c || ![t isDescendantOf:c]) return;
	if ([l_note superview] != c) {
		[l_note removeFromSuperview];
		[c addSubview:l_note positioned:NSWindowAbove relativeTo:nil];
		[NSLayoutConstraint activateConstraints:@[
			[l_note.leadingAnchor constraintEqualToAnchor:t.leadingAnchor constant:2],
			[l_note.topAnchor constraintEqualToAnchor:t.bottomAnchor constant:1]]];
	}
}

void sga_field_set_error(int a_id, const char *a_message)
{
	NSView *t = sga_get(a_id);
	NSString *m = sga_string(a_message);
	if (!s_error_notes) s_error_notes = [NSMutableDictionary dictionary];
	[t setWantsLayer:YES];
	if ([m length]) {
		[[t layer] setBorderColor:[[NSColor systemRedColor] CGColor]];
		[[t layer] setBorderWidth:1.5];
		[[t layer] setCornerRadius:4];
		NSTextField *l_note = s_error_notes[@(a_id)];
		if (!l_note) {
			l_note = [NSTextField labelWithString:@""];
			[l_note setTranslatesAutoresizingMaskIntoConstraints:NO];
			[l_note setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
			[l_note setTextColor:[NSColor systemRedColor]];
			s_error_notes[@(a_id)] = l_note;
		}
		[l_note setStringValue:m];
		[l_note setHidden:NO];
		[t setAccessibilityHelp:m];
		sga_error_place(a_id);
	} else {
		[[t layer] setBorderWidth:0];
		[s_error_notes[@(a_id)] setHidden:YES];
		[t setAccessibilityHelp:nil];
	}
}

static void sga_error_notes_sync(void)
{
	for (NSNumber *k in [s_error_notes allKeys]) sga_error_place([k intValue]);
}

const char *sga_field_error_shown(int a_id)
{
	NSTextField *l_note = s_error_notes[@(a_id)];
	return sga_return(Kind_label, l_note && ![l_note isHidden] ? [l_note stringValue] : @"");
}

/* Autocomplete: the suggestions Eiffel computed for the field's text, in a list under the
   field (a borderless child panel, never modal: AppKit's own completion runs a modal loop
   that would hold the program until the user picks). A click on a row, or Return on the
   highlighted one, fills the field (text changed); Up and Down move the highlight while the
   field keeps the focus; Escape, or leaving the field, closes the list. */
static NSMutableDictionary<NSNumber *, NSArray<NSString *> *> *s_suggestions;
static NSArray<NSString *> *sga_fields(const char *a_joined);

@interface SGASuggestions : NSObject <NSTableViewDataSource, NSTableViewDelegate>
{
@public
	NSPanel *panel;
	NSTableView *table;
	int field;   /* the widget id the list serves */
}
@end
static SGASuggestions *s_suggest;
static void sga_suggest_pick(int a_row);
@implementation SGASuggestions
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { (void)t; return (NSInteger)[s_suggestions[@(field)] count]; }
- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)r
{
	(void)c;
	NSTextField *l = [t makeViewWithIdentifier:@"sga_suggest" owner:self];
	if (!l) { l = [NSTextField labelWithString:@""]; [l setIdentifier:@"sga_suggest"]; }
	[l setStringValue:s_suggestions[@(field)][(NSUInteger)r]];
	return l;
}
- (void)clicked:(id)a_sender { (void)a_sender; if ([table clickedRow] >= 0) sga_suggest_pick((int)[table clickedRow] + 1); }
@end

static void sga_suggest_hide(void) { if (s_suggest) [[s_suggest->panel parentWindow] removeChildWindow:s_suggest->panel], [s_suggest->panel orderOut:nil]; }

static void sga_suggest_show(int a_id)
{
	NSView *f = sga_get(a_id);
	NSWindow *w = [f window];
	NSArray *l_list = s_suggestions[@(a_id)];
	if (!w || ![w isVisible] || ![l_list count]) { if (s_suggest && s_suggest->field == a_id) sga_suggest_hide(); return; }
	if (!s_suggest) {
		s_suggest = [[SGASuggestions alloc] init];
		s_suggest->panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 200, 100) styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:YES];
		[s_suggest->panel setHasShadow:YES];
		[s_suggest->panel setBecomesKeyOnlyIfNeeded:YES];
		NSScrollView *l_scroll = [[NSScrollView alloc] init];
		s_suggest->table = [[NSTableView alloc] init];
		[s_suggest->table addTableColumn:[[NSTableColumn alloc] initWithIdentifier:@"s"]];
		[s_suggest->table setHeaderView:nil];
		[s_suggest->table setDataSource:s_suggest];
		[s_suggest->table setDelegate:s_suggest];
		[s_suggest->table setTarget:s_suggest];
		[s_suggest->table setAction:@selector(clicked:)];
		[s_suggest->table setRefusesFirstResponder:YES];
		[l_scroll setDocumentView:s_suggest->table];
		[l_scroll setHasVerticalScroller:YES];
		[s_suggest->panel setContentView:l_scroll];
	}
	s_suggest->field = a_id;
	[s_suggest->table reloadData];
	NSRect r = [w convertRectToScreen:[f convertRect:[f bounds] toView:nil]];
	CGFloat h = MIN([l_list count], 8) * ([s_suggest->table rowHeight] + [s_suggest->table intercellSpacing].height) + 4;
	[s_suggest->panel setFrame:NSMakeRect(NSMinX(r), NSMinY(r) - h - 2, MAX(NSWidth(r), 160), h) display:YES];
	if ([s_suggest->panel parentWindow] != w) { sga_suggest_hide(); [w addChildWindow:s_suggest->panel ordered:NSWindowAbove]; }
	[s_suggest->panel orderFront:nil];
}

static void sga_suggest_pick(int a_row)
{
	if (!s_suggest) return;
	int l_id = s_suggest->field;
	NSArray<NSString *> *l_list = s_suggestions[@(l_id)];
	if (a_row < 1 || a_row > (int)[l_list count]) return;
	NSTextField *f = sga_text_field(l_id);
	s_suppress++;
	[f setStringValue:l_list[(NSUInteger)(a_row - 1)]];
	s_suppress--;
	sga_suggest_hide();
	sga_push(2, l_id, 0, 0, 0);
}

/* The field's keys, while its list shows (SGATarget's doCommandBySelector asks): YES when handled. */
static BOOL sga_suggest_key(int a_id, SEL a_command)
{
	if (!s_suggest || s_suggest->field != a_id || ![s_suggest->panel isVisible]) return NO;
	NSTableView *t = s_suggest->table;
	NSInteger n = [t numberOfRows], r = [t selectedRow];
	if (a_command == @selector(moveDown:)) { [t selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)MIN(r + 1, n - 1)] byExtendingSelection:NO]; [t scrollRowToVisible:[t selectedRow]]; return YES; }
	if (a_command == @selector(moveUp:)) { [t selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)MAX(r - 1, 0)] byExtendingSelection:NO]; [t scrollRowToVisible:[t selectedRow]]; return YES; }
	if (a_command == @selector(insertNewline:) && r >= 0) { sga_suggest_pick((int)r + 1); return YES; }
	/* 1p-b: Tab, or Right with the caret at the end, completes to the highlighted suggestion */
	if (r >= 0 && (a_command == @selector(insertTab:) || a_command == @selector(moveRight:))) {
		NSTextField *f = sga_get(a_id);
		NSText *l_editor = [f currentEditor];
		if (a_command == @selector(insertTab:) || (l_editor && [l_editor selectedRange].location == [[f stringValue] length] && [l_editor selectedRange].length == 0)) {
			sga_suggest_pick((int)r + 1);
			return YES;
		}
	}
	if (a_command == @selector(cancelOperation:)) { sga_suggest_hide(); return YES; }
	return NO;
}

void sga_field_set_suggestions(int a_id, const char *a_joined)
{
	if (!s_suggestions) s_suggestions = [NSMutableDictionary dictionary];
	s_suggestions[@(a_id)] = strlen(a_joined) ? sga_fields(a_joined) : @[];
	sga_suggest_show(a_id);
}

int sga_field_suggestion_count(int a_id) { return (int)[s_suggestions[@(a_id)] count]; }

/* Leaving field `a_id' closes its suggestion list. */
static void sga_suggest_end(int a_id) { if (s_suggest && s_suggest->field == a_id) sga_suggest_hide(); }

/* As a user: suggestion `i' chosen, filling the field (text changed). */
void sga_test_pick_suggestion(int a_id, int i)
{
	if (!s_suggest || s_suggest->field != a_id) sga_suggest_show(a_id);
	if (s_suggest && s_suggest->field == a_id) sga_suggest_pick(i);
	else {
		NSArray<NSString *> *l_list = s_suggestions[@(a_id)];
		if (i < 1 || i > (int)[l_list count]) return;
		[sga_text_field(a_id) setStringValue:l_list[(NSUInteger)(i - 1)]];
		sga_push(2, a_id, 0, 0, 0);
	}
}

/* Date and time together, and a month (1p): a date picker of another kind. */
int sga_date_picker(void);
static NSDate *sga_date_of(SGADatePicker *p, int a_value);

int sga_date_time_picker(int a_kind)
{
	int l_id = sga_date_picker();
	SGADatePicker *p = sga_get(l_id);
	p->kind = a_kind == 3 ? 3 : 2;
	[p setDatePickerElements:p->kind == 3 ? NSDatePickerElementFlagYearMonth
		: NSDatePickerElementFlagYearMonthDay | NSDatePickerElementFlagHourMinute];
	p->last = -1;
	return l_id;
}

/* `a_date' = year * 10000 + month * 100 + day, `a_time' = hour * 60 + minute; silent. */
void sga_date_time_set(int a_id, int a_date, int a_time)
{
	SGADatePicker *p = sga_get(a_id);
	NSCalendar *c = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
	NSDateComponents *k = [[NSDateComponents alloc] init];
	[k setYear:a_date / 10000]; [k setMonth:a_date / 100 % 100]; [k setDay:MAX(a_date % 100, 1)];
	[k setHour:a_time / 60]; [k setMinute:a_time % 60];
	[p setDateValue:[c dateFromComponents:k]];
	p->last = p->kind == 3 ? a_date / 100 : (long)a_date * 10000 + a_time;
}

int sga_date_time_date(int a_id)
{
	NSCalendar *c = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
	NSDateComponents *k = [c components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:[(NSDatePicker *)sga_get(a_id) dateValue]];
	return (int)([k year] * 10000 + [k month] * 100 + [k day]);
}

int sga_date_time_time(int a_id)
{
	NSCalendar *c = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian];
	NSDateComponents *k = [c components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:[(NSDatePicker *)sga_get(a_id) dateValue]];
	return (int)([k hour] * 60 + [k minute]);
}

/* As a user: the date and time entered, then the action. */
void sga_test_set_date_time(int a_id, int a_date, int a_time)
{
	SGADatePicker *p = sga_get(a_id);
	NSInteger l_last = p->last;
	sga_date_time_set(a_id, a_date, a_time);
	p->last = l_last;
	[p sendAction:[p action] to:[p target]];
}

/* A range slider: two knobs on one track, hand-built (AppKit has no two-thumb slider). A
   press takes the nearer knob; dragging or the arrow keys move it, never past the other.
   A change sends text changed (2, a = low, b = high). For assistive tools: two sliders,
   "Minimum" and "Maximum". */
@interface SGARangeSlider : NSView
{
@public
	NSInteger minimum, maximum, low, high, step;
	int dragging;   /* 0 none, 1 low, 2 high */
	int focused;    /* the knob the keys move */
	NSArray *elements;
}
@end
@implementation SGARangeSlider
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, 24); }
- (CGFloat)xOf:(NSInteger)v
{
	CGFloat l_inset = 10, w = NSWidth([self bounds]) - 2 * l_inset;
	return l_inset + (maximum > minimum ? (CGFloat)(v - minimum) / (CGFloat)(maximum - minimum) : 0) * w;
}
- (NSInteger)valueAt:(CGFloat)x
{
	CGFloat l_inset = 10, w = MAX(NSWidth([self bounds]) - 2 * l_inset, 1);
	NSInteger v = minimum + (NSInteger)lround((x - l_inset) / w * (CGFloat)(maximum - minimum));
	if (step > 1) v = minimum + ((v - minimum + step / 2) / step) * step;
	return MAX(minimum, MIN(maximum, v));
}
- (void)drawRect:(NSRect)r
{
	(void)r;
	CGFloat y = NSMidY([self bounds]);
	NSBezierPath *l_track = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(10, y - 2, NSWidth([self bounds]) - 20, 4) xRadius:2 yRadius:2];
	[[NSColor tertiaryLabelColor] setFill]; [l_track fill];
	NSBezierPath *l_range = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect([self xOf:low], y - 2, [self xOf:high] - [self xOf:low], 4) xRadius:2 yRadius:2];
	[[NSColor controlAccentColor] setFill]; [l_range fill];
	for (int k = 1; k <= 2; k++) {
		CGFloat x = [self xOf:k == 1 ? low : high];
		NSShadow *s = [[NSShadow alloc] init]; [s setShadowBlurRadius:2]; [s setShadowOffset:NSMakeSize(0, -1)]; [s setShadowColor:[NSColor colorWithWhite:0 alpha:0.3]];
		[NSGraphicsContext saveGraphicsState]; [s set];
		[[NSColor whiteColor] setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - 9, y - 9, 18, 18)] fill];
		[NSGraphicsContext restoreGraphicsState];
		if ([[self window] firstResponder] == self && focused == k) {
			[[NSColor keyboardFocusIndicatorColor] setStroke];
			NSBezierPath *l_ring = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - 10, y - 10, 20, 20)]; [l_ring setLineWidth:2]; [l_ring stroke];
		}
	}
}
- (void)moveKnob:(int)k to:(NSInteger)v
{
	NSInteger l_low = low, l_high = high;
	if (k == 1) low = MIN(v, high); else high = MAX(v, low);
	if (low != l_low || high != l_high) {
		[self setNeedsDisplay:YES];
		if (!s_suppress) sga_push(2, sga_id_of(self), (int)low, (int)high, 0);
	}
}
- (void)mouseDown:(NSEvent *)e
{
	NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
	[[self window] makeFirstResponder:self];
	dragging = fabs(p.x - [self xOf:low]) <= fabs(p.x - [self xOf:high]) ? 1 : 2;
	if (low == high) dragging = p.x < [self xOf:low] ? 1 : 2;
	focused = dragging;
	[self moveKnob:dragging to:[self valueAt:p.x]];
}
- (void)mouseDragged:(NSEvent *)e { if (dragging) [self moveKnob:dragging to:[self valueAt:[self convertPoint:[e locationInWindow] fromView:nil].x]]; }
- (void)mouseUp:(NSEvent *)e { (void)e; dragging = 0; }
- (void)keyDown:(NSEvent *)e
{
	unichar c = [[e charactersIgnoringModifiers] length] ? [[e charactersIgnoringModifiers] characterAtIndex:0] : 0;
	NSInteger d = c == NSRightArrowFunctionKey || c == NSUpArrowFunctionKey ? MAX(step, 1) : c == NSLeftArrowFunctionKey || c == NSDownArrowFunctionKey ? -MAX(step, 1) : 0;
	if (c == '\t') { [super keyDown:e]; return; }
	if (d) [self moveKnob:focused to:(focused == 1 ? low : high) + d];
	else [super keyDown:e];
}
- (BOOL)isAccessibilityElement { return NO; }
- (NSArray *)accessibilityChildren
{
	NSMutableArray *a = [NSMutableArray array];
	for (int k = 1; k <= 2; k++) {
		NSAccessibilityElement *x = [NSAccessibilityElement accessibilityElementWithRole:NSAccessibilitySliderRole
			frame:NSZeroRect label:k == 1 ? @"Minimum" : @"Maximum" parent:self];
		[x setAccessibilityValue:@(k == 1 ? low : high)];
		[a addObject:x];
	}
	elements = a;
	return a;
}
@end

int sga_range_slider(int a_min, int a_max)
{
	SGARangeSlider *r = [[SGARangeSlider alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
	r->minimum = a_min; r->maximum = a_max; r->low = a_min; r->high = a_max; r->step = 1; r->focused = 1;
	[r setTranslatesAutoresizingMaskIntoConstraints:NO];
	[[r.widthAnchor constraintGreaterThanOrEqualToConstant:120] setActive:YES];
	return sga_keep(r);
}

void sga_range_slider_set(int a_id, int a_low, int a_high) { SGARangeSlider *r = sga_get(a_id); r->low = a_low; r->high = a_high; [r setNeedsDisplay:YES]; }
int sga_range_slider_low(int a_id) { return (int)((SGARangeSlider *)sga_get(a_id))->low; }
int sga_range_slider_high(int a_id) { return (int)((SGARangeSlider *)sga_get(a_id))->high; }
void sga_range_slider_set_step(int a_id, int a_step) { ((SGARangeSlider *)sga_get(a_id))->step = a_step; }

/* As a user: each knob dragged where asked (the low one first). */
void sga_test_slide_range(int a_id, int a_low, int a_high)
{
	SGARangeSlider *r = sga_get(a_id);
	if (a_low > r->high) { [r moveKnob:2 to:a_high]; [r moveKnob:1 to:a_low]; }
	else { [r moveKnob:1 to:a_low]; [r moveKnob:2 to:a_high]; }
}

/* A list's multiple selection (1p): AppKit's own; the user adds rows with Command and Shift. */
void sga_list_set_multiple(int a_id, int a_on) { [(NSTableView *)s_inner[a_id] setAllowsMultipleSelection:a_on != 0]; }
int sga_list_selected_count(int a_id) { return (int)[[(NSTableView *)s_inner[a_id] selectedRowIndexes] count]; }
int sga_list_selected_at(int a_id, int i)
{
	NSIndexSet *s = [(NSTableView *)s_inner[a_id] selectedRowIndexes];
	__block int l_row = 0, k = 0;
	NSTableView *t = s_inner[a_id];
	[s enumerateIndexesUsingBlock:^(NSUInteger r, BOOL *a_stop) { if (++k == i) { l_row = (int)sga_model_row(t, (NSInteger)r) + 1; *a_stop = YES; } }];
	return l_row;
}

/* As a user: row `a_row' added to the selection (Command-click). */
void sga_test_extend_list_selection(int a_id, int a_row)
{
	if ([s_inner[a_id] isKindOfClass:NSClassFromString(@"SGAGridView")]) { sga_grid_user_select(a_id, a_row, YES); return; }   /* 1v-a */
	NSTableView *t = s_inner[a_id];
	NSInteger v = sga_view_row(t, a_row - 1);
	if (v >= 0) [t selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)v] byExtendingSelection:YES];
}

/* ---------------------------------------------- 1o: feedback and messages */

/* A spinner: AppKit's spinning progress indicator, hidden while it does not turn. */
int sga_spinner(void)
{
	NSProgressIndicator *p = [[NSProgressIndicator alloc] init];
	[p setStyle:NSProgressIndicatorStyleSpinning];
	[p setControlSize:NSControlSizeSmall];
	[p setDisplayedWhenStopped:NO];
	return sga_keep(p);
}

void sga_spinner_set(int a_id, int a_on)
{
	NSProgressIndicator *p = sga_get(a_id);
	if (a_on) [p startAnimation:nil]; else [p stopAnimation:nil];
}

/* An info bar: a tinted rounded box with the kind's symbol, the message, the program's
   action buttons and, when closable, a close button. An action sends event 26 (a = its
   number), the close button 26 with a = 0 (the shared class hides the bar). */
@interface SGAInfoBar : NSBox
{
@public
	NSImageView *icon;
	NSTextField *message;
	NSStackView *row;
	NSButton *close;
}
@end
@implementation SGAInfoBar
- (void)pressed:(NSButton *)b { if (!s_suppress) sga_push(26, sga_id_of(self), (int)[b tag], 0, 0); }
@end

static void sga_info_bar_kind(SGAInfoBar *b, int a_kind)
{
	NSColor *c = a_kind == 2 ? [NSColor systemGreenColor] : a_kind == 3 ? [NSColor systemOrangeColor] : a_kind == 4 ? [NSColor systemRedColor] : [NSColor systemBlueColor];
	NSString *s = a_kind == 2 ? @"checkmark.circle.fill" : a_kind == 3 ? @"exclamationmark.triangle.fill" : a_kind == 4 ? @"xmark.octagon.fill" : @"info.circle.fill";
	[b setFillColor:[c colorWithAlphaComponent:0.15]];
	[b setBorderColor:[c colorWithAlphaComponent:0.5]];
	[b->icon setImage:[NSImage imageWithSystemSymbolName:s accessibilityDescription:nil]];
	[b->icon setContentTintColor:c];
}

int sga_info_bar(int a_kind, const char *a_message)
{
	SGAInfoBar *b = [[SGAInfoBar alloc] init];
	[b setBoxType:NSBoxCustom];
	[b setCornerRadius:6];
	[b setBorderWidth:1];
	[b setTitlePosition:NSNoTitle];
	[b setContentViewMargins:NSMakeSize(8, 6)];
	b->icon = [[NSImageView alloc] init];
	/* One line that truncates (a wrapping label with no width to wrap at pulls the window in). */
	b->message = [NSTextField labelWithString:sga_string(a_message)];
	[b->message setLineBreakMode:NSLineBreakByTruncatingTail];
	[b->message setToolTip:sga_string(a_message)];
	[b->message setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 2 forOrientation:NSLayoutConstraintOrientationHorizontal];
	[b->message setContentHuggingPriority:NSLayoutPriorityDefaultLow - 2 forOrientation:NSLayoutConstraintOrientationHorizontal];
	b->close = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"Close"] target:b action:@selector(pressed:)];
	[b->close setBordered:NO];
	[b->close setTag:0];
	[b->close setHidden:YES];
	b->row = [NSStackView stackViewWithViews:@[b->icon, b->message, b->close]];
	[b->row setSpacing:8];
	[b->row setTranslatesAutoresizingMaskIntoConstraints:NO];
	/* The bar takes the width it is given: a stack view hugs its content above the window's
	   own size, and would pull the window in to the bar's natural width. */
	[b->row setHuggingPriority:NSLayoutPriorityDefaultLow - 2 forOrientation:NSLayoutConstraintOrientationHorizontal];
	[b setContentHuggingPriority:NSLayoutPriorityDefaultLow - 2 forOrientation:NSLayoutConstraintOrientationHorizontal];
	NSView *c = [b contentView];
	[c addSubview:b->row];
	[NSLayoutConstraint activateConstraints:@[[b->row.leadingAnchor constraintEqualToAnchor:c.leadingAnchor], [b->row.trailingAnchor constraintEqualToAnchor:c.trailingAnchor],
		[b->row.topAnchor constraintEqualToAnchor:c.topAnchor], [b->row.bottomAnchor constraintEqualToAnchor:c.bottomAnchor]]];
	sga_info_bar_kind(b, a_kind);
	[b setAccessibilityRole:NSAccessibilityGroupRole];
	return sga_keep(b);
}

void sga_info_bar_set(int a_id, int a_kind, const char *a_message)
{
	SGAInfoBar *b = sga_get(a_id);
	[b->message setStringValue:sga_string(a_message)];
	[b->message setToolTip:sga_string(a_message)];
	sga_info_bar_kind(b, a_kind);
}

void sga_info_bar_add_action(int a_id, const char *a_text, int a_number)
{
	SGAInfoBar *b = sga_get(a_id);
	NSButton *x = [NSButton buttonWithTitle:sga_string(a_text) target:b action:@selector(pressed:)];
	[x setTag:a_number];
	[x setControlSize:NSControlSizeSmall];
	[b->row insertArrangedSubview:x atIndex:[[b->row arrangedSubviews] count] - 1];
}

void sga_info_bar_set_closable(int a_id, int a_on) { [((SGAInfoBar *)sga_get(a_id))->close setHidden:a_on == 0]; }

/* As a user: action `a_number' (0: close) pressed. */
void sga_test_info_bar_press(int a_id, int a_number)
{
	SGAInfoBar *b = sga_get(a_id);
	for (NSView *v in [b->row arrangedSubviews]) if ([v isKindOfClass:[NSButton class]] && [(NSButton *)v tag] == a_number && ![v isHidden]) { [(NSButton *)v performClick:nil]; return; }
}

/* A toast: a dark rounded bubble at the bottom of the window's content, over everything,
   with the message and an optional action; it closes by itself after 4 seconds, or when
   its action is pressed (event 27, id = window, a = the toast's id). One per window. */
@interface SGAToast : NSView
{
@public
	NSTextField *message;
	NSButton *action;
	int window_id, toast_id;
	NSInteger serial;
}
@end
@implementation SGAToast
- (void)pressed:(id)a_sender
{
	(void)a_sender;
	if ([self isHidden]) return;
	[self setHidden:YES];
	if (toast_id > 0) sga_push(27, window_id, toast_id, 0, 0);
}
@end

static NSMutableDictionary<NSNumber *, SGAToast *> *s_toasts;

void sga_window_show_toast(int a_window, const char *a_message, const char *an_action_text, int a_toast_id)
{
	NSWindow *w = sga_get(a_window);
	NSView *c = [w contentView];
	if (!s_toasts) s_toasts = [NSMutableDictionary dictionary];
	SGAToast *t = s_toasts[@(a_window)];
	if (!t) {
		t = [[SGAToast alloc] init];
		[t setWantsLayer:YES];
		[[t layer] setCornerRadius:10];
		[[t layer] setBackgroundColor:[[NSColor colorWithWhite:0.15 alpha:0.94] CGColor]];
		[t setTranslatesAutoresizingMaskIntoConstraints:NO];
		t->message = [NSTextField labelWithString:@""];
		[t->message setTextColor:[NSColor whiteColor]];
		t->action = [NSButton buttonWithTitle:@"" target:t action:@selector(pressed:)];
		[t->action setBordered:NO];
		[t->action setContentTintColor:[NSColor systemYellowColor]];
		NSStackView *l_row = [NSStackView stackViewWithViews:@[t->message, t->action]];
		[l_row setSpacing:16];
		[l_row setTranslatesAutoresizingMaskIntoConstraints:NO];
		[t addSubview:l_row];
		[NSLayoutConstraint activateConstraints:@[[l_row.leadingAnchor constraintEqualToAnchor:t.leadingAnchor constant:14], [l_row.trailingAnchor constraintEqualToAnchor:t.trailingAnchor constant:-14],
			[l_row.topAnchor constraintEqualToAnchor:t.topAnchor constant:8], [l_row.bottomAnchor constraintEqualToAnchor:t.bottomAnchor constant:-8]]];
		t->window_id = a_window;
		s_toasts[@(a_window)] = t;
	}
	if ([t superview] != c) {
		[t removeFromSuperview];
		[c addSubview:t positioned:NSWindowAbove relativeTo:nil];
		[NSLayoutConstraint activateConstraints:@[[t.centerXAnchor constraintEqualToAnchor:c.centerXAnchor],
			[t.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-16], [t.widthAnchor constraintLessThanOrEqualToAnchor:c.widthAnchor constant:-32]]];
	}
	[t->message setStringValue:sga_string(a_message)];
	[t->action setTitle:sga_string(an_action_text)];
	[t->action setHidden:strlen(an_action_text) == 0];
	t->toast_id = a_toast_id;
	[t setHidden:NO];
	[c layoutSubtreeIfNeeded];
	NSInteger l_serial = ++t->serial;
	SGAToast *l_toast = t;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		if (l_toast->serial == l_serial) [l_toast setHidden:YES];
	});
}

const char *sga_test_toast_shown(int a_window)
{
	SGAToast *t = s_toasts[@(a_window)];
	return sga_return(Kind_label, t && ![t isHidden] && [t superview] ? [t->message stringValue] : @"");
}

void sga_test_toast_press(int a_window)
{
	SGAToast *t = s_toasts[@(a_window)];
	if (t && ![t isHidden] && ![t->action isHidden]) [t->action performClick:nil];
}

/* A desktop notification through UNUserNotificationCenter; a click sends event 28 (a = its
   id). AppKit allows it only to a bundled application (with a bundle identifier): a program
   run straight from its executable, as the test runner is, posts nothing. */
@interface SGANotifier : NSObject <UNUserNotificationCenterDelegate>
@end
@implementation SGANotifier
- (void)userNotificationCenter:(UNUserNotificationCenter *)c didReceiveNotificationResponse:(UNNotificationResponse *)r withCompletionHandler:(void (^)(void))done
{
	(void)c;
	NSNumber *l_id = [[[[r notification] request] content] userInfo][@"sga_id"];
	if ([l_id intValue] > 0) { sga_push(28, 0, [l_id intValue], 0, 0); sga_wake(); }
	done();
}
- (void)userNotificationCenter:(UNUserNotificationCenter *)c willPresentNotification:(UNNotification *)n withCompletionHandler:(void (^)(UNNotificationPresentationOptions))done
{
	(void)c; (void)n;
	done(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionList);
}
@end
static SGANotifier *s_notifier;

void sga_notify(const char *a_title, const char *a_body, int a_notification_id)
{
	if (![[NSBundle mainBundle] bundleIdentifier]) return;
	UNUserNotificationCenter *c = [UNUserNotificationCenter currentNotificationCenter];
	if (!s_notifier) {
		s_notifier = [[SGANotifier alloc] init];
		[c setDelegate:s_notifier];
		[c requestAuthorizationWithOptions:UNAuthorizationOptionAlert | UNAuthorizationOptionSound completionHandler:^(BOOL g, NSError *e) { (void)g; (void)e; }];
	}
	UNMutableNotificationContent *k = [[UNMutableNotificationContent alloc] init];
	[k setTitle:sga_string(a_title)];
	[k setBody:sga_string(a_body)];
	[k setUserInfo:@{@"sga_id": @(a_notification_id)}];
	[c addNotificationRequest:[UNNotificationRequest requestWithIdentifier:[[NSUUID UUID] UUIDString] content:k trigger:nil] withCompletionHandler:nil];
}

/* ------------------------------------------- 1n: icons, styles, badges, busy */

/* GUI_ICON's neutral names as SF Symbols. */
static NSString *sga_symbol_of(NSString *a_name)
{
	static NSDictionary<NSString *, NSString *> *l_map;
	if (!l_map) l_map = @{
		@"add": @"plus", @"remove": @"minus", @"close": @"xmark", @"check": @"checkmark",
		@"chevron-right": @"chevron.right", @"chevron-left": @"chevron.left", @"chevron-up": @"chevron.up", @"chevron-down": @"chevron.down",
		@"back": @"chevron.backward", @"forward": @"chevron.forward", @"search": @"magnifyingglass", @"settings": @"gearshape",
		@"delete": @"trash", @"edit": @"pencil", @"folder": @"folder", @"document": @"doc", @"open": @"folder.badge.plus",
		@"save": @"square.and.arrow.down", @"copy": @"doc.on.doc", @"cut": @"scissors", @"paste": @"doc.on.clipboard",
		@"undo": @"arrow.uturn.backward", @"redo": @"arrow.uturn.forward", @"refresh": @"arrow.clockwise",
		@"play": @"play.fill", @"pause": @"pause.fill", @"stop": @"stop.fill", @"more": @"ellipsis", @"menu": @"line.3.horizontal",
		@"info": @"info.circle", @"warning": @"exclamationmark.triangle", @"error": @"xmark.octagon", @"help": @"questionmark.circle",
		@"star": @"star", @"picture": @"photo", @"home": @"house", @"user": @"person", @"mail": @"envelope",
		@"calendar": @"calendar", @"clock": @"clock", @"lock": @"lock", @"bell": @"bell",
		@"download": @"arrow.down.circle", @"upload": @"arrow.up.circle", @"print": @"printer",
		@"filter": @"line.3.horizontal.decrease", @"sort": @"arrow.up.arrow.down"};
	return l_map[a_name];
}

static NSImage *sga_icon_image(NSString *a_name)
{
	NSString *l_symbol = sga_symbol_of(a_name);
	return l_symbol ? [NSImage imageWithSystemSymbolName:l_symbol accessibilityDescription:a_name] : nil;
}

static NSMutableDictionary<NSNumber *, NSString *> *s_button_icons;   /* button id -> icon name (kept while busy) */
static NSMutableDictionary<NSNumber *, NSProgressIndicator *> *s_busy;

static void sga_button_show_icon(int a_id)
{
	NSButton *b = sga_core(a_id);
	NSString *l_name = s_button_icons[@(a_id)];
	NSImage *i = [l_name length] && !s_busy[@(a_id)] ? sga_icon_image(l_name) : nil;
	[b setImage:i];
	[b setImagePosition:i ? ([[b title] length] ? NSImageLeading : NSImageOnly) : NSNoImage];
}

void sga_button_set_icon(int a_id, const char *a_name)
{
	if (!s_button_icons) s_button_icons = [NSMutableDictionary dictionary];
	s_button_icons[@(a_id)] = sga_string(a_name);
	sga_button_show_icon(a_id);
}

/* 0 normal, 1 suggested (the accent's tint), 2 destructive (red, and AppKit's destructive
   flag), 3 flat (no border), 4 pill (the capsule inline bezel). */
void sga_button_set_style(int a_id, int a_style)
{
	NSButton *b = sga_core(a_id);
	[b setBordered:a_style != 3];
	[b setBezelStyle:a_style == 4 ? NSBezelStyleInline : NSBezelStylePush];
	[b setBezelColor:a_style == 1 ? [NSColor controlAccentColor] : a_style == 2 ? [NSColor systemRedColor] : nil];
	[b setHasDestructiveAction:a_style == 2];
	[b invalidateIntrinsicContentSize];
}

/* Busy: a small spinner where the icon was (the shared class disables the button). */
void sga_button_set_busy(int a_id, int a_on)
{
	NSButton *b = sga_core(a_id);
	if (!s_busy) s_busy = [NSMutableDictionary dictionary];
	NSProgressIndicator *s = s_busy[@(a_id)];
	if (a_on && !s) {
		s = [[NSProgressIndicator alloc] init];
		[s setStyle:NSProgressIndicatorStyleSpinning];
		[s setControlSize:NSControlSizeSmall];
		[s setTranslatesAutoresizingMaskIntoConstraints:NO];
		[b addSubview:s];
		[NSLayoutConstraint activateConstraints:@[[s.leadingAnchor constraintEqualToAnchor:b.leadingAnchor constant:8],
			[s.centerYAnchor constraintEqualToAnchor:b.centerYAnchor], [s.widthAnchor constraintEqualToConstant:14], [s.heightAnchor constraintEqualToConstant:14]]];
		[s startAnimation:nil];
		s_busy[@(a_id)] = s;
	} else if (!a_on && s) {
		[s stopAnimation:nil];
		[s removeFromSuperview];
		[s_busy removeObjectForKey:@(a_id)];
	}
	sga_button_show_icon(a_id);
	if (a_on && [[b title] length] && ![b image]) {
		/* room for the spinner before the title */
		[b setImage:[[NSImage alloc] initWithSize:NSMakeSize(16, 14)]];
		[b setImagePosition:NSImageLeading];
	}
}

const char *sga_test_button_icon(int a_id) { return sga_return(Kind_label, s_busy[@(a_id)] ? @"" : (s_button_icons[@(a_id)] ?: @"")); }

static NSMenuItem *sga_find_numbered_anywhere(int a_id);
void sga_menu_set_item_icon(int a_item_id, const char *a_name)
{
	NSMenuItem *i = sga_find_numbered_anywhere(a_item_id);
	[i setImage:[sga_string(a_name) length] ? sga_icon_image(sga_string(a_name)) : nil];
}

/* Tabs: AppKit's tab view draws no item images and has no badges: a badge is added to the
   tab's label, "News (5)". */
static NSInteger sga_tab_item(NSTabView *t, int a_page);
static NSMutableDictionary<NSValue *, NSString *> *s_tab_titles;   /* item -> its own label */

/* AppKit's tab view draws no tab images, and an item given one loses its label: the icon is
   recorded only (the tab keeps its text). */
static NSMutableDictionary<NSValue *, NSString *> *s_tab_icons;

void sga_tabs_set_page_icon(int a_tabs, int a_page, const char *a_name)
{
	NSTabView *t = sga_get(a_tabs);
	if (!s_tab_icons) s_tab_icons = [NSMutableDictionary dictionary];
	s_tab_icons[[NSValue valueWithNonretainedObject:[t tabViewItemAtIndex:sga_tab_item(t, a_page)]]] = sga_string(a_name);
}

void sga_tabs_set_page_badge(int a_tabs, int a_page, const char *a_text)
{
	NSTabView *t = sga_get(a_tabs);
	NSTabViewItem *i = [t tabViewItemAtIndex:sga_tab_item(t, a_page)];
	NSValue *k = [NSValue valueWithNonretainedObject:i];
	if (!s_tab_titles) s_tab_titles = [NSMutableDictionary dictionary];
	if (!s_tab_titles[k]) s_tab_titles[k] = [i label];
	NSString *l_text = sga_string(a_text);
	[i setLabel:[l_text length] ? [NSString stringWithFormat:@"%@ (%@)", s_tab_titles[k], l_text] : s_tab_titles[k]];
}

/* A badge: a small red bubble (the text) or dot at the widget's trailing top corner, over the
   window's content, always shown; held by constraints as the pills are. */
@interface SGABadge : NSTextField
{
@public
	int target;
	int kind;   /* 1 text, 2 dot */
	NSArray<NSLayoutConstraint *> *placing;
}
@end
@implementation SGABadge
- (BOOL)isAccessibilityElement { return NO; }
@end

static NSMutableDictionary<NSNumber *, SGABadge *> *s_badges;

static void sga_badge_place(SGABadge *b)
{
	NSView *t = s_margins[b->target][0] ? s_inner[b->target] : sga_get(b->target);
	NSView *c = [[t window] contentView];
	if (![t isKindOfClass:[NSView class]] || !c || ![t isDescendantOf:c]) return;
	if ([b superview] != c) { [b removeFromSuperview]; [c addSubview:b positioned:NSWindowAbove relativeTo:nil]; }
	if (b->placing) [NSLayoutConstraint deactivateConstraints:b->placing];
	b->placing = @[[b.centerXAnchor constraintEqualToAnchor:t.trailingAnchor constant:-4], [b.centerYAnchor constraintEqualToAnchor:t.topAnchor constant:2]];
	[NSLayoutConstraint activateConstraints:b->placing];
}

static void sga_badges_sync(void) { for (SGABadge *b in [s_badges allValues]) if (![b superview]) sga_badge_place(b); }

void sga_widget_set_badge(int a_id, const char *a_text, int a_kind)
{
	if (!s_badges) s_badges = [NSMutableDictionary dictionary];
	SGABadge *b = s_badges[@(a_id)];
	if (a_kind == 0) {
		if (b) { if (b->placing) [NSLayoutConstraint deactivateConstraints:b->placing]; [b removeFromSuperview]; [s_badges removeObjectForKey:@(a_id)]; }
		return;
	}
	if (!b) {
		b = [SGABadge labelWithString:@""];
		[b setTranslatesAutoresizingMaskIntoConstraints:NO];
		[b setFont:[NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize] - 1]];
		[b setTextColor:[NSColor whiteColor]];
		[b setAlignment:NSTextAlignmentCenter];
		[b setDrawsBackground:YES];
		[b setBackgroundColor:[NSColor systemRedColor]];
		[b setWantsLayer:YES];
		[[b layer] setMasksToBounds:YES];
		b->target = a_id;
		s_badges[@(a_id)] = b;
	}
	b->kind = a_kind;
	if (a_kind == 2) {
		[b setStringValue:@""];
		[[b layer] setCornerRadius:4];
		[NSLayoutConstraint deactivateConstraints:[b constraints]];
		[NSLayoutConstraint activateConstraints:@[[b.widthAnchor constraintEqualToConstant:8], [b.heightAnchor constraintEqualToConstant:8]]];
	} else {
		[b setStringValue:[NSString stringWithFormat:@" %@ ", sga_string(a_text)]];
		[[b layer] setCornerRadius:7.5];
		[NSLayoutConstraint deactivateConstraints:[b constraints]];
		[NSLayoutConstraint activateConstraints:@[[b.heightAnchor constraintEqualToConstant:15], [b.widthAnchor constraintGreaterThanOrEqualToConstant:15]]];
	}
	sga_badge_place(b);
}

const char *sga_test_badge_shown(int a_id)
{
	SGABadge *b = s_badges[@(a_id)];
	NSString *s = !b ? @"" : b->kind == 2 ? @"•" : [[b stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	return sga_return(Kind_label, s);
}

/* ----------------------------------------------------------------- common */

void sga_set_enabled(int a_id, int a_on)
{
	id o = sga_core(a_id);
	if ([o isKindOfClass:[SGASpin class]]) {
		[((SGASpin *)o)->field setEnabled:a_on != 0];
		[((SGASpin *)o)->stepper setEnabled:a_on != 0];
	}
	if ([o isKindOfClass:[SGARadioGroup class]]) for (NSButton *b in [(SGARadioGroup *)o arrangedSubviews]) [b setEnabled:a_on != 0];
	if ([o isKindOfClass:[SGAExpander class]]) {
		[((SGAExpander *)o)->triangle setEnabled:a_on != 0];
		[((SGAExpander *)o)->title setEnabled:a_on != 0];
	}
	if ([o isKindOfClass:[NSControl class]]) [(NSControl *)o setEnabled:a_on != 0];
	[[s_toolbar_item objectForKey:o] setEnabled:a_on != 0];
}

int sga_is_enabled(int a_id)
{
	id o = sga_core(a_id);
	if ([o isKindOfClass:[SGASpin class]]) return [((SGASpin *)o)->field isEnabled] ? 1 : 0;
	if ([o isKindOfClass:[SGARadioGroup class]]) return [[[(SGARadioGroup *)o arrangedSubviews] firstObject] isEnabled] || ![[(SGARadioGroup *)o arrangedSubviews] count] ? 1 : 0;
	if ([o isKindOfClass:[SGAExpander class]]) return [((SGAExpander *)o)->triangle isEnabled] ? 1 : 0;
	return [o isKindOfClass:[NSControl class]] ? ([(NSControl *)o isEnabled] ? 1 : 0) : 1;
}

void sga_set_visible(int a_id, int a_on)
{
	id o = sga_get(a_id);
	if ([o isKindOfClass:[NSWindow class]]) { if (a_on) [(NSWindow *)o orderFront:nil]; else [(NSWindow *)o orderOut:nil]; }
	else {
		[(NSView *)o setHidden:a_on == 0];
		/* In a stack the slot goes too, so no gap is left. */
		if ([o isKindOfClass:[NSView class]] && sga_slot_of(o)) [sga_slot_of(o) setHidden:a_on == 0];
	}
}

int sga_is_visible(int a_id)
{
	id o = sga_get(a_id);
	if ([o isKindOfClass:[NSWindow class]]) return [(NSWindow *)o isVisible] ? 1 : 0;
	return [(NSView *)o isHidden] ? 0 : 1;
}

/* A tab view whose direction changed: its items in the opposite order (see
   sga_tabs_reversed), the shown page kept. */
static void sga_tabs_flip(NSTabView *t)
{
	NSArray<NSTabViewItem *> *l_items = [[t tabViewItems] copy];
	NSTabViewItem *l_shown = [t selectedTabViewItem];
	s_suppress++;
	for (NSTabViewItem *i in l_items) [t removeTabViewItem:i];
	for (NSTabViewItem *i in [l_items reverseObjectEnumerator]) [t addTabViewItem:i];
	if (l_shown) [t selectTabViewItem:l_shown];
	s_suppress--;
}

/* A table (or list, or outline) whose direction changed: NSTableView places its columns by
   direction only when they are added, so they are added again (probed: setting the
   direction later, or re-adding the view, changes nothing). The sort indicators, the
   highlighted column and an outline's disclosure column are kept (the selection is kept by
   sga_set_direction). */
static void sga_table_relayout(NSTableView *t)
{
	NSArray<NSTableColumn *> *l_columns = [[t tableColumns] copy];
	NSMutableArray *l_indicators = [NSMutableArray array];
	NSTableColumn *l_highlighted = [t highlightedTableColumn];
	NSTableColumn *l_outline = [t isKindOfClass:[NSOutlineView class]] ? [(NSOutlineView *)t outlineTableColumn] : nil;
	for (NSTableColumn *c in l_columns) [l_indicators addObject:[t indicatorImageInTableColumn:c] ?: [NSNull null]];
	s_suppress++;
	for (NSTableColumn *c in l_columns) [t removeTableColumn:c];
	for (NSTableColumn *c in l_columns) [t addTableColumn:c];
	if (l_outline) [(NSOutlineView *)t setOutlineTableColumn:l_outline];
	[l_columns enumerateObjectsUsingBlock:^(NSTableColumn *c, NSUInteger k, BOOL *a_stop) {
		id l_image = l_indicators[k];
		if (l_image != [NSNull null]) [t setIndicatorImage:l_image inTableColumn:c];
	}];
	[t setHighlightedTableColumn:l_highlighted];
	for (NSTableColumn *c in l_columns) [[c headerCell] setAlignment:sga_start_alignment(t)];
	[[t headerView] setNeedsDisplay:YES];
	[t reloadData];   /* the cells take their new alignment (rows and expansion stay) */
	s_suppress--;
}

void sga_set_direction(int a_id, int a_direction)
{
	id l_object = sga_get(a_id);
	if ([l_object isKindOfClass:[NSWindow class]]) l_object = [(NSWindow *)l_object contentView];
	NSView *v = l_object;
	id l_core = sga_core(a_id);
	NSUserInterfaceLayoutDirection l_layout = a_direction == 2 ? NSUserInterfaceLayoutDirectionRightToLeft
		: a_direction == 1 ? NSUserInterfaceLayoutDirectionLeftToRight : [NSApp userInterfaceLayoutDirection];
	BOOL l_changed = [v userInterfaceLayoutDirection] != l_layout || [(NSView *)l_core userInterfaceLayoutDirection] != l_layout;
	/* A table's selection, before anything changes: setting a list's direction clears it (seen
	   on GUI_LIST), and re-adding the columns would too. */
	NSIndexSet *l_selected = [l_core isKindOfClass:[NSTableView class]] ? [[(NSTableView *)l_core selectedRowIndexes] copy] : nil;
	[v setUserInterfaceLayoutDirection:l_layout];
	if (l_core != v) [(NSView *)l_core setUserInterfaceLayoutDirection:l_layout];
	if (l_changed) {
		if (s_margins[a_id][0] && [s_inner[a_id] superview]) sga_reattach(a_id);   /* a margin wrapper */
		/* In a stack, the child is placed in its slot by the child's own direction. */
		SGASlot *l_slot = sga_slot_of(v);
		if (l_slot) { [l_slot setUserInterfaceLayoutDirection:l_layout]; sga_place(l_slot, l_slot->alignment); }
	}
	if (l_changed && [l_core isKindOfClass:[NSTabView class]]) sga_tabs_flip((NSTabView *)l_core);
	if (l_changed && [l_core isKindOfClass:[NSTableView class]]) sga_table_relayout((NSTableView *)l_core);
	if (l_selected && ![[(NSTableView *)l_core selectedRowIndexes] isEqualToIndexSet:l_selected]) {
		s_suppress++;
		[(NSTableView *)l_core selectRowIndexes:l_selected byExtendingSelection:NO];
		s_suppress--;
	}
	/* Text: the direction places it (right-aligned under right to left, as GTK mirrors a
	   label's alignment), but the text's own letters decide its writing direction, so an
	   English sentence in a Hebrew window keeps its full stop at the end. A widget set left
	   to right on purpose (numbers, expressions) reads left to right whatever it holds. */
	NSTextAlignment l_align = a_direction == 2 ? NSTextAlignmentRight : a_direction == 1 ? NSTextAlignmentLeft : NSTextAlignmentNatural;
	NSWritingDirection l_writing = a_direction == 1 ? NSWritingDirectionLeftToRight : NSWritingDirectionNatural;
	if ([l_core isKindOfClass:[NSTextView class]]) {
		NSTextView *t = (NSTextView *)l_core;
		[t setBaseWritingDirection:l_writing];
		[t setAlignment:l_align];
	}
	if ([l_core isKindOfClass:[NSTextField class]]) {
		NSTextField *f = (NSTextField *)l_core;
		[f setBaseWritingDirection:l_writing];
		[f setAlignment:l_align];
	}
}

/* Short help shown when the pointer rests on the widget (1h); empty removes it. A widget
   wrapped in a scroll view gets it on both, so it shows over the scroll bars too. */
void sga_set_tooltip(int a_id, const char *a_text)
{
	NSString *l_tip = [sga_string(a_text) length] ? sga_string(a_text) : nil;
	id o = sga_get(a_id);
	if ([o isKindOfClass:[NSView class]]) [(NSView *)o setToolTip:l_tip];
	if (sga_core(a_id) != o && [sga_core(a_id) isKindOfClass:[NSView class]]) [(NSView *)sga_core(a_id) setToolTip:l_tip];
}

/* The object assistive tools read for a widget: a simple control's cell. */
static id sga_accessible(int a_id)
{
	id o = sga_core(a_id);
	if ([o isKindOfClass:[NSWindow class]]) return o;
	if ([o isKindOfClass:[NSControl class]] && [(NSControl *)o cell]) return [(NSControl *)o cell];
	return o;
}

void sga_set_accessible_label(int a_id, const char *a_text)
{
	NSString *s = sga_string(a_text);
	[sga_accessible(a_id) setAccessibilityLabel:s];
	[(id)sga_core(a_id) setAccessibilityLabel:s];
}

void sga_set_accessible_description(int a_id, const char *a_text)
{
	NSString *s = sga_string(a_text);
	[sga_accessible(a_id) setAccessibilityHelp:s];
	[(id)sga_core(a_id) setAccessibilityHelp:s];
}

/* AppKit's roles in the vocabulary the shared tests use (GTK's role names). */
static NSString *sga_role_name(NSString *a_role)
{
	static NSDictionary *l_names;
	if (!l_names) l_names = @{
		NSAccessibilityButtonRole: @"button", NSAccessibilityTextFieldRole: @"text-box",
		NSAccessibilityStaticTextRole: @"label", NSAccessibilityTableRole: @"list",
		NSAccessibilityListRole: @"list", NSAccessibilityOutlineRole: @"list",
		NSAccessibilityRowRole: @"list-item", NSAccessibilityCellRole: @"list-item",
		NSAccessibilityMenuBarRole: @"menu-bar", NSAccessibilityMenuItemRole: @"menu-item",
		NSAccessibilityMenuRole: @"menu", NSAccessibilityWindowRole: @"application",
		NSAccessibilityImageRole: @"img", NSAccessibilityScrollAreaRole: @"generic",
		NSAccessibilityGroupRole: @"generic", NSAccessibilityCheckBoxRole: @"checkbox",
		NSAccessibilitySliderRole: @"slider", NSAccessibilityTextAreaRole: @"text-box",
		NSAccessibilityTabGroupRole: @"tab-list", NSAccessibilityPopUpButtonRole: @"combo-box",
		NSAccessibilityProgressIndicatorRole: @"progress-bar", NSAccessibilityToolbarRole: @"toolbar",
		NSAccessibilityIncrementorRole: @"spin-button", NSAccessibilityRadioButtonRole: @"radio",
		NSAccessibilityComboBoxRole: @"combo-box", NSAccessibilityColorWellRole: @"button",
		NSAccessibilityDisclosureTriangleRole: @"button", NSAccessibilityLevelIndicatorRole: @"meter",
		@"AXMenuButton": @"button"};
	return l_names[a_role] ?: @"generic";
}

const char *sga_accessible_role(int a_id)
{
	if ([sga_core(a_id) isKindOfClass:[SGAGridTable class]]) return sga_return(Kind_role, @"tree-grid");
	if ([sga_core(a_id) isKindOfClass:[SGATree class]]) return sga_return(Kind_role, ((SGATree *)sga_core(a_id))->is_table ? @"tree-grid" : @"tree");
	if ([sga_core(a_id) isKindOfClass:[SGASpin class]]) return sga_return(Kind_role, @"spin-button");
	if ([sga_core(a_id) isKindOfClass:[SGAStatus class]]) return sga_return(Kind_role, @"status");
	if ([sga_core(a_id) isKindOfClass:[SGAToolbar class]]) return sga_return(Kind_role, @"toolbar");
	if ([sga_core(a_id) isKindOfClass:[SGASwitch class]]) return sga_return(Kind_role, @"switch");
	if ([sga_core(a_id) isKindOfClass:[SGADrawn class]]) return sga_return(Kind_role, @"group");
	if ([sga_core(a_id) isKindOfClass:[SGARadioGroup class]] || [sga_core(a_id) isKindOfClass:[SGASegmented class]]) return sga_return(Kind_role, @"radio-group");
	if ([sga_core(a_id) isKindOfClass:[SGADatePicker class]])
		return sga_return(Kind_role, [(NSDatePicker *)sga_core(a_id) datePickerStyle] == NSDatePickerStyleClockAndCalendar ? @"grid" : @"spin-button");
	if ([sga_core(a_id) isKindOfClass:[SGAMenuButton class]] || [sga_core(a_id) isKindOfClass:[NSComboButton class]]) return sga_return(Kind_role, @"button");
	if ([sga_core(a_id) isKindOfClass:[SGAPopover class]]) return sga_return(Kind_role, @"dialog");
	if ([sga_core(a_id) isKindOfClass:[SGASearchField class]]) return sga_return(Kind_role, @"search-box");
	if ([sga_core(a_id) isKindOfClass:[SGAPathControl class]]) return sga_return(Kind_role, @"navigation");
	if ([sga_core(a_id) isKindOfClass:[SGARating class]]) return sga_return(Kind_role, @"slider");
	if ([sga_core(a_id) isKindOfClass:[SGAExpander class]]) return sga_return(Kind_role, @"button");
	if ([sga_core(a_id) isKindOfClass:[NSBox class]]) return sga_return(Kind_role, [(NSBox *)sga_core(a_id) boxType] == NSBoxSeparator ? @"separator" : @"group");
	return sga_return(Kind_role, sga_role_name([sga_accessible(a_id) accessibilityRole]));
}

/* ----------------------------------------------------------------- canvas */

int sga_canvas(int a_width, int a_height)
{
	SGACanvas *c = [[SGACanvas alloc] initWithFrame:NSMakeRect(0, 0, a_width, a_height)];
	c->wanted = NSMakeSize(a_width, a_height);
	/* The requested size is a preference, not a minimum: the canvas gives way first, so
	   the window keeps the size the program asked for. */
	[c setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];
	[c setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationVertical];
	[c setAccessibilityRole:NSAccessibilityImageRole];
	return sga_keep(c);
}

/* A finished Cairo image surface at device scale: copied (so the caller may reuse
   it), and tagged sRGB so macOS color-manages it (spike mac_color). */
void sga_canvas_present(int a_id, void *a_cairo_surface)
{
	SGACanvas *c = sga_get(a_id);
	cairo_surface_t *s = (cairo_surface_t *)a_cairo_surface;
	if (!c || !s || cairo_surface_get_type(s) != CAIRO_SURFACE_TYPE_IMAGE) return;
	cairo_surface_flush(s);
	int w = cairo_image_surface_get_width(s), h = cairo_image_surface_get_height(s), l_stride = cairo_image_surface_get_stride(s);
	CGColorSpaceRef l_srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CFDataRef l_data = CFDataCreate(NULL, cairo_image_surface_get_data(s), (CFIndex)l_stride * h);
	CGDataProviderRef l_provider = CGDataProviderCreateWithCFData(l_data);
	CGImageRef l_image = CGImageCreate((size_t)w, (size_t)h, 8, 32, (size_t)l_stride, l_srgb,
		kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, l_provider, NULL, false, kCGRenderingIntentDefault);
	CGDataProviderRelease(l_provider);
	CFRelease(l_data);
	CGColorSpaceRelease(l_srgb);
	if (c->image) CGImageRelease(c->image);
	c->image = l_image;
	[c setNeedsDisplay:YES];
}

/* Device pixels per point: the window's backing scale (the main screen's before the canvas is in
   a window). macOS uses 1.0 and 2.0 today; the API is a REAL so a future fractional scale
   needs no change. */
double sga_scale(int a_id)
{
	NSWindow *w = [(NSView *)sga_get(a_id) window];
	CGFloat f = w ? [w backingScaleFactor] : [[NSScreen mainScreen] backingScaleFactor];
	return f > 0 ? (double)f : 1.0;
}

/* `sga_scale' rounded up (the superseded whole-number form). */
int sga_scale_factor(int a_id)
{
	int f = (int)ceil(sga_scale(a_id));
	return f < 1 ? 1 : f;
}

/* A window's size is its content's (what the program lays out in); a widget's, its own. */
/* A container's size leaves its margins out (as its position does, and as GTK reports it):
   the stack or grid inside the wrapper is measured. */
static NSView *sga_measured_view(int a_id)
{
	id o = sga_get(a_id);
	if ([o isKindOfClass:[NSWindow class]]) return [(NSWindow *)o contentView];
	return s_margins[a_id][0] ? (NSView *)s_inner[a_id] : (NSView *)o;
}

int sga_width(int a_id)
{
	NSView *v = sga_measured_view(a_id);
	int w = (int)[v bounds].size.width;
	return w > 0 ? w : ([v isKindOfClass:[SGACanvas class]] ? (int)((SGACanvas *)v)->wanted.width : 0);
}

int sga_height(int a_id)
{
	NSView *v = sga_measured_view(a_id);
	int h = (int)[v bounds].size.height;
	return h > 0 ? h : ([v isKindOfClass:[SGACanvas class]] ? (int)((SGACanvas *)v)->wanted.height : 0);
}

/* ------------------------------------------------------------------ menus */

/* The key of a neutral shortcut ("F5", "Delete", "PageUp", "comma", or a letter or digit) as
   an AppKit key equivalent. The vocabulary is SW_SHORTCUT's (simple_widgets W8), shared by
   every backend; an unknown name gives no key rather than a nonsense one. */
static NSString *sga_named_key(NSString *a_name)
{
	static NSDictionary<NSString *, NSString *> *l_names;
	if (!l_names) {
		unichar f[] = {NSUpArrowFunctionKey, NSDownArrowFunctionKey, NSLeftArrowFunctionKey, NSRightArrowFunctionKey,
			NSHomeFunctionKey, NSEndFunctionKey, NSPageUpFunctionKey, NSPageDownFunctionKey,
			NSInsertFunctionKey, NSDeleteFunctionKey};
		NSString *(^k)(unichar) = ^(unichar c) { return [NSString stringWithCharacters:&c length:1]; };
		l_names = @{@"up": k(f[0]), @"down": k(f[1]), @"left": k(f[2]), @"right": k(f[3]),
			@"home": k(f[4]), @"end": k(f[5]), @"pageup": k(f[6]), @"pagedown": k(f[7]),
			@"insert": k(f[8]), @"delete": k(f[9]), @"backspace": k(0x08), @"escape": k(0x1b), @"esc": k(0x1b),
			@"enter": @"\r", @"return": @"\r", @"tab": @"\t", @"space": @" ",
			@"plus": @"+", @"minus": @"-", @"comma": @",", @"period": @"."};
	}
	if ([a_name length] == 1) return a_name;
	if ([a_name length] >= 2 && [a_name characterAtIndex:0] == 'f') {
		NSInteger n = [[a_name substringFromIndex:1] integerValue];
		if (n >= 1 && n <= 12 && [[NSString stringWithFormat:@"f%ld", (long)n] isEqualToString:a_name])
			{ unichar c = (unichar)(NSF1FunctionKey + n - 1); return [NSString stringWithCharacters:&c length:1]; }
	}
	return l_names[a_name] ?: @"";
}

static NSString *sga_key_of(NSString *a_shortcut, NSEventModifierFlags *a_mask)
{
	NSString *l_key = @"";
	*a_mask = 0;
	for (NSString *l_part in [[a_shortcut lowercaseString] componentsSeparatedByString:@"+"]) {
		if ([l_part isEqualToString:@"primary"] || [l_part isEqualToString:@"command"]) *a_mask |= NSEventModifierFlagCommand;
		else if ([l_part isEqualToString:@"shift"]) *a_mask |= NSEventModifierFlagShift;
		else if ([l_part isEqualToString:@"alt"] || [l_part isEqualToString:@"option"]) *a_mask |= NSEventModifierFlagOption;
		else if ([l_part isEqualToString:@"control"] || [l_part isEqualToString:@"ctrl"]) *a_mask |= NSEventModifierFlagControl;
		else if ([l_part length]) l_key = sga_named_key(l_part);
	}
	return l_key;
}

static NSMenuItem *sga_item(NSString *a_text, SEL a_action, id a_target, NSString *a_shortcut)
{
	NSEventModifierFlags l_mask;
	NSString *l_key = sga_key_of(a_shortcut, &l_mask);
	NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:a_text action:a_action keyEquivalent:l_key];
	[i setKeyEquivalentModifierMask:l_mask];
	[i setTarget:a_target];
	return i;
}

void *sga_menu_new(const char *a_title)
{
	NSString *l_title = sga_string(a_title);
	NSMenuItem *l_top = [[NSMenuItem alloc] initWithTitle:l_title action:nil keyEquivalent:@""];
	NSMenu *m = [[NSMenu alloc] initWithTitle:l_title];
	[l_top setSubmenu:m];
	/* Before the Window menu, which stays after the program's own menus. */
	NSMenu *l_bar = [NSApp mainMenu];
	NSInteger l_window = s_window_item ? [l_bar indexOfItem:s_window_item] : -1;
	if (l_window >= 0) [l_bar insertItem:l_top atIndex:l_window]; else [l_bar addItem:l_top];
	return (__bridge void *)m;   /* the main menu keeps it alive */
}

/* About and Quit read "About <app>" and "Quit <app>" on a Mac, in any language: the app
   name follows the text it is given ("About" -> "About Calc", "אודות" -> "אודות Calc"). */
static NSString *sga_role_title(int a_role, NSString *a_text)
{
	return (a_role == 1 || a_role == 3) ? [NSString stringWithFormat:@"%@ %@", a_text, s_app_name] : a_text;
}

/* Roles go where a Mac user looks: About, Settings and Quit move to the application
   menu (and still come back as menu events, so the application decides); the edit
   roles go through the responder chain, so text fields get them with no Eiffel code.
   Every item carries its id as its tag (edit items raise no event; the tag finds them
   for relabeling) and its role as its represented object. */
void sga_menu_add_item(void *a_menu, const char *a_text, const char *a_shortcut, int a_item_id, int a_role)
{
	NSMenu *m = (__bridge NSMenu *)a_menu;
	NSMenu *l_app = [[[NSApp mainMenu] itemAtIndex:0] submenu];
	NSString *l_text = sga_role_title(a_role, sga_string(a_text)), *l_shortcut = sga_string(a_shortcut);
	/* On a Mac the Edit menu's key equivalents are what carry Command-Z, X, C, V and A to the
	   focused text field (GTK and Windows text boxes take those keys themselves), so an edit
	   role the program gave no shortcut gets the standard one. */
	if ([l_shortcut length] == 0 && a_role >= 10 && a_role <= 15) {
		static NSString *const l_standard[] = {@"primary+z", @"primary+shift+z", @"primary+x", @"primary+c", @"primary+v", @"primary+a"};
		l_shortcut = l_standard[a_role - 10];
	}
	NSMenuItem *i;
	switch (a_role) {
		case 1:
			/* About heads the application menu. The menu the program put it in is its Help
			   menu: macOS adds the search field there, and the Window menu goes before it. */
			i = sga_item(l_text, @selector(menuItem:), s_target, l_shortcut);
			[l_app insertItem:i atIndex:0];
			[l_app insertItem:[NSMenuItem separatorItem] atIndex:1];
			if (m != l_app && [[NSApp mainMenu] indexOfItemWithSubmenu:m] >= 0) {
				NSMenu *l_bar = [NSApp mainMenu];
				[NSApp setHelpMenu:m];
				if (s_window_item) {
					[l_bar removeItem:s_window_item];
					[l_bar insertItem:s_window_item atIndex:[l_bar indexOfItemWithSubmenu:m]];
				}
			}
			break;
		case 2:
			/* Settings sits above Services, in a section of its own. */
			i = sga_item(l_text, @selector(menuItem:), s_target, [l_shortcut length] ? l_shortcut : @"primary+comma");
			{
				NSInteger l_at = s_services_item ? [l_app indexOfItem:s_services_item] : [l_app numberOfItems];
				[l_app insertItem:i atIndex:l_at];
				[l_app insertItem:[NSMenuItem separatorItem] atIndex:l_at + 1];
			}
			break;
		case 3:
			if ([l_app numberOfItems] > 0) [l_app addItem:[NSMenuItem separatorItem]];
			i = sga_item(l_text, @selector(menuItem:), s_target, @"primary+q");
			[l_app addItem:i];
			break;
		case 10: i = sga_item(l_text, @selector(undo:), nil, l_shortcut); [m addItem:i]; break;
		case 11: i = sga_item(l_text, @selector(redo:), nil, l_shortcut); [m addItem:i]; break;
		case 12: i = sga_item(l_text, @selector(cut:), nil, l_shortcut); [m addItem:i]; break;
		case 13: i = sga_item(l_text, @selector(copy:), nil, l_shortcut); [m addItem:i]; break;
		case 14: i = sga_item(l_text, @selector(paste:), nil, l_shortcut); [m addItem:i]; break;
		case 15: i = sga_item(l_text, @selector(selectAll:), nil, l_shortcut); [m addItem:i]; break;
		default:
			i = sga_item(l_text, @selector(menuItem:), s_target, l_shortcut);
			[m addItem:i];
	}
	[i setTag:a_item_id];
	[i setRepresentedObject:@(a_role)];
}

void sga_menu_add_separator(void *a_menu) { [(__bridge NSMenu *)a_menu addItem:[NSMenuItem separatorItem]]; }

/* Context menus: an NSMenu outside the menu bar, kept alive here. A view's `menu' is what
   AppKit shows on a right-click, a Control-click or a two-finger click, so attaching it is
   all a widget needs; its items send menu events (5) like any other. */
static NSMutableArray<NSMenu *> *s_context_menus;

void *sga_context_menu_new(void)
{
	NSMenu *m = [[NSMenu alloc] initWithTitle:@""];
	if (!s_context_menus) s_context_menus = [NSMutableArray array];
	[s_context_menus addObject:m];
	return (__bridge void *)m;
}

void sga_widget_set_context_menu(int a_id, void *a_menu)
{
	NSMenu *m = (__bridge NSMenu *)a_menu;
	[(NSView *)sga_get(a_id) setMenu:m];
	/* The core (a list's table, a text area's text view) is what the click lands on. */
	if (sga_core(a_id) != sga_get(a_id) && [sga_core(a_id) isKindOfClass:[NSView class]]) [(NSView *)sga_core(a_id) setMenu:m];
}

/* Any item with this id, whatever its action. */
static NSMenuItem *sga_find_numbered(NSMenu *a_menu, int a_id)
{
	for (NSMenuItem *i in [a_menu itemArray]) {
		if ([i submenu]) { NSMenuItem *f = sga_find_numbered([i submenu], a_id); if (f) return f; }
		else if ([i tag] == a_id && [i representedObject]) return i;
	}
	return nil;
}

/* An item with this id in the menu bar or in any context menu. */
static NSMenuItem *sga_find_numbered_anywhere(int a_id)
{
	NSMenuItem *i = sga_find_numbered([NSApp mainMenu], a_id);
	for (NSMenu *m in s_context_menus) if (!i) i = sga_find_numbered(m, a_id);
	return i;
}

/* The menu bar shows the menu's own title; its item in the bar is kept the same. */
void sga_menu_set_title(void *a_menu, const char *a_title)
{
	NSMenu *m = (__bridge NSMenu *)a_menu;
	NSString *l_title = sga_string(a_title);
	[m setTitle:l_title];
	for (NSMenuItem *i in [[NSApp mainMenu] itemArray]) if ([i submenu] == m) [i setTitle:l_title];
}

const char *sga_menu_title(void *a_menu) { return sga_return(Kind_menu, [(__bridge NSMenu *)a_menu title]); }

void sga_menu_set_item_text(int a_item_id, const char *a_text)
{
	NSMenuItem *i = sga_find_numbered_anywhere(a_item_id);
	if (i) [i setTitle:sga_role_title([[i representedObject] intValue], sga_string(a_text))];
}

const char *sga_menu_item_text(int a_item_id)
{
	NSMenuItem *i = sga_find_numbered_anywhere(a_item_id);
	return sga_return(Kind_menu, i ? [i title] : @"");
}

/* ---------------------------------------------------------------- dialogs */

static int s_auto_cancel_ms;

static void sga_maybe_auto_cancel(void)
{
	if (s_auto_cancel_ms > 0) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)s_auto_cancel_ms * NSEC_PER_MSEC),
			dispatch_get_main_queue(), ^{ [NSApp stopModalWithCode:NSModalResponseCancel]; });
	}
}

static NSArray<UTType *> *sga_types(const char *a_extensions)
{
	NSMutableArray<UTType *> *l_types = [NSMutableArray array];
	for (NSString *e in [sga_string(a_extensions) componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@";,"]]) {
		NSString *l_ext = [e stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" .*"]];
		UTType *t = [l_ext length] ? [UTType typeWithFilenameExtension:l_ext] : nil;
		if (t) [l_types addObject:t];
	}
	return l_types;
}

const char *sga_open_file(int a_window, const char *a_title, int a_save, const char *a_extensions)
{
	NSArray *l_types = sga_types(a_extensions);
	NSURL *l_url = nil;
	(void)a_window;   /* app-modal for 0.1; a sheet on `a_window' later */
	if (a_save) {
		NSSavePanel *p = [NSSavePanel savePanel];
		[p setMessage:sga_string(a_title)];
		if ([l_types count]) [p setAllowedContentTypes:l_types];
		sga_maybe_auto_cancel();
		if ([p runModal] == NSModalResponseOK) l_url = [p URL];
	} else {
		NSOpenPanel *p = [NSOpenPanel openPanel];
		[p setMessage:sga_string(a_title)];
		[p setCanChooseFiles:YES];
		[p setCanChooseDirectories:NO];
		if ([l_types count]) [p setAllowedContentTypes:l_types];
		sga_maybe_auto_cancel();
		if ([p runModal] == NSModalResponseOK) l_url = [[p URLs] firstObject];
	}
	return l_url ? sga_return(Kind_path, [l_url path]) : NULL;
}

int sga_message(int a_window, const char *a_title, const char *a_text, int a_confirm)
{
	NSAlert *l_alert = [[NSAlert alloc] init];
	(void)a_window;
	[l_alert setMessageText:sga_string(a_title)];
	[l_alert setInformativeText:sga_string(a_text)];
	[l_alert addButtonWithTitle:@"OK"];
	if (a_confirm) [l_alert addButtonWithTitle:@"Cancel"];
	sga_maybe_auto_cancel();
	return [l_alert runModal] == NSAlertFirstButtonReturn ? 1 : 0;
}

/* Dialogs (1h). Like the others, app-modal; sga_test_auto_cancel_dialogs cancels them. */

/* Save, with a suggested file name; NULL when cancelled. */
const char *sga_save_file_named(int a_window, const char *a_title, const char *a_extensions, const char *a_name)
{
	NSArray *l_types = sga_types(a_extensions);
	NSSavePanel *p = [NSSavePanel savePanel];
	(void)a_window;
	[p setMessage:sga_string(a_title)];
	if ([l_types count]) [p setAllowedContentTypes:l_types];
	[p setNameFieldStringValue:sga_string(a_name)];
	sga_maybe_auto_cancel();
	return [p runModal] == NSModalResponseOK ? sga_return(Kind_path, [[p URL] path]) : NULL;
}

/* Choose a folder; NULL when cancelled. A new folder can be made from the panel. */
const char *sga_choose_folder(int a_window, const char *a_title)
{
	NSOpenPanel *p = [NSOpenPanel openPanel];
	(void)a_window;
	[p setMessage:sga_string(a_title)];
	[p setCanChooseFiles:NO];
	[p setCanChooseDirectories:YES];
	[p setCanCreateDirectories:YES];
	[p setAllowsMultipleSelection:NO];
	sga_maybe_auto_cancel();
	return [p runModal] == NSModalResponseOK ? sga_return(Kind_path, [[[p URLs] firstObject] path]) : NULL;
}

/* A three-way question: 1 yes, 2 no, 0 cancel. Mac keys: Return is Yes, Escape is Cancel,
   Command-D is No (as in "Don't Save"). */
int sga_ask(int a_window, const char *a_title, const char *a_text)
{
	NSAlert *l_alert = [[NSAlert alloc] init];
	(void)a_window;
	[l_alert setMessageText:sga_string(a_title)];
	[l_alert setInformativeText:sga_string(a_text)];
	[l_alert addButtonWithTitle:@"Yes"];
	NSButton *l_no = [l_alert addButtonWithTitle:@"No"];
	[l_no setKeyEquivalent:@"d"];
	[l_no setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
	NSButton *l_cancel = [l_alert addButtonWithTitle:@"Cancel"];
	[l_cancel setKeyEquivalent:@"\033"];
	sga_maybe_auto_cancel();
	NSModalResponse r = [l_alert runModal];
	return r == NSAlertFirstButtonReturn ? 1 : r == NSAlertSecondButtonReturn ? 2 : 0;
}

/* Dialogs (1j). */

/* One line of text, or NULL when cancelled: NSAlert with a text field as its accessory. */
const char *sga_ask_text(int a_window, const char *a_title, const char *a_prompt, const char *an_initial)
{
	NSAlert *l_alert = [[NSAlert alloc] init];
	NSTextField *f = [NSTextField textFieldWithString:sga_string(an_initial)];
	(void)a_window;
	[l_alert setMessageText:sga_string(a_title)];
	[l_alert setInformativeText:sga_string(a_prompt)];
	[l_alert addButtonWithTitle:@"OK"];
	[l_alert addButtonWithTitle:@"Cancel"];
	[f setFrame:NSMakeRect(0, 0, 260, 24)];
	[l_alert setAccessoryView:f];
	[[l_alert window] setInitialFirstResponder:f];
	sga_maybe_auto_cancel();
	return [l_alert runModal] == NSAlertFirstButtonReturn ? sga_return(Kind_field, [f stringValue]) : NULL;
}

/* OK or Cancel, with a check box ("Don't ask again"): bit 0 is OK, bit 1 is the box. */
int sga_confirm_with_check(int a_window, const char *a_title, const char *a_text, const char *a_check)
{
	NSAlert *l_alert = [[NSAlert alloc] init];
	(void)a_window;
	[l_alert setMessageText:sga_string(a_title)];
	[l_alert setInformativeText:sga_string(a_text)];
	[l_alert addButtonWithTitle:@"OK"];
	[l_alert addButtonWithTitle:@"Cancel"];
	[l_alert setShowsSuppressionButton:YES];
	[[l_alert suppressionButton] setTitle:sga_string(a_check)];
	sga_maybe_auto_cancel();
	BOOL l_ok = [l_alert runModal] == NSAlertFirstButtonReturn;
	BOOL l_checked = [[l_alert suppressionButton] state] == NSControlStateValueOn;
	return (l_ok ? 1 : 0) | (l_checked ? 2 : 0);
}

/* A font: NSFontPanel, which is not modal of its own, run as a modal window with OK and
   Cancel beside it. The answer is "family\x1fpoints\x1fbold\x1fitalic", or NULL. */
@interface SGAFontChooser : NSObject
{
@public
	NSFont *font;
}
@end
@implementation SGAFontChooser
- (void)changeFont:(id)a_sender { font = [a_sender convertFont:font]; }
- (NSFontPanelModeMask)validModesForFontPanel:(NSFontPanel *)p { (void)p; return NSFontPanelModeMaskFace | NSFontPanelModeMaskSize | NSFontPanelModeMaskCollection; }
- (void)ok:(id)a_sender { (void)a_sender; [NSApp stopModalWithCode:NSModalResponseOK]; }
- (void)cancel:(id)a_sender { (void)a_sender; [NSApp stopModalWithCode:NSModalResponseCancel]; }
@end

const char *sga_choose_font(int a_window, const char *a_title, const char *a_family, double a_points, int a_bold, int a_italic)
{
	SGAFontChooser *c = [[SGAFontChooser alloc] init];
	NSFontManager *m = [NSFontManager sharedFontManager];
	NSFont *f = [NSFont fontWithName:sga_string(a_family) size:a_points > 0 ? a_points : 13] ?: [NSFont systemFontOfSize:a_points > 0 ? a_points : 13];
	(void)a_window;
	if (a_bold) f = [m convertFont:f toHaveTrait:NSBoldFontMask];
	if (a_italic) f = [m convertFont:f toHaveTrait:NSItalicFontMask];
	c->font = f;
	NSFontPanel *p = [m fontPanel:YES];
	[m setTarget:c];
	[m setSelectedFont:f isMultiple:NO];
	[p setTitle:sga_string(a_title)];
	/* OK and Cancel, under the panel's own controls. */
	NSButton *l_ok = [NSButton buttonWithTitle:@"OK" target:c action:@selector(ok:)];
	NSButton *l_cancel = [NSButton buttonWithTitle:@"Cancel" target:c action:@selector(cancel:)];
	[l_ok setKeyEquivalent:@"\r"];
	[l_cancel setKeyEquivalent:@"\033"];
	NSStackView *l_buttons = [NSStackView stackViewWithViews:@[l_cancel, l_ok]];
	[l_buttons setEdgeInsets:NSEdgeInsetsMake(8, 8, 8, 8)];
	[p setAccessoryView:l_buttons];
	sga_maybe_auto_cancel();
	NSModalResponse r = [NSApp runModalForWindow:p];
	[p setAccessoryView:nil];
	[p orderOut:nil];
	[m setTarget:nil];
	if (r != NSModalResponseOK) return NULL;
	NSFontTraitMask t = [m traitsOfFont:c->font];
	return sga_return(Kind_path, [NSString stringWithFormat:@"%@\x1f%g\x1f%d\x1f%d", [c->font familyName] ?: @"", (double)[c->font pointSize],
		(t & NSBoldFontMask) ? 1 : 0, (t & NSItalicFontMask) ? 1 : 0]);
}

/* The standard About panel, with the program's name, version, copyright and comments. */
void sga_show_about(const char *a_name, const char *a_version, const char *a_copyright, const char *a_comments)
{
	NSMutableDictionary *o = [NSMutableDictionary dictionary];
	o[NSAboutPanelOptionApplicationName] = sga_string(a_name);
	o[NSAboutPanelOptionApplicationVersion] = sga_string(a_version);
	o[NSAboutPanelOptionVersion] = @"";
	o[@"Copyright"] = sga_string(a_copyright);
	if ([sga_string(a_comments) length]) o[NSAboutPanelOptionCredits] = [[NSAttributedString alloc] initWithString:sga_string(a_comments)];
	[NSApp orderFrontStandardAboutPanelWithOptions:o];
}

/* ------------------------------------------------------------- appearance */

int sga_is_dark(void)
{
	NSAppearanceName l_name = [[NSApp effectiveAppearance]
		bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
	return [l_name isEqualToString:NSAppearanceNameDarkAqua] ? 1 : 0;
}

void sga_set_dark(int a_on)
{
	s_setting_dark++;
	[NSApp setAppearance:[NSAppearance appearanceNamed:a_on ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]];
	s_setting_dark--;
	sga_push(10, 0, sga_is_dark(), 0, 0);
}

/* The theme's colors as 0xRRGGBB, resolved in the application's current appearance. A
   translucent color (text and separators are) is given as it looks over the window
   background, which is how it is seen. */
static void sga_rgb(NSColor *a_color, CGFloat *r, CGFloat *g, CGFloat *b, CGFloat *a)
{
	NSColor *c = [a_color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
	*r = [c redComponent]; *g = [c greenComponent]; *b = [c blueComponent]; *a = [c alphaComponent];
}
int sga_system_color(int a_role)
{
	__block int l_result = 0;
	[[NSApp effectiveAppearance] performAsCurrentDrawingAppearance:^{
		NSColor *l_color;
		switch (a_role) {
			case 1: l_color = [NSColor windowBackgroundColor]; break;
			case 2: l_color = [NSColor labelColor]; break;
			case 3: l_color = [NSColor secondaryLabelColor]; break;
			case 4: l_color = [NSColor controlAccentColor]; break;
			case 5: l_color = [NSColor selectedContentBackgroundColor]; break;
			default: l_color = [NSColor separatorColor]; break;
		}
		CGFloat r, g, b, a, br, bg, bb, ba;
		sga_rgb(l_color, &r, &g, &b, &a);
		sga_rgb([NSColor windowBackgroundColor], &br, &bg, &bb, &ba);
		r = r * a + br * (1 - a); g = g * a + bg * (1 - a); b = b * a + bb * (1 - a);
		l_result = ((int)lround(r * 255) << 16) | ((int)lround(g * 255) << 8) | (int)lround(b * 255);
	}];
	return l_result;
}

/* Where a widget is: its own frame (a container's inner stack or grid, margins excluded),
   from the top-left of its window's content area, y down, in points, after layout. */
static NSRect sga_frame_in_window(int a_id)
{
	NSView *v = s_margins[a_id][0] ? s_inner[a_id] : sga_get(a_id);
	NSView *l_content = [[v window] contentView];
	if (!l_content) return NSZeroRect;
	[l_content layoutSubtreeIfNeeded];
	NSRect r = [v convertRect:[v bounds] toView:l_content];
	if (![l_content isFlipped]) r.origin.y = [l_content bounds].size.height - NSMaxY(r);
	return r;
}
int sga_widget_x(int a_id) { return (int)lround(sga_frame_in_window(a_id).origin.x); }
int sga_widget_y(int a_id) { return (int)lround(sga_frame_in_window(a_id).origin.y); }

/* ------------------------------------------------------------ test driver */

void sga_test_click(int a_id) { [(NSButton *)sga_core(a_id) performClick:nil]; }

void sga_test_type(int a_id, const char *a_text)
{
	id o = sga_core(a_id);
	if ([o isKindOfClass:[NSTextView class]]) {
		/* As a user: replace everything through the text system, which sends textDidChange. */
		NSTextView *t = o;
		NSRange l_all = NSMakeRange(0, [[t string] length]);
		sga_colors_flush();
		[t setSelectedRange:l_all];
		[t insertText:sga_string(a_text) replacementRange:l_all];
		return;
	}
	NSTextField *f = sga_text_field(a_id);
	[f setStringValue:sga_string(a_text)];
	[[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidChangeNotification object:f];
}

static void sga_sidebar_user_choose(int a_id, int a_page);
@class SGASidebar;
void sga_test_choose(int a_id, int a_row)
{
	if ([sga_get(a_id) isKindOfClass:NSClassFromString(@"SGASidebar")]) { sga_sidebar_user_choose(a_id, a_row); return; }
	if ([s_inner[a_id] isKindOfClass:NSClassFromString(@"SGAGridView")]) { sga_grid_user_select(a_id, a_row, NO); return; }
	if ([sga_get(a_id) isKindOfClass:[SGAPathControl class]]) {   /* a click on that part */
		if (a_row >= 1 && a_row <= (int)[[(NSPathControl *)sga_get(a_id) pathItems] count]) sga_push(4, a_id, a_row, 0, 0);
		return;
	}
	if ([sga_get(a_id) isKindOfClass:[SGADropdown class]]) {
		sga_test_choose_option(a_id, a_row);
		return;
	}
	if ([sga_get(a_id) isKindOfClass:[SGARadioGroup class]]) {   /* a click on that radio */
		[(NSButton *)[(SGARadioGroup *)sga_get(a_id) arrangedSubviews][(NSUInteger)(a_row - 1)] performClick:nil];
		return;
	}
	if ([sga_get(a_id) isKindOfClass:[SGASegmented class]]) {   /* a click on that segment */
		SGASegmented *l_seg = sga_get(a_id);
		[l_seg setSelectedSegment:a_row - 1];
		[l_seg sendAction:[l_seg action] to:[l_seg target]];
		return;
	}
	if ([sga_get(a_id) isKindOfClass:[SGAComboBox class]]) {   /* that option picked from the list */
		[(SGAComboBox *)sga_get(a_id) selectItemAtIndex:a_row - 1];
		return;
	}
	if ([s_inner[a_id] isKindOfClass:[SGATree class]]) {   /* a node, by its number: shown, then clicked */
		SGATree *l_tree = s_inner[a_id];
		SGANode *n = sga_tree_node(l_tree, a_row);
		if (n) {
			sga_tree_reveal(l_tree, n);
			[l_tree selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[l_tree rowForItem:n]] byExtendingSelection:NO];
		}
		return;
	}
	if ([sga_get(a_id) isKindOfClass:[NSTabView class]]) {
		{ NSTabView *l_tabs = sga_get(a_id); [l_tabs selectTabViewItemAtIndex:sga_tab_item(l_tabs, a_row)]; }   /* as a click: page changed */
		return;
	}
	NSTableView *t = s_inner[a_id];
	/* One step, as a click: replacing the selection sends one selection change (deselecting
	   first would send two). The row is the model's (1s). */
	NSInteger v = sga_view_row(t, a_row - 1);
	if (v >= 0) [t selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)v] byExtendingSelection:NO];
}

static id sga_edit_target(SEL a_action);

/* Item `a_tag' of the program's own items or its Edit role items (10 .. 15). */
static NSMenuItem *sga_find_program_item(NSMenu *a_menu, int a_tag)
{
	for (NSMenuItem *i in [a_menu itemArray]) {
		int l_role = [[i representedObject] isKindOfClass:[NSNumber class]] ? [[i representedObject] intValue] : 0;
		if ([i tag] == a_tag && ([i action] == @selector(menuItem:) || (l_role >= 10 && l_role <= 15))) return i;
		if ([i submenu]) { NSMenuItem *f = sga_find_program_item([i submenu], a_tag); if (f) return f; }
	}
	return nil;
}

/* Choose item `a_item_id' as a user would. An Edit role item goes along the front window's
   responder chain, as it would with the application active (a test run from a terminal may
   leave it inactive, with no key window for AppKit to send to). */
void sga_test_menu(int a_item_id)
{
	NSMenuItem *i = sga_find_program_item([NSApp mainMenu], a_item_id);
	if (!i) return;
	if (![i target] && ![NSApp targetForAction:[i action] to:nil from:i]) {
		id l_target = sga_edit_target([i action]);
		if (l_target) [NSApp sendAction:[i action] to:l_target from:i];
		return;
	}
	[[i menu] performActionForItemAtIndex:[[i menu] indexOfItem:i]];
}

/* Focus widget `a_id' as a click on it would: its window comes to the front as the key window
   and the widget becomes first responder. A field's caret goes to the end of its text
   (AppKit would select it all, which a click does not). */
void sga_test_focus(int a_id)
{
	NSView *v = sga_core(a_id);
	NSWindow *w = [v window];
	if (!w) return;
	[w makeKeyAndOrderFront:nil];
	if ([w makeFirstResponder:v]) {
		id l_first = [w firstResponder];
		if ([l_first isKindOfClass:[NSTextView class]] && [(NSTextView *)l_first isFieldEditor])
			[(NSTextView *)l_first setSelectedRange:NSMakeRange([[(NSTextView *)l_first string] length], 0)];
	}
}

/* The window whose first responder the Edit menu acts on: the key window, else the frontmost
   visible window that can be key. */
static NSWindow *sga_front_window(void)
{
	NSWindow *w = [NSApp keyWindow];
	if (w && [w isVisible]) return w;
	for (NSWindow *o in [NSApp orderedWindows]) if ([o isVisible] && [o canBecomeKeyWindow]) return o;
	return nil;
}

/* What an item with action `a_action' and no target would go to: the first object along the
   front window's responder chain that implements it, then the window, its delegate, the
   application and its delegate (AppKit's order); nil when none does. */
static id sga_edit_target(SEL a_action)
{
	NSWindow *w = sga_front_window();
	id l_target = nil;
	for (NSResponder *r = [w firstResponder]; r && !l_target; r = [r nextResponder])
		if ([r respondsToSelector:a_action]) l_target = r;
	if (!l_target && w && [w respondsToSelector:a_action]) l_target = w;
	if (!l_target && [[w delegate] respondsToSelector:a_action]) l_target = [w delegate];
	if (!l_target && [NSApp respondsToSelector:a_action]) l_target = NSApp;
	if (!l_target && [[NSApp delegate] respondsToSelector:a_action]) l_target = [NSApp delegate];
	return l_target;
}

/* Would the Edit item for role `a_role' (10 undo .. 15 select all) be enabled now? As AppKit's
   menu validation decides it: the first object along the front window's responder chain (then
   the window's delegate, the application and its delegate) that implements the item's action
   is asked through validateMenuItem: or validateUserInterfaceItem:; no such object, disabled. */
int sga_test_edit_enabled(int a_role)
{
	SEL l_actions[6] = { @selector(undo:), @selector(redo:), @selector(cut:), @selector(copy:), @selector(paste:), @selector(selectAll:) };
	if (a_role < 10 || a_role > 15) return 0;
	SEL l_action = l_actions[a_role - 10];
	NSMenuItem *l_item = nil;
	NSMutableArray<NSMenu *> *l_menus = [NSMutableArray arrayWithObject:[NSApp mainMenu] ?: [[NSMenu alloc] init]];
	while (!l_item && [l_menus count] > 0) {
		NSMenu *m = l_menus[0];
		[l_menus removeObjectAtIndex:0];
		for (NSMenuItem *i in [m itemArray]) {
			if ([i action] == l_action && [[i representedObject] isEqual:@(a_role)]) { l_item = i; break; }
			if ([i submenu]) [l_menus addObject:[i submenu]];
		}
	}
	if (!l_item) l_item = [[NSMenuItem alloc] initWithTitle:@"" action:l_action keyEquivalent:@""];
	id l_target = sga_edit_target(l_action);
	if (!l_target) return 0;
	if ([l_target respondsToSelector:@selector(validateMenuItem:)]) return [l_target validateMenuItem:l_item] ? 1 : 0;
	if ([l_target respondsToSelector:@selector(validateUserInterfaceItem:)]) return [l_target validateUserInterfaceItem:l_item] ? 1 : 0;
	return 1;
}

/* Choose item `a_item' from widget `a_id's context menu, as a user would; 0 when that menu has
   no such item (or the widget has no context menu). */
int sga_test_context_menu(int a_id, int a_item)
{
	NSMenu *m = [(NSView *)sga_get(a_id) menu];
	NSMenuItem *i = m ? sga_find_numbered(m, a_item) : nil;
	if (!i) return 0;
	[[i menu] performActionForItemAtIndex:[[i menu] indexOfItem:i]];
	return 1;
}

void sga_test_request_close(int a_window) { [(NSWindow *)sga_get(a_window) performClose:nil]; }
void sga_test_auto_cancel_dialogs(int a_ms) { s_auto_cancel_ms = a_ms; }

/* A window's frame view as an image (device pixels), in its own appearance. */
static NSBitmapImageRep *sga_window_image(NSWindow *w)
{
	NSView *v = [[w contentView] superview];
	__block NSBitmapImageRep *r = nil;
	sga_colors_flush();
	[v layoutSubtreeIfNeeded];
	[v setNeedsDisplay:YES];
	[v displayIfNeeded];
	[[w effectiveAppearance] performAsCurrentDrawingAppearance:^{
		r = [v bitmapImageRepForCachingDisplayInRect:[v bounds]];
		[v cacheDisplayInRect:[v bounds] toBitmapImageRep:r];
	}];
	return r;
}

static NSPopover *s_help_popover;
static NSPopover *sga_shown_help_popover(void) { return [s_help_popover isShown] ? s_help_popover : nil; }

/* The window as the user sees it: a dialog shown as a sheet is rendered in its parent; the
   parent's attached sheet and a help popover over it are drawn where they show (each is a
   window of its own, outside the frame view's own drawing). */
int sga_snapshot(int a_window, const char *a_path)
{
	NSWindow *w = sga_get(a_window);
	if ([w isSheet] && [w sheetParent]) w = [w sheetParent];
	NSBitmapImageRep *l_base = sga_window_image(w);
	NSMutableArray<NSWindow *> *l_over = [NSMutableArray array];
	if ([w attachedSheet] && [[w attachedSheet] isVisible]) [l_over addObject:[w attachedSheet]];
	NSWindow *l_pop = [[[sga_shown_help_popover() contentViewController] view] window];
	if (l_pop && [l_pop isVisible]) [l_over addObject:l_pop];
	if (![l_over count]) return [[l_base representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:sga_string(a_path) atomically:YES] ? 1 : 0;
	NSRect b = [w frame];
	double k = (double)[l_base pixelsWide] / NSWidth(b);
	NSBitmapImageRep *r = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:[l_base pixelsWide] pixelsHigh:[l_base pixelsHigh]
		bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:r]];
	[l_base drawInRect:NSMakeRect(0, 0, [l_base pixelsWide], [l_base pixelsHigh])];
	for (NSWindow *o in l_over) {
		/* Its content view (a popover's vibrant backing and a sheet's are not captured) on a
		   card of the window background, outlined, where it shows. */
		NSView *c = o == l_pop ? [[sga_shown_help_popover() contentViewController] view] : [o contentView];
		NSRect f = [o convertRectToScreen:[c convertRect:[c bounds] toView:nil]];
		NSRect at = NSMakeRect((NSMinX(f) - NSMinX(b)) * k, (NSMinY(f) - NSMinY(b)) * k, NSWidth(f) * k, NSHeight(f) * k);
		__block NSBitmapImageRep *l_img = nil;
		[c layoutSubtreeIfNeeded];
		[[o effectiveAppearance] performAsCurrentDrawingAppearance:^{
			l_img = [c bitmapImageRepForCachingDisplayInRect:[c bounds]];
			[c cacheDisplayInRect:[c bounds] toBitmapImageRep:l_img];
			NSBezierPath *l_card = [NSBezierPath bezierPathWithRoundedRect:at xRadius:10 * k yRadius:10 * k];
			[[NSColor windowBackgroundColor] setFill];
			[l_card fill];
			[[NSColor separatorColor] setStroke];
			[l_card setLineWidth:k];
			[l_card stroke];
		}];
		[l_img drawInRect:at fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:NO hints:nil];
	}
	[NSGraphicsContext restoreGraphicsState];
	return [[r representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:sga_string(a_path) atomically:YES] ? 1 : 0;
}

/* What an assistive client reads, walked from the window: one "role: name" line per
   node, two spaces per depth; groups and scroll areas pass through without a line. */
/* An accessibility attribute, from the NSAccessibility protocol when the element has it,
   else through the older attribute API: some elements in the tree (a table's rows)
   answer only that. */
static id sga_ax(id a_element, SEL a_modern, NSString *a_attribute)
{
	if ([a_element respondsToSelector:a_modern]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
		return [a_element performSelector:a_modern];
#pragma clang diagnostic pop
	}
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	if ([a_element respondsToSelector:@selector(accessibilityAttributeValue:)]) return [a_element accessibilityAttributeValue:a_attribute];
#pragma clang diagnostic pop
	return nil;
}

/* `a_within': 1 inside a GUI_TABLE, whose parts read as GTK's column view does (probed on
   GTK 4.14): the table "tree-grid", its rows "row", cells "grid-cell", and the header's sort
   buttons "column-header"; 2 inside a GUI_TREE: the tree "tree", its rows "tree-item" (their
   cell left out, so each item's label sits under it); 0 elsewhere. */
/* A switch is a button with the switch subrole on AppKit. */
static BOOL sga_is_switch(id a_element)
{
	id l_sub = sga_ax(a_element, @selector(accessibilitySubrole), NSAccessibilitySubroleAttribute);
	return [l_sub isKindOfClass:[NSString class]] && [l_sub isEqualToString:NSAccessibilitySwitchSubrole];
}

static void sga_describe(id a_element, int a_depth, int a_within, NSMutableString *a_out)
{
	/* A drawn view (1i): a group named by its label, with the hosted window's own tree under it
	   (its first line, the hosted window itself, left out). */
	if ([a_element isKindOfClass:[SGADrawn class]]) {
		SGADrawn *d = a_element;
		for (int i = 0; i < a_depth; i++) [a_out appendString:@"  "];
		[a_out appendFormat:@"group: %@\n", [d accessibilityLabel] ?: @""];
		NSArray<NSString *> *l_lines = [d->description ?: @"" componentsSeparatedByString:@"\n"];
		for (NSUInteger k = 1; k < [l_lines count]; k++) {
			if (![l_lines[k] length]) continue;
			for (int i = 0; i <= a_depth; i++) [a_out appendString:@"  "];
			[a_out appendFormat:@"%@\n", [l_lines[k] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" "]] ];
		}
		return;
	}
	id l_role_value = sga_ax(a_element, @selector(accessibilityRole), NSAccessibilityRoleAttribute);
	NSString *l_role = [l_role_value isKindOfClass:[NSString class]] ? l_role_value : nil;
	NSString *l_name = sga_role_name(l_role);
	/* A control may answer through its cell: the view says what it is. */
	id l_view = [a_element isKindOfClass:[NSCell class]] ? [(NSCell *)a_element controlView] : a_element;
	BOOL l_tree_table = [a_element isKindOfClass:[SGATree class]] && ((SGATree *)a_element)->is_table;
	int l_within = [a_element isKindOfClass:[SGAGridTable class]] || l_tree_table ? 1 : [a_element isKindOfClass:[SGATree class]] ? 2
		: [l_view isKindOfClass:[SGAPathControl class]] ? 3   /* 3: a path control's parts are links */
		: [l_view isKindOfClass:[SGATokenField class]] ? 4 : a_within;   /* 4: a token field's tokens are buttons */
	if ([a_element isKindOfClass:[SGAGridTable class]] || l_tree_table) l_name = @"tree-grid";
	else if ([a_element isKindOfClass:[SGATree class]]) l_name = @"tree";
	else if ([a_element isKindOfClass:[SGASpin class]]) l_name = @"spin-button";
	else if ([l_view isKindOfClass:[SGAStatus class]]) l_name = @"status";
	else if ([l_view isKindOfClass:[SGADatePicker class]])
		l_name = [(NSDatePicker *)l_view datePickerStyle] == NSDatePickerStyleClockAndCalendar ? @"grid" : @"spin-button";
	else if ([l_view isKindOfClass:[SGASearchField class]]) l_name = @"search-box";
	else if ([l_view isKindOfClass:[SGAPathControl class]]) l_name = @"navigation";
	else if ([l_view isKindOfClass:[NSComboButton class]]) l_name = @"button";
	else if (a_within == 3 && [l_role isEqualToString:NSAccessibilityStaticTextRole]) l_name = @"link";
	else if (a_within == 4 && ![l_view isKindOfClass:[SGATokenField class]]) l_name = @"button";
	else if (a_within == 1 && [l_role isEqualToString:@"AXMenuButton"]) l_name = @"generic";
	else if ([l_view isKindOfClass:[NSBox class]] && [(NSBox *)l_view boxType] != NSBoxSeparator) l_name = @"group";
	else if ([l_role isEqualToString:NSAccessibilityScrollBarRole]) return;   /* scroll bars are the scroll area's own */
	else if (sga_is_switch(a_element)) l_name = @"switch";
	else if (a_within == 2) {
		if ([l_role isEqualToString:NSAccessibilityRowRole]) l_name = @"tree-item";
		else if ([l_role isEqualToString:NSAccessibilityCellRole]) l_name = @"generic";
	}
	else if (a_within == 1) {
		id l_sub = sga_ax(a_element, @selector(accessibilitySubrole), NSAccessibilitySubroleAttribute);
		if ([l_role isEqualToString:NSAccessibilityRowRole]) l_name = @"row";
		else if ([l_role isEqualToString:NSAccessibilityCellRole]) l_name = @"grid-cell";
		else if ([l_sub isKindOfClass:[NSString class]] && [l_sub isEqualToString:@"AXSortButton"]) l_name = @"column-header";
	}
	/* A tab is a radio button with the tab-button subrole on AppKit. */
	if ([l_role isEqualToString:NSAccessibilityRadioButtonRole]) {
		id l_sub = sga_ax(a_element, @selector(accessibilitySubrole), NSAccessibilitySubroleAttribute);
		if ([l_sub isKindOfClass:[NSString class]] && [l_sub isEqualToString:@"AXTabButton"]) l_name = @"tab";
	}
	int l_next = a_depth;
	if ([l_role length] && ![l_name isEqualToString:@"generic"]) {
		id l_label = sga_ax(a_element, @selector(accessibilityLabel), NSAccessibilityDescriptionAttribute);
		id l_title = sga_ax(a_element, @selector(accessibilityTitle), NSAccessibilityTitleAttribute);
		id l_value = sga_ax(a_element, @selector(accessibilityValue), NSAccessibilityValueAttribute);
		if ([l_view isKindOfClass:[SGADatePicker class]]) {   /* the value, as ISO 8601 */
			SGADatePicker *l_picker = l_view;
			NSInteger v = sga_date_value(l_picker);
			l_value = l_picker->is_time ? [NSString stringWithFormat:@"%02ld:%02ld", (long)(v / 60), (long)(v % 60)]
				: [NSString stringWithFormat:@"%04ld-%02ld-%02ld", (long)(v / 10000), (long)(v / 100 % 100), (long)(v % 100)];
		}
		if ([l_view isKindOfClass:[NSBox class]]) l_title = [(NSBox *)l_view title];
		if ([l_view isKindOfClass:[SGATokenField class]]) l_value = [[(SGATokenField *)l_view tokens] componentsJoinedByString:@", "];
		NSString *l_text = ([l_label isKindOfClass:[NSString class]] && [l_label length]) ? l_label
			: ([l_title isKindOfClass:[NSString class]] && [l_title length]) ? l_title
			: ([l_value isKindOfClass:[NSString class]] ? l_value : @"");
		for (int i = 0; i < a_depth; i++) [a_out appendString:@"  "];
		[a_out appendFormat:@"%@: %@\n", l_name, l_text];
		l_next = a_depth + 1;
	}
	id l_children = [a_element isKindOfClass:[SGASpin class]] || [l_view isKindOfClass:[SGADatePicker class]]   /* one spin button or grid */
		|| [l_view isKindOfClass:[NSComboButton class]] ? nil   /* one split button */
		: sga_ax(a_element, @selector(accessibilityChildren), NSAccessibilityChildrenAttribute);
	id l_box_title = [l_view isKindOfClass:[NSBox class]] ? [(NSBox *)l_view titleCell] : nil;   /* already the group's name */
	if (a_depth < 16 && [l_children isKindOfClass:[NSArray class]]) for (id c in l_children) if (c != l_box_title) sga_describe(c, l_next, l_within, a_out);
}

const char *sga_describe_accessibility(int a_window)
{
	NSMutableString *l_text = [NSMutableString stringWithString:@"application: "];
	NSWindow *w = sga_get(a_window);
	[l_text appendFormat:@"%@\n", [w title]];
	/* The toolbar (1g) is in the title bar, beside the content view rather than in it. */
	if ([[w toolbar] isVisible]) for (id c in [w accessibilityChildren]) {
		id l_role = sga_ax(c, @selector(accessibilityRole), NSAccessibilityRoleAttribute);
		if ([l_role isKindOfClass:[NSString class]] && [l_role isEqualToString:NSAccessibilityToolbarRole]) sga_describe(c, 1, 0, l_text);
	}
	for (id c in [[w contentView] accessibilityChildren]) sga_describe(c, 1, 0, l_text);
	return sga_return(Kind_tree, l_text);
}

/* ------------------------------------------------------------- 1r-a: the dock */

/* A center widget with tool panels docked on its four sides. The dock lays itself out: the
   top and bottom sides span the whole width, the left and right sit between them beside the
   center. Each side shows its visible panels stacked along its long axis (down on the left
   and right, across on the top and bottom), each under a title, or as tabs, one at a time.
   A side with no visible panel takes no room. The edge between a side and the center drags
   to resize it, the center keeping at least 120 points each way; a double click on the edge,
   or the side's chevron, collapses it to a strip naming its panels, and a press on a name
   expands it showing that panel. The user's acts are events: 35 an edge dragged (a side,
   b size; a queued 35 for the same side is replaced while dragging), 36 a side collapsed or
   expanded (b = 1 collapsed), 37 a tab chosen (b = the panel's index). Code changes nothing
   to the queue. Indices are the shared class's: the panel's place in `panels', from 1. */

#define SGA_DOCK_STRIP 22
#define SGA_DOCK_EDGE 6      /* the edge's grab, centered on the 1-point line */
#define SGA_DOCK_MIN_CENTER 120

/* Replace the last queued event of `a_type' for `a_id' whose `a' is `a_a', else add one. */
static void sga_push_replacing(int a_type, int a_id, int a_a, int a_b)
{
	for (int i = s_head; i != s_tail; i = (i + 1) % SGA_QUEUE)
		if (s_events[i].type == a_type && s_events[i].id == a_id && s_events[i].a == a_a) { s_events[i].b = a_b; return; }
	sga_push(a_type, a_id, a_a, a_b, 0);
}

@class SGADock;

@interface SGADockPanel : NSObject
{
@public
	int widget;          /* the panel's content widget */
	int side;            /* 1 left, 2 right, 3 top, 4 bottom */
	BOOL shown;
	NSString *key, *title;
	NSView *box;         /* a title over the content, when stacked */
	NSTextField *header;
	NSLayoutConstraint *under_header, *at_top;   /* the content's top: under the title, or at the box's top (tabbed) */
	BOOL floating;       /* 1r-b: in a window of its own, still keeping its side and place */
	NSPanel *float_win;
	NSRect float_frame;  /* logical units, from the dock window's top-left; empty until first floated */
	NSString *short_title, *about, *tab_tip, *pill;   /* 1r-c: empty when not set */
	int header_id;       /* the title bar's handle, for its pill */
}
@end
@implementation SGADockPanel
/* What its tab and its strip name show, and their tooltip. */
- (NSString *)tabText { return [short_title length] ? short_title : title; }
- (NSString *)tabTip { return [tab_tip length] ? tab_tip : (about ?: @""); }
@end

static void sga_dock_press_name(SGADock *d, SGADockPanel *p);
static void sga_dock_place_tab_pill(SGADock *d, int a_side);
static void sga_dock_slide_out(SGADock *d, SGADockPanel *p);
static void sga_dock_slide_back_later(SGADock *d);
static void sga_dock_slide_back(SGADock *d);
static void sga_dock_toggle_center_as_user(SGADock *d);
static void sga_dock_float_as_user(SGADock *d, SGADockPanel *p, BOOL a_on);
static void sga_dock_track_panel(SGADock *d, SGADockPanel *p, NSEvent *e);
void sga_dock_set_auto_hide(int a_dock, int a_side, int a_on);

@interface SGADockStrip : NSView
{
@public
	__weak SGADock *dock;
	int side;
	NSMutableArray<NSValue *> *rects;   /* each name's rectangle, in the panels' order on the side */
}
@end

@interface SGADock : NSView <NSTabViewDelegate, NSWindowDelegate>
{
@public
	NSView *center;
	NSMutableArray<SGADockPanel *> *panels;          /* the shared class's order */
	NSMutableArray<SGADockPanel *> *order[5];        /* each side's order */
	NSView *side_view[5];                            /* what the side shows: a stack or a tab view */
	NSTabView *tabs[5];
	NSStackView *stack[5];
	SGADockStrip *strip[5];
	NSButton *chevron[5];
	BOOL tabbed[5], collapsed[5];
	int size[5];
	int dragging;          /* the side whose edge is being dragged, 0 none */
	/* 1r-b */
	BOOL auto_hide[5];     /* the side stands as its strip; a panel slides out over the center */
	BOOL center_max;       /* every side folded away, the center takes the dock */
	NSButton *pin[5], *strip_pin[5];
	SGADockPanel *slid;    /* the panel slid out of an auto-hide strip, nil none */
	NSView *slide_view;    /* holds it, over the center */
	NSTimer *slide_timer;  /* the rest before sliding out, or the wait before sliding back */
	SGADockPanel *resting; /* the name the pointer rests on */
	NSView *drop_mark;     /* where a dragged panel would land */
}
- (void)rebuild:(int)a_side;
@end

static BOOL sga_dock_long_vertical(int a_side) { return a_side <= 2; }

static NSArray<SGADockPanel *> *sga_dock_visible(SGADock *d, int a_side)
{
	NSMutableArray *r = [NSMutableArray array];
	for (SGADockPanel *p in d->order[a_side]) if (p->shown && !p->floating) [r addObject:p];
	return r;
}

/* The room a side takes across: none when it shows nothing, the strip when collapsed. */
static CGFloat sga_dock_depth(SGADock *d, int a_side)
{
	if (d->center_max || ![sga_dock_visible(d, a_side) count]) return 0;
	return d->collapsed[a_side] || d->auto_hide[a_side] ? SGA_DOCK_STRIP : d->size[a_side];
}

@implementation SGADockStrip
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)r
{
	(void)r;
	[[NSColor windowBackgroundColor] setFill];
	NSRectFill([self bounds]);
	NSDictionary *l_att = @{NSFontAttributeName: [NSFont systemFontOfSize:11], NSForegroundColorAttributeName: [NSColor secondaryLabelColor]};
	rects = [NSMutableArray array];
	CGFloat at = 6;
	BOOL l_down = sga_dock_long_vertical(side);
	[self removeAllToolTips];
	for (SGADockPanel *p in sga_dock_visible(dock, side)) {
		NSString *l_name = [p tabText];
		NSSize s = [l_name sizeWithAttributes:l_att];
		NSRect l_rect = l_down ? NSMakeRect(0, at, SGA_DOCK_STRIP, s.width + 12) : NSMakeRect(at, 0, s.width + 12, SGA_DOCK_STRIP);
		[rects addObject:[NSValue valueWithRect:l_rect]];
		if (l_down) {
			NSGraphicsContext *g = [NSGraphicsContext currentContext];
			[g saveGraphicsState];
			NSAffineTransform *t = [NSAffineTransform transform];
			[t translateXBy:NSMidX(l_rect) - s.height / 2 yBy:NSMaxY(l_rect) - 6];
			[t rotateByDegrees:-90];
			[t concat];
			[l_name drawAtPoint:NSZeroPoint withAttributes:l_att];
			[g restoreGraphicsState];
		} else
			[l_name drawAtPoint:NSMakePoint(NSMinX(l_rect) + 6, (SGA_DOCK_STRIP - s.height) / 2) withAttributes:l_att];
		if ([[p tabTip] length]) [self addToolTipRect:l_rect owner:[p tabTip] userData:NULL];
		at += (l_down ? l_rect.size.height : l_rect.size.width) + 4;
	}
}
- (SGADockPanel *)nameAt:(NSEvent *)e
{
	NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
	NSArray<SGADockPanel *> *l_shown = sga_dock_visible(dock, side);
	for (NSUInteger i = 0; i < [rects count] && i < [l_shown count]; i++)
		if (NSPointInRect(p, [rects[i] rectValue])) return l_shown[i];
	return nil;
}
- (void)mouseDown:(NSEvent *)e
{
	SGADockPanel *p = [self nameAt:e];
	if (!p) return;
	if (dock->auto_hide[side]) sga_dock_slide_out(dock, p); else sga_dock_press_name(dock, p);
}
/* 1r-b: resting on a name for 0.4 s slides it out; leaving lets it slide back. */
- (void)updateTrackingAreas
{
	[super updateTrackingAreas];
	for (NSTrackingArea *a in [[self trackingAreas] copy]) [self removeTrackingArea:a];
	[self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
		options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseMoved:(NSEvent *)e
{
	if (!dock->auto_hide[side]) return;
	SGADockPanel *p = [self nameAt:e];
	if (p == dock->resting) return;
	dock->resting = p;
	[dock->slide_timer invalidate];
	dock->slide_timer = nil;
	if (p && p != dock->slid) {
		__weak SGADock *d = dock;
		dock->slide_timer = [NSTimer scheduledTimerWithTimeInterval:0.4 repeats:NO block:^(NSTimer *t) {
			(void)t;
			SGADock *l_d = d;
			if (l_d && l_d->resting) sga_dock_slide_out(l_d, l_d->resting);
		}];
	}
}
- (void)mouseExited:(NSEvent *)e { (void)e; dock->resting = nil; sga_dock_slide_back_later(dock); }
- (NSString *)accessibilityRole { return NSAccessibilityGroupRole; }
- (NSString *)accessibilityLabel { return @"Collapsed panels"; }
@end

static void sga_dock_select_silently(SGADock *d, SGADockPanel *p);

/* As the user: expand the panel's side showing it (36), and choose its tab (37) when the side
   is tabbed and it was not the one showing. */
static void sga_dock_press_name(SGADock *d, SGADockPanel *p)
{
	int l_side = p->side;
	if (d->collapsed[l_side]) {
		d->collapsed[l_side] = NO;
		[d rebuild:l_side];
		sga_push(36, sga_id_of(d), l_side, 0, 0);
	}
	if (d->tabbed[l_side] && [[d->tabs[l_side] selectedTabViewItem] identifier] != p) {
		sga_dock_select_silently(d, p);
		sga_push(37, sga_id_of(d), l_side, (int)[d->panels indexOfObjectIdenticalTo:p] + 1, 0);
	}
	sga_wake();
}

static void sga_dock_select_silently(SGADock *d, SGADockPanel *p)
{
	NSTabView *t = d->tabs[p->side];
	NSInteger i = [t indexOfTabViewItemWithIdentifier:p];
	if (i == NSNotFound) return;
	s_suppress++;
	[t selectTabViewItemAtIndex:i];
	s_suppress--;
}

@implementation SGADock
- (BOOL)isFlipped { return YES; }
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, NSViewNoIntrinsicMetric); }

/* The rectangle each side, the center and each edge's grab take now. */
- (NSRect)rectOf:(int)a_side
{
	NSRect b = [self bounds];
	CGFloat t = sga_dock_depth(self, 3), bo = sga_dock_depth(self, 4), l = sga_dock_depth(self, 1), r = sga_dock_depth(self, 2);
	CGFloat tl = t > 0 ? 1 : 0, bl = bo > 0 ? 1 : 0, ll = l > 0 ? 1 : 0, rl = r > 0 ? 1 : 0;
	/* The center keeps 120 points each way: sides give way in proportion (their sizes kept). */
	CGFloat l_over = (t + tl + bo + bl) - (b.size.height - SGA_DOCK_MIN_CENTER);
	if (l_over > 0 && t + bo > 0) { CGFloat k = fmax(0, 1 - l_over / (t + bo)); t = floor(t * k); bo = floor(bo * k); }
	l_over = (l + ll + r + rl) - (b.size.width - SGA_DOCK_MIN_CENTER);
	if (l_over > 0 && l + r > 0) { CGFloat k = fmax(0, 1 - l_over / (l + r)); l = floor(l * k); r = floor(r * k); }
	CGFloat l_mid_top = t + tl, l_mid_h = fmax(0, b.size.height - t - tl - bo - bl);
	switch (a_side) {
		case 3: return NSMakeRect(0, 0, b.size.width, t);
		case 4: return NSMakeRect(0, b.size.height - bo, b.size.width, bo);
		case 1: return NSMakeRect(0, l_mid_top, l, l_mid_h);
		case 2: return NSMakeRect(b.size.width - r, l_mid_top, r, l_mid_h);
		default: return NSMakeRect(l + ll, l_mid_top, fmax(0, b.size.width - l - ll - r - rl), l_mid_h);
	}
}
- (NSRect)edgeOf:(int)a_side
{
	if (!sga_dock_depth(self, a_side) || collapsed[a_side] || auto_hide[a_side]) return NSZeroRect;
	NSRect s = [self rectOf:a_side];
	CGFloat h = SGA_DOCK_EDGE / 2.0;
	switch (a_side) {
		case 1: return NSMakeRect(NSMaxX(s) - h + 0.5, NSMinY(s), SGA_DOCK_EDGE, s.size.height);
		case 2: return NSMakeRect(NSMinX(s) - h - 0.5, NSMinY(s), SGA_DOCK_EDGE, s.size.height);
		case 3: return NSMakeRect(0, NSMaxY(s) - h + 0.5, s.size.width, SGA_DOCK_EDGE);
		default: return NSMakeRect(0, NSMinY(s) - h - 0.5, s.size.width, SGA_DOCK_EDGE);
	}
}
- (void)layout
{
	[super layout];
	[center setFrame:[self rectOf:0]];
	for (int s = 1; s <= 4; s++) {
		NSRect f = [self rectOf:s];
		BOOL l_any = f.size.width > 0 && f.size.height > 0, l_folded = collapsed[s] || auto_hide[s];
		[side_view[s] setHidden:!l_any || l_folded];
		[strip[s] setHidden:!l_any || !l_folded];
		[chevron[s] setHidden:!l_any || l_folded];
		[pin[s] setHidden:!l_any || l_folded];
		[strip_pin[s] setHidden:!l_any || !auto_hide[s]];
		[side_view[s] setFrame:f];
		[strip[s] setFrame:f];
		[strip[s] setNeedsDisplay:YES];
		/* the chevron and the pin at the side's top-trailing corner, clear of the first title */
		NSRect c = NSMakeRect(NSMaxX(f) - 18, NSMinY(f) + 2, 16, 16);
		[chevron[s] setFrame:c];
		[pin[s] setFrame:NSOffsetRect(c, -18, 0)];
		/* the strip's pin at its far end */
		[strip_pin[s] setFrame:sga_dock_long_vertical(s) ? NSMakeRect(NSMinX(f) + 3, NSMaxY(f) - 19, 16, 16) : NSMakeRect(NSMaxX(f) - 19, NSMinY(f) + 3, 16, 16)];
	}
	/* A slid-out panel lies over the center at its side's size, without moving it. */
	[slide_view setHidden:slid == nil];
	if (slid) {
		NSRect c = [self rectOf:0];
		int k = slid->side, l_depth = (int)fmin(size[k], (k <= 2 ? c.size.width : c.size.height));
		NSRect r = k == 1 ? NSMakeRect(NSMinX(c), NSMinY(c), l_depth, c.size.height)
			: k == 2 ? NSMakeRect(NSMaxX(c) - l_depth, NSMinY(c), l_depth, c.size.height)
			: k == 3 ? NSMakeRect(NSMinX(c), NSMinY(c), c.size.width, l_depth)
			: NSMakeRect(NSMinX(c), NSMaxY(c) - l_depth, c.size.width, l_depth);
		[slide_view setFrame:r];
		[slid->box setFrame:[slide_view bounds]];
	}
	[[self window] invalidateCursorRectsForView:self];
	[self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)r
{
	(void)r;
	[[NSColor separatorColor] setFill];
	for (int s = 1; s <= 4; s++) {
		if (!sga_dock_depth(self, s)) continue;
		NSRect f = [self rectOf:s];
		switch (s) {
			case 1: NSRectFill(NSMakeRect(NSMaxX(f), NSMinY(f), 1, f.size.height)); break;
			case 2: NSRectFill(NSMakeRect(NSMinX(f) - 1, NSMinY(f), 1, f.size.height)); break;
			case 3: NSRectFill(NSMakeRect(0, NSMaxY(f), f.size.width, 1)); break;
			default: NSRectFill(NSMakeRect(0, NSMinY(f) - 1, f.size.width, 1)); break;
		}
	}
}
- (void)resetCursorRects
{
	for (int s = 1; s <= 4; s++) {
		NSRect e = [self edgeOf:s];
		if (!NSIsEmptyRect(e)) [self addCursorRect:e cursor:s <= 2 ? [NSCursor resizeLeftRightCursor] : [NSCursor resizeUpDownCursor]];
	}
}
/* Edges take the press, and so does the center's frame (a 3-point band inside it where no
   side's edge is); everything else belongs to the views under it. */
- (BOOL)onCenterFrame:(NSPoint)a_local
{
	NSRect c = [self rectOf:0];
	return NSPointInRect(a_local, c) && !NSPointInRect(a_local, NSInsetRect(c, 3, 3));
}
- (NSView *)hitTest:(NSPoint)p
{
	NSPoint l_local = [self convertPoint:p fromView:[self superview]];
	for (int s = 1; s <= 4; s++) if (NSPointInRect(l_local, [self edgeOf:s])) return self;
	if ([self onCenterFrame:l_local]) return self;
	return [super hitTest:p];
}
/* The panel whose title (stacked) is under `a_local', or nil. */
- (SGADockPanel *)headerAt:(NSPoint)a_local
{
	for (SGADockPanel *p in panels)
		if (p->shown && !p->floating && ![p->header isHidden] && [p->header window] == [self window]) {
			NSRect r = [self convertRect:NSInsetRect([p->header bounds], -4, -3) fromView:p->header];
			if (NSPointInRect(a_local, r)) return p;
		}
	return nil;
}
- (void)togglePin:(NSButton *)b
{
	int k = (int)[b tag];
	BOOL l_on = !auto_hide[k];
	sga_dock_set_auto_hide((int)sga_id_of(self), k, l_on);
	sga_push(39, sga_id_of(self), k, l_on ? 1 : 0, 0);
	sga_wake();
}
/* The size a side gets for an edge at `a_at' (dock coordinates), within the center's minimum. */
- (int)sizeFor:(int)a_side at:(NSPoint)a_at
{
	NSRect b = [self bounds];
	CGFloat v;
	switch (a_side) {
		case 1: v = a_at.x; break;
		case 2: v = b.size.width - a_at.x; break;
		case 3: v = a_at.y; break;
		default: v = b.size.height - a_at.y; break;
	}
	CGFloat l_room = a_side <= 2 ? b.size.width - sga_dock_depth(self, a_side == 1 ? 2 : 1) - 2 : b.size.height - sga_dock_depth(self, a_side == 3 ? 4 : 3) - 2;
	return (int)lround(fmax(SGA_DOCK_STRIP + 8, fmin(v, l_room - SGA_DOCK_MIN_CENTER)));
}
- (void)userSized:(int)a_side to:(int)a_size
{
	if (size[a_side] == a_size) return;
	size[a_side] = a_size;
	[self setNeedsLayout:YES];
	sga_push_replacing(35, sga_id_of(self), a_side, a_size);
	sga_wake();
}
- (void)mouseDown:(NSEvent *)e
{
	NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
	dragging = 0;
	for (int s = 1; s <= 4; s++) if (NSPointInRect(p, [self edgeOf:s])) dragging = s;
	if (!dragging && [self onCenterFrame:p]) {
		if ([e clickCount] == 2) sga_dock_toggle_center_as_user(self);
		return;
	}
	if (!dragging) {
		/* a panel's title: a double click floats it, a drag moves it */
		SGADockPanel *h = [self headerAt:p];
		if (h && [e clickCount] == 2) sga_dock_float_as_user(self, h, YES);
		else if (h) sga_dock_track_panel(self, h, e);
		return;
	}
	if ([e clickCount] == 2) {   /* a double click on the edge collapses the side */
		collapsed[dragging] = YES;
		[self setNeedsLayout:YES];
		sga_push(36, sga_id_of(self), dragging, 1, 0);
		sga_wake();
		dragging = 0;
	}
}
- (void)mouseDragged:(NSEvent *)e
{
	if (!dragging) return;
	[self userSized:dragging to:[self sizeFor:dragging at:[self convertPoint:[e locationInWindow] fromView:nil]]];
	[self layoutSubtreeIfNeeded];
}
- (void)mouseUp:(NSEvent *)e { (void)e; dragging = 0; }
- (void)chevronPressed:(NSButton *)b
{
	int s = (int)[b tag];
	collapsed[s] = YES;
	[self setNeedsLayout:YES];
	sga_push(36, sga_id_of(self), s, 1, 0);
	sga_wake();
}
/* A tab chosen by the user: 37 with the panel's index. */
- (void)tabView:(NSTabView *)t didSelectTabViewItem:(NSTabViewItem *)i
{
	(void)t;
	SGADockPanel *p = [i identifier];
	if (p) sga_dock_place_tab_pill(self, p->side);
	if (s_suppress || !p) return;
	sga_push(37, sga_id_of(self), p->side, (int)[panels indexOfObjectIdenticalTo:p] + 1, 0);
	sga_wake();
}
/* Put side `a_side''s visible panels in its stack or its tabs, in its order. */
- (void)rebuild:(int)a_side
{
	NSArray<SGADockPanel *> *l_shown = sga_dock_visible(self, a_side);
	SGADockPanel *l_active = tabbed[a_side] ? [[tabs[a_side] selectedTabViewItem] identifier] : nil;
	for (SGADockPanel *p in order[a_side]) [p->box removeFromSuperview];
	s_suppress++;
	while ([tabs[a_side] numberOfTabViewItems]) [tabs[a_side] removeTabViewItem:[tabs[a_side] tabViewItemAtIndex:0]];
	for (NSView *v in [[stack[a_side] arrangedSubviews] copy]) [stack[a_side] removeArrangedSubview:v];
	for (SGADockPanel *p in l_shown) {
		[p->header setHidden:tabbed[a_side]];
		/* the tab names a tabbed panel: its content takes the title's room */
		[p->under_header setActive:!tabbed[a_side]];
		[p->at_top setActive:tabbed[a_side]];
		if (tabbed[a_side]) {
			NSTabViewItem *i = [[NSTabViewItem alloc] initWithIdentifier:p];
			[i setLabel:[p tabText]];
			[i setToolTip:[p tabTip]];
			[i setView:p->box];
			[tabs[a_side] addTabViewItem:i];
		} else {
			[stack[a_side] addArrangedSubview:p->box];
			/* across the whole side: the stack itself only places along its axis */
			[(sga_dock_long_vertical(a_side) ? [p->box.widthAnchor constraintEqualToAnchor:stack[a_side].widthAnchor]
				: [p->box.heightAnchor constraintEqualToAnchor:stack[a_side].heightAnchor]) setActive:YES];
		}
	}
	if (l_active && [l_shown containsObject:l_active]) [tabs[a_side] selectTabViewItemWithIdentifier:l_active];
	s_suppress--;
	side_view[a_side] = tabbed[a_side] ? tabs[a_side] : stack[a_side];
	sga_dock_place_tab_pill(self, a_side);
	[tabs[a_side] setHidden:!tabbed[a_side]];
	[stack[a_side] setHidden:tabbed[a_side]];
	[strip[a_side] setNeedsDisplay:YES];
	[self setNeedsLayout:YES];
}
@end


/* ------------------------------------------------------------- 1r-b: the dock, further */

/* A side's tabs: a double click on a tab floats its panel; a drag on a tab moves it (the
   tab view tracks presses itself, so the press is looked ahead of, as in #72). */
@interface SGADockTabs : NSTabView
{
@public
	__weak SGADock *dock;
}
@end
@implementation SGADockTabs
- (void)mouseDown:(NSEvent *)e
{
	NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
	NSTabViewItem *i = [self tabViewItemAtPoint:p];
	SGADockPanel *l_panel = [i identifier];
	if (!l_panel || !dock) { [super mouseDown:e]; return; }
	if ([e clickCount] == 2) { sga_dock_float_as_user(dock, l_panel, YES); return; }
	for (;;) {
		NSEvent *n = [NSApp nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp
			untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:NO];
		if (!n || [n type] == NSEventTypeLeftMouseUp) break;
		[NSApp nextEventMatchingMask:NSEventMaskLeftMouseDragged untilDate:[NSDate distantPast] inMode:NSEventTrackingRunLoopMode dequeue:YES];
		NSPoint q = [n locationInWindow], o = [e locationInWindow];
		if (hypot(q.x - o.x, q.y - o.y) > 4) { sga_dock_track_panel(dock, l_panel, n); return; }
	}
	[super mouseDown:e];
}
@end

/* What lies over the center while a panel is slid out: leaving it lets it slide back. */
@interface SGADockSlide : NSView
{
@public
	__weak SGADock *dock;
}
@end
@implementation SGADockSlide
- (void)updateTrackingAreas
{
	[super updateTrackingAreas];
	for (NSTrackingArea *a in [[self trackingAreas] copy]) [self removeTrackingArea:a];
	[self addTrackingArea:[[NSTrackingArea alloc] initWithRect:NSZeroRect
		options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect owner:self userInfo:nil]];
}
- (void)mouseEntered:(NSEvent *)e { (void)e; [dock->slide_timer invalidate]; dock->slide_timer = nil; }
- (void)mouseExited:(NSEvent *)e { (void)e; sga_dock_slide_back_later(dock); }
- (void)drawRect:(NSRect)r { (void)r; [[NSColor windowBackgroundColor] setFill]; NSRectFill([self bounds]); }
@end

static int sga_dock_index_of(SGADock *d, SGADockPanel *p) { return (int)[d->panels indexOfObjectIdenticalTo:p] + 1; }

/* Slide `p' out over the center (its side in auto-hide), or back. */
static void sga_dock_slide_out(SGADock *d, SGADockPanel *p)
{
	[d->slide_timer invalidate];
	d->slide_timer = nil;
	if (d->slid == p) return;
	if (d->slid) { SGADockPanel *l_old = d->slid; d->slid = nil; [l_old->box removeFromSuperview]; [d rebuild:l_old->side]; }
	if (!p || !d->auto_hide[p->side] || !p->shown || p->floating) { [d setNeedsLayout:YES]; return; }
	[p->box removeFromSuperview];
	[p->header setHidden:NO];
	[p->under_header setActive:YES];
	[p->at_top setActive:NO];
	[p->box setTranslatesAutoresizingMaskIntoConstraints:YES];
	[d->slide_view addSubview:p->box];
	d->slid = p;
	[d addSubview:d->slide_view positioned:NSWindowAbove relativeTo:nil];
	[d setNeedsLayout:YES];
	[d layoutSubtreeIfNeeded];
}

static void sga_dock_slide_back(SGADock *d)
{
	if (!d->slid) return;
	SGADockPanel *p = d->slid;
	d->slid = nil;
	[p->box removeFromSuperview];
	[p->box setTranslatesAutoresizingMaskIntoConstraints:NO];
	[d rebuild:p->side];
}

/* After 0.5 s, unless the pointer came back or the focus is inside the slid-out panel. */
static void sga_dock_slide_back_later(SGADock *d)
{
	if (!d || !d->slid) return;
	[d->slide_timer invalidate];
	__weak SGADock *w = d;
	d->slide_timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer *t) {
		(void)t;
		SGADock *l_d = w;
		if (!l_d || !l_d->slid) return;
		id f = [[l_d window] firstResponder];
		if ([f isKindOfClass:[NSView class]] && [(NSView *)f isDescendantOf:l_d->slid->box]) return;
		NSPoint m = [l_d->slide_view convertPoint:[[l_d window] mouseLocationOutsideOfEventStream] fromView:nil];
		if (NSPointInRect(m, [l_d->slide_view bounds])) return;
		sga_dock_slide_back(l_d);
	}];
}

/* The dock window's top-left, in screen points, and back. */
static NSRect sga_dock_screen_of(SGADock *d, NSRect a_frame)
{
	NSRect w = [[d window] frame];
	return NSMakeRect(NSMinX(w) + a_frame.origin.x, NSMaxY(w) - a_frame.origin.y - a_frame.size.height, a_frame.size.width, a_frame.size.height);
}
static NSRect sga_dock_relative_of(SGADock *d, NSRect a_screen)
{
	NSRect w = [[d window] frame];
	return NSMakeRect(NSMinX(a_screen) - NSMinX(w), NSMaxY(w) - NSMaxY(a_screen), a_screen.size.width, a_screen.size.height);
}

/* Float `p' in a window of its own (titled with its title, over the dock's window), or dock it
   again where it was. Silent. */
static void sga_dock_float_panel(SGADock *d, SGADockPanel *p, BOOL a_on)
{
	if (!p || p->floating == a_on) return;
	if (a_on) {
		if (d->slid == p) sga_dock_slide_back(d);
		NSSize l_docked = [p->box frame].size;
		if (l_docked.width < 80 || l_docked.height < 60) l_docked = NSMakeSize(fmax(d->size[p->side], 200), 300);
		p->floating = YES;
		[d rebuild:p->side];
		[p->box removeFromSuperview];
		if (NSIsEmptyRect(p->float_frame)) {   /* the first float: over the middle of the dock's window */
			NSRect w = [[d window] frame];
			p->float_frame = NSMakeRect((w.size.width - l_docked.width) / 2, (w.size.height - l_docked.height) / 2, l_docked.width, l_docked.height);
		}
		NSUInteger l_style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable | NSWindowStyleMaskUtilityWindow;
		NSPanel *w = [[NSPanel alloc] initWithContentRect:[NSPanel contentRectForFrameRect:sga_dock_screen_of(d, p->float_frame) styleMask:l_style]
			styleMask:l_style backing:NSBackingStoreBuffered defer:NO];
		[w setReleasedWhenClosed:NO];
		[w setFloatingPanel:NO];
		[w setHidesOnDeactivate:NO];
		[w setTitle:p->title];
		[w setFrame:sga_dock_screen_of(d, p->float_frame) display:NO];
		[p->header setHidden:YES];
		[p->under_header setActive:NO];
		[p->at_top setActive:YES];
		[p->box setTranslatesAutoresizingMaskIntoConstraints:YES];
		[p->box setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
		[p->box setFrame:[[w contentView] bounds]];
		[[w contentView] addSubview:p->box];
		[w setDelegate:d];
		p->float_win = w;
		[w orderFront:nil];
	} else {
		NSPanel *w = p->float_win;
		if (w) p->float_frame = sga_dock_relative_of(d, [w frame]);
		p->float_win = nil;
		[w setDelegate:nil];
		[p->box removeFromSuperview];
		[w close];
		[p->box setAutoresizingMask:NSViewNotSizable];
		[p->box setTranslatesAutoresizingMaskIntoConstraints:NO];
		p->floating = NO;
		[d rebuild:p->side];
	}
}

static void sga_dock_float_as_user(SGADock *d, SGADockPanel *p, BOOL a_on)
{
	if (!p || p->floating == a_on) return;
	sga_dock_float_panel(d, p, a_on);
	sga_push(38, sga_id_of(d), sga_dock_index_of(d, p), a_on ? 1 : 0, 0);
	sga_wake();
}

static void sga_dock_toggle_center_as_user(SGADock *d)
{
	d->center_max = !d->center_max;
	sga_dock_slide_back(d);
	[d setNeedsLayout:YES];
	sga_push(40, sga_id_of(d), 0, d->center_max ? 1 : 0, 0);
	sga_wake();
}

/* Where a panel held at `a' (dock coordinates) would land: a side and a place on it (from
   1), YES; or NO, nowhere (a drop there floats it). A side's own room, or for a side that
   takes none, a 28-point band along the dock's edge there. */
static BOOL sga_dock_landing(SGADock *d, SGADockPanel *a_held, NSPoint a, int *a_side, int *a_position, NSRect *a_mark)
{
	NSRect b = [d bounds];
	for (int k = 1; k <= 4; k++) {
		NSRect r = [d rectOf:k];
		BOOL l_room = r.size.width > 0 && r.size.height > 0 && !d->collapsed[k] && !d->auto_hide[k];
		if (!l_room) r = k == 1 ? NSMakeRect(0, 0, 28, b.size.height) : k == 2 ? NSMakeRect(b.size.width - 28, 0, 28, b.size.height)
			: k == 3 ? NSMakeRect(0, 0, b.size.width, 28) : NSMakeRect(0, b.size.height - 28, b.size.width, 28);
		if (!NSPointInRect(a, r)) continue;
		NSMutableArray<SGADockPanel *> *l_on = [NSMutableArray arrayWithArray:sga_dock_visible(d, k)];
		[l_on removeObjectIdenticalTo:a_held];
		int l_place = (int)[l_on count] + 1;
		NSRect l_mark = r;
		if (l_room && !d->tabbed[k]) {
			/* before the first panel whose middle is past the pointer, along the side */
			for (NSUInteger i = 0; i < [l_on count]; i++) {
				NSRect f = [d convertRect:[l_on[i]->box bounds] fromView:l_on[i]->box];
				BOOL l_before = sga_dock_long_vertical(k) ? a.y < NSMidY(f) : a.x < NSMidX(f);
				if (l_before) {
					l_place = (int)i + 1;
					l_mark = sga_dock_long_vertical(k) ? NSMakeRect(NSMinX(r), NSMinY(f) - 2, r.size.width, 4) : NSMakeRect(NSMinX(f) - 2, NSMinY(r), 4, r.size.height);
					break;
				}
			}
		}
		/* the place counts the held panel out when it is already on that side (shared order) */
		*a_side = k;
		*a_position = l_place;
		*a_mark = l_mark;
		return YES;
	}
	return NO;
}

/* The user drags panel `p' (from its title or its tab): sides and gaps light where it would
   land; a drop there moves it (41), anywhere else floats it (38). */
static void sga_dock_track_panel(SGADock *d, SGADockPanel *p, NSEvent *e)
{
	int l_side = 0, l_place = 0;
	NSRect l_mark;
	[d->drop_mark setHidden:YES];
	[d addSubview:d->drop_mark positioned:NSWindowAbove relativeTo:nil];
	NSEvent *n = e;
	for (;;) {
		NSPoint a = [d convertPoint:[n locationInWindow] fromView:nil];
		if (sga_dock_landing(d, p, a, &l_side, &l_place, &l_mark)) { [d->drop_mark setFrame:l_mark]; [d->drop_mark setHidden:NO]; }
		else { l_side = 0; [d->drop_mark setHidden:YES]; }
		[[NSCursor closedHandCursor] set];
		n = [NSApp nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp untilDate:[NSDate distantFuture] inMode:NSEventTrackingRunLoopMode dequeue:YES];
		if (!n || [n type] == NSEventTypeLeftMouseUp) break;
	}
	[d->drop_mark setHidden:YES];
	[[NSCursor arrowCursor] set];
	if (n) {
		NSPoint a = [d convertPoint:[n locationInWindow] fromView:nil];
		if (!sga_dock_landing(d, p, a, &l_side, &l_place, &l_mark)) { sga_dock_float_as_user(d, p, YES); return; }
		NSUInteger l_now = [d->order[p->side] indexOfObjectIdenticalTo:p];
		if (l_side == p->side && (int)l_now + 1 == l_place) return;
		sga_dock_move(sga_id_of(d), sga_dock_index_of(d, p), l_side, l_place);
		sga_push(41, sga_id_of(d), sga_dock_index_of(d, p), l_side, l_place);
		sga_wake();
	}
}

@implementation SGADock (SGADockFloating)
/* The user closes a floating window: the panel docks again (38, b = 0); it is not hidden. */
- (BOOL)windowShouldClose:(NSWindow *)w
{
	for (SGADockPanel *p in panels) if (p->float_win == w) { sga_dock_float_as_user(self, p, NO); return NO; }
	return YES;
}
- (void)windowDidMove:(NSNotification *)n { [self keepFrameOf:[n object]]; }
- (void)windowDidResize:(NSNotification *)n { [self keepFrameOf:[n object]]; }
- (void)keepFrameOf:(NSWindow *)w
{
	for (SGADockPanel *p in panels) if (p->float_win == w) p->float_frame = sga_dock_relative_of(self, [w frame]);
}
@end

/* The primary modifier+Shift+F12 toggles the maximized center of the key window's dock. */
static SGADock *sga_dock_in(NSView *v)
{
	if ([v isKindOfClass:[SGADock class]]) return (SGADock *)v;
	for (NSView *c in [v subviews]) { SGADock *d = sga_dock_in(c); if (d) return d; }
	return nil;
}
static void sga_dock_watch_keys(void)
{
	static id s_dock_keys;
	if (s_dock_keys) return;
	s_dock_keys = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) {
		NSEventModifierFlags f = [e modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
		if ([e keyCode] == 111 && (f & NSEventModifierFlagCommand) && (f & NSEventModifierFlagShift)) {
			SGADock *d = sga_dock_in([[e window] contentView]);
			if (d) { sga_dock_toggle_center_as_user(d); return nil; }
		}
		return e;
	}];
}

int sga_dock(int a_center)
{
	SGADock *d = [[SGADock alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
	d->panels = [NSMutableArray array];
	d->center = sga_get(a_center);
	[d->center setTranslatesAutoresizingMaskIntoConstraints:YES];
	[d addSubview:d->center];
	for (int s = 1; s <= 4; s++) {
		d->order[s] = [NSMutableArray array];
		d->size[s] = s <= 2 ? 200 : 140;
		d->tabs[s] = [[SGADockTabs alloc] initWithFrame:NSZeroRect];
		((SGADockTabs *)d->tabs[s])->dock = d;
		[d->tabs[s] setDelegate:d];
		[d->tabs[s] setTranslatesAutoresizingMaskIntoConstraints:YES];
		[d->tabs[s] setHidden:YES];
		d->stack[s] = [[NSStackView alloc] initWithFrame:NSZeroRect];
		[d->stack[s] setOrientation:sga_dock_long_vertical(s) ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal];
		[d->stack[s] setDistribution:NSStackViewDistributionFillEqually];
		[d->stack[s] setAlignment:sga_dock_long_vertical(s) ? NSLayoutAttributeWidth : NSLayoutAttributeHeight];
		[d->stack[s] setSpacing:1];
		[d->stack[s] setTranslatesAutoresizingMaskIntoConstraints:YES];
		d->side_view[s] = d->stack[s];
		d->strip[s] = [[SGADockStrip alloc] initWithFrame:NSZeroRect];
		d->strip[s]->dock = d;
		d->strip[s]->side = s;
		[d->strip[s] setHidden:YES];
		NSString *l_symbol = s == 1 ? @"chevron.left" : s == 2 ? @"chevron.right" : s == 3 ? @"chevron.up" : @"chevron.down";
		d->chevron[s] = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:l_symbol accessibilityDescription:@"Collapse"] target:d action:@selector(chevronPressed:)];
		[d->chevron[s] setBordered:NO];
		[d->chevron[s] setTag:s];
		[d->chevron[s] setTranslatesAutoresizingMaskIntoConstraints:YES];
		[d->chevron[s] setToolTip:@"Collapse"];
		[d addSubview:d->stack[s]];
		[d addSubview:d->tabs[s]];
		d->pin[s] = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"pin" accessibilityDescription:@"Auto-hide"] target:d action:@selector(togglePin:)];
		d->strip_pin[s] = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"pin.slash" accessibilityDescription:@"Keep open"] target:d action:@selector(togglePin:)];
		for (NSButton *b in @[d->pin[s], d->strip_pin[s]]) {
			[b setBordered:NO];
			[b setTag:s];
			[b setTranslatesAutoresizingMaskIntoConstraints:YES];
			[b setHidden:YES];
		}
		[d->pin[s] setToolTip:@"Auto-hide"];
		[d->strip_pin[s] setToolTip:@"Keep open"];
		[d addSubview:d->strip[s]];
		[d addSubview:d->chevron[s]];
		[d addSubview:d->pin[s]];
		[d addSubview:d->strip_pin[s]];
	}
	SGADockSlide *l_slide = [[SGADockSlide alloc] initWithFrame:NSZeroRect];
	l_slide->dock = d;
	[l_slide setWantsLayer:YES];
	[[l_slide layer] setShadowOpacity:0.3];
	[[l_slide layer] setShadowRadius:6];
	[l_slide setHidden:YES];
	d->slide_view = l_slide;
	d->drop_mark = [[NSView alloc] initWithFrame:NSZeroRect];
	[d->drop_mark setWantsLayer:YES];
	[[d->drop_mark layer] setBackgroundColor:[[[NSColor controlAccentColor] colorWithAlphaComponent:0.35] CGColor]];
	[d->drop_mark setHidden:YES];
	[d addSubview:d->slide_view];
	[d addSubview:d->drop_mark];
	sga_dock_watch_keys();
	return sga_keep(d);
}

static SGADock *sga_dock_of(int a_dock) { id d = sga_get(a_dock); return [d isKindOfClass:[SGADock class]] ? d : nil; }
static SGADockPanel *sga_dock_panel(SGADock *d, int an_index) { return d && an_index >= 1 && an_index <= (int)[d->panels count] ? d->panels[(NSUInteger)an_index - 1] : nil; }
static BOOL sga_dock_side_ok(int a_side) { return a_side >= 1 && a_side <= 4; }

void sga_dock_add(int a_dock, int a_widget, int a_side, const char *a_key, const char *a_title)
{
	SGADock *d = sga_dock_of(a_dock);
	if (!d || !sga_dock_side_ok(a_side)) return;
	SGADockPanel *p = [[SGADockPanel alloc] init];
	p->widget = a_widget;
	p->side = a_side;
	p->shown = YES;
	p->key = sga_string(a_key);
	p->title = sga_string(a_title);
	p->header = [NSTextField labelWithString:p->title];
	[p->header setFont:[NSFont boldSystemFontOfSize:11]];
	[p->header setTextColor:[NSColor secondaryLabelColor]];
	NSView *v = sga_get(a_widget);
	NSView *b = [[NSView alloc] initWithFrame:NSZeroRect];
	[v setTranslatesAutoresizingMaskIntoConstraints:NO];
	[p->header setTranslatesAutoresizingMaskIntoConstraints:NO];
	[b addSubview:p->header];
	[b addSubview:v];
	/* The title top-left (clear of the side's chevron); the content fills the rest. */
	p->under_header = [v.topAnchor constraintEqualToAnchor:p->header.bottomAnchor constant:4];
	p->at_top = [v.topAnchor constraintEqualToAnchor:b.topAnchor constant:4];
	[NSLayoutConstraint activateConstraints:@[
		[p->header.topAnchor constraintEqualToAnchor:b.topAnchor constant:4],
		[p->header.leadingAnchor constraintEqualToAnchor:b.leadingAnchor constant:6],
		[p->header.trailingAnchor constraintLessThanOrEqualToAnchor:b.trailingAnchor constant:-40],
		p->under_header,
		[v.leadingAnchor constraintEqualToAnchor:b.leadingAnchor constant:6],
		[v.trailingAnchor constraintEqualToAnchor:b.trailingAnchor constant:-6],
		[v.bottomAnchor constraintEqualToAnchor:b.bottomAnchor constant:-4]]];
	[v setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
	[v setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	[b setAccessibilityLabel:p->title];
	p->box = b;
	[d->panels addObject:p];
	[d->order[a_side] addObject:p];
	[d rebuild:a_side];
}

void sga_dock_move(int a_dock, int an_index, int a_side, int a_position)
{
	SGADock *d = sga_dock_of(a_dock);
	SGADockPanel *p = sga_dock_panel(d, an_index);
	if (!p || !sga_dock_side_ok(a_side)) return;
	int l_old = p->side;
	[d->order[l_old] removeObjectIdenticalTo:p];
	NSUInteger l_at = (NSUInteger)MAX(0, MIN(a_position - 1, (int)[d->order[a_side] count]));
	[d->order[a_side] insertObject:p atIndex:l_at];
	p->side = a_side;
	[d rebuild:l_old];
	if (l_old != a_side) [d rebuild:a_side];
}

void sga_dock_remove(int a_dock, int an_index)
{
	SGADock *d = sga_dock_of(a_dock);
	SGADockPanel *p = sga_dock_panel(d, an_index);
	if (!p) return;
	if (p->floating) sga_dock_float_panel(d, p, NO);
	if (d->slid == p) sga_dock_slide_back(d);
	[d->order[p->side] removeObjectIdenticalTo:p];
	[d->panels removeObjectIdenticalTo:p];
	[p->box removeFromSuperview];
	[d rebuild:p->side];
}

/* The panel's title: its header, its tab, its name in the strip. */
void sga_dock_set_title(int a_dock, int an_index, const char *a_title)
{
	SGADock *d = sga_dock_of(a_dock);
	SGADockPanel *p = sga_dock_panel(d, an_index);
	if (!p) return;
	p->title = sga_string(a_title);
	[p->header setStringValue:p->title];
	[p->box setAccessibilityLabel:p->title];
	NSInteger i = [d->tabs[p->side] indexOfTabViewItemWithIdentifier:p];
	if (i != NSNotFound) [[d->tabs[p->side] tabViewItemAtIndex:i] setLabel:[p tabText]];
	[p->float_win setTitle:p->title];
	[d->strip[p->side] setNeedsDisplay:YES];
}

void sga_dock_set_tabbed(int a_dock, int a_side, int a_on)
{
	SGADock *d = sga_dock_of(a_dock);
	if (!d || !sga_dock_side_ok(a_side) || d->tabbed[a_side] == (a_on != 0)) return;
	d->tabbed[a_side] = a_on != 0;
	[d rebuild:a_side];
}

/* Silently: show the panel's tab (a tabbed side). */
void sga_dock_activate(int a_dock, int an_index)
{
	SGADock *d = sga_dock_of(a_dock);
	SGADockPanel *p = sga_dock_panel(d, an_index);
	if (p && d->tabbed[p->side]) sga_dock_select_silently(d, p);
}

void sga_dock_set_size(int a_dock, int a_side, int a_px)
{
	SGADock *d = sga_dock_of(a_dock);
	if (!d || !sga_dock_side_ok(a_side) || a_px <= 0) return;
	d->size[a_side] = a_px;
	[d setNeedsLayout:YES];
}

int sga_dock_size(int a_dock, int a_side)
{
	SGADock *d = sga_dock_of(a_dock);
	return d && sga_dock_side_ok(a_side) ? d->size[a_side] : 0;
}

void sga_dock_collapse(int a_dock, int a_side, int a_on)
{
	SGADock *d = sga_dock_of(a_dock);
	if (!d || !sga_dock_side_ok(a_side)) return;
	d->collapsed[a_side] = a_on != 0;
	/* 1r-b: expanding a side also pins it (the shared expand_side ends auto-hide) */
	if (!a_on && d->auto_hide[a_side]) {
		if (d->slid && d->slid->side == a_side) sga_dock_slide_back(d);
		d->auto_hide[a_side] = NO;
	}
	[d setNeedsLayout:YES];
}

void sga_dock_show_panel(int a_dock, int an_index, int a_on)
{
	SGADock *d = sga_dock_of(a_dock);
	SGADockPanel *p = sga_dock_panel(d, an_index);
	if (!p || p->shown == (a_on != 0)) return;
	p->shown = a_on != 0;
	[d rebuild:p->side];
}

/* As the user: the edge of `a_side' dragged to `a_px' (within the center's minimum), a press
   on panel `an_index''s name in its side's strip, a click on its tab. */
void sga_test_drag_dock_edge(int a_dock, int a_side, int a_px)
{
	SGADock *d = sga_dock_of(a_dock);
	if (!d || !sga_dock_side_ok(a_side) || !sga_dock_depth(d, a_side) || d->collapsed[a_side]) return;
	[d layoutSubtreeIfNeeded];
	NSRect b = [d bounds];
	NSPoint at = a_side == 1 ? NSMakePoint(a_px, 0) : a_side == 2 ? NSMakePoint(b.size.width - a_px, 0)
		: a_side == 3 ? NSMakePoint(0, a_px) : NSMakePoint(0, b.size.height - a_px);
	[d userSized:a_side to:[d sizeFor:a_side at:at]];
	[d layoutSubtreeIfNeeded];
}

void sga_test_press_dock_strip(int a_dock, int an_index)
{
	SGADock *d = sga_dock_of(a_dock);
	SGADockPanel *p = sga_dock_panel(d, an_index);
	if (p && p->shown && d->collapsed[p->side]) sga_dock_press_name(d, p);
}

void sga_test_click_dock_tab(int a_dock, int an_index)
{
	SGADock *d = sga_dock_of(a_dock);
	SGADockPanel *p = sga_dock_panel(d, an_index);
	if (!p || !p->shown || !d->tabbed[p->side]) return;
	NSTabView *t = d->tabs[p->side];
	NSInteger i = [t indexOfTabViewItemWithIdentifier:p];
	if (i != NSNotFound && [t selectedTabViewItem] != [t tabViewItemAtIndex:i]) [t selectTabViewItemAtIndex:i];   /* the delegate sends 37 */
}

/* 1r-b backend: silent. */
void sga_dock_float(int a_dock, int an_index, int a_on)
{
	SGADock *d = sga_dock_of(a_dock);
	sga_dock_float_panel(d, sga_dock_panel(d, an_index), a_on != 0);
}

void sga_dock_set_auto_hide(int a_dock, int a_side, int a_on)
{
	SGADock *d = sga_dock_of(a_dock);
	if (!d || !sga_dock_side_ok(a_side) || d->auto_hide[a_side] == (a_on != 0)) return;
	if (d->slid && d->slid->side == a_side) sga_dock_slide_back(d);
	d->auto_hide[a_side] = a_on != 0;
	[d->strip[a_side] setNeedsDisplay:YES];
	[d setNeedsLayout:YES];
}

void sga_dock_maximize_center(int a_dock, int a_on)
{
	SGADock *d = sga_dock_of(a_dock);
	if (!d) return;
	d->center_max = a_on != 0;
	sga_dock_slide_back(d);
	[d setNeedsLayout:YES];
}

/* A floating panel's frame, in logical units from the dock window's top-left. */
void sga_dock_float_frame(int a_dock, int an_index, int x, int y, int w, int h)
{
	SGADock *d = sga_dock_of(a_dock);
	SGADockPanel *p = sga_dock_panel(d, an_index);
	if (!p || w <= 0 || h <= 0) return;
	p->float_frame = NSMakeRect(x, y, w, h);
	if (p->float_win) [p->float_win setFrame:sga_dock_screen_of(d, p->float_frame) display:YES];
}

int sga_dock_float_frame_field(int a_dock, int an_index, int a_field)
{
	SGADock *d = sga_dock_of(a_dock);
	SGADockPanel *p = sga_dock_panel(d, an_index);
	if (!p) return 0;
	if (p->float_win) p->float_frame = sga_dock_relative_of(d, [p->float_win frame]);
	NSRect f = p->float_frame;
	return (int)lround(a_field == 1 ? f.origin.x : a_field == 2 ? f.origin.y : a_field == 3 ? f.size.width : f.size.height);
}

/* As the user: a double click on a panel's tab or title, closing its floating window, a
   drag of it to a side and place, resting on its name in an auto-hide strip (answers
   whether it slid out), the center's double click. */
void sga_test_float_by_user(int a_dock, int an_index)
{
	SGADock *d = sga_dock_of(a_dock);
	SGADockPanel *p = sga_dock_panel(d, an_index);
	if (p && p->shown) sga_dock_float_as_user(d, p, YES);
}

void sga_test_close_floating(int a_dock, int an_index)
{
	SGADock *d = sga_dock_of(a_dock);
	SGADockPanel *p = sga_dock_panel(d, an_index);
	if (p && p->float_win) [d windowShouldClose:p->float_win];
}

void sga_test_drag_panel(int a_dock, int an_index, int a_side, int a_position)
{
	SGADock *d = sga_dock_of(a_dock);
	SGADockPanel *p = sga_dock_panel(d, an_index);
	if (!p || !sga_dock_side_ok(a_side)) return;
	if (p->floating) sga_dock_float_panel(d, p, NO);
	sga_dock_move(a_dock, an_index, a_side, a_position);
	sga_push(41, a_dock, an_index, a_side, a_position);
	sga_wake();
}

int sga_test_slide_out(int a_dock, int an_index)
{
	SGADock *d = sga_dock_of(a_dock);
	SGADockPanel *p = sga_dock_panel(d, an_index);
	if (!p) return 0;
	sga_dock_slide_out(d, p);
	return d->slid == p ? 1 : 0;
}

void sga_test_toggle_center(int a_dock)
{
	SGADock *d = sga_dock_of(a_dock);
	if (d) sga_dock_toggle_center_as_user(d);
}

/* 1r-c: collapsible splitter panes. */
void sga_splitter_set_collapsible(int a_splitter, int a_pane, int a_on)
{
	SGASplit *s = sga_get(a_splitter);
	if (a_pane < 1 || a_pane > 2) return;
	if (!a_on && s->collapsed == a_pane) sga_split_collapse(s, a_pane, NO);
	s->collapsible[a_pane] = a_on != 0;
	[s placeArrows];
}
void sga_splitter_collapse(int a_splitter, int a_pane, int a_on)
{
	SGASplit *s = sga_get(a_splitter);
	if (a_pane >= 1 && a_pane <= 2) sga_split_collapse(s, a_pane, a_on != 0);
}
int sga_splitter_is_collapsed(int a_splitter, int a_pane) { SGASplit *s = sga_get(a_splitter); return s->collapsed == a_pane ? 1 : 0; }
/* As the user: the divider's button for `a_pane'. */
void sga_test_toggle_splitter_pane(int a_splitter, int a_pane) { [(SGASplit *)sga_get(a_splitter) userToggle:a_pane]; }

/* 1r-c: a panel's short title, description and tab tooltip (empty: not set). */
void sga_dock_set_panel_fields(int a_dock, int an_index, const char *a_short, const char *a_description, const char *a_tip)
{
	SGADock *d = sga_dock_of(a_dock);
	SGADockPanel *p = sga_dock_panel(d, an_index);
	if (!p) return;
	p->short_title = sga_string(a_short);
	p->about = sga_string(a_description);
	p->tab_tip = sga_string(a_tip);
	[p->box setAccessibilityHelp:[p->about length] ? p->about : nil];
	NSInteger i = [d->tabs[p->side] indexOfTabViewItemWithIdentifier:p];
	if (i != NSNotFound) {
		NSTabViewItem *t = [d->tabs[p->side] tabViewItemAtIndex:i];
		[t setLabel:[p tabText]];
		[t setToolTip:[p tabTip]];
	}
	if ([p->pill length] && p->header_id) sga_pill_set(p->header_id, [p->pill UTF8String], [p->about UTF8String], 2);
	sga_dock_place_tab_pill(d, p->side);
	[d->strip[p->side] setNeedsDisplay:YES];
}

/* A reference pill on the panel's title bar; on a tabbed side, at the tab view's corner while
   its tab is selected (NSTabView's tabs cannot hold one). Empty: none. Its tip is the
   description. */
void sga_dock_set_panel_pill(int a_dock, int an_index, const char *a_code)
{
	SGADock *d = sga_dock_of(a_dock);
	SGADockPanel *p = sga_dock_panel(d, an_index);
	if (!p) return;
	p->pill = sga_string(a_code);
	if (!p->header_id) p->header_id = sga_keep(p->header);
	if ([p->pill length]) sga_pill_set(p->header_id, [p->pill UTF8String], [p->about ?: @"" UTF8String], 2);
	else sga_pill_clear(p->header_id);
	sga_dock_place_tab_pill(d, p->side);
}

static void sga_dock_place_tab_pill(SGADock *d, int a_side)
{
	static NSMutableDictionary<NSValue *, NSNumber *> *s_tab_ids;
	if (!s_tab_ids) s_tab_ids = [NSMutableDictionary dictionary];
	NSTabView *t = d->tabs[a_side];
	if (!t) return;
	NSValue *k = [NSValue valueWithNonretainedObject:t];
	if (!s_tab_ids[k]) s_tab_ids[k] = @(sga_keep(t));
	int l_id = [s_tab_ids[k] intValue];
	SGADockPanel *p = d->tabbed[a_side] ? [[t selectedTabViewItem] identifier] : nil;
	if (p && [p->pill length]) sga_pill_set(l_id, [p->pill UTF8String], [p->about ?: @"" UTF8String], 2);
	else sga_pill_clear(l_id);
}

/* What a tab of panel `an_index' shows, and its tooltip, whatever the side's mode. */
const char *sga_test_panel_tab_text(int a_dock, int an_index)
{
	SGADockPanel *p = sga_dock_panel(sga_dock_of(a_dock), an_index);
	return sga_return(Kind_label, p ? [p tabText] : @"");
}
const char *sga_test_panel_tab_tooltip(int a_dock, int an_index)
{
	SGADockPanel *p = sga_dock_panel(sga_dock_of(a_dock), an_index);
	return sga_return(Kind_label, p ? [p tabTip] : @"");
}

/* As a drop would: the row found at the middle of row `a_row''s place (a list's or a table's
   row, a tree's node by its number, a token field's token). */
int sga_test_locate_row(int a_id, int a_row)
{
	id c = sga_core(a_id);
	NSView *v = c;
	NSRect r = NSZeroRect;
	if ([c isKindOfClass:[SGATree class]]) {
		SGANode *n = sga_tree_node((SGATree *)c, a_row);
		NSInteger i = n ? [(SGATree *)c rowForItem:n] : -1;
		if (i >= 0) r = [(SGATree *)c rectOfRow:i];
	} else if ([c isKindOfClass:[NSTableView class]]) {
		NSInteger i = a_row >= 1 ? sga_view_row((NSTableView *)c, a_row - 1) : -1;   /* 1s: a model row */
		if (i >= 0 && i < [(NSTableView *)c numberOfRows]) r = [(NSTableView *)c rectOfRow:i];
	} else if ([c isKindOfClass:[SGATokenField class]]) {
		NSArray<NSValue *> *l_rects = sga_token_rects((SGATokenField *)c);
		if (a_row >= 1 && a_row <= (int)[l_rects count]) r = [l_rects[(NSUInteger)a_row - 1] rectValue];
	}
	if (NSIsEmptyRect(r) || ![v window]) return 0;
	[[[v window] contentView] layoutSubtreeIfNeeded];
	NSPoint p = [v convertPoint:NSMakePoint(NSMidX(r), NSMidY(r)) toView:nil];
	int l_row = 0;
	return sga_widget_at([v window], p, &l_row) == a_id ? l_row : 0;
}
/* ---------------------------------------------- 1s: rich rows, filtering, sorting (lists) */

/* The filter text of each filtered list. */
static NSMutableDictionary<NSValue *, NSString *> *s_list_filter;

/* Rebuild the list's shown map from its filter, reload, and keep the selection with its rows:
   a selected row the filter hides is deselected, with the selection event (4). Rows with a
   subtitle make the list's rows two lines tall. */
static void sga_list_refilter(NSTableView *t)
{
	NSMutableArray *l_rows = [s_target rowsOf:t];
	NSMutableIndexSet *l_selected = [NSMutableIndexSet indexSet];
	[[t selectedRowIndexes] enumerateIndexesUsingBlock:^(NSUInteger v, BOOL *a_stop) { (void)a_stop; NSInteger m = sga_model_row(t, (NSInteger)v); if (m >= 0) [l_selected addIndex:(NSUInteger)m]; }];
	NSString *f = s_list_filter[[NSValue valueWithNonretainedObject:t]];
	if ([f length]) {
		NSMutableArray<NSNumber *> *m = [NSMutableArray array];
		for (NSUInteger i = 0; i < [l_rows count]; i++)
			if ([sga_row_title(l_rows[i]) rangeOfString:f options:NSCaseInsensitiveSearch].location != NSNotFound) [m addObject:@(i)];
		sga_set_shown_map(t, m);
	} else sga_set_shown_map(t, nil);
	BOOL l_two = NO;
	for (id r in l_rows) if ([r isKindOfClass:[SGARichRow class]] && [((SGARichRow *)r)->subtitle length]) l_two = YES;
	[t setRowHeight:l_two ? 40 : 24];
	NSMutableIndexSet *l_keep = [NSMutableIndexSet indexSet];
	__block BOOL l_lost = NO;
	[l_selected enumerateIndexesUsingBlock:^(NSUInteger m, BOOL *a_stop) {
		(void)a_stop;
		NSInteger v = m < [l_rows count] ? sga_view_row(t, (NSInteger)m) : -1;
		if (v >= 0) [l_keep addIndex:(NSUInteger)v]; else l_lost = YES;
	}];
	s_suppress++;
	[t reloadData];
	[t selectRowIndexes:l_keep byExtendingSelection:NO];
	s_suppress--;
	if (l_lost) {
		NSUInteger l_first = [l_keep firstIndex];
		sga_push(4, sga_id_of(t), l_first == NSNotFound ? 0 : (int)sga_model_row(t, (NSInteger)l_first) + 1, 0, 0);
	}
}

/* The cell of a rich row: check box, icon, title over subtitle, badge, close button. */
@interface SGARichCell : NSTableCellView
{
@public
	NSButton *check, *close;
	NSImageView *icon;
	NSTextField *title_field, *subtitle_field, *badge_field;
	__weak NSTableView *table;
	NSInteger model;
}
@end
@implementation SGARichCell
- (void)checked:(NSButton *)b { (void)b; sga_list_user_check(table, model); }
- (void)closed:(NSButton *)b { (void)b; sga_list_user_close(table, model); }
@end

static NSView *sga_rich_cell(NSTableView *t, SGARichRow *a_row, NSInteger a_model)
{
	SGARichCell *c = [t makeViewWithIdentifier:@"sga_rich" owner:s_target];
	if (!c) {
		c = [[SGARichCell alloc] initWithFrame:NSZeroRect];
		c.identifier = @"sga_rich";
		c->check = [NSButton checkboxWithTitle:@"" target:c action:@selector(checked:)];
		c->icon = [[NSImageView alloc] init];
		c->title_field = [NSTextField labelWithString:@""];
		c->subtitle_field = [NSTextField labelWithString:@""];
		[c->subtitle_field setTextColor:[NSColor secondaryLabelColor]];
		[c->subtitle_field setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
		c->badge_field = [NSTextField labelWithString:@""];
		[c->badge_field setFont:[NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]]];
		[c->badge_field setTextColor:[NSColor whiteColor]];
		[c->badge_field setWantsLayer:YES];
		[[c->badge_field layer] setBackgroundColor:[[NSColor systemRedColor] CGColor]];
		[[c->badge_field layer] setCornerRadius:8];
		[c->badge_field setAlignment:NSTextAlignmentCenter];
		c->close = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark.circle.fill" accessibilityDescription:@"Close"] target:c action:@selector(closed:)];
		[c->close setBordered:NO];
		NSStackView *l_text = [NSStackView stackViewWithViews:@[c->title_field, c->subtitle_field]];
		[l_text setOrientation:NSUserInterfaceLayoutOrientationVertical];
		[l_text setAlignment:NSLayoutAttributeLeading];
		[l_text setSpacing:0];
		[c->title_field setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
		NSStackView *l_row = [NSStackView stackViewWithViews:@[c->check, c->icon, l_text, c->badge_field, c->close]];
		[l_row setSpacing:6];
		[l_row setTranslatesAutoresizingMaskIntoConstraints:NO];
		[c addSubview:l_row];
		[NSLayoutConstraint activateConstraints:@[
			[l_row.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:2], [l_row.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-2],
			[l_row.centerYAnchor constraintEqualToAnchor:c.centerYAnchor],
			[c->badge_field.widthAnchor constraintGreaterThanOrEqualToConstant:18], [c->badge_field.heightAnchor constraintEqualToConstant:16],
			[c->icon.widthAnchor constraintEqualToConstant:16], [c->icon.heightAnchor constraintEqualToConstant:16]]];
		[l_text setHuggingPriority:NSLayoutPriorityDefaultLow - 1 forOrientation:NSLayoutConstraintOrientationHorizontal];
	}
	c->table = t;
	c->model = a_model;
	[c->check setHidden:!a_row->checkable];
	[c->check setState:a_row->checked ? NSControlStateValueOn : NSControlStateValueOff];
	[c->title_field setStringValue:a_row->title];
	[c->subtitle_field setStringValue:a_row->subtitle ?: @""];
	[c->subtitle_field setHidden:![a_row->subtitle length]];
	NSImage *l_image = [a_row->icon length] ? [NSImage imageWithSystemSymbolName:sga_symbol_of(a_row->icon) accessibilityDescription:nil] : nil;
	[c->icon setImage:l_image];
	[c->icon setHidden:l_image == nil];
	[c->badge_field setStringValue:a_row->badge > 0 ? [NSString stringWithFormat:@" %d ", a_row->badge] : @""];
	[c->badge_field setHidden:a_row->badge <= 0];
	[c->close setHidden:!a_row->closable];
	[c setAccessibilityLabel:a_row->title];
	return c;
}

/* As the user: a row's check box toggled (43), a row closed: removed, then 44 (the row it was). */
static void sga_list_user_check(NSTableView *t, NSInteger a_model)
{
	id r = a_model >= 0 && a_model < (NSInteger)[[s_target rowsOf:t] count] ? [s_target rowsOf:t][(NSUInteger)a_model] : nil;
	if (![r isKindOfClass:[SGARichRow class]] || !((SGARichRow *)r)->checkable) return;
	((SGARichRow *)r)->checked = !((SGARichRow *)r)->checked;
	NSInteger v = sga_view_row(t, a_model);
	s_suppress++;
	if (v >= 0) [t reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)v] columnIndexes:[NSIndexSet indexSetWithIndex:0]];
	s_suppress--;
	sga_push(43, sga_id_of(t), (int)a_model + 1, ((SGARichRow *)r)->checked ? 1 : 0, 0);
	sga_wake();
}

static void sga_list_user_close(NSTableView *t, NSInteger a_model)
{
	NSMutableArray *l_rows = [s_target rowsOf:t];
	id r = a_model >= 0 && a_model < (NSInteger)[l_rows count] ? l_rows[(NSUInteger)a_model] : nil;
	if (![r isKindOfClass:[SGARichRow class]] || !((SGARichRow *)r)->closable) return;
	[l_rows removeObjectAtIndex:(NSUInteger)a_model];
	sga_list_refilter(t);
	sga_push(44, sga_id_of(t), (int)a_model + 1, 0, 0);
	sga_wake();
}

/* A rich row (flags: 1 checkable, 2 checked, 4 closable), added last. */
void sga_list_extend_rich(int a_id, const char *a_title, const char *a_subtitle, const char *an_icon, int a_badge, int a_flags)
{
	NSTableView *t = s_inner[a_id];
	SGARichRow *r = [[SGARichRow alloc] init];
	r->title = sga_string(a_title);
	r->subtitle = sga_string(a_subtitle);
	r->icon = sga_string(an_icon);
	r->badge = a_badge;
	r->checkable = (a_flags & 1) != 0;
	r->checked = (a_flags & 2) != 0;
	r->closable = (a_flags & 4) != 0;
	[[s_target rowsOf:t] addObject:r];
	sga_list_refilter(t);
}

void sga_list_set_checked(int a_id, int a_row, int a_on)
{
	NSTableView *t = s_inner[a_id];
	NSMutableArray *l_rows = [s_target rowsOf:t];
	if (a_row < 1 || a_row > (int)[l_rows count] || ![l_rows[(NSUInteger)a_row - 1] isKindOfClass:[SGARichRow class]]) return;
	((SGARichRow *)l_rows[(NSUInteger)a_row - 1])->checked = a_on != 0;
	NSInteger v = sga_view_row(t, a_row - 1);
	s_suppress++;
	if (v >= 0) [t reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)v] columnIndexes:[NSIndexSet indexSetWithIndex:0]];
	s_suppress--;
}

int sga_list_is_checked(int a_id, int a_row)
{
	NSMutableArray *l_rows = [s_target rowsOf:s_inner[a_id]];
	id r = a_row >= 1 && a_row <= (int)[l_rows count] ? l_rows[(NSUInteger)a_row - 1] : nil;
	return [r isKindOfClass:[SGARichRow class]] && ((SGARichRow *)r)->checked ? 1 : 0;
}

void sga_list_remove(int a_id, int a_row)
{
	NSTableView *t = s_inner[a_id];
	NSMutableArray *l_rows = [s_target rowsOf:t];
	if (a_row < 1 || a_row > (int)[l_rows count]) return;
	[l_rows removeObjectAtIndex:(NSUInteger)a_row - 1];
	sga_list_refilter(t);
}

/* Reorder the rows: `an_order' names the old rows (from 1), in their new order, separated by
   anything that is not a digit. The selection stays with its rows; no event. */
void sga_list_reorder(int a_id, const char *an_order)
{
	NSTableView *t = s_inner[a_id];
	NSMutableArray *l_rows = [s_target rowsOf:t];
	NSMutableArray *l_new = [NSMutableArray array];
	NSMutableIndexSet *l_selected = [NSMutableIndexSet indexSet];
	[[t selectedRowIndexes] enumerateIndexesUsingBlock:^(NSUInteger v, BOOL *a_stop) { (void)a_stop; [l_selected addIndex:(NSUInteger)sga_model_row(t, (NSInteger)v)]; }];
	NSMutableIndexSet *l_now = [NSMutableIndexSet indexSet];
	NSScanner *k = [NSScanner scannerWithString:sga_string(an_order)];
	[k setCharactersToBeSkipped:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]];
	NSInteger n;
	while ([k scanInteger:&n]) {
		if (n >= 1 && n <= (NSInteger)[l_rows count]) {
			if ([l_selected containsIndex:(NSUInteger)n - 1]) [l_now addIndex:[l_new count]];
			[l_new addObject:l_rows[(NSUInteger)n - 1]];
		}
	}
	if ([l_new count] != [l_rows count]) return;   /* not a permutation: ignored */
	[l_rows setArray:l_new];
	s_suppress++;
	[t deselectAll:nil];
	s_suppress--;
	sga_list_refilter(t);
	NSMutableIndexSet *l_view = [NSMutableIndexSet indexSet];
	[l_now enumerateIndexesUsingBlock:^(NSUInteger m, BOOL *a_stop) { (void)a_stop; NSInteger v = sga_view_row(t, (NSInteger)m); if (v >= 0) [l_view addIndex:(NSUInteger)v]; }];
	s_suppress++;
	[t selectRowIndexes:l_view byExtendingSelection:NO];
	s_suppress--;
}

/* Show only the rows whose title holds `a_text' (ignoring case); empty shows all. */
void sga_list_set_filter(int a_id, const char *a_text)
{
	NSTableView *t = s_inner[a_id];
	if (!s_list_filter) s_list_filter = [NSMutableDictionary dictionary];
	s_list_filter[[NSValue valueWithNonretainedObject:t]] = sga_string(a_text);
	sga_list_refilter(t);
}

int sga_list_shown_count(int a_id) { return (int)[(NSTableView *)s_inner[a_id] numberOfRows]; }

/* As the user: row `a_row''s check box, its close button. */
void sga_test_check_row(int a_id, int a_row) { sga_list_user_check(s_inner[a_id], a_row - 1); }
void sga_test_close_row(int a_id, int a_row) { sga_list_user_close(s_inner[a_id], a_row - 1); }

/* ---------------------------------------------- 1s: editable cells and filtering (tables) */

/* Column `a_column''s editor: 0 none, 1 text, 2 check ("1" or "0"), 3 choice (the options,
   separated by 0x1F). */
void sga_table_set_column_editor(int a_id, int a_column, int a_kind, const char *an_options)
{
	SGAGridTable *t = s_inner[a_id];
	t->editor[@(a_column)] = @(a_kind);
	t->choices[@(a_column)] = a_kind == 3 ? sga_fields(an_options) : @[];
	s_suppress++;
	[t reloadData];
	s_suppress--;
}

/* A committed edit: a held table holds it now (and puts the old text back if the program
   refuses it); a lazy table passes it on. 45 (row, column); the text for table_take_edit. */
static void sga_table_commit(SGAGridTable *t, NSInteger a_model, NSInteger a_column, NSString *a_text)
{
	if (a_model < 0 || a_column < 1) return;
	[t->note removeFromSuperview];
	t->note = nil;
	NSArray<NSString *> *l_row = t->source_on ? t->cache[@(a_model)] : (a_model < (NSInteger)[t->data count] ? t->data[(NSUInteger)a_model] : nil);
	NSString *l_old = (NSUInteger)a_column - 1 < [l_row count] ? l_row[(NSUInteger)a_column - 1] : @"";
	if ([l_old isEqualToString:a_text]) return;
	if (!t->source_on && l_row) {
		NSMutableArray *l_new = [l_row mutableCopy];
		while ((NSInteger)[l_new count] < a_column) [l_new addObject:@""];
		l_new[(NSUInteger)a_column - 1] = a_text;
		t->data[(NSUInteger)a_model] = l_new;
	}
	t->edit_text = a_text;
	t->edit_old = l_old;
	t->edit_row = a_model;
	t->edit_column = a_column;
	sga_push(45, sga_id_of(t), (int)a_model + 1, (int)a_column, 0);
	sga_wake();
}

const char *sga_table_take_edit(int a_id) { SGAGridTable *t = s_inner[a_id]; return sga_return(Kind_field, t->edit_text ?: @""); }

/* The program refused the edit at (row, column): the old text back, and the message under
   the cell until the next edit in this table. */
void sga_table_refuse_edit(int a_id, int a_row, int a_column, const char *a_message)
{
	SGAGridTable *t = s_inner[a_id];
	NSInteger m = a_row - 1;
	if (!t->source_on && m >= 0 && m < (NSInteger)[t->data count] && m == t->edit_row && a_column == t->edit_column && t->edit_old) {
		NSMutableArray *l_new = [t->data[(NSUInteger)m] mutableCopy];
		if ((NSInteger)[l_new count] >= a_column) l_new[(NSUInteger)a_column - 1] = t->edit_old;
		t->data[(NSUInteger)m] = l_new;
	}
	NSInteger v = sga_view_row(t, m);
	s_suppress++;
	if (v >= 0) [t reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)v] columnIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)a_column - 1]];
	s_suppress--;
	[t->note removeFromSuperview];
	t->note = nil;
	if (v < 0 || !a_message || !*a_message) return;
	NSRect r = [t frameOfCellAtColumn:a_column - 1 row:v];
	NSTextField *n = [NSTextField labelWithString:sga_string(a_message)];
	[n setTextColor:[NSColor systemRedColor]];
	[n setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[n setDrawsBackground:YES];
	[n setBackgroundColor:[NSColor controlBackgroundColor]];
	[n sizeToFit];
	[n setFrameOrigin:NSMakePoint(NSMinX(r) + 2, NSMaxY(r))];
	[t addSubview:n];
	t->note = n;
}

/* Recompute a held table's shown rows from its filter (any of the masked columns, ignoring
   case); a selected row the filter hides is deselected, with 4. */
static void sga_table_refilter(SGAGridTable *t)
{
	NSMutableIndexSet *l_selected = [NSMutableIndexSet indexSet];
	[[t selectedRowIndexes] enumerateIndexesUsingBlock:^(NSUInteger v, BOOL *a_stop) { (void)a_stop; NSInteger m = sga_model_row(t, (NSInteger)v); if (m >= 0) [l_selected addIndex:(NSUInteger)m]; }];
	if ([t->filter length] && !t->source_on) {
		NSMutableArray<NSNumber *> *m = [NSMutableArray array];
		for (NSUInteger i = 0; i < [t->data count]; i++) {
			NSArray<NSString *> *l_row = t->data[i];
			for (NSUInteger k = 0; k < [l_row count]; k++)
				if ((t->filter_columns == 0 || (t->filter_columns & (1 << k))) && [l_row[k] rangeOfString:t->filter options:NSCaseInsensitiveSearch].location != NSNotFound) { [m addObject:@(i)]; break; }
		}
		sga_set_shown_map(t, m);
	} else if (!t->source_on) sga_set_shown_map(t, nil);
	NSMutableIndexSet *l_keep = [NSMutableIndexSet indexSet];
	__block BOOL l_lost = NO;
	[l_selected enumerateIndexesUsingBlock:^(NSUInteger m, BOOL *a_stop) { (void)a_stop; NSInteger v = sga_view_row(t, (NSInteger)m); if (v >= 0) [l_keep addIndex:(NSUInteger)v]; else l_lost = YES; }];
	s_suppress++;
	[t reloadData];
	[t selectRowIndexes:l_keep byExtendingSelection:NO];
	s_suppress--;
	if (l_lost) {
		NSUInteger l_first = [l_keep firstIndex];
		sga_push(4, sga_id_of(t), l_first == NSNotFound ? 0 : (int)sga_model_row(t, (NSInteger)l_first) + 1, 0, 0);
	}
}

/* A held table's filter: rows whose masked columns (bit 0 = column 1; 0 all) hold `a_text'. */
void sga_table_set_filter(int a_id, const char *a_text, int a_columns)
{
	SGAGridTable *t = s_inner[a_id];
	t->filter = sga_string(a_text);
	t->filter_columns = a_columns;
	sga_table_refilter(t);
}

/* A lazy table's shown rows, from the shared class: model rows (from 1) separated by anything
   that is not a digit; empty shows every row. */
void sga_table_set_shown_rows(int a_id, const char *a_rows)
{
	SGAGridTable *t = s_inner[a_id];
	NSString *l_text = sga_string(a_rows);
	if (![l_text length]) sga_set_shown_map(t, nil);
	else {
		NSMutableArray<NSNumber *> *m = [NSMutableArray array];
		NSScanner *k = [NSScanner scannerWithString:l_text];
		[k setCharactersToBeSkipped:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]];
		NSInteger n;
		while ([k scanInteger:&n]) if (n >= 1) [m addObject:@(n - 1)];
		sga_set_shown_map(t, m);
	}
	t->filter = nil;
	sga_table_refilter(t);
}

int sga_table_shown_count(int a_id) { return (int)[(NSTableView *)s_inner[a_id] numberOfRows]; }

/* As the user: `a_text' typed into cell (row, column), then Enter (a check cell takes "1" or
   "0", a choice cell an option); an edit begun there and cancelled with Escape. */
void sga_test_edit_cell(int a_id, int a_row, int a_column, const char *a_text)
{
	SGAGridTable *t = s_inner[a_id];
	if (![t->editor[@(a_column)] intValue]) return;
	sga_table_commit(t, a_row - 1, a_column, sga_string(a_text));
}

void sga_test_cancel_edit(int a_id, int a_row, int a_column)
{
	SGAGridTable *t = s_inner[a_id];
	NSInteger v = sga_view_row(t, a_row - 1);
	if (v < 0 || [t->editor[@(a_column)] intValue] != 1) return;
	[t editAt:v column:a_column];
	NSTextField *f = [t viewAtColumn:a_column - 1 row:v makeIfNecessary:NO];
	if (f) [t control:f textView:(NSTextView *)[[t window] fieldEditor:NO forObject:f] doCommandBySelector:@selector(cancelOperation:)];
}

/* What cell (row, column) shows now, by model row; and the refusal note showing ("" none). */
const char *sga_test_cell_text(int a_id, int a_row, int a_column)
{
	SGAGridTable *t = s_inner[a_id];
	NSInteger m = a_row - 1;
	NSArray<NSString *> *l_row = m < 0 ? nil : t->source_on ? t->cache[@(m)] : (m < (NSInteger)[t->data count] ? t->data[(NSUInteger)m] : nil);
	return sga_return(Kind_field, a_column >= 1 && (NSUInteger)a_column <= [l_row count] ? l_row[(NSUInteger)a_column - 1] : @"");
}
const char *sga_test_cell_note(int a_id) { SGAGridTable *t = s_inner[a_id]; return sga_return(Kind_label, t->note ? [t->note stringValue] : @""); }

/* ------------------------------------------------- 1t: navigation (tabs placed, the sidebar) */

/* A navigation list: a source-list table of entries, a heading (not selectable, not counted)
   or a page (its title, icon and badge). A click, or Return or Space, chooses a page; the
   arrow keys move the highlight, skipping headings. Collapsed, only icons show (or the
   title's first letter in a circle), the title as a tooltip. The owner hears the choice. */
@interface SGANavEntry : NSObject
{
@public
	BOOL heading;
	NSString *title, *icon, *badge;
	int page;   /* from 1; 0 for a heading */
}
@end
@implementation SGANavEntry
@end

@interface SGANavList : NSTableView <NSTableViewDataSource, NSTableViewDelegate>
{
@public
	int owner;                    /* the tabs' or the sidebar's handle */
	NSMutableArray<SGANavEntry *> *entries;
	BOOL collapsed;
}
@end

static void sga_nav_chosen(SGANavList *l, int a_page);

@implementation SGANavList
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { (void)t; return (NSInteger)[entries count]; }
- (BOOL)tableView:(NSTableView *)t isGroupRow:(NSInteger)r { (void)t; return entries[(NSUInteger)r]->heading; }
- (BOOL)tableView:(NSTableView *)t shouldSelectRow:(NSInteger)r { (void)t; return !entries[(NSUInteger)r]->heading; }
- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)r
{
	(void)c;
	SGANavEntry *e = entries[(NSUInteger)r];
	if (e->heading) {
		NSTextField *h = [NSTextField labelWithString:collapsed ? @"" : [e->title uppercaseString]];
		[h setFont:[NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]]];
		[h setTextColor:[NSColor secondaryLabelColor]];
		return h;
	}
	NSTableCellView *v = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
	NSImageView *i = [[NSImageView alloc] init];
	NSImage *l_image = [e->icon length] ? [NSImage imageWithSystemSymbolName:sga_symbol_of(e->icon) accessibilityDescription:e->title] : nil;
	if (!l_image && collapsed) {   /* no icon: the title's first letter in a circle */
		NSString *l_letter = [e->title length] ? [[e->title substringToIndex:1] uppercaseString] : @"?";
		l_image = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO drawingHandler:^BOOL(NSRect a_rect) {
			[[NSColor secondaryLabelColor] setStroke];
			NSBezierPath *o = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(a_rect, 1, 1)];
			[o stroke];
			NSDictionary *a = @{NSFontAttributeName: [NSFont boldSystemFontOfSize:10], NSForegroundColorAttributeName: [NSColor labelColor]};
			NSSize z = [l_letter sizeWithAttributes:a];
			[l_letter drawAtPoint:NSMakePoint(NSMidX(a_rect) - z.width / 2, NSMidY(a_rect) - z.height / 2) withAttributes:a];
			return YES;
		}];
	}
	[i setImage:l_image];
	[i setHidden:l_image == nil];
	NSTextField *l_title = [NSTextField labelWithString:e->title];
	[l_title setLineBreakMode:NSLineBreakByTruncatingTail];
	[l_title setHidden:collapsed];
	NSTextField *l_badge = [NSTextField labelWithString:[e->badge length] ? e->badge : @""];
	[l_badge setTextColor:[NSColor secondaryLabelColor]];
	[l_badge setHidden:collapsed || ![e->badge length]];
	NSStackView *row = [NSStackView stackViewWithViews:@[i, l_title, l_badge]];
	[row setSpacing:6];
	[row setTranslatesAutoresizingMaskIntoConstraints:NO];
	[l_title setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
	[v addSubview:row];
	[NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:2],
		[row.trailingAnchor constraintLessThanOrEqualToAnchor:v.trailingAnchor constant:-2], [row.centerYAnchor constraintEqualToAnchor:v.centerYAnchor],
		[i.widthAnchor constraintEqualToConstant:18], [i.heightAnchor constraintEqualToConstant:18]]];
	[v setToolTip:collapsed ? e->title : nil];
	[v setAccessibilityLabel:e->title];
	return v;
}
/* A click chooses at once; the arrow keys only move (Return or Space chooses). */
- (void)tableViewSelectionDidChange:(NSNotification *)n
{
	(void)n;
	NSEventType t = [[NSApp currentEvent] type];
	if (s_suppress || (t != NSEventTypeLeftMouseDown && t != NSEventTypeLeftMouseUp)) return;
	NSInteger r = [self selectedRow];
	if (r >= 0 && !entries[(NSUInteger)r]->heading) sga_nav_chosen(self, entries[(NSUInteger)r]->page);
}
- (void)keyDown:(NSEvent *)e
{
	BOOL l_choose = [e keyCode] == 36 || [e keyCode] == 76 || [[e charactersIgnoringModifiers] isEqualToString:@" "];
	NSInteger r = [self selectedRow];
	if (l_choose && r >= 0 && !entries[(NSUInteger)r]->heading) { sga_nav_chosen(self, entries[(NSUInteger)r]->page); return; }
	[super keyDown:e];
}
@end

static SGANavList *sga_nav_list_new(int a_owner, BOOL a_full)
{
	(void)a_full;
	SGANavList *l = [[SGANavList alloc] init];
	l->owner = a_owner;
	l->entries = [NSMutableArray array];
	NSTableColumn *k = [[NSTableColumn alloc] initWithIdentifier:@"sga_nav"];
	[l addTableColumn:k];
	[l setHeaderView:nil];
	[l setStyle:NSTableViewStyleSourceList];
	[l setRowHeight:26];
	[l setDataSource:l];
	[l setDelegate:l];
	return l;
}
static void sga_nav_list_reload(SGANavList *l) { s_suppress++; [l reloadData]; s_suppress--; }
static void sga_nav_list_select(SGANavList *l, int a_page)
{
	for (NSUInteger r = 0; r < [l->entries count]; r++)
		if (!l->entries[r]->heading && l->entries[r]->page == a_page) {
			s_suppress++;
			[l selectRowIndexes:[NSIndexSet indexSetWithIndex:r] byExtendingSelection:NO];
			s_suppress--;
			return;
		}
}
static NSScrollView *sga_nav_scroll(SGANavList *l)
{
	NSScrollView *s = [[NSScrollView alloc] init];
	[s setDocumentView:l];
	[s setHasVerticalScroller:YES];
	[s setDrawsBackground:NO];
	return s;
}

/* Tabs on a side: the titles kept in step with the tab view's pages. */
static void sga_tabs_titles_sync(SGATabs *t)
{
	if (!t->titles) return;
	[t->titles->entries removeAllObjects];
	for (NSInteger k = 0; k < [t numberOfTabViewItems]; k++) {
		SGANavEntry *e = [[SGANavEntry alloc] init];
		e->page = sga_tab_page(t, k);
		e->title = [[t tabViewItemAtIndex:k] label];
		[t->titles->entries addObject:e];
	}
	[t->titles->entries sortUsingComparator:^NSComparisonResult(SGANavEntry *a, SGANavEntry *b) { return a->page < b->page ? NSOrderedAscending : NSOrderedDescending; }];
	sga_nav_list_reload(t->titles);
	sga_nav_list_select(t->titles, sga_tabs_selected(sga_id_of(t)));
}

/* 0 none, 1 top, 2 bottom, 3 left, 4 right. No event. */
void sga_tabs_set_position(int a_tabs, int a_position)
{
	SGATabs *t = sga_get(a_tabs);
	t->position = a_position;
	[t setTabViewType:a_position == 1 ? NSTopTabsBezelBorder : a_position == 2 ? NSBottomTabsBezelBorder : a_position == 0 ? NSNoTabsNoBorder : NSNoTabsBezelBorder];
	if (a_position == 3 || a_position == 4) {
		if (!t->strip) {
			t->titles = sga_nav_list_new(a_tabs, NO);
			t->strip = sga_nav_scroll(t->titles);
			[t->strip setTranslatesAutoresizingMaskIntoConstraints:YES];
			[t addSubview:t->strip];
		}
		sga_tabs_titles_sync(t);
	} else if (t->strip) {
		[t->strip removeFromSuperview];
		t->strip = nil;
		t->titles = nil;
	}
	[t setNeedsLayout:YES];
}

/* The sidebar: a navigation list beside a tabless NSTabView of the pages, and a collapse
   button at the list's foot. 46 a page chosen by the user, 47 collapsed or expanded. */
@interface SGASidebar : NSView
{
@public
	SGANavList *list;
	NSScrollView *strip;
	NSTabView *pages;
	NSButton *toggle;
	BOOL collapsible, collapsed;
	NSLayoutConstraint *width;
	int count;
}
@end
@implementation SGASidebar
- (void)toggled:(NSButton *)b { (void)b; sga_sidebar_set_collapsed(sga_id_of(self), !collapsed); sga_push(47, sga_id_of(self), 0, collapsed ? 1 : 0, 0); sga_wake(); }
@end

int sga_sidebar(void)
{
	SGASidebar *s = [[SGASidebar alloc] initWithFrame:NSZeroRect];
	int l_id = sga_keep(s);
	s->list = sga_nav_list_new(l_id, YES);
	s->strip = sga_nav_scroll(s->list);
	s->pages = [[NSTabView alloc] init];
	[s->pages setTabViewType:NSNoTabsNoBorder];
	s->toggle = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"sidebar.left" accessibilityDescription:@"Collapse"] target:s action:@selector(toggled:)];
	[s->toggle setBordered:NO];
	[s->toggle setHidden:YES];
	for (NSView *v in @[s->strip, s->pages, s->toggle]) { [v setTranslatesAutoresizingMaskIntoConstraints:NO]; [s addSubview:v]; }
	s->width = [s->strip.widthAnchor constraintEqualToConstant:180];
	[NSLayoutConstraint activateConstraints:@[
		[s->strip.leadingAnchor constraintEqualToAnchor:s.leadingAnchor], [s->strip.topAnchor constraintEqualToAnchor:s.topAnchor],
		[s->strip.bottomAnchor constraintEqualToAnchor:s->toggle.topAnchor constant:-4], s->width,
		[s->toggle.leadingAnchor constraintEqualToAnchor:s.leadingAnchor constant:8], [s->toggle.bottomAnchor constraintEqualToAnchor:s.bottomAnchor constant:-6],
		[s->pages.leadingAnchor constraintEqualToAnchor:s->strip.trailingAnchor constant:8], [s->pages.trailingAnchor constraintEqualToAnchor:s.trailingAnchor],
		[s->pages.topAnchor constraintEqualToAnchor:s.topAnchor], [s->pages.bottomAnchor constraintEqualToAnchor:s.bottomAnchor]]];
	return l_id;
}

static SGASidebar *sga_sidebar_of(int a_id) { id s = sga_get(a_id); return [s isKindOfClass:[SGASidebar class]] ? s : nil; }

void sga_sidebar_extend(int a_id, int a_page, const char *a_title)
{
	SGASidebar *s = sga_sidebar_of(a_id);
	if (!s) return;
	NSView *v = sga_get(a_page);
	NSView *l_holder = [[NSView alloc] init];
	[v setTranslatesAutoresizingMaskIntoConstraints:NO];
	[l_holder addSubview:v];
	sga_pin_page(v, l_holder);
	NSTabViewItem *i = [[NSTabViewItem alloc] initWithIdentifier:nil];
	[i setView:l_holder];
	s_suppress++;
	[s->pages addTabViewItem:i];
	s_suppress--;
	SGANavEntry *e = [[SGANavEntry alloc] init];
	e->page = ++s->count;
	e->title = sga_string(a_title);
	[s->list->entries addObject:e];
	sga_nav_list_reload(s->list);
	if (s->count == 1) sga_nav_list_select(s->list, 1);
}

void sga_sidebar_add_heading(int a_id, const char *a_text)
{
	SGASidebar *s = sga_sidebar_of(a_id);
	if (!s) return;
	SGANavEntry *e = [[SGANavEntry alloc] init];
	e->heading = YES;
	e->title = sga_string(a_text);
	[s->list->entries addObject:e];
	sga_nav_list_reload(s->list);
}

static SGANavEntry *sga_sidebar_entry(SGASidebar *s, int a_page)
{
	for (SGANavEntry *e in s->list->entries) if (!e->heading && e->page == a_page) return e;
	return nil;
}

void sga_sidebar_set_icon(int a_id, int i, const char *a_name) { SGASidebar *s = sga_sidebar_of(a_id); SGANavEntry *e = s ? sga_sidebar_entry(s, i) : nil; if (e) { e->icon = sga_string(a_name); sga_nav_list_reload(s->list); sga_nav_list_select(s->list, sga_sidebar_selected(a_id)); } }
void sga_sidebar_set_badge(int a_id, int i, const char *a_text) { SGASidebar *s = sga_sidebar_of(a_id); SGANavEntry *e = s ? sga_sidebar_entry(s, i) : nil; if (e) { e->badge = sga_string(a_text); sga_nav_list_reload(s->list); sga_nav_list_select(s->list, sga_sidebar_selected(a_id)); } }

/* Quiet: page `i' shows and is highlighted. */
void sga_sidebar_select(int a_id, int i)
{
	SGASidebar *s = sga_sidebar_of(a_id);
	if (!s || i < 1 || i > s->count) return;
	s_suppress++;
	[s->pages selectTabViewItemAtIndex:i - 1];
	s_suppress--;
	sga_nav_list_select(s->list, i);
}

int sga_sidebar_selected(int a_id)
{
	SGASidebar *s = sga_sidebar_of(a_id);
	NSTabViewItem *i = s ? [s->pages selectedTabViewItem] : nil;
	return i ? (int)[s->pages indexOfTabViewItem:i] + 1 : 0;
}

void sga_sidebar_set_collapsible(int a_id, int a_on) { SGASidebar *s = sga_sidebar_of(a_id); if (s) { s->collapsible = a_on != 0; [s->toggle setHidden:!s->collapsible]; } }

void sga_sidebar_set_collapsed(int a_id, int a_on)
{
	SGASidebar *s = sga_sidebar_of(a_id);
	if (!s) return;
	s->collapsed = a_on != 0;
	s->list->collapsed = s->collapsed;
	[s->width setConstant:s->collapsed ? 44 : 180];
	[s->toggle setImage:[NSImage imageWithSystemSymbolName:s->collapsed ? @"sidebar.right" : @"sidebar.left" accessibilityDescription:s->collapsed ? @"Expand" : @"Collapse"]];
	int l_page = sga_sidebar_selected(a_id);
	sga_nav_list_reload(s->list);
	sga_nav_list_select(s->list, l_page);
}

int sga_sidebar_is_collapsed(int a_id) { SGASidebar *s = sga_sidebar_of(a_id); return s && s->collapsed ? 1 : 0; }

/* As the user: page `a_page' clicked in the sidebar (46). */
static void sga_sidebar_user_choose(int a_id, int a_page)
{
	SGASidebar *s = sga_sidebar_of(a_id);
	if (s) sga_nav_chosen(s->list, a_page);
}

/* A navigation list's choice: a sidebar shows the page and sends 46; tabs on a side select
   the page as a tab's click does (13, through the tab view's delegate). */
static void sga_nav_chosen(SGANavList *l, int a_page)
{
	id o = sga_get(l->owner);
	if ([o isKindOfClass:[SGASidebar class]]) {
		SGASidebar *s = o;
		if (a_page < 1 || a_page > s->count) return;
		s_suppress++;
		[s->pages selectTabViewItemAtIndex:a_page - 1];
		s_suppress--;
		sga_nav_list_select(l, a_page);
		sga_push(46, l->owner, a_page, 0, 0);
		sga_wake();
	} else if ([o isKindOfClass:[SGATabs class]]) {
		NSTabView *t = o;
		if (a_page >= 1 && a_page <= [t numberOfTabViewItems]) [t selectTabViewItemAtIndex:sga_tab_item(t, a_page)];
		sga_nav_list_select(l, a_page);
	}
}

/* As the user: the sidebar's collapse button (47). */
void sga_test_toggle_sidebar(int a_id) { SGASidebar *s = sga_sidebar_of(a_id); if (s) [s toggled:s->toggle]; }

/* Which page the user sees: a tab view's or a sidebar's. */
int sga_test_page_shown(int a_id)
{
	if (sga_sidebar_of(a_id)) return sga_sidebar_selected(a_id);
	return [sga_get(a_id) isKindOfClass:[NSTabView class]] ? sga_tabs_selected(a_id) : 0;
}

static void sga_tabs_titles_follow(NSTabView *t) { if ([t isKindOfClass:[SGATabs class]] && ((SGATabs *)t)->titles) sga_tabs_titles_sync((SGATabs *)t); }

/* ------------------------------------------------------------ 1u: dialogs and context help */

/* A dialog: an NSPanel holding its content above a row of buttons in the Mac's order:
   destructive buttons at the leading end, apart; then the others; then Cancel; the default
   at the trailing end. Return presses the default (never a destructive button), Escape and
   the close box press Cancel (nothing without one). A press sends 48 (a = the button, from
   1, in the order added); the program closes it. It shows as a sheet on its parent, or alone,
   app-modal while the program's run_modal pumps. */
@interface SGADialog : NSPanel <NSWindowDelegate>
{
@public
	NSView *content_area;
	NSStackView *row;
	NSMutableArray<NSButton *> *buttons;   /* in the order added */
	NSMutableArray<NSNumber *> *roles;     /* 1 default, 2 cancel, 3 destructive, 4 other */
	NSWindow *parent;
	NSModalSession session;
}
@end
static int sga_dialog_cancel(SGADialog *d)
{
	for (NSUInteger i = 0; i < [d->roles count]; i++) if ([d->roles[i] intValue] == 2 && [d->buttons[i] isEnabled]) return (int)i + 1;
	return 0;
}
@implementation SGADialog
- (void)pressed:(NSButton *)b { sga_push(48, sga_id_of(self), (int)[b tag], 0, 0); sga_wake(); }
/* The close box presses Cancel; the program closes the dialog. */
- (BOOL)windowShouldClose:(NSWindow *)w { (void)w; int n = sga_dialog_cancel(self); if (n) [self pressed:buttons[(NSUInteger)n - 1]]; return NO; }
- (void)cancelOperation:(id)s { (void)s; int n = sga_dialog_cancel(self); if (n) [self pressed:buttons[(NSUInteger)n - 1]]; }
- (BOOL)canBecomeKeyWindow { return YES; }
@end

static void sga_dialog_arrange(SGADialog *d)
{
	for (NSView *v in [[d->row arrangedSubviews] copy]) [d->row removeArrangedSubview:v], [v removeFromSuperview];
	NSView *l_gap = [[NSView alloc] init];
	[l_gap setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
	int l_order[] = {3, 0, 4, 2, 1};   /* destructive, the gap, others, cancel, default */
	for (int j = 0; j < 5; j++) {
		if (l_order[j] == 0) { [d->row addArrangedSubview:l_gap]; continue; }
		for (NSUInteger i = 0; i < [d->buttons count]; i++) if ([d->roles[i] intValue] == l_order[j]) [d->row addArrangedSubview:d->buttons[i]];
	}
}

int sga_dialog(const char *a_title)
{
	SGADialog *d = [[SGADialog alloc] initWithContentRect:NSMakeRect(0, 0, 380, 160) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:YES];
	[d setTitle:sga_string(a_title)];
	[d setReleasedWhenClosed:NO];
	[d setDelegate:d];
	[d setHidesOnDeactivate:NO];
	d->buttons = [NSMutableArray array];
	d->roles = [NSMutableArray array];
	d->content_area = [[NSView alloc] init];
	d->row = [[NSStackView alloc] init];
	[d->row setSpacing:8];
	NSView *c = [d contentView];
	for (NSView *v in @[d->content_area, d->row]) { [v setTranslatesAutoresizingMaskIntoConstraints:NO]; [c addSubview:v]; }
	[NSLayoutConstraint activateConstraints:@[
		[d->content_area.topAnchor constraintEqualToAnchor:c.topAnchor constant:20], [d->content_area.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:20],
		[d->content_area.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-20],
		[d->row.topAnchor constraintEqualToAnchor:d->content_area.bottomAnchor constant:16], [d->row.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:20],
		[d->row.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-20], [d->row.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-20]]];
	return sga_keep(d);
}

static SGADialog *sga_dialog_of(int a_id) { id d = sga_get(a_id); return [d isKindOfClass:[SGADialog class]] ? d : nil; }

void sga_dialog_set_content(int a_dialog, int a_widget)
{
	SGADialog *d = sga_dialog_of(a_dialog);
	if (!d) return;
	for (NSView *v in [[d->content_area subviews] copy]) [v removeFromSuperview];
	NSView *v = sga_get(a_widget);
	[v setTranslatesAutoresizingMaskIntoConstraints:NO];
	[d->content_area addSubview:v];
	[NSLayoutConstraint activateConstraints:@[
		[v.leadingAnchor constraintEqualToAnchor:d->content_area.leadingAnchor], [v.trailingAnchor constraintEqualToAnchor:d->content_area.trailingAnchor],
		[v.topAnchor constraintEqualToAnchor:d->content_area.topAnchor], [v.bottomAnchor constraintEqualToAnchor:d->content_area.bottomAnchor]]];
}

/* The button's number, from 1 in the order added. Roles: 1 default, 2 cancel, 3 destructive, 4 other. */
int sga_dialog_add_button(int a_dialog, const char *a_text, int a_role)
{
	SGADialog *d = sga_dialog_of(a_dialog);
	if (!d) return 0;
	NSButton *b = [NSButton buttonWithTitle:sga_string(a_text) target:d action:@selector(pressed:)];
	[b setTag:(NSInteger)[d->buttons count] + 1];
	if (a_role == 1) [b setKeyEquivalent:@"\r"];
	if (a_role == 2) [b setKeyEquivalent:@"\x1b"];
	if (a_role == 3) [b setHasDestructiveAction:YES];
	[d->buttons addObject:b];
	[d->roles addObject:@(a_role)];
	sga_dialog_arrange(d);
	return (int)[b tag];
}

void sga_dialog_set_button_enabled(int a_dialog, int n, int a_on)
{
	SGADialog *d = sga_dialog_of(a_dialog);
	if (d && n >= 1 && n <= (int)[d->buttons count]) [d->buttons[(NSUInteger)n - 1] setEnabled:a_on != 0];
}

/* Show it, never blocking: a sheet on the parent window, or alone (app-modal when asked). */
void sga_dialog_present(int a_dialog, int a_parent, int an_app_modal)
{
	SGADialog *d = sga_dialog_of(a_dialog);
	if (!d) return;
	NSWindow *p = a_parent > 0 ? sga_get(a_parent) : nil;
	[[d contentView] layoutSubtreeIfNeeded];
	[d setContentSize:[[d contentView] fittingSize]];
	if (p && [p isVisible]) {
		d->parent = p;
		[p beginSheet:d completionHandler:nil];
	} else {
		d->parent = nil;
		[d center];
		[d makeKeyAndOrderFront:nil];
		if (an_app_modal) { d->session = [NSApp beginModalSessionForWindow:d]; s_modal_window = d; }
	}
}

/* One turn of an app-modal dialog's modal session. */
void sga_dialog_pump(int a_dialog)
{
	SGADialog *d = sga_dialog_of(a_dialog);
	if (d && d->session) [NSApp runModalSession:d->session];
}

void sga_dialog_close(int a_dialog)
{
	SGADialog *d = sga_dialog_of(a_dialog);
	if (!d) return;
	if (d->session) { [NSApp endModalSession:d->session]; d->session = nil; }
	if (s_modal_window == d) s_modal_window = nil;
	if (d->parent) { [d->parent endSheet:d]; d->parent = nil; }
	[d orderOut:nil];
}

int sga_dialog_is_shown(int a_dialog) { SGADialog *d = sga_dialog_of(a_dialog); return d && [d isVisible] ? 1 : 0; }

/* As the user: a click on button `n' (if enabled); a key (1 Return, 2 Escape, 3 the close box);
   a click after `a_ms' (while run_modal pumps); the buttons' numbers as shown. */
void sga_test_press_dialog_button(int a_dialog, int n)
{
	SGADialog *d = sga_dialog_of(a_dialog);
	if (d && n >= 1 && n <= (int)[d->buttons count] && [d->buttons[(NSUInteger)n - 1] isEnabled]) [d pressed:d->buttons[(NSUInteger)n - 1]];
}

void sga_test_dialog_key(int a_dialog, int a_key)
{
	SGADialog *d = sga_dialog_of(a_dialog);
	if (!d) return;
	if (a_key == 1) {   /* Return: the enabled default, never a destructive button */
		for (NSUInteger i = 0; i < [d->roles count]; i++) if ([d->roles[i] intValue] == 1 && [d->buttons[i] isEnabled]) { [d pressed:d->buttons[i]]; return; }
	} else if (a_key == 2) [d cancelOperation:nil];
	else if (a_key == 3) [d windowShouldClose:d];
}

void sga_test_press_dialog_button_later(int a_dialog, int n, int a_ms)
{
	NSTimer *t = [NSTimer timerWithTimeInterval:a_ms / 1000.0 repeats:NO block:^(NSTimer *a_timer) { (void)a_timer; sga_test_press_dialog_button(a_dialog, n); }];
	[[NSRunLoop currentRunLoop] addTimer:t forMode:NSRunLoopCommonModes];
	[[NSRunLoop currentRunLoop] addTimer:t forMode:NSModalPanelRunLoopMode];
}

const char *sga_test_dialog_button_order(int a_dialog)
{
	SGADialog *d = sga_dialog_of(a_dialog);
	NSMutableArray<NSString *> *l_numbers = [NSMutableArray array];
	for (NSView *v in [d->row arrangedSubviews]) if ([v isKindOfClass:[NSButton class]]) [l_numbers addObject:[NSString stringWithFormat:@"%ld", (long)[(NSButton *)v tag]]];
	return sga_return(Kind_label, [l_numbers componentsJoinedByString:@","]);
}

/* Context help: F1, or Command+? (the Mac's Help shortcut), asks for help on the focused
   widget (49, a = its handle; the shared class walks up for the topic). */
static int sga_focused_widget(NSWindow *w)
{
	id f = [w firstResponder];
	if ([f isKindOfClass:[NSTextView class]] && [(NSTextView *)f isFieldEditor]) f = [(NSTextView *)f delegate];
	for (NSView *v = [f isKindOfClass:[NSView class]] ? f : nil; v; v = [v superview]) { int k = sga_id_of(v); if (k) return k; }
	return 0;
}
static void sga_help_watch(void)
{
	static id s_help_keys;
	if (s_help_keys) return;
	s_help_keys = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *e) {
		BOOL l_f1 = [e keyCode] == 122;
		BOOL l_cmd_question = ([e modifierFlags] & NSEventModifierFlagCommand) && [[e charactersIgnoringModifiers] isEqualToString:@"?"];
		if ((l_f1 || l_cmd_question) && [e window]) { sga_push(49, 0, sga_focused_widget([e window]), 0, 0); sga_wake(); return nil; }
		return e;
	}];
}

static NSString *s_help_text;
/* The default help: the text in a popover at the widget. */
void sga_help_show_tip(int a_widget, const char *a_text)
{
	NSView *v = sga_get(a_widget);
	if (![v isKindOfClass:[NSView class]] || ![v window]) return;
	[s_help_popover close];
	s_help_text = sga_string(a_text);
	NSTextField *l = [NSTextField wrappingLabelWithString:s_help_text];
	[l setPreferredMaxLayoutWidth:280];
	NSViewController *c = [[NSViewController alloc] init];
	NSView *box = [[NSView alloc] init];
	[l setTranslatesAutoresizingMaskIntoConstraints:NO];
	[box addSubview:l];
	[NSLayoutConstraint activateConstraints:@[[l.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:12], [l.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-12],
		[l.topAnchor constraintEqualToAnchor:box.topAnchor constant:10], [l.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-10]]];
	[c setView:box];
	/* The text's own size, wrapped at 280 points: a wrapping label's fitting width collapses. */
	NSRect l_text = [s_help_text boundingRectWithSize:NSMakeSize(280, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName: [l font]}];
	CGFloat l_w = ceil(NSWidth(l_text)) + 4, l_h = ceil(NSHeight(l_text)) + 2;
	[NSLayoutConstraint activateConstraints:@[[l.widthAnchor constraintEqualToConstant:l_w]]];
	s_help_popover = [[NSPopover alloc] init];
	[s_help_popover setContentSize:NSMakeSize(l_w + 24, l_h + 20)];
	[s_help_popover setContentViewController:c];
	[s_help_popover setBehavior:NSPopoverBehaviorTransient];
	[s_help_popover setAnimates:NO];   /* at its size at once: a snapshot right after shows it whole */
	[s_help_popover showRelativeToRect:[v bounds] ofView:v preferredEdge:NSRectEdgeMaxY];
}

void sga_test_press_help(int a_window)
{
	NSWindow *w = sga_get(a_window);
	if (w) { sga_push(49, 0, sga_focused_widget(w), 0, 0); sga_wake(); }
}

const char *sga_test_help_tip_shown(void) { return sga_return(Kind_label, [s_help_popover isShown] ? (s_help_text ?: @"") : @""); }

/* ------------------------------------------------------------------ 1v-a: the grid view */

/* A grid view: an NSCollectionView in a flow layout of cells, each a picture or an icon
   over a title (and a dimmer subtitle). Pictures load off the main thread and appear when
   ready. A filter shows the items whose title or subtitle holds its text; item numbers are
   always the model's. The user's selection sends 50 (a = the first selected item, 0 none),
   a double click (or Return) opens an item, 51 (a = the item). */
@interface SGAGridItem : NSObject
{
@public
	NSString *title, *subtitle, *picture, *icon;
	NSImage *image;
	BOOL loading;
}
@end
@implementation SGAGridItem
@end

@interface SGAGridCell : NSCollectionViewItem
{
@public
	NSImageView *picture_view;
	NSTextField *title_field, *subtitle_field;
}
@end
@implementation SGAGridCell
- (void)loadView
{
	NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 120, 120)];
	[v setWantsLayer:YES];
	[[v layer] setCornerRadius:8];
	picture_view = [[NSImageView alloc] init];
	[picture_view setImageScaling:NSImageScaleProportionallyUpOrDown];
	/* the picture gives way to the title (a large image would push it out of the cell) */
	for (NSInteger o = 0; o < 2; o++) {
		[picture_view setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow - 1 forOrientation:o];
		[picture_view setContentHuggingPriority:NSLayoutPriorityDefaultLow - 1 forOrientation:o];
	}
	title_field = [NSTextField labelWithString:@""];
	[title_field setAlignment:NSTextAlignmentCenter];
	[title_field setLineBreakMode:NSLineBreakByTruncatingTail];
	subtitle_field = [NSTextField labelWithString:@""];
	[subtitle_field setAlignment:NSTextAlignmentCenter];
	[subtitle_field setTextColor:[NSColor secondaryLabelColor]];
	[subtitle_field setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[subtitle_field setLineBreakMode:NSLineBreakByTruncatingTail];
	for (NSView *s in @[picture_view, title_field, subtitle_field]) { [s setTranslatesAutoresizingMaskIntoConstraints:NO]; [v addSubview:s]; }
	[NSLayoutConstraint activateConstraints:@[
		[picture_view.topAnchor constraintEqualToAnchor:v.topAnchor constant:6], [picture_view.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:6],
		[picture_view.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-6], [picture_view.bottomAnchor constraintEqualToAnchor:title_field.topAnchor constant:-4],
		[title_field.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:4], [title_field.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-4],
		[subtitle_field.topAnchor constraintEqualToAnchor:title_field.bottomAnchor], [subtitle_field.leadingAnchor constraintEqualToAnchor:v.leadingAnchor constant:4],
		[subtitle_field.trailingAnchor constraintEqualToAnchor:v.trailingAnchor constant:-4], [subtitle_field.bottomAnchor constraintEqualToAnchor:v.bottomAnchor constant:-4]]];
	[self setView:v];
}
- (void)setSelected:(BOOL)a_on
{
	[super setSelected:a_on];
	[[[self view] layer] setBackgroundColor:a_on ? [[[NSColor controlAccentColor] colorWithAlphaComponent:0.3] CGColor] : [[NSColor clearColor] CGColor]];
}
@end

@interface SGAGridView : NSCollectionView
{
@public
	NSMutableArray<SGAGridItem *> *items;
	NSArray<NSNumber *> *shown;   /* model items (from 0) shown, nil all */
	NSString *filter;
	/* model items selected while the grid has no window: an NSCollectionView that has
	   not loaded its items yet drops a selection, so it is applied on joining a window */
	NSMutableSet<NSNumber *> *pending;
}
@end

static NSInteger sga_grid_model(SGAGridView *g, NSInteger a_view) { return g->shown ? (a_view >= 0 && a_view < (NSInteger)[g->shown count] ? [g->shown[(NSUInteger)a_view] integerValue] : -1) : a_view; }
static NSInteger sga_grid_view_index(SGAGridView *g, NSInteger a_model) { if (!g->shown) return a_model; NSUInteger i = [g->shown indexOfObject:@(a_model)]; return i == NSNotFound ? -1 : (NSInteger)i; }
static void sga_grid_load(SGAGridView *g, SGAGridItem *it);

/* The grid's data source and delegate: a separate object, since NSCollectionView forwards
   some of its own delegate methods to its delegate (itself would recurse forever). */
@interface SGAGridSource : NSObject <NSCollectionViewDataSource, NSCollectionViewDelegate>
{
@public
	__weak SGAGridView *grid;
}
@end

static void sga_grid_apply_pending(SGAGridView *g);
@implementation SGAGridView
- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];
	/* after the window has laid the grid out, when it has items to select */
	__weak SGAGridView *w = self;
	if ([self window] && pending) dispatch_async(dispatch_get_main_queue(), ^{ SGAGridView *g = w; if (g && [g window] && g->pending) sga_grid_apply_pending(g); });
}
- (void)tellSelection
{
	NSIndexPath *p = [[[self selectionIndexPaths] allObjects] sortedArrayUsingSelector:@selector(compare:)].firstObject;
	sga_push(50, sga_id_of(self), p ? (int)sga_grid_model(self, [p item]) + 1 : 0, 0, 0);
	sga_wake();
}
- (void)openAt:(NSInteger)a_view
{
	NSInteger m = sga_grid_model(self, a_view);
	if (m >= 0) { sga_push(51, sga_id_of(self), (int)m + 1, 0, 0); sga_wake(); }
}
- (void)mouseDown:(NSEvent *)e
{
	[super mouseDown:e];
	if ([e clickCount] == 2) {
		NSIndexPath *p = [self indexPathForItemAtPoint:[self convertPoint:[e locationInWindow] fromView:nil]];
		if (p) [self openAt:[p item]];
	}
}
- (void)keyDown:(NSEvent *)e
{
	if (([e keyCode] == 36 || [e keyCode] == 76) && [[self selectionIndexPaths] count]) { [self openAt:[[[self selectionIndexPaths] anyObject] item]]; return; }
	[super keyDown:e];
}
@end

@implementation SGAGridSource
- (NSInteger)collectionView:(NSCollectionView *)c numberOfItemsInSection:(NSInteger)s { (void)c; (void)s; SGAGridView *g = grid; return g ? (NSInteger)(g->shown ? [g->shown count] : [g->items count]) : 0; }
- (NSCollectionViewItem *)collectionView:(NSCollectionView *)c itemForRepresentedObjectAtIndexPath:(NSIndexPath *)p
{
	SGAGridView *self_grid = grid;
	SGAGridCell *cell = [c makeItemWithIdentifier:@"sga_grid_cell" forIndexPath:p];
	NSInteger m = sga_grid_model(self_grid, [p item]);
	SGAGridItem *it = m >= 0 ? self_grid->items[(NSUInteger)m] : nil;
	[cell->title_field setStringValue:it->title ?: @""];
	[cell->subtitle_field setStringValue:it->subtitle ?: @""];
	[cell->subtitle_field setHidden:![it->subtitle length]];
	NSImage *l_image = it->image;
	if (!l_image && [it->icon length]) l_image = [NSImage imageWithSystemSymbolName:sga_symbol_of(it->icon) accessibilityDescription:it->title]
		?: [NSImage imageWithSystemSymbolName:@"questionmark.square.dashed" accessibilityDescription:it->title];   /* a name GUI_ICON does not know */
	if (!l_image && [it->picture length]) { sga_grid_load(self_grid, it); l_image = [NSImage imageWithSystemSymbolName:@"photo" accessibilityDescription:nil]; }
	[cell->picture_view setImage:l_image];
	[[cell view] setAccessibilityLabel:it->title];
	return cell;
}
- (void)collectionView:(NSCollectionView *)c didSelectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)p { (void)c; (void)p; if (!s_suppress) [grid tellSelection]; }
- (void)collectionView:(NSCollectionView *)c didDeselectItemsAtIndexPaths:(NSSet<NSIndexPath *> *)p { (void)c; (void)p; if (!s_suppress) [grid tellSelection]; }
@end

/* Load the item's picture off the main thread; show it when ready. */
static void sga_grid_load(SGAGridView *g, SGAGridItem *it)
{
	if (it->loading || it->image) return;
	it->loading = YES;
	NSString *l_path = it->picture;
	__weak SGAGridView *w = g;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSImage *l_image = [[NSImage alloc] initWithContentsOfFile:l_path];
		dispatch_async(dispatch_get_main_queue(), ^{
			SGAGridView *l_g = w;
			it->image = l_image ?: [NSImage imageWithSystemSymbolName:@"exclamationmark.triangle" accessibilityDescription:nil];
			it->loading = NO;
			NSUInteger m = l_g ? [l_g->items indexOfObjectIdenticalTo:it] : NSNotFound;
			NSInteger v = m == NSNotFound ? -1 : sga_grid_view_index(l_g, (NSInteger)m);
			if (v >= 0) {
				/* reloading an item deselects it: keep the selection */
				NSSet<NSIndexPath *> *l_selected = [l_g selectionIndexPaths];
				s_suppress++;
				[l_g reloadItemsAtIndexPaths:[NSSet setWithObject:[NSIndexPath indexPathForItem:v inSection:0]]];
				[l_g setSelectionIndexPaths:l_selected];
				s_suppress--;
			}
		});
	});
}

static SGAGridView *sga_grid_of(int a_id) { id g = s_inner[a_id]; return [g isKindOfClass:[SGAGridView class]] ? g : nil; }

static void sga_grid_refresh(SGAGridView *g)
{
	NSMutableSet<NSNumber *> *l_selected = [NSMutableSet set];
	for (NSIndexPath *p in [g selectionIndexPaths]) [l_selected addObject:@(sga_grid_model(g, [p item]))];
	if ([g->filter length]) {
		NSMutableArray<NSNumber *> *m = [NSMutableArray array];
		for (NSUInteger i = 0; i < [g->items count]; i++) {
			SGAGridItem *it = g->items[i];
			if ([it->title rangeOfString:g->filter options:NSCaseInsensitiveSearch].location != NSNotFound
				|| [it->subtitle rangeOfString:g->filter options:NSCaseInsensitiveSearch].location != NSNotFound) [m addObject:@(i)];
		}
		g->shown = m;
	} else g->shown = nil;
	NSMutableSet<NSIndexPath *> *l_keep = [NSMutableSet set];
	for (NSNumber *k in l_selected) { NSInteger v = sga_grid_view_index(g, [k integerValue]); if (v >= 0) [l_keep addObject:[NSIndexPath indexPathForItem:v inSection:0]]; }
	s_suppress++;
	[g reloadData];
	[g setSelectionIndexPaths:l_keep];
	s_suppress--;
}

int sga_grid_view(void)
{
	NSScrollView *l_scroll = [[SGARowsScroll alloc] init];
	SGAGridView *g = [[SGAGridView alloc] init];
	NSCollectionViewFlowLayout *l = [[NSCollectionViewFlowLayout alloc] init];
	[l setItemSize:NSMakeSize(120, 120)];
	[l setMinimumInteritemSpacing:8];
	[l setMinimumLineSpacing:8];
	[l setSectionInset:NSEdgeInsetsMake(8, 8, 8, 8)];
	[g setCollectionViewLayout:l];
	[g registerClass:[SGAGridCell class] forItemWithIdentifier:@"sga_grid_cell"];
	[g setSelectable:YES];
	static NSMutableArray *s_grid_sources;   /* keeps each grid's source alive */
	if (!s_grid_sources) s_grid_sources = [NSMutableArray array];
	SGAGridSource *l_source = [[SGAGridSource alloc] init];
	l_source->grid = g;
	[s_grid_sources addObject:l_source];
	[g setDataSource:l_source];
	[g setDelegate:l_source];
	g->items = [NSMutableArray array];
	[l_scroll setDocumentView:g];
	[l_scroll setHasVerticalScroller:YES];
	[l_scroll setBorderType:NSBezelBorder];
	int l_id = sga_keep(l_scroll);
	s_inner[l_id] = g;
	return l_id;
}

void sga_grid_view_extend(int a_id, const char *a_title, const char *a_picture, const char *an_icon)
{
	SGAGridView *g = sga_grid_of(a_id);
	if (!g) return;
	SGAGridItem *it = [[SGAGridItem alloc] init];
	it->title = sga_string(a_title);
	it->picture = sga_string(a_picture);
	it->icon = sga_string(an_icon);
	it->subtitle = @"";
	[g->items addObject:it];
	if ([it->picture length]) sga_grid_load(g, it);
	sga_grid_refresh(g);
}

void sga_grid_view_set_subtitle(int a_id, int i, const char *a_text)
{
	SGAGridView *g = sga_grid_of(a_id);
	if (g && i >= 1 && i <= (int)[g->items count]) { g->items[(NSUInteger)i - 1]->subtitle = sga_string(a_text); sga_grid_refresh(g); }
}

void sga_grid_view_remove(int a_id, int i)
{
	SGAGridView *g = sga_grid_of(a_id);
	if (g && i >= 1 && i <= (int)[g->items count]) {
		/* the selection is kept by model item: shift the later ones down */
		NSMutableSet<NSNumber *> *l_after = [NSMutableSet set];
		for (NSIndexPath *p in [g selectionIndexPaths]) {
			NSInteger m = sga_grid_model(g, [p item]);
			if (m != i - 1) [l_after addObject:@(m > i - 1 ? m - 1 : m)];
		}
		[g->items removeObjectAtIndex:(NSUInteger)i - 1];
		s_suppress++;
		[g setSelectionIndexPaths:[NSSet set]];
		s_suppress--;
		sga_grid_refresh(g);
		NSMutableSet<NSIndexPath *> *l_keep = [NSMutableSet set];
		for (NSNumber *k in l_after) { NSInteger v = sga_grid_view_index(g, [k integerValue]); if (v >= 0) [l_keep addObject:[NSIndexPath indexPathForItem:v inSection:0]]; }
		s_suppress++;
		[g setSelectionIndexPaths:l_keep];
		s_suppress--;
	}
}

void sga_grid_view_wipe_out(int a_id) { SGAGridView *g = sga_grid_of(a_id); if (g) { [g->items removeAllObjects]; s_suppress++; [g setSelectionIndexPaths:[NSSet set]]; s_suppress--; sga_grid_refresh(g); } }

void sga_grid_view_set_item_size(int a_id, int w, int h) { SGAGridView *g = sga_grid_of(a_id); if (g) [(NSCollectionViewFlowLayout *)[g collectionViewLayout] setItemSize:NSMakeSize(w, h)]; }

void sga_grid_view_set_spacing(int a_id, int s)
{
	SGAGridView *g = sga_grid_of(a_id);
	if (!g) return;
	NSCollectionViewFlowLayout *l = (NSCollectionViewFlowLayout *)[g collectionViewLayout];
	[l setMinimumInteritemSpacing:s];
	[l setMinimumLineSpacing:s];
}

void sga_grid_view_set_multiple(int a_id, int a_on) { SGAGridView *g = sga_grid_of(a_id); if (g) [g setAllowsMultipleSelection:a_on != 0]; }

/* Quiet: item `i' selected (added to the selection when `an_extend'); 0 clears. */
static void sga_grid_apply_pending(SGAGridView *g)
{
	NSMutableSet<NSIndexPath *> *l_paths = [NSMutableSet set];
	for (NSNumber *k in g->pending) { NSInteger v = sga_grid_view_index(g, [k integerValue]); if (v >= 0) [l_paths addObject:[NSIndexPath indexPathForItem:v inSection:0]]; }
	g->pending = nil;
	s_suppress++;
	[g reloadData];
	[g layoutSubtreeIfNeeded];
	[g setSelectionIndexPaths:l_paths];
	s_suppress--;
}

void sga_grid_view_select(int a_id, int i, int an_extend)
{
	SGAGridView *g = sga_grid_of(a_id);
	if (!g) return;
	if (![g window]) {
		if (!an_extend || !g->pending) {
			NSMutableSet<NSNumber *> *l_old = g->pending;
			g->pending = [NSMutableSet set];
			if (an_extend) for (NSIndexPath *p in [g selectionIndexPaths]) [g->pending addObject:@(sga_grid_model(g, [p item]))];
			(void)l_old;
		}
		if (i >= 1 && sga_grid_view_index(g, i - 1) >= 0) [g->pending addObject:@(i - 1)];
		return;
	}
	NSMutableSet<NSIndexPath *> *s = an_extend ? [[g selectionIndexPaths] mutableCopy] : [NSMutableSet set];
	NSInteger v = i >= 1 ? sga_grid_view_index(g, i - 1) : -1;
	if (v >= 0) [s addObject:[NSIndexPath indexPathForItem:v inSection:0]];
	s_suppress++;
	[g setSelectionIndexPaths:s];
	s_suppress--;
}

static NSArray<NSNumber *> *sga_grid_selected_models(SGAGridView *g)
{
	if (g->pending) return [[g->pending allObjects] sortedArrayUsingSelector:@selector(compare:)];
	NSMutableArray<NSNumber *> *r = [NSMutableArray array];
	for (NSIndexPath *p in [g selectionIndexPaths]) [r addObject:@(sga_grid_model(g, [p item]) + 1)];
	[r sortUsingSelector:@selector(compare:)];
	return r;
}
int sga_grid_view_selected_count(int a_id) { SGAGridView *g = sga_grid_of(a_id); return g ? (int)[[g selectionIndexPaths] count] : 0; }
int sga_grid_view_selected_at(int a_id, int k) { SGAGridView *g = sga_grid_of(a_id); NSArray *r = g ? sga_grid_selected_models(g) : @[]; return k >= 1 && k <= (int)[r count] ? [r[(NSUInteger)k - 1] intValue] : 0; }

void sga_grid_view_scroll_to(int a_id, int i)
{
	SGAGridView *g = sga_grid_of(a_id);
	NSInteger v = g && i >= 1 ? sga_grid_view_index(g, i - 1) : -1;
	if (v >= 0) [g scrollToItemsAtIndexPaths:[NSSet setWithObject:[NSIndexPath indexPathForItem:v inSection:0]] scrollPosition:NSCollectionViewScrollPositionNearestHorizontalEdge];
}

void sga_grid_view_set_filter(int a_id, const char *a_text)
{
	SGAGridView *g = sga_grid_of(a_id);
	if (!g) return;
	NSArray *l_before = sga_grid_selected_models(g);
	g->filter = sga_string(a_text);
	sga_grid_refresh(g);
	if (![sga_grid_selected_models(g) isEqualToArray:l_before]) [g tellSelection];   /* a hidden selection is deselected, with 50 */
}

int sga_grid_view_shown_count(int a_id) { SGAGridView *g = sga_grid_of(a_id); return g ? (int)(g->shown ? [g->shown count] : [g->items count]) : 0; }

/* As the user: a click on item `i', a Command-click adding it, a double click opening it;
   whether its picture has loaded. */
static void sga_grid_user_select(int a_id, int i, BOOL an_extend)
{
	SGAGridView *g = sga_grid_of(a_id);
	if (!g) return;
	sga_grid_view_select(a_id, i, an_extend);
	[g tellSelection];
}
void sga_test_activate_item(int a_id, int i) { SGAGridView *g = sga_grid_of(a_id); NSInteger v = g && i >= 1 ? sga_grid_view_index(g, i - 1) : -1; if (v >= 0) [g openAt:v]; }
/* Item `i''s picture is loaded and, when its cell is on screen, that cell shows it. */
int sga_test_item_picture_ready(int a_id, int i)
{
	SGAGridView *g = sga_grid_of(a_id);
	if (!g || i < 1 || i > (int)[g->items count]) return 0;
	SGAGridItem *it = g->items[(NSUInteger)i - 1];
	if (!it->image) return 0;
	NSInteger v = sga_grid_view_index(g, i - 1);
	SGAGridCell *c = v >= 0 ? (SGAGridCell *)[g itemAtIndexPath:[NSIndexPath indexPathForItem:v inSection:0]] : nil;
	return !c || [c->picture_view image] == it->image ? 1 : 0;
}

/* ------------------------------------------------------------------ 1p-b: focus and Escape */

/* The keyboard focus to widget `a_id', from code. */
void sga_widget_focus(int a_id)
{
	NSView *v = sga_core(a_id);
	if ([v window]) [[v window] makeFirstResponder:v];
}

/* As the user pressing Escape in field `a_id': the suggestion list closes if it shows, else 55. */
void sga_test_field_escape(int a_id)
{
	NSControl *f = sga_get(a_id);
	if ([[f window] firstResponder] != [f currentEditor] || ![f currentEditor]) [[f window] makeFirstResponder:f];
	[s_target control:f textView:(NSTextView *)[f currentEditor] doCommandBySelector:@selector(cancelOperation:)];
}

/* ------------------------------------------------------------------ 1v-b: the code editor */

/* A code editor: an NSTextView in monospace with no wrapping, a gutter of line numbers (an
   NSRulerView), auto-indent on Return (the line's leading white space), and Tab and
   Shift+Tab indenting or outdenting the selected lines (by a tab, or by spaces). The user's
   caret moves send 52 (a = line, b = column, from 1, in characters); code is quiet. */
@interface SGACodeView : NSTextView
{
@public
	int tab_width;
	BOOL spaces;
	/* 1v-e-2: the bracket pair shown, as two UTF-16 ranges, and the areas last drawn for it
	   (view coordinates), which are what gets redrawn when the pair goes. */
	BOOL pair_on;
	NSRange pair[2];
	NSRect pair_drawn[2];
	/* 1v-e-3: folding. `numbers' and `folding' say what the gutter shows; `marks' are the
	   lines that start a fold (ascending); `hidden' are the closed folds' hidden lines as
	   UTF-16 ranges, ascending and apart, each from the start of the line after a fold's
	   first line to the start of the line after its last (or the end of the text). */
	BOOL numbers_off;
	BOOL folding;
	int *marks;
	int mark_count;
	NSRange *hidden;
	int hidden_count;
}
@end

@interface SGACodeView () <NSLayoutManagerDelegate>
@end

static NSString *sga_code_indent_unit(SGACodeView *v) { return v->spaces ? [@"" stringByPaddingToLength:(NSUInteger)v->tab_width withString:@" " startingAtIndex:0] : @"\t"; }

/* Line (from 1) and column (from 1, in characters) of UTF-16 offset `k'. */
static void sga_code_line_column(NSString *s, NSUInteger k, int *a_line, int *a_column)
{
	NSUInteger l_start = 0;
	k = MIN(k, [s length]);
	*a_line = (int)sga_line_breaks(s, 0, k, &l_start) + 1;
	*a_column = (int)sga_code_point_index([s substringWithRange:NSMakeRange(l_start, k - l_start)], k - l_start) + 1;
}

/* 1v-e-3: the first hidden range of `v' that ends after UTF-16 offset `k' (hidden_count when none). */
static int sga_code_hidden_after(SGACodeView *v, NSUInteger k)
{
	int l_low = 0, l_high = v->hidden_count;
	while (l_low < l_high) {
		int l_mid = (l_low + l_high) / 2;
		if (NSMaxRange(v->hidden[l_mid]) <= k) l_low = l_mid + 1; else l_high = l_mid;
	}
	return l_low;
}

/* The hidden range of `v' that holds offset `k', or -1. */
static int sga_code_hidden_at(SGACodeView *v, NSUInteger k)
{
	int i = sga_code_hidden_after(v, k);
	return i < v->hidden_count && NSLocationInRange(k, v->hidden[i]) ? i : -1;
}

/* Does line `n' (from 1) start a fold, by the marks last set? */
static BOOL sga_code_has_mark(SGACodeView *v, int n)
{
	int l_low = 0, l_high = v->mark_count;
	while (l_low < l_high) {
		int l_mid = (l_low + l_high) / 2;
		if (v->marks[l_mid] == n) return YES;
		if (v->marks[l_mid] < n) l_low = l_mid + 1; else l_high = l_mid;
	}
	return NO;
}

@implementation SGACodeView
- (void)tellCaret
{
	int l, c;
	sga_code_line_column([self string], [self selectedRange].location, &l, &c);
	sga_push(52, sga_id_of(self), l, c, 0);
	sga_wake();
}
/* 1v-e-3: an offset in hidden lines goes to the nearest shown place on the side it came
   from: the end of the fold's first line when moving back, the start of the line after
   the fold when moving on. AppKit's own arrow keys and clicks already step over hidden
   lines (no room, no glyphs); this keeps anything else out too. */
- (NSUInteger)shownOffset:(NSUInteger)k from:(NSUInteger)an_old
{
	int i = sga_code_hidden_at(self, k);
	if (i < 0) return k;
	return k >= an_old || hidden[i].location == 0 ? NSMaxRange(hidden[i]) : hidden[i].location - 1;
}
- (void)setSelectedRanges:(NSArray<NSValue *> *)r affinity:(NSSelectionAffinity)a stillSelecting:(BOOL)s
{
	sga_colors_flush();   /* 1v-b: the view takes what it types with from the text at the caret */
	if (hidden_count) {
		NSUInteger l_old = [self selectedRange].location;
		NSMutableArray<NSValue *> *l_shown = [NSMutableArray arrayWithCapacity:[r count]];
		for (NSValue *v in r) {
			NSRange x = [v rangeValue];
			NSUInteger l_start = [self shownOffset:x.location from:l_old];
			NSUInteger l_end = x.length ? [self shownOffset:NSMaxRange(x) from:l_old] : l_start;
			[l_shown addObject:[NSValue valueWithRange:NSMakeRange(l_start, l_end >= l_start ? l_end - l_start : 0)]];
		}
		r = l_shown;
	}
	[super setSelectedRanges:r affinity:a stillSelecting:s];
	if (!s && !s_suppress && [self window]) [self tellCaret];
}
/* 1v-e-3: the hidden lines get null glyphs, and their line breaks no advance, so they take
   no room and the text stays whole. */
- (NSUInteger)layoutManager:(NSLayoutManager *)m shouldGenerateGlyphs:(const CGGlyph *)g properties:(const NSGlyphProperty *)p characterIndexes:(const NSUInteger *)c font:(NSFont *)f forGlyphRange:(NSRange)r
{
	if (!hidden_count || !r.length) return 0;
	int i = sga_code_hidden_after(self, c[0]);
	if (i >= hidden_count || hidden[i].location >= c[r.length - 1] + 1) return 0;
	NSGlyphProperty *q = malloc(sizeof(NSGlyphProperty) * r.length);
	for (NSUInteger j = 0; j < r.length; j++) {
		while (i < hidden_count && NSMaxRange(hidden[i]) <= c[j]) i++;
		q[j] = i < hidden_count && NSLocationInRange(c[j], hidden[i]) ? NSGlyphPropertyNull : p[j];
	}
	[m setGlyphs:g properties:q characterIndexes:c font:f forGlyphRange:r];
	free(q);
	return r.length;
}
- (NSControlCharacterAction)layoutManager:(NSLayoutManager *)m shouldUseAction:(NSControlCharacterAction)an_action forControlCharacterAtIndex:(NSUInteger)k
{
	(void)m;
	return hidden_count && sga_code_hidden_at(self, k) >= 0 ? NSControlCharacterActionZeroAdvancement : an_action;
}
/* The characters changed: the hidden ranges move with the text, so what was hidden stays
   hidden until the editor sets the closed folds again. Called from the text storage's edit
   notification, before the layout manager hears of the edit. */
- (void)foldsFollowEdit:(NSRange)an_edited change:(NSInteger)a_change
{
	if (!hidden_count) return;
	NSUInteger a = an_edited.location, b = an_edited.location + an_edited.length - a_change, l_new_end = NSMaxRange(an_edited);
	int n = 0;
	for (int i = 0; i < hidden_count; i++) {
		NSUInteger s = hidden[i].location, z = NSMaxRange(hidden[i]);
		/* text put at a range's start or end stays out of it */
		s = s < a ? s : (s >= b ? s + a_change : l_new_end);
		z = z <= a ? z : (z >= b ? z + a_change : l_new_end);
		if (z > s) hidden[n++] = NSMakeRange(s, z - s);
	}
	hidden_count = n;
}
/* The "…" after a closed fold's first line. */
- (void)drawFoldMarksInRect:(NSRect)a_rect
{
	NSLayoutManager *m = [self layoutManager];
	NSRange l_glyphs = [m glyphRangeForBoundingRectWithoutAdditionalLayout:a_rect inTextContainer:[self textContainer]];
	NSRange l_chars = [m characterRangeForGlyphRange:l_glyphs actualGlyphRange:NULL];
	NSDictionary *l_attributes = @{NSFontAttributeName: [self font] ?: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular], NSForegroundColorAttributeName: [NSColor secondaryLabelColor]};
	NSSize l_size = [@"…" sizeWithAttributes:l_attributes];
	for (int i = sga_code_hidden_after(self, l_chars.location); i < hidden_count && hidden[i].location <= NSMaxRange(l_chars) + 1; i++) {
		if (hidden[i].location == 0) continue;
		NSUInteger g = [m glyphIndexForCharacterAtIndex:hidden[i].location - 1];
		NSRect l_used = [m lineFragmentUsedRectForGlyphAtIndex:g effectiveRange:NULL];
		NSRect l_box = NSMakeRect(NSMaxX(l_used) + [self textContainerOrigin].x + 6, NSMinY(l_used) + [self textContainerOrigin].y + 1, l_size.width + 8, NSHeight(l_used) - 2);
		if (!NSIntersectsRect(l_box, a_rect)) continue;
		[[NSColor quaternaryLabelColor] setFill];
		[[NSBezierPath bezierPathWithRoundedRect:l_box xRadius:3 yRadius:3] fill];
		[@"…" drawAtPoint:NSMakePoint(NSMinX(l_box) + 4, NSMidY(l_box) - l_size.height / 2) withAttributes:l_attributes];
	}
}
/* 1v-e-2: the bracket tint. Drawn here, under the text and the selection, from the kept
   ranges: it is no attribute of the text (no color or trait query sees it), no undo step and
   no change. A layout manager's temporary attributes would do the same, but the tint must go
   inside the text storage's own edit notification, and there the layout manager still has
   the old text; so the view draws it and only forgets its ranges there. */
- (NSRect)pairRect:(NSRange)r
{
	NSLayoutManager *m = [self layoutManager];
	__block NSRect l_all = NSZeroRect;
	NSRange g = [m glyphRangeForCharacterRange:r actualCharacterRange:NULL];
	[m enumerateEnclosingRectsForGlyphRange:g withinSelectedGlyphRange:NSMakeRange(NSNotFound, 0) inTextContainer:[self textContainer] usingBlock:^(NSRect a_rect, BOOL *a_stop) {
		(void)a_stop;
		l_all = NSUnionRect(l_all, a_rect);
	}];
	return NSIsEmptyRect(l_all) ? NSZeroRect : NSOffsetRect(l_all, [self textContainerOrigin].x, [self textContainerOrigin].y);
}
- (void)drawViewBackgroundInRect:(NSRect)a_rect
{
	[super drawViewBackgroundInRect:a_rect];
	if (hidden_count) [self drawFoldMarksInRect:a_rect];
	if (!pair_on) return;
	NSUInteger n = [[self textStorage] length];
	[[[NSColor controlAccentColor] colorWithAlphaComponent:0.3] setFill];
	for (int i = 0; i < 2; i++) {
		if (NSMaxRange(pair[i]) > n) continue;
		NSRect f = [self pairRect:pair[i]];
		pair_drawn[i] = f;
		if (NSIntersectsRect(f, a_rect)) NSRectFillUsingOperation(f, NSCompositingOperationSourceOver);
	}
}
- (void)hidePair
{
	if (!pair_on) return;
	pair_on = NO;
	for (int i = 0; i < 2; i++) if (!NSIsEmptyRect(pair_drawn[i])) [self setNeedsDisplayInRect:pair_drawn[i]];
	pair_drawn[0] = pair_drawn[1] = NSZeroRect;
}
- (void)showPair:(NSRange)a_first second:(NSRange)a_second
{
	[self hidePair];
	pair[0] = a_first; pair[1] = a_second;
	pair_on = YES;
	for (int i = 0; i < 2; i++) { pair_drawn[i] = [self pairRect:pair[i]]; [self setNeedsDisplayInRect:pair_drawn[i]]; }
}
/* Command+Shift+\ (the bar, with Shift, on a US keyboard): 56, go to the matching bracket. */
- (BOOL)performKeyEquivalent:(NSEvent *)e
{
	NSEventModifierFlags f = [e modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask & ~(NSEventModifierFlagCapsLock | NSEventModifierFlagNumericPad | NSEventModifierFlagFunction);
	NSString *c = [e charactersIgnoringModifiers];
	if ([[self window] firstResponder] == self && f == (NSEventModifierFlagCommand | NSEventModifierFlagShift)
		&& ([e keyCode] == 42 || [c isEqualToString:@"\\"] || [c isEqualToString:@"|"])) {
		sga_push(56, sga_id_of(self), 0, 0, 0);
		sga_wake();
		return YES;
	}
	/* 1v-e-3: Command+Option+[ and ], while folding is shown: 57 with the caret's line, b 1
	   the fold key, 2 the unfold key. By key code: with Option the characters change. */
	if ([[self window] firstResponder] == self && folding && f == (NSEventModifierFlagCommand | NSEventModifierFlagOption)
		&& ([e keyCode] == 33 || [e keyCode] == 30)) {
		int l, k;
		sga_code_line_column([self string], [self selectedRange].location, &l, &k);
		sga_push(57, sga_id_of(self), l, [e keyCode] == 30 ? 2 : 1, 0);
		sga_wake();
		return YES;
	}
	return [super performKeyEquivalent:e];
}
/* Return keeps the line's indentation. */
- (void)insertNewline:(id)sender
{
	NSString *s = [self string];
	NSRange l_line = [s lineRangeForRange:NSMakeRange([self selectedRange].location, 0)];
	NSUInteger k = l_line.location;
	while (k < NSMaxRange(l_line) && k < [self selectedRange].location && ([s characterAtIndex:k] == ' ' || [s characterAtIndex:k] == '\t')) k++;
	NSString *l_indent = [s substringWithRange:NSMakeRange(l_line.location, k - l_line.location)];
	[super insertNewline:sender];
	if ([l_indent length]) [self insertText:l_indent replacementRange:[self selectedRange]];
}
/* The lines the selection touches, as one range. */
- (NSRange)selectedLines { return [[self string] lineRangeForRange:[self selectedRange]]; }
- (void)shiftLines:(BOOL)a_in
{
	NSRange r = [self selectedLines];
	NSString *s = [[self string] substringWithRange:r];
	NSMutableArray<NSString *> *l_lines = [[s componentsSeparatedByString:@"\n"] mutableCopy];
	BOOL l_last_empty = [s hasSuffix:@"\n"];
	if (l_last_empty) [l_lines removeLastObject];
	NSString *u = sga_code_indent_unit(self);
	for (NSUInteger i = 0; i < [l_lines count]; i++) {
		NSString *x = l_lines[i];
		if (a_in) x = [u stringByAppendingString:x];
		else if ([x hasPrefix:@"\t"]) x = [x substringFromIndex:1];
		else { NSUInteger n = 0; while (n < (NSUInteger)tab_width && n < [x length] && [x characterAtIndex:n] == ' ') n++; x = [x substringFromIndex:n]; }
		l_lines[i] = x;
	}
	NSString *l_new = [[l_lines componentsJoinedByString:@"\n"] stringByAppendingString:l_last_empty ? @"\n" : @""];
	if ([self shouldChangeTextInRange:r replacementString:l_new]) {
		[[self textStorage] replaceCharactersInRange:r withString:l_new];
		[self didChangeText];
		[self setSelectedRange:NSMakeRange(r.location, [l_new length])];
	}
}
/* Tab: indents the selected lines when the selection spans a line break; else a tab or spaces. */
- (void)insertTab:(id)sender
{
	(void)sender;
	NSRange r = [self selectedRange];
	if (r.length > 0 && [[[self string] substringWithRange:r] rangeOfString:@"\n"].location != NSNotFound) [self shiftLines:YES];
	else [self insertText:sga_code_indent_unit(self) replacementRange:r];
}
- (void)insertBacktab:(id)sender { (void)sender; [self shiftLines:NO]; }
@end

/* The gutter: each shown line's number, right-aligned, beside its first line fragment; and,
   while folding is shown (1v-e-3), a column of markers at its right: a triangle pointing down
   beside a line that starts an open fold, to the right beside one whose fold is closed. Lines
   hidden in a closed fold take no room and get nothing here; the numbers skip them. */
@interface SGALineRuler : NSRulerView
@end
static NSDictionary *sga_ruler_attributes(void) { return @{NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular], NSForegroundColorAttributeName: [NSColor secondaryLabelColor]}; }
/* The width of the marker column: a line's height, while folding is shown. */
static CGFloat sga_ruler_marker_width(SGACodeView *v) { return v && v->folding ? ceil([[v layoutManager] defaultLineHeightForFont:[v font] ?: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]]) : 0; }
static void sga_ruler_draw_marker(NSRect a_cell, BOOL a_closed)
{
	CGFloat s = MIN(NSWidth(a_cell), NSHeight(a_cell)) * 0.3, cx = NSMidX(a_cell), cy = NSMidY(a_cell);
	NSBezierPath *b = [NSBezierPath bezierPath];
	/* flipped: y grows downward */
	if (a_closed) { [b moveToPoint:NSMakePoint(cx - s * 0.6, cy - s)]; [b lineToPoint:NSMakePoint(cx + s * 0.6, cy)]; [b lineToPoint:NSMakePoint(cx - s * 0.6, cy + s)]; }
	else { [b moveToPoint:NSMakePoint(cx - s, cy - s * 0.6)]; [b lineToPoint:NSMakePoint(cx + s, cy - s * 0.6)]; [b lineToPoint:NSMakePoint(cx, cy + s * 0.6)]; }
	[b closePath];
	[[NSColor secondaryLabelColor] setFill];
	[b fill];
}
@implementation SGALineRuler
- (SGACodeView *)codeView { id t = [self clientView]; return [t isKindOfClass:[SGACodeView class]] ? t : nil; }
- (CGFloat)requiredThickness
{
	NSString *s = [(NSTextView *)[self clientView] string];
	SGACodeView *v = [self codeView];
	CGFloat l_marks = sga_ruler_marker_width(v);
	if (v && v->numbers_off) return 2 + l_marks;
	NSUInteger n = sga_line_breaks(s, 0, [s length], NULL) + 1;
	NSString *l_widest = [NSString stringWithFormat:@"%lu", (unsigned long)MAX(n, (NSUInteger)99)];
	return ceil([l_widest sizeWithAttributes:sga_ruler_attributes()].width) + 14 + l_marks;
}
/* Calls `a_block' with each shown line in the visible part: its number, the UTF-16 range of
   the line, and its row (its first line fragment, in this ruler's coordinates). */
- (void)eachShownLine:(void (^)(int a_line, NSRange a_range, NSRect a_row, BOOL *a_stop))a_block
{
	NSTextView *t = (NSTextView *)[self clientView];
	SGACodeView *v = [self codeView];
	NSLayoutManager *m = [t layoutManager];
	NSString *s = [t string];
	NSRect l_visible = [[t enclosingScrollView] documentVisibleRect];
	NSRange l_glyphs = [m glyphRangeForBoundingRect:l_visible inTextContainer:[t textContainer]];
	NSRange l_chars = [m characterRangeForGlyphRange:l_glyphs actualGlyphRange:NULL];
	int l_line = (int)sga_line_breaks(s, 0, l_chars.location, NULL) + 1;
	NSUInteger k = l_chars.location;
	BOOL l_stop = NO;
	for (;;) {
		int i = v && v->hidden_count ? sga_code_hidden_at(v, MIN(k, [s length])) : -1;
		if (i >= 0) {   /* hidden lines: skip them, counting their line breaks */
			NSUInteger z = NSMaxRange(v->hidden[i]);
			l_line += (int)sga_line_breaks(s, k, z, NULL);
			k = z;
			if (k >= [s length] && ![s hasSuffix:@"\n"]) break;
			continue;
		}
		NSRange l_line_range = [s lineRangeForRange:NSMakeRange(MIN(k, [s length]), 0)];
		BOOL l_extra = k >= [s length];   /* the empty last line, after a final line break, or empty text */
		NSRect f = l_extra ? [m extraLineFragmentRect] : [m lineFragmentRectForGlyphAtIndex:[m glyphIndexForCharacterAtIndex:l_line_range.location] effectiveRange:NULL];
		CGFloat y = NSMinY(f) + [t textContainerInset].height - NSMinY(l_visible);
		if (y > NSHeight([self bounds])) break;
		a_block(l_line, l_line_range, NSMakeRect(0, y, [self ruleThickness], NSHeight(f)), &l_stop);
		if (l_stop || l_extra) break;
		if (NSMaxRange(l_line_range) >= [s length]) {
			if (![s hasSuffix:@"\n"]) break;
		}
		else if (NSMaxRange(l_line_range) > NSMaxRange(l_chars)) break;
		k = NSMaxRange(l_line_range);
		l_line++;
	}
}
- (void)drawHashMarksAndLabelsInRect:(NSRect)a_rect
{
	(void)a_rect;
	SGACodeView *v = [self codeView];
	NSDictionary *a = sga_ruler_attributes();
	CGFloat w = [self ruleThickness], l_marks = sga_ruler_marker_width(v);
	BOOL l_numbers = !(v && v->numbers_off);
	[self eachShownLine:^(int a_line, NSRange a_range, NSRect a_row, BOOL *a_stop) {
		(void)a_stop;
		if (l_numbers) {
			NSString *l_label = [NSString stringWithFormat:@"%d", a_line];
			NSSize z = [l_label sizeWithAttributes:a];
			[l_label drawAtPoint:NSMakePoint(w - l_marks - z.width - 6, NSMinY(a_row) + (NSHeight(a_row) - z.height) / 2) withAttributes:a];
		}
		if (l_marks > 0 && sga_code_has_mark(v, a_line))
			sga_ruler_draw_marker(NSMakeRect(w - l_marks, NSMinY(a_row), l_marks, NSHeight(a_row)), v->hidden_count && sga_code_hidden_at(v, NSMaxRange(a_range)) >= 0);
	}];
}
/* The line whose marker is at `p' (this ruler's coordinates), or 0. */
- (int)markerLineAt:(NSPoint)p
{
	SGACodeView *v = [self codeView];
	CGFloat l_marks = sga_ruler_marker_width(v);
	__block int l_found = 0;
	if (l_marks <= 0 || p.x < [self ruleThickness] - l_marks) return 0;
	[self eachShownLine:^(int a_line, NSRange a_range, NSRect a_row, BOOL *a_stop) {
		(void)a_range;
		if (p.y >= NSMinY(a_row) && p.y < NSMaxY(a_row)) { if (sga_code_has_mark(v, a_line)) l_found = a_line; *a_stop = YES; }
	}];
	return l_found;
}
- (void)mouseDown:(NSEvent *)e
{
	int n = [self markerLineAt:[self convertPoint:[e locationInWindow] fromView:nil]];
	if (n > 0) { sga_push(57, sga_id_of([self clientView]), n, 0, 0); sga_wake(); }
	else [super mouseDown:e];
}
@end

static SGACodeView *sga_code_of(int a_id) { id t = s_inner[a_id]; return [t isKindOfClass:[SGACodeView class]] ? t : nil; }
static BOOL sga_is_code_view(id t) { return [t isKindOfClass:[SGACodeView class]]; }

int sga_code_editor(void)
{
	NSScrollView *l_scroll = [[NSScrollView alloc] init];
	SGACodeView *t = [[SGACodeView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
	t->tab_width = 4;
	[t setRichText:YES];
	[t setImportsGraphics:NO];
	[t setAllowsUndo:YES];
	[t setFont:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]];
	[t setAutomaticQuoteSubstitutionEnabled:NO];
	[t setAutomaticDashSubstitutionEnabled:NO];
	[t setAutomaticTextReplacementEnabled:NO];
	[t setAutomaticSpellingCorrectionEnabled:NO];
	[t setContinuousSpellCheckingEnabled:NO];
	[t setSmartInsertDeleteEnabled:NO];
	[t setDelegate:(id<NSTextViewDelegate>)s_target];
	/* no wrapping: the text runs on, the view scrolls across */
	[t setHorizontallyResizable:YES];
	[t setVerticallyResizable:YES];
	[t setMaxSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
	[t setAutoresizingMask:NSViewWidthSizable];
	[[t textContainer] setWidthTracksTextView:NO];
	[[t textContainer] setContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];
	[l_scroll setDocumentView:t];
	[l_scroll setBorderType:NSBezelBorder];
	[l_scroll setHasVerticalScroller:YES];
	[l_scroll setHasHorizontalScroller:YES];
	[l_scroll setAutohidesScrollers:YES];
	SGALineRuler *r = [[SGALineRuler alloc] initWithScrollView:l_scroll orientation:NSVerticalRuler];
	[r setClientView:t];
	[l_scroll setVerticalRulerView:r];
	[l_scroll setHasVerticalRuler:YES];
	[l_scroll setRulersVisible:YES];
	[[NSNotificationCenter defaultCenter] addObserverForName:NSTextDidChangeNotification object:t queue:nil usingBlock:^(NSNotification *n) { (void)n; [r setRuleThickness:[r requiredThickness]]; [r setNeedsDisplay:YES]; }];
	[[NSNotificationCenter defaultCenter] addObserverForName:NSViewBoundsDidChangeNotification object:[l_scroll contentView] queue:nil usingBlock:^(NSNotification *n) { (void)n; [r setNeedsDisplay:YES]; }];
	[r setRuleThickness:[r requiredThickness]];
	/* 1v-e-2: any change of the characters, by the user, by code or by undo, drops the bracket
	   tint. 1v-e-3: and moves the hidden lines with the text, before the layout manager hears
	   of the edit and makes the glyphs again. */
	__weak SGACodeView *l_view = t;
	[[NSNotificationCenter defaultCenter] addObserverForName:NSTextStorageDidProcessEditingNotification object:[t textStorage] queue:nil usingBlock:^(NSNotification *n) {
		NSTextStorage *l_storage = [n object];
		if ([l_storage editedMask] & NSTextStorageEditedCharacters) {
			[l_view hidePair];
			[l_view foldsFollowEdit:[l_storage editedRange] change:[l_storage changeInLength]];
		}
	}];
	[[t layoutManager] setDelegate:t];
	NSLayoutConstraint *k = [l_scroll.heightAnchor constraintGreaterThanOrEqualToConstant:64];
	[k setPriority:NSLayoutPriorityDefaultHigh];
	[k setActive:YES];
	int l_id = sga_keep(l_scroll);
	s_inner[l_id] = t;
	return l_id;
}

/* The gutter shows while it has line numbers or fold markers to show. */
static void sga_code_gutter_changed(SGACodeView *t)
{
	NSRulerView *r = [[t enclosingScrollView] verticalRulerView];
	[[t enclosingScrollView] setRulersVisible:!t->numbers_off || t->folding];
	[r setRuleThickness:[r requiredThickness]];
	[r setNeedsDisplay:YES];
}

void sga_code_set_line_numbers(int a_id, int a_on) { SGACodeView *t = sga_code_of(a_id); if (t) { t->numbers_off = a_on == 0; sga_code_gutter_changed(t); } }

void sga_code_set_indent(int a_id, int a_tab_width, int a_spaces)
{
	SGACodeView *t = sga_code_of(a_id);
	if (!t || a_tab_width < 1) return;
	t->tab_width = a_tab_width;
	t->spaces = a_spaces != 0;
	NSMutableParagraphStyle *p = [[NSMutableParagraphStyle alloc] init];
	CGFloat l_char = [@" " sizeWithAttributes:@{NSFontAttributeName: [t font] ?: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular]}].width;
	[p setTabStops:@[]];
	[p setDefaultTabInterval:l_char * a_tab_width];
	[t setDefaultParagraphStyle:p];
	NSMutableDictionary *a = [[t typingAttributes] mutableCopy];
	a[NSParagraphStyleAttributeName] = p;
	[t setTypingAttributes:a];
	sga_colors_flush();
	[[t textStorage] addAttribute:NSParagraphStyleAttributeName value:p range:NSMakeRange(0, [[t textStorage] length])];
}

int sga_text_line_count(int a_id)
{
	NSString *s = [(NSTextView *)s_inner[a_id] string];
	return (int)sga_line_breaks(s, 0, [s length], NULL) + 1;
}

int sga_text_caret_line(int a_id) { NSTextView *t = s_inner[a_id]; int l, c; sga_code_line_column([t string], [t selectedRange].location, &l, &c); return l; }
int sga_text_caret_column(int a_id) { NSTextView *t = s_inner[a_id]; int l, c; sga_code_line_column([t string], [t selectedRange].location, &l, &c); return c; }

/* The UTF-16 range of line `n' (from 1), without its line break; location NSNotFound past the end. */
static NSRange sga_line_range(NSString *s, int n)
{
	unichar l_buffer[1024];
	NSUInteger l_length = [s length], l_start = 0;
	int l = 1;   /* the line that starts at `l_start' */
	for (NSUInteger k = 0; k < l_length; ) {
		NSUInteger c = MIN((NSUInteger)1024, l_length - k);
		[s getCharacters:l_buffer range:NSMakeRange(k, c)];
		for (NSUInteger j = 0; j < c; j++) if (l_buffer[j] == '\n') {
			if (l >= n) return NSMakeRange(l_start, k + j - l_start);
			l++;
			l_start = k + j + 1;
		}
		k += c;
	}
	return l >= n ? NSMakeRange(l_start, l_length - l_start) : NSMakeRange(NSNotFound, 0);
}

const char *sga_text_line_text(int a_id, int n)
{
	NSTextView *t = s_inner[a_id];
	NSRange r = sga_line_range([t string], n);
	return sga_return(Kind_area, r.location == NSNotFound ? @"" : [[t string] substringWithRange:r]);
}

void sga_text_go_to_line(int a_id, int n)
{
	NSTextView *t = s_inner[a_id];
	NSRange r = sga_line_range([t string], n);
	if (r.location == NSNotFound) return;
	s_suppress++;
	[t setSelectedRange:NSMakeRange(r.location, 0)];
	[t scrollRangeToVisible:NSMakeRange(r.location, 0)];
	s_suppress--;
}

/* Characters `a_start' .. `an_end' (from 1, inclusive; an empty range inserts at `a_start')
   become `a_text', selected; quiet. */
void sga_text_replace_range(int a_id, int a_start, int an_end, const char *a_text)
{
	NSTextView *t = s_inner[a_id];
	NSUInteger a = sga_text_offset([t textStorage], a_start - 1), b = an_end >= a_start ? sga_text_offset([t textStorage], an_end) : a;
	NSString *l_new = sga_string(a_text);
	s_suppress++;
	if ([t shouldChangeTextInRange:NSMakeRange(a, b - a) replacementString:l_new]) {
		[[t textStorage] replaceCharactersInRange:NSMakeRange(a, b - a) withString:l_new];
		[t didChangeText];
	}
	[t setSelectedRange:NSMakeRange(a, [l_new length])];
	s_suppress--;
}

/* As the user: `a_text' typed at the caret (%N as Return, %T as Tab); the caret moved to
   (line, column) (52). */
void sga_test_type_into_code(int a_id, const char *a_text)
{
	NSTextView *t = s_inner[a_id];
	NSString *s = sga_string(a_text);
	sga_colors_flush();
	[[t window] makeFirstResponder:t];
	[s enumerateSubstringsInRange:NSMakeRange(0, [s length]) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *c, NSRange r, NSRange e, BOOL *a_stop) {
		(void)r; (void)e; (void)a_stop;
		if ([c isEqualToString:@"\n"]) [t insertNewline:nil];
		else if ([c isEqualToString:@"\t"]) [t insertTab:nil];
		else [t insertText:c replacementRange:[t selectedRange]];
	}];
}

void sga_test_caret_to(int a_id, int a_line, int a_column)
{
	NSTextView *t = s_inner[a_id];
	NSRange r = sga_line_range([t string], a_line);
	if (r.location == NSNotFound) return;
	NSString *l_line = [[t string] substringWithRange:r];
	NSUInteger k = r.location + sga_utf16_offset(l_line, a_column - 1);
	s_suppress++;
	[t setSelectedRange:NSMakeRange(k, 0)];
	s_suppress--;
	if ([t isKindOfClass:[SGACodeView class]]) [(SGACodeView *)t tellCaret];
	else { sga_push(52, sga_id_of(t), a_line, a_column, 0); sga_wake(); }
}

/* 1v-e-2: the bracket pair. Positions from 1 in characters (code points); a range that does
   not lie in the text shows no pair. The tint goes by itself at the next change of the text. */
void sga_code_show_bracket_pair(int a_id, int a_first_start, int a_first_count, int a_second_start, int a_second_count)
{
	SGACodeView *t = sga_code_of(a_id);
	if (!t) return;
	[t hidePair];
	NSTextStorage *m = [t textStorage];
	NSInteger l_count = sga_text_index(m, [m length]);
	if (a_first_start < 1 || a_first_count < 1 || a_second_start < 1 || a_second_count < 1
		|| a_first_start > l_count || a_first_count > l_count - a_first_start + 1
		|| a_second_start > l_count || a_second_count > l_count - a_second_start + 1) return;
	NSUInteger a = sga_text_offset(m, a_first_start - 1), b = sga_text_offset(m, a_first_start - 1 + a_first_count);
	NSUInteger c = sga_text_offset(m, a_second_start - 1), d = sga_text_offset(m, a_second_start - 1 + a_second_count);
	[t showPair:NSMakeRange(a, b - a) second:NSMakeRange(c, d - c)];
}

void sga_code_hide_bracket_pair(int a_id) { SGACodeView *t = sga_code_of(a_id); if (t) [t hidePair]; }

int sga_test_bracket_tint_at(int a_id, int a_position)
{
	SGACodeView *t = sga_code_of(a_id);
	if (!t || !t->pair_on || a_position < 1) return 0;
	NSTextStorage *m = [t textStorage];
	if (a_position > sga_text_index(m, [m length])) return 0;
	NSUInteger k = sga_text_offset(m, a_position - 1);
	return NSLocationInRange(k, t->pair[0]) || NSLocationInRange(k, t->pair[1]);
}

/* As the user pressing Command+Shift+\ in the editor: 56. */
void sga_test_bracket_key(int a_id) { sga_push(56, a_id, 0, 0, 0); sga_wake(); }

/* ------------------------------------------------------------------ 1v-e-3: folding */

void sga_code_set_folding_shown(int a_id, int a_on)
{
	SGACodeView *t = sga_code_of(a_id);
	if (!t) return;
	t->folding = a_on != 0;
	sga_code_gutter_changed(t);
}

void sga_code_set_fold_marks(int a_id, const int *a_lines, int a_count)
{
	SGACodeView *t = sga_code_of(a_id);
	if (!t) return;
	free(t->marks);
	t->marks = NULL;
	t->mark_count = 0;
	if (a_lines && a_count > 0) {
		t->marks = malloc(sizeof(int) * (size_t)a_count);
		memcpy(t->marks, a_lines, sizeof(int) * (size_t)a_count);
		t->mark_count = a_count;
	}
	[[[t enclosingScrollView] verticalRulerView] setNeedsDisplay:YES];
}

/* The glyphs and layout of UTF-16 range `r' are made again (the hidden lines changed there). */
static void sga_code_relayout(SGACodeView *t, NSRange r)
{
	NSLayoutManager *m = [t layoutManager];
	NSUInteger n = [[t textStorage] length];
	if (r.location > n) return;
	r.length = MIN(r.length, n - r.location);
	/* with the line before, whose "…" mark comes or goes */
	if (r.location > 0) { r.location--; r.length++; }
	[m invalidateGlyphsForCharacterRange:r changeInLength:0 actualCharacterRange:NULL];
	[m invalidateLayoutForCharacterRange:r actualCharacterRange:NULL];
}

void sga_code_set_folded_lines(int a_id, const int *a_pairs, int a_count)
{
	SGACodeView *t = sga_code_of(a_id);
	if (!t) return;
	NSString *s = [t string];
	NSUInteger l_length = [s length];
	NSRange *l_new = a_count > 0 ? malloc(sizeof(NSRange) * (size_t)a_count) : NULL;
	int n = 0;
	/* one walk through the text, as the pairs ascend: `k' is where line `l' starts */
	NSUInteger k = 0;
	int l = 1;
	unichar l_buffer[1024];
	NSUInteger l_have = 0, l_at = 0;   /* the buffer holds units l_at .. l_at + l_have */
	for (int i = 0; a_pairs && i < a_count; i++) {
		int l_first = a_pairs[2 * i], l_last = a_pairs[2 * i + 1];
		NSUInteger l_bounds[2];
		BOOL l_ok = l_first >= 1 && l_last > l_first && l_first >= l;
		for (int j = 0; l_ok && j < 2; j++) {
			int l_target = (j == 0 ? l_first : l_last) + 1;   /* the line whose start is wanted */
			while (l < l_target && k < l_length) {
				if (k >= l_at + l_have) { l_at = k; l_have = MIN((NSUInteger)1024, l_length - k); [s getCharacters:l_buffer range:NSMakeRange(l_at, l_have)]; }
				if (l_buffer[k - l_at] == '\n') l++;
				k++;
			}
			if (l < l_target) { if (j == 0) l_ok = NO; else l_bounds[1] = l_length; }   /* the text ends first */
			else l_bounds[j] = k;
		}
		if (l_ok && l_bounds[1] > l_bounds[0] && (n == 0 || l_bounds[0] >= NSMaxRange(l_new[n - 1]))) l_new[n++] = NSMakeRange(l_bounds[0], l_bounds[1] - l_bounds[0]);
	}
	/* what changes: each old range and each new one is laid out again */
	NSRange *l_old = t->hidden;
	int l_old_count = t->hidden_count;
	t->hidden = l_new;
	t->hidden_count = n;
	for (int i = 0; i < l_old_count; i++) sga_code_relayout(t, l_old[i]);
	for (int i = 0; i < n; i++) sga_code_relayout(t, l_new[i]);
	free(l_old);
	[t setNeedsDisplay:YES];
	[[[t enclosingScrollView] verticalRulerView] setNeedsDisplay:YES];
}

void sga_test_press_fold_marker(int a_id, int a_line)
{
	SGACodeView *t = sga_code_of(a_id);
	if (!t || !t->folding || !sga_code_has_mark(t, a_line) || !sga_test_line_is_shown(a_id, a_line)) return;
	sga_push(57, a_id, a_line, 0, 0);
	sga_wake();
}

void sga_test_fold_key(int a_id, int an_unfold)
{
	SGACodeView *t = sga_code_of(a_id);
	int l, c;
	if (!t || !t->folding) return;
	sga_code_line_column([t string], [t selectedRange].location, &l, &c);
	sga_push(57, a_id, l, an_unfold ? 2 : 1, 0);
	sga_wake();
}

int sga_test_line_is_shown(int a_id, int a_line)
{
	SGACodeView *t = sga_code_of(a_id);
	if (!t || a_line < 1) return 0;
	NSRange r = sga_line_range([t string], a_line);
	return r.location != NSNotFound && sga_code_hidden_at(t, r.location) < 0;
}

/* As the user pressing an arrow key in the editor, no modifier: AppKit's own moves, which
   step over hidden lines; 52 when the caret moves. */
void sga_test_code_arrow_key(int a_id, int a_direction)
{
	SGACodeView *t = sga_code_of(a_id);
	static SEL l_moves[4];
	if (!t || a_direction < 1 || a_direction > 4) return;
	if (!l_moves[0]) { l_moves[0] = @selector(moveUp:); l_moves[1] = @selector(moveDown:); l_moves[2] = @selector(moveLeft:); l_moves[3] = @selector(moveRight:); }
	[[t window] makeFirstResponder:t];
	[t doCommandBySelector:l_moves[a_direction - 1]];
}
