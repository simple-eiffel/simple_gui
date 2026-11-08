note
	description: "[
		An agent collection fired when GUI state changes (Larry's rule: state changes fire
		agent collections). Agents run in order, on the GUI processor.
	]"

class
	GUI_ACTIONS [G -> detachable TUPLE create default_create end]

create
	make

feature {NONE} -- Initialization

	make
		do
			create agents.make (2)
		ensure
			empty: count = 0
		end

feature -- Access

	count: INTEGER
			-- Number of agents.
		do
			Result := agents.count
		end

	fire_count: INTEGER
			-- How many times `call' has run.

feature -- Element change

	extend (an_agent: PROCEDURE [G])
			-- Run `an_agent' on every later `call'.
		do
			agents.extend (an_agent)
		ensure
			one_more: count = old count + 1
		end

	wipe_out
		do
			agents.wipe_out
		ensure
			empty: count = 0
		end

feature -- Basic operations

	call (a_arguments: G)
			-- Run every agent with `a_arguments'.
		do
			fire_count := fire_count + 1
			across agents as ic loop
				ic.call (a_arguments)
			end
		ensure
			counted: fire_count = old fire_count + 1
		end

feature {NONE} -- Implementation

	agents: ARRAYED_LIST [PROCEDURE [G]]

invariant
	agents_exist: agents /= Void

end
