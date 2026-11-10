note
	description: "[
		A center document with tool panels docked around it on four sides (1r-a; EiffelStudio's
		Smart Docking). Each side shows its panels stacked along its long axis, or as tabs one at
		a time; its depth drags at the edge it shares with the center, which keeps `Min_center'
		each way; it collapses to a strip that names its panels (a press on a name opens the side
		showing that panel) and expands to the size it had. A side with no visible panel takes no
		room. Panels are known by their keys; `layout' writes the whole arrangement as text and
		`restore_layout' reads it back, all or nothing. The user's changes fire `layout_actions';
		code's changes fire nothing.
	]"

class
	GUI_DOCK

inherit
	GUI_CONTAINER
		redefine
			dispatch
		end

create
	make

feature {NONE} -- Initialization

	make (a_center: GUI_WIDGET)
			-- A dock around `a_center', with no panels.
		require
			gui_thread: is_gui_thread
			has_application: has_application
			free_center: a_center.parent = Void
		do
			create children.make (4)
			create panels.make (4)
			create on_side.make_filled (create {ARRAYED_LIST [GUI_DOCK_PANEL]}.make (0), Side_left, Side_bottom)
			on_side [Side_left] := create {ARRAYED_LIST [GUI_DOCK_PANEL]}.make (2)
			on_side [Side_right] := create {ARRAYED_LIST [GUI_DOCK_PANEL]}.make (2)
			on_side [Side_top] := create {ARRAYED_LIST [GUI_DOCK_PANEL]}.make (2)
			on_side [Side_bottom] := create {ARRAYED_LIST [GUI_DOCK_PANEL]}.make (2)
			create tabbed.make_filled (False, Side_left, Side_bottom)
			create collapsed.make_filled (False, Side_left, Side_bottom)
			create auto_hidden.make_filled (False, Side_left, Side_bottom)
			create layout_actions.make
			center := a_center
			register (backend.dock (a_center.id))
			adopt (a_center)
		ensure
			centered: center = a_center and a_center.parent = Current
			empty: panels.is_empty
		end

feature -- Sides

	Side_left: INTEGER = 1
	Side_right: INTEGER = 2
	Side_top: INTEGER = 3
	Side_bottom: INTEGER = 4

	Min_center: INTEGER = 120
			-- What the center keeps across and down, in logical units, whatever the sides ask.

	is_side (a_side: INTEGER): BOOLEAN
		do
			Result := a_side >= Side_left and a_side <= Side_bottom
		end

feature -- Access

	center: GUI_WIDGET

	panels: ARRAYED_LIST [GUI_DOCK_PANEL]
			-- Every panel, shown or hidden, in the order added; a panel's index here names it to
			-- the backend and in events.

	panels_on (a_side: INTEGER): ARRAYED_LIST [GUI_DOCK_PANEL]
			-- The panels of `a_side', shown or hidden, in their order on it.
		require
			side: is_side (a_side)
		do
			Result := on_side [a_side].twin
		end

	panel_by_key (a_key: READABLE_STRING_GENERAL): detachable GUI_DOCK_PANEL
		do
			across panels as ic until Result /= Void loop
				if ic.key.same_string_general (a_key) then
					Result := ic
				end
			end
		end

	index_of (a_panel: GUI_DOCK_PANEL): INTEGER
			-- `a_panel''s index in `panels' (0: not here).
		do
			Result := panels.index_of (a_panel, 1)
		end

	is_tabbed (a_side: INTEGER): BOOLEAN
		require
			side: is_side (a_side)
		do
			Result := tabbed [a_side]
		end

	active_panel (a_side: INTEGER): detachable GUI_DOCK_PANEL
			-- The panel a tabbed side shows (else the first shown on it); Void when none shows.
		require
			side: is_side (a_side)
		do
			if attached active [a_side] as al_a and then al_a.is_visible and then al_a.side = a_side then
				Result := al_a
			else
				across on_side [a_side] as ic until Result /= Void loop
					if ic.is_visible then
						Result := ic
					end
				end
			end
		end

	side_size (a_side: INTEGER): INTEGER
			-- The side's depth (width for left and right, height for top and bottom), as the
			-- user or `set_side_size' left it.
		require
			side: is_side (a_side)
		do
			Result := backend.dock_size (id, a_side)
		ensure
			non_negative: Result >= 0
		end

	is_collapsed (a_side: INTEGER): BOOLEAN
		require
			side: is_side (a_side)
		do
			Result := collapsed [a_side]
		end

	layout_actions: GUI_ACTIONS [TUPLE]
			-- Run after the user changed the layout: an edge dragged, a side collapsed or
			-- expanded, a tab chosen.

feature -- Element change

	add_panel (a_panel: GUI_DOCK_PANEL; a_side: INTEGER)
			-- Dock `a_panel' last on `a_side'.
		require
			gui_thread: is_gui_thread
			side: is_side (a_side)
			undocked: a_panel.dock = Void
			free_content: a_panel.content.parent = Void
			key_unique: panel_by_key (a_panel.key) = Void
		local
			l_key, l_title: C_STRING
		do
			panels.extend (a_panel)
			on_side [a_side].extend (a_panel)
			adopt (a_panel.content)
			a_panel.set_dock (Current, a_side)
			l_key := backend.to_c (a_panel.key)
			l_title := backend.to_c (a_panel.title)
			backend.dock_add (id, a_panel.content.id, a_side, l_key.item, l_title.item)
			if not a_panel.is_visible then
				backend.dock_show_panel (id, panels.count, False)
			end
		ensure
			docked: a_panel.dock = Current and a_panel.side = a_side
			last_on_side: panels_on (a_side).last = a_panel
			indexed: index_of (a_panel) = panels.count
		end

	move_panel (a_panel: GUI_DOCK_PANEL; a_side: INTEGER)
			-- Move `a_panel' to the end of `a_side'.
		require
			gui_thread: is_gui_thread
			here: a_panel.dock = Current
			side: is_side (a_side)
		do
			if a_panel.side = a_side then
				put_panel (a_panel, a_side, on_side [a_side].count)
			else
				put_panel (a_panel, a_side, on_side [a_side].count + 1)
			end
		ensure
			moved: a_panel.side = a_side and panels_on (a_side).last = a_panel
			same_index: index_of (a_panel) = old index_of (a_panel)
		end

	put_panel (a_panel: GUI_DOCK_PANEL; a_side, a_position: INTEGER)
			-- Put `a_panel' at `a_position' on `a_side' (from 1).
		require
			gui_thread: is_gui_thread
			here: a_panel.dock = Current
			side: is_side (a_side)
			position_valid: a_position >= 1 and a_position <= panels_on (a_side).count + (if a_panel.side = a_side then 0 else 1 end)
		local
			l_list: ARRAYED_LIST [GUI_DOCK_PANEL]
		do
			on_side [a_panel.side].prune_all (a_panel)
			l_list := on_side [a_side]
			if a_position > l_list.count then
				l_list.extend (a_panel)
			else
				l_list.go_i_th (a_position)
				l_list.put_left (a_panel)
			end
			a_panel.set_dock (Current, a_side)
			backend.dock_move (id, index_of (a_panel), a_side, a_position)
		ensure
			placed: a_panel.side = a_side and panels_on (a_side) [a_position] = a_panel
		end

	remove_panel (a_panel: GUI_DOCK_PANEL)
			-- Take `a_panel' out of the dock; the panels after it in `panels' move up one.
		require
			gui_thread: is_gui_thread
			here: a_panel.dock = Current
		local
			l_index: INTEGER
		do
			l_index := index_of (a_panel)
			backend.dock_remove (id, l_index)
			on_side [a_panel.side].prune_all (a_panel)
			panels.go_i_th (l_index)
			panels.remove
			children.prune_all (a_panel.content)
			a_panel.content.set_parent (Void)
			a_panel.set_dock (Void, 0)
		ensure
			gone: index_of (a_panel) = 0 and a_panel.dock = Void
			one_less: panels.count = old panels.count - 1
		end

	set_tabbed (a_side: INTEGER; a_on: BOOLEAN)
			-- Show `a_side''s panels as tabs (one at a time), or stacked.
		require
			gui_thread: is_gui_thread
			side: is_side (a_side)
		do
			tabbed [a_side] := a_on
			backend.dock_set_tabbed (id, a_side, a_on)
		ensure
			set: is_tabbed (a_side) = a_on
		end

	activate_panel (a_panel: GUI_DOCK_PANEL)
			-- Show `a_panel' on its tabbed side; no event.
		require
			gui_thread: is_gui_thread
			here: a_panel.dock = Current
			shown: a_panel.is_visible
		do
			active [a_panel.side] := a_panel
			backend.dock_activate (id, index_of (a_panel))
		ensure
			active: active_panel (a_panel.side) = a_panel
		end

	set_side_size (a_side, a_size: INTEGER)
			-- Make `a_side' `a_size' deep, as far as the center's minimum allows; no event.
		require
			gui_thread: is_gui_thread
			side: is_side (a_side)
			non_negative: a_size >= 0
		do
			backend.dock_set_size (id, a_side, a_size)
		end

	collapse_side (a_side: INTEGER)
			-- Fold `a_side' to a strip naming its panels; no event.
		require
			gui_thread: is_gui_thread
			side: is_side (a_side)
		do
			collapsed [a_side] := True
			backend.dock_collapse (id, a_side, True)
		ensure
			collapsed: is_collapsed (a_side)
		end

	expand_side (a_side: INTEGER)
			-- Open `a_side' again at the size it had; no event.
		require
			gui_thread: is_gui_thread
			side: is_side (a_side)
		do
			collapsed [a_side] := False
			auto_hidden [a_side] := False
			backend.dock_collapse (id, a_side, False)
		ensure
			opened: not is_collapsed (a_side)
			pinned: not is_auto_hide (a_side)
		end

