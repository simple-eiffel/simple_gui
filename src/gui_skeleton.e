note
	description: "[
		Loading placeholders (1z-d): rounded shapes in the theme's muted color where content is
		still coming, with a lighter band sweeping across them, one sweep every 1.2 seconds on
		the application's shared animation clock. A port of simple_widgets' SW_SKELETON drawn by
		shared code with Cairo on a GUI_CANVAS, so it is the same on all three platforms and is
		tested by its pixels. On Windows its colors are SW_SKELETON's (the placeholders
		SW_THEME.surface_variant, the band SW_THEME.ink_muted at 18 percent), so its pixels match.

		Shapes: `make_lines' (bars 14 pixels high with 10 between, the last of several 62 percent
		wide), `make_disc' (an avatar), `make_rect' (a card or a picture) and `make_fill' (a block
		that fills the skeleton, the one `GUI_WIDGET.show_loading' lays over a widget).

		The band moves in 24 steps across a sweep, as SW_SKELETON's heartbeat phase does, and the
		skeleton draws again only when the step changes. While the system asks for reduced motion
		(1x's rule), or after `set_shimmer (False)', the shapes stand still and no band is drawn.
		The sweep runs only while the skeleton is shown in a window and has a size; one that stood
		still for reduced motion starts sweeping when it next draws with motion allowed.

		Screen readers: "Loading", a progress bar with no value (busy).
	]"

class
	GUI_SKELETON

inherit
	GUI_IMAGE_CANVAS
		redefine
			resized, new_native, show, hide
		end

create
	make_lines, make_disc, make_rect, make_fill

