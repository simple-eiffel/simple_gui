note
	description: "[
		A picture to look at closely (1z-a): zoom and pan, fit and actual size, and a magnifier
		lens. Drawn by shared code with Cairo on a GUI_CANVAS, so it is the same on all three
		platforms and tested by its pixels.

		Zoom 1.0 is actual size: one image pixel per logical pixel (two device pixels on a 2x
		screen). The pan is the image point at the view's top left, in image pixels. It is
		clamped so the image never leaves a gap it could fill; an image smaller than the view is
		centered. Below 4x the image is drawn with CAIRO_FILTER_GOOD, from 4x up with
		CAIRO_FILTER_NEAREST. Only the visible part is painted, and an image over 4096 pixels on
		a side is kept in tiles of 1024, so only the tiles in view are drawn.

		Input, decided here from the canvas's reports:
		- dragging pans; a click outside the image runs `background_click_actions';
		- the wheel scrolls (Shift + wheel across), and Control or Command + wheel zooms at the
		  pointer (a Windows touchpad's pinch arrives that way);
		- a pinch zooms at its center;
		- a double-click toggles fit and actual size at the pointer;
		- + and - zoom, 0 fits, 1 is actual size, and the arrows pan.

		A new image is shown fitted. While the view stays fitted (no zoom or pan since), it
		fits again when its size changes.
	]"

class
	GUI_IMAGE_VIEW

inherit
	GUI_IMAGE_CANVAS
		redefine
			resized
		end

create
	make

feature {NONE} -- Initialization

	make (a_width, a_height: INTEGER)
			-- A view asking for `a_width' by `a_height' logical pixels, with no image yet.
		require
			gui_thread: is_gui_thread
			has_application: has_application
			sized: a_width > 0 and a_height > 0
		do
				-- every attribute is attached before the canvas registers (it passes Current)
			create zoom_changed_actions.make
			create background_click_actions.make
			create alternate_text.make_empty
			create tiles.make (1)
			make_image_canvas (a_width, a_height)
			zoom := 1.0
			minimum_zoom := Default_minimum_zoom
			maximum_zoom := Default_maximum_zoom
			lens_radius := Default_lens_radius
			lens_zoom := Default_lens_zoom
			is_fitted := True
			arrows_pan := True
			pointer_actions.extend (agent on_pointer)
			key_actions.extend (agent on_key)
			wheel_actions.extend (agent on_wheel)
			magnify_actions.extend (agent on_magnify)
			pointer_leave_actions.extend (agent hide_lens)
		ensure
			no_image: image = Void
			actual_size: zoom = 1.0
			default_range: minimum_zoom = Default_minimum_zoom and maximum_zoom = Default_maximum_zoom
			default_lens: not has_lens and lens_radius = Default_lens_radius and lens_zoom = Default_lens_zoom
			fitted: is_fitted
		end

feature -- Access

	image: detachable IMG_IMAGE
			-- The picture shown.

	is_loaded: BOOLEAN
			-- Did the last `set_file' read a picture? (Otherwise the earlier one stays.)

	alternate_text: STRING_32
			-- What the picture shows, for screen readers (the canvas reads as an image with this
			-- name), and the caption when `shows_caption'.

