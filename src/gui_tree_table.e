note
	description: "[
		A tree with titled columns (NSOutlineView with columns, a GtkColumnView over a
		GtkTreeListModel, SW_TREE_TABLE): nodes as in GUI_TREE, with the node's text in
		column 1 and its other cells set by `set_cell'. Screen readers know it as a tree
		grid, as GUI_TABLE.
	]"

class
	GUI_TREE_TABLE

inherit
	GUI_TREE
		rename
			make as make_tree
		export
			{NONE} make_tree
		end

create
	make

feature {NONE} -- Initialization

	make (a_titles: ARRAY [READABLE_STRING_GENERAL])
			-- An empty tree table with these column titles.
		require
			gui_thread: is_gui_thread
			has_application: has_application
			has_columns: not a_titles.is_empty
		local
			l_c: C_STRING
			l_joined: STRING_32
		do
			create texts.make (16)
			create parents.make (16)
			create roots.make (8)
			create kids.make (16)
			create selection_actions.make
			create expansion_actions.make
			create cells.make (16)
			create titles.make (a_titles.count)
			create l_joined.make (32)
			across a_titles as ic loop
				titles.extend (ic.to_string_32)
				if @ ic.cursor_index > 1 then
					l_joined.append_character ((0x1F).to_character_32)
				end
				l_joined.append_string_general (ic)
			end
			l_c := backend.to_c (l_joined)
			register (backend.tree_table (l_c.item))
		ensure
			empty: node_count = 0
			columns: column_count = a_titles.count
		end

feature -- Access

	column_count: INTEGER
		do
			Result := titles.count
		end

	column_title (c: INTEGER): STRING_32
		require
			valid: 1 <= c and c <= column_count
		do
			Result := titles.i_th (c)
		end

	cell (n, c: INTEGER): STRING_32
			-- Node `n''s text in column `c' (column 1: its node text; empty when never set).
		require
			valid_node: is_node (n)
			valid_column: 1 <= c and c <= column_count
		do
			if c = 1 then
				Result := node_text (n)
			elseif attached cells.item (n) as al_row and then al_row.valid_index (c) and then attached al_row [c] as al_text then
				Result := al_text
			else
				create Result.make_empty
			end
		end

feature -- Element change

	set_cell (n, c: INTEGER; a_text: READABLE_STRING_GENERAL)
			-- Show `a_text' as node `n''s cell in column `c' (column 1 is its node text).
		require
			gui_thread: is_gui_thread
			valid_node: is_node (n)
			valid_column: 1 <= c and c <= column_count
		local
			l_row: ARRAY [detachable STRING_32]
			l_c: C_STRING
		do
			if c = 1 then
				texts.put_i_th (a_text.to_string_32, n)
			else
				if attached cells.item (n) as al_row then
					l_row := al_row
				else
					create l_row.make_filled (Void, 1, column_count)
					cells.put (l_row, n)
				end
				l_row [c] := a_text.to_string_32
			end
			l_c := backend.to_c (a_text)
			backend.tree_table_set_cell (id, n, c, l_c.item)
		ensure
			set: cell (n, c).same_string_general (a_text)
		end

feature {NONE} -- Implementation

	titles: ARRAYED_LIST [STRING_32]

	cells: HASH_TABLE [ARRAY [detachable STRING_32], INTEGER]
			-- Columns 2 .. n of the nodes that have any, by node.

end
