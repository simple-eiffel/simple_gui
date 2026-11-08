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
enum { Kind_label, Kind_button, Kind_field, Kind_role, Kind_path, Kind_tree, Kind_count };
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

@interface SGAContent : NSView
@end
@implementation SGAContent
- (BOOL)isFlipped { return YES; }
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)a_rect { [[NSColor windowBackgroundColor] setFill]; NSRectFill(a_rect); }
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
		CGContextDrawImage(l_cg, CGRectMake(0, 0, b.size.width, b.size.height), image);
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
	sga_push(8, sga_id_of(self), sga_gdk_key(e), (l_char >= 0xF700 && l_char <= 0xF8FF) ? 0 : l_char,
		sga_modifiers([e modifierFlags]) * 256);
}
- (void)setFrameSize:(NSSize)a_size
{
	NSSize l_old = [self frame].size;
	[super setFrameSize:a_size];
	if (!NSEqualSizes(l_old, a_size)) sga_push(9, sga_id_of(self), (int)a_size.width, (int)a_size.height, 0);
}
@end

/* ------------------------------------------------ targets and delegates */

static int s_suppress;
static int s_setting_dark;

@interface SGATarget : NSObject <NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
{
@public
	NSMutableDictionary<NSValue *, NSMutableArray<NSString *> *> *rows;
}
@end

@implementation SGATarget
- (instancetype)init { if ((self = [super init])) rows = [NSMutableDictionary dictionary]; return self; }
- (void)clicked:(id)a_sender { sga_push(1, sga_id_of(a_sender), 0, 0, 0); }
- (void)activated:(id)a_sender { sga_push(3, sga_id_of(a_sender), 0, 0, 0); }
- (void)menuItem:(NSMenuItem *)a_item { sga_push(5, 0, (int)[a_item tag], 0, 0); }
- (void)controlTextDidChange:(NSNotification *)n { if (!s_suppress) sga_push(2, sga_id_of([n object]), 0, 0, 0); }
- (NSMutableArray<NSString *> *)rowsOf:(NSTableView *)t { return rows[[NSValue valueWithNonretainedObject:t]]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)t { return (NSInteger)[[self rowsOf:t] count]; }
- (NSView *)tableView:(NSTableView *)t viewForTableColumn:(NSTableColumn *)c row:(NSInteger)r
{
	NSTextField *l_cell = [t makeViewWithIdentifier:@"sga_cell" owner:self];
	(void)c;
	if (!l_cell) { l_cell = [NSTextField labelWithString:@""]; l_cell.identifier = @"sga_cell"; }
	l_cell.stringValue = [self rowsOf:t][(NSUInteger)r];
	return l_cell;
}
- (void)tableViewSelectionDidChange:(NSNotification *)n
{
	NSTableView *t = [n object];
	if (!s_suppress && [t selectedRow] >= 0) sga_push(4, sga_id_of(t), (int)[t selectedRow] + 1, 0, 0);
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
	[l_app setSubmenu:[[NSMenu alloc] initWithTitle:s_app_name]];
	[l_bar addItem:l_app];
	[NSApp setMainMenu:l_bar];
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

/* ------------------------------------------------------- windows, layout */

int sga_window(const char *a_title, int a_width, int a_height)
{
	NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(160, 160, a_width, a_height)
		styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
		backing:NSBackingStoreBuffered defer:NO];
	[w setReleasedWhenClosed:NO];
	[w setTitle:sga_string(a_title)];
	[w setContentView:[[SGAContent alloc] initWithFrame:NSMakeRect(0, 0, a_width, a_height)]];
	[w setDelegate:s_target];
	return sga_keep(w);
}

