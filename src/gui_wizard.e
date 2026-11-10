note
	description: "[
		A wizard (1t, a "multiple step form"): a header ("Step 2 of 4: Address"), a progress
		bar, the step's page, and Back, Next (Finish on the last step) and Cancel. Each step
		may have a `can_advance' check: Next and Finish ask it, and a False stays on the step,
		whose page shows its own errors (1p). A shared composite of GUI_LABEL, GUI_PROGRESS_BAR,
		a tabless GUI_TABS and GUI_BUTTONs. `go_to_step' fires nothing; the user's buttons do.
	]"

class
	GUI_WIZARD

inherit
	GUI_STACK
		rename
			make_vertical as make_stack
		export
			{NONE} make_stack, make_horizontal, extend, extend_stretching, extend_aligned
		end

create
	make

feature {NONE} -- Initialization

	make
			-- No steps yet.
		require
			gui_thread: is_gui_thread
			has_application: has_application
		local
			l_row: GUI_STACK
		do
				-- every part first: the stack registers Current, which must then be whole
			create titles.make (4)
			create checks.make (4)
			create step_changed_actions.make
			create finish_actions.make
			create cancel_actions.make
			create header.make (" ")
			create progress.make
			create pages.make
			pages.set_tab_position (pages.Tabs_none)
			create back_button.make ("Back")
			create next_button.make ("Next")
			create cancel_button.make ("Cancel")
			make_stack
			set_spacing (8)
			back_button.click_actions.extend (agent go_back)
			next_button.click_actions.extend (agent go_next)
			cancel_button.click_actions.extend (agent cancel_by_user)
			extend (header)
			extend (progress)
			extend_stretching (pages)
			create l_row.make_horizontal
			l_row.set_spacing (8)
			l_row.extend (cancel_button)
			l_row.extend_stretching (create {GUI_LABEL}.make (""))
			l_row.extend (back_button)
			l_row.extend (next_button)
			extend (l_row)
			refresh
		ensure
			no_steps: step_count = 0 and step = 0
		end

feature -- Access

	step: INTEGER
			-- The step shown; 0 before any.
		do
			Result := pages.selected_index
		end

	step_count: INTEGER
		do
			Result := titles.count
		end

	step_title (i: INTEGER): STRING_32
		require
			valid: 1 <= i and i <= step_count
		do
			Result := titles [i]
		end

	back_button, next_button, cancel_button: GUI_BUTTON

	step_changed_actions: GUI_ACTIONS [TUPLE [step: INTEGER]]
			-- Run after the user's Back or Next moved to another step.

	finish_actions: GUI_ACTIONS [TUPLE]
			-- Run when the user's Finish passed the last step's check.

	cancel_actions: GUI_ACTIONS [TUPLE]
			-- Run when the user presses Cancel.

	can_advance (i: INTEGER): BOOLEAN
			-- Does step `i''s check (if any) let the user go on?
		require
			valid: 1 <= i and i <= step_count
		do
			Result := attached checks [i] as al_check implies al_check.item (Void)
		end

feature -- Element change

	extend_step (a_page: GUI_WIDGET; a_title: READABLE_STRING_GENERAL)
			-- Add a step showing `a_page'. The first step added is shown.
		require
			gui_thread: is_gui_thread
			not_parented: a_page.parent = Void
			has_title: not a_title.is_empty
		do
			titles.extend (a_title.to_string_32)
			checks.extend (Void)
			pages.extend (a_page, a_title)
			refresh
		ensure
			one_more: step_count = old step_count + 1
			first_shown: old step_count = 0 implies step = 1
		end

	set_can_advance (i: INTEGER; a_check: detachable FUNCTION [BOOLEAN])
			-- Step `i''s check before Next or Finish; Void: none.
		require
			valid: 1 <= i and i <= step_count
		do
			checks [i] := a_check
		end

	go_to_step (i: INTEGER)
			-- Show step `i', without an event or a check.
		require
			gui_thread: is_gui_thread
			valid: 1 <= i and i <= step_count
		do
			pages.select_page (i)
			refresh
		ensure
			shown: step = i
		end

	refresh
			-- The header, progress and buttons for the current step.
		do
			if step_count = 0 then
				header.set_text (" ")
				progress.set_value (0)
				back_button.disable
				next_button.disable
			else
				header.set_text ({STRING_32} "Step " + step.out + " of " + step_count.out + ": " + titles [step])
				progress.set_value ((step * 100) // step_count)
				if step > 1 then back_button.enable else back_button.disable end
				next_button.enable
				if step = step_count then next_button.set_text ("Finish") else next_button.set_text ("Next") end
			end
		end

feature {NONE} -- Implementation

	header: GUI_LABEL
	progress: GUI_PROGRESS_BAR
	pages: GUI_TABS
	titles: ARRAYED_LIST [STRING_32]
	checks: ARRAYED_LIST [detachable FUNCTION [BOOLEAN]]

	go_back
		do
			if step > 1 then
				pages.select_page (step - 1)
				refresh
				step_changed_actions.call ([step])
			end
		end

	go_next
		do
			if step >= 1 and then can_advance (step) then
				if step < step_count then
					pages.select_page (step + 1)
					refresh
					step_changed_actions.call ([step])
				else
					finish_actions.call ([])
				end
			end
		end

	cancel_by_user
		do
			cancel_actions.call ([])
		end

invariant
	one_check_each: checks.count = titles.count

end
