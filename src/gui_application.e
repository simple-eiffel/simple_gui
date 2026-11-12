note
	description: "[
		The one GUI application, on the GUI processor (the root processor: GTK and AppKit
		run on the main thread). `run' turns the native loop and fires each widget's
		agents from the polled queue; nothing ever calls into Eiffel from C.
		Workers reach the GUI only through `mailbox' plus their own GUI_WAKE.
	]"

class
	GUI_APPLICATION

inherit
	GUI_SHARED

create
	make

feature {NONE} -- Initialization

	make (a_name, a_id: READABLE_STRING_GENERAL)
			-- Start the toolkit for application `a_name', identified as `a_id'
			-- (such as "org.simple-eiffel.demo").
		require
			only_one: not has_application
			named: not a_name.is_empty
			identified: not a_id.is_empty
		local
			l_n, l_i: C_STRING
		do
			name := a_name.to_string_32
			identifier := a_id.to_string_32
			create widgets.make (32)
			create windows.make (2)
			create message_actions.make
			create appearance_changed_actions.make
			create window_closed_actions.make
			create menu.make
			create pills.make
			create timers.make (4)
			create notification_actions.make (2)
			create last_notification.make_empty
			create clipboard
			create dialogs
			create mailbox.make
			l_n := backend.to_c (a_name)
			l_i := backend.to_c (a_id)
			is_available := backend.init (l_n.item, l_i.item)
			if is_available then
				backend.start_heartbeat (Heartbeat_ms)
			end
			application_cell.put (Current)
		ensure
			current_application: has_application and then application = Current
			not_running: not is_running
		end

feature -- Access

	name: STRING_32

	identifier: STRING_32

	menu: GUI_MENU_MODEL
			-- The application's menus.

	dialogs: GUI_DIALOGS

	mailbox: separate GUI_MAILBOX
			-- Where workers put messages for the GUI.

	windows: ARRAYED_LIST [GUI_WINDOW]
			-- Open windows.

	message_actions: GUI_ACTIONS [TUPLE [tag: INTEGER; payload: STRING_32]]
			-- Run for each worker message, on the GUI processor.

	new_message_tag: INTEGER
			-- A mailbox tag no one else has (1v-e-1): always negative, and different on
			-- every call. A tag a class fixes for itself as a constant (the picture
			-- loader's) is positive, so the two kinds never meet. Ask on the GUI processor
			-- and hand the number to the worker that will post with it.
		do
			last_message_tag := last_message_tag - 1
			Result := last_message_tag
		ensure
			negative: Result < 0
			new: Result < old last_message_tag
		end

	last_message_tag: INTEGER
			-- The tag `new_message_tag' gave last; 0 before the first.

	appearance_changed_actions: GUI_ACTIONS [TUPLE [dark: BOOLEAN]]

	window_closed_actions: GUI_ACTIONS [TUPLE [window: GUI_WINDOW]]
			-- Run after a window closed, with that window: the controls of what it held
			-- are gone. A widget that asked the application to call it lets go here.

	help_actions: GUI_ACTIONS [TUPLE [topic: STRING_32; widget: detachable GUI_WIDGET]]
			-- 1u: run when the user asks for help (F1; Command+? on macOS), with the nearest
			-- `help_topic' up from the focused widget and the widget that has it (empty and
			-- Void: none; Void also when the user asked about the window itself). With none
			-- set, a widget's reference pill tip shows instead.
		attribute
			create Result.make
		end
			-- Run when the system switches between light and dark.

	pills: GUI_PILLS
			-- The application's reference pills (1l), put on widgets by code.

	clipboard: GUI_CLIPBOARD
			-- The system clipboard (1m).

	appearance: INTEGER
			-- `Appearance_system' (the default), `Appearance_light' or `Appearance_dark'.

	Appearance_system: INTEGER = 0
	Appearance_light: INTEGER = 1
	Appearance_dark: INTEGER = 2

	Heartbeat_ms: INTEGER = 250