void sga_window_set_content(int a_window, int a_child)
{
	NSWindow *w = sga_get(a_window);
	NSView *l_content = [w contentView];
	NSView *v = sga_get(a_child);
	for (NSView *l_old in [[l_content subviews] copy]) [l_old removeFromSuperview];
	[v setTranslatesAutoresizingMaskIntoConstraints:NO];
	[l_content addSubview:v];
	[NSLayoutConstraint activateConstraints:@[
		[v.leadingAnchor constraintEqualToAnchor:l_content.leadingAnchor],
		[v.trailingAnchor constraintEqualToAnchor:l_content.trailingAnchor],
		[v.topAnchor constraintEqualToAnchor:l_content.topAnchor],
		[v.bottomAnchor constraintEqualToAnchor:l_content.bottomAnchor]]];
}

void sga_window_show(int a_window) { [(NSWindow *)sga_get(a_window) orderFront:nil]; }
void sga_window_close(int a_window) { [(NSWindow *)sga_get(a_window) orderOut:nil]; }
void sga_window_set_title(int a_window, const char *a_title) { [(NSWindow *)sga_get(a_window) setTitle:sga_string(a_title)]; }

/* A container: a flipped wrapper holding a stack or grid inside leading, top,
   trailing and bottom margin constraints (12 px, as the API states). */
static int sga_wrap(NSView *a_inner, CGFloat a_margin)
{
	SGAWrapper *w = [[SGAWrapper alloc] init];
	[a_inner setTranslatesAutoresizingMaskIntoConstraints:NO];
	[w addSubview:a_inner];
	int l_id = sga_keep(w);
	s_inner[l_id] = a_inner;
	s_margins[l_id][0] = [a_inner.leadingAnchor constraintEqualToAnchor:w.leadingAnchor constant:a_margin];
	s_margins[l_id][1] = [a_inner.topAnchor constraintEqualToAnchor:w.topAnchor constant:a_margin];
	s_margins[l_id][2] = [w.trailingAnchor constraintEqualToAnchor:a_inner.trailingAnchor constant:a_margin];
	s_margins[l_id][3] = [w.bottomAnchor constraintEqualToAnchor:a_inner.bottomAnchor constant:a_margin];
	[NSLayoutConstraint activateConstraints:@[s_margins[l_id][0], s_margins[l_id][1], s_margins[l_id][2], s_margins[l_id][3]]];
	return l_id;
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

int sga_stack(int a_vertical, int a_spacing)
{
	NSStackView *s = [[NSStackView alloc] init];
	[s setOrientation:a_vertical ? NSUserInterfaceLayoutOrientationVertical : NSUserInterfaceLayoutOrientationHorizontal];
	[s setDistribution:NSStackViewDistributionFill];
	[s setAlignment:a_vertical ? NSLayoutAttributeLeading : NSLayoutAttributeTop];
	[s setSpacing:a_spacing];
	return sga_wrap(s, 12);
}

/* Children fill the cross axis, as GTK boxes do; `a_stretch' children take the
   main axis's spare room. */
void sga_stack_extend(int a_stack, int a_child, int a_stretch)
{
	NSStackView *s = s_inner[a_stack];
	NSView *v = sga_get(a_child);
	BOOL l_vertical = [s orientation] == NSUserInterfaceLayoutOrientationVertical;
	NSLayoutConstraintOrientation l_main = l_vertical ? NSLayoutConstraintOrientationVertical : NSLayoutConstraintOrientationHorizontal;
	[v setContentHuggingPriority:a_stretch ? 1 : NSLayoutPriorityDefaultHigh forOrientation:l_main];
	sga_keep_natural_size(v, a_stretch);
	[s addArrangedSubview:v];
	/* Children fill across the stack, except buttons, which keep their natural width as
	   GTK's do (halign START). */
	if ([v isKindOfClass:[NSButton class]]) {}
	else if (l_vertical) [[v.widthAnchor constraintEqualToAnchor:s.widthAnchor] setActive:YES];
	else [[v.heightAnchor constraintEqualToAnchor:s.heightAnchor] setActive:YES];
}

void sga_stack_set_spacing(int a_stack, int a_spacing) { [(NSStackView *)s_inner[a_stack] setSpacing:a_spacing]; }

int sga_grid(void)
{
	NSGridView *g = [NSGridView gridViewWithNumberOfColumns:0 rows:0];
	[g setRowSpacing:6];
	[g setColumnSpacing:12];
	return sga_wrap(g, 12);
}

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
}

