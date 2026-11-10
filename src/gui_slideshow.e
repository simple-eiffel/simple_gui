note
	description: "[
		A slideshow, or carousel (1v-a): one item at a time, with previous and next buttons and
		a row of dots for the position; Left and Right move too. It can wrap around and play
		by itself, pausing while the pointer is over it. A shared composite of a tabless
		GUI_TABS and GUI_BUTTONs, so each part is native. `show_item' fires nothing; the
		user's moves and autoplay fire `item_changed_actions'.
	]"

class
	GUI_SLIDESHOW

inherit
	GUI_STACK
		rename
			make_vertical as make_stack
		export
			{NONE} make_stack, make_horizontal, extend, extend_stretching, extend_aligned
		end

create
	make

feature {NONE} -- Initialization

	make
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
				-- every part first: the stack registers Current, which must then be whole
			create pages.make
			create previous_button.make ({STRING_32} "%/8249/")
			create next_button.make ({STRING_32} "%/8250/")
			create dots.make_horizontal
			create dot_buttons.make (4)
			create item_changed_actions.make
			make_stack
			set_spacing (6)
			pages.set_tab_position (pages.Tabs_none)
			previous_button.set_accessible_label ("Previous")
			next_button.set_accessible_label ("Next")
			dots.set_spacing (2)
			extend_stretching (pages)
			build_controls
			refresh
		ensure
			empty: count_items = 0 and item_index = 0
		end

feature -- Access

	item_index: INTEGER
			-- The item shown; 0 with none.
		do
			Result := pages.selected_index
		end

	count_items: INTEGER
		do
			Result := pages.count
		end

	wraps: BOOLEAN
			-- Does next after the last go to the first (and previous before the first to the last)?

	interval: INTEGER
			-- Autoplay's milliseconds per item; 0: none.

	is_paused: BOOLEAN
			-- Is autoplay held while the pointer is over the slideshow?

	previous_button, next_button: GUI_BUTTON

	item_changed_actions: GUI_ACTIONS [TUPLE [index: INTEGER]]
			-- Run when the user, or autoplay, shows another item.

feature -- Element change

	extend_item (a_widget: GUI_WIDGET)
			-- An item at the end; the first added is shown.
		require
			gui_thread: is_gui_thread
			not_parented: a_widget.parent = Void
		do
			pages.extend (a_widget, "Item " + (pages.count + 1).out)
			add_dot
			refresh
		ensure
			one_more: count_items = old count_items + 1
		end

	show_item (i: INTEGER)
			-- Show item `i', without an event.
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count_items
		do
			pages.select_page (i)
			refresh
		ensure
			shown: item_index = i
		end

	set_wraps (a_on: BOOLEAN)
		do
			wraps := a_on
			refresh
		ensure
			set: wraps = a_on
		end

	set_interval (a_ms: INTEGER)
			-- Play by itself every `a_ms' milliseconds (0: stop).
		require
			gui_thread: is_gui_thread
			not_negative: a_ms >= 0
		do
			interval := a_ms
			if attached timer as al_t then
				al_t.cancel
				timer := Void
			end
			if a_ms > 0 then
				timer := application.every (a_ms, agent tick)
			end
		ensure
			set: interval = a_ms
		end

	set_paused (a_on: BOOLEAN)
			-- Hold autoplay (the pointer is over the slideshow), or let it go on.
		do
			is_paused := a_on
		ensure
			set: is_paused = a_on
		end

	go_next
			-- As the user's Next.
		do
			move_by_user (item_index + 1)
		end

	go_previous
			-- As the user's Previous.
		do
			move_by_user (item_index - 1)
		end

feature {NONE} -- Implementation

	pages: GUI_TABS
	dots: GUI_STACK
	dot_buttons: ARRAYED_LIST [GUI_BUTTON]
	timer: detachable GUI_TIMER

	build_controls
		local
			l_row: GUI_STACK
		do
			create l_row.make_horizontal
			l_row.set_spacing (8)
			l_row.extend (previous_button)
			l_row.extend_stretching (create {GUI_LABEL}.make (""))
			l_row.extend (dots)
			l_row.extend_stretching (create {GUI_LABEL}.make (""))
			l_row.extend (next_button)
			extend (l_row)
			previous_button.click_actions.extend (agent go_previous)
			next_button.click_actions.extend (agent go_next)
			pages.page_changed_actions.extend (agent (p: INTEGER) do refresh; item_changed_actions.call ([p]) end)
		end

	add_dot
		local
			l_dot: GUI_BUTTON
			l_n: INTEGER
		do
			l_n := pages.count
			create l_dot.make ({STRING_32} "%/8226/")
			l_dot.set_accessible_label ("Item " + l_n.out)
			l_dot.click_actions.extend (agent move_by_user (l_n))
			dots.extend (l_dot)
			dot_buttons.extend (l_dot)
		end

	move_by_user (i: INTEGER)
			-- Go to item `i' (wrapping when `wraps'), and tell.
		local
			l_to: INTEGER
		do
			l_to := i
			if wraps and count_items > 0 then
				if l_to < 1 then l_to := count_items elseif l_to > count_items then l_to := 1 end
			end
			if 1 <= l_to and l_to <= count_items and l_to /= item_index then
				pages.select_page (l_to)
				refresh
				item_changed_actions.call ([l_to])
			end
		end

	tick
		do
			if not is_paused and count_items > 1 then
				if item_index = count_items and not wraps then
					move_by_user_wrapping
				else
					go_next
				end
			end
		end

	move_by_user_wrapping
			-- Autoplay at the end goes back to the first even without `wraps'.
		do
			pages.select_page (1)
			refresh
			item_changed_actions.call ([1])
		end

	refresh
			-- The buttons and dots for the item shown.
		local
			i: INTEGER
		do
			if count_items = 0 then
				previous_button.disable
				next_button.disable
			else
				if wraps or item_index > 1 then previous_button.enable else previous_button.disable end
				if wraps or item_index < count_items then next_button.enable else next_button.disable end
			end
			from i := 1 until i > dot_buttons.count loop
				if i = item_index then dot_buttons [i].disable else dot_buttons [i].enable end
				i := i + 1
			end
		end

end