feature -- Status

	is_available: BOOLEAN
			-- Did the toolkit start (is there a display)?

	is_running: BOOLEAN

	pills_shown: BOOLEAN
			-- Are the reference pills drawn on their widgets?

	is_dark: BOOLEAN
			-- Is the system appearance dark?
		require
			available: is_available
		do
			Result := backend.is_dark
		end

feature -- Timers (1m)

	every (a_ms: INTEGER; an_action: PROCEDURE): GUI_TIMER
			-- Run `an_action' every `a_ms' milliseconds, on the GUI processor, until canceled.
		require
			gui_thread: is_gui_thread
			positive: a_ms > 0
		do
			last_timer_id := last_timer_id + 1
			create Result.make (last_timer_id, a_ms, True, an_action)
			timers.force (Result, Result.id)
		ensure
			active: Result.is_active and Result.is_repeating
		end

	after (a_ms: INTEGER; an_action: PROCEDURE): GUI_TIMER
			-- Run `an_action' once, `a_ms' milliseconds from now, on the GUI processor.
		require
			gui_thread: is_gui_thread
			positive: a_ms > 0
		do
			last_timer_id := last_timer_id + 1
			create Result.make (last_timer_id, a_ms, False, an_action)
			timers.force (Result, Result.id)
		ensure
			active: Result.is_active and not Result.is_repeating
		end

