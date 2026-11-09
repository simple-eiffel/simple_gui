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
			scale
		end

feature -- Lifecycle and loop

	init (a_name, a_id: POINTER): BOOLEAN
			-- Windows always has a display. Become DPI aware first, before anything asks the
			-- desktop's scale: until then Windows answers 96 DPI, so a window and its first
			-- theme were sized at 100% on a 150% display and grew when a later theme came.
		do
			desktop.become_dpi_aware
			Result := True
		end

	is_gui_thread: BOOLEAN
		do
			Result := (create {SHELL_WAKE}).is_pump_thread
		end

	pump (a_ms: INTEGER)
			-- Run the open window's loop until an event is queued or `a_ms' pass; then ask
			-- for the rows lazy tables are about to show.
		do
			if events.is_empty then
				if attached open_window as al_w and then al_w.is_window_open then
					al_w.shell_turn (a_ms.max (0))
				else
					pump_windowless (a_ms.max (0))
				end
			end
			check_rows_wanted
		end

	pump_until_idle (a_ms: INTEGER)
			-- Dispatch what is waiting, then lay out and draw, so positions and sizes are current
			-- (the shared tests' rule 2).
		do
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
			if forced_dark_set then
				l_w.set_theme (themed (forced_dark))
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
			else
				create l_row.make
				l_row.set_padding (scaled (Stack_margin))
				l_row.set_gap (scaled (a_spacing))
					-- children fill the row's height, as in a GTK box and an NSStackView
				l_row.set_cross_axis ({SW_ROW}.Cross_stretch)
				Result := register (l_row)
				margins.force (scaled (Stack_margin), Result)
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
		do
			if attached {SW_SCROLL_AREA} widget (an_id) as al_s then
				al_s.scroll_to (a_y)
				al_s.scroll_to_x (a_x)
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
			l_file: RAW_FILE
			l_m: MANAGED_POINTER
		do
			create l_file.make_with_name (from_c (a_path))
			if attached {SW_IMAGE} widget (an_id) and then l_file.exists and then l_file.is_readable
				and then l_file.count > 0
			then
				l_file.open_read
				create l_m.make (l_file.count)
				l_file.read_to_managed_pointer (l_m, 0, l_file.count)
				l_file.close
				Result := image_set_bytes (an_id, l_m.item, l_m.count)
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
			l_stb: SIMPLE_STB
			l_img: STB_IMAGE
			l_src, l_dst: MANAGED_POINTER
			l_x, l_y, l_at: INTEGER
			r, g, b, a: NATURAL_32
		do
			create l_png.make_from_png_data (a_bytes)
			if l_png.is_valid then
				Result := l_png
			else
				create l_stb.make
				l_img := l_stb.load_rgba_from_memory (a_bytes)
				if l_img.is_valid and then l_img.width > 0 and then l_img.height > 0 then
					create l_png.make (l_img.width, l_img.height)
					if l_png.is_valid then
						l_png.flush.do_nothing
						create l_src.share_from_pointer (l_img.data, l_img.width * l_img.height * 4)
						create l_dst.share_from_pointer (l_png.data, l_png.stride * l_img.height)
						from l_y := 0 until l_y >= l_img.height loop
							from l_x := 0 until l_x >= l_img.width loop
								l_at := (l_y * l_img.width + l_x) * 4
								a := l_src.read_natural_8 (l_at + 3).to_natural_32
								r := l_src.read_natural_8 (l_at).to_natural_32 * a // 255
								g := l_src.read_natural_8 (l_at + 1).to_natural_32 * a // 255
								b := l_src.read_natural_8 (l_at + 2).to_natural_32 * a // 255
								l_dst.put_natural_32 ((a |<< 24) | (r |<< 16) | (g |<< 8) | b, l_y * l_png.stride + l_x * 4)
								l_x := l_x + 1
							end
							l_y := l_y + 1
						end
						l_png.mark_dirty.do_nothing
						Result := l_png
					end
				end
				l_img.destroy
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

	save_file_named (a_window: INTEGER; a_title, an_extensions, a_name: POINTER): POINTER
			-- simple_widgets' drawn Save dialog suggesting `a_name', waited for.
		do
			if attached windows.item (a_window) as al_w and then attached al_w.choose_file_titled (True, from_c (a_title), ".", from_c (a_name), from_c (an_extensions)) as al_path then
				Result := c_text (al_path)
			end
		end

	choose_folder (a_window: INTEGER; a_title: POINTER): POINTER
		do
			if attached windows.item (a_window) as al_w and then attached al_w.choose_folder (from_c (a_title), ".") as al_path then
				Result := c_text (al_path)
			end
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
		end

	path_control_set (an_id: INTEGER; a_path: POINTER)
		do
			if attached {GUI_SW_PATH_CONTROL} widget (an_id) as al_p then
				al_p.set_path (from_c (a_path))
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
				changed
			end
		end

	rich_text_set_color (an_id, a_start, an_end, a_rgb: INTEGER)
		do
			if attached {GUI_SW_RICH_TEXT_AREA} widget (an_id) as al_r then
				al_r.set_color (a_start, an_end, a_rgb)
				changed
			end
		end

	rich_text_set_size (an_id, a_start, an_end: INTEGER; a_points: REAL_64)
		do
			if attached {GUI_SW_RICH_TEXT_AREA} widget (an_id) as al_r then
				al_r.set_size (a_start, an_end, a_points)
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
		do
			if attached widget (an_id) as al_w then
				al_w.set_enabled (a_on)
				changed
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
			-- simple_widgets' drawn file dialog, waited for (W9).
		do
			if attached windows.item (a_window) as al_w and then attached al_w.choose_file_titled (a_save, from_c (a_title), ".", "", from_c (an_extensions)) as al_path then
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
			if is_dark then
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
				ic.set_theme (themed (a_on))
			end
			push (10, 0, a_on.to_integer, 0, 0)
			changed
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

	test_choose (an_id, a_row: INTEGER)
			-- As the user choosing a row, a table row, a tree node or a tab: reported.
		do
			if attached {SW_TEXT_LIST} widget (an_id) as al_l and then a_row >= 1 and then a_row <= al_l.count then
				al_l.select_row (a_row)
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
			-- How finely a pending dwell shot is timed.

	pace_fast_timer
			-- Run the host windows' fast timer at the finest pace any drawn view needs (its fast
			-- tick, or `Dwell_pace_ms' while a dwell shot is pending); off when none needs it.
		local
			l_ms: INTEGER
		do
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
		ensure
			scaled: Result.text_scale = dpi
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
			-- arrives (as event 11) within a slice, not after the whole `a_ms'.
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
				desktop.pump_for (a_ms.min (10))
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
			-- Run the program's own change without reporting it.
		do
			quiet := quiet + 1
			a_change.call
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
		local
			l_w: detachable SW_WIDGET
		do
			from l_w := a_w until l_w = Void or Result loop
				Result := l_w = a_ancestor
				l_w := l_w.parent
			end
		end

	changed
			-- A programmatic change: lay out and draw again (and place a splitter whose position
			-- was set before it had a size).
		do
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
