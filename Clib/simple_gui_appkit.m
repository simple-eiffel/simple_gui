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
static int s_setting_dark;

@interface SGATarget : NSObject <NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSTabViewDelegate>
{
@public
	NSMutableDictionary<NSValue *, NSMutableArray<NSString *> *> *rows;
}
@end

static int sga_tab_page(NSTabView *t, NSInteger an_item);
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
- (void)tabView:(NSTabView *)a_tabs didSelectTabViewItem:(NSTabViewItem *)an_item { if (!s_suppress) sga_push(13, sga_id_of(a_tabs), sga_tab_page(a_tabs, [a_tabs indexOfTabViewItem:an_item]), 0, 0); }
- (void)controlTextDidChange:(NSNotification *)n { if (!s_suppress) sga_push(2, sga_id_of([n object]), 0, 0, 0); }
/* 1p: leaving a field ends its editing (29), when validation on commit checks it. */
- (void)controlTextDidEndEditing:(NSNotification *)n { sga_suggest_end(sga_id_of([n object])); if (!s_suppress) sga_push(29, sga_id_of([n object]), 0, 0, 0); }
/* 1p: Up, Down, Return and Escape go to the field's suggestion list while it shows. */
- (BOOL)control:(NSControl *)c textView:(NSTextView *)tv doCommandBySelector:(SEL)a_command
{
	(void)tv;
	return sga_suggest_key(sga_id_of(c), a_command);
}
- (void)textDidChange:(NSNotification *)n { if (!s_suppress) sga_push(2, sga_id_of([n object]), 0, 0, 0); }
- (NSMutableArray<NSString *> *)rowsOf:(NSTableView *)t { return rows[[NSValue valueWithNonretainedObject:t]]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return (NSInteger)[[self rowsOf:t] count]; }
- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)r
{
	NSTextField *l_cell = [t makeViewWithIdentifier:@"sga_cell" owner:self];
	(void)c;
	if (!l_cell) { l_cell = [NSTextField labelWithString:@""]; l_cell.identifier = @"sga_cell"; }
	l_cell.stringValue = [self rowsOf:t][(NSUInteger)r];
	l_cell.alignment = sga_start_alignment(t);
	return l_cell;
}
- (void)tableViewSelectionDidChange:(NSNotification *)n
{
	NSTableView *t = [n object];
	/* A user's emptying of the selection is a selection too: row 0. With several rows (1p), the first. */
	NSUInteger l_first = [[t selectedRowIndexes] firstIndex];
	if (!s_suppress) sga_push(4, sga_id_of(t), l_first == NSNotFound ? 0 : (int)l_first + 1, 0, 0);
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

static int sga_run_once(NSDate *a_until)
{
	int n = 0;
	@autoreleasepool {
		NSEvent *e = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:a_until inMode:NSDefaultRunLoopMode dequeue:YES];
		if (e) {
			if ([e type] != NSEventTypeApplicationDefined) [NSApp sendEvent:e];
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

int sga_window(const char *a_title, int a_width, int a_height)
{
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
	NSLayoutConstraint *l_bottom = [v.bottomAnchor constraintEqualToAnchor:l_content.bottomAnchor constant:-l_content->bottom_bar];
	[NSLayoutConstraint activateConstraints:@[
		[v.leadingAnchor constraintEqualToAnchor:l_content.leadingAnchor],
		[v.trailingAnchor constraintEqualToAnchor:l_content.trailingAnchor],
		[v.topAnchor constraintEqualToAnchor:l_content.topAnchor],
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

@interface SGASplit : NSSplitView
{
@public
	NSInteger pending;   /* -1: none; -2: halfway, at the first layout (until set_position) */
}
@end
@implementation SGASplit
- (void)layout
{
	[super layout];
	if (pending != -1 && NSWidth([self bounds]) > 0 && NSHeight([self bounds]) > 0) {
		NSInteger p = pending >= 0 ? pending : (NSInteger)(([self isVertical] ? NSWidth([self bounds]) : NSHeight([self bounds])) / 2);
		pending = -1;
		sga_split_apply(self, p);
	}
}
@end

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
	[s addArrangedSubview:[[NSView alloc] init]];
	[s addArrangedSubview:[[NSView alloc] init]];
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

int sga_tabs(void)
{
	NSTabView *t = [[NSTabView alloc] init];
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
	[NSLayoutConstraint activateConstraints:@[
		[v.leadingAnchor constraintEqualToAnchor:l_holder.leadingAnchor], [v.trailingAnchor constraintEqualToAnchor:l_holder.trailingAnchor],
		[v.topAnchor constraintEqualToAnchor:l_holder.topAnchor], [v.bottomAnchor constraintEqualToAnchor:l_holder.bottomAnchor]]];
	[i setLabel:sga_string(a_title)];
	[i setView:l_holder];
	s_suppress++;
	if (sga_tabs_reversed(t)) [t insertTabViewItem:i atIndex:0]; else [t addTabViewItem:i];
	s_suppress--;
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
	{ NSTabView *t = sga_get(a_tabs); [[t tabViewItemAtIndex:sga_tab_item(t, a_page)] setLabel:sga_string(a_title)]; }
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

int sga_list(void)
{
	NSScrollView *l_scroll = [[NSScrollView alloc] init];
	NSTableView *t = [[NSTableView alloc] init];
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

void sga_list_extend(int a_id, const char *a_text)
{
	NSTableView *t = s_inner[a_id];
	[[s_target rowsOf:t] addObject:sga_string(a_text)];
	s_suppress++;
	[t reloadData];
	s_suppress--;
}

void sga_list_wipe_out(int a_id)
{
	NSTableView *t = s_inner[a_id];
	[[s_target rowsOf:t] removeAllObjects];
	s_suppress++;
	[t reloadData];
	s_suppress--;
}

void sga_list_select(int a_id, int a_row)
{
	NSTableView *t = s_inner[a_id];
	s_suppress++;
	if (a_row <= 0) [t deselectAll:nil];
	else [t selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)(a_row - 1)] byExtendingSelection:NO];
	s_suppress--;
}

int sga_list_selected(int a_id) { return (int)[(NSTableView *)s_inner[a_id] selectedRow] + 1; }

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
}
- (void)wantRowsNear:(NSInteger)a_row;
@end
@implementation SGAGridTable
- (NSInteger)numberOfRowsInTableView:(NSTableView *)a_table { return source_on ? source_count : (NSInteger)[data count]; }

/* Rows wanted (16) for the rows in view plus a viewful either side, those neither held nor
   already asked for; once per range, never for a count of 0. Rows far from the view are
   dropped from the cache. */
- (void)wantRowsNear:(NSInteger)a_row
{
	if (!source_on || source_count <= 0) return;
	NSRange v = [self rowsInRect:[self visibleRect]];
	if (v.length == 0) v = NSMakeRange((NSUInteger)a_row, 40);
	NSInteger l_margin = (NSInteger)MAX(v.length, (NSUInteger)20);
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
	NSTextField *f = [a_table makeViewWithIdentifier:@"sga_grid_cell" owner:self];
	if (!f) {
		f = [NSTextField labelWithString:@""];
		[f setIdentifier:@"sga_grid_cell"];
		[f setLineBreakMode:NSLineBreakByTruncatingTail];
	}
	NSUInteger k = [[a_table tableColumns] indexOfObject:a_column];
	NSArray<NSString *> *l_row = source_on ? cache[@(a_row)] : data[(NSUInteger)a_row];
	if (source_on && !l_row) [self wantRowsNear:a_row];
	[f setStringValue:k < [l_row count] ? l_row[k] : @""];
	[f setAlignment:sga_start_alignment(a_table)];
	return f;
}
- (void)tableViewSelectionDidChange:(NSNotification *)n
{
	if (s_suppress) return;
	NSUInteger l_first = [[self selectedRowIndexes] firstIndex];
	sga_push(4, sga_id_of(self), l_first == NSNotFound ? 0 : (int)l_first + 1, 0, 0);
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
	NSScrollView *l_scroll = [[NSScrollView alloc] init];
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
	[l_scroll setDocumentView:t];
	[l_scroll setHasVerticalScroller:YES];
	[l_scroll setBorderType:NSBezelBorder];
	int l_id = sga_keep(l_scroll);
	s_inner[l_id] = t;
	return l_id;
}

void sga_table_extend(int a_id, const char *a_cells)
{
	SGAGridTable *t = s_inner[a_id];
	[t->data addObject:sga_fields(a_cells)];
	s_suppress++;
	[t reloadData];
	s_suppress--;
}

void sga_table_wipe_out(int a_id)
{
	SGAGridTable *t = s_inner[a_id];
	[t->data removeAllObjects];
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
	s_suppress++;
	[t reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)r] columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [[t tableColumns] count])]];
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
	s_suppress++;
	[t reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)r] columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [[t tableColumns] count])]];
	s_suppress--;
}

