note
	description: "[
		Testing only: act as the user would (each action emits the events a user's would),
		let the loop settle, take snapshots, and read the assistive tree.
	]"

class
	GUI_TEST_DRIVER

inherit
	GUI_SHARED

feature -- User actions

	perform_click (a_button: GUI_BUTTON)
		require
			has_application: has_application
		do
			backend.test_click (a_button.id)
			settle
		end

	toggle (a_box: GUI_CHECK_BOX)
			-- Click the box as a user would (fires toggled).
		require
			has_application: has_application
		do
			backend.test_click (a_box.id)
			settle
		ensure
			flipped: a_box.is_checked /= old a_box.is_checked
		end

	type_text (a_field: GUI_TEXT_FIELD; a_text: READABLE_STRING_GENERAL)
			-- Replace the field's text as a user would (fires change events).
		require
			has_application: has_application
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.test_type (a_field.id, l_c.item)
			settle
		ensure
			typed: a_field.text.same_string_general (a_text)
		end

	type_into_area (an_area: GUI_TEXT_AREA; a_text: READABLE_STRING_GENERAL)
			-- Replace a text area's text as a user would (fires change events).
		require
			has_application: has_application
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.test_type (an_area.id, l_c.item)
			settle
		ensure
			typed: an_area.text.same_string_general (a_text)
		end

	click_header (a_table: GUI_TABLE; a_column: INTEGER)
			-- Click a column's header as a user would (fires header_actions).
		require
			has_application: has_application
			valid: 1 <= a_column and a_column <= a_table.column_count
		do
			backend.test_click_header (a_table.id, a_column)
			settle
		end

	choose_table_row (a_table: GUI_TABLE; a_row: INTEGER)
			-- Select only row `a_row' as a user would (fires selection_actions).
		require
			has_application: has_application
			valid: 1 <= a_row and a_row <= a_table.row_count
		do
			backend.test_choose (a_table.id, a_row)
			settle
		ensure
			selected: a_table.selected_row = a_row
		end

	choose_node (a_tree: GUI_TREE; a_node: INTEGER)
			-- Select a node as a user would (fires selection_actions).
		require
			has_application: has_application
			valid: a_tree.is_node (a_node)
		do
			backend.test_choose (a_tree.id, a_node)
			settle
		ensure
			selected: a_tree.selected_node = a_node
		end

	expand_node (a_tree: GUI_TREE; a_node: INTEGER; a_on: BOOLEAN)
			-- Expand (or collapse) a node as a user would (fires expansion_actions).
		require
			has_application: has_application
			valid: a_tree.is_node (a_node)
		do
			backend.test_expand (a_tree.id, a_node, a_on)
			settle
		end

	choose_row (a_list: GUI_LIST; a_row: INTEGER)
			-- Select a row as a user would (fires selection).
		require
			has_application: has_application
			valid: 1 <= a_row and a_row <= a_list.count
		do
			backend.test_choose (a_list.id, a_row)
			settle
		ensure
			selected: a_list.selected_index = a_row
		end

	choose_option (a_chooser: GUI_CHOOSER; a_row: INTEGER)
			-- Choose a dropdown's row, a radio or a segment as a user would (fires selection
			-- when it is another one).
		require
			has_application: has_application
			valid: 1 <= a_row and a_row <= a_chooser.count
		do
			backend.test_choose (a_chooser.id, a_row)
			settle
		ensure
			selected: a_chooser.selected_index = a_row
		end

	set_slider (a_slider: GUI_SLIDER; a_value: INTEGER)
			-- Drag the knob to `a_value' as a user would (fires change on a change).
		require
			has_application: has_application
			in_range: a_slider.minimum <= a_value and a_value <= a_slider.maximum
		do
			backend.test_slide (a_slider.id, a_value)
			settle
		ensure
			set: a_slider.value = a_value
		end

	flip_switch (a_switch: GUI_SWITCH)
			-- Click the switch as a user would (fires toggled).
		require
			has_application: has_application
		do
			backend.test_click (a_switch.id)
			settle
		ensure
			flipped: a_switch.is_on /= old a_switch.is_on
		end

	set_date (a_picker: GUI_DATE_PICKER; y, m, d: INTEGER)
			-- Enter a date as a user would (fires change on a change).
		require
			has_application: has_application
			valid: a_picker.is_valid_date (y, m, d)
		do
			backend.test_set_date (a_picker.id, y * 10000 + m * 100 + d)
			settle
		ensure
			set: a_picker.year = y and a_picker.month = m and a_picker.day = d
		end

	set_time (a_picker: GUI_TIME_PICKER; h, m: INTEGER)
			-- Enter a time as a user would (fires change on a change).
		require
			has_application: has_application
			valid_hour: 0 <= h and h <= 23
			valid_minute: 0 <= m and m <= 59
		do
			backend.test_set_date (a_picker.id, h * 60 + m)
			settle
		ensure
			set: a_picker.hour = h and a_picker.minute = m
		end

	set_color (a_chooser: GUI_COLOR_CHOOSER; a_color: NATURAL_32)
			-- Choose a color as a user would (fires change on a change).
		require
			has_application: has_application
			rgb: a_color <= 0xFFFFFF
		do
			backend.test_set_color (a_chooser.id, a_color.to_integer_32)
			settle
		ensure
			set: a_chooser.color = a_color
		end

	type_combo (a_combo: GUI_COMBO_BOX; a_text: READABLE_STRING_GENERAL)
			-- Type `a_text' and press Return, as a user would (fires change on a change).
		require
			has_application: has_application
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.test_type_combo (a_combo.id, l_c.item)
			settle
		ensure
			set: a_combo.text.same_string_general (a_text)
		end

	pick_combo_option (a_combo: GUI_COMBO_BOX; i: INTEGER)
			-- Pick option `i' from the list, as a user would (fires change on a change).
		require
			has_application: has_application
			valid: 1 <= i and i <= a_combo.count
		do
			backend.test_choose (a_combo.id, i)
			settle
		ensure
			set: a_combo.text.same_string (a_combo.i_th (i))
		end

	toggle_expander (an_expander: GUI_EXPANDER)
			-- Click the expander's title as a user would (fires toggled).
		require
			has_application: has_application
		do
			backend.test_toggle_expander (an_expander.id)
			settle
		ensure
			flipped: an_expander.is_expanded /= old an_expander.is_expanded
		end

	click_split (a_button: GUI_MENU_BUTTON)
			-- Click a split button's main part as a user would (fires click).
		require
			has_application: has_application
			split: a_button.is_split
		do
			backend.test_click (a_button.id)
			settle
		end

	dismiss_popover (a_popover: GUI_POPOVER)
			-- Press Escape over a shown popover, as a user would (fires closed).
		require
			has_application: has_application
			shown: a_popover.is_shown
		do
			backend.test_dismiss_popover (a_popover.id)
			settle
		ensure
			hidden: not a_popover.is_shown
		end

	type_tokens (a_field: GUI_TOKEN_FIELD; a_text: READABLE_STRING_GENERAL)
			-- Type `a_text' (tokens separated by commas) and press Return, as a user would.
		require
			has_application: has_application
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.test_type_tokens (a_field.id, l_c.item)
			settle
		end

	rate (a_rating: GUI_RATING; a_value: INTEGER)
			-- Click star `a_value' as a user would (fires change on a change).
		require
			has_application: has_application
			in_range: 0 <= a_value and a_value <= a_rating.maximum
		do
			backend.test_rate (a_rating.id, a_value)
			settle
		ensure
			set: a_rating.value = a_value
		end

	toggle_reveal (a_field: GUI_PASSWORD_FIELD)
			-- Click the eye, as a user (fires `reveal_actions').
		require
			has_application: has_application
		do
			backend.test_toggle_reveal (a_field.id)
			settle
		ensure
			flipped: a_field.is_revealed /= old a_field.is_revealed
		end

	leave_field (a_field: GUI_TEXT_FIELD)
			-- Move the focus out of `a_field', as a user tabbing away (commits it: validation).
		require
			has_application: has_application
		do
			backend.test_end_editing (a_field.id)
			settle
		end

	pick_suggestion (a_field: GUI_TEXT_FIELD; i: INTEGER)
			-- Choose suggestion `i' from the list, as a user.
		require
			has_application: has_application
			valid: 1 <= i and i <= a_field.suggestions.count
		do
			backend.test_pick_suggestion (a_field.id, i)
			settle
		end

	field_error (a_field: GUI_TEXT_FIELD): STRING_32
			-- The message shown under `a_field' now (empty: none).
		require
			has_application: has_application
		do
			Result := backend.from_c (backend.field_error_shown (a_field.id))
		end

	set_date_time (a_picker: GUI_DATE_TIME_PICKER; y, m, d, h, min: INTEGER)
			-- Enter a date and time, as a user.
		require
			has_application: has_application
			valid: a_picker.is_valid_date (y, m, d) and 0 <= h and h <= 23 and 0 <= min and min <= 59
		do
			backend.test_set_date_time (a_picker.id, y * 10000 + m * 100 + d, h * 60 + min)
			settle
		end

	set_month (a_picker: GUI_MONTH_PICKER; y, m: INTEGER)
			-- Enter a month, as a user.
		require
			has_application: has_application
			valid: 1 <= y and y <= 9999 and 1 <= m and m <= 12
		do
			backend.test_set_date_time (a_picker.id, y * 10000 + m * 100 + 1, 0)
			settle
		end

	slide_range (a_slider: GUI_RANGE_SLIDER; a_low, a_high: INTEGER)
			-- Drag the thumbs to `a_low' and `a_high', as a user.
		require
			has_application: has_application
			in_range: a_slider.minimum <= a_low and a_low <= a_high and a_high <= a_slider.maximum
		do
			backend.test_slide_range (a_slider.id, a_low, a_high)
			settle
		end

	extend_list_selection (a_list: GUI_LIST; a_row: INTEGER)
			-- Add row `a_row' to the selection, as a Command-click or Control-click.
		require
			has_application: has_application
			multiple: a_list.is_multiple_selection
			valid: 1 <= a_row and a_row <= a_list.count
		do
			backend.test_extend_list_selection (a_list.id, a_row)
			settle
		end

	cancel_dialogs_after (a_ms: INTEGER)
			-- Cancel each dialog `a_ms' milliseconds after it opens (0: never), so tests of
			-- GUI_DIALOGS run unattended.
		require
			has_application: has_application
			not_negative: a_ms >= 0
		do
			backend.test_auto_cancel_dialogs (a_ms)
		end

	enter_number (a_spin: GUI_SPIN_BOX; a_value: INTEGER)
			-- Set the value as a user would (fires change).
		require
			has_application: has_application
			in_range: a_spin.minimum <= a_value and a_value <= a_spin.maximum
		do
			backend.test_set_number (a_spin.id, a_value)
			settle
		ensure
			set: a_spin.value = a_value
		end

	choose_page (a_tabs: GUI_TABS; a_page: INTEGER)
			-- Click tab `a_page' as a user would (fires page changed).
		require
			has_application: has_application
			valid: 1 <= a_page and a_page <= a_tabs.count
		do
			backend.test_choose (a_tabs.id, a_page)
			settle
		ensure
			shown: a_tabs.selected_index = a_page
		end

	invoke_menu (an_item_id: INTEGER)
			-- Choose menu item `an_item_id' as a user would.
		require
			has_application: has_application
			valid: 1 <= an_item_id and an_item_id <= application.menu.item_count
		do
			backend.test_menu (an_item_id)
			settle
		end

	request_close (a_window: GUI_WINDOW)
			-- Ask to close `a_window' as a user would (fires close requested).
		require
			has_application: has_application
			open: not a_window.is_closed
		do
			backend.test_request_close (a_window.id)
			settle
		end

	focus (a_widget: GUI_WIDGET)
			-- Give `a_widget' the keyboard focus, as a click on it would.
		require
			has_application: has_application
		do
			backend.test_focus (a_widget.id)
			settle
		end

	edit_enabled (a_role: INTEGER): BOOLEAN
			-- Would the Edit menu's item for `a_role' ({GUI_MENU}.Role_undo .. Role_select_all) be
			-- enabled now, for the focus of the window in front?
		require
			has_application: has_application
			edit_role: a_role >= 10 and a_role <= 15
		do
			Result := backend.test_edit_enabled (a_role)
		end

	invoke_context_item (a_widget: GUI_WIDGET; an_item_id: INTEGER)
			-- Open `a_widget's context menu and choose item `an_item_id', as a user would.
		require
			has_application: has_application
			has_menu: a_widget.context_menu /= Void
		local
			l_found: BOOLEAN
		do
			l_found := backend.test_context_menu (a_widget.id, an_item_id)
			settle
			last_context_item_found := l_found
		end

	last_context_item_found: BOOLEAN
			-- Did the last `invoke_context_item' find the item in that widget's context menu?

	set_dark (a_on: BOOLEAN)
			-- Switch the appearance (fires appearance_changed_actions).
		require
			has_application: has_application
		do
			backend.set_dark (a_on)
			settle
		end

	pump_until_idle (a_ms: INTEGER)
			-- Run the loop until nothing is pending (or `a_ms' pass), then fire the queue.
		require
			has_application: has_application
			non_negative: a_ms >= 0
		do
			backend.pump_until_idle (a_ms)
			application.drain_queue
		end

	press_shortcut (a_window: GUI_WINDOW; a_shortcut: READABLE_STRING_GENERAL)
			-- Press `a_shortcut' in `a_window' as a user would.
		require
			has_application: has_application
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_shortcut)
			backend.test_press_shortcut (a_window.id, l_c.item)
			settle
		end

	wait (a_ms: INTEGER)
			-- Turn the loop about `a_ms' milliseconds, firing events as they come (timers): in
			-- 10 ms turns, each of which an event may end early, so it is at most `a_ms'.
		require
			has_application: has_application
			non_negative: a_ms >= 0
		local
			i: INTEGER
		do
			from i := 1 until i > a_ms // 10 loop
				application.process_events (10)
				i := i + 1
			end
		end

	button_icon (a_button: GUI_BUTTON): STRING_32
			-- The icon name `a_button' shows now; empty for none.
		require
			has_application: has_application
		do
			settle
			Result := backend.from_c (backend.test_button_icon (a_button.id))
		end

	badge_shown (a_widget: GUI_WIDGET): STRING_32
			-- The badge `a_widget' shows now: its text, a bullet for a dot, empty for none.
		require
			has_application: has_application
		do
			settle
			Result := backend.from_c (backend.test_badge_shown (a_widget.id))
		end

	press_info_bar (a_bar: GUI_INFO_BAR; a_number: INTEGER)
			-- Press action `a_number' of `a_bar' (0: its close button) as a user would.
		require
			has_application: has_application
		do
			backend.test_info_bar_press (a_bar.id, a_number)
			settle
		end

	toast_shown (a_window: GUI_WINDOW): STRING_32
			-- The toast showing in `a_window' now; empty for none.
		require
			has_application: has_application
		do
			settle
			Result := backend.from_c (backend.test_toast_shown (a_window.id))
		end

	press_toast (a_window: GUI_WINDOW)
			-- Press the action of the toast showing in `a_window', as a user would.
		require
			has_application: has_application
		do
			backend.test_toast_press (a_window.id)
			settle
		end

	pick (a_source: GUI_WIDGET; a_row: INTEGER)
			-- Start a pick on `a_source' (row `a_row', 0 for the widget itself) as a user would.
		require
			has_application: has_application
		do
			backend.test_pick (a_source.id, a_row)
			settle
		end

	drop (a_target: GUI_WIDGET; a_row: INTEGER)
			-- Drop what is picked on `a_target' (row `a_row'), as a user would.
		require
			has_application: has_application
		do
			backend.test_drop (a_target.id, a_row)
			settle
		end

	drop_files (a_target: GUI_WIDGET; a_paths: ITERABLE [PATH])
			-- Drop files on `a_target' as another program's drag would.
		require
			has_application: has_application
		local
			l_joined: STRING_32
			l_c: C_STRING
		do
			create l_joined.make_empty
			across a_paths as ic loop
				if not l_joined.is_empty then
					l_joined.append_character ('%N')
				end
				l_joined.append (ic.name)
			end
			l_c := backend.to_c (l_joined)
			backend.test_drop_files (a_target.id, l_c.item)
			settle
		end

	drop_text (a_target: GUI_WIDGET; a_text: READABLE_STRING_GENERAL)
			-- Drop text on `a_target' as another program's drag would.
		require
			has_application: has_application
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_text)
			backend.test_drop_text (a_target.id, l_c.item)
			settle
		end

	cancel_pick
		require
			has_application: has_application
		do
			backend.test_cancel_pick
			settle
		end

	drag_out_carries (a_source: GUI_WIDGET): STRING_32
			-- What a drag out of `a_source' would give another program now: the text, a line
			-- feed, then the paths one per line; empty for nothing.
		require
			has_application: has_application
		do
			settle
			Result := backend.from_c (backend.test_drag_out (a_source.id))
		end

	end_drag_out (a_source: GUI_WIDGET; a_how: INTEGER)
			-- End a drag out of `a_source' as another program would (`a_how' as in event 34).
		require
			has_application: has_application
		do
			backend.test_drag_out_ended (a_source.id, a_how)
			settle
		end

	is_accepting (a_target: GUI_WIDGET): BOOLEAN
			-- Does `a_target' show that it takes the pebble in flight?
		require
			has_application: has_application
		do
			settle
			Result := backend.test_is_accepting (a_target.id)
		end

	pill_tip (a_widget: GUI_WIDGET): STRING_32
			-- The tip `a_widget''s reference pill shows now; empty when it shows none.
		require
			has_application: has_application
		do
			settle
			Result := backend.from_c (backend.pill_tip_shown (a_widget.id))
		end