feature -- Animation (1x)

	animation_clock: GUI_ANIMATION_CLOCK
			-- The shared clock every animation runs on (Larry's decision A, 2026-11-12): it
			-- decides every value, and the backend only shows it.
		once ("OBJECT")
			create Result.make (agent backend.start_frame_ticks, agent backend.stop_frame_ticks,
				agent reduces_motion, agent run_later)
		end

	animation_duration: INTEGER
			-- How long an animation runs unless told otherwise, in milliseconds.
		do
			if is_animation_duration_set then
				Result := animation_duration_chosen
			else
				Result := Default_animation_duration
			end
		end

	Default_animation_duration: INTEGER = 200
			-- `animation_duration' until a program sets another.

	set_animation_duration (a_ms: INTEGER)
			-- Run animations `a_ms' long unless told otherwise.
		require
			non_negative: a_ms >= 0
		do
			animation_duration_chosen := a_ms
			is_animation_duration_set := True
		ensure
			set: animation_duration = a_ms
		end

	reduces_motion: BOOLEAN
			-- Does the system ask for reduced motion now (Windows' "Show animations" off,
			-- GTK's gtk-enable-animations off, macOS's Reduce motion)? While it does, every
			-- animation completes at once. A test may stand in for the system.
		do
			if attached motion_override as al_override then
				Result := al_override.item
			else
				Result := backend.motion_reduced
			end
		end

	set_reduces_motion_for_tests (a_on: BOOLEAN)
			-- Tests: answer `reduces_motion' with `a_on', whatever the system says.
		do
			create motion_override.put (a_on)
		ensure
			overridden: reduces_motion = a_on
		end

	clear_reduces_motion_for_tests
			-- Tests: let the system answer `reduces_motion' again.
		do
			motion_override := Void
		end

feature -- Desktop notifications (1o)

	last_notification: STRING_32
			-- The title and body of the notification sent most recently, as "title%Nbody" (tests).

	notify (a_title, a_body: READABLE_STRING_GENERAL)
			-- Show a desktop notification (outside the program's windows).
		require
			gui_thread: is_gui_thread
			titled: not a_title.is_empty
		do
			send_notification (a_title, a_body, 0)
		end

	notify_with_action (a_title, a_body: READABLE_STRING_GENERAL; an_action: PROCEDURE)
			-- A desktop notification; `an_action' runs, on the GUI processor, if the user clicks it.
		require
			gui_thread: is_gui_thread
			titled: not a_title.is_empty
		do
			notification_actions.extend (an_action)
			send_notification (a_title, a_body, notification_actions.count)
		end

feature -- Pick and drop (1q)

	pebble_in_flight: detachable ANY
			-- What the user has picked and not yet dropped.

	is_picking: BOOLEAN
		do
			Result := pebble_in_flight /= Void
		end

feature -- Appearance (1m)

	set_appearance (an_appearance: INTEGER)
			-- Light or dark whatever the system says, or follow the system again; fires
			-- `appearance_changed_actions' as a change of the system's does.
		require
			gui_thread: is_gui_thread
			known: an_appearance >= Appearance_system and an_appearance <= Appearance_dark
		do
			appearance := an_appearance
			inspect an_appearance
			when Appearance_light then
				backend.set_dark (False)
			when Appearance_dark then
				backend.set_dark (True)
			else
				backend.follow_system_appearance
			end
		ensure
			set: appearance = an_appearance
		end

feature -- Reference pills

	set_pills_shown (a_shown: BOOLEAN)
			-- Show or hide every widget's reference pill; each shows its definition as it is now.
		require
			gui_thread: is_gui_thread
		do
			pills_shown := a_shown
			if a_shown then
				across widgets as ic loop
					ic.send_pill
				end
			end
			backend.pills_show (a_shown)
		ensure
			set: pills_shown = a_shown
		end

	toggle_pills
			-- Show the pills if hidden, hide them if shown (the View menu's item).
		require
			gui_thread: is_gui_thread
		do
			set_pills_shown (not pills_shown)
		ensure
			flipped: pills_shown = not old pills_shown
		end

feature -- Theme colors

	Color_window_background: INTEGER = 1
	Color_text: INTEGER = 2
	Color_secondary_text: INTEGER = 3
	Color_accent: INTEGER = 4
	Color_selection: INTEGER = 5
	Color_separator: INTEGER = 6

	system_color (a_role: INTEGER): NATURAL_32
			-- The theme's color for `a_role' as 0xRRGGBB; it follows light and dark, so a canvas
			-- can draw to match the window around it. The program's own value when
			-- `set_theme_color' gave one (1w), unless the system's contrast setting is on.
		require
			available: is_available
			known: is_theme_role (a_role)
		do
			if has_theme_color (a_role) and then not backend.is_high_contrast then
				if is_dark then
					Result := theme_darks [a_role].to_natural_32
				else
					Result := theme_lights [a_role].to_natural_32
				end
			else
				Result := backend.system_color (a_role).to_natural_32
			end
		ensure
			rgb: Result <= 0xFFFFFF
		end

	is_theme_role (a_role: INTEGER): BOOLEAN
		do
			Result := a_role >= Color_window_background and a_role <= Color_separator
		ensure
			definition: Result = (a_role >= Color_window_background and a_role <= Color_separator)
		end

	has_theme_color (a_role: INTEGER): BOOLEAN
			-- Did the program give its own color for `a_role' (`set_theme_color')?
		require
			known: is_theme_role (a_role)
		do
			Result := theme_lights [a_role] >= 0
		end

	set_theme_color (a_role: INTEGER; a_rgb, a_dark_rgb: NATURAL_32)
			-- Use `a_rgb' (and `a_dark_rgb' in the dark appearance) for `a_role' in place of the
			-- system's color: `system_color' answers it, styles that name the role follow it,
			-- and the toolkit shows it where it lets a program change the theme. The system's
			-- contrast setting wins: while it is on, the system's colors are used.
		require
			gui_thread: is_gui_thread
			available: is_available
			known: is_theme_role (a_role)
			rgb: a_rgb <= 0xFFFFFF and a_dark_rgb <= 0xFFFFFF
		do
			theme_lights [a_role] := a_rgb.to_integer_32
			theme_darks [a_role] := a_dark_rgb.to_integer_32
			send_theme_color (a_role)
			restyle_all
		ensure
			set: has_theme_color (a_role)
			answered: not is_high_contrast implies system_color (a_role) = (if is_dark then a_dark_rgb else a_rgb end)
		end

	reset_theme_color (a_role: INTEGER)
			-- Go back to the system's color for `a_role'.
		require
			gui_thread: is_gui_thread
			available: is_available
			known: is_theme_role (a_role)
		do
			theme_lights [a_role] := -1
			theme_darks [a_role] := -1
			send_theme_color (a_role)
			restyle_all
		ensure
			reset: not has_theme_color (a_role)
		end

	set_accent_color (a_rgb, a_dark_rgb: NATURAL_32)
			-- The program's accent (role `Color_accent'), on the controls that show one: default
			-- buttons, checks, radios, switches, sliders, progress bars, selections and the focus
			-- ring, where the toolkit allows.
		require
			gui_thread: is_gui_thread
			available: is_available
			rgb: a_rgb <= 0xFFFFFF and a_dark_rgb <= 0xFFFFFF
		do
			set_theme_color (Color_accent, a_rgb, a_dark_rgb)
		ensure
			set: has_theme_color (Color_accent)
		end

