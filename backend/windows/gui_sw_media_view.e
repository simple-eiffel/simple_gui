note
	description: "[
		GUI_MEDIA_PLAYER on Windows (1z-b): the video, letterboxed on black, over simple_widgets'
		drawn SW_MEDIA_BAR. Media Foundation's engine serves the frames (GUI_SW_MEDIA); this view
		only paints the one served last. With audio alone it is the bar.

		Full screen shows a second view of the same player over the whole window (the window's
		cover layer), so the player is never taken out of its layout: both paint the same frame
		and each has its own bar, kept in step.

		Keys, while it holds the focus, go to `on_key' (space, Left, Right and Escape are the
		player's).
	]"

class
	GUI_SW_MEDIA_VIEW

inherit
	SW_WIDGET
		redefine
			preferred_width, arrange, widget_at, sub_widgets, accepts_focus, handle_key,
			handle_click, accessible_role, default_accessible_name
		end

create
	make

feature {NONE} -- Initialization

	make (a_video_width, a_video_height: REAL_64)
			-- A view asking for a video area of `a_video_width' by `a_video_height' device pixels.
		require
			sized: a_video_width > 0.0 and a_video_height > 0.0
		do
			video_area_width := a_video_width
			video_area_height := a_video_height
			create bar.make
			bar.set_parent (Current)
			is_controls_visible := True
		ensure
			controls_shown: is_controls_visible
		end

feature -- Access

	bar: SW_MEDIA_BAR
			-- The transport bar.

	media: detachable GUI_SW_MEDIA
			-- The player shown.

	video_area_width, video_area_height: REAL_64
			-- The video area asked for, in device pixels.

	is_controls_visible: BOOLEAN

	on_key: detachable PROCEDURE [INTEGER]
			-- A virtual key pressed while it holds the focus.

feature -- Element change

	set_media (a_media: GUI_SW_MEDIA)
		do
			media := a_media
		ensure
			set: media = a_media
		end

	set_controls_visible (a_on: BOOLEAN)
		do
			is_controls_visible := a_on
			if not a_on then
				bar.vanish
			end
		ensure
			set: is_controls_visible = a_on
		end

	set_on_key (a_action: PROCEDURE [INTEGER])
		do
			on_key := a_action
		ensure
			set: on_key = a_action
		end

feature -- Status

	shows_video: BOOLEAN
			-- Does it give room to a video: before the media is ready (it may have one), and with one?
		do
			Result := not attached media as al_m or else not al_m.engine.is_ready_told or else al_m.engine.has_video
		end

	bar_height: REAL_64
			-- The bar's share of the height: none while hidden.
		do
			if is_controls_visible then
				Result := bar.Bar_height
			end
		end

feature -- Layout

	preferred_width (a_p: SW_PAINTER): REAL_64
		do
			Result := video_area_width
			if is_controls_visible then
				Result := Result.max (bar.preferred_width (a_p))
			end
		end

	preferred_height (a_p: SW_PAINTER; a_width: REAL_64): REAL_64
			-- The video area and the bar; the bar alone for audio.
		do
			Result := bar_height
			if shows_video then
				Result := Result + video_area_height
			end
			Result := Result.max (1.0)
		end

	arrange (a_p: SW_PAINTER)
			-- The bar along the bottom.
		do
			if is_controls_visible then
				bar.set_bounds (x, y + (height - bar_height).max (0.0), width, bar_height.min (height))
				bar.arrange (a_p)
			else
				bar.vanish
			end
		end

	sub_widgets: ARRAYED_LIST [SW_WIDGET]
		do
			create Result.make (1)
			if is_controls_visible then
				Result.extend (bar)
			end
		end

	widget_at (a_px, a_py: REAL_64): detachable SW_WIDGET
		do
			if contains (a_px, a_py) then
				if is_controls_visible and then bar.contains (a_px, a_py) then
					Result := bar.widget_at (a_px, a_py)
				end
				if Result = Void then
					Result := Current
				end
			end
		end

feature -- Drawing

	draw (a_p: SW_PAINTER)
			-- Black, the frame served last letterboxed on it, and the bar.
		local
			l_h, l_scale, l_w, l_fh: REAL_64
		do
			l_h := (height - bar_height).max (0.0)
			if l_h > 0.0 and then shows_video then
				a_p.set_color (0x000000)
				a_p.fill_rect (x, y, width, l_h)
				if attached media as al_m and then attached al_m.frame as al_frame and then al_frame.is_valid
					and then al_frame.width > 0 and then al_frame.height > 0
				then
					l_scale := (width / al_frame.width).min (l_h / al_frame.height)
					l_w := al_frame.width * l_scale
					l_fh := al_frame.height * l_scale
					a_p.push_clip (x, y, width, l_h)
					a_p.draw_image (al_frame, x + (width - l_w) / 2.0, y + (l_h - l_fh) / 2.0, l_w, l_fh)
					a_p.pop_clip
				end
			end
			if is_controls_visible then
				bar.paint (a_p)
			end
		end

feature -- Input

	accepts_focus: BOOLEAN
		do
			Result := True
		end

	handle_key (a_vk: INTEGER; a_shift: BOOLEAN)
		do
			if attached on_key as al_key then
				al_key.call (a_vk)
			end
		end

	handle_click (a_px, a_py: REAL_64): BOOLEAN
			-- A click on the video takes the focus (for the keys).
		do
			Result := is_enabled
		end

feature -- Accessibility

	accessible_role: INTEGER
		do
			Result := {SW_ACCESSIBILITY}.Role_group
		end

	default_accessible_name: STRING_32
		do
			Result := {STRING_32} "Media player"
		end

invariant
	bar_is_ours: bar.parent = Current

end
