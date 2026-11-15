note
	description: "[
		Video and audio, with the toolkit's own transport controls (1z-b): AVKit's AVPlayerView on
		the Mac; on Linux a GtkPicture showing a GtkMediaFile (GStreamer) over GtkMediaControls;
		on Windows Media Foundation's media engine serving frames into simple_gui's drawn window,
		with simple_widgets' drawn SW_MEDIA_BAR as its controls. Audio alone is the same widget:
		it shows only the transport bar, and `has_video' is False.

		Opening is asynchronous: `ready_actions' run when the duration and the video size are
		known, or `failed_actions' with the reason. Nothing plays until `play'. Position reports
		(`position_actions') come only while somebody watches them, at most every 250 ms while
		playing; shared code keeps the last one reported, and `position_ms' asks the toolkit
		afresh.

		Full screen is the window's own, with the player filling it; `full_screen_actions' tell
		each change both ways, the user's Escape included.

		Keyboard, when the player holds the focus: space plays and pauses, Left and Right seek 5
		seconds, Escape leaves full screen. The controls are the toolkit's own, so they speak to
		screen readers as the toolkit's do.

		Reported through event 66, a = the kind: 1 ready (b = the duration in milliseconds), 2 the
		position (b = milliseconds), 3 ended, 4 failed, 5 full screen changed (b = 1 on, 0 off).
	]"

class
	GUI_MEDIA_PLAYER

inherit
	GUI_WIDGET
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make
			-- An empty player, its transport controls shown.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create ready_actions.make
			create ended_actions.make
			create failed_actions.make
			create full_screen_actions.make
			create failure.make_empty
			is_controls_visible := True
			register (backend.media_player)
		ensure
			not_ready: not is_ready
			not_failed: not is_failed
			controls_shown: is_controls_visible
			not_looping: not is_looping
		end

