note
	description: "[
		Shows a part of a larger widget, with scroll bars as needed (GtkScrolledWindow,
		NSScrollView, a scrolling panel on Windows). The content keeps its natural size, and
		fills the area when it is smaller.
	]"

class
	GUI_SCROLL_AREA

inherit
	GUI_SINGLE_CONTAINER

create
	make

feature {NONE} -- Initialization

	make
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create children.make (1)
			register (backend.scroll_area)
		ensure
			empty: content = Void
		end

feature -- Basic operations

	scroll_to (a_x, a_y: INTEGER)
			-- Bring the content's point (`a_x', `a_y') to the top left, as far as it goes.
		require
			gui_thread: is_gui_thread
			not_negative: a_x >= 0 and a_y >= 0
		do
			backend.scroll_area_scroll_to (id, a_x, a_y)
		end

	scroll_to_widget (a_widget: GUI_WIDGET)
			-- Scroll so `a_widget', which is inside the content, starts at the top left (as far
			-- as the scroll goes). Quiet.
		require
			gui_thread: is_gui_thread
		do
			if attached content as al_content then
				scroll_to ((a_widget.x - al_content.x).max (0), (a_widget.y - al_content.y).max (0))
			end
		end

feature {NONE} -- Implementation

	backend_set_content (a_child: INTEGER)
		do
			backend.scroll_area_set_content (id, a_child)
		end

end
