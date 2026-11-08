note
	description: "A widget that lays out child widgets (never absolute frames)."

deferred class
	GUI_CONTAINER

inherit
	GUI_WIDGET
		redefine
			cascade_direction
		end

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
