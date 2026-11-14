note
	description: "[
		1y-b: a frame that keeps its content at a ratio of width to height (a video or picture
		box, W3Schools' aspect-ratio box). Its height follows its width, at the ratio; the
		content gets the largest size of that ratio that fits the space given, centered.
		GtkAspectFrame's job, done by a container of our own on GTK so the height follows the
		width; an aspect constraint on macOS; a small frame on Windows.
	]"

class
	GUI_ASPECT_FRAME

inherit
	GUI_SINGLE_CONTAINER

create
	make

feature {NONE} -- Initialization

	make (a_ratio: REAL_64)
			-- An empty frame keeping `a_ratio' (width over height).
		require
			gui_thread: is_gui_thread
			has_application: has_application
			positive: a_ratio > 0.0
		do
			create children.make (1)
			ratio := a_ratio
			register (backend.aspect_frame (a_ratio))
		ensure
			set: ratio = a_ratio
			empty: content = Void
		end

feature -- Access

	ratio: REAL_64
			-- Width over height.

feature -- Element change

	set_ratio (a_ratio: REAL_64)
			-- Keep `a_ratio' from now on.
		require
			gui_thread: is_gui_thread
			positive: a_ratio > 0.0
		do
			ratio := a_ratio
			backend.aspect_set_ratio (id, a_ratio)
		ensure
			set: ratio = a_ratio
		end

feature {NONE} -- Implementation

	backend_set_content (a_child: INTEGER)
		do
			backend.aspect_set_content (id, a_child)
		end

invariant
	positive: ratio > 0.0

end
