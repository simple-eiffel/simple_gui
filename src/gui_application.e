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
			create menu.make
			create pills.make
			create timers.make (4)
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

	appearance_changed_actions: GUI_ACTIONS [TUPLE [dark: BOOLEAN]]
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
			-- can draw to match the window around it.
		require
			available: is_available
			known: a_role >= Color_window_background and a_role <= Color_separator
		do
			Result := backend.system_color (a_role).to_natural_32
		ensure
			rgb: Result <= 0xFFFFFF
		end

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
					appearance_changed_actions.call ([l_a = 1])
				when 11 then
					take_messages (mailbox)
				when 30 then
					begin_pick (l_id, l_a)
				when 31 then
					finish_pick (l_id, l_a)
				when 32 then
					pebble_in_flight := Void
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

feature {GUI_TEST_DRIVER} -- Registry

	widgets: HASH_TABLE [GUI_WIDGET, INTEGER]
			-- Every widget, by id.

feature {NONE} -- Implementation

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

	take_messages (a_mailbox: separate GUI_MAILBOX)
			-- Copy out every message, release the mailbox, then fire `message_actions'.
		local
			l_tags: ARRAYED_LIST [INTEGER]
			l_texts: ARRAYED_LIST [STRING_32]
			l_text: STRING_32
		do
			create l_tags.make (4)
			create l_texts.make (4)
			from
			until
				a_mailbox.is_empty
			loop
				l_tags.extend (a_mailbox.first_tag)
				create l_text.make_from_separate (a_mailbox.first_payload)
				l_texts.extend (l_text)
				a_mailbox.remove_first
			end
			fire_messages (l_tags, l_texts)
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
