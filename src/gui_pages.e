note
	description: "[
		A stack of pages showing one at a time, with no tab strip (1x-c): the "stacks" of
		the outline; GUI_STACK stays a row or column. Pages are 1-based and switch only from
		code, with `select_page', through `page_transition' (GUI_PAGE_SWITCHER). GTK: a
		GtkStack with its own transition off; macOS: a host view of our own; Windows: a
		drawn page host.
	]"

class
	GUI_PAGES

inherit
	GUI_PAGE_SWITCHER
		redefine
			switch_ended
		end

create
	make

feature {NONE} -- Initialization

	make
			-- No pages yet.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create children.make (4)
			create page_changed_actions.make
			register (backend.pages)
		ensure
			empty: count = 0
			no_transition: page_transition = Transition_none
		end

feature -- Access

	selected_index: INTEGER
			-- The page selected (shown, or being switched to), or 0 when there are no pages.
		do
			Result := backend.pages_selected (id)
		end

	page_changed_actions: GUI_ACTIONS [TUPLE [page: INTEGER]]
			-- Run once when a switch `select_page' started has ended, with the new page whole:
			-- at the transition's end, or on the queue's next turn with no transition or
			-- while motion is reduced. A switch cut short by another runs nothing.

feature -- Element change

	extend_page (a_page: GUI_WIDGET)
			-- Add `a_page' as the last page. The first page added is shown.
		require
			gui_thread: is_gui_thread
			not_parented: a_page.parent = Void
			not_self: a_page /= Current
		do
			adopt (a_page)
			backend.pages_extend (id, a_page.id)
			if count = 1 then
				shown_page := 1
			end
		ensure
			parent_set: a_page.parent = Current
			last: children.last = a_page
			first_shown: old count = 0 implies selected_index = 1
		end

	select_page (i: INTEGER)
			-- Switch to page `i' through `page_transition'; `page_changed_actions' when the
			-- switch ends. Nothing when page `i' is already the one selected.
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count
		do
			if i /= shown_page then
				start_switch (shown_page, i)
			end
		ensure
			selected: selected_index = i
			not_yet: page_changed_actions.fire_count = old page_changed_actions.fire_count
		end

feature {NONE} -- Implementation

	show_page_at_once (i: INTEGER)
			-- Show page `i' alone.
		do
			backend.pages_select (id, i)
		end

	switch_ended (a_page: INTEGER)
			-- Tell the program the switch to `a_page' has ended.
		do
			page_changed_actions.call ([a_page])
		end

end