feature -- Style classes (1w)

	define_style_class (a_name: READABLE_STRING_GENERAL; a_style: GUI_STYLE)
			-- Make `a_name' mean `a_style' (as it is now; later changes to `a_style' need another
			-- call). Every widget that has the class shows it at once.
		require
			gui_thread: is_gui_thread
			named: not a_name.is_empty
		do
			style_classes.force (a_style.twin, a_name.to_string_32)
			across widgets as ic loop
				if ic.has_style_class (a_name) then
					ic.restyle
				end
			end
		ensure
			defined: attached style_class (a_name) as al_style and then al_style.is_equal (a_style)
		end

	style_class (a_name: READABLE_STRING_GENERAL): detachable GUI_STYLE
			-- The style that class `a_name' means; Void when it is not defined.
		do
			Result := style_classes.item (a_name.to_string_32)
		end

feature -- Fonts (1w)

	load_font (a_path: PATH): ARRAYED_LIST [STRING_32]
			-- Load the font file at `a_path' (TTF, OTF or a collection) for this program only.
			-- The family names it adds, which GUI_STYLE.set_font_family takes from now on; empty
			-- when the file cannot be loaded.
		require
			gui_thread: is_gui_thread
			available: is_available
		local
			l_c: C_STRING
			l_names: STRING_32
		do
			l_c := backend.to_c (a_path.name)
			l_names := backend.from_c (backend.font_load (l_c.item))
			create Result.make (2)
			if not l_names.is_empty then
				across l_names.split ('%/31/') as ic loop
					if not ic.is_empty then
						Result.extend (ic)
					end
				end
			end
		ensure
			usable: across Result as ic all has_font_family (ic) end
		end

	has_font_family (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- Can text be shown in family `a_name' (installed, or loaded by `load_font')?
		require
			available: is_available
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_name)
			Result := backend.font_family_available (l_c.item)
		end

feature -- Contrast (1w)

	is_high_contrast: BOOLEAN
			-- Is the system's contrast setting on (Windows High Contrast, GTK's HighContrast
			-- theme, macOS Increase Contrast)? Style colors, backgrounds and shadows are then
			-- left out; fonts, sizes, padding and borders still show.
		require
			available: is_available
		do
			Result := backend.is_high_contrast
		end

	low_contrast_warned: BOOLEAN
			-- Did a styled widget's text and background measure below 4.5:1 (WCAG 2's minimum
			-- for body text)? A workbench build says so once on standard error.