feature {NONE} -- Initialization

	make_lines (a_count: INTEGER)
			-- `a_count' placeholder lines, for text still coming, asking for `Lines_width' across.
		require
			gui_thread: is_gui_thread
			has_application: has_application
			at_least_one: a_count >= 1
		do
			shape := Shape_lines
			line_count := a_count
			make_skeleton (Lines_width, lines_height (a_count))
		ensure
			lines: shape = Shape_lines and line_count = a_count
			shimmers: has_shimmer
		end

	make_disc (a_diameter: INTEGER)
			-- A round placeholder `a_diameter' across (an avatar, a picture).
		require
			gui_thread: is_gui_thread
			has_application: has_application
			positive: a_diameter > 0
		do
			shape := Shape_disc
			line_count := 1
			disc_diameter := a_diameter
			make_skeleton (a_diameter, a_diameter)
		ensure
			disc: shape = Shape_disc and disc_diameter = a_diameter
			shimmers: has_shimmer
		end

	make_rect (a_width, a_height: INTEGER)
			-- A block placeholder `a_width' by `a_height' (a card, a picture).
		require
			gui_thread: is_gui_thread
			has_application: has_application
			positive: a_width > 0 and a_height > 0
		do
			shape := Shape_rect
			line_count := 1
			rect_width := a_width
			rect_height := a_height
			make_skeleton (a_width, a_height)
		ensure
			rect: shape = Shape_rect and rect_width = a_width and rect_height = a_height
			shimmers: has_shimmer
		end

	make_fill
			-- A block placeholder that fills the whole skeleton and follows its size, asking for no
			-- size of its own (laid over a widget by `GUI_WIDGET.show_loading').
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			shape := Shape_fill
			line_count := 1
			make_skeleton (1, 1)
		ensure
			fill: shape = Shape_fill
			shimmers: has_shimmer
		end

	make_skeleton (a_width, a_height: INTEGER)
			-- A busy canvas asking for `a_width' by `a_height', named "Loading", shimmering.
		require
			sized: a_width > 0 and a_height > 0
		local
			l_appearance: PROCEDURE [TUPLE [dark: BOOLEAN]]
		do
			has_shimmer := True
			drawn_phase := -1
			make_image_canvas (a_width, a_height)
			set_accessible_label (Loading_name)
			l_appearance := agent (a_dark: BOOLEAN) do refresh end
			appearance_agent := l_appearance
			application.appearance_changed_actions.extend (l_appearance)
		ensure
			shimmers: has_shimmer
			named: accessible_label.same_string (Loading_name)
		end

feature -- Access

	shape: INTEGER
			-- `Shape_lines', `Shape_disc', `Shape_rect' or `Shape_fill'.

	Shape_lines: INTEGER = 0
	Shape_disc: INTEGER = 1
	Shape_rect: INTEGER = 2
	Shape_fill: INTEGER = 3

	line_count: INTEGER
			-- How many lines (1 for the other shapes).

	disc_diameter: INTEGER
			-- A disc's diameter, logical pixels.

	rect_width, rect_height: INTEGER
			-- A block's size, logical pixels (it is drawn no wider than the skeleton).

	Line_height: REAL_64 = 14.0
			-- A line's height, logical pixels (SW_SKELETON's).

	Line_gap: REAL_64 = 10.0
			-- The space between lines (SW_SKELETON's).

	Last_line_share: REAL_64 = 0.62
			-- How much of the width the last of several lines takes.

	Lines_width: INTEGER = 200
			-- The width `make_lines' asks for; the lines take whatever width the skeleton gets.

	Sweep_ms: INTEGER = 1200
			-- One sweep of the band, milliseconds.

	Phase_count: INTEGER = 24
			-- The steps a sweep moves the band through (SW_SKELETON's phases).

	Band_alpha: REAL_64 = 0.18
			-- The band's opacity over the placeholders (SW_SKELETON's).

	Fill_mix: REAL_64 = 0.12
			-- Where the backend gives no placeholder color: how far the window background is
			-- mixed toward the secondary text for it.

	Loading_name: STRING_32 = "Loading"
			-- What screen readers announce.

	lines_height (a_count: INTEGER): INTEGER
			-- The height `a_count' lines take: each `Line_height', `Line_gap' between.
		require
			at_least_one: a_count >= 1
		do
			Result := (a_count * Line_height + (a_count - 1) * Line_gap).ceiling
		ensure
			positive: Result > 0
		end

	fill_color: NATURAL_32
			-- The placeholders' color now, 0xRRGGBB: the backend's (SW_THEME.surface_variant on
			-- Windows), else the window background mixed `Fill_mix' toward the secondary text.
		require
			available: application.is_available
		local
			l_own: INTEGER
		do
			l_own := backend.skeleton_fill_color
			if l_own >= 0 then
				Result := l_own.to_natural_32
			else
				Result := mixed (application.system_color (application.Color_window_background),
					application.system_color (application.Color_secondary_text), Fill_mix)
			end
		ensure
			rgb: Result <= 0xFFFFFF
		end

	band_color: NATURAL_32
			-- The band's color now, 0xRRGGBB, drawn at `Band_alpha': the theme's secondary text
			-- (SW_THEME.ink_muted on Windows).
		require
			available: application.is_available
		do
			Result := application.system_color (application.Color_secondary_text)
		ensure
			rgb: Result <= 0xFFFFFF
		end

	phase: INTEGER
			-- Where the band is now: 0 to `Phase_count' - 1 steps across, from the clock's time
			-- since the sweep began (0 before it has).
		local
			l_since: INTEGER_64
		do
			if is_sweep_started then
				l_since := (application.animation_clock.now_ms - sweep_origin_ms).max (0)
				Result := ((l_since \\ Sweep_ms) * Phase_count // Sweep_ms).to_integer_32
			end
		ensure
			in_range: 0 <= Result and Result < Phase_count
		end

feature -- Status report

	has_shimmer: BOOLEAN
			-- Does the band sweep (unless motion is reduced)? Yes by default.

	is_shimmering: BOOLEAN
			-- Is the band sweeping now, on the clock?
		do
			Result := attached sweep as al_sweep and then application.animation_clock.has (al_sweep)
		end

	shows_band: BOOLEAN
			-- Is the band drawn: shimmer on and motion not reduced?
		do
			Result := has_shimmer and not application.reduces_motion
		end

feature -- Element change

	set_shimmer (a_on: BOOLEAN)
			-- Sweep the band (`a_on'), or let the shapes stand still with no band.
		require
			gui_thread: is_gui_thread
		do
			has_shimmer := a_on
			if a_on then
				keep_sweeping
			else
				stop_sweep
			end
			refresh
		ensure
			set: has_shimmer = a_on
			still_when_off: not a_on implies not is_shimmering
		end

feature -- Status setting

	show
			-- Show the skeleton; the band sweeps again.
		do
			is_paused := False
			Precursor
			keep_sweeping
		end

	hide
			-- Hide the skeleton; the band stops, so the clock may rest.
		do
			is_paused := True
			stop_sweep
			Precursor
		ensure then
			still: not is_shimmering
		end

feature {NONE} -- Drawing

	new_native (a_width, a_height: INTEGER): INTEGER
			-- A canvas that reads as busy.
		do
			Result := backend.busy_canvas (a_width, a_height)
		end

	draw (a_context: CAIRO_CONTEXT; a_width, a_height: INTEGER)
			-- SW_SKELETON's drawing, at the skeleton's top left: the placeholders, then the band
			-- clipped to each one's box.
		local
			i: INTEGER
			f, ly, lw, rw, rh, d: REAL_64
			l_band: BOOLEAN
			l_fill, l_ink: NATURAL_32
		do
			l_band := shows_band
			drawn_phase := phase
			f := drawn_phase / Phase_count
			l_fill := fill_color
			l_ink := band_color
			inspect shape
			when Shape_disc then
				d := disc_diameter
				a_context.set_color_hex (l_fill).do_nothing
				circle_fill (a_context, d / 2.0, d / 2.0, d / 2.0)
				if l_band then
					a_context.save.clip_rectangle (0.0, 0.0, d, d).do_nothing
					set_band (a_context, l_ink)
					rounded_fill (a_context, f * d - 20.0, 0.0, 40.0, d, 8.0)
					a_context.restore.do_nothing
				end
			when Shape_rect, Shape_fill then
				if shape = Shape_fill then
					rw := a_width
					rh := a_height
				else
					rw := rect_width
					rh := rect_height
				end
				a_context.set_color_hex (l_fill).do_nothing
				rounded_fill (a_context, 0.0, 0.0, rw.min (a_width.to_double), rh, 4.0)
				if l_band then
					a_context.save.clip_rectangle (0.0, 0.0, rw.min (a_width.to_double), rh).do_nothing
					set_band (a_context, l_ink)
					rounded_fill (a_context, f * rw - 30.0, 0.0, 60.0, rh, 4.0)
					a_context.restore.do_nothing
				end
			else
				from i := 0 until i >= line_count loop
					ly := i * (Line_height + Line_gap)
					if i = line_count - 1 and line_count > 1 then
						lw := a_width * Last_line_share
					else
						lw := a_width
					end
					a_context.set_color_hex (l_fill).do_nothing
					rounded_fill (a_context, 0.0, ly, lw, Line_height, Line_height / 2.0)
					if l_band then
						a_context.save.clip_rectangle (0.0, ly, lw, Line_height).do_nothing
						set_band (a_context, l_ink)
						rounded_fill (a_context, f * lw - 30.0, ly, 60.0, Line_height, Line_height / 2.0)
						a_context.restore.do_nothing
					end
					i := i + 1
				end
			end
		end

	set_band (a_context: CAIRO_CONTEXT; a_rgb: NATURAL_32)
			-- Draw in `a_rgb' at `Band_alpha' (SW_PAINTER.set_color_alpha).
		require
			valid: a_context.is_valid
		do
			a_context.set_color_rgba (((a_rgb |>> 16) & 0xFF) / 255.0, ((a_rgb |>> 8) & 0xFF) / 255.0,
				(a_rgb & 0xFF) / 255.0, Band_alpha).do_nothing
		end

	rounded_fill (a_context: CAIRO_CONTEXT; a_x, a_y, a_w, a_h, a_r: REAL_64)
			-- Fill the rectangle with corners of radius `a_r', on the path SW_PAINTER.rrect_path
			-- takes (its arc angles included), so the pixels are the same.
		require
			valid: a_context.is_valid
			radius_non_negative: a_r >= 0.0
		do
			a_context.new_path.do_nothing
			if a_r > 0.0 then
				a_context.arc (a_x + a_w - a_r, a_y + a_r, a_r, -1.5708, 0.0).do_nothing
				a_context.arc (a_x + a_w - a_r, a_y + a_h - a_r, a_r, 0.0, 1.5708).do_nothing
				a_context.arc (a_x + a_r, a_y + a_h - a_r, a_r, 1.5708, 3.1416).do_nothing
				a_context.arc (a_x + a_r, a_y + a_r, a_r, 3.1416, 4.7124).do_nothing
			else
				a_context.move_to (a_x, a_y).line_to (a_x + a_w, a_y).line_to (a_x + a_w, a_y + a_h).line_to (a_x, a_y + a_h).do_nothing
			end
			a_context.close_path.fill.do_nothing
		end

	circle_fill (a_context: CAIRO_CONTEXT; a_cx, a_cy, a_r: REAL_64)
			-- Fill the circle as SW_PAINTER.circle_fill does.
		require
			valid: a_context.is_valid
			positive: a_r > 0.0
		do
			a_context.new_path.arc (a_cx, a_cy, a_r, 0.0, Painter_two_pi).fill.do_nothing
		end

	Painter_two_pi: REAL_64 = 6.28319
			-- SW_PAINTER's full turn (its own rounding, kept so the edge pixels match).

	mixed (a_from, a_to: NATURAL_32; a_share: REAL_64): NATURAL_32
			-- `a_from' moved `a_share' of the way to `a_to', channel by channel (0xRRGGBB).
		require
			share_in_range: a_share >= 0.0 and a_share <= 1.0
		local
			l_shift: INTEGER
			l_a, l_b: REAL_64
		do
			from l_shift := 0 until l_shift > 16 loop
				l_a := ((a_from |>> l_shift) & 0xFF).to_real_64
				l_b := ((a_to |>> l_shift) & 0xFF).to_real_64
				Result := Result | ((l_a + (l_b - l_a) * a_share).rounded.max (0).min (255).to_natural_32 |<< l_shift)
				l_shift := l_shift + 8
			end
		ensure
			rgb: Result <= 0xFFFFFF
		end

	resized
			-- A new size: draw again, and sweep if it should.
		do
			Precursor
			keep_sweeping
		end

feature {NONE} -- Sweeping

	sweep: detachable GUI_ANIMATION
			-- The sweep running or run last.

	is_sweep_started: BOOLEAN
			-- Has a sweep begun since the band last stood still?

	sweep_origin_ms: INTEGER_64
			-- The clock's time when the sweeps began.

	drawn_phase: INTEGER
			-- The `phase' drawn last (-1 before the first frame).

	is_paused: BOOLEAN
			-- Hidden with `hide'?

	appearance_agent: detachable PROCEDURE [TUPLE [dark: BOOLEAN]]
			-- What redraws the skeleton when light and dark switch; Void once it has let go.

	should_sweep: BOOLEAN
			-- Should the band be sweeping: shimmer on, motion allowed, shown, drawn once (it has had a
			-- size), and its window open? Not its size now: GTK answers 0 for a widget shown again
			-- until its next layout, and sends no new size when it is the same as before.
		do
			Result := has_shimmer and not is_paused and not is_let_go and then not application.reduces_motion
				and then frame_count > 0
		end

	keep_sweeping
			-- Start sweeping when it should and is not.
		do
			if should_sweep and not is_shimmering then
				if not is_sweep_started then
					sweep_origin_ms := application.animation_clock.now_ms
					is_sweep_started := True
				end
				start_sweep
			end
		end

	start_sweep
			-- One sweep on the clock, `Sweep_ms' long; the next follows when it ends.
		local
			l_sweep: GUI_ANIMATION
		do
			create l_sweep.make (0.0, 1.0, Sweep_ms, {GUI_EASING}.Linear, agent sweep_step)
			sweep := l_sweep
			l_sweep.finished_actions.extend (agent sweep_ended (l_sweep))
			application.animation_clock.run (l_sweep)
		end

	sweep_step (a_value: REAL_64)
			-- A tick: draw again when the band has moved a step.
		do
			if not is_let_go and then phase /= drawn_phase then
				refresh
			end
		end

	sweep_ended (a_sweep: GUI_ANIMATION)
			-- `a_sweep' arrived. When it ran its whole time (not ended early by the clock's
			-- `finish_all' or reduced motion), the next begins if the band should still sweep.
		do
			if sweep = a_sweep then
				if application.animation_clock.now_ms >= a_sweep.start_ms + Sweep_ms and then should_sweep then
					start_sweep
				else
					sweep := Void
					is_sweep_started := False
					if not is_let_go then
						refresh
					end
				end
			end
		end

	stop_sweep
			-- Stop the band where it is.
		do
			if attached sweep as al_sweep then
				sweep := Void
				application.animation_clock.cancel (al_sweep)
			end
			is_sweep_started := False
		ensure
			still: not is_shimmering
		end

feature {NONE} -- Letting go

	let_go_of_pictures
			-- The window closed: stop sweeping and stop listening for light and dark. The skeleton
			-- holds no pictures of its own.
		do
			stop_sweep
			if attached appearance_agent as al_agent then
				application.appearance_changed_actions.prune (al_agent)
				appearance_agent := Void
			end
		end

invariant
	known_shape: shape >= Shape_lines and shape <= Shape_fill
	lines_positive: line_count >= 1
	phase_drawn_in_range: drawn_phase >= -1 and drawn_phase < Phase_count

end
