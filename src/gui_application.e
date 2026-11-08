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

	Heartbeat_ms: INTEGER = 250

feature -- Status

	is_available: BOOLEAN
			-- Did the toolkit start (is there a display)?

	is_running: BOOLEAN

	is_dark: BOOLEAN
			-- Is the system appearance dark?
		require
			available: is_available
		do
			Result := backend.is_dark
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
				else
					if attached widgets.item (l_id) as al_widget then
						al_widget.dispatch (l_type, l_a, l_b, l_c)
					end
				end
			end
		end

feature {NONE} -- Implementation

	widgets: HASH_TABLE [GUI_WIDGET, INTEGER]
			-- Every widget, by id.

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
