note
	description: "[
		Pagination (1t): Previous, page numbers with gaps, Next, for results shown a page at a
		time. The first and last pages, and `siblings' pages either side of the current one,
		have buttons; a gap is a "…". The current page's button is disabled, as are Previous on
		the first page and Next on the last. A shared composite of GUI_BUTTONs and GUI_LABELs,
		so it looks native on each platform. `set_page' fires nothing; the user's clicks do.
	]"

class
	GUI_PAGINATION

inherit
	GUI_STACK
		rename
			make_horizontal as make_stack
		export
			{NONE} make_vertical, make_stack, extend, extend_stretching, extend_aligned
		end

create
	make, make_with_siblings

feature {NONE} -- Initialization

	make
			-- One page either side of the current one.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			make_with_siblings (1)
		ensure
			no_pages: page_count = 0 and page = 0
			siblings: siblings = 1
		end

	make_with_siblings (a_siblings: INTEGER)
			-- `a_siblings' pages either side of the current one.
		require
			gui_thread: is_gui_thread
			has_application: has_application
			sensible: 0 <= a_siblings and a_siblings <= 5
		local
			i: INTEGER
			l_b: GUI_BUTTON
			l_gap: GUI_LABEL
		do
				-- every part first: the stack registers Current, which must then be whole
			siblings := a_siblings
			create page_actions.make
			create slots.make (slot_count)
			create gaps.make (slot_count)
			create previous_button.make ({STRING_32} "%/8249/")
			create next_button.make ({STRING_32} "%/8250/")
			from i := 1 until i > slot_count loop
				create l_b.make ("0")
				slots.extend (l_b)
				create l_gap.make ({STRING_32} "%/8230/")
				gaps.extend (l_gap)
				i := i + 1
			end
			make_stack
			set_spacing (4)
			previous_button.set_accessible_label ("Previous page")
			next_button.set_accessible_label ("Next page")
			extend (previous_button)
			from i := 1 until i > slot_count loop
				slots [i].hide
				extend (slots [i])
				gaps [i].hide
				extend (gaps [i])
				i := i + 1
			end
			extend (next_button)
				-- every attribute is set: the agents may now name Current
			previous_button.click_actions.extend (agent choose_by_user (-1))
			next_button.click_actions.extend (agent choose_by_user (0))
			from i := 1 until i > slot_count loop
				slots [i].click_actions.extend (agent choose_slot (i))
				i := i + 1
			end
			arrange
		ensure
			no_pages: page_count = 0 and page = 0
			siblings: siblings = a_siblings
		end

feature -- Access

	page: INTEGER
			-- The current page; 0 when there are none.

	page_count: INTEGER

	siblings: INTEGER
			-- How many pages either side of the current one have buttons.

	page_actions: GUI_ACTIONS [TUPLE [page: INTEGER]]
			-- Run when the user chooses a page.

	previous_button, next_button: GUI_BUTTON

	button_for (p: INTEGER): detachable GUI_BUTTON
			-- The button showing page `p', if one does.
		do
			across slots as ic loop
				if ic.is_shown and then ic.text.same_string (p.out) then
					Result := ic
				end
			end
		end

	shown_pages: ARRAYED_LIST [INTEGER]
			-- The page numbers with buttons, in order; 0 for each gap.
		do
			Result := layout (page, page_count)
		end

feature -- Element change

	set_page_count (n: INTEGER)
			-- `n' pages; the current page stays where it can (page 1 when there was none).
		require
			gui_thread: is_gui_thread
			not_negative: n >= 0
		do
			page_count := n
			if n = 0 then
				page := 0
			else
				page := page.max (1).min (n)
			end
			arrange
		ensure
			counted: page_count = n
			in_range: (n = 0 implies page = 0) and (n > 0 implies 1 <= page and page <= n)
		end

	set_page (p: INTEGER)
			-- Make `p' the current page, without an event.
		require
			gui_thread: is_gui_thread
			valid: 1 <= p and p <= page_count
		do
			page := p
			arrange
		ensure
			set: page = p
			no_event: page_actions.fire_count = old page_actions.fire_count
		end

feature {NONE} -- Implementation

	slots: ARRAYED_LIST [GUI_BUTTON]
			-- The number buttons, in order; each is followed by its gap label.

	gaps: ARRAYED_LIST [GUI_LABEL]

	slot_count: INTEGER
			-- The most items a layout has: the first, a gap, the siblings and the current, a gap, the last.
		do
			Result := 2 * siblings + 5
		end

	layout (p, n: INTEGER): ARRAYED_LIST [INTEGER]
			-- The items for page `p' of `n': page numbers, 0 for a gap, at most `slot_count'.
		local
			k, l_low, l_high: INTEGER
		do
			create Result.make (slot_count)
			if n <= slot_count then
				from k := 1 until k > n loop Result.extend (k); k := k + 1 end
			elseif p <= siblings + 3 then
					-- near the start: 1 .. 2s+3, gap, n
				from k := 1 until k > 2 * siblings + 3 loop Result.extend (k); k := k + 1 end
				Result.extend (0)
				Result.extend (n)
			elseif p >= n - siblings - 2 then
					-- near the end: 1, gap, n-2s-2 .. n
				Result.extend (1)
				Result.extend (0)
				from k := n - 2 * siblings - 2 until k > n loop Result.extend (k); k := k + 1 end
			else
				l_low := p - siblings
				l_high := p + siblings
				Result.extend (1)
				Result.extend (0)
				from k := l_low until k > l_high loop Result.extend (k); k := k + 1 end
				Result.extend (0)
				Result.extend (n)
			end
		ensure
			fits: Result.count <= slot_count
			ends: n > 0 implies (Result.first = 1 and Result.last = n)
		end

	arrange
			-- Show the buttons and gaps for the current page.
		local
			l_items: ARRAYED_LIST [INTEGER]
			i: INTEGER
		do
			l_items := layout (page, page_count)
			from i := 1 until i > slot_count loop
				if i <= l_items.count and then l_items [i] > 0 then
					slots [i].set_text (l_items [i].out)
					slots [i].set_accessible_label ("Page " + l_items [i].out)
					slots [i].show
					gaps [i].hide
					if l_items [i] = page then slots [i].disable else slots [i].enable end
				elseif i <= l_items.count then
					slots [i].hide
					gaps [i].show
				else
					slots [i].hide
					gaps [i].hide
				end
				i := i + 1
			end
			if page > 1 then previous_button.enable else previous_button.disable end
			if page > 0 and page < page_count then next_button.enable else next_button.disable end
			set_accessible_label ("Page " + page.out + " of " + page_count.out)
		end

	choose_slot (i: INTEGER)
		do
			if slots [i].text.is_integer then
				choose_by_user (slots [i].text.to_integer)
			end
		end

	choose_by_user (p: INTEGER)
			-- The user chose page `p' (-1 previous, 0 next).
		local
			l_to: INTEGER
		do
			if p = -1 then
				l_to := page - 1
			elseif p = 0 then
				l_to := page + 1
			else
				l_to := p
			end
			if 1 <= l_to and l_to <= page_count and l_to /= page then
				page := l_to
				arrange
				page_actions.call ([l_to])
			end
		end

invariant
	page_in_range: (page_count = 0 implies page = 0) and (page_count > 0 implies 1 <= page and page <= page_count)
	one_gap_each: slots.count = gaps.count

end
