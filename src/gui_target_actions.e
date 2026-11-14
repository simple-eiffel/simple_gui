note
	description: "[
		Agents a widget runs whose first agent the widget must hear of, so it can tell the
		toolkit: drops from another program (1q-b) and size reports (1y).
	]"

class
	GUI_TARGET_ACTIONS [G -> detachable TUPLE create default_create end]

inherit
	GUI_ACTIONS [G]
		rename
			make as make_actions
		redefine
			extend
		end

create
	make

feature {NONE} -- Initialization

	make (a_first_told: PROCEDURE)
			-- Empty; `a_first_told' runs when the first agent is added.
		do
			make_actions
			first_told := a_first_told
		ensure
			empty: count = 0
		end

feature -- Element change

	extend (an_agent: PROCEDURE [G])
		do
			Precursor (an_agent)
			if count = 1 then
				first_told.call (Void)
			end
		end

feature {NONE} -- Implementation

	first_told: PROCEDURE
			-- Told when the first agent arrives.

end
