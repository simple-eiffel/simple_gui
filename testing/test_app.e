note
	description: "simple_gui test runner (F_code -keep, all assertions live). Needs a display."

class
	TEST_APP

inherit
	GUI_SHARED

create
	make

feature {NONE} -- Initialization

	make
		local
			t: GUI_TESTS
			l_app: GUI_APPLICATION
		do
			print ("simple_gui tests%N%N")
			create l_app.make ("simple_gui tests", "org.simple-eiffel.simple-gui-tests")
			if not l_app.is_available then
				print ("  SKIP: no display (the toolkit did not start)%N")
			else
				create t.make (l_app)
				run_test (agent t.test_label_text_roundtrip, "label_text_roundtrip")
				run_test (agent t.test_hebrew_and_greek_roundtrip, "hebrew_and_greek_roundtrip")
				run_test (agent t.test_button_click_fires_agents, "button_click_fires_agents")
				run_test (agent t.test_set_text_fires_no_event, "set_text_fires_no_event")
				run_test (agent t.test_typing_fires_change, "typing_fires_change")
				run_test (agent t.test_select_row_fires_no_event, "select_row_fires_no_event")
				run_test (agent t.test_choosing_a_row_fires_selection, "choosing_a_row_fires_selection")
				run_test (agent t.test_containers_parent_children, "containers_parent_children")
				run_test (agent t.test_direction_cascades_to_children, "direction_cascades_to_children")
				run_test (agent t.test_menu_item_runs_its_agent, "menu_item_runs_its_agent")
				run_test (agent t.test_accessibility_tree_has_roles_and_labels, "accessibility_tree_has_roles_and_labels")
				run_test (agent t.test_canvas_presents_an_image, "canvas_presents_an_image")
				run_test (agent t.test_dark_mode_switch_fires_and_reads, "dark_mode_switch_fires_and_reads")
				run_test (agent t.test_snapshots_light_and_dark, "snapshots_light_and_dark")
				run_test (agent t.test_worker_message_arrives_through_mailbox_and_wake, "worker_message_arrives_through_mailbox_and_wake")
				run_test (agent t.test_close_request_without_agents_closes, "close_request_without_agents_closes")
				run_test (agent t.test_splitter, "splitter")
				run_test (agent t.test_wrapping_label_grows_taller, "wrapping_label_grows_taller")
				run_test (agent t.test_number_label_stays_left_to_right, "number_label_stays_left_to_right")
				run_test (agent t.test_stack_alignment, "stack_alignment")
				run_test (agent t.test_grid_columns, "grid_columns")
				run_test (agent t.test_homogeneous_columns_fill, "homogeneous_columns_fill")
				run_test (agent t.test_tabs, "tabs")
				run_test (agent t.test_menus_relabel, "menus_relabel")
				run_test (agent t.test_context_menu, "context_menu")
				run_test (agent t.test_check_box_events, "check_box_events")
				run_test (agent t.test_text_area, "text_area")
				run_test (agent t.test_table, "table")
				run_test (agent t.test_system_colors_follow_the_appearance, "system_colors_follow_the_appearance")
				run_test (agent t.test_right_to_left_keeps_numbering, "right_to_left_keeps_numbering")
				run_test (agent t.test_tree, "tree")
				run_test (agent t.test_positions_mirror, "positions_mirror")
				run_test (agent t.test_small_window_grows_to_fit, "small_window_grows_to_fit")
			end
			print ("%N=== Results: " + passed.out + " passed, " + failed.out + " failed ===%N")
			if failed = 0 and passed > 0 then
				print ("ALL TESTS PASSED%N")
			end
		end

	run_test (a_test: PROCEDURE; a_name: STRING)
			-- Run one test; any exception (contract or otherwise) fails it.
		local
			l_retried: BOOLEAN
		do
			if not l_retried then
				a_test.call (Void)
				print ("  PASS: " + a_name + "%N")
				passed := passed + 1
			end
		rescue
			print ("  FAIL: " + a_name + "%N")
			if attached (create {EXCEPTION_MANAGER}).last_exception as al_e then
				if attached al_e.tag as al_tag then
					print ("        tag: " + al_tag.to_string_8 + "%N")
				end
				if attached al_e.description as al_why then
					print ("        why: " + al_why.to_string_8 + "%N")
				end
			end
			failed := failed + 1
			l_retried := True
			retry
		end

	passed: INTEGER

	failed: INTEGER

end