void sga_table_scroll_to(int a_id, int a_row)
{
	NSTableView *t = s_inner[a_id];
	if (a_row >= 1 && a_row <= [t numberOfRows]) [t scrollRowToVisible:a_row - 1];
}

void sga_table_set_multiple(int a_id, int a_on) { [(NSTableView *)s_inner[a_id] setAllowsMultipleSelection:a_on != 0]; }

void sga_table_select(int a_id, int a_row, int a_extend)
{
	NSTableView *t = s_inner[a_id];
	s_suppress++;
	if (a_row <= 0) [t deselectAll:nil];
	else [t selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)(a_row - 1)] byExtendingSelection:a_extend != 0];
	s_suppress--;
}

int sga_table_selected_count(int a_id) { return (int)[[(NSTableView *)s_inner[a_id] selectedRowIndexes] count]; }

int sga_table_selected_at(int a_id, int i)
{
	__block int l_seen = 0, l_row = 0;
	[[(NSTableView *)s_inner[a_id] selectedRowIndexes] enumerateIndexesUsingBlock:^(NSUInteger r, BOOL *a_stop) {
		if (++l_seen == i) { l_row = (int)r + 1; *a_stop = YES; }
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
	NSScrollView *l_scroll = [[NSScrollView alloc] init];
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

void sga_group_box_set_title(int a_id, const char *a_title) { [(NSBox *)sga_get(a_id) setTitle:sga_string(a_title)]; }

void sga_group_box_set_content(int a_id, int a_child)
{
	NSBox *b = sga_get(a_id);
	NSView *c = [b contentView];
	NSView *v = sga_get(a_child);
	for (NSView *l_old in [[c subviews] copy]) [l_old removeFromSuperview];
	[v setTranslatesAutoresizingMaskIntoConstraints:NO];
	[c addSubview:v];
	[NSLayoutConstraint activateConstraints:@[
		[v.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:4],
		[v.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-4],
		[v.topAnchor constraintEqualToAnchor:c.topAnchor constant:4],
		[v.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-4]]];
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
   a = the part, 1 = the root). The control does not navigate; the program does. */
@interface SGAPathControl : NSPathControl
@end
@implementation SGAPathControl
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

void sga_path_control_set(int a_id, const char *a_path) { [(NSPathControl *)sga_get(a_id) setURL:[NSURL fileURLWithPath:sga_string(a_path)]]; }
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

static NSRange sga_rich_range(NSTextView *t, int a_start, int an_end)
{
	NSString *s = [[t textStorage] string];
	NSUInteger l_from = sga_utf16_offset(s, a_start - 1), l_to = sga_utf16_offset(s, an_end);
	return NSMakeRange(l_from, l_to > l_from ? l_to - l_from : 0);
}

/* Bold (1), italic (2) or underline (3), on or off, over a range. */
void sga_rich_text_set_trait(int a_id, int a_start, int an_end, int a_trait, int a_on)
{
	NSTextView *t = s_inner[a_id];
	NSTextStorage *m = [t textStorage];
	NSRange r = sga_rich_range(t, a_start, an_end);
	if (r.length == 0) return;
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
	NSRange r = sga_rich_range(t, a_start, an_end);
	if (r.length) [[t textStorage] addAttribute:NSForegroundColorAttributeName value:sga_rgb_color(a_rgb) range:r];
}

void sga_rich_text_set_size(int a_id, int a_start, int an_end, double a_points)
{
	NSTextView *t = s_inner[a_id];
	NSTextStorage *m = [t textStorage];
	NSRange r = sga_rich_range(t, a_start, an_end);
	if (r.length == 0 || a_points <= 0) return;
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
	NSString *s = [[t textStorage] string];
	NSUInteger k = sga_utf16_offset(s, i - 1);
	return k < [s length] ? [[t textStorage] attributesAtIndex:k effectiveRange:NULL] : @{};
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
	NSTextView *t = s_inner[a_id];
	/* A rich text view gives new text its own text color as an attribute: that is the default. */
	BOOL l_default = !c || [c isEqual:[t textColor]] || [c isEqual:[NSColor textColor]] || [c isEqual:[NSColor labelColor]];
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
	return (int)sga_code_point_index([[t textStorage] string], [t selectedRange].location) + 1;
}

int sga_rich_text_selection_end(int a_id)
{
	NSTextView *t = s_inner[a_id];
	NSRange r = [t selectedRange];
	return (int)sga_code_point_index([[t textStorage] string], NSMaxRange(r));
}

void sga_rich_text_select(int a_id, int a_start, int an_end)
{
	NSTextView *t = s_inner[a_id];
	[t setSelectedRange:sga_rich_range(t, a_start, an_end)];
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
void sga_list_scroll_to_row(int a_id, int a_row) { [(NSTableView *)s_inner[a_id] scrollRowToVisible:a_row - 1]; }
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
				if (r >= 0) *a_row = [c isKindOfClass:[SGATree class]] ? ((SGANode *)[(SGATree *)c itemAtRow:r])->number : (int)r + 1;
			}
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
	[s enumerateIndexesUsingBlock:^(NSUInteger r, BOOL *a_stop) { if (++k == i) { l_row = (int)r + 1; *a_stop = YES; } }];
	return l_row;
}

/* As a user: row `a_row' added to the selection (Command-click). */
void sga_test_extend_list_selection(int a_id, int a_row)
{
	[(NSTableView *)s_inner[a_id] selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)(a_row - 1)] byExtendingSelection:YES];
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
		[t setSelectedRange:l_all];
		[t insertText:sga_string(a_text) replacementRange:l_all];
		return;
	}
	NSTextField *f = sga_text_field(a_id);
	[f setStringValue:sga_string(a_text)];
	[[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidChangeNotification object:f];
}

