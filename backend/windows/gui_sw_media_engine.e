note
	description: "[
		GUI_MEDIA_PLAYER's playback on Windows (1z-b): Media Foundation's media engine in
		frame-server mode (simple_gui_win_media.h). It decodes and plays the sound; the backend
		asks it for each video frame (`tick') and copies the frame into a Cairo image that
		simple_widgets paints (`copy_frame_into').

		Every external over simple_gui_win_media.h is in this one class, so the header lands in
		one generated C file (the inline-C statics rule).
	]"

class
	GUI_SW_MEDIA_ENGINE

inherit
	DISPOSABLE

create
	make

feature {NONE} -- Initialization

	make
			-- An engine; `is_available' is False where Media Foundation is not installed.
		do
			handle := c_new
		end

feature -- Status

	is_available: BOOLEAN
			-- Did Media Foundation give us an engine?
		do
			Result := handle /= default_pointer
		end

	is_ready_told: BOOLEAN
			-- Has ready been reported for the media opened last (`mark_ready')?

feature -- Opening

	open (a_path: POINTER; a_is_url: BOOLEAN)
			-- Open the UTF-8 file path (made absolute) or URL at `a_path'.
		do
			is_ready_told := False
			c_open (handle, a_path, a_is_url.to_integer)
		ensure
			not_told: not is_ready_told
		end

	mark_ready
			-- Ready was reported: the duration and the video track count from now.
		do
			is_ready_told := True
			c_mark_ready (handle)
		ensure
			told: is_ready_told
		end

feature -- Transport

	play
		do
			c_play (handle)
		end

	pause
		do
			c_pause (handle)
		end

	stop
		do
			c_stop (handle)
		end

	seek (a_ms: INTEGER)
		do
			c_seek (handle, a_ms)
		end

feature -- State

	position_ms: INTEGER
		do
			Result := c_position_ms (handle)
		end

	duration_ms: INTEGER
		do
			Result := c_duration_ms (handle)
		end

	is_playing: BOOLEAN
		do
			Result := c_is_playing (handle) /= 0
		end

	rate: REAL_64
			-- GetPlaybackRate while playing, else 0.
		do
			Result := c_rate (handle)
		end

	volume: REAL_64
		do
			Result := c_volume (handle)
		end

	is_muted: BOOLEAN
		do
			Result := c_is_muted (handle) /= 0
		end

	video_width: INTEGER
		do
			Result := c_video_width (handle)
		end

	video_height: INTEGER
		do
			Result := c_video_height (handle)
		end

	has_video: BOOLEAN
		do
			Result := c_has_video (handle) /= 0
		end

	failure: POINTER
			-- Why it failed, UTF-8 (the engine's own buffer).
		do
			Result := c_failure (handle)
		end

feature -- Settings

	set_volume (a_volume: REAL_64)
		do
			c_set_volume (handle, a_volume)
		end

	set_muted (a_on: BOOLEAN)
		do
			c_set_muted (handle, a_on.to_integer)
		end

	set_loops (a_on: BOOLEAN)
		do
			c_set_loops (handle, a_on.to_integer)
		end

feature -- Reports and frames

	next_report (a_kind, a_value: TYPED_POINTER [INTEGER]): BOOLEAN
			-- The engine's next report (1 metadata loaded, 3 ended, 4 failed), if any.
		do
			Result := c_next (handle, a_kind, a_value) /= 0
		end

	tick: BOOLEAN
			-- Is there a new frame (now transferred)?
		do
			Result := c_tick (handle) /= 0
		end

	frame_width: INTEGER
			-- The last frame's width; 0 with none.
		do
			Result := c_frame_width (handle)
		end

	frame_height: INTEGER
		do
			Result := c_frame_height (handle)
		end

	copy_frame_into (a_surface: CAIRO_SURFACE): BOOLEAN
			-- Copy the last frame into `a_surface', which is the frame's size.
		require
			valid: a_surface.is_valid
		do
			a_surface.flush.do_nothing
			Result := c_copy_frame (handle, a_surface.data, a_surface.stride, a_surface.width, a_surface.height) /= 0
			a_surface.mark_dirty.do_nothing
		end

	frame_color: NATURAL_32
			-- The mean of the last frame's center 16 by 16, 0xFFRRGGBB; 0 with none.
		do
			Result := c_frame_color (handle)
		end

feature -- Removal

	close
			-- Shut the engine down.
		do
			if handle /= default_pointer then
				c_free (handle)
				handle := default_pointer
			end
		ensure
			closed: not is_available
		end

	dispose
		do
			close
		end

feature {NONE} -- Implementation

	handle: POINTER
			-- The sgw_media record.

