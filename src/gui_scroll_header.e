note
	description: "[
		1y-d: a header tied to a scrolling widget. Hiding: scrolling down by more than
		`threshold' since the last change of direction hides the header with 1x's slide from the
		top, scrolling up shows it again, and at the top it is always shown (the header should sit
		in a GUI_STACK or be a window's content, where slides take their share of space).
		Compacting: `compact_actions' run when the scroll passes `compact_distance' and
		`full_actions' when it is back above, and the program shrinks the header itself. Under
		reduced motion the hide and show are at once. A hidden header takes no focus; it comes
		back when the user scrolls up or reaches the top, and when the program focuses it.
	]"

class
	GUI_SCROLL_HEADER

inherit
	GUI_SHARED

create
	make_hiding, make_compacting

feature {NONE} -- Initialization

	make_hiding (a_header: GUI_WIDGET; a_scrolling: GUI_SCROLLING)
			-- Hide `a_header' as `a_scrolling' scrolls down and show it as it scrolls up.
		require
			gui_thread: is_gui_thread
			distinct: a_header /= a_scrolling
		do
			header := a_header
			scrolling := a_scrolling
			is_hiding := True
			create compact_actions.make
			create full_actions.make
			a_scrolling.scroll_actions.extend (agent follow)
			a_header.focus_enter_actions.extend (agent come_back)
		ensure
			hiding: is_hiding
			shown: not is_hidden
		end

	make_compacting (a_header: GUI_WIDGET; a_scrolling: GUI_SCROLLING; a_distance: INTEGER)
			-- Run `compact_actions' when `a_scrolling' passes `a_distance', `full_actions' back above.
		require
			gui_thread: is_gui_thread
			distinct: a_header /= a_scrolling
			positive: a_distance > 0
		do
			header := a_header
			scrolling := a_scrolling
			compact_distance := a_distance
			create compact_actions.make
			create full_actions.make
			a_scrolling.scroll_actions.extend (agent follow)
		ensure
			compacting: not is_hiding
			full: not is_compact
		end

feature -- Access

	header: GUI_WIDGET
			-- The header.

	scrolling: GUI_SCROLLING
			-- The widget it follows.

	is_hiding: BOOLEAN
			-- Does it hide the header (else it runs compact and full actions)?

	threshold: INTEGER
			-- How far down, since the last change of direction, hides the header (logical pixels).
		do
			if threshold_set > 0 then
				Result := threshold_set
			else
				Result := Default_threshold
			end
		ensure
			positive: Result > 0
		end

	Default_threshold: INTEGER = 24

	compact_distance: INTEGER
			-- Past this offset the header is compact (compacting only).

	is_hidden: BOOLEAN
			-- Has it hidden the header?

	is_compact: BOOLEAN
			-- Is the header compact now?

	compact_actions, full_actions: GUI_ACTIONS [TUPLE]
			-- Run when the header should become compact, or full again.

feature -- Element change

	set_threshold (a_pixels: INTEGER)
		require
			positive: a_pixels > 0
		do
			threshold_set := a_pixels
		ensure
			set: threshold = a_pixels
		end

feature {NONE} -- Implementation

	threshold_set: INTEGER

	last_y: INTEGER
			-- The offset at the last report.

	turn_y: INTEGER
			-- Where the scroll last turned downward.

	is_going_down: BOOLEAN

	follow (a_y: INTEGER)
			-- `scrolling' is now at `a_y'.
		do
			if is_hiding then
				if a_y <= 0 then
					reveal
				elseif a_y > last_y then
					if not is_going_down then
						is_going_down := True
						turn_y := last_y
					end
					if a_y - turn_y > threshold then
						conceal
					end
				elseif a_y < last_y then
					is_going_down := False
					reveal
				end
			elseif a_y > compact_distance and not is_compact then
				is_compact := True
				compact_actions.call (Void)
			elseif a_y <= compact_distance and is_compact then
				is_compact := False
				full_actions.call (Void)
			end
			last_y := a_y
		end

	come_back
			-- The focus came into the header.
		do
			reveal
		end

	conceal
			-- Slide the header away, once.
		do
			if not is_hidden then
				is_hidden := True
				header.hide_animated ({GUI_WIDGET}.Effect_slide_from_top)
			end
		ensure
			hidden: is_hidden
		end

	reveal
			-- Slide the header back, once.
		do
			if is_hidden then
				is_hidden := False
				header.show_animated ({GUI_WIDGET}.Effect_slide_from_top)
			end
		ensure
			shown: not is_hidden
		end

invariant
	compact_only_when_compacting: is_compact implies not is_hiding
	hidden_only_when_hiding: is_hidden implies is_hiding

end