feature -- Basic operations

	run
			-- Turn the loop until `quit'.
		require
			available: is_available
			not_running: not is_running
		do
			from
				is_running := True
			until
				not is_running
			loop
				process_events (Heartbeat_ms)
			end
		ensure
			stopped: not is_running
		end

	quit
			-- Stop `run' after this turn.
		do
			is_running := False
		ensure
			stopped: not is_running
		end

	process_events (a_ms: INTEGER)
			-- Turn the loop for up to `a_ms' milliseconds, then fire the queued events.
		require
			available: is_available
			non_negative: a_ms >= 0
		do
			backend.pump (a_ms)
			drain_queue
		end

feature {GUI_WIDGET, GUI_TEST_DRIVER} -- Registration and dispatch

	register (a_widget: GUI_WIDGET)
		do
			widgets.force (a_widget, a_widget.id)
			if attached {GUI_WINDOW} a_widget as al_window then
				windows.extend (al_window)
			end
		ensure
			registered: widgets.has (a_widget.id)
		end

	window_closed (a_window: GUI_WINDOW)
			-- `a_window' closed; quit after the last.
		do
			windows.prune_all (a_window)
			window_closed_actions.call ([a_window])
			if windows.is_empty then
				quit
			end
		ensure
			gone: not windows.has (a_window)
		end

	drain_queue
			-- Fire every queued event.
		local
			l_type, l_id, l_a, l_b, l_c: INTEGER
		do
			from
			until
				not backend.next ($l_type, $l_id, $l_a, $l_b, $l_c)
			loop
				inspect l_type
				when 5 then
					menu.invoke (l_a)
				when 10 then
					resend_theme_colors
					restyle_all
					appearance_changed_actions.call ([l_a = 1])
				when 11 then
					fire_waiting_messages
				when 28 then
					if notification_actions.valid_index (l_a) then
						notification_actions.i_th (l_a).call (Void)
					end
				when 49 then
					answer_help (l_a)
				when 30 then
					begin_pick (l_id, l_a)
				when 31 then
					finish_pick (l_id, l_a)
				when 32 then
					pebble_in_flight := Void
				when 33 then
					if attached widgets.item (l_id) as al_target then
						al_target.take_outside_drop (l_a)
					end
				when 34 then
					if attached widgets.item (l_id) as al_source then
						al_source.end_drag_out (l_a)
					end
				when 62 then
						-- 1x: a frame tick, `l_a' milliseconds after the last one
					animation_clock.frame_tick (l_a.max (0))
				when 24 then
					if attached timers.item (l_a) as al_timer then
						al_timer.fire
						if not al_timer.is_active then
							timers.remove (l_a)
						end
					end
				else
					if attached widgets.item (l_id) as al_widget then
						al_widget.dispatch (l_type, l_a, l_b, l_c)
					end
				end
			end
		end

feature {GUI_WIDGET, GUI_TEST_DRIVER} -- Style (1w)

	check_contrast (a_style: GUI_STYLE)
			-- Note it when `a_style' puts text on a background with too little contrast.
		local
			l_fg, l_bg: NATURAL_32
			l_dark: BOOLEAN
		do
			if
				not low_contrast_warned and then a_style.is_set (a_style.Property_foreground)
				and then a_style.is_set (a_style.Property_background)
			then
				l_dark := is_dark
				l_fg := a_style.color (a_style.Property_foreground, l_dark, agent system_color)
				l_bg := a_style.color (a_style.Property_background, l_dark, agent system_color)
				if a_style.contrast_ratio (l_fg, l_bg) < 4.5 then
					low_contrast_warned := True
					if is_workbench_build then
						io.error.put_string ("simple_gui: a styled widget's text and background measure below 4.5:1 (GUI_STYLE.contrast_ratio).%N")
					end
				end
			end
		end

	restyle_all
			-- Show every styled widget's style anew (the appearance, the theme or the system's
			-- contrast setting changed).
		do
			across widgets as ic loop
				if ic.is_styled or ic.has_native_style then
					ic.restyle
				end
			end
		end

feature {GUI_TEST_DRIVER} -- Registry

	widgets: HASH_TABLE [GUI_WIDGET, INTEGER]
			-- Every widget, by id.

