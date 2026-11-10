note
	description: "[
		GUI_PATH_CONTROL on Windows: a row of link buttons, one per part of a path (the root
		first: "/" or a drive like "C:"), between chevrons; read as navigation. A part
		clicked is reported through `on_part' with its number (1 = the root).
	]"

class
	GUI_SW_PATH_CONTROL

inherit
	SW_ROW
		redefine
			shared_role_name
		end

create
	make_path

feature {NONE} -- Initialization

	make_path
		do
			make
			set_gap (2.0)
			create parts.make (8)
			create path_text.make_empty
		ensure
			empty: parts.is_empty
		end

feature -- Access

	parts: ARRAYED_LIST [STRING_32]

	path_text: STRING_32

	on_part: detachable PROCEDURE [INTEGER]

feature -- Element change

	set_on_part (a_action: PROCEDURE [INTEGER])
		do
			on_part := a_action
		end

	set_path (a_path: READABLE_STRING_GENERAL)
			-- Split `a_path' into its parts, and show them.
		local
			l_piece: STRING_32
			i: INTEGER
		do
			path_text := a_path.to_string_32
			parts.wipe_out
			if not path_text.is_empty and then (path_text.item (1) = '/' or path_text.item (1) = '\') then
					-- the root: "/", or "\" for a Windows path without a drive
				parts.extend (path_text.item (1).out.to_string_32)
			end
			create l_piece.make_empty
			from i := 1 until i > path_text.count loop
				if path_text.item (i) = '/' or path_text.item (i) = '\' then
					if not l_piece.is_empty then
						parts.extend (l_piece)
						create l_piece.make_empty
					end
				else
					l_piece.extend (path_text.item (i))
				end
				i := i + 1
			end
			if not l_piece.is_empty then
				parts.extend (l_piece)
			end
			show_parts
		end

	set_parts (a_parts: READABLE_STRING_GENERAL)
			-- Any parts (1t breadcrumbs), joined by U+001F, shown as they are.
		do
			path_text := {STRING_32} ""
			parts.wipe_out
			across a_parts.to_string_32.split ('%/31/') as ic loop
				parts.extend (ic)
			end
			show_parts
		end

	show_parts
			-- A link button per part, chevrons between.
		local
			i: INTEGER
			l_b: GUI_SW_LINK_BUTTON
		do
			children.wipe_out
			from i := 1 until i > parts.count loop
				if i > 1 then
					put (create {SW_LABEL}.make_ui ({STRING_32} "%/8250/"))
				end
				create l_b.make (parts.i_th (i), agent report (i))
				put (l_b)
				i := i + 1
			end
		end

	press_part (i: INTEGER)
			-- As the user clicking part `i'.
		require
			valid: 1 <= i and i <= parts.count
		do
			report (i)
		end

feature -- Accessibility

	shared_role_name: detachable STRING_32
		do
			Result := {STRING_32} "navigation"
		end

feature {NONE} -- Implementation

	report (i: INTEGER)
		do
			if attached on_part as al_action then
				al_action.call ([i])
			end
		end

invariant
	parts_exist: parts /= Void

end