feature -- Zoom

	zoom: REAL_64
			-- Logical pixels per image pixel: 1.0 is actual size.

	minimum_zoom: REAL_64
			-- The smallest zoom (1/32 unless set).

	maximum_zoom: REAL_64
			-- The largest zoom (32 unless set).

	Default_minimum_zoom: REAL_64 = 0.03125
	Default_maximum_zoom: REAL_64 = 32.0

	is_fitted: BOOLEAN
			-- Is the whole image shown, centered, as `zoom_to_fit' left it (and kept so while the
			-- view's size changes)? A zoom or a pan ends it.

	fit_may_enlarge: BOOLEAN
			-- May fitting zoom past actual size? (No by default.)

	fit_zoom: REAL_64
			-- The zoom `zoom_to_fit' gives now: the whole image in the frame, never above 1.0
			-- unless `fit_may_enlarge', within the zoom range (1.0 with no image or no size yet).
		do
			Result := 1.0
			if attached image as al_image and then frame_width > 0.0 and then frame_height > 0.0 then
				Result := (frame_width / al_image.width).min (frame_height / al_image.height)
				if not fit_may_enlarge then
					Result := Result.min (1.0)
				end
			end
			Result := Result.max (minimum_zoom).min (maximum_zoom)
		ensure
			in_range: Result >= minimum_zoom and Result <= maximum_zoom
		end

	zoom_changed_actions: GUI_ACTIONS [TUPLE [zoom: REAL_64]]
			-- Run with the new zoom whenever it changes.

	Key_zoom_step: REAL_64 = 1.25
			-- The zoom + and - make.

feature -- Pan

	pan_x, pan_y: REAL_64
			-- The image point at the view's top left, in image pixels (negative while a smaller
			-- image is centered).

	image_x_at (a_x: REAL_64): REAL_64
			-- The image's x under view point x (logical pixels).
		do
			Result := pan_x + a_x / zoom
		end

	image_y_at (a_y: REAL_64): REAL_64
			-- The image's y under view point y.
		do
			Result := pan_y + a_y / zoom
		end

	view_x_of (an_image_x: REAL_64): REAL_64
			-- Where image x shows in the view, logical pixels.
		do
			Result := (an_image_x - pan_x) * zoom
		end

	view_y_of (an_image_y: REAL_64): REAL_64
			-- Where image y shows in the view.
		do
			Result := (an_image_y - pan_y) * zoom
		end

	is_on_image (a_x, a_y: REAL_64): BOOLEAN
			-- Does view point (x, y) show the image?
		do
			if attached image as al_image then
				Result := image_x_at (a_x) >= 0.0 and image_x_at (a_x) < al_image.width
					and image_y_at (a_y) >= 0.0 and image_y_at (a_y) < al_image.height
			end
		end

	Pan_step: INTEGER = 48
			-- How far an arrow or a wheel notch moves the view, logical pixels.

feature -- Lens

	has_lens: BOOLEAN
			-- Does a magnifier lens follow the pointer?

	lens_radius: INTEGER
			-- Its radius, logical pixels (80 unless set).

	lens_zoom: REAL_64
			-- Its magnification relative to the view's zoom (3 unless set).

	Default_lens_radius: INTEGER = 80
	Default_lens_zoom: REAL_64 = 3.0

	is_lens_shown: BOOLEAN
			-- Is the lens showing now (the pointer over the view)?

	lens_x, lens_y: INTEGER
			-- Where its center is, logical pixels (the pointer).

feature -- Frame and caption

	fit_margin: INTEGER
			-- Logical pixels kept clear around a fitted image (0 unless set; a lightbox's).

	shows_caption: BOOLEAN
			-- Is `alternate_text' shown as a caption under the image?

	arrows_pan: BOOLEAN
			-- Do the arrow keys pan? (Yes unless set: a lightbox uses them to move through its
			-- images.)

	Caption_height: INTEGER = 32
			-- The strip a caption takes under the frame, logical pixels.

	background_click_actions: GUI_ACTIONS [TUPLE [x, y: INTEGER]]
			-- Run on a click (a press and release that did not drag) outside the image.