void sga_test_choose(int a_id, int a_row)
{
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
	   first would send two). */
	[t selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)(a_row - 1)] byExtendingSelection:NO];
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

int sga_snapshot(int a_window, const char *a_path)
{
	NSWindow *w = sga_get(a_window);
	NSView *v = [[w contentView] superview];
	__block int l_ok = 0;
	[v layoutSubtreeIfNeeded];
	[v setNeedsDisplay:YES];
	[v displayIfNeeded];
	[[w effectiveAppearance] performAsCurrentDrawingAppearance:^{
		NSBitmapImageRep *r = [v bitmapImageRepForCachingDisplayInRect:[v bounds]];
		[v cacheDisplayInRect:[v bounds] toBitmapImageRep:r];
		l_ok = [[r representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:sga_string(a_path) atomically:YES] ? 1 : 0;
	}];
	return l_ok;
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
}
@end
@implementation SGADockPanel
@end

static void sga_dock_press_name(SGADock *d, SGADockPanel *p);

@interface SGADockStrip : NSView
{
@public
	__weak SGADock *dock;
	int side;
	NSMutableArray<NSValue *> *rects;   /* each name's rectangle, in the panels' order on the side */
}
@end

@interface SGADock : NSView <NSTabViewDelegate>
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
}
- (void)rebuild:(int)a_side;
@end

