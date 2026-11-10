note
	description: "[
		A grid view (1v-a): items in a flowing grid of cells, each a picture (an image file,
		scaled to fit and kept in proportion) or an icon, over a title and an optional dimmer
		subtitle; for file and image browsers (GtkGridView, NSCollectionView, a drawn
		SW_GRID_VIEW). Items are 1-based; 0 means none. Pictures load off the GUI thread: a
		cell shows its icon or an empty frame until its picture is ready.

		`select_item' and `clear_selection' fire nothing; the user's choice fires
		`selection_actions', and a double click or Return on an item fires `activate_actions'.
		A filter hides items without renumbering them.
	]"

class
	GUI_GRID_VIEW

inherit
	GUI_WIDGET
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create titles.make (16)
			create selection_actions.make
			create activate_actions.make
			register (backend.grid_view)
		ensure
			empty: count = 0
		end

feature -- Access

	count: INTEGER
		do
			Result := titles.count
		end

	item_title (i: INTEGER): STRING_32
		require
			valid: 1 <= i and i <= count
		do
			Result := titles [i]
		end

	selected_index: INTEGER
			-- The first selected item, or 0.
		do
			if backend.grid_view_selected_count (id) > 0 then
				Result := backend.grid_view_selected_at (id, 1)
			end
		ensure
			in_range: 0 <= Result and Result <= count
		end

	selected_items: ARRAYED_LIST [INTEGER]
			-- Every selected item, in order.
		local
			k, n: INTEGER
		do
			n := backend.grid_view_selected_count (id)
			create Result.make (n)
			from k := 1 until k > n loop
				Result.extend (backend.grid_view_selected_at (id, k))
				k := k + 1
			end
		ensure
			in_range: across Result as ic all 1 <= ic and ic <= count end
		end

	is_multiple_selection: BOOLEAN

	filter_text: STRING_32
		attribute
			create Result.make_empty
		end

	shown_count: INTEGER
			-- How many items the filter lets show.
		do
			Result := backend.grid_view_shown_count (id)
		ensure
			in_range: 0 <= Result and Result <= count
		end

	item_width, item_height: INTEGER
			-- The cell's size, logical units (120 by 120 until set).

	selection_actions: GUI_ACTIONS [TUPLE [index: INTEGER]]
			-- Run when the user changes the selection, with the first selected item (0: none).

	activate_actions: GUI_ACTIONS [TUPLE [index: INTEGER]]
			-- Run when the user opens an item: a double click, or Return on the selected one.

feature -- Element change

	extend (a_title: READABLE_STRING_GENERAL)
			-- An item at the end with no picture.
		require
			gui_thread: is_gui_thread
		do
			put_item (a_title, "", "")
		ensure
			one_more: count = old count + 1
		end

	extend_picture (a_title: READABLE_STRING_GENERAL; a_path: PATH)
			-- An item at the end showing the image at `a_path', loaded off the GUI thread.
		require
			gui_thread: is_gui_thread
		do
			put_item (a_title, a_path.name, "")
		ensure
			one_more: count = old count + 1
		end

	extend_icon (a_title: READABLE_STRING_GENERAL; a_name: READABLE_STRING_GENERAL)
			-- An item at the end showing icon `a_name'.
		require
			gui_thread: is_gui_thread
			known: (create {GUI_ICON}).is_known (a_name)
		do
			put_item (a_title, "", a_name)
		ensure
			one_more: count = old count + 1
		end

	set_item_subtitle (i: INTEGER; a_text: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.grid_view_set_subtitle (id, i, l_c.item)
		end

	remove_item (i: INTEGER)
			-- Take item `i' out, quietly; the items after it move up one.
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count
		do
			titles.go_i_th (i)
			titles.remove
			backend.grid_view_remove (id, i)
		ensure
			one_less: count = old count - 1
		end

	wipe_out
		require
			gui_thread: is_gui_thread
		do
			titles.wipe_out
			backend.grid_view_wipe_out (id)
		ensure
			empty: count = 0
		end

	set_item_size (a_width, a_height: INTEGER)
		require
			gui_thread: is_gui_thread
			sensible: a_width >= 32 and a_height >= 32
		do
			item_width := a_width
			item_height := a_height
			backend.grid_view_set_item_size (id, a_width, a_height)
		ensure
			set: item_width = a_width and item_height = a_height
		end

	set_spacing (a_spacing: INTEGER)
		require
			gui_thread: is_gui_thread
			not_negative: a_spacing >= 0
		do
			backend.grid_view_set_spacing (id, a_spacing)
		end

	set_multiple_selection (a_on: BOOLEAN)
		require
			gui_thread: is_gui_thread
		do
			is_multiple_selection := a_on
			backend.grid_view_set_multiple (id, a_on)
		ensure
			set: is_multiple_selection = a_on
		end

	select_item (i: INTEGER)
			-- Select only item `i', without an event.
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count
		do
			backend.grid_view_select (id, i, False)
		ensure
			selected: selected_index = i
			no_event: selection_actions.fire_count = old selection_actions.fire_count
		end

	clear_selection
		require
			gui_thread: is_gui_thread
		do
			backend.grid_view_select (id, 0, False)
		ensure
			none: selected_index = 0
		end

	scroll_to_item (i: INTEGER)
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= count
		do
			backend.grid_view_scroll_to (id, i)
		end

	set_filter (a_text: READABLE_STRING_GENERAL)
			-- Show only the items whose title or subtitle contains `a_text', ignoring case.
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			filter_text := a_text.to_string_32
			l_c := backend.to_c (a_text)
			backend.grid_view_set_filter (id, l_c.item)
		ensure
			set: filter_text.same_string_general (a_text)
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
			-- 50: the user's selection (the first selected item); 51: an item opened.
		do
			if a_type = 50 then
				selection_actions.call ([a_a])
			elseif a_type = 51 and then 1 <= a_a and a_a <= count then
				activate_actions.call ([a_a])
			end
		end

feature {NONE} -- Implementation

	titles: ARRAYED_LIST [STRING_32]

	put_item (a_title, a_path, an_icon: READABLE_STRING_GENERAL)
		local
			l_title, l_path, l_icon: C_STRING
		do
			titles.extend (a_title.to_string_32)
			l_title := backend.to_c (a_title)
			l_path := backend.to_c (a_path)
			l_icon := backend.to_c (an_icon)
			backend.grid_view_extend (id, l_title.item, l_path.item, l_icon.item)
		end

invariant
	titles_exist: titles /= Void

end