void sga_grid_set_spacing(int a_grid, int a_row_gap, int a_column_gap)
{
	NSGridView *g = s_inner[a_grid];
	[g setRowSpacing:a_row_gap];
	[g setColumnSpacing:a_column_gap];
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
void sga_label_set(int a_id, const char *a_text) { [(NSTextField *)sga_get(a_id) setStringValue:sga_string(a_text)]; }
const char *sga_label_get(int a_id) { return sga_return(Kind_label, [(NSTextField *)sga_get(a_id) stringValue]); }

int sga_button(const char *a_text)
{
	return sga_keep([NSButton buttonWithTitle:sga_string(a_text) target:s_target action:@selector(clicked:)]);
}
void sga_button_set(int a_id, const char *a_text) { [(NSButton *)sga_get(a_id) setTitle:sga_string(a_text)]; }
const char *sga_button_get(int a_id) { return sga_return(Kind_button, [(NSButton *)sga_get(a_id) title]); }

int sga_field(void)
{
	NSTextField *f = [NSTextField textFieldWithString:@""];
	[f setDelegate:s_target];
	[f setTarget:s_target];
	[f setAction:@selector(activated:)];
	return sga_keep(f);
}

void sga_field_set(int a_id, const char *a_text)
{
	s_suppress++;
	[(NSTextField *)sga_get(a_id) setStringValue:sga_string(a_text)];
	s_suppress--;
}

const char *sga_field_get(int a_id) { return sga_return(Kind_field, [(NSTextField *)sga_get(a_id) stringValue]); }
void sga_field_set_placeholder(int a_id, const char *a_text) { [(NSTextField *)sga_get(a_id) setPlaceholderString:sga_string(a_text)]; }

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

/* ----------------------------------------------------------------- common */

void sga_set_enabled(int a_id, int a_on)
{
	id o = sga_core(a_id);
	if ([o isKindOfClass:[NSControl class]]) [(NSControl *)o setEnabled:a_on != 0];
}

int sga_is_enabled(int a_id)
{
	id o = sga_core(a_id);
	return [o isKindOfClass:[NSControl class]] ? ([(NSControl *)o isEnabled] ? 1 : 0) : 1;
}

void sga_set_visible(int a_id, int a_on)
{
	id o = sga_get(a_id);
	if ([o isKindOfClass:[NSWindow class]]) { if (a_on) [(NSWindow *)o orderFront:nil]; else [(NSWindow *)o orderOut:nil]; }
	else [(NSView *)o setHidden:a_on == 0];
}

int sga_is_visible(int a_id)
{
	id o = sga_get(a_id);
	if ([o isKindOfClass:[NSWindow class]]) return [(NSWindow *)o isVisible] ? 1 : 0;
	return [(NSView *)o isHidden] ? 0 : 1;
}

void sga_set_direction(int a_id, int a_direction)
{
	id l_object = sga_get(a_id);
	if ([l_object isKindOfClass:[NSWindow class]]) l_object = [(NSWindow *)l_object contentView];
	NSView *v = l_object;
	id l_core = sga_core(a_id);
	NSUserInterfaceLayoutDirection l_layout = a_direction == 2 ? NSUserInterfaceLayoutDirectionRightToLeft
		: a_direction == 1 ? NSUserInterfaceLayoutDirectionLeftToRight : [NSApp userInterfaceLayoutDirection];
	[v setUserInterfaceLayoutDirection:l_layout];
	if (l_core != v) [(NSView *)l_core setUserInterfaceLayoutDirection:l_layout];
	if ([l_core isKindOfClass:[NSTextField class]]) {
		NSTextField *f = (NSTextField *)l_core;
		[f setBaseWritingDirection:a_direction == 2 ? NSWritingDirectionRightToLeft
			: a_direction == 1 ? NSWritingDirectionLeftToRight : NSWritingDirectionNatural];
		[f setAlignment:NSTextAlignmentNatural];
	}
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
		NSAccessibilitySliderRole: @"slider", NSAccessibilityTextAreaRole: @"text-box"};
	return l_names[a_role] ?: @"generic";
}

