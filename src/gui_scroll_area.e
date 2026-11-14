note
	description: "[
		Shows a part of a larger widget, with scroll bars as needed (GtkScrolledWindow,
		NSScrollView, a scrolling panel on Windows). The content keeps its natural size, and
		fills the area when it is smaller.
		It scrolls at once (`scroll_to') or smoothly (`scroll_to_animated', 1x-d) on the
		application's animation clock. A smooth scroll moves only where the program asked: the
		moment the user scrolls (wheel, drag, scroll bar, keys, a trackpad's momentum) it stops
		where it is, and the user's scroll stands.
	]"

class
	GUI_SCROLL_AREA

inherit
	GUI_SINGLE_CONTAINER

	GUI_SCROLLING
		redefine
			scroll_y, max_scroll_y
		end

create
	make

feature {NONE} -- Initialization

	make
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create children.make (1)
			create smooth_scroll_finished_actions.make
			register (backend.scroll_area)
		ensure
			empty: content = Void
			not_scrolling: not is_scrolling_smoothly
		end

feature -- Access

	scroll_x: INTEGER
			-- How far the content is scrolled from its left edge, in logical pixels.
		do
			Result := backend.scroll_area_x (id)
		ensure
			not_negative: Result >= 0
		end

	scroll_y: INTEGER
			-- How far the content is scrolled from its top edge, in logical pixels.
		do
			Result := backend.scroll_area_y (id)
		ensure then
			not_negative: Result >= 0
		end

	max_scroll_x: INTEGER
			-- The furthest `scroll_x' goes: the content's width less the visible width (0 when
			-- the content fits).
		do
			Result := backend.scroll_area_max_x (id)
		ensure
			not_negative: Result >= 0
		end

	max_scroll_y: INTEGER
			-- The furthest `scroll_y' goes: the content's height less the visible height (0 when
			-- the content fits).
		do
			Result := backend.scroll_area_max_y (id)
		ensure then
			not_negative: Result >= 0
		end

	smooth_target_x, smooth_target_y: INTEGER
			-- Where the smooth scroll started last is going (its asked point, clamped to the
			-- furthest the content then went).

	smooth_scroll_finished_actions: GUI_ACTIONS [TUPLE]
			-- Run when a smooth scroll reaches its target; never for one stopped by the user, by
			-- `scroll_to' or by a later smooth scroll.

feature -- Status

	is_scrolling_smoothly: BOOLEAN
			-- Is a smooth scroll on its way?
		do
			Result := attached smooth_scroll as al_s and then not al_s.is_finished
		end

feature -- Basic operations

	scroll_to (a_x, a_y: INTEGER)
			-- Bring the content's point (`a_x', `a_y') to the top left, as far as it goes, at
			-- once. A smooth scroll on its way stops.
		require
			gui_thread: is_gui_thread
			not_negative: a_x >= 0 and a_y >= 0
		do
			stop_smooth_scroll
			backend.scroll_area_scroll_to (id, a_x, a_y)
		ensure
			not_smooth: not is_scrolling_smoothly
		end

	scroll_to_widget (a_widget: GUI_WIDGET)
			-- Scroll so `a_widget', which is inside the content, starts at the top left (as far
			-- as the scroll goes), at once. Quiet.
		require
			gui_thread: is_gui_thread
		do
			if attached content as al_content then
				scroll_to ((a_widget.x - al_content.x).max (0), (a_widget.y - al_content.y).max (0))
			end
		end

	scroll_to_animated (a_x, a_y: INTEGER)
			-- Move the content's point (`a_x', `a_y') to the top left, as far as it goes, over
			-- the application's `animation_duration' (at once while motion is reduced). A smooth
			-- scroll still on its way is cut short; the user's own scroll stops this one where it
			-- is. `smooth_scroll_finished_actions' when it arrives.
		require
			gui_thread: is_gui_thread
			not_negative: a_x >= 0 and a_y >= 0
		local
			l_animation: GUI_ANIMATION
		do
			stop_smooth_scroll
			smooth_target_x := a_x.min (max_scroll_x)
			smooth_target_y := a_y.min (max_scroll_y)
			smooth_from_x := scroll_x
			smooth_from_y := scroll_y
			left_x := smooth_from_x
			left_y := smooth_from_y
			create l_animation.make (0.0, 1.0, application.animation_duration, {GUI_EASING}.Ease_in_out,
				agent show_smooth_frame)
			l_animation.finished_actions.extend (agent smooth_scroll_ended (l_animation))
			smooth_scroll := l_animation
			application.animation_clock.run (l_animation)
		ensure
			target_clamped: smooth_target_x <= a_x and smooth_target_y <= a_y
		end

	scroll_to_widget_animated (a_widget: GUI_WIDGET)
			-- Smoothly scroll so `a_widget', which is inside the content, starts at the top left
			-- (as far as the scroll goes); see `scroll_to_animated'.
		require
			gui_thread: is_gui_thread
		do
			if attached content as al_content then
				scroll_to_animated ((a_widget.x - al_content.x).max (0), (a_widget.y - al_content.y).max (0))
			end
		end

feature {NONE} -- Smooth scrolling

	smooth_scroll: detachable GUI_ANIMATION
			-- The smooth scroll started last.

	smooth_from_x, smooth_from_y: INTEGER
			-- Where it started.

	left_x, left_y: INTEGER
			-- Where its last frame left the content, as the toolkit then answered.

	show_smooth_frame (a_fraction: REAL_64)
			-- One frame of the smooth scroll: `a_fraction' of the way, unless the user has moved
			-- the content since the last frame, which stops it there.
		local
			f: REAL_64
		do
			if scroll_x /= left_x or scroll_y /= left_y then
					-- the user scrolled: theirs stands
				stop_smooth_scroll
			else
				f := a_fraction.max (0.0).min (1.0)
				backend.scroll_area_scroll_to (id,
					(smooth_from_x + (smooth_target_x - smooth_from_x) * f).rounded.max (0),
					(smooth_from_y + (smooth_target_y - smooth_from_y) * f).rounded.max (0))
				left_x := scroll_x
				left_y := scroll_y
			end
		end

	smooth_scroll_ended (a_animation: GUI_ANIMATION)
			-- `a_animation' has reached its target.
		do
			if smooth_scroll = a_animation then
				smooth_scroll_finished_actions.call (Void)
			end
		end

	stop_smooth_scroll
			-- Stop a smooth scroll on its way where it is, without its finished actions.
		do
			if attached smooth_scroll as al_s and then not al_s.is_finished then
				application.animation_clock.cancel (al_s)
			end
		ensure
			stopped: not is_scrolling_smoothly
		end

feature {NONE} -- Implementation

	backend_set_content (a_child: INTEGER)
		do
			backend.scroll_area_set_content (id, a_child)
		end

end
