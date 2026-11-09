note
	description: "[
		A simple_widgets widget inside a native simple_gui window (spec 1i): charts, boards,
		timelines, sheets and the rest of the drawn widgets. The root draws, takes the pointer
		and keys, follows light and dark, shows its menus, popovers and tooltips (drawn, inside
		this widget's bounds), animates, and reads to assistive tools under this widget.

			create l_chart.make
			create l_drawn.make (l_chart, 480, 320)
			l_window.set_content (l_drawn)

		Inside is a hosted SW_WINDOW (`sw_window'), fed this view's events in device pixels; it
		renders after each one and this widget presents the frame. After the program changes
		the SW widgets' data, call `refresh'. The SW widgets' own agents are the events: they
		run on the GUI processor, as in any simple_gui program. Its dialogs (SW `ask',
		`choose_file') are GUI_DIALOGS'.

		In simple_gui_drawn.ecf, so programs with native controls only never link
		simple_widgets.
	]"

class
	GUI_DRAWN

inherit
	GUI_WIDGET
		redefine
			dispatch, refresh_description
		end

create
	make

feature {NONE} -- Initialization

	make (a_root: SW_WIDGET; a_width, a_height: INTEGER)
			-- Host `a_root', preferring `a_width' by `a_height' logical pixels (it fills as a canvas does).
		require
			gui_thread: is_gui_thread
			has_application: has_application
			no_parent: a_root.parent = Void
			sized: a_width >= 1 and a_height >= 1
		do
			root := a_root
			scale := 1.0
			create sw_window.make ("drawn", 0, 0, a_width, a_height, new_theme)
			sw_window.start_hosting
			register (backend.drawn (a_width, a_height))
			scale := backend.scale (id)
			sw_window.set_theme (new_theme)
			sw_window.set_root (a_root)
			sw_window.set_on_frame (agent present)
			sw_window.set_dialog_delegate (agent ask, agent choose_file)
			application.appearance_changed_actions.extend (agent on_appearance)
			backend.drawn_set_ticks (id, Tick_ms, 0)
				-- laid out at the preferred size at once, so it draws and publishes its tree even
				-- before the view's first resize (9) arrives, which corrects it (WSLg can be late)
			sw_window.host_event ({SHELL_EVENTS}.Event_window_resize, device (a_width), device (a_height), 0)
			sw_window.request_render
		ensure
			root_set: root = a_root
		end

feature -- Access

	root: SW_WIDGET
			-- The hosted simple_widgets widget.

	sw_window: SW_WINDOW
			-- The hosted window `root' lives in (for advanced use: its theme, focus, overlays).

	scale: REAL_64
			-- Device pixels per logical pixel, as last measured.

	frame_count: INTEGER
			-- Frames presented (for tests and tuning).

feature -- Basic operations

	refresh
			-- Draw again after the program changed the SW widgets' data. Silent; before the view is
			-- laid out (`width' = 0) it does nothing.
		require
			gui_thread: is_gui_thread
		do
			if width > 0 then
				sw_window.request_render
			end
		end

	set_fast_tick (a_ms: INTEGER)
			-- SW's fast tick (event 25) every `a_ms' milliseconds, for animation; 0 stops it.
		require
			gui_thread: is_gui_thread
			not_negative: a_ms >= 0
		do
			backend.drawn_set_ticks (id, Tick_ms, a_ms)
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
			-- The view's events (spec 1i: 9 resize, 18 to 23), to the hosted window.
		do
			inspect a_type
			when 9 then
				resized (a_a, a_b)
			when 18 then
				pointer (a_a, a_b, a_c)
			when 19 then
				simulate (a_c // 256)
				sw_window.host_event ({SHELL_EVENTS}.Event_window_wheel, device (a_a), device (a_b), a_c)
			when 20 then
				if a_b = 1 and then virtual_key (a_a) > 0 then
					simulate (a_c // 256)
					sw_window.host_event ({SHELL_EVENTS}.Event_window_key, virtual_key (a_a), 0, 0)
				end
			when 21 then
				character (a_a)
			when 23 then
				timer (a_a, a_b)
			else
			end
			sync_host
		end

feature {GUI_TEST_DRIVER} -- Accessibility

	refresh_description
			-- The hosted window's tree, for `describe_accessibility' under this widget's group.
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (sw_window.describe_accessibility)
			backend.drawn_set_description (id, l_c.item)
		end

feature {NONE} -- Events

	resized (a_width, a_height: INTEGER)
			-- The view is `a_width' by `a_height' logical pixels: resize the hosted window, with a
			-- new theme when the screen's scale changed.
		local
			l_scale: REAL_64
		do
			l_scale := backend.scale (id)
			if l_scale /= scale then
				scale := l_scale
				sw_window.set_theme (new_theme)
			end
			sw_window.host_event ({SHELL_EVENTS}.Event_window_resize, device (a_width), device (a_height), 0)
		end

	pointer (a_x, a_y, a_c: INTEGER)
			-- A pointer event (c = kind + button * 16 + modifiers * 256) as SW's.
		local
			l_kind, l_button, l_type: INTEGER
		do
			l_kind := a_c \\ 16
			l_button := (a_c // 16) \\ 16
			simulate (a_c // 256)
			inspect l_kind
			when 1 then
				if l_button = 1 then
					l_type := {SHELL_EVENTS}.Event_window_press
				elseif l_button = 3 then
					l_type := {SHELL_EVENTS}.Event_window_middle
				end
			when 2 then
				if l_button = 1 then
					l_type := {SHELL_EVENTS}.Event_window_release
				elseif l_button = 2 then
					l_type := {SHELL_EVENTS}.Event_window_context
				end
			when 3 then
				if l_button = 1 then
					l_type := {SHELL_EVENTS}.Event_window_drag
				else
					l_type := {SHELL_EVENTS}.Event_window_move
				end
			when 4 then
				l_type := {SHELL_EVENTS}.Event_window_leave
			when 5 then
				l_type := {SHELL_EVENTS}.Event_window_double
			when 6 then
				l_type := {SHELL_EVENTS}.Event_window_triple
			else
			end
			if l_type > 0 then
				sw_window.host_event (l_type, device (a_x), device (a_y), 0)
			end
		end

	character (a_code: INTEGER)
			-- A typed character, as UTF-16 units (two for one beyond the BMP), as SW reads them.
		local
			l_v: INTEGER
		do
			if a_code >= 0x10000 then
				l_v := a_code - 0x10000
				sw_window.host_event ({SHELL_EVENTS}.Event_window_char, 0xD800 + l_v // 0x400, 0, 0)
				sw_window.host_event ({SHELL_EVENTS}.Event_window_char, 0xDC00 + l_v \\ 0x400, 0, 0)
			elseif a_code > 0 then
				sw_window.host_event ({SHELL_EVENTS}.Event_window_char, a_code, 0, 0)
			end
		end

	timer (a_kind, a_serial: INTEGER)
			-- 0 the tick, 1 the fast tick, 2 the dwell shot `a_serial' (only the latest, still armed).
		do
			inspect a_kind
			when 0 then
				sw_window.host_event ({SHELL_EVENTS}.Event_tick, 0, 0, 0)
			when 1 then
				sw_window.host_event ({SHELL_EVENTS}.Event_fast_tick, 0, 0, 0)
			when 2 then
				if a_serial = sw_window.hosted_dwell_serial and sw_window.is_dwell_timer_armed then
					sw_window.host_event (Event_dwell, 0, 0, 0)
				end
			else
			end
		end

	on_appearance (a_dark: BOOLEAN)
			-- Light or dark changed: a new theme, and a new frame.
		do
			sw_window.set_theme (new_theme)
			refresh
		end

	present
			-- The hosted window's new frame, to the view.
		do
			backend.drawn_present (id, sw_window.frame_surface.handle, sw_window.win_w, sw_window.win_h)
			frame_count := frame_count + 1
		end

	sync_host
			-- After an event: the pointer shape the hosted window wants, and its dwell shot.
		do
			if sw_window.hosted_cursor /= shown_cursor then
				shown_cursor := sw_window.hosted_cursor
				backend.drawn_set_cursor (id, shown_cursor)
			end
			if sw_window.hosted_dwell_serial /= armed_serial then
				armed_serial := sw_window.hosted_dwell_serial
				if sw_window.hosted_dwell_ms > 0 then
					backend.drawn_arm_dwell (id, sw_window.hosted_dwell_ms, armed_serial)
				end
			end
		end

feature {NONE} -- Dialogs (the hosted window's, through GUI_DIALOGS)

	ask (a_kind: INTEGER; a_title, a_message: STRING_32; a_confirm: BOOLEAN): BOOLEAN
		do
			if a_confirm then
				Result := application.dialogs.confirm (a_title, a_message)
			else
				application.dialogs.inform (a_title, a_message)
				Result := True
			end
		end

	choose_file (a_save: BOOLEAN; a_title, a_start_dir, a_suggested, an_extensions: STRING_32): detachable STRING_32
		local
			l_extensions: ARRAYED_LIST [READABLE_STRING_GENERAL]
			l_path: detachable PATH
		do
			create l_extensions.make (4)
			across an_extensions.split (';') as ic loop
				across ic.split (',') as ic2 loop
					ic2.adjust
					ic2.prune_all_leading ('*')
					ic2.prune_all_leading ('.')
					if not ic2.is_empty then
						l_extensions.extend (ic2)
					end
				end
			end
			if a_save then
				l_path := application.dialogs.save_file_named (a_title, l_extensions.to_array, a_suggested)
			else
				l_path := application.dialogs.open_file (a_title, l_extensions.to_array)
			end
			if attached l_path as al_path then
				Result := al_path.name
			end
		end

feature {NONE} -- Implementation

	shown_cursor: INTEGER

	armed_serial: INTEGER

	Tick_ms: INTEGER = 250
			-- SW's heartbeat, as simple_shell gives it.

	Event_dwell: INTEGER = 55

	device (a_logical: INTEGER): INTEGER
			-- `a_logical' pixels in device pixels.
		do
			Result := (a_logical * scale).rounded
		end

	new_theme: SW_THEME
			-- Light or dark as the application is, at the screen's scale (SW lays out in device pixels).
		do
			if application.is_dark then
				create Result.make_dark
			else
				create Result.make_light
			end
			Result.set_text_scale (scale)
		end

	simulate (a_modifiers: INTEGER)
			-- The modifiers SW reads (1 shift, 2 control, 4 alt, 8 super): super counts as control,
			-- so Command-C is SW's Control-C on macOS.
		do
			keys.simulate (a_modifiers \\ 2 = 1, (a_modifiers // 2) \\ 2 = 1 or (a_modifiers // 8) \\ 2 = 1, (a_modifiers // 4) \\ 2 = 1)
		end

	keys: SW_KEYS
		once
			create Result
		end

	virtual_key (a_keyval: INTEGER): INTEGER
			-- The Windows virtual key SW expects for the GDK keyval `a_keyval' (0: none).
		do
			inspect a_keyval
			when 0x61 .. 0x7A then Result := a_keyval - 0x20
			when 0x41 .. 0x5A, 0x30 .. 0x39 then Result := a_keyval
			when 0x20 then Result := 32
			when 0xFF0D, 0xFF8D then Result := 13
			when 0xFF1B then Result := 27
			when 0xFF09, 0xFE20 then Result := 9
			when 0xFF08 then Result := 8
			when 0xFFFF then Result := 46
			when 0xFF63 then Result := 45
			when 0xFF50 then Result := 36
			when 0xFF57 then Result := 35
			when 0xFF55 then Result := 33
			when 0xFF56 then Result := 34
			when 0xFF51 then Result := 37
			when 0xFF52 then Result := 38
			when 0xFF53 then Result := 39
			when 0xFF54 then Result := 40
			when 0xFFBE .. 0xFFC9 then Result := 112 + a_keyval - 0xFFBE
			when 0xFFE1, 0xFFE2 then Result := 16
			when 0xFFE3, 0xFFE4, 0xFFEB, 0xFFEC then Result := 17
			when 0xFFE9, 0xFFEA then Result := 18
			when 0x2C then Result := 188
			when 0x2E then Result := 190
			when 0x2D then Result := 189
			when 0x3D then Result := 187
			else
			end
		end

invariant
	root_exists: root /= Void

end