feature -- Access

	position_ms: INTEGER
			-- Where it is now, in milliseconds, asked of the toolkit.
		require
			gui_thread: is_gui_thread
		do
			Result := backend.media_position_ms (id).max (0)
		ensure
			non_negative: Result >= 0
		end

	duration_ms: INTEGER
			-- Its length in milliseconds; 0 until ready.
		require
			gui_thread: is_gui_thread
		do
			if is_ready then
				Result := backend.media_duration_ms (id).max (0)
			end
		ensure
			non_negative: Result >= 0
			zero_until_ready: not is_ready implies Result = 0
		end

	last_reported_position_ms: INTEGER
			-- The position the last report gave (`position_actions'), 0 before one.

	volume: REAL_64
			-- 0 (silent) to 1 (full), as the toolkit has it.
		require
			gui_thread: is_gui_thread
		do
			Result := backend.media_volume (id).max (0.0).min (1.0)
		ensure
			unit: Result >= 0.0 and Result <= 1.0
		end

	video_width: INTEGER
			-- The video's natural width in pixels; 0 for audio alone or before ready.
		require
			gui_thread: is_gui_thread
		do
			if is_ready then
				Result := backend.media_video_width (id).max (0)
			end
		ensure
			non_negative: Result >= 0
			zero_until_ready: not is_ready implies Result = 0
		end

	video_height: INTEGER
			-- The video's natural height in pixels; 0 for audio alone or before ready.
		require
			gui_thread: is_gui_thread
		do
			if is_ready then
				Result := backend.media_video_height (id).max (0)
			end
		ensure
			non_negative: Result >= 0
			zero_until_ready: not is_ready implies Result = 0
		end

	failure: STRING_32
			-- Why the last opening failed; empty unless `is_failed'.

feature -- Status

	is_ready: BOOLEAN
			-- Did the media opened last get ready to play (`ready_actions' ran)?

	is_failed: BOOLEAN
			-- Did the media opened last fail (`failed_actions' ran)?

	is_playing: BOOLEAN
			-- Playing now (not paused, stopped or ended)?
		require
			gui_thread: is_gui_thread
		do
			Result := backend.media_is_playing (id)
		end

	is_muted: BOOLEAN
		require
			gui_thread: is_gui_thread
		do
			Result := backend.media_is_muted (id)
		end

	has_video: BOOLEAN
			-- Ready, with a video track to show?
		require
			gui_thread: is_gui_thread
		do
			Result := is_ready and then backend.media_has_video (id)
		ensure
			only_when_ready: Result implies is_ready
		end

	is_looping: BOOLEAN
			-- Does it play again from the start at the end, instead of ending?

	is_controls_visible: BOOLEAN
			-- Is the toolkit's own transport bar shown?

	is_full_screen: BOOLEAN
			-- Is it filling its window's full screen now?
		require
			gui_thread: is_gui_thread
		do
			Result := backend.media_is_full_screen (id)
		end

feature -- Actions

	ready_actions: GUI_ACTIONS [TUPLE]
			-- Run when the media opened last is ready: its duration and video size are known.

	ended_actions: GUI_ACTIONS [TUPLE]
			-- Run when it plays to its end (never while looping).

	failed_actions: GUI_ACTIONS [TUPLE [reason: STRING_32]]
			-- Run when the media opened last cannot be played, with the toolkit's reason.

	position_actions: GUI_TARGET_ACTIONS [TUPLE [position_ms: INTEGER]]
			-- Run with the position while it plays, at most every 250 ms. The first agent asks the
			-- toolkit to report it; nothing is reported before.
		do
			if attached position_actions_made as al_a then
				Result := al_a
			else
				create Result.make (agent watch_position)
				position_actions_made := Result
			end
		end

	full_screen_actions: GUI_ACTIONS [TUPLE [on: BOOLEAN]]
			-- Run when it comes to fill its window's full screen (True) or leaves it (False),
			-- however that came: `set_full_screen', Escape or the toolkit's own button.

feature -- Opening

	open_file (a_path: PATH)
			-- Open the media file at `a_path'; `ready_actions' or `failed_actions' follow.
		require
			gui_thread: is_gui_thread
			named: not a_path.is_empty
		do
			forget_opened
			backend.media_open_file (id, backend.to_c (a_path.name).item)
		ensure
			not_ready_yet: not is_ready
			not_failed_yet: not is_failed
		end

	open_url (a_url: READABLE_STRING_GENERAL)
			-- Open the media at `a_url', as `open_file' does a file. For a local server only (tests
			-- never use it).
		require
			gui_thread: is_gui_thread
			named: not a_url.is_empty
		do
			forget_opened
			backend.media_open_url (id, backend.to_c (a_url).item)
		ensure
			not_ready_yet: not is_ready
			not_failed_yet: not is_failed
		end

feature -- Transport

	play
		require
			gui_thread: is_gui_thread
		do
			backend.media_play (id)
		end

	pause
		require
			gui_thread: is_gui_thread
		do
			backend.media_pause (id)
		end

	stop
			-- Pause, and go back to the start.
		require
			gui_thread: is_gui_thread
		do
			backend.media_stop (id)
		end

	seek (a_ms: INTEGER)
			-- Move to `a_ms' milliseconds, playing or paused as it was.
		require
			gui_thread: is_gui_thread
			non_negative: a_ms >= 0
		do
			backend.media_seek (id, a_ms)
		end

feature -- Sound

	set_volume (a_volume: REAL_64)
			-- 0 (silent) to 1 (full).
		require
			gui_thread: is_gui_thread
			unit: a_volume >= 0.0 and a_volume <= 1.0
		do
			backend.media_set_volume (id, a_volume)
		ensure
			set: (volume - a_volume).abs < 0.01
		end

	set_muted (a_on: BOOLEAN)
		require
			gui_thread: is_gui_thread
		do
			backend.media_set_muted (id, a_on)
		ensure
			set: is_muted = a_on
		end

feature -- Display

	set_controls_visible (a_on: BOOLEAN)
			-- Show the toolkit's own transport bar (`a_on'), or hide it.
		require
			gui_thread: is_gui_thread
		do
			is_controls_visible := a_on
			backend.media_set_controls_visible (id, a_on)
		ensure
			set: is_controls_visible = a_on
		end

	set_loops (a_on: BOOLEAN)
			-- At the end, play again from the start (`a_on'), or end.
		require
			gui_thread: is_gui_thread
		do
			is_looping := a_on
			backend.media_set_loops (id, a_on)
		ensure
			set: is_looping = a_on
		end

	set_full_screen (a_on: BOOLEAN)
			-- Fill the window's own full screen (`a_on'), or come back; `full_screen_actions' tell
			-- when the change has come. Only in an open window.
		require
			gui_thread: is_gui_thread
		do
			backend.media_set_full_screen (id, a_on)
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 66 then
				inspect a_a
				when 1 then
					if not is_ready and not is_failed then
						is_ready := True
						ready_actions.call (Void)
					end
				when 2 then
					last_reported_position_ms := a_b.max (0)
					if attached position_actions_made as al_a then
						al_a.call ([last_reported_position_ms])
					end
				when 3 then
					ended_actions.call (Void)
				when 4 then
					if not is_failed and not is_ready then
						is_failed := True
						failure := backend.from_c (backend.media_failure (id))
						if failure.is_empty then
							failure := {STRING_32} "the media could not be played"
						end
						failed_actions.call ([failure])
					end
				when 5 then
					full_screen_actions.call ([a_b = 1])
				else
				end
			else
				Precursor (a_type, a_a, a_b, a_c)
			end
		end

feature {NONE} -- Implementation

	position_actions_made: detachable like position_actions

	forget_opened
			-- Before opening anew: not ready, not failed, nothing reported.
		do
			is_ready := False
			is_failed := False
			create failure.make_empty
			last_reported_position_ms := 0
		ensure
			not_ready: not is_ready
			not_failed: not is_failed
			no_reason: failure.is_empty
		end

	watch_position
			-- The first position agent: ask the toolkit to report.
		do
			backend.media_set_watched (id, True)
		end

invariant
	ready_or_failed: not (is_ready and is_failed)
	reason_when_failed: is_failed = not failure.is_empty

end
