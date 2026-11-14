note
	description: "[
		1y-d: a thin progress bar following how far a scrolling widget is scrolled down (W3Schools'
		scroll indicator): 0 at the top, 100 at the end, 0 while nothing scrolls. Shared code
		only, over GUI_PROGRESS_BAR; it reads to screen readers as a progress bar named
		"Scroll position".
	]"

class
	GUI_SCROLL_PROGRESS

inherit
	GUI_PROGRESS_BAR
		rename
			make as make_bar
		end

create
	make

feature {NONE} -- Initialization

	make (a_scrolling: GUI_SCROLLING)
			-- A bar following `a_scrolling'.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			scrolling := a_scrolling
			make_bar
			set_accessible_label ("Scroll position")
			a_scrolling.reported_actions.extend (agent follow)
			a_scrolling.scroll_actions.extend (agent (a_y: INTEGER) do follow end)
		ensure
			following: scrolling = a_scrolling
		end

feature -- Access

	scrolling: GUI_SCROLLING
			-- The widget followed.

feature {NONE} -- Implementation

	follow
			-- Show how far `scrolling' is now.
		do
			set_value ((scrolling.scroll_fraction * 100.0).rounded.max (0).min (100))
		end

end
