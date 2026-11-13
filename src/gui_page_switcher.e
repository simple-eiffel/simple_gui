note
	description: "[
		A container that shows its pages one at a time and can switch between them with a
		transition (1x-c): GUI_TABS and GUI_PAGES. The shared clock decides every frame of
		a switch and the backend only shows it (`pages_set_transition_frame'), so the curve
		is the same on all three platforms. A crossfade blends the two pages; a slide moves
		toward the new page's side (forward is trailing, back is leading, mirrored under
		right-to-left: the backend reads the direction from the two page numbers). While
		the system asks for reduced motion, or with `Transition_none', a switch ends at
		once and its end comes on the queue's next turn.
	]"

deferred class
	GUI_PAGE_SWITCHER

inherit
	GUI_CONTAINER

feature -- Access

	selected_index: INTEGER
			-- The page selected (shown, or being switched to), or 0 when there are no pages.
		deferred
		ensure
			in_range: 0 <= Result and Result <= count
		end

	page_transition: INTEGER
			-- How a switch between pages is shown; `Transition_none' until set.

	switch_from, switch_to: INTEGER
			-- The pages of the switch started last (0 before any).

	switch_fraction: REAL_64
			-- How far the running switch has got (0 to 1); 1 when none runs.
		do
			if attached switch_animation as al_animation and then not al_animation.is_finished then
				Result := al_animation.current_value
			else
				Result := 1.0
			end
		ensure
			in_range: 0.0 <= Result and Result <= 1.0
		end

feature -- Status

	is_switching: BOOLEAN
			-- Is a transition between two pages running?
		do
			Result := attached switch_animation as al_animation and then not al_animation.is_finished
		end

feature -- Transitions (1x-c)

	Transition_none: INTEGER = 0
			-- The new page at once.

	Transition_crossfade: INTEGER = 1
			-- The old page fades out as the new one fades in.

	Transition_slide: INTEGER = 2
			-- The new page slides in from its side as the old one slides out.

	is_transition (a_kind: INTEGER): BOOLEAN
			-- Is `a_kind' one of the transitions?
		do
			Result := a_kind >= Transition_none and a_kind <= Transition_slide
		end

	set_page_transition (a_kind: INTEGER)
			-- Show later switches between pages with `a_kind'.
		require
			gui_thread: is_gui_thread
			known: is_transition (a_kind)
		do
			page_transition := a_kind
		ensure
			set: page_transition = a_kind
		end

feature {NONE} -- Switching

	shown_page: INTEGER
			-- The page the user sees once any running switch ends (0 before any page).

	switch_kind: INTEGER
			-- The transition of the switch started last.

	switch_animation: detachable GUI_ANIMATION
			-- The switch started last.

	show_page_at_once (i: INTEGER)
			-- Show page `i' alone, with no event.
		require
			valid: 1 <= i and i <= count
		deferred
		end

	switch_ended (a_page: INTEGER)
			-- A switch to `a_page' has ended. Nothing here.
		do
		end

	start_switch (a_from, a_to: INTEGER)
			-- Show page `a_to' in place of page `a_from' through `page_transition' over the
			-- application's `animation_duration'; at once with `Transition_none', from no page,
			-- or while motion is reduced. A switch still running is cut short (its end never
			-- comes). `switch_ended' when this one ends.
		require
			valid_to: 1 <= a_to and a_to <= count
		local
			l_animation: GUI_ANIMATION
		do
			if attached switch_animation as al_earlier then
				application.animation_clock.cancel (al_earlier)
			end
			switch_from := a_from
			switch_to := a_to
			switch_kind := page_transition
			shown_page := a_to
			if switch_kind = Transition_none or a_from = a_to or a_from < 1 or a_from > count then
				show_page_at_once (a_to)
					-- a zero-length switch: its end comes on the next turn, as a reduced one's does
				create l_animation.make (1.0, 1.0, 0, {GUI_EASING}.Ease_in_out, agent (a_fraction: REAL_64) do end)
			else
				create l_animation.make (0.0, 1.0, application.animation_duration, {GUI_EASING}.Ease_in_out,
					agent show_switch_frame (a_from, a_to, ?))
			end
			l_animation.finished_actions.extend (agent switch_animation_ended (l_animation, a_to))
			switch_animation := l_animation
			application.animation_clock.run (l_animation)
		ensure
			to_set: shown_page = a_to and switch_to = a_to
			from_set: switch_from = a_from
		end

	show_switch_frame (a_from, a_to: INTEGER; a_fraction: REAL_64)
			-- One frame of the switch from `a_from' to `a_to'.
		do
			backend.pages_set_transition_frame (id, a_from, a_to, switch_kind, a_fraction.max (0.0).min (1.0))
		end

	switch_animation_ended (a_animation: GUI_ANIMATION; a_to: INTEGER)
			-- `a_animation', the switch to `a_to', has ended.
		do
			if switch_animation = a_animation then
				switch_ended (a_to)
			end
		end

invariant
	known_transition: is_transition (page_transition)
	shown_page_in_range: 0 <= shown_page and shown_page <= count

end
