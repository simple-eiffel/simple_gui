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
			dispatch, has_row_pebbles, pebble_at_row
		end

	GUI_SCROLLING

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
			create roots.make (8)
			create kids.make (16)
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

	children_of (n: INTEGER): ARRAYED_LIST [INTEGER]
			-- `n''s children in order (0: the roots).
		require
			valid: n = 0 or else is_node (n)
		do
			if n = 0 then
				Result := roots.twin
			else
				Result := kids [n].twin
			end
		end

	is_ancestor (a, n: INTEGER): BOOLEAN
			-- Is `a' above `n' (its parent, its parent's parent...)?
		require
			valid_a: is_node (a)
			valid_n: is_node (n)
		local
			k: INTEGER
		do
			from k := parents [n] until k = 0 or Result loop
				Result := k = a
				k := parents [k]
			end
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

	move_node (n, a_parent, a_position: INTEGER)
			-- Move `n' (with everything under it) under `a_parent' (0: to the top level), as
			-- child number `a_position' there (0: last), without an event.
		require
			gui_thread: is_gui_thread
			valid: is_node (n)
			valid_parent: a_parent = 0 or else is_node (a_parent)
			not_into_itself: a_parent /= n and then (a_parent = 0 or else not is_ancestor (n, a_parent))
			position_valid: a_position >= 0
		local
			l_from, l_into: ARRAYED_LIST [INTEGER]
		do
			l_from := siblings (parents [n])
			l_from.prune_all (n)
			l_into := siblings (a_parent)
			if a_position = 0 or a_position > l_into.count then
				l_into.extend (n)
			else
				l_into.go_i_th (a_position)
				l_into.put_left (n)
			end
			parents [n] := a_parent
			backend.tree_move (id, n, a_parent, l_into.index_of (n, 1))
		ensure
			moved: parent_of (n) = a_parent
			placed: a_position > 0 and a_position <= old children_of (a_parent).count + 1 implies children_of (a_parent) [a_position] = n
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

feature -- Moving nodes (1q-c)

	is_reorderable: BOOLEAN
			-- May the user move a node by dragging (or picking) it onto another?

	set_reorderable (a_on: BOOLEAN)
			-- Let the user move nodes (`a_on'), or stop. A node dropped on another becomes its
			-- last child; dropped below the rows, the last top-level node; never into itself
			-- or under its own children. The tree moves it and `move_actions' tell the node,
			-- its new parent and its place there. A node carries a GUI_ROW_MOVE unless a row
			-- pebble function is set, and only this tree takes it.
		require
			gui_thread: is_gui_thread
		do
			is_reorderable := a_on
			if a_on and not is_reorder_hooked then
				is_reorder_hooked := True
				drop_actions.extend_checked (agent take_node_move, agent is_own_node_move)
			end
			tell_pick
		ensure
			set: is_reorderable = a_on
		end

	move_actions: GUI_ACTIONS [TUPLE [node, new_parent, position: INTEGER]]
			-- Run after the user moved `node' under `new_parent' (0: the top level), as child
			-- number `position'.
		do
			if attached move_actions_made as al_a then
				Result := al_a
			else
				create Result.make
				move_actions_made := Result
			end
		end

	has_row_pebbles: BOOLEAN
		do
			Result := Precursor or is_reorderable
		end

	pebble_at_row (a_row: INTEGER): detachable ANY
			-- `a_row' is a node number for a tree.
		do
			if is_node (a_row) and is_reorderable and row_pebble_function = Void then
				create {GUI_ROW_MOVE} Result.make (Current, a_row)
			else
				Result := Precursor (a_row)
			end
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

	roots: ARRAYED_LIST [INTEGER]
			-- The top-level nodes in order.

	kids: ARRAYED_LIST [ARRAYED_LIST [INTEGER]]
			-- Each node's children in order.

	siblings (a_parent: INTEGER): ARRAYED_LIST [INTEGER]
			-- The live list of `a_parent''s children (0: the roots).
		do
			if a_parent = 0 then
				Result := roots
			else
				Result := kids [a_parent]
			end
		end

	is_reorder_hooked: BOOLEAN

	move_actions_made: detachable like move_actions

	is_own_node_move (a_pebble: ANY): BOOLEAN
			-- Is `a_pebble' one of this tree's nodes, while it is reorderable?
		do
			Result := is_reorderable and then attached {GUI_ROW_MOVE} a_pebble as al_m
				and then al_m.source = Current and then is_node (al_m.row)
		end

	take_node_move (a_move: GUI_ROW_MOVE)
			-- A node of this tree dropped on node `last_drop_row' (0: below the rows).
		local
			n, l_parent: INTEGER
		do
			n := a_move.row
			l_parent := last_drop_row
			if not is_node (l_parent) then
				l_parent := 0
			end
			if is_node (n) and then l_parent /= n and then (l_parent = 0 or else not is_ancestor (n, l_parent))
				and then not (parents [n] = l_parent and then siblings (l_parent).last = n)
			then
				move_node (n, l_parent, 0)
				move_actions.call ([n, l_parent, siblings (l_parent).count])
			end
		end

	add (a_parent: INTEGER; a_text: READABLE_STRING_GENERAL)
		local
			l_c: C_STRING
		do
			texts.extend (a_text.to_string_32)
			parents.extend (a_parent)
			kids.extend (create {ARRAYED_LIST [INTEGER]}.make (2))
			last_node := texts.count
			siblings (a_parent).extend (last_node)
			l_c := backend.to_c (a_text)
			backend.tree_add (id, last_node, a_parent, l_c.item)
		end

invariant
	paired: texts.count = parents.count
	kids_paired: kids.count = texts.count

end
