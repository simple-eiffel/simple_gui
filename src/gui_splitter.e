note
	description: "[
		Two panes with a divider the user can drag (NSSplitView, GtkPaned, SW's splitter).
		Horizontal puts the panes side by side (GTK's naming), vertical stacks them. When
		the splitter grows, the first pane keeps its size and the second takes the change.
		Until `set_position', the divider starts halfway.
		`position' is where the divider sits, in logical pixels from the leading edge (the
		right one, right to left) or the top; `set_position' fires nothing, and 0.2 has no
		event for the user's drag: read `position' when it is needed.
	]"

class
	GUI_SPLITTER

inherit
	GUI_CONTAINER
		redefine
			dispatch
		end

create
	make_horizontal, make_vertical

feature {NONE} -- Initialization

	make_horizontal
			-- Two panes side by side.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create children.make (2)
			register (backend.splitter (False))
		ensure
			side_by_side: not is_vertical
			empty: count = 0
		end

	make_vertical
			-- Two panes, one above the other.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create children.make (2)
			is_vertical := True
			register (backend.splitter (True))
		ensure
			stacked: is_vertical
			empty: count = 0
		end

feature -- Access

	is_vertical: BOOLEAN
			-- Are the panes stacked (else side by side)?

	first: detachable GUI_WIDGET
			-- The leading (or top) pane.

	second: detachable GUI_WIDGET
			-- The trailing (or bottom) pane.

	position: INTEGER
			-- The divider's distance from the leading edge (or the top), in logical pixels.
		do
			Result := backend.splitter_position (id)
		ensure
			non_negative: Result >= 0
		end

feature -- Element change

	set_first (a_widget: GUI_WIDGET)
			-- Put `a_widget' in the leading (or top) pane.
		require
			gui_thread: is_gui_thread
			empty: first = Void
			not_parented: a_widget.parent = Void
			not_self: a_widget /= Current
		do
			adopt (a_widget)
			first := a_widget
			backend.splitter_set_pane (id, 1, a_widget.id)
		ensure
			set: first = a_widget and a_widget.parent = Current
		end

	set_second (a_widget: GUI_WIDGET)
			-- Put `a_widget' in the trailing (or bottom) pane.
		require
			gui_thread: is_gui_thread
			empty: second = Void
			not_parented: a_widget.parent = Void
			not_self: a_widget /= Current
		do
			adopt (a_widget)
			second := a_widget
			backend.splitter_set_pane (id, 2, a_widget.id)
		ensure
			set: second = a_widget and a_widget.parent = Current
		end

	set_position (a_position: INTEGER)
			-- Move the divider to `a_position' logical pixels from the leading edge (or the
			-- top), as far as the panes allow; no event.
		require
			gui_thread: is_gui_thread
			non_negative: a_position >= 0
		do
			stop_position_animation
			backend.splitter_set_position (id, a_position)
		ensure
			not_moving: not is_moving_smoothly
		end

	animate_position (a_position: INTEGER)
			-- Move the divider to `a_position' (as `set_position') over the application's
			-- `animation_duration' (at once while motion is reduced). One still on its way is cut
			-- short; the user's own drag stops this one where it is (1x-e). No event;
			-- `position_finished_actions' when it arrives.
		require
			gui_thread: is_gui_thread
			non_negative: a_position >= 0
		local
			l_animation: GUI_ANIMATION
		do
			stop_position_animation
			position_target := a_position
			position_from := position
			position_left := position_from
			create l_animation.make (0.0, 1.0, application.animation_duration, {GUI_EASING}.Ease_in_out,
				agent show_position_frame)
			l_animation.finished_actions.extend (agent position_animation_ended (l_animation))
			position_animation := l_animation
			application.animation_clock.run (l_animation)
		ensure
			target_set: position_target = a_position
		end

	is_moving_smoothly: BOOLEAN
			-- Is a divider animation on its way?
		do
			Result := attached position_animation as al_a and then not al_a.is_finished
		end

	position_target: INTEGER
			-- Where the divider animation started last is going (the panes may stop it short).

	position_finished_actions: GUI_ACTIONS [TUPLE]
			-- Run when a divider animation arrives; never for one stopped.
		attribute
			create Result.make
		end