feature {NONE} -- Style (1w)

	style_classes: HASH_TABLE [GUI_STYLE, STRING_32]
			-- Each defined class, by name.
		attribute
			create Result.make (4)
		end

	theme_lights: ARRAY [INTEGER]
			-- The program's own color for each theme role in the light appearance; -1: the system's.
		attribute
			create Result.make_filled (-1, Color_window_background, Color_separator)
		end

	theme_darks: ARRAY [INTEGER]
			-- The same in the dark appearance.
		attribute
			create Result.make_filled (-1, Color_window_background, Color_separator)
		end

	send_theme_color (a_role: INTEGER)
			-- Give the backend the program's color for `a_role' in the appearance of now.
		do
			if not has_theme_color (a_role) or else backend.is_high_contrast then
					-- The system's contrast setting wins: the toolkit shows its own colors.
				backend.set_theme_color (a_role, -1)
			elseif is_dark then
				backend.set_theme_color (a_role, theme_darks [a_role])
			else
				backend.set_theme_color (a_role, theme_lights [a_role])
			end
		end

	resend_theme_colors
			-- The appearance or the system's contrast setting changed: give the backend each
			-- override's variant for now (none under the contrast setting).
		do
			across Color_window_background |..| Color_separator as ic loop
				send_theme_color (ic)
			end
		end

	is_workbench_build: BOOLEAN
			-- Is this a workbench (development) build, not a finalized one?
		external
			"C inline"
		alias
			"[
				#ifdef WORKBENCH
				return EIF_TRUE;
				#else
				return EIF_FALSE;
				#endif
			]"
		end

