note
	description: "[
		The drawn view on Windows (1i): an SW_CANVAS that a GUI_DRAWN presents its hosted
		simple_widgets window in, with the input that window needs beyond a canvas's: the
		wheel (`on_wheel'), double and triple presses (`on_multi_press'), the pointer leaving
		(`on_leave'), Tab kept for the hosted widgets (`wants_tab'), and the pointer shape the
		hosted window asks for (`hosted_cursor'). It reads as a group. Presses, releases,
		drags, keys and characters come through the canvas's own agents. Only the primary
		button is heard, as on any SW_CANVAS: a secondary click is SW's context-menu route.
	]"

class
	GUI_SW_DRAWN_VIEW

inherit
	SW_CANVAS
		redefine
			handle_wheel, handle_double_click, handle_triple_click, wants_tab, cursor_kind,
			accessible_role, set_hover_point
		end

create
	make_view

feature {NONE} -- Initialization

	make_view (a_width, a_height: REAL_64)
			-- A view preferring `a_width' by `a_height'.
		require
			sized: a_width >= 1.0 and a_height >= 1.0
		do
			make (a_height)
			min_width := a_width
			min_height := a_height
		end

feature -- Access

	on_wheel: detachable PROCEDURE [INTEGER]
			-- The wheel's delta (120 a notch, positive away from the user).

	on_multi_press: detachable PROCEDURE [INTEGER, REAL_64, REAL_64]
			-- (2 or 3 presses, x, y), canvas-relative.

	on_leave: detachable PROCEDURE
			-- The pointer left the view.

	hosted_cursor: INTEGER
			-- The pointer shape the hosted window asks for.

	last_x, last_y: REAL_64
			-- Where the pointer was last seen, canvas-relative.

feature -- Element change

	set_on_wheel (a_action: PROCEDURE [INTEGER])
		do
			on_wheel := a_action
		ensure
			set: on_wheel = a_action
		end

	set_on_multi_press (a_action: PROCEDURE [INTEGER, REAL_64, REAL_64])
		do
			on_multi_press := a_action
		ensure
			set: on_multi_press = a_action
		end

	set_on_leave (a_action: PROCEDURE)
		do
			on_leave := a_action
		ensure
			set: on_leave = a_action
		end

	set_hosted_cursor (a_kind: INTEGER)
		require
			known: a_kind >= 0 and a_kind <= 6
		do
			hosted_cursor := a_kind
		ensure
			set: hosted_cursor = a_kind
		end

	set_hover_point (a_px, a_py: REAL_64)
			-- Remember where the pointer is (for the wheel), then as a canvas: a move.
		do
			last_x := a_px - x
			last_y := a_py - y
			Precursor (a_px, a_py)
		end

feature -- Input

	handle_wheel (a_delta: INTEGER): BOOLEAN
		do
			if attached on_wheel as al_wheel then
				al_wheel.call (a_delta)
				Result := True
			end
		end

	handle_double_click (a_px, a_py: REAL_64): BOOLEAN
		do
			if attached on_multi_press as al_press then
				al_press.call (2, a_px - x, a_py - y)
				Result := True
			end
		end

	handle_triple_click (a_px, a_py: REAL_64): BOOLEAN
		do
			if attached on_multi_press as al_press then
				al_press.call (3, a_px - x, a_py - y)
				Result := True
			end
		end

	wants_tab: BOOLEAN
			-- Tab moves between the hosted widgets, not out of the view.
		do
			Result := True
		end

	cursor_kind: INTEGER
		do
			Result := hosted_cursor
		end

feature -- Accessibility

	accessible_role: INTEGER
		do
			Result := {SW_ACCESSIBILITY}.Role_group
		end

end
