note
	description: "[
		A widget made of rows (a list, a table, a tree) whose rows can each carry a pebble (1q):
		`set_row_pebble_function' answers the pebble for a row (a tree passes its node id).
		A pick on a row lifts that row's pebble; a press outside the rows lifts the widget's own.
	]"

deferred class
	GUI_ROW_SOURCE

inherit
	GUI_WIDGET
		redefine
			pebble_at_row, has_row_pebbles
		end

feature -- Pick and drop (1q)

	row_pebble_function: detachable FUNCTION [TUPLE [row: INTEGER], detachable ANY]
			-- The pebble each row carries.

	set_row_pebble_function (a_function: detachable FUNCTION [TUPLE [row: INTEGER], detachable ANY])
			-- Let each row carry the pebble `a_function' answers for it (Void: rows carry none).
		require
			gui_thread: is_gui_thread
		do
			row_pebble_function := a_function
			tell_pick
		ensure
			set: row_pebble_function = a_function
		end

	has_row_pebbles: BOOLEAN
		do
			Result := row_pebble_function /= Void
		end

	pebble_at_row (a_row: INTEGER): detachable ANY
		do
			if a_row > 0 and then attached row_pebble_function as al_f then
				Result := al_f.item ([a_row])
			else
				Result := pebble
			end
		end

end
