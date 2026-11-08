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

feature -- Evidence

	snapshot (a_window: GUI_WINDOW; a_path: PATH): BOOLEAN
			-- Render `a_window' to a PNG at `a_path'.
		require
			has_application: has_application
			open: not a_window.is_closed
		local
			l_c: C_STRING
		do
			l_c := backend.to_c (a_path.name)
			Result := backend.snapshot (a_window.id, l_c.item)
		end

	describe_accessibility (a_window: GUI_WINDOW): STRING_32
			-- The assistive tree of `a_window': one "role: name" line per node.
		require
			has_application: has_application
			open: not a_window.is_closed
		do
			Result := backend.from_c (backend.describe_accessibility (a_window.id))
		end

feature {NONE} -- Implementation

	settle
		do
			pump_until_idle (300)
		end

end
