note
	description: "[
		Nodes of text in a hierarchy the user expands and collapses (NSOutlineView, a
		GtkListView over a GtkTreeListModel, SW_TREE). Nodes are numbered 1, 2, 3... in the
		order they are added; 0 means none.

		`add_root', `add_child', `expand', `collapse' and `select_node' fire nothing (selecting
		a node expands its ancestors so it can be seen). A user's selection fires
		`selection_actions' with the node; a user's expanding or collapsing fires
		`expansion_actions' with the node and whether it is now expanded.
	]"

class
	GUI_TREE

inherit
	GUI_ROW_SOURCE
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make
			-- An empty tree.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		do
			create texts.make (16)
			create parents.make (16)
			create selection_actions.make
			create expansion_actions.make
			register (backend.tree)
		ensure
			empty: node_count = 0
		end

feature -- Access

	node_count: INTEGER
		do
			Result := texts.count
		end

	is_node (n: INTEGER): BOOLEAN
		do
			Result := 1 <= n and n <= node_count
		end

	node_text (n: INTEGER): STRING_32
		require
			valid: is_node (n)
		do
			Result := texts.i_th (n)
		end

	parent_of (n: INTEGER): INTEGER
			-- The node `n' was added under, or 0 for a root.
		require
			valid: is_node (n)
		do
			Result := parents.i_th (n)
		end

	is_expanded (n: INTEGER): BOOLEAN
			-- Are `n''s children shown?
		require
			valid: is_node (n)
		do
			Result := backend.tree_is_expanded (id, n)
		end

	selected_node: INTEGER
			-- The selected node, or 0.
		do
			Result := backend.tree_selected (id)
		ensure
			in_range: Result = 0 or else is_node (Result)
		end

	last_node: INTEGER
			-- The node added most recently.

	selection_actions: GUI_ACTIONS [TUPLE [node: INTEGER]]
			-- Run when the user selects a node (0: none).

	expansion_actions: GUI_ACTIONS [TUPLE [node: INTEGER; is_open: BOOLEAN]]
			-- Run when the user expands or collapses a node.

feature -- Element change

	add_root (a_text: READABLE_STRING_GENERAL)
			-- Add a top-level node; its number is `last_node'.
		require
			gui_thread: is_gui_thread
		do
			add (0, a_text)
		ensure
			one_more: node_count = old node_count + 1
			numbered: last_node = node_count and parent_of (last_node) = 0
		end

	add_child (a_parent: INTEGER; a_text: READABLE_STRING_GENERAL)
			-- Add a node under `a_parent'; its number is `last_node'.
		require
			gui_thread: is_gui_thread
			valid_parent: is_node (a_parent)
		do
			add (a_parent, a_text)
		ensure
			one_more: node_count = old node_count + 1
			numbered: last_node = node_count and parent_of (last_node) = a_parent
		end

	expand (n: INTEGER)
			-- Show `n''s children, without an event.
		require
			gui_thread: is_gui_thread
			valid: is_node (n)
		do
			backend.tree_set_expanded (id, n, True)
		ensure
			no_event: expansion_actions.fire_count = old expansion_actions.fire_count
		end

	collapse (n: INTEGER)
			-- Hide `n''s children, without an event.
		require
			gui_thread: is_gui_thread
			valid: is_node (n)
		do
			backend.tree_set_expanded (id, n, False)
		ensure
			collapsed: not is_expanded (n)
			no_event: expansion_actions.fire_count = old expansion_actions.fire_count
		end

	select_node (n: INTEGER)
			-- Select `n' (0: none), expanding its ancestors; no event.
		require
			gui_thread: is_gui_thread
			valid: n = 0 or else is_node (n)
		do
			backend.tree_select (id, n)
		ensure
			selected: selected_node = n
			no_event: selection_actions.fire_count = old selection_actions.fire_count
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
		do
			if a_type = 4 then
				selection_actions.call ([a_a])
			elseif a_type = 15 then
				expansion_actions.call ([a_a, a_b = 1])
			end
		end

feature {NONE} -- Implementation

	texts: ARRAYED_LIST [STRING_32]

	parents: ARRAYED_LIST [INTEGER]

	add (a_parent: INTEGER; a_text: READABLE_STRING_GENERAL)
		local
			l_c: C_STRING
		do
			texts.extend (a_text.to_string_32)
			parents.extend (a_parent)
			last_node := texts.count
			l_c := backend.to_c (a_text)
			backend.tree_add (id, last_node, a_parent, l_c.item)
		end

invariant
	paired: texts.count = parents.count

end
