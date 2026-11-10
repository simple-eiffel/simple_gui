note
	description: "[
		Sidebar navigation (1t): pages shown one at a time beside a list of their titles, with
		icons, badges and group headings; the list can collapse to icons only (a GtkListBox
		navigation sidebar beside a GtkStack; a source list beside a tabless NSTabView; drawn
		by simple_widgets on Windows). Pages are 1-based and headings are not counted.
		`select_page', `collapse' and `expand' fire nothing; the user's choices do.
	]"

class
	GUI_SIDEBAR

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
			create collapse_actions.make
			register (backend.sidebar)
		ensure
			empty: count = 0
			open: not is_collapsed
		end

feature -- Access

	page_count: INTEGER
		do
			Result := count
		end

	page_title (i: INTEGER): STRING_32
		require
			valid: 1 <= i and i <= count
		do
			Result := titles.i_th (i)
		end

	selected_index: INTEGER
			-- The page shown, or 0 when there are none.
		do
			Result := backend.sidebar_selected (id)
		ensure
			in_range: 0 <= Result and Result <= count
		end

	is_collapsible: BOOLEAN
			-- Does the list have a collapse button?

	is_collapsed: BOOLEAN
			-- Does the list show icons only?
		do
			Result := backend.sidebar_is_collapsed (id)
		end

	page_changed_actions: GUI_ACTIONS [TUPLE [page: INTEGER]]
			-- Run when the user chooses a page.

	collapse_actions: GUI_ACTIONS [TUPLE [is_collapsed: BOOLEAN]]
			-- Run when the user collapses or expands the list.

feature -- Element change

	extend (a_page: GUI_WIDGET; a_title: READABLE_STRING_GENERAL)
			-- Add `a_page' as the last page, its title in the list. The first page added is shown.
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
			backend.sidebar_extend (id, a_page.id, l_c.item)
		ensure
			parent_set: a_page.parent = Current
			last: children.last = a_page and page_title (count).same_string_general (a_title)
			first_shown: old count = 0 implies selected_index = 1
		end

	add_heading (a_text: READABLE_STRING_GENERAL)
			-- A group heading in the list before the next page added; not a page.
		require
			gui_thread: is_gui_thread
			has_text: not a_text.is_empty
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.sidebar_add_heading (id, l_c.item)
		ensure
			no_page: count = old count
		end

	set_page_icon (i: INTEGER; a_name: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count
			known: (create {GUI_ICON}).is_known (a_name)
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_name)
			backend.sidebar_set_icon (id, i, l_c.item)
		end

	set_page_badge (i: INTEGER; a_text: READABLE_STRING_GENERAL)
			-- `a_text' as a badge after page `i''s title (empty: none).
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count
			short: a_text.count <= 8
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.sidebar_set_badge (id, i, l_c.item)
		end

	select_page (i: INTEGER)
			-- Show page `i', without an event.
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count
		do
			backend.sidebar_select (id, i)
		ensure
			shown: selected_index = i
			no_event: page_changed_actions.fire_count = old page_changed_actions.fire_count
		end

	set_collapsible (a_on: BOOLEAN)
			-- Give the list a collapse button at its foot, or not.
		require
			gui_thread: is_gui_thread
		do
			is_collapsible := a_on
			backend.sidebar_set_collapsible (id, a_on)
		ensure
			set: is_collapsible = a_on
		end

	collapse
			-- Icons only, titles as tooltips; no event.
		require
			gui_thread: is_gui_thread
		do
			backend.sidebar_set_collapsed (id, True)
		ensure
			collapsed: is_collapsed
		end

	expand
			-- Titles again; no event.
		require
			gui_thread: is_gui_thread
		do
			backend.sidebar_set_collapsed (id, False)
		ensure
			open: not is_collapsed
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
			-- 46: the user chose page `a_a'; 47: the user collapsed (`a_b' = 1) or expanded the list.
		do
			if a_type = 46 and then 1 <= a_a and a_a <= count then
				page_changed_actions.call ([a_a])
			elseif a_type = 47 then
				collapse_actions.call ([a_b = 1])
			end
		end

feature {NONE} -- Implementation

	titles: ARRAYED_LIST [STRING_32]

invariant
	one_title_each: titles.count = children.count

end