const char *sga_accessible_role(int a_id) { return sga_return(Kind_role, sga_role_name([sga_accessible(a_id) accessibilityRole])); }

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
   it), and tagged sRGB so macOS colour-manages it (spike mac_color). */
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

int sga_scale_factor(int a_id)
{
	NSWindow *w = [(NSView *)sga_get(a_id) window];
	CGFloat f = w ? [w backingScaleFactor] : [[NSScreen mainScreen] backingScaleFactor];
	return f < 1 ? 1 : (int)lround(f);
}

int sga_width(int a_id)
{
	NSView *v = sga_get(a_id);
	int w = (int)[v bounds].size.width;
	return w > 0 ? w : ([v isKindOfClass:[SGACanvas class]] ? (int)((SGACanvas *)v)->wanted.width : 0);
}

int sga_height(int a_id)
{
	NSView *v = sga_get(a_id);
	int h = (int)[v bounds].size.height;
	return h > 0 ? h : ([v isKindOfClass:[SGACanvas class]] ? (int)((SGACanvas *)v)->wanted.height : 0);
}

/* ------------------------------------------------------------------ menus */

static NSString *sga_key_of(NSString *a_shortcut, NSEventModifierFlags *a_mask)
{
	NSString *l_key = @"";
	*a_mask = 0;
	for (NSString *l_part in [[a_shortcut lowercaseString] componentsSeparatedByString:@"+"]) {
		if ([l_part isEqualToString:@"primary"] || [l_part isEqualToString:@"command"]) *a_mask |= NSEventModifierFlagCommand;
		else if ([l_part isEqualToString:@"shift"]) *a_mask |= NSEventModifierFlagShift;
		else if ([l_part isEqualToString:@"alt"] || [l_part isEqualToString:@"option"]) *a_mask |= NSEventModifierFlagOption;
		else if ([l_part isEqualToString:@"control"] || [l_part isEqualToString:@"ctrl"]) *a_mask |= NSEventModifierFlagControl;
		else if ([l_part isEqualToString:@"comma"]) l_key = @",";
		else if ([l_part length]) l_key = l_part;
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
	[[NSApp mainMenu] addItem:l_top];
	return (__bridge void *)m;   /* the main menu keeps it alive */
}

/* Roles go where a Mac user looks: About, Settings and Quit move to the application
   menu (and still come back as menu events, so the application decides); the edit
   roles go through the responder chain, so text fields get them with no Eiffel code. */
void sga_menu_add_item(void *a_menu, const char *a_text, const char *a_shortcut, int a_item_id, int a_role)
{
	NSMenu *m = (__bridge NSMenu *)a_menu;
	NSMenu *l_app = [[[NSApp mainMenu] itemAtIndex:0] submenu];
	NSString *l_text = sga_string(a_text), *l_shortcut = sga_string(a_shortcut);
	NSMenuItem *i;
	switch (a_role) {
		case 1:
			i = sga_item([NSString stringWithFormat:@"About %@", s_app_name], @selector(menuItem:), s_target, l_shortcut);
			[i setTag:a_item_id];
			[l_app insertItem:i atIndex:0];
			break;
		case 2:
			i = sga_item(@"Settings…", @selector(menuItem:), s_target, [l_shortcut length] ? l_shortcut : @"primary+comma");
			[i setTag:a_item_id];
			[l_app addItem:i];
			break;
		case 3:
			if ([l_app numberOfItems] > 0) [l_app addItem:[NSMenuItem separatorItem]];
			i = sga_item([NSString stringWithFormat:@"Quit %@", s_app_name], @selector(menuItem:), s_target, @"primary+q");
			[i setTag:a_item_id];
			[l_app addItem:i];
			break;
		case 10: [m addItem:sga_item(l_text, @selector(undo:), nil, l_shortcut)]; break;
		case 11: [m addItem:sga_item(l_text, @selector(redo:), nil, l_shortcut)]; break;
		case 12: [m addItem:sga_item(l_text, @selector(cut:), nil, l_shortcut)]; break;
		case 13: [m addItem:sga_item(l_text, @selector(copy:), nil, l_shortcut)]; break;
		case 14: [m addItem:sga_item(l_text, @selector(paste:), nil, l_shortcut)]; break;
		case 15: [m addItem:sga_item(l_text, @selector(selectAll:), nil, l_shortcut)]; break;
		default:
			i = sga_item(l_text, @selector(menuItem:), s_target, l_shortcut);
			[i setTag:a_item_id];
			[m addItem:i];
	}
}

void sga_menu_add_separator(void *a_menu) { [(__bridge NSMenu *)a_menu addItem:[NSMenuItem separatorItem]]; }

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

/* ------------------------------------------------------------ test driver */

void sga_test_click(int a_id) { [(NSButton *)sga_core(a_id) performClick:nil]; }

void sga_test_type(int a_id, const char *a_text)
{
	NSTextField *f = sga_core(a_id);
	[f setStringValue:sga_string(a_text)];
	[[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidChangeNotification object:f];
}

void sga_test_choose(int a_id, int a_row)
{
	NSTableView *t = s_inner[a_id];
	[t deselectAll:nil];
	[t selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)(a_row - 1)] byExtendingSelection:NO];
}

