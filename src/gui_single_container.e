note
	description: "A container that holds one widget: GUI_SCROLL_AREA, GUI_GROUP_BOX, GUI_EXPANDER."

deferred class
	GUI_SINGLE_CONTAINER

inherit
	GUI_CONTAINER

feature -- Access

	content: detachable GUI_WIDGET
			-- The widget inside, once set.

feature -- Element change

	set_content (a_widget: GUI_WIDGET)
			-- Put `a_widget' inside.
		require
			gui_thread: is_gui_thread
			empty: content = Void
			not_parented: a_widget.parent = Void
			not_self: a_widget /= Current
		do
			adopt (a_widget)
			content := a_widget
			backend_set_content (a_widget.id)
		ensure
			set: content = a_widget and a_widget.parent = Current
		end

feature {NONE} -- Implementation

	backend_set_content (a_child: INTEGER)
			-- Put `a_child' inside, in the toolkit.
		deferred
		end

invariant
	one_at_most: count <= 1

end