static BOOL sga_dock_long_vertical(int a_side) { return a_side <= 2; }

static NSArray<SGADockPanel *> *sga_dock_visible(SGADock *d, int a_side)
{
	NSMutableArray *r = [NSMutableArray array];
	for (SGADockPanel *p in d->order[a_side]) if (p->shown) [r addObject:p];
	return r;
}

/* The room a side takes across: none when it shows nothing, the strip when collapsed. */
static CGFloat sga_dock_depth(SGADock *d, int a_side)
{
	if (![sga_dock_visible(d, a_side) count]) return 0;
	return d->collapsed[a_side] ? SGA_DOCK_STRIP : d->size[a_side];
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
	for (SGADockPanel *p in sga_dock_visible(dock, side)) {
		NSSize s = [p->title sizeWithAttributes:l_att];
		NSRect l_rect = l_down ? NSMakeRect(0, at, SGA_DOCK_STRIP, s.width + 12) : NSMakeRect(at, 0, s.width + 12, SGA_DOCK_STRIP);
		[rects addObject:[NSValue valueWithRect:l_rect]];
		if (l_down) {
			NSGraphicsContext *g = [NSGraphicsContext currentContext];
			[g saveGraphicsState];
			NSAffineTransform *t = [NSAffineTransform transform];
			[t translateXBy:NSMidX(l_rect) - s.height / 2 yBy:NSMaxY(l_rect) - 6];
			[t rotateByDegrees:-90];
			[t concat];
			[p->title drawAtPoint:NSZeroPoint withAttributes:l_att];
			[g restoreGraphicsState];
		} else
			[p->title drawAtPoint:NSMakePoint(NSMinX(l_rect) + 6, (SGA_DOCK_STRIP - s.height) / 2) withAttributes:l_att];
		at += (l_down ? l_rect.size.height : l_rect.size.width) + 4;
	}
}
- (void)mouseDown:(NSEvent *)e
{
	NSPoint p = [self convertPoint:[e locationInWindow] fromView:nil];
	NSArray<SGADockPanel *> *l_shown = sga_dock_visible(dock, side);
	for (NSUInteger i = 0; i < [rects count] && i < [l_shown count]; i++)
		if (NSPointInRect(p, [rects[i] rectValue])) { sga_dock_press_name(dock, l_shown[i]); return; }
}
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
	if (!sga_dock_depth(self, a_side) || collapsed[a_side]) return NSZeroRect;
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
		BOOL l_any = f.size.width > 0 && f.size.height > 0;
		[side_view[s] setHidden:!l_any || collapsed[s]];
		[strip[s] setHidden:!l_any || !collapsed[s]];
		[chevron[s] setHidden:!l_any || collapsed[s]];
		[side_view[s] setFrame:f];
		[strip[s] setFrame:f];
		[strip[s] setNeedsDisplay:YES];
		/* the chevron at the side's corner nearest the center's top */
		NSRect c = NSMakeRect(s == 2 ? NSMinX(f) + 2 : NSMaxX(f) - 18, NSMinY(f) + 2, 16, 16);
		[chevron[s] setFrame:c];
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
/* Edges take the press; everything else belongs to the views under it. */
- (NSView *)hitTest:(NSPoint)p
{
	NSPoint l_local = [self convertPoint:p fromView:[self superview]];
	for (int s = 1; s <= 4; s++) if (NSPointInRect(l_local, [self edgeOf:s])) return self;
	return [super hitTest:p];
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
	if (!dragging) return;
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
			[i setLabel:p->title];
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
	[tabs[a_side] setHidden:!tabbed[a_side]];
	[stack[a_side] setHidden:tabbed[a_side]];
	[strip[a_side] setNeedsDisplay:YES];
	[self setNeedsLayout:YES];
}
@end

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
		d->tabs[s] = [[NSTabView alloc] initWithFrame:NSZeroRect];
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
		[d addSubview:d->strip[s]];
		[d addSubview:d->chevron[s]];
	}
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
		[p->header.trailingAnchor constraintLessThanOrEqualToAnchor:b.trailingAnchor constant:-22],
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
	if (i != NSNotFound) [[d->tabs[p->side] tabViewItemAtIndex:i] setLabel:p->title];
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