static NSMenuItem *sga_find_item(NSMenu *a_menu, int a_tag)
{
	for (NSMenuItem *i in [a_menu itemArray]) {
		if ([i action] == @selector(menuItem:) && [i tag] == a_tag) return i;
		if ([i submenu]) { NSMenuItem *f = sga_find_item([i submenu], a_tag); if (f) return f; }
	}
	return nil;
}

void sga_test_menu(int a_item_id)
{
	NSMenuItem *i = sga_find_item([NSApp mainMenu], a_item_id);
	if (i) [[i menu] performActionForItemAtIndex:[[i menu] indexOfItem:i]];
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

static void sga_describe(id a_element, int a_depth, NSMutableString *a_out)
{
	id l_role_value = sga_ax(a_element, @selector(accessibilityRole), NSAccessibilityRoleAttribute);
	NSString *l_role = [l_role_value isKindOfClass:[NSString class]] ? l_role_value : nil;
	NSString *l_name = sga_role_name(l_role);
	int l_next = a_depth;
	if ([l_role length] && ![l_name isEqualToString:@"generic"]) {
		id l_label = sga_ax(a_element, @selector(accessibilityLabel), NSAccessibilityDescriptionAttribute);
		id l_title = sga_ax(a_element, @selector(accessibilityTitle), NSAccessibilityTitleAttribute);
		id l_value = sga_ax(a_element, @selector(accessibilityValue), NSAccessibilityValueAttribute);
		NSString *l_text = ([l_label isKindOfClass:[NSString class]] && [l_label length]) ? l_label
			: ([l_title isKindOfClass:[NSString class]] && [l_title length]) ? l_title
			: ([l_value isKindOfClass:[NSString class]] ? l_value : @"");
		for (int i = 0; i < a_depth; i++) [a_out appendString:@"  "];
		[a_out appendFormat:@"%@: %@\n", l_name, l_text];
		l_next = a_depth + 1;
	}
	id l_children = sga_ax(a_element, @selector(accessibilityChildren), NSAccessibilityChildrenAttribute);
	if (a_depth < 16 && [l_children isKindOfClass:[NSArray class]]) for (id c in l_children) sga_describe(c, l_next, a_out);
}

const char *sga_describe_accessibility(int a_window)
{
	NSMutableString *l_text = [NSMutableString stringWithString:@"application: "];
	NSWindow *w = sga_get(a_window);
	[l_text appendFormat:@"%@\n", [w title]];
	for (id c in [[w contentView] accessibilityChildren]) sga_describe(c, 1, l_text);
	return sga_return(Kind_tree, l_text);
}
