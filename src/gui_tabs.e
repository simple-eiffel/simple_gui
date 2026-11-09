note
	description: "[
		Pages shown one at a time under a row of tabs (NSTabView, GtkNotebook, SW_NOTEBOOK).
		Pages are 1-based; `select_page' never fires `page_changed_actions', a user's choice
		does. The tabs follow the base direction: right to left, the first tab is at the right.
	]"

class
	GUI_TABS

inherit
	GUI_CONTAINER
		redefine
			dispatch
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
			create titles.make (4)
			create page_changed_actions.make
			register (backend.tabs)
		ensure
			empty: count = 0
		end

feature -- Access

	page_title (i: INTEGER): STRING_32
			-- The title on tab `i'.
		require
			valid: 1 <= i and i <= count
		do
			Result := titles.i_th (i)
		end

	selected_index: INTEGER
			-- The page shown, or 0 when there are no pages.
		do
			Result := backend.tabs_selected (id)
		ensure
			in_range: 0 <= Result and Result <= count
		end

	page_changed_actions: GUI_ACTIONS [TUPLE [page: INTEGER]]
			-- Run when the user chooses another page.

feature -- Element change

	extend (a_page: GUI_WIDGET; a_title: READABLE_STRING_GENERAL)
			-- Add `a_page' as the last page, under a tab titled `a_title'. The first page added is shown.
		require
			gui_thread: is_gui_thread
			not_parented: a_page.parent = Void
			not_self: a_page /= Current
			has_title: not a_title.is_empty
		local
			l_c: C_STRING
		do
			adopt (a_page)
			titles.extend (a_title.to_string_32)
			l_c := backend.to_c (a_title)
			backend.tabs_extend (id, a_page.id, l_c.item)
		ensure
			parent_set: a_page.parent = Current
			last: children.last = a_page and page_title (count).same_string_general (a_title)
			first_shown: old count = 0 implies selected_index = 1
		end

	select_page (i: INTEGER)
			-- Show page `i', without a page-changed event.
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count
		do
			backend.tabs_select (id, i)
		ensure
			shown: selected_index = i
			no_event: page_changed_actions.fire_count = old page_changed_actions.fire_count
		end

	set_page_icon (i: INTEGER; a_name: READABLE_STRING_GENERAL)
			-- Show icon `a_name' before tab `i''s title.
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count
			known: (create {GUI_ICON}).is_known (a_name)
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_name)
			backend.tabs_set_page_icon (id, i, l_c.item)
		end

	set_page_badge (i: INTEGER; a_text: READABLE_STRING_GENERAL)
			-- Show `a_text' as a badge on tab `i' (empty: none).
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count
			short: a_text.count <= 8
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.tabs_set_page_badge (id, i, l_c.item)
		end

	set_page_title (i: INTEGER; a_title: READABLE_STRING_GENERAL)
			-- Retitle tab `i' (for example on a change of language).
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count
			has_title: not a_title.is_empty
		local
			l_c: C_STRING
		do
			titles.put_i_th (a_title.to_string_32, i)
			l_c := backend.to_c (a_title)
			backend.tabs_set_title (id, i, l_c.item)
		ensure
			set: page_title (i).same_string_general (a_title)
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 13 then
				page_changed_actions.call ([a_a])
			end
		end

feature {NONE} -- Implementation

	titles: ARRAYED_LIST [STRING_32]

invariant
	one_title_each: titles.count = children.count

end
