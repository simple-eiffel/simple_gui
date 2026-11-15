note
	description: "[
		One GUI_MEDIA_PLAYER on Windows (1z-b): its Media Foundation engine, the frame both its
		views paint, its view in the layout and, while full screen, the view filling the window.
		GUI_BACKEND turns it on every pump (`take_reports', `take_frame') and keeps the bars in
		step (`sync_bars').
	]"

class
	GUI_SW_MEDIA

create
	make

feature {NONE} -- Initialization

	make (an_id: INTEGER; a_view: GUI_SW_MEDIA_VIEW)
		do
			id := an_id
			view := a_view
			create engine.make
		ensure
			id_set: id = an_id
			view_set: view = a_view
		end

feature -- Access

	id: INTEGER
			-- simple_gui's id for the player.

	engine: GUI_SW_MEDIA_ENGINE

	view: GUI_SW_MEDIA_VIEW
			-- The player in its layout.

	filler: detachable GUI_SW_MEDIA_VIEW
			-- While full screen: the view over the whole window.

	frame: detachable CAIRO_SURFACE
			-- The frame served last, the frame's size, opaque.

	full_screen_window: INTEGER
			-- The window it fills, while full screen; 0 otherwise.

	window_was_full_screen: BOOLEAN
			-- Was that window full screen already when the player came to fill it?

	is_watched: BOOLEAN
			-- Are positions reported (66/2)?

	last_report_ms: REAL_64
			-- The clock when the last position report went.

	busy_until_ms: REAL_64
			-- Until then, the pump turns often for it (it was opened or moved lately).

	is_opened: BOOLEAN
			-- Has media been opened?

	is_settled: BOOLEAN
			-- Has the media opened last reported ready or failed?

	is_full_screen: BOOLEAN
		do
			Result := full_screen_window > 0
		end

	views: ARRAYED_LIST [GUI_SW_MEDIA_VIEW]
			-- The view, and the filler while there is one.
		do
			create Result.make (2)
			Result.extend (view)
			if attached filler as al_f then
				Result.extend (al_f)
			end
		end

feature -- Element change

	set_watched (a_on: BOOLEAN)
		do
			is_watched := a_on
		ensure
			set: is_watched = a_on
		end

	mark_busy (a_now_ms: REAL_64)
			-- It was opened or moved: turn often for a while.
		do
			busy_until_ms := a_now_ms + Busy_ms
		end

	mark_opened (a_now_ms: REAL_64)
		do
			is_opened := True
			is_settled := False
			mark_busy (a_now_ms)
			across views as ic loop
				ic.bar.clear_duration
			end
		ensure
			opened: is_opened
			not_settled: not is_settled
		end

	mark_settled
		do
			is_settled := True
		ensure
			settled: is_settled
		end

	note_report (a_now_ms: REAL_64)
		do
			last_report_ms := a_now_ms
		end

	enter_full_screen (a_window: INTEGER; a_filler: GUI_SW_MEDIA_VIEW; a_window_was: BOOLEAN)
		require
			named: a_window > 0
		do
			full_screen_window := a_window
			filler := a_filler
			window_was_full_screen := a_window_was
			a_filler.set_media (Current)
			a_filler.set_controls_visible (view.is_controls_visible)
		ensure
			full: is_full_screen
		end

	leave_full_screen
		do
			full_screen_window := 0
			filler := Void
			window_was_full_screen := False
		ensure
			not_full: not is_full_screen
		end

	set_frame (a_frame: detachable CAIRO_SURFACE)
			-- Keep `a_frame' as the frame, destroying the one before when it is another.
		do
			if attached frame as al_old and then al_old /= a_frame and then al_old.is_valid then
				al_old.destroy
			end
			frame := a_frame
		ensure
			set: frame = a_frame
		end

feature -- Turning

	is_busy (a_now_ms: REAL_64): BOOLEAN
			-- Must the pump turn often for it: playing, opening, or moved lately?
		do
			Result := engine.is_available and is_opened and then
				(not is_settled or a_now_ms < busy_until_ms or engine.is_playing)
		end

	take_frame: BOOLEAN
			-- Copy a new frame, when the engine has one, into `frame'. Is there a new one?
		local
			l_w, l_h: INTEGER
			l_frame: CAIRO_SURFACE
		do
			if engine.is_available and then engine.tick then
				l_w := engine.frame_width
				l_h := engine.frame_height
				if l_w > 0 and l_h > 0 then
					if attached frame as al_f and then al_f.is_valid and then al_f.width = l_w and then al_f.height = l_h then
						l_frame := al_f
					else
						create l_frame.make (l_w, l_h)
					end
					if l_frame.is_valid and then engine.copy_frame_into (l_frame) then
						set_frame (l_frame)
						Result := True
					elseif l_frame /= frame and l_frame.is_valid then
						l_frame.destroy
					end
				end
			end
		end

	sync_bars
			-- Each bar shows the player as it stands.
		local
			l_duration: INTEGER
		do
			if engine.is_available then
				l_duration := engine.duration_ms
				across views as ic loop
					if l_duration > 0 then
						ic.bar.set_duration (l_duration / 1000.0)
						ic.bar.set_position (engine.position_ms / 1000.0)
					end
					ic.bar.set_playing (engine.is_playing)
					ic.bar.set_volume (engine.volume.max (0.0).min (1.0))
					ic.bar.set_muted (engine.is_muted)
					ic.bar.set_full_screen (is_full_screen)
				end
			end
		end

	close
			-- Shut the engine down and let the frame go.
		do
			engine.close
			set_frame (Void)
			filler := Void
		end

feature -- Constants

	Busy_ms: REAL_64 = 1500.0
			-- How long after an opening or a move the pump keeps turning often.

	Report_every_ms: REAL_64 = 250.0
			-- Position reports come at most this often.

end