feature -- Floating, auto-hide, the maximized center (1r-b)

	float_panel (a_panel: GUI_DOCK_PANEL)
			-- Put `a_panel' in a window of its own, keeping its side and place; no event.
		require
			gui_thread: is_gui_thread
			here: a_panel.dock = Current
		do
			if not a_panel.is_floating then
				a_panel.put_floating (True)
				backend.dock_float (id, index_of (a_panel), True)
			end
		ensure
			floating: a_panel.is_floating
			same_side: a_panel.side = old a_panel.side
		end

	redock_panel (a_panel: GUI_DOCK_PANEL)
			-- Put a floating `a_panel' back in its side and place; no event.
		require
			gui_thread: is_gui_thread
			here: a_panel.dock = Current
		do
			if a_panel.is_floating then
				a_panel.put_floating (False)
				backend.dock_float (id, index_of (a_panel), False)
			end
		ensure
			docked: not a_panel.is_floating
		end

	floating_frame (a_panel: GUI_DOCK_PANEL): TUPLE [x, y, width, height: INTEGER]
			-- Where `a_panel''s window stands (or last stood), in logical units relative to the
			-- dock's window.
		require
			here: a_panel.dock = Current
		local
			i: INTEGER
		do
			i := index_of (a_panel)
			Result := [backend.dock_float_frame_field (id, i, 1), backend.dock_float_frame_field (id, i, 2),
				backend.dock_float_frame_field (id, i, 3), backend.dock_float_frame_field (id, i, 4)]
		end

	set_floating_frame (a_panel: GUI_DOCK_PANEL; a_x, a_y, a_width, a_height: INTEGER)
			-- Stand `a_panel''s window there (now if floating, else when it floats). Wayland places
			-- no program's windows, so there only the size is taken.
		require
			gui_thread: is_gui_thread
			here: a_panel.dock = Current
			sized: a_width > 0 and a_height > 0
		do
			backend.dock_float_frame (id, index_of (a_panel), a_x, a_y, a_width, a_height)
		end

	is_auto_hide (a_side: INTEGER): BOOLEAN
		require
			side: is_side (a_side)
		do
			Result := auto_hidden [a_side]
		end

	set_auto_hide (a_side: INTEGER; a_on: BOOLEAN)
			-- Stand `a_side' as its strip, its panels sliding out over the center on a rest or a
			-- press (`a_on'), or pin it open again; no event.
		require
			gui_thread: is_gui_thread
			side: is_side (a_side)
		do
			auto_hidden [a_side] := a_on
			if a_on then
				collapsed [a_side] := False
			end
			backend.dock_set_auto_hide (id, a_side, a_on)
		ensure
			set: is_auto_hide (a_side) = a_on
			not_folded: a_on implies not is_collapsed (a_side)
		end

	is_center_maximized: BOOLEAN

	maximize_center
			-- Fold every side away, remembered, so the center takes the dock; floating panels
			-- stay floating. No event.
		require
			gui_thread: is_gui_thread
		do
			is_center_maximized := True
			backend.dock_maximize_center (id, True)
		ensure
			maximized: is_center_maximized
		end

	restore_center
			-- Give every side back its fold, auto-hide and size; no event.
		require
			gui_thread: is_gui_thread
		do
			is_center_maximized := False
			backend.dock_maximize_center (id, False)
		ensure
			restored: not is_center_maximized
		end

