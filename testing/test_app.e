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
				run_test (agent t.test_splitter_near_an_edge, "splitter_near_an_edge")
				run_test (agent t.test_a_big_table_fills, "a_big_table_fills")
				run_test (agent t.test_a_row_source_asks_only_for_rows_in_view, "a_row_source_asks_only_for_rows_in_view")
				run_test (agent t.test_refresh_rows_asks_again, "refresh_rows_asks_again")
				run_test (agent t.test_a_row_source_selects_by_number, "a_row_source_selects_by_number")
				run_test (agent t.test_set_row_count_resizes, "set_row_count_resizes")
				run_test (agent t.test_edit_items_follow_the_focus, "edit_items_follow_the_focus")
				run_test (agent t.test_dropdown_extend_selects_first_silently, "dropdown_extend_selects_first_silently")
				run_test (agent t.test_dropdown_select_row_is_silent_and_choose_option_emits, "dropdown_select_row_is_silent_and_choose_option_emits")
				run_test (agent t.test_dropdown_wipe_out_clears, "dropdown_wipe_out_clears")
				run_test (agent t.test_spin_box_set_value_is_silent_and_enter_number_emits, "spin_box_set_value_is_silent_and_enter_number_emits")
				run_test (agent t.test_spin_box_range_and_step, "spin_box_range_and_step")
				run_test (agent t.test_progress_bar_value_round_trips, "progress_bar_value_round_trips")
				run_test (agent t.test_toolbar_buttons_click_and_disable, "toolbar_buttons_click_and_disable")
				run_test (agent t.test_status_bar_text_round_trips, "status_bar_text_round_trips")
				run_test (agent t.test_window_with_toolbar_and_status_bar_describes_roles, "window_with_toolbar_and_status_bar_describes_roles")
				run_test (agent t.test_window_with_toolbar_and_status_bar_snapshot, "window_with_toolbar_and_status_bar_snapshot")
				run_test (agent t.test_radio_group_and_segmented_choose, "radio_group_and_segmented_choose")
				run_test (agent t.test_slider_and_switch, "slider_and_switch")
				run_test (agent t.test_date_time_and_color_round_trip, "date_time_and_color_round_trip")
				run_test (agent t.test_combo_box_commits, "combo_box_commits")
				run_test (agent t.test_containers_hold_their_content, "containers_hold_their_content")
				run_test (agent t.test_image_separator_and_tooltip, "image_separator_and_tooltip")
				run_test (agent t.test_tree_table_cells, "tree_table_cells")
				run_test (agent t.test_dialogs_cancel_unattended, "dialogs_cancel_unattended")
				run_test (agent t.test_window_of_1h_controls_describes_roles, "window_of_1h_controls_describes_roles")
				run_test (agent t.test_window_of_1h_controls_snapshot, "window_of_1h_controls_snapshot")
				run_test (agent t.test_calendar_round_trips_and_emits, "calendar_round_trips_and_emits")
				run_test (agent t.test_menu_button_items_and_split_click, "menu_button_items_and_split_click")
				run_test (agent t.test_level_bar_thresholds, "level_bar_thresholds")
				run_test (agent t.test_popover_shows_hides_and_reports_dismissal, "popover_shows_hides_and_reports_dismissal")
				run_test (agent t.test_search_field_types_and_activates, "search_field_types_and_activates")
				run_test (agent t.test_token_field_makes_and_removes_tokens, "token_field_makes_and_removes_tokens")
				run_test (agent t.test_path_control_parts, "path_control_parts")
				run_test (agent t.test_rating_set_silently_and_user_emits, "rating_set_silently_and_user_emits")
				run_test (agent t.test_rich_text_ranges_round_trip, "rich_text_ranges_round_trip")
				run_test (agent t.test_dialogs_1j_cancel_unattended, "dialogs_1j_cancel_unattended")
				run_test (agent t.test_window_of_1j_controls_describes_roles, "window_of_1j_controls_describes_roles")
				run_test (agent t.test_window_of_1j_controls_snapshot, "window_of_1j_controls_snapshot")
				run_test (agent t.test_reference_pills_show_their_tips, "reference_pills_show_their_tips")
				run_test (agent t.test_timers_fire_and_cancel, "timers_fire_and_cancel")
				run_test (agent t.test_clipboard_round_trip, "clipboard_round_trip")
				run_test (agent t.test_window_shortcut_fires, "window_shortcut_fires")
				run_test (agent t.test_fullscreen_toggles, "fullscreen_toggles")
				run_test (agent t.test_appearance_can_be_chosen, "appearance_can_be_chosen")
				run_test (agent t.test_scrolling_into_view, "scrolling_into_view")
				run_test (agent t.test_pick_and_drop_typed, "pick_and_drop_typed")
				run_test (agent t.test_files_and_text_dropped_in, "files_and_text_dropped_in")
				run_test (agent t.test_dragged_out_to_other_programs, "dragged_out_to_other_programs")
				run_test (agent t.test_list_rows_reorder, "list_rows_reorder")
				run_test (agent t.test_tree_nodes_move, "tree_nodes_move")
				run_test (agent t.test_tokens_move, "tokens_move")
				run_test (agent t.test_file_field_takes_a_dropped_file, "file_field_takes_a_dropped_file")
				run_test (agent t.test_dock_sides_tabs_sizes_and_collapse, "dock_sides_tabs_sizes_and_collapse")
				run_test (agent t.test_dock_layout_round_trip, "dock_layout_round_trip")
				run_test (agent t.test_dock_floats_hides_and_maximizes, "dock_floats_hides_and_maximizes")
				run_test (agent t.test_dock_layout_keeps_1r_b_states, "dock_layout_keeps_1r_b_states")
				run_test (agent t.test_password_field_reveals_and_hides, "password_field_reveals_and_hides")
				run_test (agent t.test_validation_kinds_and_live_check, "validation_kinds_and_live_check")
				run_test (agent t.test_autocomplete_suggests_and_fills, "autocomplete_suggests_and_fills")
				run_test (agent t.test_file_field_shows_the_path, "file_field_shows_the_path")
				run_test (agent t.test_dropdown_groups_do_not_count, "dropdown_groups_do_not_count")
				run_test (agent t.test_date_time_and_month_pickers_round_trip, "date_time_and_month_pickers_round_trip")
				run_test (agent t.test_range_slider_keeps_low_below_high, "range_slider_keeps_low_below_high")
				run_test (agent t.test_list_multiple_selection, "list_multiple_selection")
				run_test (agent t.test_window_of_1p_controls_describes_roles, "window_of_1p_controls_describes_roles")
				run_test (agent t.test_window_of_1p_controls_snapshot, "window_of_1p_controls_snapshot")
				run_test (agent t.test_feedback_spinner_info_bar_toast_notify, "feedback_spinner_info_bar_toast_notify")
				run_test (agent t.test_every_icon_shows_on_a_button, "every_icon_shows_on_a_button")
				run_test (agent t.test_styles_badges_and_busy, "styles_badges_and_busy")
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
				if attached (create {EXECUTION_ENVIRONMENT}).item ("GUI_TRACE") and then attached al_e.trace as al_trace then
						-- GUI_TRACE=1: where it failed
					print (al_trace.to_string_8 + "%N")
				end
			end
			failed := failed + 1
			l_retried := True
			retry
		end

	passed: INTEGER

	failed: INTEGER

end
