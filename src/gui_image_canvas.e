note
	description: "[
		A canvas that shows pictures, drawn by shared code with Cairo (1z-a): the parent of
		GUI_IMAGE_VIEW and GUI_IMAGE_COMPARE. It draws a whole frame on request at the canvas's
		device scale (its background, then what the child draws in logical pixels), and lets
		its pictures go when its window closes: a cairo surface is freed only by `destroy',
		never by the garbage collector.

		Filters are the same on all three platforms: CAIRO_FILTER_GOOD below 4x, and
		CAIRO_FILTER_NEAREST from 4x up, so pixels stay crisp when inspected.
	]"

deferred class
	GUI_IMAGE_CANVAS

inherit
	GUI_CANVAS
		rename
			make as make_canvas
		end

feature {NONE} -- Initialization

	make_image_canvas (a_width, a_height: INTEGER)
			-- A canvas asking for `a_width' by `a_height' logical pixels, transparent, that draws
			-- again whenever its size changes.
		require
			gui_thread: is_gui_thread
			has_application: has_application
			sized: a_width > 0 and a_height > 0
		local
			l_closed: PROCEDURE [TUPLE [window: GUI_WINDOW]]
		do
			make_canvas (a_width, a_height)
			l_closed := agent window_closed
			window_closed_agent := l_closed
			application.window_closed_actions.extend (l_closed)
			resize_actions.extend (agent (a_w, a_h: INTEGER) do resized end)
		ensure
			transparent: background_color = 0
			holding: not is_let_go
		end

feature -- Access

	background_color: NATURAL_32
			-- What shows where no picture is, as 0xAARRGGBB with straight alpha; transparent
			-- (0) by default, so the window's own background shows through.

	frame_count: INTEGER
			-- How many frames have been presented.

	is_let_go: BOOLEAN
			-- Has the canvas let its pictures go (its window closed)? It draws no more.

feature -- Element change

	set_background_color (a_color: NATURAL_32)
			-- Show `a_color' where no picture is.
		require
			gui_thread: is_gui_thread
		do
			background_color := a_color
			refresh
		ensure
			set: background_color = a_color
		end

feature -- Drawing

	refresh
			-- Draw the canvas now, at its device scale, and present it. Nothing while it has no
			-- size yet (it draws when its first size arrives) or once it has let go.
		require
			gui_thread: is_gui_thread
		local
			l_frame: CAIRO_SURFACE
			l_context: CAIRO_CONTEXT
			w, h: INTEGER
			l_scale: REAL_64
		do
			w := pixel_width
			h := pixel_height
			if w > 0 and h > 0 and not is_let_go then
				l_scale := scale
				create l_frame.make (w, h)
				create l_context.make (l_frame)
				l_context.scale (l_scale, l_scale).do_nothing
				if background_color /= 0 then
					l_context.set_color_hex_alpha (background_color).paint.do_nothing
				end
				draw (l_context, width, height)
				l_context.destroy
				present (l_frame)
				l_frame.destroy
				frame_count := frame_count + 1
			end
		end

feature {NONE} -- Drawing

	draw (a_context: CAIRO_CONTEXT; a_width, a_height: INTEGER)
			-- Draw over the background, in logical pixels, on a view `a_width' by `a_height'.
		require
			valid: a_context.is_valid
			sized: a_width > 0 and a_height > 0
		deferred
		end

	resized
			-- The canvas has a new size: draw again.
		do
			refresh
		end

	paint_scaled (a_context: CAIRO_CONTEXT; a_surface: CAIRO_SURFACE; a_x, a_y, a_scale_x, a_scale_y: REAL_64)
			-- `a_surface' with its top left at (`a_x', `a_y'), `a_scale_x' logical pixels to each
			-- of its pixels across and `a_scale_y' down, through the clip, filtered for the larger
			-- of the two. Its edges are padded, so neighboring tiles meet without a seam.
		require
			valid: a_context.is_valid
			surface_valid: a_surface.is_valid
			positive_scales: a_scale_x > 0.0 and a_scale_y > 0.0
		local
			l_pattern: CAIRO_SURFACE_PATTERN
		do
			create l_pattern.make_from_surface (a_surface)
			l_pattern.set_filter (filter_for (a_scale_x.max (a_scale_y))).set_extend ({CAIRO_PATTERN}.Extend_pad).do_nothing
			a_context.save.translate (a_x, a_y).scale (a_scale_x, a_scale_y).do_nothing
			a_context.set_pattern (l_pattern).rectangle (0.0, 0.0, a_surface.width, a_surface.height).fill.restore.do_nothing
			l_pattern.destroy
		end

	filter_for (a_zoom: REAL_64): INTEGER
			-- The source filter at `a_zoom': nearest from `Nearest_from' up, good below.
		do
			if a_zoom >= Nearest_from then
				Result := {CAIRO_PATTERN}.Filter_nearest
			else
				Result := {CAIRO_PATTERN}.Filter_good
			end
		ensure
			nearest_when_inspected: a_zoom >= Nearest_from implies Result = {CAIRO_PATTERN}.Filter_nearest
			good_below: a_zoom < Nearest_from implies Result = {CAIRO_PATTERN}.Filter_good
		end

	Nearest_from: REAL_64 = 4.0
			-- From this zoom up, pixels are drawn as crisp blocks.

feature {NONE} -- Letting go

	let_go_of_pictures
			-- Destroy every cairo surface this canvas holds.
		deferred
		end

	window_closed_agent: detachable PROCEDURE [TUPLE [window: GUI_WINDOW]]
			-- What `make_image_canvas' gave the application's `window_closed_actions'; Void once
			-- this canvas has let go.

	window_closed (a_window: GUI_WINDOW)
			-- `a_window' closed: if this canvas was in it, let its pictures go.
		do
			if enclosing_window = a_window then
				is_let_go := True
				let_go_of_pictures
				if attached window_closed_agent as al_agent then
					application.window_closed_actions.prune (al_agent)
					window_closed_agent := Void
				end
			end
		end

invariant
	let_go_means_unhooked: is_let_go implies window_closed_agent = Void

end