feature {NONE} -- Externals

	c_new: POINTER
		external "C inline use %"simple_gui_win_media.h%""
		alias "return sgw_media_new();"
		end

	c_free (a_m: POINTER)
		external "C inline use %"simple_gui_win_media.h%""
		alias "sgw_media_free((sgw_media *) $a_m);"
		end

	c_open (a_m, a_text: POINTER; a_is_url: INTEGER)
		external "C inline use %"simple_gui_win_media.h%""
		alias "sgw_media_open((sgw_media *) $a_m, (const char *) $a_text, (int) $a_is_url);"
		end

	c_mark_ready (a_m: POINTER)
		external "C inline use %"simple_gui_win_media.h%""
		alias "sgw_media_mark_ready((sgw_media *) $a_m);"
		end

	c_play (a_m: POINTER)
		external "C inline use %"simple_gui_win_media.h%""
		alias "sgw_media_play((sgw_media *) $a_m);"
		end

	c_pause (a_m: POINTER)
		external "C inline use %"simple_gui_win_media.h%""
		alias "sgw_media_pause((sgw_media *) $a_m);"
		end

	c_stop (a_m: POINTER)
		external "C inline use %"simple_gui_win_media.h%""
		alias "sgw_media_stop((sgw_media *) $a_m);"
		end

	c_seek (a_m: POINTER; a_ms: INTEGER)
		external "C inline use %"simple_gui_win_media.h%""
		alias "sgw_media_seek((sgw_media *) $a_m, (int) $a_ms);"
		end

	c_position_ms (a_m: POINTER): INTEGER
		external "C inline use %"simple_gui_win_media.h%""
		alias "return sgw_media_position_ms((sgw_media *) $a_m);"
		end

	c_duration_ms (a_m: POINTER): INTEGER
		external "C inline use %"simple_gui_win_media.h%""
		alias "return sgw_media_duration_ms((sgw_media *) $a_m);"
		end

	c_is_playing (a_m: POINTER): INTEGER
		external "C inline use %"simple_gui_win_media.h%""
		alias "return sgw_media_is_playing((sgw_media *) $a_m);"
		end

	c_rate (a_m: POINTER): REAL_64
		external "C inline use %"simple_gui_win_media.h%""
		alias "return sgw_media_rate((sgw_media *) $a_m);"
		end

	c_volume (a_m: POINTER): REAL_64
		external "C inline use %"simple_gui_win_media.h%""
		alias "return sgw_media_volume((sgw_media *) $a_m);"
		end

	c_set_volume (a_m: POINTER; a_volume: REAL_64)
		external "C inline use %"simple_gui_win_media.h%""
		alias "sgw_media_set_volume((sgw_media *) $a_m, (double) $a_volume);"
		end

	c_is_muted (a_m: POINTER): INTEGER
		external "C inline use %"simple_gui_win_media.h%""
		alias "return sgw_media_is_muted((sgw_media *) $a_m);"
		end

	c_set_muted (a_m: POINTER; a_on: INTEGER)
		external "C inline use %"simple_gui_win_media.h%""
		alias "sgw_media_set_muted((sgw_media *) $a_m, (int) $a_on);"
		end

	c_set_loops (a_m: POINTER; a_on: INTEGER)
		external "C inline use %"simple_gui_win_media.h%""
		alias "sgw_media_set_loops((sgw_media *) $a_m, (int) $a_on);"
		end

	c_video_width (a_m: POINTER): INTEGER
		external "C inline use %"simple_gui_win_media.h%""
		alias "return sgw_media_video_width((sgw_media *) $a_m);"
		end

	c_video_height (a_m: POINTER): INTEGER
		external "C inline use %"simple_gui_win_media.h%""
		alias "return sgw_media_video_height((sgw_media *) $a_m);"
		end

	c_has_video (a_m: POINTER): INTEGER
		external "C inline use %"simple_gui_win_media.h%""
		alias "return sgw_media_has_video((sgw_media *) $a_m);"
		end

	c_failure (a_m: POINTER): POINTER
		external "C inline use %"simple_gui_win_media.h%""
		alias "return (EIF_POINTER) sgw_media_failure((sgw_media *) $a_m);"
		end

	c_next (a_m: POINTER; a_kind, a_value: TYPED_POINTER [INTEGER]): INTEGER
		external "C inline use %"simple_gui_win_media.h%""
		alias "return sgw_media_next((sgw_media *) $a_m, (int *) $a_kind, (int *) $a_value);"
		end

	c_tick (a_m: POINTER): INTEGER
		external "C inline use %"simple_gui_win_media.h%""
		alias "return sgw_media_tick((sgw_media *) $a_m);"
		end

	c_frame_width (a_m: POINTER): INTEGER
		external "C inline use %"simple_gui_win_media.h%""
		alias "return sgw_media_frame_width((sgw_media *) $a_m);"
		end

	c_frame_height (a_m: POINTER): INTEGER
		external "C inline use %"simple_gui_win_media.h%""
		alias "return sgw_media_frame_height((sgw_media *) $a_m);"
		end

	c_copy_frame (a_m, a_data: POINTER; a_stride, a_w, a_h: INTEGER): INTEGER
		external "C inline use %"simple_gui_win_media.h%""
		alias "return sgw_media_copy_frame((sgw_media *) $a_m, (unsigned char *) $a_data, (int) $a_stride, (int) $a_w, (int) $a_h);"
		end

	c_frame_color (a_m: POINTER): NATURAL_32
		external "C inline use %"simple_gui_win_media.h%""
		alias "return (EIF_NATURAL_32) sgw_media_frame_color((sgw_media *) $a_m);"
		end

end
