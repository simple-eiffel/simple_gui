note
	description: "[
		simple_gui's Windows backend: the API over simple_widgets (drawn, the Cairo look) on
		simple_shell. Widgets live in an id table; their agents push simple_gui's events onto a
		queue that `next' drains, and programmatic changes stay silent (simple_widgets' setters
		already are). Windows are GUI_SW_WINDOWs: one open at a time in this first stage, opened
		step by step (simple_shell's shell_open_window and shell_turn, W1).

		Stage 1 covers the loop, windows, stacks, grids, labels, buttons, fields, check boxes,
		text areas, lists, the canvas, menus, dialogs, appearance, accessibility and the test
		doors. The splitter, tabs, table, tree and context menus come in stage 2; until then
		they fail loudly ("not yet on Windows") rather than quietly doing nothing.
	]"

class
	GUI_BACKEND

inherit
	GUI_BACKEND_API
		redefine
			scale, text_area_string
		end

	GUI_PICTURE_BYTES

feature -- Lifecycle and loop

	init (a_name, a_id: POINTER): BOOLEAN
			-- Windows always has a display. Become DPI aware first, before anything asks the
			-- desktop's scale: until then Windows answers 96 DPI, so a window and its first
			-- theme were sized at 100% on a 150% display and grew when a later theme came.
			-- Then claim the pump for this thread, so a worker's wake always has somewhere
			-- to go: before any shell window exists (a grid asks for its pictures on its
			-- first frame, while its window is composed) `SHELL_WAKE.wake' found no window
			-- and no claimed thread, answered "nobody", and the wake was lost (issue 107).
		do
			desktop.become_dpi_aware
			wake_reader.claim_pump_thread
			if not from_c (a_name).is_empty then
				app_title.put (from_c (a_name))
			end
			Result := True
		end

	is_gui_thread: BOOLEAN
		do
			Result := (create {SHELL_WAKE}).is_pump_thread
		end

	pump (a_ms: INTEGER)
			-- Run the open window's loop until an event is queued or `a_ms' pass (or the next
			-- timer is due); then fire the timers due and ask for the rows lazy tables are about
			-- to show.
		local
			l_wait: INTEGER
		do
			if is_render_due then
				changed
			end
			if events.is_empty then
				l_wait := a_ms.max (0).min (ms_to_next_timer)
				if attached open_window as al_w and then al_w.is_window_open then
					al_w.shell_turn (l_wait)
				else
					pump_windowless (l_wait)
				end
			end
			fire_due_timers
			check_pick_menu
			check_rows_wanted
		end

	pump_until_idle (a_ms: INTEGER)
			-- Dispatch what is waiting, then lay out and draw, so positions and sizes are current
			-- (the shared tests' rule 2).
		do
			is_render_due := False
			if attached open_window as al_w and then al_w.is_window_open then
				al_w.shell_turn_pending
				al_w.request_render
				apply_pending_positions
				if last_positions_moved then
					al_w.request_render
				end
				al_w.shell_turn_pending
			end
			check_rows_wanted
		end

	start_heartbeat (a_ms: INTEGER)
			-- simple_shell's window keeps its own heartbeat.
		do
		end

	wake
			-- Reach the pump from any processor (simple_shell's wake is process-wide).
		do
			(create {SHELL_WAKE}).wake
		end

	next (a_type, an_id, a_a, a_b, a_c: TYPED_POINTER [INTEGER]): BOOLEAN
			-- Hand over the oldest queued event.
		do
			if not events.is_empty then
				put_int (a_type, events.item.type)
				put_int (an_id, events.item.id)
				put_int (a_a, events.item.a)
				put_int (a_b, events.item.b)
				put_int (a_c, events.item.c)
				events.remove
				Result := True
			end
		end

feature {GUI_SW_WINDOW} -- Events

	push (a_type, an_id, a_a, a_b, a_c: INTEGER)
			-- Queue one simple_gui event.
		do
			events.extend ([a_type, an_id, a_a, a_b, a_c])
		end

feature {GUI_SW_WINDOW} -- Widget numbers (1u)

	id_of_widget (a_widget: SW_WIDGET): INTEGER
			-- `a_widget''s simple_gui id, 0 when it is not one of ours.
		local
			i: INTEGER
		do
			from i := 1 until i > items.count or Result > 0 loop
				if items.i_th (i) = a_widget then
					Result := i
				end
				i := i + 1
			end
		ensure
			in_range: 0 <= Result and Result <= items.count
		end

feature -- Windows and containers

	window (a_title: POINTER; a_width, a_height: INTEGER): INTEGER
		local
			l_w: GUI_SW_WINDOW
		do
			Result := register (Void)
			create l_w.make (Current, Result, from_c (a_title), device (a_width.max (1)), device (a_height.max (1)))
				-- the window's heartbeat and fast tick time the drawn views (1i)
			l_w.set_on_tick (agent on_window_tick)
			l_w.set_on_shell_event (agent on_window_shell_event)
			l_w.set_on_pick_cancelled (agent pick_cancelled)
			if forced_dark_set or is_high_contrast then
				wear (l_w)
			end
			windows.put (l_w, Result)
		end

	window_set_content (a_window, a_child: INTEGER)
		do
			window_content.force (a_child, a_window)
			if attached windows.item (a_window) as al_w and then al_w.is_window_open then
				compose (a_window, al_w)
			end
		end

	window_set_toolbar (a_window, a_toolbar: INTEGER)
		do
			window_toolbar.force (a_toolbar, a_window)
			if attached windows.item (a_window) as al_w and then al_w.is_window_open then
				compose (a_window, al_w)
			end
		end

	window_set_status_bar (a_window, a_bar: INTEGER)
		do
			window_status_bar.force (a_bar, a_window)
			if attached windows.item (a_window) as al_w and then al_w.is_window_open then
				compose (a_window, al_w)
			end
		end

	window_show (a_window: INTEGER)
			-- Open the window: the first as simple_shell's main window, one shown while that is
			-- open as a floating document window of it (W3).
		do
			if attached windows.item (a_window) as al_w and then not al_w.is_window_open and then not floats.has (a_window) then
				if attached open_window as al_owner and then al_owner.is_window_open then
					float_window (a_window, al_w, al_owner)
				else
					open_native (a_window, al_w)
				end
			end
		end

	window_close (a_window: INTEGER)
		do
			hidden_windows.remove (a_window)
			if attached floats.item (a_window) as al_f then
				floats.remove (a_window)
				if attached open_window as al_owner and then al_owner.floating_windows.has (al_f) then
					al_owner.unfloat (al_f)
				end
				changed
			elseif attached windows.item (a_window) as al_w and then al_w.is_window_open then
				across floats as ic loop
					if al_w.floating_windows.has (ic) then
						al_w.unfloat (ic)
					end
				end
				floats.wipe_out
				release_picture_loaders (al_w)
				al_w.close
				al_w.shell_turn_pending
			end
		end

	window_set_title (a_window: INTEGER; a_title: POINTER)
		do
			if attached windows.item (a_window) as al_w then
				al_w.set_title (from_c (a_title))
			end
		end

	window_install_shortcuts (a_window: INTEGER; a_spec: POINTER)
			-- "id=shortcut;id=shortcut": each registrable shortcut runs its menu item.
		local
			l_pair: LIST [STRING_32]
			l_shortcut: SW_SHORTCUT
		do
			if attached windows.item (a_window) as al_w then
				across from_c (a_spec).split (';') as ic loop
					l_pair := ic.split ('=')
					if l_pair.count = 2 and then l_pair.first.is_integer then
						create l_shortcut.make (l_pair.last)
						if l_shortcut.is_registrable then
							al_w.register_shortcut (l_pair.last, agent choose_menu_item (l_pair.first.to_integer))
						end
					end
				end
			end
		end

	stack (a_vertical: BOOLEAN; a_spacing: INTEGER): INTEGER
		local
			l_col: SW_COLUMN
			l_row: SW_ROW
		do
			if a_vertical then
				create l_col.make
					-- 12 clear around a stack, as GTK and AppKit keep
				l_col.set_padding (scaled (Stack_margin))
				l_col.set_gap (scaled (a_spacing))
				Result := register (l_col)
				margins.force (scaled (Stack_margin), Result)
				stack_ids.force (True, Result)
			else
				create l_row.make
				l_row.set_padding (scaled (Stack_margin))
				l_row.set_gap (scaled (a_spacing))
					-- children fill the row's height, as in a GTK box and an NSStackView
				l_row.set_cross_axis ({SW_ROW}.Cross_stretch)
				Result := register (l_row)
				margins.force (scaled (Stack_margin), Result)
				stack_ids.force (True, Result)
			end
		end

	stack_extend (a_stack, a_child: INTEGER; a_stretch: BOOLEAN)
		do
			if attached {SW_BOX_CONTAINER} widget (a_stack) as al_box and then attached widget (a_child) as al_child then
				al_box.put (al_child)
				if a_stretch then
					al_child.set_grow (1.0)
				end
				if stack_alignment.has (a_stack) then
					al_child.set_cross_alignment (stack_alignment.item (a_stack))
				elseif attached {SW_COLUMN} al_box and then attached {SW_BUTTON} al_child then
						-- GTK and AppKit keep a button at its natural width in a column
					al_child.set_cross_alignment ({SW_WIDGET}.Place_start)
				end
			end
		end

	stack_set_spacing (a_stack, a_spacing: INTEGER)
		do
			if attached {SW_BOX_CONTAINER} widget (a_stack) as al_box then
				al_box.set_gap (scaled (a_spacing))
			end
		end

	stack_set_alignment (a_stack, an_alignment: INTEGER)
			-- simple_gui's Align_fill .. Align_end are simple_widgets' Place_fill .. Place_end.
		do
			stack_alignment.force (an_alignment, a_stack)
			if attached {SW_BOX_CONTAINER} widget (a_stack) as al_box then
				across al_box.children as ic loop
					ic.set_cross_alignment (an_alignment)
				end
			end
		end

	stack_align_child (a_stack, a_child, an_alignment: INTEGER)
		do
			if attached widget (a_child) as al_child then
				al_child.set_cross_alignment (an_alignment)
			end
		end

	grid: INTEGER
		local
			l_g: SW_GRID
		do
			create l_g.make
			l_g.set_padding (scaled (Stack_margin))
			Result := register (l_g)
			margins.force (scaled (Stack_margin), Result)
		end

	Stack_margin: INTEGER = 12
			-- Logical pixels kept clear around a stack's or a grid's children, on every platform.

	grid_put (a_grid, a_child, a_row, a_column, a_rows, a_columns: INTEGER)
		do
			if attached {SW_GRID} widget (a_grid) as al_g and then attached widget (a_child) as al_child then
				al_g.put_spanning (al_child, a_row, a_column, a_rows, a_columns)
			end
		end

	grid_set_spacing (a_grid, a_row_gap, a_column_gap: INTEGER)
		do
			if attached {SW_GRID} widget (a_grid) as al_g then
				al_g.set_gaps (scaled (a_row_gap), scaled (a_column_gap))
			end
		end

	grid_set_homogeneous_columns (a_grid: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_GRID} widget (a_grid) as al_g then
				al_g.set_homogeneous_columns (a_on)
			end
		end

	grid_set_stretching_column (a_grid, a_column: INTEGER)
		do
			if attached {SW_GRID} widget (a_grid) as al_g then
				al_g.set_stretching_column (a_column.max (0))
			end
		end

	dock (a_center: INTEGER): INTEGER
			-- 1r-a: SW_DOCK_HOST around the center (its zones: west, east, south, north).
		local
			l_host: SW_DOCK_HOST
		do
			if attached widget (a_center) as al_c then
				create l_host.make (al_c)
				Result := register (l_host)
				l_host.set_on_layout_change (agent dock_layout_changed (Result))
				l_host.set_on_float_request (agent dock_float_requested (Result, ?))
				dock_seen.force (dock_state (l_host), Result)
			else
				Result := register (Void)
			end
		end

	dock_add (a_dock, a_content, a_side: INTEGER; a_key, a_title: POINTER)
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then attached widget (a_content) as al_c then
				dock_quiet := dock_quiet + 1
				al_h.add_keyed_panel (from_c (a_key), from_c (a_title), al_c, dock_zone (a_side)).do_nothing
				dock_quiet := dock_quiet - 1
				dock_settled (a_dock, al_h)
			end
		end

	dock_move (a_dock, an_index, a_side, a_position: INTEGER)
			-- At `a_position' among the zone's panels (simple_widgets keeps an order per zone).
		local
			l_zone, l_room: INTEGER
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then an_index >= 1 and then an_index <= al_h.panels.count then
				l_zone := dock_zone (a_side)
				l_room := al_h.all_panels_in (l_zone).count
				if al_h.panels.i_th (an_index).zone /= l_zone then
					l_room := l_room + 1
				end
				dock_quiet := dock_quiet + 1
				al_h.move_panel_to (an_index, l_zone, a_position.max (1).min (l_room))
				dock_quiet := dock_quiet - 1
				dock_settled (a_dock, al_h)
			end
		end

	dock_remove (a_dock, an_index: INTEGER)
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then an_index >= 1 and then an_index <= al_h.panels.count then
				dock_quiet := dock_quiet + 1
				al_h.remove_panel (an_index)
				dock_quiet := dock_quiet - 1
				dock_settled (a_dock, al_h)
			end
		end

	dock_set_title (a_dock, an_index: INTEGER; a_title: POINTER)
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then an_index >= 1 and then an_index <= al_h.panels.count then
				al_h.panels.i_th (an_index).title := from_c (a_title)
				changed
			end
		end

	dock_set_tabbed (a_dock, a_side: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h then
				dock_quiet := dock_quiet + 1
				al_h.set_tabbed (dock_zone (a_side), a_on)
				dock_quiet := dock_quiet - 1
				dock_settled (a_dock, al_h)
			end
		end

	dock_activate (a_dock, an_index: INTEGER)
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then an_index >= 1 and then an_index <= al_h.panels.count
				and then al_h.is_panel_visible (an_index)
			then
				dock_quiet := dock_quiet + 1
				al_h.activate_panel (an_index)
				dock_quiet := dock_quiet - 1
				dock_settled (a_dock, al_h)
			end
		end

	dock_set_size (a_dock, a_side, a_size: INTEGER)
			-- As a share of the host (simple_widgets sizes zones by fraction); asked before the
			-- host is laid out, it waits until it is.
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h then
				dock_wanted.force (a_size, a_dock * 8 + a_side)
				dock_apply_sizes (a_dock, al_h)
			end
		end

	dock_size (a_dock, a_side: INTEGER): INTEGER
		local
			l_zone: INTEGER
			l_extent: REAL_64
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h then
				dock_apply_sizes (a_dock, al_h)
				if dock_wanted.has (a_dock * 8 + a_side) then
					Result := dock_wanted.item (a_dock * 8 + a_side)
				else
					l_zone := dock_zone (a_side)
					if l_zone = al_h.Zone_west or l_zone = al_h.Zone_east then
						l_extent := al_h.width
					else
						l_extent := al_h.height
					end
					Result := logical (al_h, al_h.fraction (l_zone) * l_extent).max (0)
				end
			end
		end

	dock_collapse (a_dock, a_side: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h then
				dock_quiet := dock_quiet + 1
				if a_on then
					al_h.collapse_zone (dock_zone (a_side))
				else
					al_h.expand_zone (dock_zone (a_side))
				end
				dock_quiet := dock_quiet - 1
				dock_settled (a_dock, al_h)
			end
		end

	dock_show_panel (a_dock, an_index: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then an_index >= 1 and then an_index <= al_h.panels.count then
				dock_quiet := dock_quiet + 1
				if a_on then
					al_h.show_panel (an_index)
				else
					al_h.hide_panel (an_index)
				end
				dock_quiet := dock_quiet - 1
				dock_settled (a_dock, al_h)
			end
		end

	dock_float (a_dock, an_index: INTEGER; a_on: BOOLEAN)
			-- 1r-b: a floating window (SW_WINDOW's, GW-22) at the panel's frame, or back.
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then an_index >= 1 and then an_index <= al_h.panels.count then
				dock_quiet := dock_quiet + 1
				if a_on and not al_h.is_floating (an_index) then
					dock_float_now (a_dock, al_h, an_index)
				elseif not a_on and al_h.is_floating (an_index) then
					dock_redock_now (al_h, an_index)
				end
				dock_quiet := dock_quiet - 1
				dock_settled (a_dock, al_h)
			end
		end

	dock_float_frame (a_dock, an_index, a_x, a_y, a_width, a_height: INTEGER)
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then an_index >= 1 and then an_index <= al_h.panels.count then
				dock_frames.force ([a_x, a_y, a_width, a_height], al_h.panels.i_th (an_index).key)
			end
		end

	dock_float_frame_field (a_dock, an_index, a_field: INTEGER): INTEGER
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then an_index >= 1 and then an_index <= al_h.panels.count
				and then attached dock_frames.item (al_h.panels.i_th (an_index).key) as al_f
			then
				inspect a_field
				when 1 then Result := al_f.x
				when 2 then Result := al_f.y
				when 3 then Result := al_f.w
				else Result := al_f.h
				end
			end
		end

	dock_set_auto_hide (a_dock, a_side: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h then
				dock_quiet := dock_quiet + 1
				al_h.set_auto_hide (dock_zone (a_side), a_on)
				dock_quiet := dock_quiet - 1
				dock_settled (a_dock, al_h)
			end
		end

	dock_maximize_center (a_dock: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h then
				dock_quiet := dock_quiet + 1
				if a_on then al_h.maximize_center else al_h.restore_center end
				dock_quiet := dock_quiet - 1
				dock_settled (a_dock, al_h)
			end
		end

	test_float_by_user (a_dock, an_index: INTEGER)
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then an_index >= 1 and then an_index <= al_h.panels.count
				and then not al_h.is_floating (an_index)
			then
				dock_float_requested (a_dock, an_index)
			end
		end

	test_close_floating (a_dock, an_index: INTEGER)
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then an_index >= 1 and then an_index <= al_h.panels.count
				and then al_h.is_floating (an_index)
			then
				dock_float_closed (a_dock, al_h.panels.i_th (an_index).key)
			end
		end

	test_drag_panel (a_dock, an_index, a_side, a_position: INTEGER)
		do
			dock_move (a_dock, an_index, a_side, a_position)
			push (41, a_dock, an_index, a_side, a_position)
		end

	test_slide_out (a_dock, an_index: INTEGER): BOOLEAN
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then an_index >= 1 and then an_index <= al_h.panels.count
				and then al_h.is_panel_visible (an_index) and then al_h.is_auto_hide (al_h.panels.i_th (an_index).zone)
			then
				dock_quiet := dock_quiet + 1
				al_h.slide_out (an_index)
				dock_quiet := dock_quiet - 1
				dock_settled (a_dock, al_h)
				Result := al_h.slid_out_panel = an_index
			end
		end

	test_toggle_center (a_dock: INTEGER)
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h then
				dock_maximize_center (a_dock, not al_h.is_center_maximized)
				push (40, a_dock, 0, al_h.is_center_maximized.to_integer, 0)
			end
		end

	dock_set_panel_fields (a_dock, an_index: INTEGER; a_short_title, a_description, a_tab_tooltip: POINTER)
			-- 1r-c: SW_DOCK_HOST keeps them by the panel's key.
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then an_index >= 1 and then an_index <= al_h.panels.count then
				al_h.set_panel_short_title (an_index, from_c (a_short_title))
				al_h.set_panel_description (an_index, from_c (a_description))
				al_h.set_panel_tooltip (an_index, from_c (a_tab_tooltip))
				changed
			end
		end

	dock_set_panel_pill (a_dock, an_index: INTEGER; a_code: POINTER)
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then an_index >= 1 and then an_index <= al_h.panels.count then
				al_h.set_panel_pill (an_index, from_c (a_code))
				changed
			end
		end

	test_panel_tab_text (a_dock, an_index: INTEGER): POINTER
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then an_index >= 1 and then an_index <= al_h.panels.count then
				Result := c_text (al_h.tab_text (an_index))
			else
				Result := c_text ({STRING_32} "")
			end
		end

	test_panel_tab_tooltip (a_dock, an_index: INTEGER): POINTER
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then an_index >= 1 and then an_index <= al_h.panels.count then
				Result := c_text (al_h.tab_tip (an_index))
			else
				Result := c_text ({STRING_32} "")
			end
		end

	test_locate_row (an_id, a_row: INTEGER): INTEGER
			-- `row_at_point' at the middle of row `a_row''s place.
		local
			l_y, l_end: REAL_64
		do
			if attached {GUI_SW_TOKEN_FIELD} widget (an_id) as al_t then
				if a_row >= 1 and a_row <= al_t.tokens.count and a_row <= al_t.children.count then
					Result := row_at_point (an_id, al_t.chip_middle (a_row).x, al_t.chip_middle (a_row).y)
				end
			elseif attached {SW_LIST} widget (an_id) as al_list then
				l_y := al_list.y + (a_row - 1) * al_list.row_height - al_list.scroll_y + al_list.row_height / 2
				Result := row_at_point (an_id, al_list.x + al_list.width / 2, l_y)
			elseif attached {SW_TREE [INTEGER]} widget (an_id) as al_tree then
					-- the first point down the tree whose row is `a_row', then its row's middle
				from
					l_y := al_tree.y
					l_end := al_tree.y + al_tree.height
				until
					l_y > l_end or Result = a_row
				loop
					if row_at_point (an_id, al_tree.x + al_tree.width / 2, l_y) = a_row then
						Result := a_row
					end
					l_y := l_y + 2.0
				end
			end
		end

	test_drag_dock_edge (a_dock, a_side, a_size: INTEGER)
			-- As the user's drag: the size taken, and the change reported as the host reports a
			-- drag (35).
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h then
				dock_wanted.force (a_size, a_dock * 8 + a_side)
				dock_quiet := dock_quiet + 1
				dock_apply_sizes (a_dock, al_h)
				dock_quiet := dock_quiet - 1
				push (35, a_dock, a_side, dock_size (a_dock, a_side), 0)
				dock_settled (a_dock, al_h)
			end
		end

	test_press_dock_strip (a_dock, an_index: INTEGER)
			-- As a press on a name in a folded zone's strip: the zone opens showing that panel.
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then an_index >= 1 and then an_index <= al_h.panels.count
				and then al_h.is_collapsed (al_h.panels.i_th (an_index).zone)
			then
				al_h.zone_widget (al_h.panels.i_th (an_index).zone).open_at_panel (an_index)
				changed
			end
		end

	test_click_dock_tab (a_dock, an_index: INTEGER)
			-- As a click on the panel's tab.
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then an_index >= 1 and then an_index <= al_h.panels.count
				and then al_h.is_panel_visible (an_index)
			then
				al_h.activate_panel (an_index)
				changed
			end
		end

	splitter (a_vertical: BOOLEAN): INTEGER
			-- A holder column; the SW_SPLITTER goes into it once both panes are set (simple_widgets
			-- takes both at creation).
		local
			l_holder: SW_COLUMN
		do
			create l_holder.make
			l_holder.set_padding (0.0)
			l_holder.set_gap (0.0)
			Result := register (l_holder)
			splitter_info.force ([a_vertical, 0, 0, -1], Result)
		end

	splitter_set_pane (a_splitter, a_pane, a_child: INTEGER)
		local
			l_sp: SW_SPLITTER
		do
			if attached splitter_info.item (a_splitter) as al_info and then not splitters.has (a_splitter) then
				if a_pane = 1 then
					al_info.first := a_child
				else
					al_info.second := a_child
				end
				if al_info.first > 0 and al_info.second > 0 and then attached {SW_COLUMN} widget (a_splitter) as al_holder
					and then attached widget (al_info.first) as al_a and then attached widget (al_info.second) as al_b
				then
					create l_sp.make (al_a, al_b)
					l_sp.set_horizontal (al_info.vertical)
					l_sp.set_grow (1.0)
					al_holder.put (l_sp)
					splitters.force (l_sp, a_splitter)
					l_sp.set_on_collapse_change (agent splitter_collapse_told (a_splitter, ?, ?))
					if attached splitter_collapsible.item (a_splitter) as al_c then
						l_sp.set_collapsible (1, al_c [1])
						l_sp.set_collapsible (2, al_c [2])
					end
					changed
				end
			end
		end

	splitter_position (a_splitter: INTEGER): INTEGER
			-- Logical pixels from the leading edge to the divider.
		do
			apply_pending_positions
			if attached splitters.item (a_splitter) as al_sp and then splitter_extent (al_sp) > 0.0 then
				Result := logical (al_sp, splitter_extent (al_sp) * al_sp.ratio)
			elseif attached splitter_info.item (a_splitter) as al_info and then al_info.pending >= 0 then
				Result := al_info.pending
			end
		end

	splitter_set_collapsible (a_splitter, a_pane: INTEGER; a_on: BOOLEAN)
			-- 1r-c: kept until SW_SPLITTER is made (it takes both panes at once), then applied.
		local
			l_flags: ARRAY [BOOLEAN]
		do
			if a_pane = 1 or a_pane = 2 then
				if attached splitter_collapsible.item (a_splitter) as al_c then
					l_flags := al_c
				else
					create l_flags.make_filled (False, 1, 2)
					splitter_collapsible.force (l_flags, a_splitter)
				end
				l_flags [a_pane] := a_on
				if attached splitters.item (a_splitter) as al_sp then
					al_sp.set_collapsible (a_pane, a_on)
					changed
				end
			end
		end

	splitter_collapse (a_splitter, a_pane: INTEGER; a_on: BOOLEAN)
		do
			if attached splitters.item (a_splitter) as al_sp and then (a_pane = 1 or a_pane = 2) then
				if a_on and then al_sp.is_collapsible (a_pane) and then not al_sp.is_pane_collapsed (a_pane)
					and then not al_sp.is_pane_collapsed (3 - a_pane)
				then
					al_sp.collapse_pane (a_pane)
				elseif not a_on and then al_sp.is_pane_collapsed (a_pane) then
					al_sp.expand_pane (a_pane)
				end
				changed
			end
		end

	splitter_is_collapsed (a_splitter, a_pane: INTEGER): BOOLEAN
		do
			Result := attached splitters.item (a_splitter) as al_sp and then (a_pane = 1 or a_pane = 2)
				and then al_sp.is_pane_collapsed (a_pane)
		end

	test_toggle_splitter_pane (a_splitter, a_pane: INTEGER)
			-- As the divider's button: the pane toggles and the change is told (42).
		do
			if attached splitters.item (a_splitter) as al_sp and then (a_pane = 1 or a_pane = 2) then
				splitter_collapse (a_splitter, a_pane, not al_sp.is_pane_collapsed (a_pane))
				push (42, a_splitter, a_pane, al_sp.is_pane_collapsed (a_pane).to_integer, 0)
			end
		end

	splitter_collapse_told (a_splitter, a_pane: INTEGER; a_collapsed: BOOLEAN)
			-- SW_SPLITTER's notice of the user's act (its button, a double click, an opening drag).
		do
			push (42, a_splitter, a_pane, a_collapsed.to_integer, 0)
		end

	splitter_collapsible: HASH_TABLE [ARRAY [BOOLEAN], INTEGER]
		once ("OBJECT")
			create Result.make (2)
		end

	splitter_set_position (a_splitter, a_position: INTEGER)
			-- Kept until the splitter has a size, then applied (a position set before showing holds).
		do
			if attached splitter_info.item (a_splitter) as al_info then
				al_info.pending := a_position.max (0)
				apply_pending_positions
				changed
			end
		end

feature -- Controls

	label (a_text: POINTER): INTEGER
		do
			Result := register (create {SW_LABEL}.make_ui (from_c (a_text)))
		end

	label_set (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_LABEL} widget (an_id) as al_l then
				al_l.set_text (from_c (a_text))
				changed
			end
		end

	label_get (an_id: INTEGER): POINTER
		do
			if attached {SW_LABEL} widget (an_id) as al_l then
				Result := c_text (al_l.text)
			end
		end

	label_set_wrap_width (an_id, a_characters: INTEGER)
		do
			if attached {SW_LABEL} widget (an_id) as al_l then
				al_l.set_wrap_chars (a_characters.max (0))
				changed
			end
		end

	button (a_text: POINTER): INTEGER
		local
			l_b: SW_BUTTON
		do
			create l_b.make (from_c (a_text), Void)
			Result := register (l_b)
			l_b.set_on_click (agent push (1, Result, 0, 0, 0))
		end

	button_set (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_BUTTON} widget (an_id) as al_b then
				al_b.set_label (from_c (a_text))
				changed
			end
		end

	button_get (an_id: INTEGER): POINTER
		do
			if attached {SW_BUTTON} widget (an_id) as al_b then
				Result := c_text (al_b.label)
			end
		end

	field: INTEGER
		local
			l_t: SW_TEXT_BOX
		do
			create l_t.make_single_line ("")
			Result := register (l_t)
			l_t.set_on_change (agent push (2, Result, 0, 0, 0))
			l_t.set_on_activate (agent push (3, Result, 0, 0, 0))
			l_t.set_on_focus_lost (agent push (29, Result, 0, 0, 0))
		end

	field_set (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t then
				al_t.set_text (from_c (a_text))
				changed
			end
		end

	field_get (an_id: INTEGER): POINTER
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t then
				Result := c_text (al_t.text)
			end
		end

	field_set_placeholder (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t then
				al_t.set_placeholder (from_c (a_text))
				changed
			end
		end

	dropdown: INTEGER
		local
			l_d: GUI_SW_DROPDOWN
		do
			create l_d.make_dropdown
			Result := register (l_d)
			l_d.set_on_pick (agent report_row (Result, ?))
		end

	dropdown_extend (an_id: INTEGER; a_text: POINTER)
		do
			if attached {GUI_SW_DROPDOWN} widget (an_id) as al_d then
				al_d.extend_option (from_c (a_text))
				changed
			end
		end

	dropdown_wipe_out (an_id: INTEGER)
		do
			if attached {GUI_SW_DROPDOWN} widget (an_id) as al_d then
				al_d.clear_options
				changed
			end
		end

	dropdown_select (an_id, a_row: INTEGER)
		do
			if attached {GUI_SW_DROPDOWN} widget (an_id) as al_d and then a_row <= al_d.options.count then
				al_d.select_quietly (a_row)
				changed
			end
		end

	dropdown_selected (an_id: INTEGER): INTEGER
		do
			if attached {GUI_SW_DROPDOWN} widget (an_id) as al_d then
				Result := al_d.selected_index
			end
		end

	spin_box (a_min, a_max: INTEGER): INTEGER
		local
			l_s: GUI_SW_SPIN_BOX
		do
			create l_s.make (a_min, a_min, a_max, Void)
			Result := register (l_s)
			l_s.set_on_change (agent report_number (Result, ?))
		end

	spin_box_set_value (an_id, a_value: INTEGER)
		do
			if attached {GUI_SW_SPIN_BOX} widget (an_id) as al_s then
				al_s.set_value (a_value)
				changed
			end
		end

	spin_box_value (an_id: INTEGER): INTEGER
		do
			if attached {GUI_SW_SPIN_BOX} widget (an_id) as al_s then
				Result := al_s.value
			end
		end

	spin_box_set_step (an_id, a_step: INTEGER)
		do
			if attached {GUI_SW_SPIN_BOX} widget (an_id) as al_s then
				al_s.set_step (a_step)
			end
		end

	progress_bar: INTEGER
		local
			l_p: SW_PROGRESS
		do
			create l_p.make (0.0)
			Result := register (l_p)
		end

	progress_bar_set (an_id, a_percent: INTEGER)
		do
			if attached {SW_PROGRESS} widget (an_id) as al_p then
				al_p.set_fraction (a_percent / 100)
				changed
			end
		end

	progress_bar_value (an_id: INTEGER): INTEGER
		do
			if attached {SW_PROGRESS} widget (an_id) as al_p then
				Result := (al_p.fraction * 100).rounded
			end
		end

	toolbar: INTEGER
		local
			l_t: GUI_SW_TOOLBAR_ROW
		do
			create l_t.make
			l_t.set_gap (4.0)
			Result := register (l_t)
		end

	toolbar_extend (a_toolbar, a_button: INTEGER)
		do
			if attached {GUI_SW_TOOLBAR_ROW} widget (a_toolbar) as al_t and then attached widget (a_button) as al_b then
				al_t.put (al_b)
				changed
			end
		end

	toolbar_add_separator (a_toolbar: INTEGER)
		local
			l_s: SW_SEPARATOR
		do
			if attached {GUI_SW_TOOLBAR_ROW} widget (a_toolbar) as al_t then
				create l_s.make_vertical
				al_t.put (l_s)
				changed
			end
		end

	status_bar: INTEGER
		local
			l_s: SW_STATUS_BAR
		do
			create l_s.make
			Result := register (l_s)
		end

	status_bar_set_text (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_STATUS_BAR} widget (an_id) as al_s then
				al_s.set_left (from_c (a_text))
				changed
			end
		end

	status_bar_text (an_id: INTEGER): POINTER
		do
			if attached {SW_STATUS_BAR} widget (an_id) as al_s then
				Result := c_text (al_s.left_text)
			end
		end

	radio_group (a_vertical: BOOLEAN): INTEGER
		local
			l_r: SW_RADIO_GROUP
		do
			create l_r.make
			l_r.set_vertical (a_vertical)
			Result := register (l_r)
			l_r.set_on_change (agent report_choice (Result, ?))
		end

	radio_group_extend (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_RADIO_GROUP} widget (an_id) as al_r then
				al_r.add_option (from_c (a_text))
				if al_r.options.count = 1 then
					quietly (agent al_r.select_index (1))
				end
				changed
			end
		end

	radio_group_select (an_id, i: INTEGER)
		do
			if attached {SW_RADIO_GROUP} widget (an_id) as al_r and then 1 <= i and then i <= al_r.options.count then
				quietly (agent al_r.select_index (i))
				changed
			end
		end

	radio_group_selected (an_id: INTEGER): INTEGER
		do
			if attached {SW_RADIO_GROUP} widget (an_id) as al_r then
				Result := al_r.selected_index
			end
		end

	segmented: INTEGER
		local
			l_s: SW_SEGMENTED
		do
			create l_s.make
			Result := register (l_s)
			l_s.set_on_change (agent report_choice (Result, ?))
		end

	segmented_extend (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_SEGMENTED} widget (an_id) as al_s then
				al_s.add_segment (from_c (a_text))
				if al_s.segments.count = 1 then
					quietly (agent al_s.select_segment (1))
				end
				changed
			end
		end

	segmented_select (an_id, i: INTEGER)
		do
			if attached {SW_SEGMENTED} widget (an_id) as al_s and then 1 <= i and then i <= al_s.segments.count then
				quietly (agent al_s.select_segment (i))
				changed
			end
		end

	segmented_selected (an_id: INTEGER): INTEGER
		do
			if attached {SW_SEGMENTED} widget (an_id) as al_s then
				Result := al_s.selected_index
			end
		end

	slider (a_min, a_max: INTEGER; a_vertical: BOOLEAN): INTEGER
		local
			l_s: GUI_SW_SLIDER
		do
			create l_s.make_range (a_min, a_max, a_vertical)
			Result := register (l_s)
			l_s.set_on_change (agent report_slider (Result, ?))
		end

	slider_set_value (an_id, a_value: INTEGER)
		do
			if attached {GUI_SW_SLIDER} widget (an_id) as al_s then
				al_s.set_value (a_value)
				changed
			end
		end

	slider_value (an_id: INTEGER): INTEGER
		do
			if attached {GUI_SW_SLIDER} widget (an_id) as al_s then
				Result := al_s.value
			end
		end

	slider_set_step (an_id, a_step: INTEGER)
		do
			if attached {GUI_SW_SLIDER} widget (an_id) as al_s then
				al_s.set_step (a_step)
			end
		end

	switch: INTEGER
		local
			l_s: SW_SWITCH
		do
			create l_s.make ("", False, Void)
			Result := register (l_s)
			l_s.set_on_change (agent report_switch (Result))
		end

	switch_set (an_id: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_SWITCH} widget (an_id) as al_s then
				al_s.set_on (a_on)
				changed
			end
		end

	switch_is_on (an_id: INTEGER): BOOLEAN
		do
			Result := attached {SW_SWITCH} widget (an_id) as al_s and then al_s.is_on
		end

	date_picker: INTEGER
			-- Today, until set.
		local
			l_d: SW_DATE_PICKER
			l_today: SIMPLE_DATE
		do
			create l_d.make_picker
			create l_today.make_now
			l_d.set_date (l_today.year, l_today.month, l_today.day)
			Result := register (l_d)
			l_d.set_on_date_change (agent report_date (Result, ?, ?, ?))
		end

	time_picker: INTEGER
			-- The current time, until set.
		local
			l_t: SW_TIME_PICKER
			l_now: SIMPLE_TIME
		do
			create l_t.make_picker
			create l_now.make_now
			l_t.set_time (l_now.hour, l_now.minute)
			Result := register (l_t)
			l_t.set_on_time_change (agent report_time (Result, ?, ?))
		end

	date_picker_set (an_id, a_value: INTEGER)
			-- A date as y*10000 + m*100 + d, a time as h*60 + m; quiet.
		do
			if attached {SW_CALENDAR} widget (an_id) as al_c then
				al_c.select_date (a_value // 10000, a_value // 100 \\ 100, a_value \\ 100)
				changed
			elseif attached {SW_DATE_PICKER} widget (an_id) as al_d then
				quietly (agent al_d.set_date (a_value // 10000, a_value // 100 \\ 100, a_value \\ 100))
				changed
			elseif attached {SW_TIME_PICKER} widget (an_id) as al_t then
				quietly (agent al_t.set_time (a_value // 60, a_value \\ 60))
				changed
			elseif attached date_time_values.item (an_id) as al_v then
					-- 1p's date and time picker, set as a date picker: its time stays
				date_time_set (an_id, a_value, al_v.time)
			end
		end

	date_picker_value (an_id: INTEGER): INTEGER
		do
			if attached {SW_CALENDAR} widget (an_id) as al_c then
				Result := al_c.selected_year * 10000 + al_c.selected_month * 100 + al_c.selected_day
			elseif attached {SW_DATE_PICKER} widget (an_id) as al_d then
				Result := al_d.selected_year * 10000 + al_d.selected_month * 100 + al_d.selected_day
			elseif attached {SW_TIME_PICKER} widget (an_id) as al_t then
				Result := al_t.hour * 60 + al_t.minute
			elseif attached date_time_values.item (an_id) as al_v then
					-- 1p's date and time picker, read as a date picker
				Result := al_v.date
			end
		end

	color_chooser: INTEGER
			-- A swatch button that opens simple_widgets' color picker in the window's sheet.
		local
			l_c: GUI_SW_COLOR_BUTTON
		do
			create l_c.make_color (0)
			Result := register (l_c)
			l_c.set_on_request (agent pick_color (Result))
		end

	color_chooser_set (an_id, a_rgb: INTEGER)
		do
			if attached {GUI_SW_COLOR_BUTTON} widget (an_id) as al_c then
				al_c.set_rgb (a_rgb.to_natural_32)
				changed
			end
		end

	color_chooser_value (an_id: INTEGER): INTEGER
		do
			if attached {GUI_SW_COLOR_BUTTON} widget (an_id) as al_c then
				Result := al_c.rgb.to_integer_32
			end
		end

	pick_color (an_id: INTEGER)
			-- The user clicked a color chooser: the picker, waited for; a new color is reported.
		local
			l_rgb: INTEGER
		do
			if attached {GUI_SW_COLOR_BUTTON} widget (an_id) as al_c and then attached open_window as al_w then
				l_rgb := al_w.choose_color (al_c.rgb)
				if l_rgb >= 0 and then l_rgb /= al_c.rgb.to_integer_32 then
					al_c.set_rgb (l_rgb.to_natural_32)
					report_color (an_id, al_c.rgb)
					changed
				end
			end
		end

	scroll_area: INTEGER
		do
			Result := register (create {SW_SCROLL_AREA}.make (300.0))
		end

	scroll_area_set_content (an_id, a_child: INTEGER)
		do
			if attached {SW_SCROLL_AREA} widget (an_id) as al_s and then attached widget (a_child) as al_c then
				al_s.set_child (al_c)
				changed
			end
		end

	scroll_area_scroll_to (an_id, a_x, a_y: INTEGER)
			-- `a_x' and `a_y' are logical pixels; simple_widgets scrolls in device pixels.
		do
			if attached {SW_SCROLL_AREA} widget (an_id) as al_s then
				al_s.scroll_to (scaled (a_y))
				al_s.scroll_to_x (scaled (a_x))
				changed
			end
		end

	image: INTEGER
			-- An empty picture until a file or an image file's bytes are given.
		local
			l_image: SW_IMAGE
		do
			create l_image.make_from_surface (create {CAIRO_SURFACE}.make (1, 1))
				-- scaled down to fit, never enlarged (GUI_IMAGE's promise)
			l_image.set_enlarges (False)
			Result := register (l_image)
		end

	image_set_file (an_id: INTEGER; a_path: POINTER): BOOLEAN
			-- PNG, JPEG, GIF, BMP, TGA, PSD, HDR and PNM files.
		local
			l_m: MANAGED_POINTER
		do
			l_m := file_bytes (from_c (a_path))
			if attached {SW_IMAGE} widget (an_id) and then attached l_m as al_m then
				Result := image_set_bytes (an_id, al_m.item, al_m.count)
			end
		end

	decoded_file (a_path: READABLE_STRING_GENERAL): detachable CAIRO_SURFACE
			-- The picture file `a_path' on this thread, PNG through cairo else simple_stb; Void
			-- when it is missing or will not decode. The grid view uses it when it has no worker.
		do
			if attached file_bytes (a_path) as al_m then
				Result := decoded (al_m)
			end
		end

	picture_loaders: ARRAYED_LIST [GUI_PICTURE_LOADER]
			-- One per grid view; released when a window closes over the grid.
		once ("OBJECT")
			create Result.make (2)
		end

	release_picture_loaders (a_window: SW_WINDOW)
			-- Let go the workers of the grids in `a_window' (they restart on the next request).
		do
			if attached a_window.root as al_root then
				across picture_loaders as ic loop
					if ic.is_started and then is_inside (ic.grid, al_root) then
						ic.release
					end
				end
			end
		end

	image_set_bytes (an_id: INTEGER; a_bytes: POINTER; a_count: INTEGER): BOOLEAN
			-- A whole image file's bytes: PNG through cairo, anything else simple_stb reads.
		local
			l_m: MANAGED_POINTER
		do
			if attached {SW_IMAGE} widget (an_id) as al_i and then a_count > 0 then
				create l_m.make_from_pointer (a_bytes, a_count)
				if attached decoded (l_m) as al_s then
					al_i.set_surface (al_s)
					Result := True
					changed
				end
			end
		end

	decoded (a_bytes: MANAGED_POINTER): detachable CAIRO_SURFACE
			-- `a_bytes' as a picture: cairo's own PNG reader, else simple_stb's decoders (JPEG,
			-- GIF, BMP, ...) premultiplied into ARGB32. Void if neither reads it.
		require
			has_bytes: a_bytes.count > 0
		local
			l_png: CAIRO_SURFACE
			l_picture: GUI_DECODED_PICTURE
		do
			create l_png.make_from_png_data (a_bytes)
			if l_png.is_valid then
				Result := l_png
			else
				create l_picture.make_from_bytes (a_bytes)
				Result := l_picture.to_surface
			end
		end

	separator (a_vertical: BOOLEAN): INTEGER
		local
			l_s: SW_SEPARATOR
		do
			if a_vertical then
				create l_s.make_vertical
			else
				create l_s.make
			end
			Result := register (l_s)
		end

	group_box (a_title: POINTER): INTEGER
		do
			Result := register (create {SW_GROUP}.make_titled (from_c (a_title)))
		end

	group_box_set_title (an_id: INTEGER; a_title: POINTER)
		do
			if attached {SW_GROUP} widget (an_id) as al_g then
				al_g.set_title (from_c (a_title))
				changed
			end
		end

	group_box_set_content (an_id, a_child: INTEGER)
		do
			if attached {SW_GROUP} widget (an_id) as al_g and then attached widget (a_child) as al_c then
				al_g.put (al_c)
				changed
			end
		end

	expander (a_title: POINTER): INTEGER
		local
			l_e: GUI_SW_EXPANDER
		do
			create l_e.make_titled (from_c (a_title))
			Result := register (l_e)
			l_e.set_on_change (agent report_expander (Result, ?))
		end

	expander_set_title (an_id: INTEGER; a_title: POINTER)
		do
			if attached {GUI_SW_EXPANDER} widget (an_id) as al_e then
				al_e.set_title (from_c (a_title))
				changed
			end
		end

	expander_set_content (an_id, a_child: INTEGER)
		do
			if attached {GUI_SW_EXPANDER} widget (an_id) as al_e and then attached widget (a_child) as al_c then
				al_e.set_content (al_c)
				changed
			end
		end

	expander_set_expanded (an_id: INTEGER; a_on: BOOLEAN)
		do
			if attached {GUI_SW_EXPANDER} widget (an_id) as al_e then
				quietly (agent al_e.set_expanded (a_on))
				changed
			end
		end

	expander_is_expanded (an_id: INTEGER): BOOLEAN
		do
			Result := attached {GUI_SW_EXPANDER} widget (an_id) as al_e and then al_e.is_expanded
		end

	combo_box: INTEGER
		local
			l_c: GUI_SW_COMBO_BOX
		do
			create l_c.make_combo
			Result := register (l_c)
			l_c.set_on_commit (agent report_commit (Result))
		end

	combo_box_extend (an_id: INTEGER; a_text: POINTER)
		do
			if attached {GUI_SW_COMBO_BOX} widget (an_id) as al_c then
				al_c.add_option (from_c (a_text))
			end
		end

	combo_box_wipe_out (an_id: INTEGER)
		do
			if attached {GUI_SW_COMBO_BOX} widget (an_id) as al_c then
				al_c.options.wipe_out
				changed
			end
		end

	combo_box_set_text (an_id: INTEGER; a_text: POINTER)
		do
			if attached {GUI_SW_COMBO_BOX} widget (an_id) as al_c then
				al_c.set_program_text (from_c (a_text))
				changed
			end
		end

	combo_box_text (an_id: INTEGER): POINTER
		do
			if attached {GUI_SW_COMBO_BOX} widget (an_id) as al_c then
				Result := c_text (al_c.text)
			end
		end

	tree_table (a_titles: POINTER): INTEGER
			-- An SW_TREE_TABLE over node numbers: column 1 is the tree (the node's text, as in
			-- `tree'), and each further title a column whose cells the backend keeps.
		local
			l_t: SW_TREE_TABLE [INTEGER]
			l_roots: ARRAYED_LIST [INTEGER]
			l_titles: LIST [STRING_32]
			i: INTEGER
		do
			create l_t.make (150.0)
			Result := register (l_t)
			l_titles := from_c (a_titles).split ('%/31/')
			if not l_titles.is_empty then
				l_t.set_tree_title (l_titles.first)
			end
			from
				i := 2
			until
				i > l_titles.count
			loop
				l_t.add_column (create {SW_GRID_COLUMN [INTEGER]}.make (l_titles.i_th (i), 120.0, agent tree_cell (Result, ?, i)))
				i := i + 1
			end
			create l_roots.make (8)
			tree_roots.force (l_roots, Result)
			l_t.set_roots (l_roots)
			l_t.set_children (agent tree_children (Result, ?))
			l_t.set_label (agent tree_label (Result, ?))
			l_t.set_on_select (agent report_tree_select (Result, ?))
			l_t.set_on_expansion (agent report_expansion (Result, ?, ?))
		end

	tree_table_set_cell (an_id, a_node, a_column: INTEGER; a_text: POINTER)
			-- Column 1 is the node's own text.
		do
			if a_column = 1 then
				node_text.force (from_c (a_text), node_key (an_id, a_node))
			else
				node_cells.force (from_c (a_text), node_key (an_id, a_node).out + ":" + a_column.out)
			end
			changed
		end

	set_tooltip (an_id: INTEGER; a_text: POINTER)
		do
			if attached widget (an_id) as al_w then
				al_w.set_tooltip (from_c (a_text))
			end
		end

	timer_start (a_timer_id, a_ms: INTEGER; a_repeat: BOOLEAN)
			-- 1m: a deadline the pump keeps (it waits no longer than the next one).
		do
			gui_timers.force ([a_ms.max (1), a_repeat, clock.milliseconds + a_ms.max (1)], a_timer_id)
		end

	timer_stop (a_timer_id: INTEGER)
		do
			gui_timers.remove (a_timer_id)
		end

	start_frame_ticks
			-- 1x: simple_shell's frame ticks (DwmFlush-paced on a helper thread, the
			-- high-resolution timer as the fallback), each pushed as event 62.
		do
			frame_ticks.start
			is_frame_ticking := frame_ticks.last_started
			frame_value_pending := False
		end

	stop_frame_ticks
		do
			frame_ticks.stop
			is_frame_ticking := False
		end

	frame_ticks: SHELL_FRAME_TICKS
			-- simple_shell's frame ticks (event 69).
		once ("OBJECT")
			create Result
		end

	is_frame_ticking: BOOLEAN
			-- Has the clock asked for frame ticks?

	motion_reduced: BOOLEAN
			-- Windows' "Show animations in Windows" off (simple_shell, event 57).
		do
			Result := (create {SHELL_APPEARANCE}).system_reduces_motion
		end

	widget_set_opacity (an_id: INTEGER; a_opacity: REAL_64)
			-- 1x: simple_widgets paints the widget at that alpha; at 0 a hit passes to its
			-- parent.
		do
			widget_opacities.force (a_opacity, an_id)
			if is_frame_ticking then
					-- noted before `changed', which renders at once
				frame_value_pending := True
				frame_value_mark := frames_rendered_total
			end
			if attached widget (an_id) as al_w then
				al_w.set_opacity (a_opacity)
				changed
			end
		end

	widget_opacities: HASH_TABLE [REAL_64, INTEGER]
			-- The opacity each widget was given (1x).
		once ("OBJECT")
			create Result.make (4)
		end

	clipboard_text: POINTER
		do
			Result := c_text ((create {SW_CLIPBOARD}).text)
		end

	clipboard_set_text (a_text: POINTER)
		do
			(create {SW_CLIPBOARD}).set_text (from_c (a_text))
		end

	window_add_shortcut (a_window: INTEGER; a_shortcut: POINTER; a_shortcut_id: INTEGER)
			-- simple_widgets' window accelerator; remembered for the test driver.
		local
			l_spec: STRING_32
		do
			l_spec := from_c (a_shortcut)
			if attached windows.item (a_window) as al_w and then (create {SW_SHORTCUT}.make (l_spec)).is_registrable then
				al_w.register_shortcut (l_spec, agent push (25, a_window, a_shortcut_id, 0, 0))
				window_shortcuts.force (a_shortcut_id, shortcut_key (a_window, l_spec))
			end
		end

	test_press_shortcut (a_window: INTEGER; a_shortcut: POINTER)
		local
			l_spec: STRING_32
		do
			l_spec := shortcut_key (a_window, from_c (a_shortcut))
			if window_shortcuts.has (l_spec) then
				push (25, a_window, window_shortcuts.item (l_spec), 0, 0)
			end
		end

	window_set_fullscreen (a_window: INTEGER; a_on: BOOLEAN)
			-- Borderless over the whole monitor, and back to the style and place it had.
		local
			l_saved: MANAGED_POINTER
		do
			if attached windows.item (a_window) as al_w and then al_w.hwnd /= default_pointer then
				if a_on and not fullscreen_saves.has (a_window) then
					create l_saved.make (24)
					c_enter_fullscreen (al_w.hwnd, l_saved.item)
					fullscreen_saves.force (l_saved, a_window)
				elseif not a_on and then attached fullscreen_saves.item (a_window) as al_saved then
					c_leave_fullscreen (al_w.hwnd, al_saved.item)
					fullscreen_saves.remove (a_window)
				end
			end
		end

	window_is_fullscreen (a_window: INTEGER): BOOLEAN
		do
			Result := fullscreen_saves.has (a_window)
		end

	window_native_handle (a_window: INTEGER): POINTER
			-- The window's HWND.
		do
			if attached windows.item (a_window) as al_w then
				Result := al_w.hwnd
			end
		end

	follow_system_appearance
			-- Every window follows the Windows light or dark setting again.
		local
			l_was: BOOLEAN
		do
			l_was := is_dark
			forced_dark_set := False
			across windows as ic loop
				wear (ic)
			end
			if is_dark /= l_was then
				push (10, 0, is_dark.to_integer, 0, 0)
			end
		end

	list_scroll_to_row (an_id, a_row: INTEGER)
		do
			if attached {SW_LIST} widget (an_id) as al_l and then a_row >= 1 and then a_row <= al_l.row_count then
				al_l.scroll_to_row (a_row)
				changed
			end
		end

	button_set_icon (an_id: INTEGER; a_name: POINTER)
			-- 1n: the name's SW glyph before the label (`glyph_of').
		local
			l_name: STRING_32
		do
			l_name := from_c (a_name)
			if attached {SW_BUTTON} widget (an_id) as al_b then
				al_b.set_glyph (glyph_of (l_name))
				if l_name.is_empty then
					button_icons.remove (an_id)
				else
					button_icons.force (l_name, an_id)
				end
				changed
			end
		end

	button_set_style (an_id, a_style: INTEGER)
			-- SW_BUTTON's kinds: suggested is primary, destructive danger, flat quiet; a pill is
			-- a normal button with rounded ends.
		do
			if attached {SW_BUTTON} widget (an_id) as al_b then
				inspect a_style
				when 1 then al_b.set_kind ({SW_BUTTON}.Kind_primary)
				when 2 then al_b.set_kind ({SW_BUTTON}.Kind_danger)
				when 3 then al_b.set_kind ({SW_BUTTON}.Kind_quiet)
				else al_b.set_kind ({SW_BUTTON}.Kind_normal)
				end
				al_b.set_pill (a_style = 4)
				changed
			end
		end

	button_set_busy (an_id: INTEGER; a_on: BOOLEAN)
			-- The spinner turns on the windows' fast tick while any button is busy.
		do
			if attached {SW_BUTTON} widget (an_id) as al_b then
				al_b.set_busy (a_on)
				if a_on then
					busy_buttons.force (an_id, an_id)
				else
					busy_buttons.remove (an_id)
				end
				pace_fast_timer
				changed
			end
		end

	menu_set_item_icon (an_item_id: INTEGER; a_name: POINTER)
			-- Kept, and drawn as each menu is built (`build_menu').
		do
			menu_item_icons.force (glyph_of (from_c (a_name)), an_item_id)
		end

	tabs_set_page_icon (a_tabs, a_page: INTEGER; a_name: POINTER)
		do
			if attached {SW_TABS} widget (a_tabs) as al_t and then a_page >= 1 and then a_page <= al_t.labels.count then
				al_t.set_page_glyph (a_page, glyph_of (from_c (a_name)))
				changed
			end
		end

	tabs_set_page_badge (a_tabs, a_page: INTEGER; a_text: POINTER)
		do
			if attached {SW_TABS} widget (a_tabs) as al_t and then a_page >= 1 and then a_page <= al_t.labels.count then
				al_t.set_page_badge (a_page, from_c (a_text))
				changed
			end
		end

	widget_set_badge (an_id: INTEGER; a_text: POINTER; a_kind: INTEGER)
			-- Kept here and drawn by the widget's window (simple_widgets' widget badges).
		do
			inspect a_kind
			when 1 then widget_badges.force (from_c (a_text), an_id)
			when 2 then widget_badges.force ({STRING_32} "", an_id)
			else widget_badges.remove (an_id)
			end
			apply_all_pills
		end

	test_button_icon (an_id: INTEGER): POINTER
		do
			if attached button_icons.item (an_id) as al_name then
				Result := c_text (al_name)
			else
				Result := c_text ({STRING_32} "")
			end
		end

	test_badge_shown (an_id: INTEGER): POINTER
			-- What the widget's window draws for it: its text, a bullet for a dot, else empty.
		local
			l_shown: STRING_32
		do
			create l_shown.make_empty
			if attached widget (an_id) as al_w and then attached window_of (al_w) as al_win
				and then al_win.is_window_open and then attached al_win.widget_badge_text (al_w) as al_text
			then
				if al_text.is_empty then
					l_shown := {STRING_32} "%/8226/"
				else
					l_shown := al_text
				end
			end
			Result := c_text (l_shown)
		end

	spinner: INTEGER
			-- 1o: an SW_SPINNER, turned on the windows' fast tick while it spins.
		local
			l_s: SW_SPINNER
		do
			create l_s.make (20.0)
			Result := register (l_s)
		end

	spinner_set (an_id: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_SPINNER} widget (an_id) as al_s then
				al_s.set_spinning (a_on)
				if a_on then
					spinning.force (an_id, an_id)
				else
					spinning.remove (an_id)
				end
				pace_fast_timer
				changed
			end
		end

	info_bar (a_kind: INTEGER; a_message: POINTER): INTEGER
			-- An SW_INFO_BAR: the kind's mark, the message, a row of action buttons, and a close
			-- button hidden until it is closable.
		local
			l_bar: SW_INFO_BAR
			l_label: SW_LABEL
			l_actions: SW_ROW
			l_close: SW_BUTTON
		do
			create l_bar.make (a_kind.max (1).min (4))
			create l_label.make_ui (from_c (a_message))
			create l_actions.make
			create l_close.make ("", Void)
			l_close.set_glyph ({SW_PAINTER}.Glyph_close)
			l_close.set_kind ({SW_BUTTON}.Kind_quiet)
			l_close.set_visible (False)
			l_bar.put (l_label)
			l_bar.put (l_actions)
			l_bar.put (l_close)
			Result := register (l_bar)
			l_close.set_on_click (agent push (26, Result, 0, 0, 0))
			info_bars.force ([l_label, l_actions, l_close], Result)
		end

	info_bar_set (an_id, a_kind: INTEGER; a_message: POINTER)
		do
			if attached {SW_INFO_BAR} widget (an_id) as al_bar and then attached info_bars.item (an_id) as al_parts then
				al_bar.set_kind (a_kind.max (1).min (4))
				al_parts.label.set_text (from_c (a_message))
				changed
			end
		end

	info_bar_add_action (an_id: INTEGER; a_text: POINTER; a_number: INTEGER)
		local
			l_b: SW_BUTTON
		do
			if attached info_bars.item (an_id) as al_parts then
				create l_b.make (from_c (a_text), agent push (26, an_id, a_number, 0, 0))
				l_b.set_kind ({SW_BUTTON}.Kind_quiet)
				al_parts.actions.put (l_b)
				changed
			end
		end

	info_bar_set_closable (an_id: INTEGER; a_on: BOOLEAN)
		do
			if attached info_bars.item (an_id) as al_parts then
				al_parts.close.set_visible (a_on)
				changed
			end
		end

	window_show_toast (a_window: INTEGER; a_message, an_action_text: POINTER; a_toast_id: INTEGER)
			-- SW_WINDOW's notices; an action pushes event 27.
		local
			l_action: STRING_32
		do
			if attached windows.item (a_window) as al_w then
				l_action := from_c (an_action_text)
				if a_toast_id > 0 and not l_action.is_empty then
					al_w.toast_with_action (from_c (a_message), 1, l_action, agent push (27, a_window, a_toast_id, 0, 0))
				else
					al_w.toast (from_c (a_message), 1)
				end
				if al_w.is_window_open then
					al_w.request_render
				end
			end
		end

	notify (a_title, a_body: POINTER; a_notification_id: INTEGER)
			-- A balloon from the program's notification-area icon (made on the first notice);
			-- simple_shell reports a click on it, which becomes event 28.
		local
			l_title, l_body: STRING_32
		do
			if not attached notify_tray.item then
				notify_tray.put (create {SHELL_TRAY}.make (app_title.item.head ({SHELL_TRAY}.Tooltip_maximum)))
			end
			if attached notify_tray.item as al_tray and then al_tray.is_installed then
				l_title := from_c (a_title).head ({SHELL_TRAY}.Title_maximum)
				l_body := from_c (a_body).head ({SHELL_TRAY}.Body_maximum)
				if not l_title.is_empty then
					al_tray.balloon (l_title, l_body)
					last_notification_id := a_notification_id
				end
			end
		end

	test_info_bar_press (an_id, a_number: INTEGER)
		local
			l_i: INTEGER
		do
			if attached info_bars.item (an_id) as al_parts then
				if a_number = 0 then
					al_parts.close.perform_click
				else
					across al_parts.actions.children as ic loop
						l_i := l_i + 1
						if l_i = a_number then
							ic.perform_click
						end
					end
				end
				changed
			end
		end

	test_toast_shown (a_window: INTEGER): POINTER
		do
			if attached windows.item (a_window) as al_w and then not al_w.toasts.is_empty then
				Result := c_text (al_w.toasts.last.txt)
			else
				Result := c_text ({STRING_32} "")
			end
		end

	test_toast_press (a_window: INTEGER)
			-- What a click on the notice's action does: the notice goes, the action runs.
		local
			l_toast: detachable TUPLE [txt: STRING_32; tkind: INTEGER; life: INTEGER; act_label: STRING_32; act: detachable PROCEDURE]
		do
			if attached windows.item (a_window) as al_w then
				across al_w.toasts as ic loop
					if ic.act /= Void then
						l_toast := ic
					end
				end
				if attached l_toast as al_t and then attached al_t.act as al_act then
					al_w.toasts.prune_all (al_t)
					al_act.call
				end
			end
		end

	password_field: INTEGER
			-- 1p: a masked SW_TEXT_BOX with its eye (12, a = 1 shown) and editing ended (29).
		local
			l_t: SW_TEXT_BOX
		do
			create l_t.make_password ("")
			Result := register (l_t)
			l_t.set_on_change (agent push (2, Result, 0, 0, 0))
			l_t.set_on_activate (agent push (3, Result, 0, 0, 0))
			l_t.set_on_focus_lost (agent push (29, Result, 0, 0, 0))
			l_t.set_on_reveal (agent report_reveal (Result, ?))
		end

	password_set_revealed (an_id: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t and then al_t.is_masked then
				al_t.set_revealed (a_on)
				changed
			end
		end

	password_is_revealed (an_id: INTEGER): BOOLEAN
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t then
				Result := al_t.is_revealed
			end
		end

	caps_lock_on: BOOLEAN
		do
			Result := c_caps_lock_on /= 0
		end

	field_set_error (an_id: INTEGER; a_message: POINTER)
			-- The danger look, and the message as a note under the field (kept, and drawn by its
			-- window once it is in one).
		local
			l_message: STRING_32
		do
			l_message := from_c (a_message)
			if attached {SW_TEXT_BOX} widget (an_id) as al_t then
				al_t.set_invalid (not l_message.is_empty)
			end
			if l_message.is_empty then
				field_errors.remove (an_id)
			else
				field_errors.force (l_message, an_id)
			end
			if attached widget (an_id) as al_w and then attached window_of (al_w) as al_win then
				al_win.set_widget_note (al_w, l_message)
				if al_win.is_window_open then
					al_win.request_render
				end
			end
		end

	field_error_shown (an_id: INTEGER): POINTER
		local
			l_shown: STRING_32
		do
			create l_shown.make_empty
			if attached widget (an_id) as al_w and then attached window_of (al_w) as al_win
				and then attached al_win.widget_note_text (al_w) as al_note
			then
				l_shown := al_note
			end
			Result := c_text (l_shown)
		end

	field_set_suggestions (an_id: INTEGER; a_joined: POINTER)
			-- SW_WINDOW's suggestion list under the field; a choice fills the field (2).
		local
			l_items: LIST [STRING_32]
			l_kept: ARRAYED_LIST [STRING_32]
		do
			l_items := from_c (a_joined).split ('%/31/')
			create l_kept.make (l_items.count)
			across l_items as ic loop
				if not ic.is_empty then
					l_kept.extend (ic)
				end
			end
			field_suggestions.force (l_kept, an_id)
			if attached widget (an_id) as al_w and then attached window_of (al_w) as al_win then
				if l_kept.is_empty then
					if al_win.suggestions_for = al_w then
						al_win.hide_suggestions
					end
				else
					al_win.show_suggestions (al_w, l_kept, agent fill_suggestion (an_id, ?))
				end
				if al_win.is_window_open then
					al_win.request_render
				end
			end
		end

	dropdown_add_header (an_id: INTEGER; a_text: POINTER)
		do
			if attached {GUI_SW_DROPDOWN} widget (an_id) as al_d then
				al_d.add_header (from_c (a_text))
			end
		end

	dropdown_add_separator (an_id: INTEGER)
		do
			if attached {GUI_SW_DROPDOWN} widget (an_id) as al_d then
				al_d.add_separator_row
			end
		end

	date_time_picker (a_kind: INTEGER): INTEGER
			-- 2: an SW_DATE_PICKER and an SW_TIME_PICKER in a row (2, a = date, b = time);
			-- 3: a month dropdown and a year spin box in a row (2, a = y*100+m).
		local
			l_row: SW_ROW
			l_date: SW_DATE_PICKER
			l_time: SW_TIME_PICKER
			l_month: GUI_SW_DROPDOWN
			l_year: GUI_SW_SPIN_BOX
			l_now: SIMPLE_DATE
			l_clock: SIMPLE_TIME
			i: INTEGER
		do
			create l_now.make_now
			create l_clock.make_now
			create l_row.make
			Result := register (l_row)
			if a_kind = 3 then
				create l_month.make_dropdown
				from i := 1 until i > 12 loop
					l_month.extend_option (month_name (i))
					i := i + 1
				end
				l_month.set_accessible_name ("Month")
				create l_year.make (l_now.year, 1, 9999, Void)
				l_year.set_accessible_name ("Year")
				l_row.put (l_month)
				l_row.put (l_year)
				date_time_parts.force ([l_month, l_year], Result)
				date_time_values.force ([l_now.year * 10000 + l_now.month * 100 + 1, 0], Result)
				quietly (agent l_month.select_quietly (l_now.month))
				l_month.set_on_pick (agent month_picked (Result, ?))
				l_year.set_on_change (agent year_changed (Result, ?))
			else
				create l_date.make_picker
				l_date.set_date (l_now.year, l_now.month, l_now.day)
				create l_time.make_picker
				l_time.set_time (l_clock.hour, l_clock.minute)
				l_row.put (l_date)
				l_row.put (l_time)
				date_time_parts.force ([l_date, l_time], Result)
				date_time_values.force ([l_now.year * 10000 + l_now.month * 100 + l_now.day, l_clock.hour * 60 + l_clock.minute], Result)
				l_date.set_on_date_change (agent date_part_changed (Result, ?, ?, ?))
				l_time.set_on_time_change (agent time_part_changed (Result, ?, ?))
			end
		end

	date_time_set (an_id, a_date, a_time: INTEGER)
		do
			if attached date_time_values.item (an_id) as al_v and then attached date_time_parts.item (an_id) as al_p then
				al_v.date := a_date
				al_v.time := a_time
				if attached {GUI_SW_DROPDOWN} al_p.first as al_month and then attached {GUI_SW_SPIN_BOX} al_p.second as al_year then
					quietly (agent al_month.select_quietly ((a_date // 100 \\ 100).max (1).min (12)))
					quietly (agent al_year.set_value (a_date // 10000))
				elseif attached {SW_DATE_PICKER} al_p.first as al_date and then attached {SW_TIME_PICKER} al_p.second as al_time then
					quietly (agent al_date.set_date (a_date // 10000, a_date // 100 \\ 100, a_date \\ 100))
					quietly (agent al_time.set_time (a_time // 60, a_time \\ 60))
				end
				changed
			end
		end

	date_time_date (an_id: INTEGER): INTEGER
		do
			if attached date_time_values.item (an_id) as al_v then
				Result := al_v.date
			end
		end

	date_time_time (an_id: INTEGER): INTEGER
		do
			if attached date_time_values.item (an_id) as al_v then
				Result := al_v.time
			end
		end

	range_slider (a_min, a_max: INTEGER): INTEGER
			-- Two GUI_SW_SLIDERs, Minimum over Maximum, kept in order (2, a = low, b = high).
		local
			l_column: SW_COLUMN
			l_low, l_high: GUI_SW_SLIDER
		do
			create l_column.make
			Result := register (l_column)
			create l_low.make_range (a_min, a_max, False)
			create l_high.make_range (a_min, a_max, False)
			l_low.set_accessible_name ("Minimum")
			l_high.set_accessible_name ("Maximum")
			quietly (agent l_low.set_value (a_min))
			quietly (agent l_high.set_value (a_max))
			l_column.put (l_low)
			l_column.put (l_high)
			range_parts.force ([l_low, l_high], Result)
			l_low.set_on_change (agent range_moved (Result, True, ?))
			l_high.set_on_change (agent range_moved (Result, False, ?))
		end

	range_slider_set (an_id, a_low, a_high: INTEGER)
		do
			if attached range_parts.item (an_id) as al_p then
				quietly (agent (al_p.low).set_value (a_low))
				quietly (agent (al_p.high).set_value (a_high))
				changed
			end
		end

	range_slider_low (an_id: INTEGER): INTEGER
		do
			if attached range_parts.item (an_id) as al_p then
				Result := al_p.low.value
			end
		end

	range_slider_high (an_id: INTEGER): INTEGER
		do
			if attached range_parts.item (an_id) as al_p then
				Result := al_p.high.value
			end
		end

	range_slider_set_step (an_id, a_step: INTEGER)
		do
			if attached range_parts.item (an_id) as al_p then
				al_p.low.set_step (a_step)
				al_p.high.set_step (a_step)
			end
		end

	list_set_multiple (an_id: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l then
				al_l.set_multiple (a_on)
				changed
			end
		end

	list_selected_count (an_id: INTEGER): INTEGER
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l then
				Result := al_l.selected_rows.count
			end
		end

	list_selected_at (an_id, i: INTEGER): INTEGER
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l and then al_l.selected_rows.valid_index (i) then
				Result := al_l.selected_rows [i]
			end
		end

	test_toggle_reveal (an_id: INTEGER)
			-- What a click on the eye does.
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t and then al_t.is_masked then
				al_t.toggle_reveal
				report_reveal (an_id, al_t.is_revealed)
				changed
			end
		end

	test_pick_suggestion (an_id, i: INTEGER)
		do
			if attached widget (an_id) as al_w and then attached window_of (al_w) as al_win
				and then al_win.suggestions_for = al_w and then i >= 1 and then i <= al_win.suggestions.count
			then
				al_win.choose_suggestion (i)
			else
				fill_suggestion (an_id, i)
			end
		end

	test_end_editing (an_id: INTEGER)
		do
			push (29, an_id, 0, 0, 0)
		end

	test_set_date_time (an_id, a_date, a_time: INTEGER)
		do
			date_time_set (an_id, a_date, a_time)
			if attached date_time_parts.item (an_id) as al_p and then attached {GUI_SW_DROPDOWN} al_p.first then
				push (2, an_id, a_date // 100, 0, 0)
			else
				push (2, an_id, a_date, a_time, 0)
			end
		end

	test_slide_range (an_id, a_low, a_high: INTEGER)
			-- As dragging each thumb in turn.
		do
			if attached range_parts.item (an_id) as al_p then
				al_p.low.set_value (a_low)
				range_moved (an_id, True, a_low)
				al_p.high.set_value (a_high)
				range_moved (an_id, False, a_high)
				changed
			end
		end

	test_extend_list_selection (an_id, a_row: INTEGER)
		do
			if attached {SW_GRID_VIEW} widget (an_id) as al_g and then al_g.is_multiple and then al_g.is_shown (a_row) then
				al_g.press_item (a_row, True)
				changed
			elseif attached {SW_TEXT_LIST} widget (an_id) as al_l and then al_l.is_multiple
				and then a_row >= 1 and then a_row <= al_l.row_count
			then
				al_l.extend_selection (a_row)
				changed
			end
		end

	widget_set_pick (an_id, a_mode: INTEGER; a_is_source, a_by_row: BOOLEAN)
			-- 1q: SW's pick gestures on the widget (a drag, or a secondary click for the click
			-- and menu modes), its pebble a token answered by `pick_started'.
		do
			pick_modes.force (a_mode, an_id)
			if attached widget (an_id) as al_w then
				al_w.set_pick_gestures (a_is_source and a_mode = 1, a_is_source and a_mode >= 2)
				if a_is_source then
					al_w.set_pebble_hook (agent pick_started (an_id, a_mode, a_by_row, ?, ?))
				else
					al_w.set_pebble_hook (Void)
				end
			end
		end

	widget_set_drop_target (an_id: INTEGER; an_internal, a_files, a_text: BOOLEAN)
			-- The widget takes the pick token only while Eiffel has named it (`pick_ok'); files
			-- from Explorer arrive through SW's files hook (1q-b), text from other programs
			-- through its text hook, the window taking text by OLE (simple_shell 1.40.0) while
			-- any widget does.
		do
			if attached widget (an_id) as al_w then
				if an_internal then
					al_w.set_drop_hooks (agent pick_accepts (an_id, ?, ?, ?), agent pick_received (an_id, ?, ?, ?))
				end
				if a_files then
					al_w.set_files_hook (agent outside_files (an_id, ?))
				else
					al_w.set_files_hook (Void)
				end
				if a_text then
					al_w.set_text_drop_hook (agent outside_text (an_id, ?))
				else
					al_w.set_text_drop_hook (Void)
				end
			end
			if a_files then
				takes_outside.force (1 | (takes_outside.item (an_id) & 2), an_id)
			else
				takes_outside.force (takes_outside.item (an_id) & 2, an_id)
			end
			if a_text then
				takes_outside.force (takes_outside.item (an_id) | 2, an_id)
			else
				takes_outside.force (takes_outside.item (an_id) & 1, an_id)
			end
			tell_window_takes_text
		end

	tell_window_takes_text
			-- The open window takes text from other programs while any widget does.
		local
			l_any: BOOLEAN
		do
			across takes_outside as ic until l_any loop
				l_any := ic & 2 /= 0
			end
			if attached open_window as al_w and then al_w.is_window_open and then al_w.accepts_text /= l_any then
				al_w.set_accepts_text (l_any)
			end
		end

	outside_text (an_id: INTEGER; a_text: STRING_32)
			-- Text from another program landed on widget `an_id' (SW's text hook).
		do
			dropped_text.force (a_text, an_id)
			push (33, an_id, 2, 0, 0)
		end

	drag_out_ended (an_id, a_how: INTEGER)
			-- SW's drag out of widget `an_id' ended: 34 unless it landed on one of our windows.
		do
			if a_how /= {SHELL_WINDOW}.Drag_landed_here then
				push (34, an_id, a_how, 0, 0)
			end
		end

	take_dropped_paths (an_id: INTEGER): POINTER
			-- 1q-b: kept until the next drop.
		do
			if attached dropped_paths.item (an_id) as al_p then
				Result := c_text (al_p)
			else
				Result := c_text ({STRING_32} "")
			end
		end

	take_dropped_text (an_id: INTEGER): POINTER
		do
			if attached dropped_text.item (an_id) as al_t then
				Result := c_text (al_t)
			else
				Result := c_text ({STRING_32} "")
			end
		end

	test_drop_files (an_id: INTEGER; a_paths: POINTER)
		do
			if takes_outside.item (an_id) & 1 /= 0 then
				dropped_paths.force (from_c (a_paths), an_id)
				push (33, an_id, 1, 0, 0)
			end
		end

	test_drop_text (an_id: INTEGER; a_text: POINTER)
			-- Through the window's real OLE drop target when it is open (simple_shell's
			-- `simulate_drag_in' at the widget's middle), else straight to event 33.
		do
			if takes_outside.item (an_id) & 2 /= 0 then
				if attached widget (an_id) as al_w and then attached open_window as al_win
					and then al_win.is_window_open and then al_win.accepts_text
				then
					al_win.simulate_drag_in ((al_w.x + al_w.width / 2.0).truncated_to_integer,
						(al_w.y + al_w.height / 2.0).truncated_to_integer, from_c (a_text), {STRING_32} "")
				else
					dropped_text.force (from_c (a_text), an_id)
					push (33, an_id, 2, 0, 0)
				end
			end
		end

	widget_set_drag_out (an_id: INTEGER; a_text, a_paths: POINTER)
			-- 1q-c: kept here; the drag itself is OLE DoDragDrop through simple_shell.
		local
			l_text, l_paths: STRING_32
		do
			l_text := from_c (a_text)
			l_paths := from_c (a_paths)
			if l_text.is_empty and l_paths.is_empty then
				drag_out_data.remove (an_id)
			else
				drag_out_data.force ([l_text, l_paths], an_id)
			end
			if attached widget (an_id) as al_w then
				al_w.set_drag_out (l_text, l_paths)
				al_w.set_drag_out_ended_hook (agent drag_out_ended (an_id, ?))
			end
		end

	test_drag_out (an_id: INTEGER): POINTER
		do
			if attached drag_out_data.item (an_id) as al_d then
				Result := c_text (al_d.text + {STRING_32} "%N" + al_d.paths)
			else
				Result := c_text ({STRING_32} "")
			end
		end

	test_drag_out_ended (an_id, a_how: INTEGER)
		do
			if drag_out_data.has (an_id) then
				push (34, an_id, a_how, 0, 0)
			end
		end

	drag_out_data: HASH_TABLE [TUPLE [text, paths: STRING_32], INTEGER]
			-- What a drag out of each widget carries: text, and paths newline-separated.
		once ("OBJECT")
			create Result.make (2)
		end

	takes_outside: HASH_TABLE [INTEGER, INTEGER]
			-- What each widget takes from other programs: 1 files, 2 text.
		once ("OBJECT")
			create Result.make (4)
		end

	dropped_paths: HASH_TABLE [STRING_32, INTEGER]
			-- The files dropped on each widget last, newline-separated.
		once ("OBJECT")
			create Result.make (2)
		end

	dropped_text: HASH_TABLE [STRING_32, INTEGER]
		once ("OBJECT")
			create Result.make (2)
		end

	outside_files (an_id: INTEGER; a_paths: ARRAYED_LIST [STRING_32])
			-- Files from Explorer landed on widget `an_id' (SW's files hook).
		local
			l_joined: STRING_32
		do
			create l_joined.make (64)
			across a_paths as ic loop
				if not l_joined.is_empty then
					l_joined.append_character ('%N')
				end
				l_joined.append (ic)
			end
			dropped_paths.force (l_joined, an_id)
			push (33, an_id, 1, 0, 0)
		end

	pick_targets (a_source: INTEGER; a_ids: POINTER; a_count: INTEGER; a_labels: POINTER)
		local
			l_ids: MANAGED_POINTER
			l_labels: LIST [STRING_32]
			l_menu: SW_MENU
			i: INTEGER
		do
			if pick_source = a_source then
				pick_ok.wipe_out
					-- the shared side always passes a buffer of at least one INTEGER_32
				create l_ids.share_from_pointer (a_ids, a_count.max (1) * 4)
				from i := 0 until i >= a_count loop
					pick_ok.force (l_ids.read_integer_32 (i * 4), l_ids.read_integer_32 (i * 4))
					i := i + 1
				end
				if pick_mode = 3 and then attached widget (a_source) as al_src and then attached window_of (al_src) as al_win then
						-- a menu of the targets in place of the line
					al_win.cancel_pick_quietly
					l_labels := from_c (a_labels).split ('%N')
					create l_menu.make
					from i := 1 until i > a_count loop
						l_menu.add_item (if l_labels.valid_index (i) and then not l_labels [i].is_empty then l_labels [i] else {STRING_32} "?" end,
							"", True, agent pick_chosen (l_ids.read_integer_32 ((i - 1) * 4)))
						i := i + 1
					end
					pick_menu_window := al_win
					al_win.open_menu_at (l_menu, al_win.last_pointer_x, al_win.last_pointer_y)
				end
				changed
			end
		end

	pick_cancel
		do
			if attached widget (pick_source) as al_src and then attached window_of (al_src) as al_win then
				al_win.cancel_pick_quietly
			end
			pick_clear
		end

	test_pick (a_source, a_row: INTEGER)
		do
			pick_begin (a_source, pick_modes.item (a_source).max (1), a_row)
		end

	test_drop (a_target, a_row: INTEGER)
		do
			if pick_source > 0 then
				if pick_ok.has (a_target) then
					push (31, a_target, a_row, 0, 0)
				else
					push (32, pick_source, 0, 0, 0)
				end
				pick_cancel
			end
		end

	test_cancel_pick
		do
			if pick_source > 0 then
				push (32, pick_source, 0, 0, 0)
				pick_cancel
			end
		end

	test_is_accepting (a_target: INTEGER): BOOLEAN
			-- Through the widget's own hook, as SW asks it during a pick.
		do
			if attached widget (a_target) as al_w then
				Result := pick_source > 0 and then al_w.accepts_pebble_at (pick_token, al_w.x + 1.0, al_w.y + 1.0)
			end
		end

	pill_set (an_id: INTEGER; a_code, a_tip: POINTER; a_corner: INTEGER)
			-- 1l: kept here, drawn as the window's reference marks (simple_widgets' pills).
		do
			pills.force ([from_c (a_code), from_c (a_tip), a_corner.max (1).min (4)], an_id)
			apply_all_pills
		end

	pill_clear (an_id: INTEGER)
		do
			pills.remove (an_id)
			apply_all_pills
		end

	pills_show (a_shown: BOOLEAN)
		do
			pills_are_shown := a_shown
			apply_all_pills
		end

	pill_tip_shown (an_id: INTEGER): POINTER
			-- The tip, while the pills show, its widget is in an open window, and that window
			-- wears the mark; else empty.
		local
			l_tip: STRING_32
		do
			create l_tip.make_empty
			if pills_are_shown and then attached pills.item (an_id) as al_pill
				and then attached widget (an_id) as al_w and then attached window_of (al_w) as al_win
				and then al_win.is_window_open and then al_win.reference_marks_shown
				and then across al_win.reference_marks as ic some ic.widget = al_w end
			then
				l_tip := al_pill.tip
			end
			Result := c_text (l_tip)
		end

	save_file_named (a_window: INTEGER; a_title, an_extensions, a_name: POINTER): POINTER
			-- The system's own Save dialog (simple_shell: IFileSaveDialog), owned by the window,
			-- suggesting `a_name' (2026-11-11: it replaced simple_widgets' drawn sheet, which
			-- overflowed a small window and left Save and Cancel out of reach).
		local
			l_dialog: SHELL_FILE_DIALOG
		do
			create l_dialog.make
			arm_dialog_cancel
			l_dialog.choose_save_file (window_native_handle (a_window), from_c (a_title), file_filter (from_c (an_extensions)), working_folder, from_c (a_name))
			if l_dialog.has_choice then
				Result := c_text (l_dialog.chosen_path)
			end
		end

	open_dialog_answer (a_title, a_extensions: READABLE_STRING_32): detachable STRING_32
			-- The system's own Open dialog (simple_shell), or Void when cancelled.
		local
			l_dialog: SHELL_FILE_DIALOG
		do
			create l_dialog.make
			arm_dialog_cancel
			l_dialog.choose_file (if a_title.is_empty then {STRING_32} "Open" else a_title end, file_filter (a_extensions), working_folder)
			if l_dialog.has_choice then
				Result := l_dialog.chosen_path
			end
		end

	choose_folder (a_window: INTEGER; a_title: POINTER): POINTER
			-- The system's own folder dialog (simple_shell: IFileOpenDialog picking folders).
		local
			l_dialog: SHELL_FILE_DIALOG
		do
			create l_dialog.make
			arm_dialog_cancel
			l_dialog.choose_folder (window_native_handle (a_window), from_c (a_title), working_folder)
			if l_dialog.has_choice then
				Result := c_text (l_dialog.chosen_path)
			end
		end

	file_filter (a_extensions: READABLE_STRING_32): STRING_32
			-- `a_extensions' ("pdf;txt"; empty: any file) as a dialog filter:
			-- "Files (*.pdf;*.txt)|*.pdf;*.txt|All files|*.*".
		local
			l_patterns: STRING_32
		do
			create l_patterns.make_empty
			across a_extensions.split (';') as ic loop
				if not ic.is_empty then
					if not l_patterns.is_empty then
						l_patterns.append_character (';')
					end
					l_patterns.append ({STRING_32} "*." + ic)
				end
			end
			if l_patterns.is_empty then
				Result := {STRING_32} "All files|*.*"
			else
				Result := {STRING_32} "Files (" + l_patterns + ")|" + l_patterns + "|All files|*.*"
			end
		ensure
			paired: Result.has ('|')
		end

	arm_dialog_cancel
			-- Tests (`test_auto_cancel_dialogs'): cancel the system dialog about to open, as GTK's
			-- timer does for its own; nothing when the tests have not asked.
		do
			if auto_cancel_ms > 0 then
				c_cancel_dialog_after (auto_cancel_ms)
			end
		end

	c_cancel_dialog_after (a_ms: INTEGER)
			-- A thread waits for this process's next system dialog (class #32770) and presses
			-- Cancel on it `a_ms' milliseconds after it appears.
		external "C inline use %"simple_gui_win_dialog_cancel.h%""
		alias "sgw_cancel_dialog_after ($a_ms);"
		end

	working_folder: STRING_32
			-- Where the file dialogs start: the program's working folder.
		do
			Result := (create {EXECUTION_ENVIRONMENT}).current_working_path.name.to_string_32
		end

	ask (a_window: INTEGER; a_title, a_text: POINTER): INTEGER
			-- 1 yes, 2 no, 0 cancel.
		do
			if attached windows.item (a_window) as al_w then
				Result := al_w.ask_three (from_c (a_title), from_c (a_text))
			end
		end

	calendar: INTEGER
			-- Today, until set.
		local
			l_c: SW_CALENDAR
			l_today: SIMPLE_DATE
		do
			create l_c.make
			create l_today.make_now
			l_c.select_date (l_today.year, l_today.month, l_today.day)
			Result := register (l_c)
			l_c.set_on_pick (agent report_date (Result, ?, ?, ?))
		end

	menu_button (a_text: POINTER; a_split: BOOLEAN): INTEGER
		local
			l_m: GUI_SW_MENU_BUTTON
			l_s: GUI_SW_SPLIT_BUTTON
		do
			if a_split then
				create l_s.make_split (from_c (a_text))
				Result := register (l_s)
				l_s.main_part.set_on_click (agent push (1, Result, 0, 0, 0))
			else
				create l_m.make_menu (from_c (a_text))
				Result := register (l_m)
			end
		end

	menu_button_set_menu (an_id: INTEGER; a_menu: POINTER)
		local
			l_index: INTEGER
		do
			l_index := menu_index (a_menu)
			if attached {GUI_SW_SPLIT_BUTTON} widget (an_id) as al_s then
				al_s.arrow.set_filler (agent fill_context (?, 0.0, 0.0, l_index))
			elseif attached {GUI_SW_MENU_BUTTON} widget (an_id) as al_m then
				al_m.set_filler (agent fill_context (?, 0.0, 0.0, l_index))
			end
		end

	level_bar (a_min, a_max: INTEGER): INTEGER
		do
			Result := register (create {GUI_SW_LEVEL_BAR}.make_range (a_min, a_max))
		end

	level_bar_set (an_id, a_value: INTEGER)
		do
			if attached {GUI_SW_LEVEL_BAR} widget (an_id) as al_l then
				al_l.set_value (a_value)
				changed
			end
		end

	level_bar_value (an_id: INTEGER): INTEGER
		do
			if attached {GUI_SW_LEVEL_BAR} widget (an_id) as al_l then
				Result := al_l.value
			end
		end

	level_bar_set_warning (an_id, a_value: INTEGER)
		do
			if attached {GUI_SW_LEVEL_BAR} widget (an_id) as al_l then
				al_l.set_warning (a_value)
				changed
			end
		end

	level_bar_set_critical (an_id, a_value: INTEGER)
		do
			if attached {GUI_SW_LEVEL_BAR} widget (an_id) as al_l then
				al_l.set_critical (a_value)
				changed
			end
		end

	popover: INTEGER
		do
			Result := register (create {GUI_SW_POPOVER_PANEL}.make)
		end

	popover_set_content (an_id, a_child: INTEGER)
		do
			if attached {GUI_SW_POPOVER_PANEL} widget (an_id) as al_p and then attached widget (a_child) as al_c then
				al_p.set_content (al_c)
				changed
			end
		end

	popover_show_at (an_id, an_anchor: INTEGER)
			-- Under the anchor, on the window's sheet layer.
		do
			if attached {GUI_SW_POPOVER_PANEL} widget (an_id) as al_p and then attached widget (an_anchor) as al_a
				and then attached open_window as al_w
			then
				al_w.show_popover_panel (al_p, an_id, al_a.x, al_a.y + al_a.height)
				changed
			end
		end

	popover_hide (an_id: INTEGER)
		do
			if attached open_window as al_w then
				al_w.hide_popover_quietly
				changed
			end
		end

	popover_is_shown (an_id: INTEGER): BOOLEAN
		do
			Result := attached open_window as al_w and then attached al_w.popover_shown as al_p
				and then attached widget (an_id) as al_w2 and then al_p = al_w2
		end

	search_field: INTEGER
		local
			l_s: GUI_SW_SEARCH_FIELD
		do
			create l_s.make_search
			Result := register (l_s)
			l_s.set_on_change (agent push (2, Result, 0, 0, 0))
			l_s.set_on_activate (agent push (3, Result, 0, 0, 0))
			l_s.set_on_focus_lost (agent push (29, Result, 0, 0, 0))
		end

	token_field: INTEGER
		local
			l_t: GUI_SW_TOKEN_FIELD
		do
			create l_t.make_tokens
			Result := register (l_t)
			l_t.set_on_change (agent push (2, Result, 0, 0, 0))
		end

	token_field_extend (an_id: INTEGER; a_text: POINTER)
		do
			if attached {GUI_SW_TOKEN_FIELD} widget (an_id) as al_t then
				al_t.extend_token (from_c (a_text))
				changed
			end
		end

	token_field_remove (an_id, i: INTEGER)
		do
			if attached {GUI_SW_TOKEN_FIELD} widget (an_id) as al_t and then 1 <= i and then i <= al_t.tokens.count then
				al_t.remove_token (i)
				changed
			end
		end

	token_field_wipe_out (an_id: INTEGER)
		do
			if attached {GUI_SW_TOKEN_FIELD} widget (an_id) as al_t then
				al_t.wipe_out
				changed
			end
		end

	token_field_count (an_id: INTEGER): INTEGER
		do
			if attached {GUI_SW_TOKEN_FIELD} widget (an_id) as al_t then
				Result := al_t.tokens.count
			end
		end

	token_field_item (an_id, i: INTEGER): POINTER
		do
			if attached {GUI_SW_TOKEN_FIELD} widget (an_id) as al_t and then 1 <= i and then i <= al_t.tokens.count then
				Result := c_text (al_t.tokens.i_th (i))
			end
		end

	path_control: INTEGER
		local
			l_p: GUI_SW_PATH_CONTROL
		do
			create l_p.make_path
			Result := register (l_p)
			l_p.set_on_part (agent report_row (Result, ?))
			l_p.set_on_chevron (agent report_chevron (Result, ?))
			l_p.set_on_space (agent report_path_space (Result))
		end

	path_control_set_chevrons (an_id: INTEGER; a_on: BOOLEAN)
			-- 1p-b.
		do
			if attached {GUI_SW_PATH_CONTROL} widget (an_id) as al_p then
				al_p.set_chevrons (a_on)
				changed
			end
		end

	path_control_set_root_icon (an_id: INTEGER; a_name: POINTER)
			-- 1p-b: the named icon drawn before part 1; empty for none.
		local
			l_name: STRING_32
		do
			l_name := from_c (a_name)
			if attached {GUI_SW_PATH_CONTROL} widget (an_id) as al_p then
				if l_name.is_empty then
					al_p.set_root_icon (l_name, 0)
				else
					al_p.set_root_icon (l_name, glyph_of (l_name))
				end
				changed
			end
		end

	widget_focus (an_id: INTEGER)
			-- 1p-b: the keyboard focus to the widget, from code (a click's focus path), in the
			-- window it is in: a second window's own (a print preview's canvas), else the main one.
		local
			l_top: SW_WIDGET
			l_done: BOOLEAN
		do
			if attached widget (an_id) as al_w and then al_w.accepts_focus then
				from
					l_top := al_w
				until
					not attached l_top.parent as al_up
				loop
					l_top := al_up
				end
				across floats as ic until l_done loop
					if ic.content = l_top then
						ic.give_focus (al_w)
						l_done := True
					end
				end
			end
			if not l_done then
				test_focus (an_id)
			end
		end

	test_press_chevron (an_id, a_part: INTEGER)
		do
			if attached {GUI_SW_PATH_CONTROL} widget (an_id) as al_p and then al_p.has_chevrons
				and then a_part >= 1 and then a_part <= al_p.parts.count
			then
				al_p.press_chevron (a_part)
				changed
			end
		end

	test_press_path_space (an_id: INTEGER)
		do
			if attached {GUI_SW_PATH_CONTROL} widget (an_id) as al_p and then al_p.has_chevrons then
				al_p.press_space
				changed
			end
		end

	test_field_escape (an_id: INTEGER)
			-- As Escape in the field with no suggestion list showing: 55 (a showing list is
			-- closed by the key itself, in GUI_SW_WINDOW).
		do
			report_field_escape (an_id)
		end

feature {GUI_SW_WINDOW} -- Address-bar events (1p-b)

	report_chevron (an_id, a_part: INTEGER)
		do
			push (53, an_id, a_part, 0, 0)
		end

	report_path_space (an_id: INTEGER)
		do
			push (54, an_id, 0, 0, 0)
		end

	report_field_escape (an_id: INTEGER)
		do
			push (55, an_id, 0, 0, 0)
		end

feature -- Path controls, continued

	path_control_set (an_id: INTEGER; a_path: POINTER)
		do
			if attached {GUI_SW_PATH_CONTROL} widget (an_id) as al_p then
				al_p.set_path (from_c (a_path))
				changed
			end
		end

	path_control_set_parts (an_id: INTEGER; a_parts: POINTER)
			-- 1t.
		do
			if attached {GUI_SW_PATH_CONTROL} widget (an_id) as al_p then
				al_p.set_parts (from_c (a_parts))
				changed
			end
		end

	path_control_count (an_id: INTEGER): INTEGER
		do
			if attached {GUI_SW_PATH_CONTROL} widget (an_id) as al_p then
				Result := al_p.parts.count
			end
		end

	path_control_part (an_id, i: INTEGER): POINTER
		do
			if attached {GUI_SW_PATH_CONTROL} widget (an_id) as al_p and then 1 <= i and then i <= al_p.parts.count then
				Result := c_text (al_p.parts.i_th (i))
			end
		end

	rating (a_maximum: INTEGER): INTEGER
		local
			l_r: SW_RATING
		do
			create l_r.make (0, a_maximum, Void)
			Result := register (l_r)
			l_r.set_on_change (agent report_number (Result, ?))
		end

	rating_set (an_id, a_value: INTEGER)
		do
			if attached {SW_RATING} widget (an_id) as al_r then
				al_r.set_value (a_value)
				changed
			end
		end

	rating_value (an_id: INTEGER): INTEGER
		do
			if attached {SW_RATING} widget (an_id) as al_r then
				Result := al_r.value
			end
		end

	rich_text_area: INTEGER
		local
			l_r: GUI_SW_RICH_TEXT_AREA
		do
			create l_r.make_rich (themed (is_dark).size_body)
			Result := register (l_r)
			l_r.set_on_change (agent push (2, Result, 0, 0, 0))
		end

	rich_text_set_trait (an_id, a_start, an_end, a_trait: INTEGER; a_on: BOOLEAN)
		do
			if attached {GUI_SW_RICH_TEXT_AREA} widget (an_id) as al_r then
				al_r.set_trait (a_start, an_end, a_trait, a_on)
				style_changed
			end
		end

	rich_text_set_color (an_id, a_start, an_end, a_rgb: INTEGER)
		do
			if attached {GUI_SW_RICH_TEXT_AREA} widget (an_id) as al_r then
				al_r.set_color (a_start, an_end, a_rgb)
				style_changed
			end
		end

	rich_text_set_size (an_id, a_start, an_end: INTEGER; a_points: REAL_64)
		do
			if attached {GUI_SW_RICH_TEXT_AREA} widget (an_id) as al_r then
				al_r.set_size (a_start, an_end, a_points)
				style_changed
			end
		end

	rich_text_trait_at (an_id, i, a_trait: INTEGER): BOOLEAN
		do
			if attached {GUI_SW_RICH_TEXT_AREA} widget (an_id) as al_r and then 1 <= i and then i <= al_r.text.count then
				inspect a_trait
				when 1 then Result := al_r.style_at (i).bold
				when 2 then Result := al_r.style_at (i).italic
				else Result := al_r.style_at (i).underline
				end
			end
		end

	rich_text_color_at (an_id, i: INTEGER): INTEGER
		do
			Result := -1
			if attached {GUI_SW_RICH_TEXT_AREA} widget (an_id) as al_r and then 1 <= i and then i <= al_r.text.count then
				Result := al_r.style_at (i).color
			end
		end

	rich_text_size_at (an_id, i: INTEGER): REAL_64
			-- The character's own size, else the box's (the theme's body size).
		do
			if attached {GUI_SW_RICH_TEXT_AREA} widget (an_id) as al_r and then 1 <= i and then i <= al_r.text.count then
				Result := al_r.style_at (i).size
				if Result <= 0.0 then
					Result := al_r.body_points
				end
			end
		end

	rich_text_selection_start (an_id: INTEGER): INTEGER
		do
			if attached {GUI_SW_RICH_TEXT_AREA} widget (an_id) as al_r then
				Result := al_r.selection_first
			end
		end

	rich_text_selection_end (an_id: INTEGER): INTEGER
		do
			if attached {GUI_SW_RICH_TEXT_AREA} widget (an_id) as al_r then
				Result := al_r.selection_last
			end
		end

	rich_text_select (an_id, a_start, an_end: INTEGER)
		do
			if attached {GUI_SW_RICH_TEXT_AREA} widget (an_id) as al_r then
				al_r.select_characters (a_start, an_end)
				changed
			end
		end

	code_editor: INTEGER
			-- GUI_SW_CODE_AREA: event 2 on an edit, event 52 (line, column) when the user
			-- moves the caret, event 56 for the key that goes to the matching bracket.
		local
			l_c: GUI_SW_CODE_AREA
		do
			create l_c.make_rich (themed (is_dark).size_body)
			Result := register (l_c)
			l_c.set_on_change (agent push (2, Result, 0, 0, 0))
			l_c.set_on_caret_move (agent push (52, Result, ?, ?, 0))
			l_c.set_on_bracket_key (agent push (56, Result, 0, 0, 0))
			l_c.set_on_fold (agent push (57, Result, ?, ?, 0))
			l_c.set_on_completion_key (agent push (58, Result, ?, 0, 0))
			l_c.set_on_completion_press (agent push (59, Result, ?, 0, 0))
			l_c.set_on_code_key (agent (an_action: INTEGER; a_shift: BOOLEAN; an_id: INTEGER)
				do
					push (60, an_id, an_action, a_shift.to_integer, 0)
				end (?, ?, Result))
			l_c.set_on_caret_gesture (agent push (61, Result, ?, ?, 0))
		end

	code_set_extra_carets (an_id: INTEGER; a_pairs: POINTER; a_count: INTEGER)
		local
			l_data: MANAGED_POINTER
			l_carets: ARRAYED_LIST [TUPLE [caret, anchor: INTEGER]]
			i: INTEGER
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				create l_carets.make (a_count.max (0))
				if a_count > 0 and then a_pairs /= default_pointer then
					create l_data.share_from_pointer (a_pairs, a_count * 8)
					from i := 0 until i >= a_count loop
						l_carets.extend ([l_data.read_integer_32 (i * 8), l_data.read_integer_32 (i * 8 + 4)])
						i := i + 1
					end
				end
				al_c.set_extra_carets (l_carets)
				style_changed
			end
		end

	code_typed_text (an_id: INTEGER): POINTER
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				Result := c_text (al_c.typed_text)
			else
				Result := c_text ({STRING_32} "")
			end
		end

	text_begin_edit_group (an_id: INTEGER)
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				al_c.begin_edit_group
			end
		end

	text_end_edit_group (an_id: INTEGER)
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				al_c.end_edit_group
				changed
			end
		end

	code_show_completions (an_id: INTEGER; a_joined: POINTER; a_selected: INTEGER)
		local
			l_rows: ARRAYED_LIST [TUPLE [label, detail: STRING_32; kind: INTEGER]]
			l_parts: LIST [STRING_32]
			l_kind: INTEGER
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				create l_rows.make (8)
				across from_c (a_joined).split ((0x1F).to_character_32) as ic loop
					l_parts := ic.split ((0x1E).to_character_32)
					if l_parts.count = 3 and then not l_parts [1].is_empty then
						l_kind := 0
						if l_parts [3].is_integer then
							l_kind := l_parts [3].to_integer
						end
						l_rows.extend ([l_parts [1], l_parts [2], l_kind])
					end
				end
				al_c.show_completions (l_rows, a_selected)
				style_changed
			end
		end

	code_select_completion (an_id, a_row: INTEGER)
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c and then al_c.is_completion_shown then
				al_c.select_completion (a_row)
				style_changed
			end
		end

	code_hide_completions (an_id: INTEGER)
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c and then al_c.is_completion_shown then
				al_c.hide_completions
				style_changed
			end
		end

	code_show_bracket_pair (an_id, a_first_start, a_first_count, a_second_start, a_second_count: INTEGER)
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				al_c.show_bracket_pair (a_first_start, a_first_count, a_second_start, a_second_count)
					-- as a style: the frame comes at the next turn of the loop (a look
					-- hides and shows, and a frame for each cost 26 ms on a large text)
				style_changed
			end
		end

	code_hide_bracket_pair (an_id: INTEGER)
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c and then al_c.has_bracket_pair then
				al_c.hide_bracket_pair
				style_changed
			end
		end

	code_set_folding_shown (an_id: INTEGER; a_on: BOOLEAN)
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c and then al_c.is_folding_shown /= a_on then
				al_c.set_folding_shown (a_on)
				changed
			end
		end

	code_set_fold_marks (an_id: INTEGER; a_lines: POINTER; a_count: INTEGER)
		local
			l_marks: GUI_LINE_RANGES
			l_data: MANAGED_POINTER
			i, l_line: INTEGER
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				create l_marks.make
				if a_count > 0 and then a_lines /= default_pointer then
					create l_data.share_from_pointer (a_lines, a_count * 4)
					from
						i := 0
					until
						i >= a_count
					loop
						l_line := l_data.read_integer_32 (i * 4)
						if l_line >= 1 then
							l_marks.put (l_line, l_line)
						end
						i := i + 1
					end
				end
				al_c.set_fold_marks (l_marks)
				style_changed
			end
		end

	code_set_folded_lines (an_id: INTEGER; a_pairs: POINTER; a_count: INTEGER)
			-- (A pair that hides nothing is left out; pairs that reach one another, which
			-- the caller promised not to send, hide what they hide together.)
		local
			l_ranges: GUI_LINE_RANGES
			l_data: MANAGED_POINTER
			i, l_first, l_last: INTEGER
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				create l_ranges.make
				if a_count > 0 and then a_pairs /= default_pointer then
					create l_data.share_from_pointer (a_pairs, a_count * 8)
					from
						i := 0
					until
						i >= a_count
					loop
						l_first := l_data.read_integer_32 (i * 8)
						l_last := l_data.read_integer_32 (i * 8 + 4)
						if l_first >= 1 and l_last > l_first then
							l_ranges.put (l_first, l_last)
						end
						i := i + 1
					end
				end
				if not l_ranges.is_disjoint then
					l_ranges := l_ranges.merged
				end
				al_c.set_hidden_lines (l_ranges)
				style_changed
			end
		end

	code_set_line_numbers (an_id: INTEGER; a_on: BOOLEAN)
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				al_c.set_line_numbers_shown (a_on)
				changed
			end
		end

	code_set_indent (an_id, a_tab_width: INTEGER; a_spaces: BOOLEAN)
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c and then a_tab_width >= 1 then
				al_c.set_indent (a_tab_width, a_spaces)
				changed
			end
		end

	text_line_count (an_id: INTEGER): INTEGER
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				Result := al_c.code_line_count
			end
		end

	text_caret_line (an_id: INTEGER): INTEGER
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				Result := al_c.code_caret_line
			end
		end

	text_caret_column (an_id: INTEGER): INTEGER
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				Result := al_c.code_caret_column
			end
		end

	text_line_text (an_id, n: INTEGER): POINTER
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c and then 1 <= n and then n <= al_c.code_line_count then
				Result := c_text (al_c.code_line_text (n))
			else
				Result := c_text ("")
			end
		end

	text_go_to_line (an_id, n: INTEGER)
			-- The program's own move: no event.
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c and then 1 <= n and then n <= al_c.code_line_count then
				al_c.go_to_line (n)
				changed
			end
		end

	text_replace_range (an_id, a_start, an_end: INTEGER; a_text: POINTER)
			-- The program's own change, one undo step: no event.
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c
				and then 1 <= a_start and then a_start <= an_end + 1 and then an_end <= al_c.text.count
			then
				al_c.replace_characters (a_start, an_end, from_c (a_text))
				changed
			end
		end

	ask_text (a_window: INTEGER; a_title, a_prompt, an_initial: POINTER): POINTER
		do
			if attached windows.item (a_window) as al_w and then attached al_w.ask_text_sheet (from_c (a_title), from_c (a_prompt), from_c (an_initial)) as al_t then
				Result := c_text (al_t)
			end
		end

	confirm_with_check (a_window: INTEGER; a_title, a_text, a_check: POINTER): INTEGER
		do
			if attached windows.item (a_window) as al_w then
				Result := al_w.confirm_check_sheet (from_c (a_title), from_c (a_text), from_c (a_check))
			end
		end

	choose_font (a_window: INTEGER; a_title, a_family: POINTER; a_points: REAL_64; a_bold, an_italic: BOOLEAN): POINTER
		do
			if attached windows.item (a_window) as al_w and then attached al_w.choose_font_sheet (from_c (a_title), font_families,
				from_c (a_family), a_points, a_bold, an_italic) as al_f
			then
				Result := c_text (al_f)
			end
		end

	show_about (a_name, a_version, a_copyright, a_comments: POINTER)
		do
			if attached open_window as al_w then
				al_w.about_sheet (from_c (a_name), from_c (a_version), from_c (a_copyright), from_c (a_comments))
			end
		end

	font_families: ARRAYED_LIST [STRING_32]
			-- The installed font families (GDI), sorted, each once.
		local
			l_buf: MANAGED_POINTER
			l_sorted: SORTED_TWO_WAY_LIST [STRING_32]
			n: INTEGER
		do
			create Result.make (256)
			create l_buf.make (2 * Font_buffer)
			n := c_font_families (l_buf.item, Font_buffer)
			if n > 0 then
				create l_sorted.make
				across (create {UTF_CONVERTER}).utf_16_0_pointer_to_string_32 (l_buf).split ('%/31/') as ic loop
					if not ic.is_empty then
						l_sorted.extend (ic.twin)
					end
				end
				across l_sorted as ic loop
					Result.extend (ic)
				end
			end
		end

	Font_buffer: INTEGER = 131072
			-- WCHARs for the family names.

	c_font_families (a_buf: POINTER; a_cap: INTEGER): INTEGER
		external
			"C inline use %"simple_gui_win.h%""
		alias
			"return sgw_font_families((WCHAR *) $a_buf, (int) $a_cap);"
		end

	check_box (a_text: POINTER): INTEGER
		local
			l_c: SW_CHECK_BOX
		do
			create l_c.make (from_c (a_text), False, Void)
			Result := register (l_c)
			l_c.set_on_change (agent report_toggle (Result))
		end

	check_box_set (an_id: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_CHECK_BOX} widget (an_id) as al_c then
				al_c.set_checked (a_on)
				changed
			end
		end

	check_box_is_checked (an_id: INTEGER): BOOLEAN
		do
			Result := attached {SW_CHECK_BOX} widget (an_id) as al_c and then al_c.is_checked
		end

	check_box_set_text (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_CHECK_BOX} widget (an_id) as al_c then
				al_c.set_label (from_c (a_text))
				changed
			end
		end

	check_box_text (an_id: INTEGER): POINTER
		do
			if attached {SW_CHECK_BOX} widget (an_id) as al_c then
				Result := c_text (al_c.label)
			end
		end

	text_area: INTEGER
		local
			l_t: SW_TEXT_BOX
		do
			create l_t.make ("")
			Result := register (l_t)
			l_t.set_on_change (agent push (2, Result, 0, 0, 0))
		end

	text_area_set (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t then
				al_t.set_text (from_c (a_text))
				changed
			end
		end

	text_area_get (an_id: INTEGER): POINTER
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t then
				Result := c_text (al_t.text)
			end
		end

	text_area_string (an_id: INTEGER): STRING_32
			-- A copy of the box's own string: no pass through UTF-8 and back.
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t then
				Result := al_t.text.twin
			else
				create Result.make_empty
			end
		end

	text_area_set_read_only (an_id: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t then
				al_t.set_read_only (a_on)
			end
		end

	tabs: INTEGER
		local
			l_t: SW_TABS
		do
			create l_t.make
			Result := register (l_t)
			l_t.set_on_change (agent report_page (Result, ?))
		end

	tabs_extend (a_tabs, a_page: INTEGER; a_title: POINTER)
		do
			if attached {SW_TABS} widget (a_tabs) as al_t and then attached widget (a_page) as al_p then
				quiet := quiet + 1
				al_t.add_page (from_c (a_title), al_p)
				quiet := quiet - 1
				changed
			end
		end

	tabs_select (a_tabs, a_page: INTEGER)
		do
			if attached {SW_TABS} widget (a_tabs) as al_t and then a_page >= 1 and then a_page <= al_t.pages.count then
				quiet := quiet + 1
				al_t.select_tab (a_page)
				quiet := quiet - 1
				changed
			end
		end

	tabs_selected (a_tabs: INTEGER): INTEGER
		do
			if attached {SW_TABS} widget (a_tabs) as al_t then
				Result := al_t.selected_index
			end
		end

	dialog (a_title: POINTER): INTEGER
			-- 1u: a sheet's content, built when shown.
		local
			l_d: GUI_SW_DIALOG
		do
			create l_d.make (from_c (a_title))
			Result := register (l_d)
			l_d.set_on_press (agent dialog_pressed (Result, ?))
		end

	dialog_set_content (a_dialog, a_widget: INTEGER)
		do
			if attached {GUI_SW_DIALOG} widget (a_dialog) as al_d and then attached widget (a_widget) as al_c then
				al_d.set_content (al_c)
			end
		end

	dialog_add_button (a_dialog: INTEGER; a_text: POINTER; a_role: INTEGER): INTEGER
		do
			if attached {GUI_SW_DIALOG} widget (a_dialog) as al_d then
				Result := al_d.add_button (from_c (a_text), a_role.max (1).min (4))
			end
		end

	dialog_set_button_enabled (a_dialog, n: INTEGER; a_on: BOOLEAN)
		do
			if attached {GUI_SW_DIALOG} widget (a_dialog) as al_d and then 1 <= n and then n <= al_d.button_count then
				al_d.set_button_enabled (n, a_on)
				changed
			end
		end

	dialog_present (a_dialog, a_parent_window: INTEGER; an_app_modal: BOOLEAN)
			-- A centered sheet in the parent window; with none, in the application's open window.
		local
			l_win: detachable GUI_SW_WINDOW
		do
			if attached {GUI_SW_DIALOG} widget (a_dialog) as al_d then
				if a_parent_window > 0 and then attached windows.item (a_parent_window) as al_p and then al_p.is_window_open then
					l_win := al_p
				else
					l_win := open_window
				end
				if attached l_win as al_w and then al_w.is_window_open then
					al_w.present_dialog (al_d)
					changed
				end
			end
		end

	dialog_pump (a_dialog: INTEGER)
			-- Nothing on Windows: the sheet is drawn by the window's own loop.
		do
		end

	dialog_close (a_dialog: INTEGER)
		do
			if attached {GUI_SW_DIALOG} widget (a_dialog) as al_d and then attached al_d.host as al_h then
				al_h.dismiss_dialog (al_d)
				changed
			end
		end

	dialog_is_shown (a_dialog: INTEGER): BOOLEAN
		do
			Result := attached {GUI_SW_DIALOG} widget (a_dialog) as al_d and then attached al_d.host as al_h
				and then al_h.is_dialog_up (al_d)
		end

	help_show_tip (a_widget: INTEGER; a_text: POINTER)
			-- A note under the widget for about 6 seconds.
		do
			if attached widget (a_widget) as al_w and then attached window_of (al_w) as al_win and then al_win.is_window_open then
				al_win.show_help_tip (from_c (a_text), al_w.x, al_w.y + al_w.height)
				help_tip_window := al_win
				help_tip_due := clock.milliseconds + Help_tip_ms
				changed
			end
		end

	test_press_dialog_button (a_dialog, n: INTEGER)
			-- As a click on the button.
		do
			if attached {GUI_SW_DIALOG} widget (a_dialog) as al_d and then dialog_is_shown (a_dialog) then
				al_d.press (n)
			end
		end

	test_dialog_key (a_dialog, a_key: INTEGER)
			-- 1 Return (the default button), 2 Escape and 3 the close box (Cancel).
		do
			if attached {GUI_SW_DIALOG} widget (a_dialog) as al_d and then dialog_is_shown (a_dialog) then
				if a_key = 1 then
					al_d.press_role (1)
				elseif a_key = 2 or a_key = 3 then
					al_d.press_role (2)
				end
			end
		end

	test_press_dialog_button_later (a_dialog, n, a_ms: INTEGER)
		do
			later_presses.extend ([a_dialog, n, clock.milliseconds + a_ms.max (1)])
		end

	test_dialog_button_order (a_dialog: INTEGER): POINTER
		local
			l_order: STRING_32
		do
			create l_order.make_empty
			if attached {GUI_SW_DIALOG} widget (a_dialog) as al_d then
				l_order := al_d.shown_order
			end
			Result := c_text (l_order)
		end

	test_press_help (a_window: INTEGER)
			-- As F1 in the window.
		do
			if attached windows.item (a_window) as al_w then
				al_w.press_help
			end
		end

	test_help_tip_shown: POINTER
		local
			l_text: STRING_32
		do
			create l_text.make_empty
			if attached help_tip_window as al_win then
				l_text := al_win.help_tip_showing
			end
			Result := c_text (l_text)
		end

	tabs_set_position (a_tabs, a_position: INTEGER)
			-- 1t: SW_TABS' strip placement (the same numbers).
		do
			if attached {SW_TABS} widget (a_tabs) as al_t and then a_position >= 0 and then a_position <= 4 then
				al_t.set_strip_position (a_position)
				changed
			end
		end

	sidebar: INTEGER
			-- 1t: SW_SIDEBAR; the user's page is 46, the collapse button 47.
		local
			l_s: SW_SIDEBAR
		do
			create l_s.make
			Result := register (l_s)
			l_s.set_on_page_change (agent (an_id, p: INTEGER) do push (46, an_id, p, 0, 0) end (Result, ?))
			l_s.set_on_collapse_change (agent (an_id: INTEGER; c: BOOLEAN) do push (47, an_id, 0, c.to_integer, 0) end (Result, ?))
		end

	sidebar_extend (a_sidebar, a_page: INTEGER; a_title: POINTER)
		do
			if attached {SW_SIDEBAR} widget (a_sidebar) as al_s and then attached widget (a_page) as al_page then
				al_s.extend (al_page, from_c (a_title))
				changed
			end
		end

	sidebar_add_heading (a_sidebar: INTEGER; a_text: POINTER)
		do
			if attached {SW_SIDEBAR} widget (a_sidebar) as al_s then
				al_s.add_heading (from_c (a_text))
				changed
			end
		end

	sidebar_set_icon (a_sidebar, i: INTEGER; a_name: POINTER)
		do
			if attached {SW_SIDEBAR} widget (a_sidebar) as al_s and then i >= 1 and then i <= al_s.page_count then
				al_s.set_page_icon (i, from_c (a_name))
				changed
			end
		end

	sidebar_set_badge (a_sidebar, i: INTEGER; a_text: POINTER)
		do
			if attached {SW_SIDEBAR} widget (a_sidebar) as al_s and then i >= 1 and then i <= al_s.page_count then
				al_s.set_page_badge (i, from_c (a_text))
				changed
			end
		end

	sidebar_select (a_sidebar, i: INTEGER)
		do
			if attached {SW_SIDEBAR} widget (a_sidebar) as al_s and then i >= 1 and then i <= al_s.page_count then
				al_s.select_page (i)
				changed
			end
		end

	sidebar_selected (a_sidebar: INTEGER): INTEGER
		do
			if attached {SW_SIDEBAR} widget (a_sidebar) as al_s then
				Result := al_s.selected_page
			end
		end

	sidebar_set_collapsible (a_sidebar: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_SIDEBAR} widget (a_sidebar) as al_s then
				al_s.set_collapsible (a_on)
				changed
			end
		end

	sidebar_set_collapsed (a_sidebar: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_SIDEBAR} widget (a_sidebar) as al_s then
				if a_on then al_s.collapse else al_s.expand end
				changed
			end
		end

	sidebar_is_collapsed (a_sidebar: INTEGER): BOOLEAN
		do
			Result := attached {SW_SIDEBAR} widget (a_sidebar) as al_s and then al_s.is_collapsed
		end

	test_toggle_sidebar (a_sidebar: INTEGER)
		do
			if attached {SW_SIDEBAR} widget (a_sidebar) as al_s then
				al_s.press_collapse_button
				changed
			end
		end

	test_page_shown (an_id: INTEGER): INTEGER
			-- The page SW shows in tabs or a sidebar.
		do
			if attached {SW_TABS} widget (an_id) as al_t then
				Result := al_t.selected_index
			elseif attached {SW_SIDEBAR} widget (an_id) as al_s then
				Result := al_s.selected_page
			end
		end

	tabs_set_title (a_tabs, a_page: INTEGER; a_title: POINTER)
		do
			if attached {SW_TABS} widget (a_tabs) as al_t and then a_page >= 1 and then a_page <= al_t.labels.count then
				al_t.labels.put_i_th (from_c (a_title), a_page)
				changed
			end
		end

	list: INTEGER
		local
			l_l: SW_TEXT_LIST
		do
			create l_l.make (120.0)
			Result := register (l_l)
			l_l.set_on_select (agent report_row (Result, ?))
			l_l.set_on_row_check (agent (an_id, r: INTEGER; c: BOOLEAN) do push (43, an_id, r, c.to_integer, 0) end (Result, ?, ?))
			l_l.set_on_row_close (agent (an_id, r: INTEGER) do push (44, an_id, r, 0, 0) end (Result, ?))
		end

	list_extend_rich (an_id: INTEGER; a_title, a_subtitle, an_icon: POINTER; a_badge, a_flags: INTEGER)
			-- 1s: SW_TEXT_LIST's row, then its parts.
		local
			i: INTEGER
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l then
				al_l.extend (from_c (a_title))
				i := al_l.count
				al_l.set_row_subtitle (i, from_c (a_subtitle))
				al_l.set_row_icon (i, from_c (an_icon))
				al_l.set_row_badge (i, a_badge.max (0))
				al_l.set_row_checkable (i, a_flags & 1 /= 0)
				al_l.set_row_checked (i, a_flags & 2 /= 0)
				al_l.set_row_closable (i, a_flags & 4 /= 0)
				changed
			end
		end

	list_set_checked (an_id, a_row: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l and then a_row >= 1 and then a_row <= al_l.count then
				al_l.set_row_checked (a_row, a_on)
				changed
			end
		end

	list_is_checked (an_id, a_row: INTEGER): BOOLEAN
		do
			Result := attached {SW_TEXT_LIST} widget (an_id) as al_l and then a_row >= 1 and then a_row <= al_l.count
				and then al_l.is_row_checked (a_row)
		end

	list_remove (an_id, a_row: INTEGER)
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l and then a_row >= 1 and then a_row <= al_l.count then
				al_l.remove_row (a_row)
				changed
			end
		end

	list_reorder (an_id: INTEGER; an_order: POINTER)
		local
			l_order: ARRAY [INTEGER]
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l then
				l_order := numbers_in (from_c (an_order))
				if al_l.is_permutation (l_order) then
					al_l.reorder (l_order)
					changed
				end
			end
		end

	list_set_filter (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l then
				al_l.set_filter_text (from_c (a_text))
				changed
			end
		end

	list_shown_count (an_id: INTEGER): INTEGER
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l then
				Result := al_l.shown_count
			end
		end

	test_check_row (an_id, a_row: INTEGER)
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l and then a_row >= 1 and then a_row <= al_l.count then
				al_l.press_row_check (a_row)
				changed
			end
		end

	test_close_row (an_id, a_row: INTEGER)
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l and then a_row >= 1 and then a_row <= al_l.count then
				al_l.press_row_close (a_row)
				changed
			end
		end

	numbers_in (a_text: READABLE_STRING_32): ARRAY [INTEGER]
			-- The whole numbers in `a_text', in order, whatever separates them.
		local
			l_list: ARRAYED_LIST [INTEGER]
			l_n, i: INTEGER
			l_in: BOOLEAN
		do
			create l_list.make (8)
			from i := 1 until i > a_text.count + 1 loop
				if i <= a_text.count and then a_text [i].is_digit then
					l_n := l_n * 10 + (a_text [i].code - ('0').code)
					l_in := True
				elseif l_in then
					l_list.extend (l_n)
					l_n := 0
					l_in := False
				end
				i := i + 1
			end
			create Result.make_from_array (l_list.to_array)
		end

	grid_view: INTEGER
			-- 1v-a: SW_GRID_VIEW, a drawn grid; 50 is the user's selection, 51 an activation.
		local
			l_g: SW_GRID_VIEW
			l_loader: GUI_PICTURE_LOADER
		do
			create l_g.make (240.0)
			Result := register (l_g)
				-- every format, decoded off the GUI thread by a worker processor
			create l_loader.make (l_g, agent changed)
			picture_loaders.extend (l_loader)
			l_g.set_picture_loader (agent l_loader.request)
			l_g.set_picture_decoder (agent decoded_file)
			l_g.set_on_select (agent (an_id, i: INTEGER) do push (50, an_id, i, 0, 0) end (Result, ?))
			l_g.set_on_activate (agent (an_id, i: INTEGER) do push (51, an_id, i, 0, 0) end (Result, ?))
		end

	grid_view_extend (an_id: INTEGER; a_title, a_picture, an_icon: POINTER)
		local
			i: INTEGER
		do
			if attached {SW_GRID_VIEW} widget (an_id) as al_g then
				al_g.extend (from_c (a_title))
				i := al_g.count
				if not from_c (a_picture).is_empty then
					al_g.set_item_picture (i, from_c (a_picture))
				end
				al_g.set_item_icon (i, from_c (an_icon))
				changed
			end
		end

	grid_view_set_subtitle (an_id, i: INTEGER; a_text: POINTER)
		do
			if attached {SW_GRID_VIEW} widget (an_id) as al_g and then i >= 1 and then i <= al_g.count then
				al_g.set_item_subtitle (i, from_c (a_text))
				changed
			end
		end

	grid_view_remove (an_id, i: INTEGER)
		do
			if attached {SW_GRID_VIEW} widget (an_id) as al_g and then i >= 1 and then i <= al_g.count then
				al_g.remove_item (i)
				changed
			end
		end

	grid_view_wipe_out (an_id: INTEGER)
		do
			if attached {SW_GRID_VIEW} widget (an_id) as al_g then
				al_g.wipe_out
				changed
			end
		end

	grid_view_set_item_size (an_id, a_width, a_height: INTEGER)
		do
			if attached {SW_GRID_VIEW} widget (an_id) as al_g and then a_width > 0 and then a_height > 0 then
				al_g.set_item_size (a_width, a_height)
				changed
			end
		end

	grid_view_set_spacing (an_id, a_spacing: INTEGER)
		do
			if attached {SW_GRID_VIEW} widget (an_id) as al_g and then a_spacing >= 0 then
				al_g.set_spacing (a_spacing)
				changed
			end
		end

	grid_view_set_multiple (an_id: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_GRID_VIEW} widget (an_id) as al_g then
				al_g.set_multiple (a_on)
				changed
			end
		end

	grid_view_select (an_id, i: INTEGER; an_extend: BOOLEAN)
			-- Quiet; 0 clears.
		do
			if attached {SW_GRID_VIEW} widget (an_id) as al_g and then i >= 0 and then i <= al_g.count then
				al_g.select_item_quietly (i, an_extend)
				changed
			end
		end

	grid_view_selected_count (an_id: INTEGER): INTEGER
		do
			if attached {SW_GRID_VIEW} widget (an_id) as al_g then
				Result := al_g.selected_count
			end
		end

	grid_view_selected_at (an_id, k: INTEGER): INTEGER
		do
			if attached {SW_GRID_VIEW} widget (an_id) as al_g and then k >= 1 and then k <= al_g.selected_count then
				Result := al_g.selected_at (k)
			end
		end

	grid_view_scroll_to (an_id, i: INTEGER)
		do
			if attached {SW_GRID_VIEW} widget (an_id) as al_g and then i >= 1 and then i <= al_g.count then
				al_g.scroll_to_item (i)
				changed
			end
		end

	grid_view_set_filter (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_GRID_VIEW} widget (an_id) as al_g then
				al_g.set_filter_text (from_c (a_text))
				changed
			end
		end

	grid_view_shown_count (an_id: INTEGER): INTEGER
		do
			if attached {SW_GRID_VIEW} widget (an_id) as al_g then
				Result := al_g.shown_count
			end
		end

	test_activate_item (an_id, i: INTEGER)
			-- As the user double-clicking an item: selected, then activated (51).
		do
			if attached {SW_GRID_VIEW} widget (an_id) as al_g and then al_g.is_shown (i) then
				al_g.activate_by_user (i)
				changed
			end
		end

	test_item_picture_ready (an_id, i: INTEGER): BOOLEAN
			-- Is the item's picture decoded and drawn? (The frame decodes one a heartbeat.)
		do
			Result := attached {SW_GRID_VIEW} widget (an_id) as al_g and then i >= 1 and then i <= al_g.count
				and then al_g.is_picture_ready (i)
		end

	list_extend (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l then
				al_l.extend (from_c (a_text))
				changed
			end
		end

	list_wipe_out (an_id: INTEGER)
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l then
				al_l.wipe_out
				changed
			end
		end

	list_select (an_id, a_row: INTEGER)
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l and then a_row >= 0 and then a_row <= al_l.count then
				al_l.select_row_quietly (a_row)
				if a_row > 0 then
					al_l.scroll_to_row (a_row)
				end
				changed
			end
		end

	list_selected (an_id: INTEGER): INTEGER
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l then
				Result := al_l.selected_index
			end
		end

	table (a_titles: POINTER): INTEGER
			-- An SW_DATA_GRID over rows of text cells (titles and cells joined by U+001F). A header
			-- click is reported, not sorted: the program sorts by refilling.
		local
			g: SW_DATA_GRID [ARRAY [STRING_32]]
			i: INTEGER
		do
			create g.make (150.0)
			i := 0
			across from_c (a_titles).split ('%/31/') as ic loop
				i := i + 1
				g.add_column (create {SW_GRID_COLUMN [ARRAY [STRING_32]]}.make (ic, 150.0, agent cell_of (?, i)))
			end
			Result := register (g)
			table_rows.force (create {ARRAYED_LIST [ARRAY [STRING_32]]}.make (16), Result)
			g.set_on_header_click (agent report_header (Result, ?, ?))
			g.set_on_select (agent report_table_select (Result, ?))
			g.set_on_cell_edit (agent table_cell_edited (Result, ?, ?, ?))
		end

	table_cell_edited (a_table, a_model, a_column: INTEGER; a_text: STRING_32): detachable STRING_32
			-- SW_DATA_GRID's edit: accepted for now (a held table shows it) and told (45); the
			-- program's validator may refuse it after (`table_refuse_edit').
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g then
				last_edit_old := al_g.cell_text (a_model, a_column).twin
			end
			last_edit_text := a_text.twin
			push (45, a_table, a_model, a_column, 0)
		end

	last_edit_text: STRING_32
			-- The text of the edit 45 told of.
		attribute
			create Result.make_empty
		end

	last_edit_old: STRING_32
			-- The cell's text before it.
		attribute
			create Result.make_empty
		end

	table_set_column_editor (a_table, a_column, a_kind: INTEGER; a_choices: POINTER)
		local
			l_choices: ARRAYED_LIST [STRING_32]
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g and then a_column >= 1 and then a_column <= al_g.columns.count
				and then a_kind >= 0 and then a_kind <= 3
			then
				al_g.set_column_editor (a_column, a_kind)
				if a_kind = 3 then
					create l_choices.make (4)
					across from_c (a_choices).split ('%/31/') as ic loop
						l_choices.extend (ic)
					end
					al_g.set_column_choices (a_column, l_choices.to_array)
				end
				changed
			end
		end

	table_take_edit (a_table: INTEGER): POINTER
		do
			Result := c_text (last_edit_text)
		end

	table_refuse_edit (a_table, a_row, a_column: INTEGER; a_message: POINTER)
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g and then a_row >= 1 and then a_row <= al_g.rows.count
				and then a_column >= 1 and then a_column <= al_g.columns.count
			then
				al_g.refuse_edit (a_row, a_column, last_edit_old, from_c (a_message))
				changed
			end
		end

	table_set_filter (a_table: INTEGER; a_text: POINTER; a_columns_mask: INTEGER)
			-- Held rows matched here: the text, ignoring case, in the mask's columns (0: all).
		local
			l_needle: STRING_32
			l_shown: ARRAYED_LIST [INTEGER]
			r, c: INTEGER
			l_hit: BOOLEAN
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g and then attached table_rows.item (a_table) as al_rows then
				l_needle := from_c (a_text).as_lower
				if l_needle.is_empty then
					al_g.set_shown_models (Void)
				else
					create l_shown.make (al_rows.count)
					from r := 1 until r > al_rows.count loop
						l_hit := False
						from c := 1 until c > al_g.columns.count or l_hit loop
							if a_columns_mask = 0 or else (c <= 31 and then a_columns_mask & (1 |<< (c - 1)) /= 0) then
								l_hit := al_g.cell_text (r, c).as_lower.has_substring (l_needle)
							end
							c := c + 1
						end
						if l_hit then
							l_shown.extend (r)
						end
						r := r + 1
					end
					al_g.set_shown_models (l_shown.to_array)
				end
				changed
			end
		end

	table_set_shown_rows (a_table: INTEGER; a_rows: POINTER)
		local
			l_text: STRING_32
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g then
				l_text := from_c (a_rows)
				if l_text.is_empty then
					al_g.set_shown_models (Void)
				else
					al_g.set_shown_models (numbers_in (l_text))
				end
				changed
				check_rows_wanted
			end
		end

	table_shown_count (a_table: INTEGER): INTEGER
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g then
				Result := al_g.shown_count
			end
		end

	test_edit_cell (a_table, a_row, a_column: INTEGER; a_text: POINTER)
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g and then a_row >= 1 and then a_row <= al_g.rows.count
				and then a_column >= 1 and then a_column <= al_g.columns.count
			then
				al_g.edit_cell_by_user (a_row, a_column, from_c (a_text))
				changed
			end
		end

	test_cancel_edit (a_table, a_row, a_column: INTEGER)
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g and then a_row >= 1 and then a_row <= al_g.rows.count
				and then a_column >= 1 and then a_column <= al_g.columns.count
			then
				al_g.cancel_edit_by_user (a_row, a_column)
				changed
			end
		end

	test_cell_text (a_table, a_row, a_column: INTEGER): POINTER
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g and then a_row >= 1 and then a_row <= al_g.rows.count
				and then a_column >= 1 and then a_column <= al_g.columns.count
			then
				Result := c_text (al_g.cell_text (a_row, a_column))
			else
				Result := c_text ({STRING_32} "")
			end
		end

	test_cell_note (a_table: INTEGER): POINTER
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g then
				Result := c_text (al_g.cell_note)
			else
				Result := c_text ({STRING_32} "")
			end
		end

	table_extend (a_table: INTEGER; a_cells: POINTER)
			-- One row more: appended to the grid in place (`add_row'), not by handing it
			-- every row again, so filling a table is linear (it copied every row so far).
		local
			l_cells: ARRAY [STRING_32]
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g and then attached table_rows.item (a_table) as al_rows then
				l_cells := cells_of (from_c (a_cells))
				al_rows.extend (l_cells)
				al_g.add_row (l_cells)
				changed
			end
		end

	table_wipe_out (a_table: INTEGER)
			-- No rows; a table in source mode leaves it (1f).
		do
			row_sources.remove (a_table)
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g and then attached table_rows.item (a_table) as al_rows then
				al_rows.wipe_out
				al_g.set_holds_edits (True)
				al_g.forget_edits
				al_g.set_rows (al_rows)
				changed
			end
		end

	table_set_multiple (a_table: INTEGER; a_on: BOOLEAN)
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g then
				al_g.set_multiple (a_on)
			end
		end

	table_select (a_table, a_row: INTEGER; a_extend: BOOLEAN)
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g and then a_row >= 0 and then a_row <= al_g.rows.count then
				al_g.select_model_row_quietly (a_row, a_extend)
				changed
			end
		end

	table_set_source (a_table, a_count: INTEGER)
			-- Source mode (1f): `a_count' rows, every one the shared empty row until answered;
			-- the selection and the rows held are dropped.
		local
			l_source: GUI_SW_ROW_SOURCE
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g then
				create l_source.make (a_count, al_g.columns.count)
				row_sources.force (l_source, a_table)
				if attached table_rows.item (a_table) as al_rows then
					al_rows.wipe_out
				end
				al_g.select_model_row_quietly (0, False)
				al_g.set_holds_edits (False)
				al_g.set_shown_models (Void)
				al_g.set_rows (empty_rows (l_source, a_count, Void))
				changed
				check_rows_wanted
			end
		end

	table_set_row (a_table, a_row: INTEGER; a_cells: POINTER)
			-- An answer to rows wanted: hold the row and draw it; past `Cache_limit' answered
			-- rows the oldest out of sight go back to empty.
		local
			l_shown: TUPLE [first, last: INTEGER]
			l_old, l_kept: INTEGER
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g and then attached row_sources.item (a_table) as al_s
				and then a_row >= 1 and then a_row <= al_s.count and then a_row <= al_g.rows.count
			then
				al_g.put_row (cells_of (from_c (a_cells)), a_row)
				al_s.pending.remove (a_row)
				al_s.answered.extend (a_row)
				l_shown := al_g.shown_positions
				from
					l_kept := 0
				until
					al_s.answered.count <= al_s.Cache_limit or l_kept >= al_s.answered.count
				loop
					l_old := al_s.answered.item
					al_s.answered.remove
					if l_old >= l_shown.first and l_old <= l_shown.last then
							-- in sight: keep it, at the back
						al_s.answered.extend (l_old)
						l_kept := l_kept + 1
					elseif l_old <= al_g.rows.count then
						al_g.put_row (al_s.empty, l_old)
					end
				end
				changed
			end
		end

	table_set_row_count (a_table, a_count: INTEGER)
			-- The source now has `a_count' rows: rows held past it go, and so do selected rows
			-- past it (SW_DATA_GRID.set_rows drops them); no event.
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g and then attached row_sources.item (a_table) as al_s then
				al_s.set_count (a_count)
				al_g.set_shown_models (Void)
				al_g.set_rows (empty_rows (al_s, a_count, al_g.rows))
				changed
				check_rows_wanted
			end
		end

	table_forget_rows (a_table: INTEGER)
			-- Every row may have changed: all back to empty, asked for again as they show; the
			-- selection stays by row number.
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g and then attached row_sources.item (a_table) as al_s then
				al_s.forget_all
				al_g.set_rows (empty_rows (al_s, al_s.count, Void))
				changed
				check_rows_wanted
			end
		end

	table_forget_row (a_table, a_row: INTEGER)
			-- Row `a_row' changed: back to empty, asked for again if it shows.
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g and then attached row_sources.item (a_table) as al_s
				and then a_row >= 1 and then a_row <= al_g.rows.count
			then
				al_g.put_row (al_s.empty, a_row)
				al_s.pending.remove (a_row)
				changed
				check_rows_wanted
			end
		end

	table_scroll_to (a_table, a_row: INTEGER)
			-- Bring row `a_row' into view (any table; in source mode its rows are then asked for).
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g and then a_row >= 1 and then a_row <= al_g.view.count then
				al_g.scroll_to_position (a_row)
				changed
				check_rows_wanted
			end
		end

	row_sources: HASH_TABLE [GUI_SW_ROW_SOURCE, INTEGER]
			-- The tables in source mode (1f), by id.
		once ("OBJECT")
			create Result.make (4)
		end

	empty_rows (a_source: GUI_SW_ROW_SOURCE; a_count: INTEGER; a_keep: detachable LIST [ARRAY [STRING_32]]): ARRAYED_LIST [ARRAY [STRING_32]]
			-- `a_count' rows: those of `a_keep' that fit, then the shared empty row.
		local
			i: INTEGER
		do
			create Result.make (a_count)
			from
				i := 1
			until
				i > a_count
			loop
				if attached a_keep as al_keep and then i <= al_keep.count then
					Result.extend (al_keep.i_th (i))
				else
					Result.extend (a_source.empty)
				end
				i := i + 1
			end
		ensure
			counted: Result.count = a_count
		end

	check_rows_wanted
			-- For each table in source mode: the rows in sight plus one viewful either side that
			-- are still empty and not yet asked for are asked for, as one span (event 16).
		local
			l_shown: TUPLE [first, last: INTEGER]
			l_lo, l_hi, l_margin, l_first, l_last, r: INTEGER
		do
			from
				row_sources.start
			until
				row_sources.after
			loop
				if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (row_sources.key_for_iteration) as al_g
					and then attached row_sources.item_for_iteration as al_s and then al_s.count > 0
				then
					l_shown := al_g.shown_positions
					if l_shown.first > 0 then
						l_margin := l_shown.last - l_shown.first + 1
						l_lo := (l_shown.first - l_margin).max (1)
						l_hi := (l_shown.last + l_margin).min (al_s.count).min (al_g.rows.count)
						l_first := 0
						l_last := 0
						from
							r := l_lo
						until
							r > l_hi
						loop
							if al_g.rows.i_th (r) = al_s.empty and then not al_s.pending.has (r) then
								al_s.pending.force (True, r)
								if l_first = 0 then
									l_first := r
								end
								l_last := r
							end
							r := r + 1
						end
						if l_first > 0 then
							push (16, row_sources.key_for_iteration, l_first, l_last, 0)
						end
					end
				end
				row_sources.forth
			end
		end

	table_selected_count (a_table: INTEGER): INTEGER
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g then
				Result := al_g.selected_count
			end
		end

	table_selected_at (a_table, i: INTEGER): INTEGER
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g and then i >= 1 and then i <= al_g.selected_count then
				Result := ascending_selection (al_g).i_th (i)
			end
		end

	table_set_sort_indicator (a_table, a_column: INTEGER; a_ascending: BOOLEAN)
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g and then a_column >= 0 and then a_column <= al_g.columns.count then
				al_g.set_sort_indicator (a_column, a_ascending)
				changed
			end
		end

	tree: INTEGER
			-- An SW_TREE over node numbers; the backend keeps the texts, parents and children.
		local
			l_t: SW_TREE [INTEGER]
			l_roots: ARRAYED_LIST [INTEGER]
		do
			create l_t.make (150.0)
			Result := register (l_t)
			create l_roots.make (8)
			tree_roots.force (l_roots, Result)
			l_t.set_roots (l_roots)
			l_t.set_children (agent tree_children (Result, ?))
			l_t.set_label (agent tree_label (Result, ?))
			l_t.set_on_select (agent report_tree_select (Result, ?))
			l_t.set_on_expansion (agent report_expansion (Result, ?, ?))
		end

	tree_add (a_tree, a_node, a_parent: INTEGER; a_text: POINTER)
		do
			if attached {SW_TREE [INTEGER]} widget (a_tree) as al_t and then attached tree_roots.item (a_tree) as al_roots then
				node_text.force (from_c (a_text), node_key (a_tree, a_node))
				node_parent.force (a_parent, node_key (a_tree, a_node))
				if a_parent = 0 then
					al_roots.extend (a_node)
				else
					if not node_children.has (node_key (a_tree, a_parent)) then
						node_children.force (create {ARRAYED_LIST [INTEGER]}.make (4), node_key (a_tree, a_parent))
					end
					if attached node_children.item (node_key (a_tree, a_parent)) as al_kids then
						al_kids.extend (a_node)
					end
				end
				al_t.set_roots (al_roots)
				changed
			end
		end

	tree_move (a_tree, a_node, a_parent, a_position: INTEGER)
			-- 1q-c: the node's children travel with it (they hang off its number).
		local
			l_from, l_into: detachable ARRAYED_LIST [INTEGER]
		do
			if attached {SW_TREE [INTEGER]} widget (a_tree) as al_t and then attached tree_roots.item (a_tree) as al_roots then
				if node_parent.item (node_key (a_tree, a_node)) = 0 then
					l_from := al_roots
				else
					l_from := node_children.item (node_key (a_tree, node_parent.item (node_key (a_tree, a_node))))
				end
				if attached l_from then
					l_from.prune_all (a_node)
				end
				if a_parent = 0 then
					l_into := al_roots
				else
					if not node_children.has (node_key (a_tree, a_parent)) then
						node_children.force (create {ARRAYED_LIST [INTEGER]}.make (4), node_key (a_tree, a_parent))
					end
					l_into := node_children.item (node_key (a_tree, a_parent))
				end
				if attached l_into as al_into then
					if a_position >= 1 and a_position <= al_into.count then
						al_into.go_i_th (a_position)
						al_into.put_left (a_node)
					else
						al_into.extend (a_node)
					end
				end
				node_parent.force (a_parent, node_key (a_tree, a_node))
				al_t.set_roots (al_roots)
				changed
			end
		end

	tree_set_expanded (a_tree, a_node: INTEGER; a_on: BOOLEAN)
			-- The program's: silent (SW_TREE reports only the user's).
		do
			if attached {SW_TREE [INTEGER]} widget (a_tree) as al_t then
				reveal (a_tree, al_t, a_node)
				if a_on then
					al_t.expand_node (a_node)
				else
					al_t.collapse_node (a_node)
				end
				changed
			end
		end

	tree_is_expanded (a_tree, a_node: INTEGER): BOOLEAN
		do
			Result := attached {SW_TREE [INTEGER]} widget (a_tree) as al_t and then al_t.is_expanded (a_node)
		end

	tree_select (a_tree, a_node: INTEGER)
			-- Select silently, showing the node (its ancestors open).
		do
			if attached {SW_TREE [INTEGER]} widget (a_tree) as al_t then
				reveal (a_tree, al_t, a_node)
				al_t.select_node_quietly (a_node)
				changed
			end
		end

	tree_selected (a_tree: INTEGER): INTEGER
		do
			if attached {SW_TREE [INTEGER]} widget (a_tree) as al_t then
				Result := al_t.selected_node
			end
		end

feature -- Every widget

	set_enabled (an_id: INTEGER; a_on: BOOLEAN)
			-- A container switched off switches off every enabled widget it holds, and on
			-- again exactly those, as on GTK and AppKit: SW_WIDGET's own flag stops only the
			-- widget itself, so the example's buttons still answered under its print preview
			-- (found by the simple_shell#48 probe, 2026-11-12).
		local
			l_held: ARRAYED_LIST [SW_WIDGET]
		do
			if attached widget (an_id) as al_w then
				if not a_on then
					if not held_off.has (an_id) and then not al_w.sub_widgets.is_empty then
						create l_held.make (8)
						collect_enabled_below (al_w, l_held)
						across l_held as ic loop
							ic.set_enabled (False)
						end
						held_off.force (l_held, an_id)
					end
				elseif attached held_off.item (an_id) as al_held then
					across al_held as ic loop
						ic.set_enabled (True)
					end
					held_off.remove (an_id)
				end
				al_w.set_enabled (a_on)
				changed
			end
		end

	held_off: HASH_TABLE [ARRAYED_LIST [SW_WIDGET], INTEGER]
			-- By container: the widgets inside it its switching off switched off.
		once ("OBJECT")
			create Result.make (4)
		end

	collect_enabled_below (a_widget: SW_WIDGET; a_into: ARRAYED_LIST [SW_WIDGET])
			-- Every enabled widget below `a_widget', at any depth, into `a_into'.
		do
			across
				a_widget.sub_widgets as ic
			loop
				if ic.is_enabled then
					a_into.extend (ic)
				end
				collect_enabled_below (ic, a_into)
			end
		end

	is_enabled (an_id: INTEGER): BOOLEAN
		do
			Result := attached widget (an_id) as al_w and then al_w.is_enabled
		end

	set_visible (an_id: INTEGER; a_on: BOOLEAN)
			-- A widget hides or shows; a window is shown by opening it.
		do
			if attached widget (an_id) as al_w then
				al_w.set_visible (a_on)
				changed
			elseif attached windows.item (an_id) as al_win then
				if not a_on then
					if al_win.is_window_open then
						al_win.hide_window
					end
					hidden_windows.force (True, an_id)
				elseif al_win.is_window_open then
					al_win.show_window
					hidden_windows.remove (an_id)
				else
					window_show (an_id)
				end
			end
		end

	is_visible (an_id: INTEGER): BOOLEAN
			-- A widget not hidden; a window open.
		do
			if attached widget (an_id) as al_w then
				Result := al_w.is_visible
			elseif attached floats.item (an_id) as al_f then
				Result := al_f.is_open
			elseif attached windows.item (an_id) as al_win then
				Result := al_win.is_window_open and not hidden_windows.has (an_id)
			end
		end

	set_direction (an_id, a_direction: INTEGER)
			-- simple_gui's Direction_auto .. Direction_right_to_left are simple_widgets'
			-- Layout_inherit .. Layout_right_to_left.
		do
			if attached widget (an_id) as al_w then
				al_w.set_layout_direction (a_direction)
				changed
			elseif attached windows.item (an_id) as al_win then
				window_direction.force (a_direction, an_id)
				if attached al_win.root as al_root then
					al_root.set_layout_direction (a_direction)
				end
				changed
			end
		end

	set_accessible_label (an_id: INTEGER; a_text: POINTER)
		do
			if attached widget (an_id) as al_w then
				al_w.set_accessible_name (from_c (a_text))
			end
		end

	set_accessible_description (an_id: INTEGER; a_text: POINTER)
		do
			if attached widget (an_id) as al_w then
				al_w.set_accessible_description (from_c (a_text))
			end
		end

	widget_x (an_id: INTEGER): INTEGER
			-- Logical pixels from the content area's left edge.
		do
			if attached widget (an_id) as al_w and then attached content_origin (al_w) as al_o then
				Result := logical (al_w, al_w.x + margin_of (an_id) - al_o.x)
			end
		end

	widget_y (an_id: INTEGER): INTEGER
			-- Logical pixels from the content area's top edge.
		do
			if attached widget (an_id) as al_w and then attached content_origin (al_w) as al_o then
				Result := logical (al_w, al_w.y + margin_of (an_id) - al_o.y)
			end
		end

	accessible_role (an_id: INTEGER): POINTER
		do
			if attached widget (an_id) as al_w then
				if attached al_w.shared_role_name as al_shared then
					Result := c_text (al_shared)
				else
					Result := c_text (accessibility_names.role_name (al_w.accessible_role))
				end
			else
				Result := c_text ({STRING_32} "application")
			end
		end

feature -- Canvas

	canvas (a_width, a_height: INTEGER): INTEGER
		local
			l_c: SW_CANVAS
		do
			create l_c.make (a_height.max (1).to_double)
			l_c := l_c.with_min_size (a_width.max (1).to_double, a_height.max (1).to_double)
			Result := register (l_c)
			l_c.set_on_pointer (agent report_pointer (Result, ?, ?, ?, ?, ?))
			l_c.set_on_resize (agent report_resize (Result, ?, ?))
			l_c.set_on_key (agent report_key (Result, ?, ?))
			l_c.set_on_char (agent report_char (Result, ?))
		end

	canvas_present (an_id: INTEGER; a_cairo_surface: POINTER)
			-- Keep our own cairo reference to the finished image (the program keeps its own)
			-- and show it 1:1.
		local
			l_img: CAIRO_SURFACE
		do
			if attached {SW_CANVAS} widget (an_id) as al_c and then a_cairo_surface /= default_pointer then
				if presented.has (an_id) then
					c_surface_destroy (presented.item (an_id))
				end
				presented.force (c_surface_reference (a_cairo_surface), an_id)
				create l_img.make_from_handle (presented.item (an_id))
				if l_img.width > 0 and l_img.height > 0 then
					al_c.present_image (l_img, (l_img.width / al_c.width.max (1.0)).max (0.01))
				end
				changed
			end
		end

	drawn (a_width, a_height: INTEGER): INTEGER
			-- 1i: a GUI_SW_DRAWN_VIEW whose input becomes events 18 to 22, in logical pixels.
		local
			l_v: GUI_SW_DRAWN_VIEW
		do
			create l_v.make_view (device (a_width.max (1)).to_double, device (a_height.max (1)).to_double)
			Result := register (l_v)
			l_v.set_on_pointer (agent report_drawn_pointer (Result, ?, ?, ?, ?, ?))
			l_v.set_on_resize (agent report_resize (Result, ?, ?))
			l_v.set_on_key (agent report_drawn_key (Result, ?, ?))
			l_v.set_on_char (agent report_drawn_char (Result, ?))
			l_v.set_on_wheel (agent report_drawn_wheel (Result, ?))
			l_v.set_on_multi_press (agent report_drawn_multi (Result, ?, ?, ?))
			l_v.set_on_leave (agent report_drawn_leave (Result))
			l_v.on_hover_change.extend (agent (a_id: INTEGER; a_on: BOOLEAN)
				do
					if not a_on then
						report_drawn_leave (a_id)
					end
				end (Result, ?))
			l_v.on_focus_change.extend (agent (a_id: INTEGER; a_on: BOOLEAN)
				do
					push (22, a_id, a_on.to_integer, 0, 0)
				end (Result, ?))
			drawn_timers.force ([0, 0, {INTEGER_64} 0, {INTEGER_64} 0, {INTEGER_64} 0, 0], Result)
		end

	drawn_present (an_id: INTEGER; a_surface: POINTER; a_width, a_height: INTEGER)
			-- Keep a copy of the frame's top-left `a_width' by `a_height' device pixels, shown 1:1.
		local
			l_copy: POINTER
		do
			if attached {GUI_SW_DRAWN_VIEW} widget (an_id) as al_v and then a_surface /= default_pointer
				and then a_width > 0 and then a_height > 0
			then
				l_copy := c_copy_region (a_surface, a_width, a_height)
				if l_copy /= default_pointer then
					if presented.has (an_id) then
						c_surface_destroy (presented.item (an_id))
					end
					presented.force (l_copy, an_id)
					al_v.present_image (create {CAIRO_SURFACE}.make_from_handle (l_copy), 1.0)
					changed
				end
			end
		end

	drawn_set_cursor (an_id, a_kind: INTEGER)
		do
			if attached {GUI_SW_DRAWN_VIEW} widget (an_id) as al_v and then a_kind >= 0 and then a_kind <= 6 then
				al_v.set_hosted_cursor (a_kind)
			end
		end

	drawn_set_ticks (an_id, a_tick_ms, a_fast_ms: INTEGER)
			-- On the host windows' heartbeat and fast tick: see `check_drawn_timers'.
		local
			l_now: INTEGER_64
		do
			if attached drawn_timers.item (an_id) as al_t then
				l_now := clock.milliseconds
				al_t.tick_ms := a_tick_ms.max (0)
				al_t.fast_ms := a_fast_ms.max (0)
				al_t.next_tick := l_now + al_t.tick_ms
				al_t.next_fast := l_now + al_t.fast_ms
				pace_fast_timer
			end
		end

	drawn_arm_dwell (an_id, a_ms, a_serial: INTEGER)
		do
			if attached drawn_timers.item (an_id) as al_t then
				al_t.serial := a_serial
				if a_ms > 0 then
					al_t.dwell_due := clock.milliseconds + a_ms
				else
					al_t.dwell_due := 0
				end
				pace_fast_timer
			end
		end

	drawn_set_description (an_id: INTEGER; a_text: POINTER)
		do
			drawn_trees.force (from_c (a_text), an_id)
		end

	test_drawn_event (an_id, a_type, a_a, a_b, a_c: INTEGER)
		do
			push (a_type, an_id, a_a, a_b, a_c)
		end

	scale_factor (an_id: INTEGER): INTEGER
		do
			Result := scale (an_id).ceiling.max (1)
		end

	scale (an_id: INTEGER): REAL_64
			-- simple_widgets lays out in device pixels: one canvas unit per pixel, so the image
			-- the program draws at width x scale lands 1:1.
		do
			if attached {SW_CANVAS} widget (an_id) as al_c then
				Result := al_c.device_scale
			else
				Result := 1.0
			end
		end

	width (an_id: INTEGER): INTEGER
		do
			if attached widget (an_id) as al_w then
				Result := logical (al_w, (al_w.width - 2.0 * margin_of (an_id)).max (0.0))
			elseif attached windows.item (an_id) as al_win then
				Result := (al_win.win_w / dpi).rounded
			end
		end

	height (an_id: INTEGER): INTEGER
		do
			if attached widget (an_id) as al_w then
				Result := logical (al_w, (al_w.height - 2.0 * margin_of (an_id)).max (0.0))
			elseif attached windows.item (an_id) as al_win then
				Result := (al_win.win_h / dpi).rounded
			end
		end

feature -- Menus

	menu_new (a_title: POINTER): POINTER
		do
			menus.extend ([from_c (a_title), create {ARRAYED_LIST [TUPLE [text, shortcut: STRING_32; id, role: INTEGER; separator: BOOLEAN]]}.make (8)])
			Result := default_pointer + menus.count
		end

	menu_add_item (a_menu: POINTER; a_text, a_shortcut: POINTER; an_item_id, a_role: INTEGER)
		do
			if attached menu_of (a_menu) as al_m then
				al_m.items.extend ([from_c (a_text), from_c (a_shortcut), an_item_id, a_role, False])
			end
		end

	menu_set_title (a_menu: POINTER; a_title: POINTER)
		local
			i: INTEGER
		do
			i := menu_index (a_menu)
			if attached menu_of (a_menu) as al_m then
				al_m.title := from_c (a_title)
				across windows as ic loop
					if attached ic.menu_bar as al_bar and then i <= al_bar.labels.count then
						al_bar.set_title (i, al_m.title)
					end
				end
				changed
			end
		end

	menu_title (a_menu: POINTER): POINTER
		do
			if attached menu_of (a_menu) as al_m then
				Result := c_text (al_m.title)
			end
		end

	menu_set_item_text (an_item_id: INTEGER; a_text: POINTER)
			-- Menus are built on every open, so the next open shows it.
		do
			if attached menu_item (an_item_id) as al_i then
				al_i.text := from_c (a_text)
			end
		end

	menu_item_text (an_item_id: INTEGER): POINTER
		do
			if attached menu_item (an_item_id) as al_i then
				Result := c_text (al_i.text)
			end
		end

	menu_add_separator (a_menu: POINTER)
		do
			if attached menu_of (a_menu) as al_m then
				al_m.items.extend ([{STRING_32} "", {STRING_32} "", 0, 0, True])
			end
		end

	context_menu_new: POINTER
			-- A menu outside the bar, for one widget's right-click.
		do
			context_menus.extend ([{STRING_32} "", create {ARRAYED_LIST [TUPLE [text, shortcut: STRING_32; id, role: INTEGER; separator: BOOLEAN]]}.make (8)])
			Result := default_pointer + (Context_base + context_menus.count)
		end

	widget_set_context_menu (an_id: INTEGER; a_menu: POINTER)
			-- The widget's right-click menu is the model's items in place of the widget's own
			-- (SW's menu_extension, replacing), as AppKit's and GTK's context menus are.
		do
			if attached widget (an_id) as al_w then
				widget_context.force (menu_index (a_menu), an_id)
				al_w.set_menu_extension (agent fill_context (?, ?, ?, menu_index (a_menu)))
				al_w.set_menu_extension_replaces (True)
			end
		end

feature -- Dialogs

	open_file (a_window: INTEGER; a_title: POINTER; a_save: BOOLEAN; an_extensions: POINTER): POINTER
			-- The system's own Open or Save dialog (simple_shell), waited for (2026-11-11: they
			-- replaced simple_widgets' drawn sheets, as GTK and AppKit already use their own).
		do
			if a_save then
				Result := save_file_named (a_window, a_title, an_extensions, c_text (""))
			elseif attached open_dialog_answer (from_c (a_title), from_c (an_extensions)) as al_path then
				Result := c_text (al_path)
			end
		end

	message (a_window: INTEGER; a_title, a_text: POINTER; a_confirm: BOOLEAN): BOOLEAN
			-- simple_widgets' drawn dialog, waited for (W9).
		do
			if attached windows.item (a_window) as al_w then
				Result := al_w.ask ({SW_DIALOG}.Kind_info, from_c (a_title), from_c (a_text), a_confirm)
			end
		end

feature -- Appearance

	is_dark: BOOLEAN
		do
			if forced_dark_set then
				Result := forced_dark
			else
				Result := (create {SHELL_APPEARANCE}).system_prefers_dark
			end
		end

	system_color (a_role: INTEGER): INTEGER
			-- The theme's colors: 1 background, 2 text, 3 secondary text, 4 accent, 5 selection,
			-- 6 separator.
		local
			t: SW_THEME
			l_rgb: NATURAL_32
		do
			if is_high_contrast then
				t := contrast_theme
			elseif is_dark then
				create t.make_dark
			else
				create t.make_light
			end
			inspect a_role
			when 1 then l_rgb := t.background
			when 2 then l_rgb := t.ink
			when 3 then l_rgb := t.ink_muted
			when 4 then l_rgb := t.accent
			when 5 then l_rgb := t.wash_accent
			else l_rgb := t.outline
			end
			Result := (l_rgb & 0xFFFFFF).to_integer_32
		end

	set_dark (a_on: BOOLEAN)
			-- Tests: wear dark (or light) everywhere and report the change.
		do
			forced_dark_set := True
			forced_dark := a_on
			across windows as ic loop
				wear (ic)
			end
			push (10, 0, a_on.to_integer, 0, 0)
			changed
		end

	set_theme_color (a_role, a_rgb: INTEGER)
			-- 1w: the program's own color for the theme role `a_role' (1 background, 2 text,
			-- 3 secondary text, 4 accent, 5 selection, 6 separator); -1 gives the theme's
			-- back. Every window wears it at once. See `wear_theme_colors' for the one limit.
		do
			if a_role >= 1 and a_role <= 6 and then theme_overrides [a_role] /= a_rgb.max (-1) then
				theme_overrides [a_role] := a_rgb.max (-1)
				across windows as ic loop
					wear (ic)
				end
				changed
			end
		end

	is_high_contrast: BOOLEAN
			-- 1w: is the system's contrast setting on (or held on or off by the test door)?
		do
			if forced_contrast_set then
				Result := forced_contrast
			else
				Result := (create {SHELL_APPEARANCE}).system_high_contrast
			end
		end

	widget_set_reveal (an_id, a_effect: INTEGER; a_fraction: REAL_64; a_takes_input: BOOLEAN)
			-- 1x-b: simple_widgets shows the widget revealed (a fade multiplies its alpha, a
			-- slide or grow takes that share of its natural size and draws clipped in it),
			-- passing pointer hits to its parent without `a_takes_input'.
		local
			l_effect: INTEGER
		do
			if is_frame_ticking then
					-- noted before `changed', which renders at once
				frame_value_pending := True
				frame_value_mark := frames_rendered_total
			end
			l_effect := a_effect
			if l_effect > 1 and then not reveals_in_place (an_id) then
					-- the rule on all three: slides and grow reveal in a stack or as a window's
					-- content; elsewhere they fade
				l_effect := 1
			end
			if attached widget (an_id) as al_w then
				al_w.set_reveal (l_effect, a_fraction, a_takes_input)
				changed
			end
		end

	reveals_in_place (an_id: INTEGER): BOOLEAN
			-- Do slides and grow reveal widget `an_id' - in a stack, or as a window's content?
			-- Elsewhere they fade, as on GTK and AppKit (PROD and MACMINI, 2026-11-12).
		do
			if window_content.has_item (an_id) then
				Result := True
			elseif attached widget (an_id) as al_w and then attached al_w.parent as al_p then
				Result := stack_ids.has (items.index_of (al_p, 1))
			end
		end

	stack_ids: HASH_TABLE [BOOLEAN, INTEGER]
			-- The ids of the widgets `stack' made.
		once ("OBJECT")
			create Result.make (16)
		end

	widget_yield_focus (an_id: INTEGER)
			-- 1x-b: the main window's focus leaves the widget for the next in its ring.
		do
			if attached widget (an_id) as al_w and then attached open_window as al_win then
				al_win.yield_focus (al_w)
			end
		end

	test_reveal_shown (an_id: INTEGER): REAL_64
			-- 1x-b: the reveal simple_widgets shows the widget at; -1 when it is gone.
		do
			if attached widget (an_id) as al_w then
				Result := al_w.reveal
			else
				Result := -1.0
			end
		end

	test_extent (an_id: INTEGER; a_vertical: BOOLEAN): INTEGER
			-- 1x-b: the height (`a_vertical') or width the widget was laid out at; -1 when gone.
		do
			if attached widget (an_id) as al_w then
				if a_vertical then
					Result := al_w.height.rounded
				else
					Result := al_w.width.rounded
				end
			else
				Result := -1
			end
		end

	test_has_focus (an_id: INTEGER): INTEGER
			-- 1x-b: does the main window's focus sit on the widget or inside it? -1 when gone.
		do
			if attached widget (an_id) as al_w and then attached open_window as al_win then
				if attached al_win.focused as al_f and then al_win.is_within (al_f, al_w) then
					Result := 1
				end
			else
				Result := -1
			end
		end

	test_opacity_shown (an_id: INTEGER): REAL_64
			-- 1x: the opacity simple_widgets paints the widget at, a fade's share included; -1
			-- when it is gone.
		do
			if attached widget (an_id) as al_w then
				Result := al_w.painted_opacity
			else
				Result := -1.0
			end
		end

	test_pointer_reaches (an_id: INTEGER): INTEGER
			-- 1x: would a press at the middle of `an_id' reach it or something in it (a hit on
			-- a fully transparent widget passes to its parent)? -1 when it has no size or top.
		local
			l_top: SW_WIDGET
			l_hit: detachable SW_WIDGET
		do
			Result := -1
			if attached widget (an_id) as al_w and then al_w.width > 0.0 and then al_w.height > 0.0 then
				from
					l_top := al_w
				until
					not attached l_top.parent as al_up
				loop
					l_top := al_up
				end
				if attached open_window as al_win then
					l_hit := al_win.reachable_target (l_top.widget_at (al_w.x + al_w.width / 2.0, al_w.y + al_w.height / 2.0))
					Result := 0
					from
					until
						l_hit = Void or Result = 1
					loop
						if l_hit = al_w then
							Result := 1
						end
						l_hit := l_hit.parent
					end
				end
			end
		end

	test_frames (a_which: INTEGER): INTEGER
			-- 1x: frames counted at each tick: painted when a value set since the tick before
			-- was rendered before this one, missed when not; 2 the longest gap between painted
			-- frames and 4 their 95th-percentile gap (nearest rank; 0 with none yet), both in
			-- tenths of a millisecond, each frame stamped with the compositor vblank it made
			-- (the first at or after its drawing ended); 5 the 95th-percentile gap by tick
			-- time, the measure before vblank stamps (for the record); 3 resets.
		do
			inspect a_which
			when 0 then
				Result := frames_painted
			when 1 then
				Result := frames_missed
			when 2 then
				Result := frames_longest_gap
			when 4 then
				Result := percentile_95 (frame_gaps)
			when 5 then
				Result := percentile_95 (frame_tick_gaps)
			else
				frames_painted := 0
				frames_missed := 0
				frames_longest_gap := 0
				frames_last_painted_ms := 0
				frames_last_vblank_ms := 0.0
				frame_gaps.wipe_out
				frame_tick_gaps.wipe_out
			end
		end

	percentile_95 (a_gaps: ARRAYED_LIST [INTEGER]): INTEGER
			-- The 95th-percentile of `a_gaps' by nearest rank; 0 when empty.
		local
			l_sorted: ARRAYED_LIST [INTEGER]
			i, j, l_v: INTEGER
		do
			if not a_gaps.is_empty then
				l_sorted := a_gaps.twin
					-- insertion sort: a run holds about 130 gaps
				from i := 2 until i > l_sorted.count loop
					l_v := l_sorted.i_th (i)
					from j := i - 1 until j < 1 or else l_sorted.i_th (j) <= l_v loop
						l_sorted.put_i_th (l_sorted.i_th (j), j + 1)
						j := j - 1
					end
					l_sorted.put_i_th (l_v, j + 1)
					i := i + 1
				end
				Result := l_sorted.i_th ((0.95 * l_sorted.count).ceiling.max (1))
			end
		ensure
			none_is_zero: a_gaps.is_empty implies Result = 0
		end

	frame_tick_gaps: ARRAYED_LIST [INTEGER]
			-- The gaps between painted frames by tick time, in tenths of a millisecond (the
			-- measure before vblank stamps, kept for the record).
		once ("OBJECT")
			create Result.make (256)
		end

	note_frame_drawn
			-- A window finished drawing a frame now.
		do
			last_draw_end_ms := c_now_ms
		end

	last_draw_end_ms: REAL_64
			-- When a window last finished drawing a frame (high-resolution milliseconds).

	frames_last_vblank_ms: REAL_64
			-- The vblank the last painted frame made.

	c_now_ms: REAL_64
			-- Now, in the high-resolution milliseconds the frame stamps use.
		external "C inline use %"simple_shell.h%""
		alias "return shell_now_ms();"
		end

	c_vblank_made (a_ms: REAL_64): REAL_64
			-- The first compositor vblank at or after `a_ms' (high-resolution milliseconds): the
			-- vblank a frame whose drawing ended then made. `a_ms' itself when the compositor
			-- gives no timing. DwmGetCompositionTimingInfo is loaded at run time (the ISE target
			-- predates it); with no window it gives the compositor's own timing (Windows 8.1 on).
		external "C inline use %"simple_shell.h%", <dwmapi.h>, <math.h>"
		alias "[
			typedef HRESULT (WINAPI *sg_dwm_timing_fn)(HWND, DWM_TIMING_INFO*);
			static sg_dwm_timing_fn l_timing = 0;
			static int l_looked = 0;
			DWM_TIMING_INFO l_info;
			LARGE_INTEGER l_freq;
			double l_vblank, l_period;
			if (!l_looked) {
				HMODULE l_dwm = LoadLibraryW(L"dwmapi.dll");
				l_looked = 1;
				if (l_dwm) l_timing = (sg_dwm_timing_fn)(void*)GetProcAddress(l_dwm, "DwmGetCompositionTimingInfo");
			}
			if (!l_timing) return $a_ms;
			ZeroMemory(&l_info, sizeof(l_info));
			l_info.cbSize = sizeof(l_info);
			if (FAILED(l_timing(NULL, &l_info)) || l_info.qpcRefreshPeriod == 0) return $a_ms;
			QueryPerformanceFrequency(&l_freq);
			l_vblank = (double)l_info.qpcVBlank * 1000.0 / (double)l_freq.QuadPart;
			l_period = (double)l_info.qpcRefreshPeriod * 1000.0 / (double)l_freq.QuadPart;
			return l_vblank + ceil(($a_ms - l_vblank) / l_period) * l_period;
		]"
		end

	frame_gaps: ARRAYED_LIST [INTEGER]
			-- The gaps between painted frames since the last reset, in tenths of a millisecond.
		once ("OBJECT")
			create Result.make (256)
		end

	frames_painted, frames_missed, frames_longest_gap: INTEGER
			-- 1x frame counts (`test_frames').

	frames_last_painted_ms: INTEGER_64
			-- When the last painted frame was counted.

	frame_value_pending: BOOLEAN
			-- Was a value set since the last tick?

	frame_value_mark: INTEGER
			-- `frames_rendered_total' when that value was set.

	frames_rendered_total: INTEGER
			-- Frames the open windows have rendered.
		do
			across windows as ic loop
				if attached ic as al_w then
					Result := Result + al_w.frames_rendered
				end
			end
		end

	count_frame
			-- A tick: count the value set since the tick before as painted or missed.
			-- A painted frame is stamped with the vblank its drawing made: a draw that ends
			-- after a vblank takes the next one, so a late frame shows as a two-frame gap.
		local
			l_now: INTEGER_64
			l_vblank: REAL_64
			l_gap: INTEGER
		do
			if frame_value_pending then
				l_now := clock.milliseconds
				if frames_rendered_total > frame_value_mark then
					frames_painted := frames_painted + 1
					l_vblank := c_vblank_made (last_draw_end_ms)
					if frames_last_vblank_ms > 0.0 then
						l_gap := ((l_vblank - frames_last_vblank_ms) * 10.0).rounded
						frames_longest_gap := frames_longest_gap.max (l_gap)
						frame_gaps.extend (l_gap)
					end
					frames_last_vblank_ms := l_vblank
					if frames_last_painted_ms > 0 then
						frame_tick_gaps.extend (((l_now - frames_last_painted_ms) * 10).to_integer_32)
					end
					frames_last_painted_ms := l_now
				else
					frames_missed := frames_missed + 1
				end
				frame_value_pending := False
			end
		end

	test_set_high_contrast (a_on: BOOLEAN)
			-- Tests: behave as if the contrast setting were `a_on', and report the change.
		local
			l_was: BOOLEAN
		do
			l_was := is_high_contrast
			forced_contrast_set := True
			forced_contrast := a_on
			if a_on /= l_was then
				across windows as ic loop
					wear (ic)
				end
				push (10, 0, is_dark.to_integer, 0, 0)
				changed
			end
		ensure then
			held: is_high_contrast = a_on
		end

feature -- Own appearance (1w)

	widget_set_style (an_id: INTEGER; a_spec: POINTER)
			-- 1w: the widget wears the style in `a_spec' (see GUI_STYLE.flat); an empty spec
			-- gives its own look back. UNITS: the spec's lengths are logical pixels and its
			-- type size is points; simple_widgets takes device pixels and a type size in theme
			-- units before the text scale (a point is 4/3 of one).
		local
			l_style: SW_WIDGET_STYLE
			i: INTEGER
		do
			if attached widget (an_id) as al_w then
				style_fonts.remove (an_id)
				if a_spec = default_pointer or else from_c (a_spec).is_empty then
					al_w.set_style (Void)
				else
					create l_style.make
					across from_c (a_spec).split ('%/31/') as ic loop
						i := ic.index_of ('=', 1)
						if i > 1 then
							put_style_part (l_style, an_id, ic.substring (1, i - 1), ic.substring (i + 1, ic.count))
						end
					end
					al_w.set_style (l_style)
				end
				changed
			end
		end

	widget_style_supported (an_id: INTEGER; a_property: POINTER): BOOLEAN
			-- 1w: does the widget show the part of a style the key `a_property' sets?
		local
			l_part: INTEGER
		do
			if a_property /= default_pointer and then attached widget (an_id) as al_w then
				l_part := style_part (from_c (a_property))
				Result := l_part > 0 and then al_w.shows_style (l_part)
			end
		end

	font_load (a_path: POINTER): POINTER
			-- 1w: add the faces in the font file at `a_path' for this process only, and answer
			-- the family names it carries (parted by unit separators); empty when the file
			-- cannot be loaded. Loading a file again only names its families again.
			-- HOW: simple_shaping's private font load (GDI, which every drawn text goes
			-- through here); each window's shaping kit then forgets its font answers, so a
			-- widget already styled with the family is set in it at the next draw.
		local
			l_path, l_names: STRING_32
			l_loaded: BOOLEAN
		do
			create l_names.make_empty
			if a_path /= default_pointer and then not from_c (a_path).is_empty then
				l_path := from_c (a_path)
				if loaded_fonts.has (l_path) then
					l_loaded := True
				elseif font_kit.facade.load_font_file (l_path) > 0 then
					loaded_fonts.extend (l_path)
					l_loaded := True
					across windows as ic loop
						if attached ic.shaping as al_kit then
							al_kit.facade.forget_font_answers
						end
					end
					changed
				end
				if l_loaded then
					across font_kit.facade.font_file_families (l_path) as ic loop
						if not l_names.is_empty then
							l_names.append_character ('%/31/')
						end
						l_names.append (ic)
					end
				end
			end
			Result := c_text (l_names)
		end

	font_family_available (a_name: POINTER): BOOLEAN
			-- 1w: can text be set in a font called `a_name' as itself: a generic name (system,
			-- sans-serif, serif, monospace), a family installed on the machine, or one
			-- `font_load' added?
		local
			l_name: STRING_32
		do
			if a_name /= default_pointer then
				l_name := from_c (a_name)
				if l_name.is_case_insensitive_equal_general ("system") or l_name.is_case_insensitive_equal_general ("sans-serif")
					or l_name.is_case_insensitive_equal_general ("serif") or l_name.is_case_insensitive_equal_general ("monospace") then
					Result := True
				elseif not l_name.is_empty then
					Result := font_kit.facade.has_font_family (l_name)
				end
			end
		end

feature -- Test doors (act on the widget as a user would)

	test_style_value (an_id: INTEGER; a_key: POINTER): POINTER
			-- Tests: what the widget shows now for the style key `a_key', written as the spec
			-- writes it; empty when the widget has no style, the style does not set the key
			-- or the widget does not show it. It is read from the style the widget's own
			-- drawing takes (`SW_WIDGET.shown_style'), in the spec's units again.
		local
			l_key, l_answer: STRING_32
			l_part: INTEGER
		do
			create l_answer.make_empty
			if a_key /= default_pointer and then attached widget (an_id) as al_w then
				l_key := from_c (a_key)
				l_part := style_part (l_key)
				if l_part > 0 and then attached al_w.shown_style (l_part) as al_s then
					if l_key.same_string_general ("fg") then
						l_answer := style_hex (al_s.foreground)
					elseif l_key.same_string_general ("bg") then
						l_answer := style_hex (al_s.background)
					elseif l_key.same_string_general ("placeholder") then
						l_answer := style_hex (al_s.placeholder)
					elseif l_key.same_string_general ("selection") then
						l_answer := style_hex (al_s.selection)
					elseif l_key.same_string_general ("border_color") then
						if al_s.has_border_color then
							l_answer := style_hex (al_s.border_color)
						end
					elseif l_key.same_string_general ("shadow_color") then
						if al_s.has_shadow_color then
							l_answer := style_hex (al_s.shadow_color)
						end
					elseif l_key.same_string_general ("font") then
						if attached style_fonts.item (an_id) as al_word then
							l_answer := al_word.twin
						end
					elseif l_key.same_string_general ("size") then
						l_answer := style_number (al_s.size * 0.75)
					elseif l_key.same_string_general ("weight") then
						l_answer.append_integer (al_s.weight)
					elseif l_key.same_string_general ("italic") then
						l_answer.append_integer (al_s.is_italic.to_integer)
					elseif l_key.same_string_general ("pad") then
						l_answer := style_number (al_s.padding_top / dpi) + "," + style_number (al_s.padding_end / dpi)
							+ "," + style_number (al_s.padding_bottom / dpi) + "," + style_number (al_s.padding_start / dpi)
					elseif l_key.same_string_general ("border") then
						l_answer := style_number (al_s.border_width / dpi)
					elseif l_key.same_string_general ("radius") then
						l_answer := style_number (al_s.radius / dpi)
					elseif l_key.same_string_general ("shadow") then
						l_answer := style_number (al_s.shadow_x / dpi) + "," + style_number (al_s.shadow_y / dpi)
							+ "," + style_number (al_s.shadow_blur / dpi) + "," + style_number (al_s.shadow_alpha * 100.0)
					elseif l_key.same_string_general ("scroll") then
						l_answer.append_integer (al_s.scroll_bars)
					end
				end
			end
			Result := c_text (l_answer)
		end

feature -- Test doors (act on the widget as a user would)

	test_click (an_id: INTEGER)
		do
			if attached {GUI_SW_SPLIT_BUTTON} widget (an_id) as al_s then
				al_s.main_part.perform_click
				changed
			elseif attached widget (an_id) as al_w then
				al_w.perform_click
				changed
			end
		end

	test_click_header (a_table, a_column: INTEGER)
			-- As a click on the header: reported with the next direction, not sorted.
		do
			if attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (a_table) as al_g then
				report_header (a_table, a_column, not (al_g.indicator_column = a_column and not al_g.indicator_descending))
			end
		end

	test_expand (a_tree, a_node: INTEGER; a_on: BOOLEAN)
			-- As the user's click on the triangle: reported.
		do
			if attached {SW_TREE [INTEGER]} widget (a_tree) as al_t then
				reveal (a_tree, al_t, a_node)
				if a_on then
					al_t.user_expand (a_node)
				else
					al_t.user_collapse (a_node)
				end
				changed
			end
		end

	test_type (an_id: INTEGER; a_text: POINTER)
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t and then not al_t.is_read_only then
				al_t.type_text (from_c (a_text))
				changed
			end
		end

	test_type_into_code (an_id: INTEGER; a_text: POINTER)
			-- Type at the caret as the user would: Return and Tab through the editor's own
			-- handling.
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c and then not al_c.is_read_only then
				al_c.type_code (from_c (a_text))
				changed
			end
		end

	test_bracket_tint_at (an_id, a_position: INTEGER): BOOLEAN
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				Result := al_c.is_bracket_tinted (a_position)
			end
		end

	test_fill_event_queue (a_count: INTEGER)
			-- The queue is a list here, unbounded: every one is kept.
		local
			i: INTEGER
		do
			from i := 1 until i > a_count loop
				push (0, 0, 0, 0, 0)
				i := i + 1
			end
		end

	test_bracket_key (an_id: INTEGER)
			-- The key that goes to the matching bracket, as the user would press it (event 56).
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				al_c.press_bracket_key
			end
		end

	test_code_key (an_id, an_action: INTEGER; a_shift: BOOLEAN; a_text: POINTER)
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				al_c.press_code_key (an_action, a_shift, from_c (a_text))
			end
		end

	clock_ms: REAL_64
			-- 1v-e-6: the performance counter, through simple_shell.
		do
			Result := desktop.now_ms
		end

	code_first_visible_line (an_id: INTEGER): INTEGER
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				Result := al_c.first_visible_line
			end
		end

	code_last_visible_line (an_id: INTEGER): INTEGER
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				Result := al_c.last_visible_line
			end
		end

	test_caret_gesture (an_id, a_gesture, a_position: INTEGER)
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				al_c.tell_caret_gesture (a_gesture, a_position)
			end
		end

	test_completion_key (an_id, a_key: INTEGER)
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				al_c.press_completion_key (a_key)
			end
		end

	test_press_completion (an_id, a_row: INTEGER)
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c and then al_c.is_completion_shown then
				al_c.press_completion_row (a_row)
			end
		end

	test_completions_shown (an_id: INTEGER): BOOLEAN
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				Result := al_c.is_completion_shown
			end
		end

	test_press_fold_marker (an_id, a_line: INTEGER)
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				al_c.press_fold_marker (a_line)
			end
		end

	test_fold_key (an_id: INTEGER; a_unfold: BOOLEAN)
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				al_c.press_fold_key (a_unfold)
			end
		end

	test_line_is_shown (an_id, a_line: INTEGER): BOOLEAN
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				Result := al_c.is_line_shown (a_line)
			end
		end

	test_code_arrow_key (an_id, a_direction: INTEGER)
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c then
				inspect a_direction
				when 1 then
					al_c.handle_key (38, False)
				when 2 then
					al_c.handle_key (40, False)
				when 3 then
					al_c.handle_key (37, False)
				else
					al_c.handle_key (39, False)
				end
				changed
			end
		end

	test_caret_to (an_id, a_line, a_column: INTEGER)
			-- Move the caret as the user would (event 52).
		do
			if attached {GUI_SW_CODE_AREA} widget (an_id) as al_c
				and then 1 <= a_line and then a_line <= al_c.code_line_count and then a_column >= 1
			then
				al_c.move_caret_to (a_line, a_column)
				changed
			end
		end

	test_choose (an_id, a_row: INTEGER)
			-- As the user choosing a row, a table row, a tree node or a tab: reported.
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l and then a_row >= 1 and then a_row <= al_l.count then
				al_l.select_row (a_row)
			elseif attached {SW_GRID_VIEW} widget (an_id) as al_gv and then al_gv.is_shown (a_row) then
				al_gv.press_item (a_row, False)
			elseif attached {GUI_SW_PATH_CONTROL} widget (an_id) as al_p and then a_row >= 1 and then a_row <= al_p.parts.count then
				al_p.press_part (a_row)
			elseif attached {SW_SIDEBAR} widget (an_id) as al_side and then a_row >= 1 and then a_row <= al_side.page_count then
				al_side.press_page (a_row)
			elseif attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (an_id) as al_g and then a_row >= 1 and then a_row <= al_g.rows.count then
				quiet := quiet + 1
				al_g.select_model_row_quietly (0, False)
				quiet := quiet - 1
				al_g.select_model_row (a_row)
			elseif attached {SW_TREE [INTEGER]} widget (an_id) as al_t then
				reveal (an_id, al_t, a_row)
				al_t.select_node (a_row)
			elseif attached {SW_TABS} widget (an_id) as al_tabs and then a_row >= 1 and then a_row <= al_tabs.pages.count then
				al_tabs.select_tab (a_row)
			elseif attached {GUI_SW_DROPDOWN} widget (an_id) as al_d and then a_row >= 1 and then a_row <= al_d.options.count then
				al_d.pick (a_row)
			elseif attached {SW_RADIO_GROUP} widget (an_id) as al_r and then a_row >= 1 and then a_row <= al_r.options.count then
				if al_r.selected_index /= a_row then
					al_r.select_index (a_row)
				end
			elseif attached {SW_SEGMENTED} widget (an_id) as al_s and then a_row >= 1 and then a_row <= al_s.segments.count then
				if al_s.selected_index /= a_row then
					al_s.select_segment (a_row)
				end
			elseif attached {GUI_SW_COMBO_BOX} widget (an_id) as al_c and then a_row >= 1 and then a_row <= al_c.options.count then
				al_c.choose_option (a_row)
			end
			changed
		end

	test_set_number (an_id, a_value: INTEGER)
			-- As the user committing `a_value': reported when it changes the value.
		do
			if attached {GUI_SW_SPIN_BOX} widget (an_id) as al_s and then a_value /= al_s.value then
				al_s.set_value (a_value)
				report_number (an_id, al_s.value)
				changed
			end
		end

	test_slide (an_id, a_value: INTEGER)
			-- As the user moving the slider to `a_value'.
		do
			if attached {GUI_SW_SLIDER} widget (an_id) as al_s and then al_s.value /= a_value then
				al_s.set_value (a_value)
				report_slider (an_id, al_s.fraction)
				changed
			end
		end

	test_set_date (an_id, a_value: INTEGER)
			-- As the user entering a date (y*10000 + m*100 + d) or a time (h*60 + m): one report.
		do
			if date_picker_value (an_id) /= a_value then
				date_picker_set (an_id, a_value)
				push (2, an_id, a_value, 0, 0)
			end
		end

	test_set_color (an_id, a_rgb: INTEGER)
		do
			if color_chooser_value (an_id) /= a_rgb then
				color_chooser_set (an_id, a_rgb)
				push (2, an_id, a_rgb, 0, 0)
			end
		end

	test_type_combo (an_id: INTEGER; a_text: POINTER)
			-- As the user typing `a_text' and pressing Return.
		do
			if attached {GUI_SW_COMBO_BOX} widget (an_id) as al_c then
				al_c.set_text (from_c (a_text))
				al_c.commit
				changed
			end
		end

	test_toggle_expander (an_id: INTEGER)
			-- As the user clicking the expander's title.
		do
			if attached {GUI_SW_EXPANDER} widget (an_id) as al_e then
				al_e.set_expanded (not al_e.is_expanded)
				changed
			end
		end

	test_auto_cancel_dialogs (a_ms: INTEGER)
		do
			auto_cancel_ms := a_ms.max (0)
		end

	auto_cancel_ms: INTEGER
			-- Tests: cancel each dialog this long after it opens (0: never).

	test_dismiss_popover (an_id: INTEGER)
			-- As the user clicking outside: closed (17).
		do
			if attached open_window as al_w and then attached al_w.popover_shown then
				al_w.close_sheet
				changed
			end
		end

	test_type_tokens (an_id: INTEGER; a_text: POINTER)
			-- As the user typing "a, b" then Return: one change.
		do
			if attached {GUI_SW_TOKEN_FIELD} widget (an_id) as al_t and then al_t.add_typed (from_c (a_text)) > 0 then
				al_t.report
				changed
			end
		end

	test_rate (an_id, a_value: INTEGER)
		do
			if attached {SW_RATING} widget (an_id) as al_r and then al_r.value /= a_value then
				al_r.set_value (a_value)
				report_number (an_id, a_value)
				changed
			end
		end

	test_menu (an_item_id: INTEGER)
		do
			choose_menu_item (an_item_id)
		end

	test_request_close (a_window: INTEGER)
			-- As the title bar's close button: the main window through simple_shell (event 66,
			-- then 6); a floating window reports 6 as its panel's close button does.
		do
			if floats.has (a_window) then
				push (6, a_window, 0, 0, 0)
			elseif attached windows.item (a_window) as al_w and then al_w.is_window_open then
				al_w.request_close
			end
		end

	test_focus (an_id: INTEGER)
			-- As a click on it: the main window's focus moves to the widget.
		do
			if attached widget (an_id) as al_w and then al_w.accepts_focus and then attached open_window as al_win then
				al_win.give_focus (al_w)
				changed
			end
		end

	test_edit_enabled (a_role: INTEGER): BOOLEAN
			-- As the Edit menu would show it: the main window's focus can carry the role out.
		do
			if attached open_window as al_win then
				Result := al_win.can_edit_focused (a_role)
			end
		end

	test_context_menu (an_id, an_item_id: INTEGER): BOOLEAN
			-- Choose item `an_item_id' from the widget's right-click menu: False when that menu
			-- has no such item (or the widget has none).
		do
			if widget_context.has (an_id) and then attached menu_of (default_pointer + widget_context.item (an_id)) as al_m then
				across al_m.items as ic loop
					if not Result and then not ic.separator and then ic.id = an_item_id then
						Result := True
					end
				end
				if Result then
					push (5, 0, an_item_id, 0, 0)
				end
			end
		end

	snapshot (an_id: INTEGER; a_path: POINTER): BOOLEAN
			-- The window's last frame as a PNG; a floating window's from its own panel.
		do
			if attached floats.item (an_id) as al_f then
				if al_f.is_open then
					al_f.render
					Result := al_f.export_frame_png (from_c (a_path))
				end
			elseif attached windows.item (an_id) as al_w then
				al_w.request_render
				Result := al_w.write_frame (from_c (a_path))
			end
		end

	describe_accessibility (a_window: INTEGER): POINTER
		do
			if attached windows.item (a_window) as al_w then
				Result := c_text (with_drawn_trees (al_w.describe_accessibility))
			end
		end

feature {NONE} -- Drawn views (1i)

	drawn_timers: HASH_TABLE [TUPLE [tick_ms, fast_ms: INTEGER; next_tick, next_fast, dwell_due: INTEGER_64; serial: INTEGER], INTEGER]
			-- Each drawn view's ticks (0: off) and their next times, and its pending dwell shot
			-- (`dwell_due' 0: none), on `clock'.
		once ("OBJECT")
			create Result.make (2)
		end

	drawn_trees: HASH_TABLE [STRING_32, INTEGER]
			-- Each drawn view's hosted accessibility tree, as GUI_DRAWN last gave it.
		once ("OBJECT")
			create Result.make (2)
		end

	clock: SIMPLE_MONOTONIC_CLOCK
		once ("OBJECT")
			create Result
		end

	fast_timer_ms: INTEGER
			-- The host windows' fast timer as last set (0: off).

	Dwell_pace_ms: INTEGER = 50

	Busy_pace_ms: INTEGER = 80
			-- How often a busy button's spinner turns.
			-- How finely a pending dwell shot is timed.

	pace_fast_timer
			-- Run the host windows' fast timer at the finest pace any drawn view needs (its fast
			-- tick, or `Dwell_pace_ms' while a dwell shot is pending); off when none needs it.
		local
			l_ms: INTEGER
		do
			if not busy_buttons.is_empty then
				l_ms := Busy_pace_ms
			end
			if not spinning.is_empty then
				l_ms := Spin_pace_ms
			end
			across drawn_timers as ic loop
				if ic.fast_ms > 0 and then (l_ms = 0 or else ic.fast_ms < l_ms) then
					l_ms := ic.fast_ms
				end
				if ic.dwell_due > 0 and then (l_ms = 0 or else Dwell_pace_ms < l_ms) then
					l_ms := Dwell_pace_ms
				end
			end
			if l_ms /= fast_timer_ms then
				fast_timer_ms := l_ms
				across windows as ic loop
					if attached ic as al_w and then al_w.is_window_open then
						if l_ms > 0 then
							al_w.set_fast_timer (l_ms)
						else
							al_w.kill_fast_timer
						end
					end
				end
			end
		end

	on_window_tick
			-- A host window's heartbeat.
		do
			check_drawn_timers
		end

	on_window_shell_event (a_type, a_x, a_y: INTEGER)
			-- A host window's fast tick (25) times the drawn views too.
		do
			if a_type = 25 then
				check_drawn_timers
				if not busy_buttons.is_empty and then attached open_window as al_w and then al_w.is_window_open then
					al_w.request_render
				end
				render_spinning
			elseif a_type = {SHELL_EVENTS}.Event_frame_tick then
					-- 1x: a frame tick, `a_x' milliseconds after the last
				count_frame
				push (62, 0, a_x, 0, 0)
			elseif a_type = {SHELL_TRAY}.Event_click and then a_x = {SHELL_TRAY}.Click_balloon and then last_notification_id > 0 then
				push (28, 0, last_notification_id, 0, 0)
			end
		end

	check_drawn_timers
			-- Each drawn view's ticks and dwell shot that are due (event 23), once each.
		local
			l_now: INTEGER_64
			l_dwell_fired: BOOLEAN
		do
			l_now := clock.milliseconds
			across drawn_timers as ic loop
				if ic.tick_ms > 0 and then l_now >= ic.next_tick then
					ic.next_tick := l_now + ic.tick_ms
					push (23, @ic.key, 0, 0, 0)
				end
				if ic.fast_ms > 0 and then l_now >= ic.next_fast then
					ic.next_fast := l_now + ic.fast_ms
					push (23, @ic.key, 1, 0, 0)
				end
				if ic.dwell_due > 0 and then l_now >= ic.dwell_due then
					ic.dwell_due := 0
					l_dwell_fired := True
					push (23, @ic.key, 2, ic.serial, 0)
				end
			end
			if l_dwell_fired then
				pace_fast_timer
			end
		end

	report_drawn_pointer (an_id, a_kind: INTEGER; a_x, a_y: REAL_64; a_button, a_modifiers: INTEGER)
		do
			if attached widget (an_id) as al_w then
				push (18, an_id, logical (al_w, a_x), logical (al_w, a_y), a_kind + a_button * 16 + a_modifiers * 256)
			end
		end

	report_drawn_multi (an_id, a_count: INTEGER; a_x, a_y: REAL_64)
			-- A double (5) or triple (6) press of the primary button.
		do
			if attached {GUI_SW_DRAWN_VIEW} widget (an_id) as al_v then
				push (18, an_id, logical (al_v, a_x), logical (al_v, a_y),
					(if a_count >= 3 then 6 else 5 end) + 16 + al_v.modifiers * 256)
			end
		end

	report_drawn_leave (an_id: INTEGER)
		do
			if attached {GUI_SW_DRAWN_VIEW} widget (an_id) as al_v then
				push (18, an_id, logical (al_v, al_v.last_x), logical (al_v, al_v.last_y), 4 + al_v.modifiers * 256)
			end
		end

	report_drawn_wheel (an_id, a_delta: INTEGER)
		do
			if attached {GUI_SW_DRAWN_VIEW} widget (an_id) as al_v then
				push (19, an_id, logical (al_v, al_v.last_x), logical (al_v, al_v.last_y), a_delta)
			end
		end

	report_drawn_key (an_id, a_vk: INTEGER; a_shift: BOOLEAN)
			-- A key down, as a GDK keyval (the shared vocabulary GUI_DRAWN maps back); keys it
			-- has no word for are left out.
		do
			if gdk_keyval (a_vk) > 0 and then attached {GUI_SW_DRAWN_VIEW} widget (an_id) as al_v then
				push (20, an_id, gdk_keyval (a_vk), 1, al_v.modifiers * 256)
			end
		end

	report_drawn_char (an_id, a_code: INTEGER)
			-- A character: text, and Return, Tab, Backspace and Escape as WM_CHAR gives them;
			-- the other control characters (Ctrl+C is 3) are shortcuts, not text.
		do
			if a_code >= 32 or else a_code = 8 or else a_code = 9 or else a_code = 13 or else a_code = 27 then
				push (21, an_id, a_code, 0, 0)
			end
		end

	gdk_keyval (a_vk: INTEGER): INTEGER
			-- The GDK keyval for Windows virtual key `a_vk' (GUI_DRAWN.virtual_key's inverse); 0 for none.
		do
			inspect a_vk
			when 65 .. 90 then Result := a_vk + 0x20
			when 48 .. 57 then Result := a_vk
			when 32 then Result := 0x20
			when 13 then Result := 0xFF0D
			when 27 then Result := 0xFF1B
			when 9 then Result := 0xFF09
			when 8 then Result := 0xFF08
			when 46 then Result := 0xFFFF
			when 45 then Result := 0xFF63
			when 36 then Result := 0xFF50
			when 35 then Result := 0xFF57
			when 33 then Result := 0xFF55
			when 34 then Result := 0xFF56
			when 37 then Result := 0xFF51
			when 38 then Result := 0xFF52
			when 39 then Result := 0xFF53
			when 40 then Result := 0xFF54
			when 112 .. 123 then Result := 0xFFBE + a_vk - 112
			when 16 then Result := 0xFFE1
			when 17 then Result := 0xFFE3
			when 18 then Result := 0xFFE9
			when 188 then Result := 0x2C
			when 190 then Result := 0x2E
			when 189 then Result := 0x2D
			when 187 then Result := 0x3D
			else
			end
		ensure
			non_negative: Result >= 0
		end

	with_drawn_trees (a_text: STRING_32): STRING_32
			-- `a_text' with each drawn view's hosted tree under its "group:" line (the tree's
			-- first line, the hosted window itself, left out), as on GTK and macOS.
		local
			l_lines: LIST [STRING_32]
			l_indent: INTEGER
			l_line: STRING_32
		do
			create Result.make (a_text.count + 256)
			l_lines := a_text.split ('%N')
			across l_lines as ic loop
				Result.append (ic)
				Result.append_character ('%N')
				across drawn_trees as al_tree loop
					if attached widget (@al_tree.key) as al_v and then not al_v.is_hidden then
						l_line := ic.twin
						l_indent := l_line.count
						l_line.left_adjust
						l_indent := l_indent - l_line.count
						if l_line.same_string ({STRING_32} "group: " + al_v.accessible_name) then
							across al_tree.split ('%N') as al_sub loop
								if @al_sub.cursor_index > 1 then
									l_line := al_sub.twin
									l_line.left_adjust
									if not l_line.is_empty then
										Result.append (create {STRING_32}.make_filled (' ', l_indent + 2))
										Result.append (l_line)
										Result.append_character ('%N')
									end
								end
							end
						end
					end
				end
			end
			if not a_text.is_empty and then a_text [a_text.count] /= '%N' and then Result.count > 0 then
				Result.remove_tail (1)
			end
		end

	c_copy_region (a_surface: POINTER; a_width, a_height: INTEGER): POINTER
			-- A new image surface: the top-left `a_width' by `a_height' of `a_surface' (an image
			-- surface, possibly larger), or null.
		external
			"C inline use <cairo.h>"
		alias
			"[
				cairo_surface_t *s = (cairo_surface_t *) $a_surface, *c;
				cairo_t *cr;
				int w = $a_width, h = $a_height;
				if (cairo_surface_get_type(s) != CAIRO_SURFACE_TYPE_IMAGE) return NULL;
				cairo_surface_flush(s);
				if (w > cairo_image_surface_get_width(s)) w = cairo_image_surface_get_width(s);
				if (h > cairo_image_surface_get_height(s)) h = cairo_image_surface_get_height(s);
				if (w <= 0 || h <= 0) return NULL;
				c = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, h);
				cr = cairo_create(c);
				cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
				cairo_set_source_surface(cr, s, 0, 0);
				cairo_paint(cr);
				cairo_destroy(cr);
				return c;
			]"
		end

feature {NONE} -- Dialogs and help tips (1u)

	Help_tip_ms: INTEGER = 6000
			-- How long a help tip stays.

	dialog_pressed (a_dialog, n: INTEGER)
			-- The user pressed button `n': 48.
		do
			push (48, a_dialog, n, 0, 0)
		end

	later_presses: ARRAYED_LIST [TUPLE [dialog, n: INTEGER; due: INTEGER_64]]
			-- Tests: presses due later.
		once ("OBJECT")
			create Result.make (2)
		end

	help_tip_window: detachable GUI_SW_WINDOW
			-- The window the last help tip was shown in.

	help_tip_due: INTEGER_64
			-- When it comes down (0: none up).

	ms_to_next_deadline: INTEGER_64
			-- Milliseconds until the soonest later press or tip expiry, a large number if none.
		local
			l_now: INTEGER_64
		do
			Result := {INTEGER_64} 1_000_000
			l_now := clock.milliseconds
			across later_presses as ic loop
				Result := Result.min (ic.due - l_now)
			end
			if help_tip_due > 0 then
				Result := Result.min (help_tip_due - l_now)
			end
		end

	fire_due_dialog_deadlines
			-- Presses a test asked for, and the help tip's end.
		local
			l_now: INTEGER_64
			l_due: ARRAYED_LIST [TUPLE [dialog, n: INTEGER; due: INTEGER_64]]
		do
			l_now := clock.milliseconds
			if not later_presses.is_empty then
				create l_due.make (0)
				across later_presses as ic loop
					if l_now >= ic.due then
						l_due.extend (ic)
					end
				end
				across l_due as ic loop
					later_presses.prune_all (ic)
					test_press_dialog_button (ic.dialog, ic.n)
				end
			end
			if help_tip_due > 0 and then l_now >= help_tip_due then
				help_tip_due := 0
				if attached help_tip_window as al_win then
					al_win.hide_help_tip
					changed
				end
			end
		end

feature {NONE} -- Timers, shortcuts and full screen (1m)

	gui_timers: HASH_TABLE [TUPLE [ms: INTEGER; repeat: BOOLEAN; due: INTEGER_64], INTEGER]
			-- Each running timer: its interval, whether it repeats, and when it is next due.
		once ("OBJECT")
			create Result.make (4)
		end

	ms_to_next_timer: INTEGER
			-- Milliseconds until the soonest timer is due (0 if one is due; a large number if none).
		local
			l_now, l_soonest: INTEGER_64
		do
			l_soonest := {INTEGER_64} 1_000_000
			l_now := clock.milliseconds
			across gui_timers as ic loop
				l_soonest := l_soonest.min (ic.due - l_now)
			end
			l_soonest := l_soonest.min (ms_to_next_deadline)
			Result := l_soonest.max (0).min (1_000_000).to_integer_32
		ensure
			non_negative: Result >= 0
		end

	fire_due_timers
			-- Event 24 for every timer due; a repeating one is due again an interval later.
		local
			l_now: INTEGER_64
			l_done: ARRAYED_LIST [INTEGER]
		do
			fire_due_dialog_deadlines
			if not gui_timers.is_empty then
				l_now := clock.milliseconds
				create l_done.make (0)
				across gui_timers as ic loop
					if l_now >= ic.due then
						push (24, 0, @ic.key, 0, 0)
						if ic.repeat then
							ic.due := (ic.due + ic.ms).max (l_now + 1)
						else
							l_done.extend (@ic.key)
						end
					end
				end
				across l_done as ic loop
					gui_timers.remove (ic)
				end
			end
		end

	window_shortcuts: HASH_TABLE [INTEGER, STRING_32]
			-- Each window shortcut id, by "window:shortcut" (lower case), for the test driver.
		once ("OBJECT")
			create Result.make (4)
		end

	shortcut_key (a_window: INTEGER; a_spec: READABLE_STRING_GENERAL): STRING_32
			-- "window:shortcut", the shortcut in lower case.
		do
			create Result.make (16)
			Result.append_integer (a_window)
			Result.append_character (':')
			Result.append_string_general (a_spec)
			Result.to_lower
		end

	fullscreen_saves: HASH_TABLE [MANAGED_POINTER, INTEGER]
			-- Each full-screen window: its style and rectangle before, to go back to.
		once ("OBJECT")
			create Result.make (2)
		end

	c_enter_fullscreen (a_hwnd, a_save: POINTER)
			-- Save the window style and rectangle in `a_save' (24 bytes), then make it a
			-- borderless window over its whole monitor.
		external
			"C inline use <windows.h>"
		alias
			"[
				HWND h = (HWND) $a_hwnd;
				LONG_PTR *saved = (LONG_PTR *) $a_save;
				RECT *r = (RECT *) ((char *) $a_save + 8);
				MONITORINFO mi;
				saved[0] = GetWindowLongPtrW(h, GWL_STYLE);
				GetWindowRect(h, r);
				mi.cbSize = sizeof mi;
				GetMonitorInfoW(MonitorFromWindow(h, MONITOR_DEFAULTTONEAREST), &mi);
				SetWindowLongPtrW(h, GWL_STYLE, (saved[0] & ~WS_OVERLAPPEDWINDOW) | WS_POPUP);
				SetWindowPos(h, HWND_TOP, mi.rcMonitor.left, mi.rcMonitor.top,
					mi.rcMonitor.right - mi.rcMonitor.left, mi.rcMonitor.bottom - mi.rcMonitor.top,
					SWP_FRAMECHANGED | SWP_NOOWNERZORDER);
			]"
		end

	c_leave_fullscreen (a_hwnd, a_save: POINTER)
			-- Give the window back the style and rectangle `a_save' holds.
		external
			"C inline use <windows.h>"
		alias
			"[
				HWND h = (HWND) $a_hwnd;
				LONG_PTR *saved = (LONG_PTR *) $a_save;
				RECT *r = (RECT *) ((char *) $a_save + 8);
				SetWindowLongPtrW(h, GWL_STYLE, saved[0]);
				SetWindowPos(h, NULL, r->left, r->top, r->right - r->left, r->bottom - r->top,
					SWP_FRAMECHANGED | SWP_NOZORDER | SWP_NOOWNERZORDER);
			]"
		end

feature {NONE} -- Icons, badges and busy buttons (1n)

	glyph_of (a_name: READABLE_STRING_GENERAL): INTEGER
			-- The SW glyph drawing icon `a_name' (GUI_ICON's vocabulary); 0 for none.
		local
			l_names: ARRAY [STRING_32]
			l_glyphs: ARRAY [INTEGER]
			i: INTEGER
		do
			l_names := (create {GUI_ICON}).names
			l_glyphs := <<1, 2, 3, 4, 5, 7, 8, 6, 7, 5, 9, 10, 11, 12, 13, 14, 29, 30, 31, 32, 33, 34, 35, 15,
				16, 17, 18, 19, 20, 21, 22, 25, 36, 26, 28, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48>>
			from i := l_names.lower until i > l_names.upper or Result > 0 loop
				if l_names [i].same_string_general (a_name) then
					Result := l_glyphs [i - l_names.lower + l_glyphs.lower]
				end
				i := i + 1
			end
		ensure
			known: Result >= 0 and Result <= {SW_PAINTER}.Glyph_last
		end

	button_icons: HASH_TABLE [STRING_32, INTEGER]
			-- Each button's icon name, for the test driver.
		once ("OBJECT")
			create Result.make (8)
		end

	busy_buttons: HASH_TABLE [INTEGER, INTEGER]
			-- The buttons busy now.
		once ("OBJECT")
			create Result.make (2)
		end

	menu_item_icons: HASH_TABLE [INTEGER, INTEGER]
			-- Each menu item's glyph, by item id.
		once ("OBJECT")
			create Result.make (4)
		end

	widget_badges: HASH_TABLE [STRING_32, INTEGER]
			-- Each badged widget's text ("" for a dot), by widget id.
		once ("OBJECT")
			create Result.make (4)
		end

	apply_badges (a_w: GUI_SW_WINDOW)
			-- `a_w''s badges: one for each badged widget in it.
		do
			a_w.widget_badges.wipe_out
			across widget_badges as ic loop
				if attached widget (@ic.key) as al_w and then window_of (al_w) = a_w then
					a_w.set_widget_badge (al_w, ic)
				end
			end
		end

feature {NONE} -- Feedback (1o)

	spinning: HASH_TABLE [INTEGER, INTEGER]
			-- The spinners turning now.
		once ("OBJECT")
			create Result.make (2)
		end

	info_bars: HASH_TABLE [TUPLE [label: SW_LABEL; actions: SW_ROW; close: SW_BUTTON], INTEGER]
			-- Each info bar's parts, by its id.
		once ("OBJECT")
			create Result.make (2)
		end

	notify_tray: CELL [detachable SHELL_TRAY]
			-- The icon desktop notices come from, once one was sent.
		once ("OBJECT")
			create Result.put (Void)
		end

	app_title: CELL [STRING_32]
			-- The application's name (`init'), the tray icon's tooltip.
		once ("OBJECT")
			create Result.put ({STRING_32} "simple_gui")
		end

	last_notification_id: INTEGER
			-- The id of the notice the balloon shows now; a click on it reports this.

	Spin_pace_ms: INTEGER = 80
			-- How often a spinner turns.

	render_spinning
			-- A frame for each window with a spinner turning in it.
		do
			across spinning as ic loop
				if attached widget (@ic.key) as al_s and then attached window_of (al_s) as al_w and then al_w.is_window_open then
					al_w.request_render
				end
			end
		end

feature {NONE} -- Forms (1p)

	field_errors: HASH_TABLE [STRING_32, INTEGER]
			-- Each field's error message, drawn as a note once the field is in a window.
		once ("OBJECT")
			create Result.make (2)
		end

	field_suggestions: HASH_TABLE [ARRAYED_LIST [STRING_32], INTEGER]
			-- The suggestions shown last under each field.
		once ("OBJECT")
			create Result.make (2)
		end

	date_time_parts: HASH_TABLE [TUPLE [first, second: SW_WIDGET], INTEGER]
		once ("OBJECT")
			create Result.make (2)
		end

	date_time_values: HASH_TABLE [TUPLE [date, time: INTEGER], INTEGER]
		once ("OBJECT")
			create Result.make (2)
		end

	range_parts: HASH_TABLE [TUPLE [low, high: GUI_SW_SLIDER], INTEGER]
		once ("OBJECT")
			create Result.make (2)
		end

	apply_notes (a_w: GUI_SW_WINDOW)
			-- `a_w''s field errors, as notes under their fields.
		do
			a_w.widget_notes.wipe_out
			across field_errors as ic loop
				if attached widget (@ic.key) as al_w and then window_of (al_w) = a_w then
					a_w.set_widget_note (al_w, ic)
				end
			end
		end

	report_reveal (an_id: INTEGER; a_shown: BOOLEAN)
		do
			push (12, an_id, if a_shown then 1 else 0 end, 0, 0)
		end

	fill_suggestion (an_id, i: INTEGER)
			-- The user chose suggestion `i': it fills the field, and the field reports the change.
		do
			if attached {SW_TEXT_BOX} widget (an_id) as al_t and then attached field_suggestions.item (an_id) as al_items
				and then al_items.valid_index (i)
			then
				al_t.set_text (al_items [i])
				push (2, an_id, 0, 0, 0)
				changed
			end
		end

	month_name (a_month: INTEGER): STRING_32
		do
			inspect a_month
			when 1 then Result := "January"
			when 2 then Result := "February"
			when 3 then Result := "March"
			when 4 then Result := "April"
			when 5 then Result := "May"
			when 6 then Result := "June"
			when 7 then Result := "July"
			when 8 then Result := "August"
			when 9 then Result := "September"
			when 10 then Result := "October"
			when 11 then Result := "November"
			else Result := "December"
			end
		end

	month_picked (an_id, a_month: INTEGER)
		do
			if attached date_time_values.item (an_id) as al_v then
				al_v.date := (al_v.date // 10000) * 10000 + a_month * 100 + 1
				if quiet = 0 then
					push (2, an_id, al_v.date // 100, 0, 0)
				end
			end
		end

	year_changed (an_id, a_year: INTEGER)
		do
			if attached date_time_values.item (an_id) as al_v then
				al_v.date := a_year * 10000 + (al_v.date // 100 \\ 100) * 100 + 1
				if quiet = 0 then
					push (2, an_id, al_v.date // 100, 0, 0)
				end
			end
		end

	date_part_changed (an_id, y, m, d: INTEGER)
		do
			if attached date_time_values.item (an_id) as al_v then
				al_v.date := y * 10000 + m * 100 + d
				if quiet = 0 then
					push (2, an_id, al_v.date, al_v.time, 0)
				end
			end
		end

	time_part_changed (an_id, h, m: INTEGER)
		do
			if attached date_time_values.item (an_id) as al_v then
				al_v.time := h * 60 + m
				if quiet = 0 then
					push (2, an_id, al_v.date, al_v.time, 0)
				end
			end
		end

	range_moved (an_id: INTEGER; a_low_moved: BOOLEAN; a_value: REAL_64)
			-- Keep low <= high (the thumb moved stops at the other), and report both.
		do
			if quiet = 0 and then attached range_parts.item (an_id) as al_p then
				if al_p.low.value > al_p.high.value then
					if a_low_moved then
						quietly (agent (al_p.low).set_value (al_p.high.value))
					else
						quietly (agent (al_p.high).set_value (al_p.low.value))
					end
				end
				push (2, an_id, al_p.low.value, al_p.high.value, 0)
			end
		end

	c_caps_lock_on: INTEGER
		external "C inline use <windows.h>"
		alias "return (GetKeyState (VK_CAPITAL) & 1) ? 1 : 0;"
		end

feature {NONE} -- Pick and drop (1q)

	pick_source: INTEGER
			-- The widget a pick lifted from; 0 when none is on.

	pick_mode: INTEGER

	pick_token: STRING_32
			-- What SW carries for a pick; the pebble itself stays in Eiffel's GUI_APPLICATION.
		once ("OBJECT")
			Result := {STRING_32} "sg-pebble"
		end

	pick_ok: HASH_TABLE [INTEGER, INTEGER]
			-- The targets Eiffel named for the pick on now.
		once ("OBJECT")
			create Result.make (4)
		end

	pick_modes: HASH_TABLE [INTEGER, INTEGER]
			-- Each source's pick mode, by widget id.
		once ("OBJECT")
			create Result.make (4)
		end

	pick_menu_window: detachable GUI_SW_WINDOW
			-- The window showing a menu-mode pick's menu.

	pick_begin (a_source, a_mode, a_row: INTEGER)
		do
			pick_clear
			pick_source := a_source
			pick_mode := a_mode
			push (30, a_source, a_row, 0, 0)
		end

	pick_clear
		do
			pick_source := 0
			pick_mode := 0
			pick_ok.wipe_out
			pick_menu_window := Void
		ensure
			none: pick_source = 0 and pick_ok.is_empty
		end

	pick_started (a_source, a_mode: INTEGER; a_by_row: BOOLEAN; a_x, a_y: REAL_64): detachable ANY
			-- SW asks for the source's pebble: report event 30 and carry the token.
		local
			l_row: INTEGER
		do
			if a_by_row then
				l_row := row_at_point (a_source, a_x, a_y)
			end
			pick_begin (a_source, a_mode, l_row)
			Result := pick_token
		end

	pick_accepts (a_target: INTEGER; a_pebble: ANY; a_x, a_y: REAL_64): BOOLEAN
		do
			Result := a_pebble = pick_token and then pick_source > 0 and then pick_ok.has (a_target)
		end

	pick_received (a_target: INTEGER; a_pebble: ANY; a_x, a_y: REAL_64)
		do
			if pick_accepts (a_target, a_pebble, a_x, a_y) then
				push (31, a_target, row_at_point (a_target, a_x, a_y), 0, 0)
				pick_clear
			end
		end

	pick_chosen (a_target: INTEGER)
			-- A target chosen from the menu mode's menu.
		do
			if pick_source > 0 then
				push (31, a_target, 0, 0, 0)
				pick_clear
			end
		end

	pick_cancelled
			-- SW_WINDOW's notice: the pick ended with the pebble going nowhere.
		do
			if pick_source > 0 and then pick_menu_window = Void then
				push (32, pick_source, 0, 0, 0)
				pick_clear
			end
		end

	check_pick_menu
			-- A menu-mode menu closed with no choice is a cancel.
		do
			if pick_source > 0 and then attached pick_menu_window as al_w and then al_w.open_popup = Void then
				push (32, pick_source, 0, 0, 0)
				pick_clear
			end
		end

	dock_frames: HASH_TABLE [TUPLE [x, y, w, h: INTEGER], STRING_32]
			-- Each panel's floating frame by key, logical units relative to the dock's window.
		once ("OBJECT")
			create Result.make (2)
		end

	dock_float_now (a_dock: INTEGER; a_host: SW_DOCK_HOST; an_index: INTEGER)
			-- Tear the panel out into a floating window at its frame (the first time, over the
			-- middle of the window at its docked size).
		local
			l_key, l_title: STRING_32
			l_rect: TUPLE [rx, ry, rw, rh: REAL_64]
			l_float: SW_FLOATING_WINDOW
			x, y, w, h: INTEGER
		do
			if attached open_window as al_win and then al_win.is_window_open then
				l_key := a_host.panels.i_th (an_index).key.twin
				l_title := a_host.panels.i_th (an_index).title.twin
				l_rect := a_host.zone_rect (a_host.panels.i_th (an_index).zone)
				if attached dock_frames.item (l_key) as al_f and then al_f.w > 0 and then al_f.h > 0 then
					x := device (al_f.x).max (0); y := device (al_f.y).max (0); w := device (al_f.w); h := device (al_f.h)
				else
					w := l_rect.rw.truncated_to_integer.max (320)
					h := l_rect.rh.truncated_to_integer.max (200) + 32
					x := ((al_win.win_w - w) // 2).max (0); y := ((al_win.win_h - h) // 2).max (0)
					dock_frames.force ([logical (a_host, x), logical (a_host, y), logical (a_host, w), logical (a_host, h)], l_key)
				end
				a_host.float_panel (an_index)
				l_float := al_win.float_widget (a_host.panels.i_th (an_index).content, l_title, al_win.win_x + x, al_win.win_y + y, w, h)
				if l_float.is_open then
					l_float.set_on_close_request (agent dock_float_closed (a_dock, l_key))
					dock_floats.force (l_float, l_key)
				else
					a_host.redock_panel (an_index)
				end
			end
		end

	dock_floats: HASH_TABLE [SW_FLOATING_WINDOW, STRING_32]
			-- The floating window of each floating panel, by key.
		once ("OBJECT")
			create Result.make (2)
		end

	dock_redock_now (a_host: SW_DOCK_HOST; an_index: INTEGER)
		local
			l_key: STRING_32
		do
			l_key := a_host.panels.i_th (an_index).key.twin
			if attached open_window as al_win and then attached dock_floats.item (l_key) as al_f then
				dock_floats.remove (l_key)
				al_win.dock_floating (a_host, l_key, al_f)
			elseif a_host.is_floating (an_index) then
				a_host.redock_panel (an_index)
			end
		end

	dock_float_requested (a_dock, an_index: INTEGER)
			-- The user's double click on a tab or title bar: float it, 38 (index, 1).
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h and then not al_h.is_floating (an_index) then
				dock_quiet := dock_quiet + 1
				dock_float_now (a_dock, al_h, an_index)
				dock_quiet := dock_quiet - 1
				dock_settled (a_dock, al_h)
				if al_h.is_floating (an_index) then
					push (38, a_dock, an_index, 1, 0)
				end
			end
		end

	dock_float_closed (a_dock: INTEGER; a_key: STRING_32)
			-- The user closed a floating panel's window: it docks again, 38 (index, 0).
		local
			l_index: INTEGER
		do
			if attached {SW_DOCK_HOST} widget (a_dock) as al_h then
				l_index := al_h.panel_by_key (a_key)
				if l_index > 0 and then al_h.is_floating (l_index) then
					dock_quiet := dock_quiet + 1
					dock_redock_now (al_h, l_index)
					dock_quiet := dock_quiet - 1
					dock_settled (a_dock, al_h)
					push (38, a_dock, l_index, 0, 0)
				end
			end
		end

	dock_zone (a_side: INTEGER): INTEGER
			-- simple_gui's side (1 left, 2 right, 3 top, 4 bottom) as SW_DOCK_HOST's zone.
		do
			inspect a_side
			when 1 then Result := {SW_DOCK_HOST}.Zone_west
			when 2 then Result := {SW_DOCK_HOST}.Zone_east
			when 3 then Result := {SW_DOCK_HOST}.Zone_north
			else Result := {SW_DOCK_HOST}.Zone_south
			end
		end

	dock_side (a_zone: INTEGER): INTEGER
		do
			if a_zone = {SW_DOCK_HOST}.Zone_west then Result := 1
			elseif a_zone = {SW_DOCK_HOST}.Zone_east then Result := 2
			elseif a_zone = {SW_DOCK_HOST}.Zone_north then Result := 3
			else Result := 4
			end
		end

	dock_quiet: INTEGER
			-- Above 0 while the program changes a dock: its layout notice is not the user's.

	dock_wanted: HASH_TABLE [INTEGER, INTEGER]
			-- Sides' sizes the program asked for and the host has not taken yet (dock * 8 + side).
		once ("OBJECT")
			create Result.make (4)
		end

	dock_seen: HASH_TABLE [TUPLE [fractions: ARRAY [REAL_64]; folded: ARRAY [BOOLEAN]; actives: ARRAY [INTEGER]; hidden: ARRAY [BOOLEAN]], INTEGER]
			-- Each dock's state as last reported, to tell what the user changed.
		once ("OBJECT")
			create Result.make (2)
		end

	dock_state (a_host: SW_DOCK_HOST): TUPLE [fractions: ARRAY [REAL_64]; folded: ARRAY [BOOLEAN]; actives: ARRAY [INTEGER]; hidden: ARRAY [BOOLEAN]]
		local
			z: INTEGER
		do
			Result := [create {ARRAY [REAL_64]}.make_filled (0.0, 1, 4), create {ARRAY [BOOLEAN]}.make_filled (False, 1, 4),
				create {ARRAY [INTEGER]}.make_filled (0, 1, 4), create {ARRAY [BOOLEAN]}.make_filled (False, 1, 4)]
			from z := 1 until z > 4 loop
				Result.fractions [z] := a_host.fraction (z)
				Result.folded [z] := a_host.is_collapsed (z)
				Result.actives [z] := a_host.active_panel (z)
				Result.hidden [z] := a_host.is_auto_hide (z)
				z := z + 1
			end
		end

	dock_settled (a_dock: INTEGER; a_host: SW_DOCK_HOST)
			-- The program's change is done: it is the state to compare the user's against.
		do
			dock_seen.force (dock_state (a_host), a_dock)
			changed
		end

	dock_apply_sizes (a_dock: INTEGER; a_host: SW_DOCK_HOST)
			-- Give the host the sizes asked for, once it is laid out.
		local
			s, l_zone: INTEGER
			l_extent, l_fraction: REAL_64
		do
			from s := 1 until s > 4 loop
				if dock_wanted.has (a_dock * 8 + s) then
					l_zone := dock_zone (s)
					if l_zone = a_host.Zone_west or l_zone = a_host.Zone_east then
						l_extent := a_host.width
					else
						l_extent := a_host.height
					end
					if l_extent > 0 then
						l_fraction := (device (dock_wanted.item (a_dock * 8 + s)) / l_extent).max (a_host.Min_fraction).min (a_host.Max_fraction)
						dock_quiet := dock_quiet + 1
						a_host.set_fraction (l_zone, l_fraction)
						dock_quiet := dock_quiet - 1
						dock_wanted.remove (a_dock * 8 + s)
					end
				end
				s := s + 1
			end
			dock_seen.force (dock_state (a_host), a_dock)
		end

	dock_layout_changed (a_dock: INTEGER)
			-- SW_DOCK_HOST's notice: when the user (not the program) changed it, report what
			-- changed: 35 a zone's size, 36 a fold, 37 the panel a tabbed zone shows.
		local
			l_now: like dock_state
			z: INTEGER
		do
			if dock_quiet = 0 and then attached {SW_DOCK_HOST} widget (a_dock) as al_h then
				l_now := dock_state (al_h)
				if attached dock_seen.item (a_dock) as al_was then
					from z := 1 until z > 4 loop
						if l_now.fractions [z] /= al_was.fractions [z] then
							push (35, a_dock, dock_side (z), dock_size (a_dock, dock_side (z)), 0)
						end
						if l_now.folded [z] /= al_was.folded [z] then
							push (36, a_dock, dock_side (z), l_now.folded [z].to_integer, 0)
						end
						if l_now.hidden [z] /= al_was.hidden [z] then
							push (39, a_dock, dock_side (z), l_now.hidden [z].to_integer, 0)
						end
						if l_now.actives [z] /= al_was.actives [z] and then l_now.actives [z] > 0 and then al_h.is_tabbed (z) then
							push (37, a_dock, dock_side (z), l_now.actives [z], 0)
						end
						z := z + 1
					end
				end
				dock_seen.force (l_now, a_dock)
			end
		end

	row_at_point (an_id: INTEGER; a_x, a_y: REAL_64): INTEGER
			-- The list row, the tree's node number or the token (1q-c) under window point
			-- (`a_x', `a_y'); 0 for none or another kind of widget.
		local
			r: INTEGER
		do
			if attached {GUI_SW_TOKEN_FIELD} widget (an_id) as al_t then
				Result := al_t.token_at (a_x, a_y)
			elseif attached {SW_LIST} widget (an_id) as al_list then
				Result := al_list.row_at (a_y)
			elseif attached {SW_TREE [INTEGER]} widget (an_id) as al_tree then
				r := al_tree.row_at (a_y)
				if r > 0 then
					Result := al_tree.visible.i_th (r).node
				end
			end
		end

feature {NONE} -- Reference pills (1l)

	pills: HASH_TABLE [TUPLE [code, tip: STRING_32; corner: INTEGER], INTEGER]
			-- Each widget's pill, by widget id.
		once ("OBJECT")
			create Result.make (8)
		end

	pills_are_shown: BOOLEAN

	apply_all_pills
		do
			across windows as ic loop
				if attached ic as al_w then
					apply_pills (al_w)
				end
			end
		end

	apply_pills (a_w: GUI_SW_WINDOW)
			-- `a_w''s reference marks: one for each pill whose widget is in it (simple_widgets'
			-- corners are numbered as simple_gui's).
		do
			a_w.clear_reference_marks
			across pills as ic loop
				if attached widget (@ic.key) as al_w and then window_of (al_w) = a_w then
					a_w.add_reference_mark (al_w, ic.code, ic.tip, ic.corner)
				end
			end
			a_w.set_reference_marks_shown (pills_are_shown)
			apply_badges (a_w)
			apply_notes (a_w)
			if a_w.is_window_open then
				a_w.request_render
			end
		end

	window_of (a_widget: SW_WIDGET): detachable GUI_SW_WINDOW
			-- The window `a_widget' is in, if any.
		local
			l_top: SW_WIDGET
		do
			from
				l_top := a_widget
			until
				not attached l_top.parent as al_up
			loop
				l_top := al_up
			end
			across windows as ic until attached Result loop
				if attached ic as al_win and then al_win.root = l_top then
					Result := al_win
				end
			end
		end

feature {NONE} -- Own appearance (1w)

	style_fonts: HASH_TABLE [STRING_32, INTEGER]
			-- The `font' word each styled widget was given, by widget number: what
			-- `test_style_value' answers ("system", not the face that stands for it here).
		once ("OBJECT")
			create Result.make (8)
		end

	font_kit: SW_SHAPING
			-- The backend's own door to the fonts: it loads font files and answers which
			-- families exist, with or without a window open.
		once ("OBJECT")
			create Result.make
		end

	loaded_fonts: ARRAYED_LIST [STRING_32]
			-- The font files `font_load' has added, as their paths were given.
		once ("OBJECT")
			create Result.make (2)
			Result.compare_objects
		end

	style_hex (a_rgb: NATURAL_32): STRING_32
			-- `a_rgb' (0xRRGGBB) as a spec writes a color: six lowercase hex digits.
		do
			Result := (a_rgb & 0xFFFFFF).to_hex_string.substring (3, 8).as_lower
		ensure
			six_digits: Result.count = 6
		end

	style_part (a_key: READABLE_STRING_GENERAL): INTEGER
			-- The SW_WIDGET_STYLE part the spec key `a_key' sets; 0 for a key nobody knows.
		do
			if a_key.same_string ("fg") then
				Result := {SW_WIDGET_STYLE}.Part_foreground
			elseif a_key.same_string ("bg") then
				Result := {SW_WIDGET_STYLE}.Part_background
			elseif a_key.same_string ("placeholder") then
				Result := {SW_WIDGET_STYLE}.Part_placeholder
			elseif a_key.same_string ("selection") then
				Result := {SW_WIDGET_STYLE}.Part_selection
			elseif a_key.same_string ("font") then
				Result := {SW_WIDGET_STYLE}.Part_family
			elseif a_key.same_string ("size") then
				Result := {SW_WIDGET_STYLE}.Part_size
			elseif a_key.same_string ("weight") then
				Result := {SW_WIDGET_STYLE}.Part_weight
			elseif a_key.same_string ("italic") then
				Result := {SW_WIDGET_STYLE}.Part_italic
			elseif a_key.same_string ("pad") then
				Result := {SW_WIDGET_STYLE}.Part_padding
			elseif a_key.same_string ("border") or a_key.same_string ("border_color") then
				Result := {SW_WIDGET_STYLE}.Part_border
			elseif a_key.same_string ("radius") then
				Result := {SW_WIDGET_STYLE}.Part_radius
			elseif a_key.same_string ("shadow") or a_key.same_string ("shadow_color") then
				Result := {SW_WIDGET_STYLE}.Part_shadow
			elseif a_key.same_string ("scroll") then
				Result := {SW_WIDGET_STYLE}.Part_scroll_bars
			end
		ensure
			a_part_or_none: Result >= 0 and Result <= {SW_WIDGET_STYLE}.Part_scroll_bars
		end

	put_style_part (a_style: SW_WIDGET_STYLE; an_id: INTEGER; a_key, a_value: STRING_32)
			-- Set on `a_style' what the spec pair `a_key'=`a_value' says. A value that is
			-- not what the key takes is left out, as the specification asks.
		local
			l_rgb, l_whole: INTEGER
			l_n: ARRAYED_LIST [REAL_64]
		do
			l_rgb := style_color (a_value)
			l_n := style_numbers (a_value)
			if l_n.count = 1 then
				l_whole := l_n.first.rounded
			end
			if a_key.same_string_general ("fg") then
				if l_rgb >= 0 then
					a_style.set_foreground (l_rgb.to_natural_32)
				end
			elseif a_key.same_string_general ("bg") then
				if l_rgb >= 0 then
					a_style.set_background (l_rgb.to_natural_32)
				end
			elseif a_key.same_string_general ("placeholder") then
				if l_rgb >= 0 then
					a_style.set_placeholder (l_rgb.to_natural_32)
				end
			elseif a_key.same_string_general ("selection") then
				if l_rgb >= 0 then
					a_style.set_selection (l_rgb.to_natural_32)
				end
			elseif a_key.same_string_general ("border_color") then
				if l_rgb >= 0 then
					a_style.set_border_color (l_rgb.to_natural_32)
				end
			elseif a_key.same_string_general ("shadow_color") then
				if l_rgb >= 0 then
					a_style.set_shadow_color (l_rgb.to_natural_32)
				end
			elseif a_key.same_string_general ("font") then
				if not a_value.is_empty then
					style_fonts.force (a_value, an_id)
					if a_value.is_case_insensitive_equal_general ("system") or a_value.is_case_insensitive_equal_general ("sans-serif") then
						a_style.set_face ({SW_PAINTER}.Role_ui, "")
					elseif a_value.is_case_insensitive_equal_general ("serif") then
						a_style.set_face ({SW_PAINTER}.Role_body, "")
					elseif a_value.is_case_insensitive_equal_general ("monospace") then
						a_style.set_face ({SW_PAINTER}.Role_mono, "")
					else
						a_style.set_face (0, a_value)
					end
				end
			elseif a_key.same_string_general ("size") then
				if l_n.count = 1 and then l_n.first > 0.0 then
					a_style.set_size (l_n.first * 4.0 / 3.0)
				end
			elseif a_key.same_string_general ("weight") then
				if l_n.count = 1 and then l_whole >= 1 and then l_whole <= 1000 then
					a_style.set_weight (l_whole)
				end
			elseif a_key.same_string_general ("italic") then
				a_style.set_italic (a_value.same_string_general ("1"))
			elseif a_key.same_string_general ("pad") then
				if l_n.count = 4 then
					a_style.set_padding (l_n [1].max (0.0) * dpi, l_n [2].max (0.0) * dpi, l_n [3].max (0.0) * dpi, l_n [4].max (0.0) * dpi)
				end
			elseif a_key.same_string_general ("border") then
				if l_n.count = 1 then
					a_style.set_border (l_n.first.max (0.0) * dpi)
				end
			elseif a_key.same_string_general ("radius") then
				if l_n.count = 1 then
					a_style.set_radius (l_n.first.max (0.0) * dpi)
				end
			elseif a_key.same_string_general ("shadow") then
				if l_n.count = 4 then
					a_style.set_shadow (l_n [1] * dpi, l_n [2] * dpi, l_n [3].max (0.0) * dpi, (l_n [4] / 100.0).max (0.0).min (1.0))
				end
			elseif a_key.same_string_general ("scroll") then
				if l_n.count = 1 and then a_style.is_scroll_bar_kind (l_whole) then
					a_style.set_scroll_bars (l_whole)
				end
			end
		end

	style_color (a_value: READABLE_STRING_32): INTEGER
			-- `a_value' (six hex digits) as 0xRRGGBB; -1 when it is anything else.
		local
			i, l_digit: INTEGER
			c: CHARACTER_32
		do
			if a_value.count = 6 then
				from
					i := 1
				until
					i > 6 or Result < 0
				loop
					c := a_value [i]
					if c >= '0' and c <= '9' then
						l_digit := c.code - ('0').code
					elseif c >= 'a' and c <= 'f' then
						l_digit := c.code - ('a').code + 10
					elseif c >= 'A' and c <= 'F' then
						l_digit := c.code - ('A').code + 10
					else
						l_digit := -1
					end
					if l_digit < 0 then
						Result := -1
					else
						Result := Result * 16 + l_digit
					end
					i := i + 1
				end
			else
				Result := -1
			end
		ensure
			a_color_or_none: Result >= -1 and Result <= 0xFFFFFF
		end

	style_numbers (a_value: READABLE_STRING_32): ARRAYED_LIST [REAL_64]
			-- The numbers in `a_value', parted by commas; empty when any part is not one.
		local
			l_bad: BOOLEAN
		do
			create Result.make (4)
			across a_value.split (',') as ic loop
				if ic.is_real_64 then
					Result.extend (ic.to_real_64)
				else
					l_bad := True
				end
			end
			if l_bad then
				Result.wipe_out
			end
		end

	style_number (a_value: REAL_64): STRING_32
			-- `a_value' as a spec writes it: at most two decimals, no trailing zeros
			-- ("15.5", "14", "-2").
		local
			l_hundredths, l_fraction: INTEGER_64
		do
			l_hundredths := (a_value.abs * 100.0).rounded_real_64.truncated_to_integer_64
			create Result.make (8)
			if a_value < 0.0 and l_hundredths > 0 then
				Result.append_character ('-')
			end
			Result.append_integer_64 (l_hundredths // 100)
			l_fraction := l_hundredths \\ 100
			if l_fraction > 0 then
				Result.append_character ('.')
				if l_fraction \\ 10 = 0 then
					Result.append_integer_64 (l_fraction // 10)
				else
					if l_fraction < 10 then
						Result.append_character ('0')
					end
					Result.append_integer_64 (l_fraction)
				end
			end
		ensure
			never_empty: not Result.is_empty
		end

feature {NONE} -- State

	items: ARRAYED_LIST [detachable SW_WIDGET]
			-- Every widget by id (a window's slot is Void).
		once ("OBJECT")
			create Result.make (64)
		end

	windows: HASH_TABLE [GUI_SW_WINDOW, INTEGER]
		once ("OBJECT")
			create Result.make (4)
		end

	window_content: HASH_TABLE [INTEGER, INTEGER]
			-- Each window's content widget.
		once ("OBJECT")
			create Result.make (4)
		end

	window_toolbar: HASH_TABLE [INTEGER, INTEGER]
			-- Each window's toolbar.
		once ("OBJECT")
			create Result.make (4)
		end

	window_status_bar: HASH_TABLE [INTEGER, INTEGER]
			-- Each window's status bar.
		once ("OBJECT")
			create Result.make (4)
		end

	window_direction: HASH_TABLE [INTEGER, INTEGER]
		once ("OBJECT")
			create Result.make (4)
		end

	stack_alignment: HASH_TABLE [INTEGER, INTEGER]
			-- A stack's alignment for children added later.
		once ("OBJECT")
			create Result.make (8)
		end

	margins: HASH_TABLE [REAL_64, INTEGER]
			-- The device pixels kept clear inside each stack and grid: outside its frame, as a
			-- GTK margin is, so `widget_x' .. `height' leave them out.
		once ("OBJECT")
			create Result.make (16)
		end

	margin_of (an_id: INTEGER): REAL_64
			-- Device pixels kept clear inside `an_id' (0 for anything but a stack or a grid).
		do
			if margins.has (an_id) then
				Result := margins.item (an_id)
			end
		ensure
			non_negative: Result >= 0.0
		end

	scaled (a_logical: INTEGER): REAL_64
			-- `a_logical' pixels (0 if negative) as device pixels on the desktop.
		do
			Result := a_logical.max (0) * dpi
		ensure
			non_negative: Result >= 0.0
		end

	events: ARRAYED_QUEUE [TUPLE [type, id, a, b, c: INTEGER]]
		once ("OBJECT")
			create Result.make (64)
		end

	menus: ARRAYED_LIST [TUPLE [title: STRING_32; items: ARRAYED_LIST [TUPLE [text, shortcut: STRING_32; id, role: INTEGER; separator: BOOLEAN]]]]
		once ("OBJECT")
			create Result.make (4)
		end

	presented: HASH_TABLE [POINTER, INTEGER]
			-- Our cairo reference to each canvas's shown image.
		once ("OBJECT")
			create Result.make (4)
		end

	accessibility_names: SW_ACCESSIBILITY
		once ("OBJECT")
			create Result
		end

	splitter_info: HASH_TABLE [TUPLE [vertical: BOOLEAN; first, second, pending: INTEGER], INTEGER]
			-- Each splitter's orientation, panes and a position waiting for a size (-1: none).
		once ("OBJECT")
			create Result.make (2)
		end

	splitters: HASH_TABLE [SW_SPLITTER, INTEGER]
		once ("OBJECT")
			create Result.make (2)
		end

	table_rows: HASH_TABLE [ARRAYED_LIST [ARRAY [STRING_32]], INTEGER]
		once ("OBJECT")
			create Result.make (2)
		end

	tree_roots: HASH_TABLE [ARRAYED_LIST [INTEGER], INTEGER]
		once ("OBJECT")
			create Result.make (2)
		end

	node_text: HASH_TABLE [STRING_32, INTEGER_64]
			-- Keyed by `node_key'.
		once ("OBJECT")
			create Result.make (32)
		end

	node_parent: HASH_TABLE [INTEGER, INTEGER_64]
		once ("OBJECT")
			create Result.make (32)
		end

	node_children: HASH_TABLE [ARRAYED_LIST [INTEGER], INTEGER_64]
		once ("OBJECT")
			create Result.make (32)
		end

	context_menus: ARRAYED_LIST [TUPLE [title: STRING_32; items: ARRAYED_LIST [TUPLE [text, shortcut: STRING_32; id, role: INTEGER; separator: BOOLEAN]]]]
		once ("OBJECT")
			create Result.make (4)
		end

	widget_context: HASH_TABLE [INTEGER, INTEGER]
			-- Each widget's context menu (its handle's number).
		once ("OBJECT")
			create Result.make (4)
		end

	Context_base: INTEGER = 100_000
			-- Context menu handles count from here (bar menus from 1).

	quiet: INTEGER
			-- Above 0 while the program changes a control: its reports are not queued.

	floats: HASH_TABLE [SW_FLOATING_WINDOW, INTEGER]
			-- Windows open while the main one was: floating document windows of it (W3).
		once ("OBJECT")
			create Result.make (2)
		end

	open_window: detachable GUI_SW_WINDOW
			-- The native window open now.

	forced_dark, forced_dark_set: BOOLEAN

	forced_contrast, forced_contrast_set: BOOLEAN
			-- Tests: the contrast setting as `test_set_high_contrast' gave it.

	theme_overrides: ARRAY [INTEGER]
			-- 1w: the program's own color for each theme role (1 to 6) as 0xRRGGBB; -1: the
			-- theme's own.
		once ("OBJECT")
			create Result.make_filled (-1, 1, 6)
		end

	last_c: detachable C_STRING
			-- The text handed out last (alive until the next).

feature {GUI_SW_WINDOW} -- Themes

	themed (a_dark: BOOLEAN): SW_THEME
			-- A light or dark theme at the desktop's scale (150% draws everything half again as
			-- large): simple_widgets lays out in device pixels.
		do
			if a_dark then
				create Result.make_dark
			else
				create Result.make_light
			end
			Result.set_text_scale (dpi)
			wear_theme_colors (Result)
		ensure
			scaled: Result.text_scale = dpi
		end

	contrast_theme: SW_THEME
			-- A theme painted with the system's colors as the contrast setting has them now,
			-- at the desktop's scale. The program's own colors stay out of it.
		local
			sa: SHELL_APPEARANCE
		do
			create sa
			create Result.make_high_contrast (sa.system_color (sa.Color_window), sa.system_color (sa.Color_window_text),
				sa.system_color (sa.Color_highlight), sa.system_color (sa.Color_highlight_text),
				sa.system_color (sa.Color_button_face), sa.system_color (sa.Color_hotlight))
			Result.set_text_scale (dpi)
		ensure
			contrast: Result.is_high_contrast
			scaled: Result.text_scale = dpi
		end

	wear (a_window: GUI_SW_WINDOW)
			-- `a_window' wears the theme of now: the contrast one while the test door holds
			-- the setting on, the light or dark one a test forced, else the system's (which
			-- follows light, dark and the real contrast setting by itself).
		do
			if forced_contrast_set and then forced_contrast then
				a_window.set_theme (contrast_theme)
			elseif forced_dark_set then
				a_window.set_theme (themed (forced_dark))
			else
				a_window.follow_system_theme (themed (False), themed (True))
			end
		end

	wear_theme_colors (a_theme: SW_THEME)
			-- Put the program's own colors (`theme_overrides') over `a_theme''s.
			-- THE ONE LIMIT: SW_THEME holds its text readable on its surface (4.5 to 1, and
			-- 3 to 1 for secondary text), so a text color that would break that is not worn
			-- and the theme's own stays. The text on an accent fill becomes black or white,
			-- whichever reads better on the new accent.
		local
			l_background, l_outline, l_ink, l_muted, l_accent, l_on_accent: NATURAL_32
		do
			l_background := a_theme.background
			l_outline := a_theme.outline
			l_ink := a_theme.ink
			l_muted := a_theme.ink_muted
			if theme_overrides [1] >= 0 then
				l_background := theme_overrides [1].to_natural_32
			end
			if theme_overrides [2] >= 0 and then a_theme.contrast_ratio (theme_overrides [2].to_natural_32, a_theme.surface) >= a_theme.Body_contrast then
				l_ink := theme_overrides [2].to_natural_32
			end
			if theme_overrides [3] >= 0 and then a_theme.contrast_ratio (theme_overrides [3].to_natural_32, a_theme.surface) >= a_theme.Label_contrast then
				l_muted := theme_overrides [3].to_natural_32
			end
			if theme_overrides [6] >= 0 then
				l_outline := theme_overrides [6].to_natural_32
			end
			a_theme.set_surfaces (l_background, a_theme.surface, a_theme.surface_variant, l_outline, l_ink, l_muted)
			if theme_overrides [4] >= 0 then
				l_accent := theme_overrides [4].to_natural_32
				a_theme.set_semantics (l_accent, a_theme.success, a_theme.warning, a_theme.danger, a_theme.neutral)
				if a_theme.contrast_ratio (0xFFFFFF, l_accent) >= a_theme.contrast_ratio (0x000000, l_accent) then
					l_on_accent := 0xFFFFFF
				end
				a_theme.set_inks_on_fills (l_on_accent, a_theme.ink_on_success, a_theme.ink_on_warning, a_theme.ink_on_danger)
			end
			if theme_overrides [5] >= 0 then
				a_theme.set_washes (theme_overrides [5].to_natural_32, a_theme.wash_success, a_theme.wash_warning, a_theme.wash_danger)
			end
		end

feature {NONE} -- Implementation

	dpi: REAL_64
			-- Device pixels per logical pixel on the desktop.
		do
			Result := desktop.dpi_scale
			if Result <= 0.0 then
				Result := 1.0
			end
		ensure
			positive: Result > 0.0
		end

	device (a_logical: INTEGER): INTEGER
			-- Logical pixels as device pixels.
		do
			Result := (a_logical * dpi).rounded.max (1)
		end

	hidden_windows: HASH_TABLE [BOOLEAN, INTEGER]
			-- Windows the program hid (open, not shown).
		once ("OBJECT")
			create Result.make (2)
		end

	pump_windowless (a_ms: INTEGER)
			-- No window open: pump this thread in short slices so a processor's wake still
			-- arrives (as event 11) within a slice, not after the whole `a_ms'. A slice is never
			-- shorter than a millisecond, because `SHELL_DESKTOP.pump_for' takes a positive
			-- span: with `a_ms' 0 (a timer is due now) the waiting messages are still
			-- dispatched and it returns almost at once.
		require
			non_negative: a_ms >= 0
		local
			i, l_slices: INTEGER
			l_woke: BOOLEAN
		do
			wake_reader.claim_pump_thread
			l_slices := (a_ms // 10).max (1)
			from
				i := 1
			until
				i > l_slices or l_woke
			loop
				desktop.pump_for (a_ms.min (10).max (1))
				l_woke := drain.took_wake
				i := i + 1
			end
			if l_woke then
				push (11, 0, 0, 0, 0)
			end
		end

	wake_reader: SHELL_WAKE
		once ("OBJECT")
			create Result
		end

	work_area_client_height: INTEGER
			-- The tallest client area a window can have on screen: the work area less a
			-- title bar (about 48 logical pixels).
		do
			Result := (desktop.work_area_height - (48 * dpi).rounded).max (1)
		ensure
			positive: Result > 0
		end

	desktop: SHELL_DESKTOP
		once ("OBJECT")
			create Result
		end

	drain: GUI_SHELL_DRAIN
		once ("OBJECT")
			create Result
		end

	register (a_widget: detachable SW_WIDGET): INTEGER
		do
			items.extend (a_widget)
			Result := items.count
		ensure
			numbered: Result = items.count
		end

	widget (an_id: INTEGER): detachable SW_WIDGET
		do
			if an_id >= 1 and an_id <= items.count then
				Result := items.i_th (an_id)
			end
		end

	open_native (a_window: INTEGER; a_w: GUI_SW_WINDOW)
			-- The first window: simple_shell's main window, opened step by step (W1).
		do
			hidden_windows.remove (a_window)
			compose (a_window, a_w)
				-- as large as the content needs, as GTK and AppKit open a window
			a_w.grow_to_fit (desktop.work_area_width, work_area_client_height)
			a_w.set_close_requests_are_events (True)
			a_w.shell_open_window (a_w.title, a_w.win_x, a_w.win_y, a_w.win_w, a_w.win_h)
			open_window := a_w
			tell_window_takes_text
			a_w.request_render
			apply_pending_positions
			if last_positions_moved then
				a_w.request_render
			end
		end

	float_window (a_window: INTEGER; a_w: GUI_SW_WINDOW; a_owner: GUI_SW_WINDOW)
			-- Window `a_window' as a floating document window of `a_owner': the application's
			-- menu bar above its content, as GTK gives every window (its drop-downs open in
			-- the floating window, its Edit items act on that window's focus); its close
			-- button reports 6.
		local
			l_root: SW_COLUMN
			l_bar: SW_MENU_BAR
			l_f: SW_FLOATING_WINDOW
			l_w, l_h, i: INTEGER
		do
			create l_root.make
			l_root.set_padding (0.0)
			l_root.set_gap (0.0)
			if not menus.is_empty then
				create l_bar.make
				from i := 1 until i > menus.count loop
					l_bar.add_menu (menus.i_th (i).title, agent build_float_menu (i, a_window, a_owner))
					i := i + 1
				end
				l_root.put (l_bar)
			end
			if window_content.has (a_window) and then attached widget (window_content.item (a_window)) as al_content then
				al_content.set_grow (1.0)
				l_root.put (al_content)
			end
			if window_direction.has (a_window) then
				l_root.set_layout_direction (window_direction.item (a_window))
			end
				-- as large as the content needs, like the main window (`grow_to_fit')
			l_w := a_w.win_w.max (l_root.preferred_width (a_owner.painter).ceiling.min (desktop.work_area_width))
			l_h := a_w.win_h.max (l_root.preferred_height (a_owner.painter, l_w).ceiling.min (work_area_client_height))
			l_f := a_owner.float_document (l_root, a_w.title, a_owner.win_x + 40, a_owner.win_y + 40, l_w, l_h)
			if l_f.is_open then
				floats.force (l_f, a_window)
				l_f.set_on_close_request (agent push (6, a_window, 0, 0, 0))
				changed
			end
		end

	build_float_menu (a_index, a_window: INTEGER; a_owner: GUI_SW_WINDOW): SW_MENU
			-- Menu `a_index' for floating window `a_window''s menu bar: its Edit items act on that
			-- window's focus (on `a_owner''s if it has closed meanwhile).
		do
			if attached floats.item (a_window) as al_f then
				Result := build_menu (a_index, al_f)
			else
				Result := build_menu (a_index, a_owner)
			end
		end

	compose (a_window: INTEGER; a_w: GUI_SW_WINDOW)
			-- The window's root: the menu bar (when there are menus), the toolbar, the content
			-- and the status bar, top to bottom.
		local
			l_root: SW_COLUMN
			l_bar: SW_MENU_BAR
			i: INTEGER
		do
			create l_root.make
			l_root.set_padding (0.0)
			l_root.set_gap (0.0)
			if not menus.is_empty then
				create l_bar.make
				from i := 1 until i > menus.count loop
					l_bar.add_menu (menus.i_th (i).title, agent build_menu (i, a_w))
					i := i + 1
				end
				l_root.put (l_bar)
				a_w.set_menu_bar (l_bar)
			end
			if window_toolbar.has (a_window) and then attached widget (window_toolbar.item (a_window)) as al_toolbar then
				l_root.put (al_toolbar)
			end
			if window_content.has (a_window) and then attached widget (window_content.item (a_window)) as al_content then
				al_content.set_grow (1.0)
				l_root.put (al_content)
			end
			if window_status_bar.has (a_window) and then attached widget (window_status_bar.item (a_window)) as al_status then
				l_root.put (al_status)
			end
			if window_direction.has (a_window) then
				l_root.set_layout_direction (window_direction.item (a_window))
			end
			a_w.set_root (l_root)
			apply_pills (a_w)
		end

	build_menu (a_index: INTEGER; a_w: SW_POINTER_ROUTING): SW_MENU
			-- Menu `a_index' as it stands now: items report event 5; edit roles act on the
			-- widget focused in `a_w' (the window the menu bar is in) and gray when it
			-- cannot act.
		local
			l_hint: STRING_32
		do
			create Result.make
			across menus.i_th (a_index).items as ic loop
				if ic.separator then
					Result.add_separator
				else
					l_hint := shortcut_text (ic.shortcut)
					if ic.role >= {SW_WIDGET}.Edit_undo and ic.role <= {SW_WIDGET}.Edit_select_all then
						Result.add_item (ic.text, l_hint, a_w.can_edit_focused (ic.role), agent a_w.edit_focused (ic.role))
					else
						Result.add_item (ic.text, l_hint, True, agent push (5, 0, ic.id, 0, 0))
					end
					if menu_item_icons.has (ic.id) then
						Result.set_item_glyph (Result.items.count, menu_item_icons.item (ic.id))
					end
				end
			end
		end

	shortcut_text (a_spec: STRING_32): STRING_32
		local
			l_s: SW_SHORTCUT
		do
			create l_s.make (a_spec)
			if l_s.is_valid then
				Result := l_s.display_text
			else
				create Result.make_empty
			end
		end

	choose_menu_item (an_item_id: INTEGER)
			-- As a user choosing the item: an edit role acts on the focused widget, anything
			-- else reports event 5.
		do
			if attached menu_item (an_item_id) as al_i and then al_i.role >= {SW_WIDGET}.Edit_undo and then al_i.role <= {SW_WIDGET}.Edit_select_all then
				if attached open_window as al_w then
					al_w.edit_focused (al_i.role)
				end
			else
				push (5, 0, an_item_id, 0, 0)
			end
		end

	menu_index (a_menu: POINTER): INTEGER
		do
			Result := a_menu.to_integer_32
		end

	menu_of (a_menu: POINTER): detachable TUPLE [title: STRING_32; items: ARRAYED_LIST [TUPLE [text, shortcut: STRING_32; id, role: INTEGER; separator: BOOLEAN]]]
		do
			if menu_index (a_menu) >= 1 and menu_index (a_menu) <= menus.count then
				Result := menus.i_th (menu_index (a_menu))
			elseif menu_index (a_menu) > Context_base and menu_index (a_menu) <= Context_base + context_menus.count then
				Result := context_menus.i_th (menu_index (a_menu) - Context_base)
			end
		end

	menu_item (an_item_id: INTEGER): detachable TUPLE [text, shortcut: STRING_32; id, role: INTEGER; separator: BOOLEAN]
		do
			across menus as m loop
				across m.items as ic loop
					if Result = Void and then not ic.separator and then ic.id = an_item_id then
						Result := ic
					end
				end
			end
			across context_menus as m loop
				across m.items as ic loop
					if Result = Void and then not ic.separator and then ic.id = an_item_id then
						Result := ic
					end
				end
			end
		end

	report_page (an_id, a_page: INTEGER)
		do
			if quiet = 0 then
				push (13, an_id, a_page, 0, 0)
			end
		end

	report_header (an_id, a_column: INTEGER; a_ascending: BOOLEAN)
		do
			push (14, an_id, a_column, a_ascending.to_integer, 0)
		end

	report_table_select (an_id, a_model: INTEGER)
			-- Selection (4): a = the first selected row.
		do
			if quiet = 0 and then attached {SW_DATA_GRID [ARRAY [STRING_32]]} widget (an_id) as al_g then
				if al_g.selected_count > 0 then
					push (4, an_id, ascending_selection (al_g).first, 0, 0)
				else
					push (4, an_id, 0, 0, 0)
				end
			end
		end

	report_tree_select (an_id, a_node: INTEGER)
		do
			if quiet = 0 then
				push (4, an_id, a_node, 0, 0)
			end
		end

	report_expansion (an_id, a_node: INTEGER; a_open: BOOLEAN)
		do
			if quiet = 0 then
				push (15, an_id, a_node, a_open.to_integer, 0)
			end
		end

	ascending_selection (a_g: SW_DATA_GRID [ARRAY [STRING_32]]): ARRAYED_LIST [INTEGER]
			-- The selected rows, lowest first, as AppKit and GTK give them (SW_DATA_GRID keeps
			-- them in the order they were chosen).
		local
			i, j, l_row: INTEGER
		do
			create Result.make (a_g.selected_count)
			from i := 1 until i > a_g.selected_count loop
				l_row := a_g.selected_at (i)
				from j := 1 until j > Result.count or else Result.i_th (j) > l_row loop
					j := j + 1
				end
				Result.go_i_th (j)
				Result.put_left (l_row)
				i := i + 1
			end
		ensure
			all_of_them: Result.count = a_g.selected_count
		end

	cells_of (a_joined: STRING_32): ARRAY [STRING_32]
			-- The cells of a row joined by U+001F.
		local
			l_parts: LIST [STRING_32]
			i: INTEGER
		do
			l_parts := a_joined.split ('%/31/')
			create Result.make_filled ({STRING_32} "", 1, l_parts.count)
			from i := 1 until i > l_parts.count loop
				Result.put (l_parts.i_th (i), i)
				i := i + 1
			end
		end

	cell_of (a_row: ARRAY [STRING_32]; a_column: INTEGER): STRING_32
		do
			if a_column >= a_row.lower and a_column <= a_row.upper then
				Result := a_row.item (a_column)
			else
				create Result.make_empty
			end
		end

	node_key (a_tree, a_node: INTEGER): INTEGER_64
			-- One key per tree and node.
		do
			Result := a_tree.to_integer_64 * 1_000_000_000 + a_node
		end

	tree_children (a_tree, a_node: INTEGER): ARRAYED_LIST [INTEGER]
		do
			if attached node_children.item (node_key (a_tree, a_node)) as al_kids then
				Result := al_kids.twin
			else
				create Result.make (0)
			end
		end

	tree_label (a_tree, a_node: INTEGER): STRING_32
		do
			if attached node_text.item (node_key (a_tree, a_node)) as al_text then
				Result := al_text
			else
				create Result.make_empty
			end
		end

	reveal (a_tree: INTEGER; a_t: SW_TREE [INTEGER]; a_node: INTEGER)
			-- Open every ancestor of `a_node' (silently).
		local
			l_chain: ARRAYED_LIST [INTEGER]
			k, l_guard: INTEGER
		do
			create l_chain.make (4)
			from
				k := node_parent.item (node_key (a_tree, a_node))
			until
				k = 0 or l_guard > 1000
			loop
				l_chain.put_front (k)
				k := node_parent.item (node_key (a_tree, k))
				l_guard := l_guard + 1
			end
			across l_chain as ic loop
				a_t.expand_node (ic)
			end
		end

	fill_context (a_menu: SW_MENU; a_x, a_y: REAL_64; a_index: INTEGER)
			-- A right-click: the context menu's items, as they stand now.
		do
			if a_index > Context_base and a_index <= Context_base + context_menus.count then
				across context_menus.i_th (a_index - Context_base).items as ic loop
					if ic.separator then
						a_menu.add_separator
					else
						a_menu.add_item (ic.text, shortcut_text (ic.shortcut), True, agent push (5, 0, ic.id, 0, 0))
					end
				end
			end
		end

	splitter_extent (a_sp: SW_SPLITTER): REAL_64
			-- The length the divider moves along, in device pixels.
		do
			if a_sp.is_horizontal then
				Result := a_sp.height - {SW_SPLITTER}.Divider_w
			else
				Result := a_sp.width - {SW_SPLITTER}.Divider_w
			end
		end

	apply_pending_positions
			-- Place every splitter whose position was set before it had a size
			-- (`last_positions_moved' tells whether one moved).
		do
			last_positions_moved := False
			from
				splitter_info.start
			until
				splitter_info.after
			loop
				if splitter_info.item_for_iteration.pending >= 0
					and then attached splitters.item (splitter_info.key_for_iteration) as al_sp
					and then splitter_extent (al_sp) > 0.0
				then
					al_sp.set_ratio_within (device (splitter_info.item_for_iteration.pending) / splitter_extent (al_sp), splitter_extent (al_sp))
					splitter_info.item_for_iteration.pending := -1
					last_positions_moved := True
				end
				splitter_info.forth
			end
		end

	last_positions_moved: BOOLEAN

	report_toggle (an_id: INTEGER)
		do
			push (12, an_id, check_box_is_checked (an_id).to_integer, 0, 0)
		end

	report_row (an_id, a_row: INTEGER)
		do
			push (4, an_id, a_row, 0, 0)
		end

	report_number (an_id, a_value: INTEGER)
		do
			push (2, an_id, a_value, 0, 0)
		end

	report_choice (an_id, i: INTEGER)
			-- A radio group's or segmented control's choice, unless the program made it.
		do
			if quiet = 0 then
				push (4, an_id, i, 0, 0)
			end
		end

	report_slider (an_id: INTEGER; a_fraction: REAL_64)
		do
			if quiet = 0 and then attached {GUI_SW_SLIDER} widget (an_id) as al_s then
				push (2, an_id, al_s.value, 0, 0)
			end
		end

	report_switch (an_id: INTEGER)
		do
			if quiet = 0 then
				push (12, an_id, switch_is_on (an_id).to_integer, 0, 0)
			end
		end

	report_date (an_id, y, m, d: INTEGER)
		do
			if quiet = 0 then
				push (2, an_id, y * 10000 + m * 100 + d, 0, 0)
			end
		end

	report_time (an_id, h, m: INTEGER)
		do
			if quiet = 0 then
				push (2, an_id, h * 60 + m, 0, 0)
			end
		end

	report_color (an_id: INTEGER; a_rgb: NATURAL_32)
		do
			if quiet = 0 then
				push (2, an_id, a_rgb.to_integer_32, 0, 0)
			end
		end

	report_expander (an_id, a_section: INTEGER)
		do
			if quiet = 0 then
				push (12, an_id, expander_is_expanded (an_id).to_integer, 0, 0)
			end
		end

	report_commit (an_id: INTEGER)
		do
			if quiet = 0 then
				push (2, an_id, 0, 0, 0)
			end
		end

	quietly (a_change: PROCEDURE)
			-- Run the program's own change without reporting it. An exception in the change
			-- still lowers the count: left raised, it silenced every later user event.
		do
			quiet := quiet + 1
			a_change.call
			quiet := quiet - 1
		ensure
			balanced: quiet = old quiet
		rescue
			quiet := quiet - 1
		end

	tree_cell (a_tree, a_node, a_column: INTEGER): STRING_32
			-- A tree table's cell (column 2 on).
		do
			if attached node_cells.item (node_key (a_tree, a_node).out + ":" + a_column.out) as al_s then
				Result := al_s
			else
				create Result.make_empty
			end
		end

	node_cells: HASH_TABLE [STRING_32, STRING]
			-- Tree table cells, by node key and column.
		once ("OBJECT")
			create Result.make (64)
		end

	report_pointer (an_id, a_kind: INTEGER; a_x, a_y: REAL_64; a_button, a_modifiers: INTEGER)
		do
			if attached widget (an_id) as al_w then
				push (7, an_id, logical (al_w, a_x), logical (al_w, a_y), a_kind + a_button * 16 + a_modifiers * 256)
			end
		end

	report_resize (an_id: INTEGER; a_width, a_height: REAL_64)
		do
			if attached widget (an_id) as al_w then
				push (9, an_id, logical (al_w, a_width), logical (al_w, a_height), 0)
			end
		end

	report_key (an_id, a_vk: INTEGER; a_shift: BOOLEAN)
			-- Keys that type nothing, in GDK's key codes (the shared vocabulary); typing comes
			-- through `report_char'.
		local
			l_code: INTEGER
		do
			inspect a_vk
			when 37 then l_code := 0xFF51
			when 38 then l_code := 0xFF52
			when 39 then l_code := 0xFF53
			when 40 then l_code := 0xFF54
			when 36 then l_code := 0xFF50
			when 35 then l_code := 0xFF57
			when 33 then l_code := 0xFF55
			when 34 then l_code := 0xFF56
			when 46 then l_code := 0xFFFF
			when 112 .. 123 then l_code := 0xFFBE + (a_vk - 112)
			else
			end
			if l_code /= 0 and then attached {SW_CANVAS} widget (an_id) as al_c then
				push (8, an_id, l_code, 0, al_c.modifiers * 256)
			end
		end

	report_char (an_id, a_code: INTEGER)
		local
			l_code: INTEGER
		do
			inspect a_code
			when 8 then l_code := 0xFF08
			when 9 then l_code := 0xFF09
			when 13 then l_code := 0xFF0D
			when 27 then l_code := 0xFF1B
			else
				l_code := a_code
			end
			if a_code >= 8 and then attached {SW_CANVAS} widget (an_id) as al_c then
				push (8, an_id, l_code, if a_code >= 32 or l_code /= a_code then a_code else 0 end, al_c.modifiers * 256)
			end
		end

	logical (a_w: SW_WIDGET; a_device: REAL_64): INTEGER
			-- Device pixels as logical ones (simple_widgets lays out in device pixels).
		local
			l_scale: REAL_64
		do
			l_scale := 1.0
			if attached open_window as al_win then
				l_scale := al_win.theme.text_scale.max (0.01)
			end
			Result := (a_device / l_scale).rounded
		end

	content_origin (a_w: SW_WIDGET): detachable SW_WIDGET
			-- The content widget of the window `a_w' is in (positions count from its corner).
		do
			across window_content as ic loop
				if Result = Void and then attached widget (ic) as al_c and then is_inside (a_w, al_c) then
					Result := al_c
				end
			end
		end

	is_inside (a_w, a_ancestor: SW_WIDGET): BOOLEAN
			-- Is `a_w' `a_ancestor' itself or under it?
		local
			l_w: detachable SW_WIDGET
		do
			from l_w := a_w until l_w = Void or Result loop
				Result := l_w = a_ancestor
				l_w := l_w.parent
			end
		end

	is_render_due: BOOLEAN
			-- Has a styling call changed what a frame would show since the last one drawn?

	style_changed
			-- A style was set over a range of a text: draw at the next turn of the loop, not
			-- now. A highlighter sets thousands of ranges in a row, and a frame for each lays
			-- the text out and draws it thousands of times (measured: 30 lines of code took
			-- 30 seconds to color).
		do
			is_render_due := True
		ensure
			due: is_render_due
		end

	changed
			-- A programmatic change: lay out and draw again (and place a splitter whose position
			-- was set before it had a size).
		do
			is_render_due := False
			if attached open_window as al_w and then al_w.is_window_open then
				al_w.request_render
				apply_pending_positions
				if last_positions_moved then
					al_w.request_render
				end
			end
		end

	c_text (a_text: READABLE_STRING_GENERAL): POINTER
			-- `a_text' as a UTF-8 C string, alive until the next one.
		local
			l_c: C_STRING
		do
			l_c := to_c (a_text)
			last_c := l_c
			Result := l_c.item
		end

	put_int (a_target: TYPED_POINTER [INTEGER]; a_value: INTEGER)
		do
			(create {MANAGED_POINTER}.share_from_pointer (a_target.to_pointer, 4)).put_integer_32 (a_value, 0)
		end

	not_yet (a_what: STRING)
			-- Fail loudly: stage 2 of the Windows backend.
		local
			l_e: DEVELOPER_EXCEPTION
		do
			l_e := create {DEVELOPER_EXCEPTION}
			l_e.set_description ("not yet on Windows: " + a_what)
			l_e.raise
		end

	c_surface_reference (a_surface: POINTER): POINTER
		external
			"C inline use <cairo.h>"
		alias
			"return cairo_surface_reference((cairo_surface_t *) $a_surface);"
		end

	c_surface_destroy (a_surface: POINTER)
		external
			"C inline use <cairo.h>"
		alias
			"cairo_surface_destroy((cairo_surface_t *) $a_surface);"
		end

end