feature -- Layouts

	layout: STRING_32
			-- The arrangement as text: each side's size, tabs, collapse, active panel and
			-- auto-hide; each panel's side, place and visibility, by key; each floating panel's
			-- frame; whether the center is maximized.
		local
			s: INTEGER
		do
			create Result.make (200)
			Result.append ("dock 1%N")
			from s := Side_left until s > Side_bottom loop
				Result.append ("side " + s.out + "%T" + side_size (s).out + "%T" + tabbed [s].to_integer.out + "%T"
					+ collapsed [s].to_integer.out + "%T")
				if attached active [s] as al_a and then al_a.side = s then
					Result.append (al_a.key)
				end
				Result.append ("%T" + auto_hidden [s].to_integer.out)
				Result.append_character ('%N')
				across on_side [s] as ic loop
					Result.append ({STRING_32} "panel " + s.out + "%T" + ic.is_visible.to_integer.out + "%T" + ic.key + "%N")
				end
				s := s + 1
			end
			across panels as ic loop
				if ic.is_floating then
					Result.append ({STRING_32} "float " + floating_frame (ic).x.out + "%T" + floating_frame (ic).y.out + "%T"
						+ floating_frame (ic).width.out + "%T" + floating_frame (ic).height.out + "%T" + ic.key + "%N")
				end
			end
			if is_center_maximized then
				Result.append ("center maximized%N")
			end
		end

	restore_layout (a_text: READABLE_STRING_GENERAL): BOOLEAN
			-- Arrange as `a_text' (from `layout') says, and answer True; when it names a panel
			-- this dock lacks or is not a layout, change nothing and answer False. Panels it does
			-- not name keep their places, after the named ones. A 1r-a layout (no auto-hide, no
			-- floating, no center line) restores as it did. No event.
		require
			gui_thread: is_gui_thread
		local
			l_sides: ARRAY [TUPLE [size, tabs, folded: INTEGER; active: STRING_32; hidden: INTEGER]]
			l_panels: ARRAYED_LIST [TUPLE [side, shown: INTEGER; panel: GUI_DOCK_PANEL]]
			l_floats: ARRAYED_LIST [TUPLE [x, y, w, h: INTEGER; panel: GUI_DOCK_PANEL]]
			l_maximized: BOOLEAN
			l_ok: BOOLEAN
			l_fields: LIST [STRING_32]
			l_line: STRING_32
			s, l_pos: INTEGER
		do
			create l_sides.make_filled ([0, 0, 0, {STRING_32} "", 0], Side_left, Side_bottom)
			create l_panels.make (panels.count)
			create l_floats.make (2)
			l_ok := True
			across a_text.to_string_32.split ('%N') as ic loop
				l_line := ic.twin
				l_line.prune_all ('%R')
				if l_ok and not l_line.is_empty then
					if l_line.starts_with ("side ") then
						l_fields := l_line.substring (6, l_line.count).split ('%T')
						if (l_fields.count = 5 or l_fields.count = 6) and then l_fields [1].is_integer and then is_side (l_fields [1].to_integer)
							and then l_fields [2].is_integer and then l_fields [3].is_integer and then l_fields [4].is_integer
							and then (l_fields.count = 5 or else l_fields [6].is_integer)
						then
							l_sides [l_fields [1].to_integer] := [l_fields [2].to_integer.max (0), l_fields [3].to_integer,
								l_fields [4].to_integer, l_fields [5].twin, if l_fields.count = 6 then l_fields [6].to_integer else 0 end]
						else
							l_ok := False
						end
					elseif l_line.starts_with ("panel ") then
						l_fields := l_line.substring (7, l_line.count).split ('%T')
						if l_fields.count = 3 and then l_fields [1].is_integer and then is_side (l_fields [1].to_integer)
							and then l_fields [2].is_integer and then attached panel_by_key (l_fields [3]) as al_p
							and then not across l_panels as ic_seen some ic_seen.panel = al_p end
						then
							l_panels.extend ([l_fields [1].to_integer, l_fields [2].to_integer, al_p])
						else
							l_ok := False
						end
					elseif l_line.starts_with ("float ") then
						l_fields := l_line.substring (7, l_line.count).split ('%T')
						if l_fields.count = 5 and then l_fields [1].is_integer and then l_fields [2].is_integer
							and then l_fields [3].is_integer and then l_fields [4].is_integer
							and then l_fields [3].to_integer > 0 and then l_fields [4].to_integer > 0
							and then attached panel_by_key (l_fields [5]) as al_p
						then
							l_floats.extend ([l_fields [1].to_integer, l_fields [2].to_integer, l_fields [3].to_integer, l_fields [4].to_integer, al_p])
						else
							l_ok := False
						end
					elseif l_line.same_string ("center maximized") then
						l_maximized := True
					elseif not l_line.same_string ("dock 1") then
						l_ok := False
					end
				end
			end
			if l_ok then
				from s := Side_left until s > Side_bottom loop
					l_pos := 0
					across l_panels as ic loop
						if ic.side = s then
							l_pos := l_pos + 1
							put_panel (ic.panel, s, l_pos)
						end
					end
					s := s + 1
				end
				across l_panels as ic loop
					if (ic.shown = 1) /= ic.panel.is_visible then
						if ic.shown = 1 then ic.panel.show else ic.panel.hide end
					end
				end
				from s := Side_left until s > Side_bottom loop
					set_tabbed (s, l_sides [s].tabs = 1)
					if l_sides [s].size > 0 then
						set_side_size (s, l_sides [s].size)
					end
					if attached panel_by_key (l_sides [s].active) as al_a and then al_a.side = s and then al_a.is_visible then
						activate_panel (al_a)
					end
					if l_sides [s].folded = 1 then collapse_side (s) else expand_side (s) end
					set_auto_hide (s, l_sides [s].hidden = 1)
					s := s + 1
				end
				across panels as ic loop
					if not across l_floats as ic_f some ic_f.panel = ic end then
						redock_panel (ic)
					end
				end
				across l_floats as ic loop
					set_floating_frame (ic.panel, ic.x, ic.y, ic.w, ic.h)
					float_panel (ic.panel)
				end
				if l_maximized then maximize_center elseif is_center_maximized then restore_center end
			end
			Result := l_ok
		end

	save_layout (a_path: PATH)
			-- Write `layout' to the file at `a_path'.
		local
			f: PLAIN_TEXT_FILE
		do
			create f.make_with_path (a_path)
			f.open_write
			f.put_string ((create {UTF_CONVERTER}).string_32_to_utf_8_string_8 (layout))
			f.close
		end

	load_layout (a_path: PATH): BOOLEAN
			-- `restore_layout' from the file at `a_path'; False when it cannot be read.
		require
			gui_thread: is_gui_thread
		local
			f: PLAIN_TEXT_FILE
			l_text: STRING_8
		do
			create f.make_with_path (a_path)
			if f.exists and then f.is_readable then
				f.open_read
				create l_text.make (f.count)
				from f.read_stream (f.count.max (1)) until f.exhausted or f.last_string.is_empty loop
					l_text.append (f.last_string)
					f.read_stream (4096)
				end
				l_text.append (f.last_string)
				f.close
				Result := restore_layout ((create {UTF_CONVERTER}).utf_8_string_8_to_string_32 (l_text))
			end
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
			-- 35 an edge dragged (side, size), 36 a side collapsed or expanded (side, 1 or 0),
			-- 37 a tab chosen (side, the panel's index); 1r-b: 38 a panel floated or docked
			-- (index, 1 or 0), 39 auto-hide pinned or unpinned (side, 1 or 0), 40 the center
			-- maximized or restored (b), 41 a panel moved by drag (index, side, position).
		do
			inspect a_type
			when 35 then
				layout_actions.call (Void)
			when 36 then
				if is_side (a_a) then
					collapsed [a_a] := a_b = 1
					layout_actions.call (Void)
				end
			when 37 then
				if is_side (a_a) and then panels.valid_index (a_b) then
					active [a_a] := panels [a_b]
					layout_actions.call (Void)
				end
			when 38 then
				if panels.valid_index (a_a) then
					panels [a_a].put_floating (a_b = 1)
					layout_actions.call (Void)
				end
			when 39 then
				if is_side (a_a) then
					auto_hidden [a_a] := a_b = 1
					if a_b = 1 then
						collapsed [a_a] := False
					end
					layout_actions.call (Void)
				end
			when 40 then
				is_center_maximized := a_b = 1
				layout_actions.call (Void)
			when 41 then
				if panels.valid_index (a_a) and then is_side (a_b) then
					take_moved (panels [a_a], a_b, a_c)
					layout_actions.call (Void)
				end
			else
			end
		end

feature {NONE} -- Implementation

	on_side: ARRAY [ARRAYED_LIST [GUI_DOCK_PANEL]]
			-- Each side's panels, in their order on it.

	tabbed, collapsed, auto_hidden: ARRAY [BOOLEAN]

	take_moved (a_panel: GUI_DOCK_PANEL; a_side, a_position: INTEGER)
			-- The user moved `a_panel' (the backend has already): follow in the books.
		local
			l_list: ARRAYED_LIST [GUI_DOCK_PANEL]
		do
			on_side [a_panel.side].prune_all (a_panel)
			l_list := on_side [a_side]
			if a_position < 1 or a_position > l_list.count then
				l_list.extend (a_panel)
			else
				l_list.go_i_th (a_position)
				l_list.put_left (a_panel)
			end
			a_panel.set_dock (Current, a_side)
		end

	active: ARRAY [detachable GUI_DOCK_PANEL]
		attribute
			create Result.make_filled (Void, Side_left, Side_bottom)
		end

invariant
	every_panel_on_its_side: across panels as ic all on_side [ic.side].has (ic) and ic.dock = Current end
	center_is_a_child: has (center)

end
