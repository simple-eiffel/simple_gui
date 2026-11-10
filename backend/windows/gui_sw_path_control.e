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
			create root_icon.make_empty
		ensure
			empty: parts.is_empty
		end

feature -- Access

	parts: ARRAYED_LIST [STRING_32]

	path_text: STRING_32

	on_part: detachable PROCEDURE [INTEGER]

	on_chevron: detachable PROCEDURE [INTEGER]

	on_space: detachable PROCEDURE

	has_chevrons: BOOLEAN
			-- Are the separators clickable chevrons, with the empty area after them?

	root_icon: STRING_32
			-- The name of the icon before part 1; empty for none.

	root_glyph: INTEGER
			-- The SW glyph drawing `root_icon'.

feature -- Element change

	set_on_part (a_action: PROCEDURE [INTEGER])
		do
			on_part := a_action
		end

	set_on_chevron (a_action: PROCEDURE [INTEGER])
			-- Told which part's chevron was clicked (the part before it).
		do
			on_chevron := a_action
		end

	set_on_space (a_action: PROCEDURE)
			-- Told the empty space after the last part was clicked (or Ctrl+L, Alt+D, F4).
		do
			on_space := a_action
		end

	set_chevrons (a_on: BOOLEAN)
			-- 1p-b: each separator a clickable chevron, one more after the last part, and a
			-- stretching empty area after that. Rebuilds the parts.
		do
			has_chevrons := a_on
			show_parts
		ensure
			set: has_chevrons = a_on
		end

	set_root_icon (a_name: READABLE_STRING_GENERAL; a_glyph: INTEGER)
			-- 1p-b: the icon `a_name' (drawn as SW glyph `a_glyph', 0 for none) before part 1;
			-- an empty name for none. Rebuilds the parts.
		require
			named: a_name.is_empty implies a_glyph = 0
		do
			root_icon := a_name.to_string_32
			root_glyph := a_glyph
			show_parts
		ensure
			set: root_icon.same_string_general (a_name)
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
			if root_glyph > 0 then
				put (create {SW_ICON}.make (root_glyph, 16.0))
			end
			from i := 1 until i > parts.count loop
				if i > 1 then
					put_separator (i - 1)
				end
				create l_b.make (parts.i_th (i), agent report (i))
				put (l_b)
				i := i + 1
			end
			if has_chevrons then
				if parts.count > 0 then
					put_separator (parts.count)
				end
				put (create {GUI_SW_PATH_SPACE}.make_space (agent report_space))
			end
		end

	put_separator (a_before: INTEGER)
			-- The "›" after part `a_before': a label, or with chevrons a flat button that
			-- reports a click on it.
		local
			l_c: SW_BUTTON
		do
			if has_chevrons then
				create l_c.make ({STRING_32} "%/8250/", agent report_chevron (a_before))
				l_c.set_kind ({SW_BUTTON}.Kind_quiet)
				put (l_c)
			else
				put (create {SW_LABEL}.make_ui ({STRING_32} "%/8250/"))
			end
		end

	press_chevron (a_part: INTEGER)
			-- As the user clicking the chevron after part `a_part'.
		require
			chevrons: has_chevrons
			valid: 1 <= a_part and a_part <= parts.count
		do
			report_chevron (a_part)
		end

	press_space
			-- As the user clicking the empty area after the last part, or Ctrl+L, Alt+D or F4.
		do
			report_space
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

	report_chevron (i: INTEGER)
		do
			if attached on_chevron as al_action then
				al_action.call ([i])
			end
		end

	report_space
		do
			if attached on_space as al_action then
				al_action.call
			end
		end

	report (i: INTEGER)
		do
			if attached on_part as al_action then
				al_action.call ([i])
			end
		end

invariant
	parts_exist: parts /= Void
	icon_named: root_icon /= Void

end