feature -- Collapsing panes (1r-c)

	is_collapsible (a_pane: INTEGER): BOOLEAN
			-- May pane `a_pane' (1 leading or top, 2 trailing or bottom) collapse?
		require
			pane: a_pane = 1 or a_pane = 2
		do
			Result := collapsible [a_pane]
		end

	set_collapsible (a_pane: INTEGER; a_on: BOOLEAN)
			-- Let pane `a_pane' collapse (a button on the divider, a double click on it), or not.
		require
			gui_thread: is_gui_thread
			pane: a_pane = 1 or a_pane = 2
		do
			collapsible [a_pane] := a_on
			backend.splitter_set_collapsible (id, a_pane, a_on)
		ensure
			set: is_collapsible (a_pane) = a_on
		end

	is_pane_collapsed (a_pane: INTEGER): BOOLEAN
		require
			pane: a_pane = 1 or a_pane = 2
		do
			Result := backend.splitter_is_collapsed (id, a_pane)
		end

	collapse_pane (a_pane: INTEGER)
			-- Give pane `a_pane''s room to the other, remembering `position'; no event.
		require
			gui_thread: is_gui_thread
			pane: a_pane = 1 or a_pane = 2
			collapsible: is_collapsible (a_pane)
			other_open: not is_pane_collapsed (3 - a_pane)
		do
			stop_position_animation
			backend.splitter_collapse (id, a_pane, True)
		ensure
			collapsed: is_pane_collapsed (a_pane)
		end

	expand_pane (a_pane: INTEGER)
			-- Open pane `a_pane' again, the divider back where it was; no event.
		require
			gui_thread: is_gui_thread
			pane: a_pane = 1 or a_pane = 2
		do
			stop_position_animation
			backend.splitter_collapse (id, a_pane, False)
		ensure
			opened: not is_pane_collapsed (a_pane)
		end

	collapse_actions: GUI_ACTIONS [TUPLE [pane: INTEGER; is_collapsed: BOOLEAN]]
			-- Run when the user collapses or expands a pane.
		do
			if attached collapse_actions_made as al_a then
				Result := al_a
			else
				create Result.make
				collapse_actions_made := Result
			end
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
			-- 42: a pane collapsed or expanded by the user (pane, 1 or 0).
		do
			if a_type = 42 and then (a_a = 1 or a_a = 2) and then attached collapse_actions_made as al_a then
				al_a.call ([a_a, a_b = 1])
			end
		end

feature {NONE} -- Collapsing

	collapsible: ARRAY [BOOLEAN]
		attribute
			create Result.make_filled (False, 1, 2)
		end

	collapse_actions_made: detachable like collapse_actions

feature {NONE} -- Divider animation (1x-e)

	position_animation: detachable GUI_ANIMATION
			-- The divider animation started last.

	position_from: INTEGER
			-- Where it started.

	position_left: INTEGER
			-- Where its last frame left the divider, as the toolkit then answered.

	show_position_frame (a_fraction: REAL_64)
			-- One frame: `a_fraction' of the way, unless the user has moved the divider since
			-- the last frame, which stops it there (as 1x-d's smooth scroll).
		do
			if position /= position_left then
				stop_position_animation
			else
				backend.splitter_set_position (id,
					(position_from + (position_target - position_from) * a_fraction.max (0.0).min (1.0)).rounded.max (0))
				position_left := position
			end
		end

	position_animation_ended (a_animation: GUI_ANIMATION)
			-- `a_animation' has arrived.
		do
			if position_animation = a_animation then
				position_finished_actions.call (Void)
			end
		end

	stop_position_animation
			-- Stop a divider animation on its way where it is, without its finished actions.
		do
			if attached position_animation as al_a and then not al_a.is_finished then
				application.animation_clock.cancel (al_a)
			end
		ensure
			stopped: not is_moving_smoothly
		end

invariant
	at_most_two: count <= 2

end