feature -- Tiles

	tile_count: INTEGER
			-- How many cairo surfaces hold the image: 1, or its tiles when it is over
			-- `Tiled_above' pixels on a side.
		do
			Result := tiles.count
		end

	tiles_painted: INTEGER
			-- How many of them the last frame drew: only those in view.

	Tile_size: INTEGER = 1024
	Tiled_above: INTEGER = 4096

feature -- Element change

	set_image (an_image: IMG_IMAGE)
			-- Show `an_image', fitted.
		require
			gui_thread: is_gui_thread
			usable: an_image.is_usable
		do
			image := an_image
			make_tiles (an_image)
			zoom_to_fit
		ensure
			shown: image = an_image
			fitted: is_fitted
		end

	set_file (a_path: PATH)
			-- Show the picture in `a_path' (read by simple_image), fitted; keep the one shown when
			-- it can't be read.
		require
			gui_thread: is_gui_thread
		do
			if attached (create {SIMPLE_IMAGE}.make).load (a_path.name) as al_image then
				is_loaded := True
				set_image (al_image)
			else
				is_loaded := False
			end
		end

	set_alternate_text (a_text: READABLE_STRING_GENERAL)
			-- Say what the picture shows (screen readers read the view as an image so named).
		require
			gui_thread: is_gui_thread
		do
			alternate_text := a_text.to_string_32
			set_accessible_label (a_text)
			if shows_caption then
				refit_or_refresh
			end
		ensure
			set: alternate_text.same_string_general (a_text)
		end

	set_zoom (a_zoom: REAL_64)
			-- Zoom to `a_zoom' (within the range) about the view's center.
		require
			gui_thread: is_gui_thread
			positive: a_zoom > 0.0
		do
			zoom_at (a_zoom, width / 2, height / 2)
		ensure
			in_range: zoom >= minimum_zoom and zoom <= maximum_zoom
			not_fitted: not is_fitted
		end

	zoom_at (a_zoom: REAL_64; a_x, a_y: REAL_64)
			-- Zoom to `a_zoom' (within the range), keeping the image point under view point
			-- (`a_x', `a_y') where it is, as far as the pan's clamp allows.
		require
			gui_thread: is_gui_thread
			positive: a_zoom > 0.0
		local
			l_x, l_y: REAL_64
		do
			l_x := image_x_at (a_x)
			l_y := image_y_at (a_y)
			apply_zoom (a_zoom)
			pan_x := l_x - a_x / zoom
			pan_y := l_y - a_y / zoom
			clamp_pan
			is_fitted := False
			refresh
		ensure
			in_range: zoom >= minimum_zoom and zoom <= maximum_zoom
			not_fitted: not is_fitted
		end

	zoom_to_fit
			-- Show the whole image, centered in the frame (`fit_zoom').
		require
			gui_thread: is_gui_thread
		do
			apply_zoom (fit_zoom)
			clamp_pan
			is_fitted := True
			refresh
		ensure
			fitted: is_fitted
			fit: zoom = fit_zoom
		end

	actual_size
			-- Zoom to 1.0 about the view's center.
		require
			gui_thread: is_gui_thread
		do
			set_zoom (1.0)
		ensure
			actual: (minimum_zoom <= 1.0 and 1.0 <= maximum_zoom) implies zoom = 1.0
		end

	set_zoom_range (a_minimum, a_maximum: REAL_64)
			-- Keep the zoom from `a_minimum' to `a_maximum'.
		require
			gui_thread: is_gui_thread
			positive: a_minimum > 0.0
			ordered: a_minimum <= a_maximum
		do
			minimum_zoom := a_minimum
			maximum_zoom := a_maximum
			if is_fitted then
				zoom_to_fit
			elseif zoom < a_minimum or zoom > a_maximum then
				set_zoom (zoom)
			end
		ensure
			set: minimum_zoom = a_minimum and maximum_zoom = a_maximum
			in_range: zoom >= minimum_zoom and zoom <= maximum_zoom
		end

	set_fit_may_enlarge (a_on: BOOLEAN)
			-- Let fitting zoom past actual size (`a_on'), or not.
		require
			gui_thread: is_gui_thread
		do
			fit_may_enlarge := a_on
			if is_fitted then
				zoom_to_fit
			end
		ensure
			set: fit_may_enlarge = a_on
		end

	set_pan (a_x, a_y: REAL_64)
			-- Put image point (`a_x', `a_y') at the view's top left, clamped so the image leaves
			-- no gap it could fill.
		require
			gui_thread: is_gui_thread
		do
			pan_x := a_x
			pan_y := a_y
			clamp_pan
			is_fitted := False
			refresh
		ensure
			not_fitted: not is_fitted
		end

	pan_by (a_dx, a_dy: REAL_64)
			-- Move the pan by (`a_dx', `a_dy') image pixels, clamped.
		require
			gui_thread: is_gui_thread
		do
			set_pan (pan_x + a_dx, pan_y + a_dy)
		ensure
			not_fitted: not is_fitted
		end

	set_lens (a_on: BOOLEAN)
			-- Show a magnifier lens at the pointer while it is over the view (`a_on'), or not.
		require
			gui_thread: is_gui_thread
		do
			has_lens := a_on
			if not a_on and is_lens_shown then
				hide_lens
			end
		ensure
			set: has_lens = a_on
		end

	set_lens_radius (a_radius: INTEGER)
			-- The lens's radius, logical pixels.
		require
			gui_thread: is_gui_thread
			positive: a_radius > 0
		do
			lens_radius := a_radius
			if is_lens_shown then
				refresh
			end
		ensure
			set: lens_radius = a_radius
		end

	set_lens_zoom (a_factor: REAL_64)
			-- The lens's magnification relative to the view's zoom.
		require
			gui_thread: is_gui_thread
			positive: a_factor > 0.0
		do
			lens_zoom := a_factor
			if is_lens_shown then
				refresh
			end
		ensure
			set: lens_zoom = a_factor
		end

	set_fit_margin (a_margin: INTEGER)
			-- Keep `a_margin' logical pixels clear around a fitted image.
		require
			gui_thread: is_gui_thread
			not_negative: a_margin >= 0
		do
			fit_margin := a_margin
			refit_or_refresh
		ensure
			set: fit_margin = a_margin
		end

	set_shows_caption (a_on: BOOLEAN)
			-- Show `alternate_text' as a caption under the image (`a_on'), or not.
		require
			gui_thread: is_gui_thread
		do
			shows_caption := a_on
			refit_or_refresh
		ensure
			set: shows_caption = a_on
		end

	set_arrows_pan (a_on: BOOLEAN)
			-- Let the arrow keys pan (`a_on'), or leave them to the program.
		require
			gui_thread: is_gui_thread
		do
			arrows_pan := a_on
		ensure
			set: arrows_pan = a_on
		end

feature -- Lens

	hide_lens
			-- Take the lens away until the pointer moves over the view again.
		require
			gui_thread: is_gui_thread
		do
			if is_lens_shown then
				is_lens_shown := False
				refresh
			end
		ensure
			hidden: not is_lens_shown
		end

feature {NONE} -- Zoom and pan

	apply_zoom (a_zoom: REAL_64)
			-- Set `zoom' to `a_zoom' within the range, and say so when it changed.
		require
			positive: a_zoom > 0.0
		local
			l_old: REAL_64
		do
			l_old := zoom
			zoom := a_zoom.max (minimum_zoom).min (maximum_zoom)
			if zoom /= l_old then
				zoom_changed_actions.call ([zoom])
			end
		ensure
			in_range: zoom >= minimum_zoom and zoom <= maximum_zoom
		end

	clamp_pan
			-- Keep the image covering the frame where it can, and centered in it where it is
			-- smaller, on each axis.
		do
			if attached image as al_image then
				pan_x := clamped (pan_x, al_image.width, fit_margin, frame_width)
				pan_y := clamped (pan_y, al_image.height, fit_margin, frame_height)
			end
		end

	clamped (a_pan: REAL_64; a_size: INTEGER; a_start, a_extent: REAL_64): REAL_64
			-- `a_pan' on one axis, for an image `a_size' pixels long and a frame from view
			-- point `a_start', `a_extent' long: centered when the image fits in it, else with
			-- the frame covered.
		local
			l_shown: REAL_64
		do
			l_shown := a_size * zoom
			if l_shown <= a_extent then
				Result := - (a_start + (a_extent - l_shown) / 2.0) / zoom
			else
				Result := a_pan.max (- a_start / zoom).min (a_size - (a_start + a_extent) / zoom)
			end
		end

	frame_width: REAL_64
			-- The width a fitted image fits in: the view's, less the margins.
		do
			Result := (width - 2 * fit_margin).max (0)
		ensure
			not_negative: Result >= 0.0
		end

	frame_height: REAL_64
			-- The height a fitted image fits in: the view's, less the margins and the caption.
		do
			Result := (height - 2 * fit_margin - caption_space).max (0)
		ensure
			not_negative: Result >= 0.0
		end

	caption_space: INTEGER
			-- `Caption_height' while a caption shows, else 0.
		do
			if shows_caption and not alternate_text.is_empty then
				Result := Caption_height
			end
		end

	refit_or_refresh
			-- Fit again while fitted, else clamp the pan; then draw.
		do
			if is_fitted then
				zoom_to_fit
			else
				clamp_pan
				refresh
			end
		end

	resized
			-- A new size: fit again while fitted, else keep the pan clamped.
		do
			refit_or_refresh
		end

feature {NONE} -- Tiles

	tiles: ARRAYED_LIST [TUPLE [surface: CAIRO_SURFACE; x, y: INTEGER]]
			-- The image as cairo surfaces, each with its top left in image pixels.

	make_tiles (an_image: IMG_IMAGE)
			-- Hold `an_image' as one cairo surface, or in tiles of `Tile_size' when it is over
			-- `Tiled_above' pixels on a side.
		require
			usable: an_image.is_usable
		local
			l_x, l_y, l_w, l_h: INTEGER
			l_part: IMG_IMAGE
		do
			let_go_of_pictures
			if an_image.width > Tiled_above or an_image.height > Tiled_above then
				from l_y := 0 until l_y >= an_image.height loop
					l_h := Tile_size.min (an_image.height - l_y)
					from l_x := 0 until l_x >= an_image.width loop
						l_w := Tile_size.min (an_image.width - l_x)
						l_part := an_image.cropped (l_x, l_y, l_w, l_h)
						tiles.extend ([l_part.to_cairo_surface, l_x, l_y])
						l_part.destroy
						l_x := l_x + Tile_size
					end
					l_y := l_y + Tile_size
				end
			else
				tiles.extend ([an_image.to_cairo_surface, 0, 0])
			end
		ensure
			held: tile_count >= 1
		end

	let_go_of_pictures
			-- Destroy the tiles.
		do
			across tiles as ic loop
				ic.surface.destroy
			end
			tiles.wipe_out
		ensure then
			none: tile_count = 0
		end

feature {NONE} -- Drawing

	draw (a_context: CAIRO_CONTEXT; a_width, a_height: INTEGER)
			-- The visible part of the image, the caption and the lens.
		do
			tiles_painted := 0
			if image /= Void then
				a_context.save.rectangle (0.0, 0.0, a_width, a_height).clip.do_nothing
				paint_tiles (a_context, zoom, pan_x, pan_y, 0.0, 0.0, a_width, a_height)
				a_context.restore.do_nothing
				if caption_space > 0 then
					paint_caption (a_context, a_width, a_height)
				end
				if is_lens_shown then
					paint_lens (a_context)
				end
			end
		end

	paint_tiles (a_context: CAIRO_CONTEXT; a_zoom, a_pan_x, a_pan_y, a_left, a_top, a_width, a_height: REAL_64)
			-- The tiles that meet view rectangle (`a_left', `a_top', `a_width', `a_height'), at
			-- `a_zoom' with image point (`a_pan_x', `a_pan_y') at view point (0, 0).
		require
			valid: a_context.is_valid
			positive: a_zoom > 0.0
		local
			l_left, l_top, l_right, l_bottom: REAL_64
		do
			l_left := a_pan_x + a_left / a_zoom
			l_top := a_pan_y + a_top / a_zoom
			l_right := a_pan_x + (a_left + a_width) / a_zoom
			l_bottom := a_pan_y + (a_top + a_height) / a_zoom
			if tiles.count > 1 then
					-- tile edges on whole device pixels, so neighbors meet with no seam
				a_context.set_antialias ({CAIRO_CONTEXT}.Antialias_none).do_nothing
			end
			across tiles as ic loop
				if ic.x < l_right and ic.x + ic.surface.width > l_left and ic.y < l_bottom and ic.y + ic.surface.height > l_top then
					paint_scaled (a_context, ic.surface, (ic.x - a_pan_x) * a_zoom, (ic.y - a_pan_y) * a_zoom, a_zoom, a_zoom)
					tiles_painted := tiles_painted + 1
				end
			end
			a_context.set_antialias ({CAIRO_CONTEXT}.Antialias_default).do_nothing
		end

	paint_caption (a_context: CAIRO_CONTEXT; a_width, a_height: INTEGER)
			-- `alternate_text', centered in the strip under the frame.
		require
			valid: a_context.is_valid
		local
			l_text_width: REAL_64
		do
			a_context.select_font ("Sans", 0, 0).set_font_size (Caption_font_size).do_nothing
			l_text_width := a_context.text_width (alternate_text)
			a_context.set_color_hex_alpha (Caption_color).do_nothing
			a_context.move_to (((a_width - l_text_width) / 2.0).max (fit_margin), a_height - fit_margin - Caption_height / 2 + Caption_font_size / 3).do_nothing
			a_context.show_text (alternate_text).do_nothing
		end

	Caption_font_size: REAL_64 = 15.0
	Caption_color: NATURAL_32 = 0xFFFFFFFF

	paint_lens (a_context: CAIRO_CONTEXT)
			-- The lens at the pointer: a circle showing the image `lens_zoom' times larger, the
			-- point under the pointer at its center, with a soft shadow and a 1 pixel border.
		require
			valid: a_context.is_valid
		local
			l_x, l_y, l_r, l_zoom: REAL_64
			i: INTEGER
		do
			l_x := lens_x + 0.0
			l_y := lens_y + 0.0
			l_r := lens_radius
			l_zoom := zoom * lens_zoom
			from i := 4 until i < 1 loop
				a_context.set_color_rgba (0.0, 0.0, 0.0, 0.06).fill_circle (l_x, l_y + 2.0, l_r + i).do_nothing
				i := i - 1
			end
			a_context.save.arc (l_x, l_y, l_r, 0.0, 2.0 * {MATH_CONST}.Pi).clip.do_nothing
			a_context.set_color_hex_alpha (Lens_backing).paint.do_nothing
			paint_tiles (a_context, l_zoom, image_x_at (l_x) - l_x / l_zoom, image_y_at (l_y) - l_y / l_zoom, l_x - l_r, l_y - l_r, 2.0 * l_r, 2.0 * l_r)
			a_context.restore.do_nothing
			a_context.set_line_width (1.0).set_color_hex_alpha (Lens_border).stroke_circle (l_x, l_y, l_r - 0.5).do_nothing
		end

	Lens_backing: NATURAL_32 = 0xFF808080
			-- What the lens shows beyond the image's edge.

	Lens_border: NATURAL_32 = 0xFF505050

feature {NONE} -- Input

	press_x, press_y: INTEGER
			-- Where the button went down.

	press_pan_x, press_pan_y: REAL_64
			-- The pan then.

	is_pressed: BOOLEAN
			-- Is a button held (since a press on this view)?

	has_dragged: BOOLEAN
			-- Did the pointer move far enough while held to be a drag?

	last_press_ms: REAL_64
			-- When the last press was, for double-clicks.

	last_press_x, last_press_y: INTEGER
			-- Where it was.

	Double_click_ms: REAL_64 = 400.0
	Click_slop: INTEGER = 4
			-- A second press this soon and this near is a double-click; a press that moves less
			-- than the slop is a click.

	on_pointer (a_kind, a_x, a_y, a_button, a_modifiers: INTEGER)
			-- Drags pan, a double-click toggles fit and actual size, and the lens follows.
		local
			l_now: REAL_64
		do
			inspect a_kind
			when 1 then
				l_now := backend.clock_ms
				if l_now - last_press_ms <= Double_click_ms and (a_x - last_press_x).abs <= Click_slop and (a_y - last_press_y).abs <= Click_slop then
					last_press_ms := 0.0
					toggle_fit (a_x, a_y)
				else
					last_press_ms := l_now
					last_press_x := a_x
					last_press_y := a_y
				end
				is_pressed := True
				has_dragged := False
				press_x := a_x
				press_y := a_y
				press_pan_x := pan_x
				press_pan_y := pan_y
			when 2 then
				if is_pressed and not has_dragged and not is_on_image (a_x, a_y) then
					background_click_actions.call ([a_x, a_y])
				end
				is_pressed := False
			when 3 then
				if is_pressed and ((a_x - press_x).abs > Click_slop or (a_y - press_y).abs > Click_slop) then
					has_dragged := True
				end
				if has_lens then
					lens_x := a_x
					lens_y := a_y
					is_lens_shown := True
				end
				if is_pressed and has_dragged then
					set_pan (press_pan_x - (a_x - press_x) / zoom, press_pan_y - (a_y - press_y) / zoom)
				elseif has_lens then
					refresh
				end
			else
			end
		end

	toggle_fit (a_x, a_y: INTEGER)
			-- Fitted: actual size at the pointer; otherwise fit.
		do
			if is_fitted then
				zoom_at (1.0, a_x, a_y)
			else
				zoom_to_fit
			end
		end

	on_key (a_key: INTEGER; a_character: CHARACTER_32; a_modifiers: INTEGER)
			-- + and - zoom, 0 fits, 1 is actual size, the arrows pan.
		do
			if a_key = Key_plus or a_key = Key_equal or a_key = Key_pad_plus then
				set_zoom (zoom * Key_zoom_step)
			elseif a_key = Key_minus or a_key = Key_pad_minus then
				set_zoom (zoom / Key_zoom_step)
			elseif a_key = Key_zero or a_key = Key_pad_zero then
				zoom_to_fit
			elseif a_key = Key_one or a_key = Key_pad_one then
				actual_size
			elseif arrows_pan then
				inspect a_key
				when Key_left then pan_by (- Pan_step / zoom, 0.0)
				when Key_right then pan_by (Pan_step / zoom, 0.0)
				when Key_up then pan_by (0.0, - Pan_step / zoom)
				when Key_down then pan_by (0.0, Pan_step / zoom)
				else
				end
			end
		end

	on_wheel (an_amount, a_modifiers, a_x, a_y: INTEGER)
			-- Control or Command + wheel zooms at the pointer; Shift + wheel pans across; the
			-- wheel alone pans up and down.
		local
			l_notches: REAL_64
		do
			l_notches := an_amount / 120.0
			if (a_modifiers & (Modifier_control | Modifier_command)) /= 0 then
				zoom_at (zoom * (Wheel_zoom_step ^ l_notches), a_x, a_y)
			elseif (a_modifiers & Modifier_shift) /= 0 then
				pan_by (- l_notches * Pan_step / zoom, 0.0)
			else
				pan_by (0.0, - l_notches * Pan_step / zoom)
			end
		end

	on_magnify (a_factor: REAL_64; a_x, a_y: INTEGER)
			-- A pinch zooms at its center.
		do
			if a_factor > 0.0 then
				zoom_at (zoom * a_factor, a_x, a_y)
			end
		end

	Modifier_shift: INTEGER = 1
	Modifier_control: INTEGER = 2
	Modifier_command: INTEGER = 8

	Key_plus: INTEGER = 0x2B
	Key_equal: INTEGER = 0x3D
	Key_minus: INTEGER = 0x2D
	Key_zero: INTEGER = 0x30
	Key_one: INTEGER = 0x31
	Key_pad_plus: INTEGER = 0xFFAB
	Key_pad_minus: INTEGER = 0xFFAD
	Key_pad_zero: INTEGER = 0xFFB0
	Key_pad_one: INTEGER = 0xFFB1
	Key_left: INTEGER = 0xFF51
	Key_up: INTEGER = 0xFF52
	Key_right: INTEGER = 0xFF53
	Key_down: INTEGER = 0xFF54
			-- The keys, as the canvas reports them (GDK's key codes on every platform).

invariant
	zoom_in_range: zoom >= minimum_zoom and zoom <= maximum_zoom
	range_ordered: 0.0 < minimum_zoom and minimum_zoom <= maximum_zoom
	lens_sized: lens_radius > 0 and lens_zoom > 0.0
	margin_not_negative: fit_margin >= 0
	image_held: (image /= Void and not is_let_go) implies tile_count >= 1

end
