note
	description: "[
		A drop target's typed actions (1q; Vision2's and EiffelStudio's pick and drop). Each
		action takes one argument, and its type says what the target takes:
			drop_actions.extend (agent take_note (?))   -- take_note (a_note: NOTE)
		A pebble goes only to the actions whose `valid_operands' take it, so a target that has
		only NOTE actions never lights for a STRING. `set_veto' adds a check beyond the type for
		the whole target; `extend_checked' adds one for a single action.
		The first action tells the backend the widget is a drop target.
	]"

class
	GUI_DROP_ACTIONS

inherit
	GUI_SHARED

create
	make

feature {NONE} -- Initialization

	make (a_target_id: INTEGER; a_first_told: PROCEDURE)
			-- Empty; `a_first_told' runs when the first action is added (the widget tells the
			-- backend what it takes, pebbles and outside drops together).
		require
			named: a_target_id > 0
		do
			target_id := a_target_id
			first_told := a_first_told
			create actions.make (2)
			create checks.make (2)
		ensure
			set: target_id = a_target_id
			empty: count = 0
		end

feature -- Access

	target_id: INTEGER
			-- The widget these actions belong to.

	count: INTEGER
		do
			Result := actions.count
		end

	veto: detachable FUNCTION [TUPLE [pebble: ANY], BOOLEAN]
			-- A further check: a pebble it answers False for is refused.

feature -- Status

	accepts (a_pebble: ANY): BOOLEAN
			-- Would a drop of `a_pebble' run at least one action?
		do
			if not attached veto as al_veto or else al_veto.item ([a_pebble]) then
				across 1 |..| actions.count as ic_i until Result loop
					Result := takes (ic_i, a_pebble)
				end
			end
		end

feature -- Element change

	extend (an_action: PROCEDURE [TUPLE [ANY]])
			-- Run `an_action' on drops of pebbles its argument takes.
		require
			gui_thread: is_gui_thread
		do
			actions.extend (an_action)
			checks.extend (Void)
			if actions.count = 1 then
				first_told.call (Void)
			end
		ensure
			one_more: count = old count + 1
		end

	extend_checked (an_action: PROCEDURE [TUPLE [ANY]]; a_check: FUNCTION [TUPLE [ANY], BOOLEAN])
			-- As `extend', but `an_action' takes only the pebbles its argument's type takes that
			-- `a_check' also answers True for (a reorderable list takes only its own rows).
		require
			gui_thread: is_gui_thread
		do
			actions.extend (an_action)
			checks.extend (a_check)
			if actions.count = 1 then
				first_told.call (Void)
			end
		ensure
			one_more: count = old count + 1
		end

	set_veto (a_veto: detachable FUNCTION [TUPLE [pebble: ANY], BOOLEAN])
		do
			veto := a_veto
		ensure
			set: veto = a_veto
		end

feature {GUI_APPLICATION} -- Basic operations

	drop (a_pebble: ANY)
			-- Run every action that takes `a_pebble'.
		require
			accepted: accepts (a_pebble)
		do
			across 1 |..| actions.count as ic_i loop
				if takes (ic_i, a_pebble) then
					actions [ic_i].call ([a_pebble])
				end
			end
		end

feature {NONE} -- Implementation

	actions: ARRAYED_LIST [PROCEDURE [TUPLE [ANY]]]

	checks: ARRAYED_LIST [detachable FUNCTION [TUPLE [ANY], BOOLEAN]]
			-- Each action's further check (Void: its type alone decides).

	takes (i: INTEGER; a_pebble: ANY): BOOLEAN
			-- Does action `i' take `a_pebble'?
		require
			valid: actions.valid_index (i)
		do
			Result := actions [i].valid_operands ([a_pebble])
				and then (not attached checks [i] as al_check or else al_check.item ([a_pebble]))
		end

	first_told: PROCEDURE
			-- Told when the first action arrives.

invariant
	actions_exist: actions /= Void
	a_check_each: checks.count = actions.count

end
