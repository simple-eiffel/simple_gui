note
	description: "[
		1y: a widget that changes its layout at breakpoints: GUI_WINDOW, on its own size, and
		GUI_CONTAINER, on the size its parent gives it (as CSS container queries do). Of its
		breakpoints the last added that matches its size is applied (AdwBreakpoint's rule and
		CSS's "later wins"); with none matching, the program's own layout stands. Sizes come
		from the widget's size reports, so the choice is made after layout, the same on every
		platform. A container whose own content decides its size can switch back and forth
		between two layouts; break on a size the parent gives (a stretched child).
	]"

deferred class
	GUI_BREAKING

inherit
	GUI_SHARED

feature -- Access

	width: INTEGER
			-- Current width in logical pixels.
		deferred
		end

	height: INTEGER
			-- Current height in logical pixels.
		deferred
		end

	size_changed_actions: GUI_TARGET_ACTIONS [TUPLE [width, height: INTEGER]]
			-- Run after layout when the size changed.
		deferred
		end

	active_breakpoint: detachable GUI_BREAKPOINT
			-- The breakpoint applied now (Void: none matches, or no size yet).

	breakpoint_count: INTEGER
			-- How many breakpoints this widget has.
		do
			if attached breakpoint_list as al_list then
				Result := al_list.count
			end
		ensure
			non_negative: Result >= 0
		end

	breakpoint (i: INTEGER): GUI_BREAKPOINT
			-- The `i'-th breakpoint, in the order added.
		require
			valid_index: i >= 1 and i <= breakpoint_count
		do
			check attached breakpoint_list as al_list then
				Result := al_list.i_th (i)
			end
		end

	has_breakpoint (a_breakpoint: GUI_BREAKPOINT): BOOLEAN
			-- Is `a_breakpoint' one of this widget's?
		do
			Result := attached breakpoint_list as al_list and then al_list.has (a_breakpoint)
		end

	last_match (a_width, a_height: INTEGER): detachable GUI_BREAKPOINT
			-- The last added breakpoint that matches `a_width' by `a_height' (Void: none).
		do
			if attached breakpoint_list as al_list then
				across al_list as ic loop
					if ic.matches (a_width, a_height) then
						Result := ic
					end
				end
			end
		ensure
			matching: attached Result as al_r implies al_r.matches (a_width, a_height)
			own: attached Result as al_r implies has_breakpoint (al_r)
		end

feature -- Element change

	add_breakpoint (a_breakpoint: GUI_BREAKPOINT)
			-- Add `a_breakpoint' after the others, and choose again at the present size if
			-- there is one.
		require
			gui_thread: is_gui_thread
			not_added: not a_breakpoint.is_added
		local
			l_list: ARRAYED_LIST [GUI_BREAKPOINT]
		do
			if attached breakpoint_list as al_list then
				l_list := al_list
			else
				create l_list.make (2)
				breakpoint_list := l_list
				size_changed_actions.extend (agent choose_breakpoint)
			end
			l_list.extend (a_breakpoint)
			a_breakpoint.mark_added
			if width > 0 and height > 0 then
				choose_breakpoint (width, height)
			end
		ensure
			added: has_breakpoint (a_breakpoint) and a_breakpoint.is_added
			last: breakpoint (breakpoint_count) = a_breakpoint
			one_more: breakpoint_count = old breakpoint_count + 1
		end

feature {NONE} -- Breakpoints

	breakpoint_list: detachable ARRAYED_LIST [GUI_BREAKPOINT]
			-- The breakpoints, in the order added (Void until the first).

	choose_breakpoint (a_width, a_height: INTEGER)
			-- Apply the last breakpoint matching `a_width' by `a_height': the one applied
			-- before, if it changes, is unapplied first.
		local
			l_new: detachable GUI_BREAKPOINT
		do
			l_new := last_match (a_width, a_height)
			if l_new /= active_breakpoint then
				if attached active_breakpoint as al_old then
					active_breakpoint := l_new
					al_old.unapply
				else
					active_breakpoint := l_new
				end
				if attached l_new as al_new then
					al_new.apply
				end
			end
		ensure
			chosen: active_breakpoint = old last_match (a_width, a_height)
		end

invariant
	active_is_own: attached active_breakpoint as al_a implies has_breakpoint (al_a)

end
