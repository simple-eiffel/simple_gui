note
	description: "A widget that lays out child widgets (never absolute frames)."

deferred class
	GUI_CONTAINER

inherit
	GUI_WIDGET
		redefine
			cascade_direction
		end

	GUI_BREAKING

feature -- Access

	children: ARRAYED_LIST [GUI_WIDGET]
			-- The widgets in this container, in order.

	count: INTEGER
		do
			Result := children.count
		end

	has (a_widget: GUI_WIDGET): BOOLEAN
		do
			Result := children.has (a_widget)
		end

	holds (a_widget: GUI_WIDGET): BOOLEAN
			-- Is `a_widget' inside this container, at any depth?
		local
			l_up: detachable GUI_WIDGET
		do
			from l_up := a_widget.parent until Result or l_up = Void loop
				Result := l_up = Current
				l_up := l_up.parent
			end
		end

feature -- Revealed on hover (1y-c)

	reveals_on_hover (a_part: GUI_WIDGET): BOOLEAN
			-- Does `a_part' show only while the pointer or the focus is inside this container?
		do
			Result := attached hover_parts as al_parts and then al_parts.has (a_part)
		end

	is_hover_shown: BOOLEAN
			-- Are the parts revealed on hover shown now: the pointer or the keyboard focus inside?
		do
			Result := is_pointer_inside or has_focus_within
		end

	set_reveals_on_hover (a_part: GUI_WIDGET; a_on: BOOLEAN)
			-- Show `a_part', a widget inside this container, only while the pointer or the keyboard
			-- focus is inside it (`a_on'), or always. It fades in and out (1x's `animate_opacity',
			-- at once under reduced motion) and keeps its layout space, so nothing moves. At
			-- opacity 0 it takes no pointer input, but it stays in the focus order and the
			-- accessibility tree: Tab reaches it, and so reveals it, and screen readers read it.
		require
			gui_thread: is_gui_thread
			inside: holds (a_part)
		local
			l_parts: ARRAYED_LIST [GUI_WIDGET]
		do
			if a_on then
				if not reveals_on_hover (a_part) then
					if attached hover_parts as al_parts then
						l_parts := al_parts
					else
						create l_parts.make (2)
						hover_parts := l_parts
						pointer_enter_actions.extend (agent show_hover_parts)
						pointer_leave_actions.extend (agent show_hover_parts)
						focus_enter_actions.extend (agent show_hover_parts)
						focus_leave_actions.extend (agent show_hover_parts)
					end
					l_parts.extend (a_part)
					if is_hover_shown then
						a_part.set_opacity (1.0)
					else
						a_part.set_opacity (0.0)
					end
				end
			elseif attached hover_parts as al_parts and then al_parts.has (a_part) then
				al_parts.prune_all (a_part)
				a_part.set_opacity (1.0)
			end
		ensure
			set: reveals_on_hover (a_part) = a_on
			shown_as_now: (a_on and not old reveals_on_hover (a_part)) implies (a_part.opacity = (if is_hover_shown then 1.0 else 0.0 end))
		end

feature {NONE} -- Revealed on hover

	hover_parts: detachable ARRAYED_LIST [GUI_WIDGET]
			-- The parts shown only while the pointer or the focus is inside (Void: none yet).

	show_hover_parts
			-- The pointer or the focus came or went: fade each part to suit.
		do
			if attached hover_parts as al_parts then
				across al_parts as ic loop
					if is_hover_shown then
						ic.animate_opacity (1.0)
					else
						ic.animate_opacity (0.0)
					end
				end
			end
		end

feature {NONE} -- Implementation

	adopt (a_widget: GUI_WIDGET)
			-- Record `a_widget' as a child.
		require
			not_parented: a_widget.parent = Void
			not_self: a_widget /= Current
		do
			children.extend (a_widget)
			a_widget.set_parent (Current)
			a_widget.inherit_direction (base_direction)
		ensure
			parent_set: a_widget.parent = Current
			added: count = old count + 1
		end

	cascade_direction
		do
			across children as ic loop
				ic.inherit_direction (base_direction)
			end
		end

invariant
	children_exist: children /= Void

end
