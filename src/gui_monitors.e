note
	description: "[
		The monitors attached to the desktop (1z-c), through GUI_APPLICATION.monitors,
		for placing windows: each one's bounds and work area (the part the taskbar, the
		menu bar and the Dock leave) as GUI_RECTANGLE, its own scale and its name.

		Units, by meaning, the same on every platform (each backend converts
		simple_shell's SHELL_MONITORS fields):
		- a monitor's size and its work area's size are in that monitor's own logical
		  pixels: the size a window shows on it;
		- x and y are the platform's own arrangement, in the primary monitor's logical
		  pixels, origin at the primary's top left. They tell which monitor is where; a
		  window is placed on a monitor through the API, never by adding coordinates
		  across monitors;
		- `scale' is each monitor's own (1.0, 1.5, 2.0).

		The answers are a snapshot. `changed_actions' run, after a new snapshot, when the
		system's monitors change (plugged, unplugged, rearranged, rescaled): shared code
		polls simple_shell's change count on the heartbeat (event 67).
	]"

class
	GUI_MONITORS

inherit
	GUI_SHARED

create {GUI_APPLICATION}
	make

feature {NONE} -- Initialization

	make
			-- A snapshot of the monitors now.
		do
			create changed_actions.make
			create shell.make
			last_change_count := shell.change_count
		end

feature -- Access

	count: INTEGER
			-- Monitors in the snapshot.
		do
			Result := shell.count
		ensure
			non_negative: Result >= 0
		end

	primary_index: INTEGER
			-- The primary monitor (the one with the taskbar or the menu bar); 0 when the
			-- snapshot has none.
		do
			Result := shell.primary_index
		ensure
			valid: Result = 0 or valid_index (Result)
		end

	bounds (a_index: INTEGER): GUI_RECTANGLE
			-- Monitor `a_index' whole: its x and y in the primary's logical pixels, its size
			-- in its own.
		require
			valid: valid_index (a_index)
		do
			Result := logical (a_index, shell.left (a_index), shell.top (a_index), shell.right (a_index), shell.bottom (a_index))
		end

	work_area (a_index: INTEGER): GUI_RECTANGLE
			-- The part of monitor `a_index' that windows open in: less the taskbar, the menu
			-- bar and the Dock (GTK 4 has no such query, so there it is the whole monitor).
		require
			valid: valid_index (a_index)
		do
			Result := logical (a_index, shell.work_left (a_index), shell.work_top (a_index), shell.work_right (a_index),
				shell.work_bottom (a_index))
		end

	scale (a_index: INTEGER): REAL_64
			-- Monitor `a_index''s own scale: device pixels per logical pixel (1.0, 1.5, 2.0).
		require
			valid: valid_index (a_index)
		do
			Result := shell.scale (a_index) / 100
		ensure
			positive: Result > 0
		end

	name (a_index: INTEGER): STRING_32
			-- Monitor `a_index''s name: the system's for it, which tells it apart across
			-- sessions ("\\.\DISPLAY1", the screen's model, its connector).
		require
			valid: valid_index (a_index)
		do
			Result := shell.device_name (a_index)
		end

	changed_actions: GUI_ACTIONS [TUPLE]
			-- Run when the system's monitors change, after the new snapshot is taken.

feature -- Status

	valid_index (a_index: INTEGER): BOOLEAN
			-- Is `a_index' a monitor of the snapshot?
		do
			Result := shell.valid_index (a_index)
		ensure
			definition: Result = (a_index >= 1 and a_index <= count)
		end

feature -- Element change

	refresh
			-- Take a new snapshot now.
		require
			gui_thread: is_gui_thread
		do
			shell.refresh
		end

feature {GUI_APPLICATION, GUI_WINDOW, GUI_TEST_DRIVER} -- Implementation

	shell: SHELL_MONITORS
			-- simple_shell's snapshot, in its own units.

	poll
			-- On the heartbeat: take a change of the system's monitors, if there was one.
		do
			if shell.change_count /= last_change_count then
				take_change
			end
		end

	take_change
			-- The monitors changed (event 67, or a moved change count): a new snapshot, then
			-- `changed_actions'.
		do
			last_change_count := shell.change_count
			shell.refresh
			changed_actions.call (Void)
		ensure
			told: changed_actions.fire_count = old changed_actions.fire_count + 1
		end

feature {NONE} -- Implementation

	last_change_count: INTEGER
			-- simple_shell's change count at the last snapshot.

	logical (a_index, a_left, a_top, a_right, a_bottom: INTEGER): GUI_RECTANGLE
			-- The rectangle of monitor `a_index' whose edges are `a_left' .. `a_bottom' in
			-- simple_shell's units: its x and y by the backend's position units, its size by
			-- its own size units. The size is taken edge to edge, rounded at each edge, so a
			-- monitor's work area stays inside its bounds.
		require
			valid: valid_index (a_index)
			ordered: a_left <= a_right and a_top <= a_bottom
		local
			l_place, l_size: REAL_64
		do
			l_place := backend.monitor_position_units (shell, a_index)
			l_size := backend.monitor_size_units (shell, a_index)
			create Result.make ((a_left / l_place).rounded, (a_top / l_place).rounded,
				((a_right / l_size).rounded - (a_left / l_size).rounded).max (0),
				((a_bottom / l_size).rounded - (a_top / l_size).rounded).max (0))
		end

invariant
	shell_count_bounded: count <= shell.Max_monitors

end
