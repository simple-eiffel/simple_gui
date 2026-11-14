note
	description: "[
		1y-d: a widget that scrolls itself (GUI_SCROLL_AREA, GUI_LIST, GUI_TABLE, GUI_TREE,
		GUI_TREE_TABLE, GUI_GRID_VIEW): its vertical offset, the furthest it goes, the fraction
		scrolled, agents told after the offset changes for any reason, and infinite scroll.
		Backends report a scroller when its offset, its furthest offset or its content's
		extent changed (event 65, at most once a turn of the queue, only while watched); shared
		code reads the numbers and decides. Near the end: `near_end_actions' run once when the
		distance left falls to `near_end_distance' or less, and are armed again when the content
		grows (even while it still fits, so a short list keeps loading until it fills) or when
		the user scrolls back above the distance.
	]"

deferred class
	GUI_SCROLLING

inherit
	GUI_SHARED

feature -- Access

	id: INTEGER
			-- The backend's name for this widget.
		deferred
		end

	scroll_y: INTEGER
			-- How far the content is scrolled from its top, in logical pixels.
		do
			Result := backend.scroller_y (id)
		ensure
			not_negative: Result >= 0
		end

	max_scroll_y: INTEGER
			-- The furthest `scroll_y' goes: the content's height less the visible height (0 when
			-- it fits).
		do
			Result := backend.scroller_max_y (id)
		ensure
			not_negative: Result >= 0
		end

	scroll_fraction: REAL_64
			-- How far down, from 0.0 at the top to 1.0 at the end (0.0 when nothing scrolls).
		do
			if max_scroll_y > 0 then
				Result := (scroll_y / max_scroll_y).max (0.0).min (1.0)
			end
		ensure
			in_range: Result >= 0.0 and Result <= 1.0
		end

	scroll_actions: GUI_TARGET_ACTIONS [TUPLE [y: INTEGER]]
			-- Run with the new `scroll_y' after it changed for any reason: the user, the program, a
			-- smooth scroll, or content that shrank. The first agent asks the backend to watch.
		do
			if attached scroll_actions_made as al_a then
				Result := al_a
			else
				create Result.make (agent watch_scroller)
				scroll_actions_made := Result
			end
		end

	near_end_actions: GUI_TARGET_ACTIONS [TUPLE]
			-- Run once when the distance left to the end falls to `near_end_distance' or less; armed
			-- again when the content grows or the user scrolls back above the distance. The first
			-- agent asks the backend to watch.
		do
			if attached near_end_actions_made as al_a then
				Result := al_a
			else
				create Result.make (agent watch_scroller)
				near_end_actions_made := Result
			end
		end

	near_end_distance: INTEGER
			-- How close to the end counts as near it, in logical pixels.
		do
			if near_end_distance_set > 0 then
				Result := near_end_distance_set
			else
				Result := Default_near_end_distance
			end
		ensure
			positive: Result > 0
		end

	Default_near_end_distance: INTEGER = 300

	is_near_end_armed: BOOLEAN
			-- Will `near_end_actions' run when the end comes near?
		do
			Result := not near_end_spent
		end

feature -- Element change

	set_near_end_distance (a_distance: INTEGER)
			-- Count `a_distance' logical pixels from the end as near it.
		require
			gui_thread: is_gui_thread
			positive: a_distance > 0
		do
			near_end_distance_set := a_distance
		ensure
			set: near_end_distance = a_distance
		end

feature {GUI_SCROLL_PROGRESS} -- Reports

	reported_actions: GUI_ACTIONS [TUPLE]
			-- Run after every report, after `scroll_actions': the fraction may change with the
			-- content alone (GUI_SCROLL_PROGRESS follows it).
		attribute
			create Result.make
		end

feature {GUI_APPLICATION, GUI_SCROLLING} -- Reports

	take_scroll_report
			-- 1y-d: the backend says the offset, the furthest offset or the content's extent may
			-- have changed: tell `scroll_actions' of a new offset, and look at the end.
		local
			l_y, l_extent: INTEGER
		do
			l_y := scroll_y
			if l_y /= last_scroll_y then
				last_scroll_y := l_y
				if attached scroll_actions_made as al_a then
					al_a.call ([l_y])
				end
			end
			l_extent := backend.scroller_extent (id)
			if l_extent > last_extent then
				near_end_spent := False
			end
			last_extent := l_extent
			look_at_the_end
			reported_actions.call (Void)
		end

	look_at_the_end
			-- Run `near_end_actions' if armed and near the end; arm them again above the distance.
		local
			l_left: INTEGER
		do
			l_left := max_scroll_y - scroll_y
			if l_left > near_end_distance then
				near_end_spent := False
			elseif not near_end_spent and then attached near_end_actions_made as al_a and then al_a.count > 0 then
				near_end_spent := True
				al_a.call (Void)
			end
		end

feature {NONE} -- Implementation

	scroll_actions_made: detachable like scroll_actions

	near_end_actions_made: detachable like near_end_actions

	near_end_distance_set: INTEGER

	near_end_spent: BOOLEAN
			-- Have `near_end_actions' run since the content last grew or the user went back up?

	last_scroll_y: INTEGER
			-- The offset `scroll_actions' were last told of.

	last_extent: INTEGER
			-- The content's extent as last reported.

	is_scroller_watched: BOOLEAN

	watch_scroller
			-- Ask the backend for this widget's scroll reports, once.
		do
			if not is_scroller_watched then
				is_scroller_watched := True
				backend.scroller_watch (id, True)
			end
		end

end