feature -- Evidence

	snapshot (a_window: GUI_WINDOW; a_path: PATH): BOOLEAN
			-- Render `a_window' to a PNG at `a_path', after letting the loop settle: a
			-- change made just before (a label set, rows added) is laid out first, since GTK
			-- draws nothing for a widget whose layout is still pending.
		require
			has_application: has_application
			open: not a_window.is_closed
		local
			l_c: C_STRING
		do
			settle
			l_c := backend.to_c (a_path.name)
			Result := backend.snapshot (a_window.id, l_c.item)
		end

	describe_accessibility (a_window: GUI_WINDOW): STRING_32
			-- The assistive tree of `a_window': one "role: name" line per node.
		require
			has_application: has_application
			open: not a_window.is_closed
		do
			across application.widgets as ic loop
				ic.refresh_description
			end
			Result := backend.from_c (backend.describe_accessibility (a_window.id))
		end

feature {NONE} -- Implementation

	settle
			-- Pump until idle, and again while tables are still answering rows wanted (16), so
			-- lazy rows are in place (at most 20 rounds).
		local
			l_before, l_round: INTEGER
		do
			from
				l_before := -1
			until
				l_before = rows_wanted_answered.item or l_round = 20
			loop
				l_before := rows_wanted_answered.item
				pump_until_idle (300)
				l_round := l_round + 1
			end
		end

end