feature {NONE} -- Animation (1x)

	motion_override: detachable CELL [BOOLEAN]
			-- A test's stand-in for the system's reduce-motion answer.

	animation_duration_chosen: INTEGER
			-- The duration a program chose (`set_animation_duration').

	is_animation_duration_set: BOOLEAN
			-- Has a program chosen `animation_duration'? (An INTEGER attribute cannot start at
			-- 200 by itself: a self-initializing body never runs for an expanded type.)

	run_later (an_action: PROCEDURE)
			-- Run `an_action' on the queue's next turn (the clock's finished actions for an
			-- animation completed at once).
		do
			after (1, an_action).do_nothing
		end

feature {NONE} -- Implementation

	answer_help (a_focused: INTEGER)
			-- The user asked for help about widget `a_focused' (0: the window).
		local
			l_widget, l_topic_owner, l_pill_owner: detachable GUI_WIDGET
			l_c: C_STRING
		do
			from
				l_widget := widgets.item (a_focused)
			until
				l_widget = Void or else (l_topic_owner /= Void and l_pill_owner /= Void)
			loop
				if attached l_widget as al_w then
					if l_topic_owner = Void and then not al_w.help_topic.is_empty then
						l_topic_owner := al_w
					end
					if l_pill_owner = Void and then attached al_w.pill_code as al_code and then pills.has (al_code) then
						l_pill_owner := al_w
					end
					l_widget := al_w.parent
				end
			end
			if help_actions.count > 0 then
				if attached l_topic_owner as al_owner then
					help_actions.call ([al_owner.help_topic, al_owner])
				else
					help_actions.call ([create {STRING_32}.make_empty, Void])
				end
			elseif attached l_pill_owner as al_owner and then attached al_owner.pill_code as al_code then
				l_c := backend.to_c (pills.item (al_code).tip)
				backend.help_show_tip (al_owner.id, l_c.item)
			end
		end

	notification_actions: ARRAYED_LIST [PROCEDURE]
			-- Each clickable notification's action, by its id (from 1).

	send_notification (a_title, a_body: READABLE_STRING_GENERAL; an_id: INTEGER)
		local
			l_t, l_b: C_STRING
		do
			create last_notification.make_from_string_general (a_title)
			last_notification.append_character ('%N')
			last_notification.append_string_general (a_body)
			l_t := backend.to_c (a_title)
			l_b := backend.to_c (a_body)
			backend.notify (l_t.item, l_b.item, an_id)
		end

	begin_pick (a_source, a_row: INTEGER)
			-- Event 30: lift the source's pebble and tell the backend which widgets take it
			-- (with their labels, for `Pick_menu'); or cancel when there is none.
		local
			l_ids: ARRAYED_LIST [INTEGER]
			l_labels: STRING_32
			l_buffer: MANAGED_POINTER
			l_c: C_STRING
			i: INTEGER
		do
			pebble_in_flight := Void
			if attached widgets.item (a_source) as al_source and then attached al_source.pebble_at_row (a_row) as al_pebble then
				pebble_in_flight := al_pebble
				create l_ids.make (4)
				create l_labels.make_empty
				across widgets as ic loop
					if ic.has_drop_actions and then ic.is_enabled and then ic.drop_actions.accepts (al_pebble) then
						l_ids.extend (ic.id)
						if not l_labels.is_empty then
							l_labels.append_character ('%N')
						end
						l_labels.append (ic.accessible_label)
					end
				end
				create l_buffer.make ((l_ids.count * 4).max (4))
				from i := 1 until i > l_ids.count loop
					l_buffer.put_integer_32 (l_ids [i], (i - 1) * 4)
					i := i + 1
				end
				l_c := backend.to_c (l_labels)
				backend.pick_targets (a_source, l_buffer.item, l_ids.count, l_c.item)
			else
				backend.pick_cancel
			end
		end

	finish_pick (a_target, a_row: INTEGER)
			-- Event 31: the pebble lands on `a_target' (row `a_row'); its accepting actions run.
		do
			if attached pebble_in_flight as al_pebble then
				pebble_in_flight := Void
				if attached widgets.item (a_target) as al_target and then al_target.has_drop_actions
					and then al_target.drop_actions.accepts (al_pebble)
				then
					al_target.set_last_drop_row (a_row)
					al_target.drop_actions.drop (al_pebble)
				end
			end
		ensure
			landed: not is_picking
		end

	timers: HASH_TABLE [GUI_TIMER, INTEGER]
			-- The active timers, by id.

	last_timer_id: INTEGER

	fire_waiting_messages
			-- Copy every waiting message out of `mailbox', then fire `message_actions'.
			-- The mailbox is released when `take_messages' returns, before anything fires:
			-- a handler may wait on a worker (GUI_PICTURE_LOADER asks its worker for
			-- results) while that worker waits to post to the mailbox, and firing with the
			-- mailbox held deadlocked both processors.
		local
			l_tags: ARRAYED_LIST [INTEGER]
			l_texts: ARRAYED_LIST [STRING_32]
		do
			create l_tags.make (4)
			create l_texts.make (4)
			take_messages (mailbox, l_tags, l_texts)
			fire_messages (l_tags, l_texts)
		end

	take_messages (a_mailbox: separate GUI_MAILBOX; a_tags: ARRAYED_LIST [INTEGER]; a_texts: ARRAYED_LIST [STRING_32])
			-- Move every message in `a_mailbox' to the ends of `a_tags' and `a_texts'. Fires
			-- nothing: `a_mailbox' stays held until this returns.
		require
			paired: a_tags.count = a_texts.count
		local
			l_text: STRING_32
		do
			from
			until
				a_mailbox.is_empty
			loop
				a_tags.extend (a_mailbox.first_tag)
				create l_text.make_from_separate (a_mailbox.first_payload)
				a_texts.extend (l_text)
				a_mailbox.remove_first
			end
		ensure
			still_paired: a_tags.count = a_texts.count
		end

	fire_messages (a_tags: ARRAYED_LIST [INTEGER]; a_texts: ARRAYED_LIST [STRING_32])
		require
			paired: a_tags.count = a_texts.count
		local
			i: INTEGER
		do
			from
				i := 1
			until
				i > a_tags.count
			loop
				message_actions.call ([a_tags.i_th (i), a_texts.i_th (i)])
				i := i + 1
			end
		end

invariant
	windows_registered: across windows as ic all widgets.has (ic.id) end

end
