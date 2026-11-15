note
	description: "[
		A before-and-after comparison slider (1z-a): two pictures fitted the same, the before
		picture on one side of a divider and the after picture on the other. Drawn by shared
		code with Cairo on a GUI_CANVAS, so it is the same on all three platforms.

		The divider runs from 0 (all after) to 1 (all before), 0.5 by default: before is left
		of it (above it with `set_vertical'), after right of it (below). Dragging its handle
		moves it; the arrow keys move it by 1%, and Shift + arrow by 10%.
	]"

class
	GUI_IMAGE_COMPARE

inherit
	GUI_IMAGE_CANVAS

create
	make

feature {NONE} -- Initialization

	make (a_before, an_after: IMG_IMAGE)
			-- Compare `a_before' with `an_after'. The canvas asks for the before picture's size,
			-- scaled down to fit `Largest_asked_width' by `Largest_asked_height'.
		require
			gui_thread: is_gui_thread
			has_application: has_application
			before_usable: a_before.is_usable
			after_usable: an_after.is_usable
		local
			l_fit: REAL_64
		do
				-- every attribute is attached before the canvas registers (it passes Current)
			before := a_before
			after := an_after
			before_surface := a_before.to_cairo_surface
			after_surface := an_after.to_cairo_surface
			divider := 0.5
			create divider_changed_actions.make
			l_fit := (Largest_asked_width / a_before.width).min (Largest_asked_height / a_before.height).min (1.0)
			make_image_canvas ((a_before.width * l_fit).rounded.max (1), (a_before.height * l_fit).rounded.max (1))
			pointer_actions.extend (agent on_pointer)
			key_actions.extend (agent on_key)
		ensure
			before_set: before = a_before
			after_set: after = an_after
			halfway: divider = 0.5
			side_by_side: not is_vertical
		end

feature -- Access

	before: IMG_IMAGE
			-- The picture before the change.

	after: IMG_IMAGE
			-- The picture after it.

	divider: REAL_64
			-- Where the divider is across the pictures (down them when vertical), 0 to 1.

	is_vertical: BOOLEAN
			-- Is the split top and bottom (before above) rather than left and right?

	divider_changed_actions: GUI_ACTIONS [TUPLE [divider: REAL_64]]
			-- Run with the new place whenever the divider moves.

	Largest_asked_width: INTEGER = 480
	Largest_asked_height: INTEGER = 360

	Key_step: REAL_64 = 0.01
	Shift_key_step: REAL_64 = 0.1
			-- How far an arrow, and Shift + arrow, moves the divider.

feature -- Where the pictures show

	picture_left: REAL_64
			-- Where the fitted pictures' left edge is, logical pixels.
		do
			Result := (width - picture_width) / 2.0
		end

	picture_top: REAL_64
			-- Where their top edge is.
		do
			Result := (height - picture_height) / 2.0
		end

	picture_width: REAL_64
			-- How wide they show: the before picture fitted to the view, keeping its proportions.
		do
			Result := before.width * fit_scale
		end

	picture_height: REAL_64
			-- How tall they show.
		do
			Result := before.height * fit_scale
		end

	divider_position: REAL_64
			-- Where the divider is in the view: its x, or its y when vertical.
		do
			if is_vertical then
				Result := picture_top + divider * picture_height
			else
				Result := picture_left + divider * picture_width
			end
		end

feature -- Element change

	set_divider (a_divider: REAL_64)
			-- Put the divider at `a_divider' (clamped to 0 .. 1).
		require
			gui_thread: is_gui_thread
		local
			l_new: REAL_64
		do
			l_new := a_divider.max (0.0).min (1.0)
			if l_new /= divider then
				divider := l_new
				refresh
				divider_changed_actions.call ([divider])
			end
		ensure
			clamped: divider = a_divider.max (0.0).min (1.0)
		end

	set_vertical (a_on: BOOLEAN)
			-- Split top and bottom (`a_on') or left and right.
		require
			gui_thread: is_gui_thread
		do
			is_vertical := a_on
			refresh
		ensure
			set: is_vertical = a_on
		end

feature {NONE} -- Drawing

	before_surface, after_surface: CAIRO_SURFACE
			-- The pictures as cairo surfaces.

	fit_scale: REAL_64
			-- Logical pixels per pixel of the before picture, fitted to the view (enlarged too).
		do
			if width > 0 and height > 0 then
				Result := (width / before.width).min (height / before.height)
			else
				Result := 1.0
			end
		ensure
			positive: Result > 0.0
		end

	draw (a_context: CAIRO_CONTEXT; a_width, a_height: INTEGER)
			-- The before picture, the after picture clipped to its side, and the handle.
		local
			l_x, l_y, l_w, l_h, l_at: REAL_64
		do
			if not is_let_go then
				l_x := picture_left
				l_y := picture_top
				l_w := picture_width
				l_h := picture_height
				l_at := divider_position
				paint_scaled (a_context, before_surface, l_x, l_y, l_w / before.width, l_h / before.height)
				a_context.save.do_nothing
				if is_vertical then
					a_context.rectangle (l_x, l_at, l_w, (l_y + l_h - l_at).max (0.0)).clip.do_nothing
				else
					a_context.rectangle (l_at, l_y, (l_x + l_w - l_at).max (0.0), l_h).clip.do_nothing
				end
				paint_scaled (a_context, after_surface, l_x, l_y, l_w / after.width, l_h / after.height)
				a_context.restore.do_nothing
				paint_handle (a_context, l_x, l_y, l_w, l_h, l_at)
			end
		end

	paint_handle (a_context: CAIRO_CONTEXT; a_x, a_y, a_w, a_h, a_at: REAL_64)
			-- The divider's line across the pictures, with a round knob at its middle.
		local
			l_cx, l_cy: REAL_64
		do
			a_context.set_line_width (2.0).set_color_hex_alpha (Handle_color).do_nothing
			if is_vertical then
				a_context.draw_line (a_x, a_at, a_x + a_w, a_at).do_nothing
				l_cx := a_x + a_w / 2.0
				l_cy := a_at
			else
				a_context.draw_line (a_at, a_y, a_at, a_y + a_h).do_nothing
				l_cx := a_at
				l_cy := a_y + a_h / 2.0
			end
			a_context.set_color_hex_alpha (Handle_shadow).fill_circle (l_cx, l_cy + 1.0, Knob_radius + 1.0).do_nothing
			a_context.set_color_hex_alpha (Handle_color).fill_circle (l_cx, l_cy, Knob_radius).do_nothing
			a_context.set_line_width (1.0).set_color_hex_alpha (Handle_shadow).stroke_circle (l_cx, l_cy, Knob_radius).do_nothing
		end

	Knob_radius: REAL_64 = 10.0
	Handle_color: NATURAL_32 = 0xFFFFFFFF
	Handle_shadow: NATURAL_32 = 0x66000000

	let_go_of_pictures
			-- Destroy the two surfaces.
		do
			before_surface.destroy
			after_surface.destroy
		end

feature {NONE} -- Input

	is_dragging: BOOLEAN
			-- Is the handle being dragged?

	Grab_reach: REAL_64 = 16.0
			-- How near the divider a press must be to take the handle, logical pixels.

	on_pointer (a_kind, a_x, a_y, a_button, a_modifiers: INTEGER)
			-- A press near the divider takes the handle; dragging moves it.
		local
			l_at: REAL_64
		do
			inspect a_kind
			when 1 then
				if is_vertical then
					l_at := a_y
				else
					l_at := a_x
				end
				is_dragging := (l_at - divider_position).abs <= Grab_reach
			when 3 then
				if is_dragging then
					follow (a_x, a_y)
				end
			when 2 then
				if is_dragging then
					follow (a_x, a_y)
					is_dragging := False
				end
			else
			end
		end

	follow (a_x, a_y: INTEGER)
			-- Put the divider under the pointer.
		do
			if is_vertical then
				if picture_height > 0.0 then
					set_divider ((a_y - picture_top) / picture_height)
				end
			elseif picture_width > 0.0 then
				set_divider ((a_x - picture_left) / picture_width)
			end
		end

	on_key (a_key: INTEGER; a_character: CHARACTER_32; a_modifiers: INTEGER)
			-- Left and up move the divider back, right and down forward: 1%, or 10% with Shift.
		local
			l_step: REAL_64
		do
			if (a_modifiers & 1) /= 0 then
				l_step := Shift_key_step
			else
				l_step := Key_step
			end
			inspect a_key
			when 0xFF51, 0xFF52 then
				set_divider (divider - l_step)
			when 0xFF53, 0xFF54 then
				set_divider (divider + l_step)
			else
			end
		end

invariant
	divider_in_range: 0.0 <= divider and divider <= 1.0

end
