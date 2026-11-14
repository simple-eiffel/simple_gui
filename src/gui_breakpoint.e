note
	description: "[
		1y: a size at which a window or container changes its layout (W3Schools' media queries,
		CSS container queries). It matches widths at most or at least a bound, and may be
		narrowed by height bounds; every bound must hold. Its owner (GUI_BREAKING) applies the
		last added breakpoint that matches its size: `applied_actions' run when this one
		becomes the applied one, `unapplied_actions' when it stops being it. A breakpoint
		changes settings (a row into a column, a pane collapsed, fewer columns); it never moves
		a widget to another container.
	]"

class
	GUI_BREAKPOINT

create
	make_width_at_most, make_width_at_least

feature {NONE} -- Initialization

	make_width_at_most (a_width: INTEGER)
			-- Match widths of `a_width' logical pixels or less.
		require
			positive: a_width > 0
		do
			max_width := a_width
			create applied_actions.make
			create unapplied_actions.make
		ensure
			bound_set: max_width = a_width and min_width = 0
			no_height_bound: min_height = 0 and max_height = 0
			not_applied: not is_applied
			not_added: not is_added
		end

	make_width_at_least (a_width: INTEGER)
			-- Match widths of `a_width' logical pixels or more.
		require
			positive: a_width > 0
		do
			min_width := a_width
			create applied_actions.make
			create unapplied_actions.make
		ensure
			bound_set: min_width = a_width and max_width = 0
			no_height_bound: min_height = 0 and max_height = 0
			not_applied: not is_applied
			not_added: not is_added
		end

feature -- Access

	min_width, max_width, min_height, max_height: INTEGER
			-- The bounds, in logical pixels; 0 is no bound.

	applied_actions: GUI_ACTIONS [TUPLE]
			-- Run when this becomes its owner's applied breakpoint.

	unapplied_actions: GUI_ACTIONS [TUPLE]
			-- Run when this stops being its owner's applied breakpoint (before the next one's
			-- `applied_actions').

feature -- Status report

	is_applied: BOOLEAN
			-- Is this its owner's applied breakpoint now?

	is_added: BOOLEAN
			-- Has a window or container taken this breakpoint? (One owner each.)

	matches (a_width, a_height: INTEGER): BOOLEAN
			-- Does a size of `a_width' by `a_height' meet every bound?
		do
			Result := (min_width = 0 or else a_width >= min_width)
				and (max_width = 0 or else a_width <= max_width)
				and (min_height = 0 or else a_height >= min_height)
				and (max_height = 0 or else a_height <= max_height)
		ensure
			definition: Result = ((min_width = 0 or else a_width >= min_width)
				and (max_width = 0 or else a_width <= max_width)
				and (min_height = 0 or else a_height >= min_height)
				and (max_height = 0 or else a_height <= max_height))
		end

feature -- Element change

	set_height_at_most (a_height: INTEGER)
			-- Also require heights of `a_height' or less.
		require
			positive: a_height > 0
			ordered: min_height = 0 or else a_height >= min_height
			not_added: not is_added
		do
			max_height := a_height
		ensure
			set: max_height = a_height
		end

	set_height_at_least (a_height: INTEGER)
			-- Also require heights of `a_height' or more.
		require
			positive: a_height > 0
			ordered: max_height = 0 or else a_height <= max_height
			not_added: not is_added
		do
			min_height := a_height
		ensure
			set: min_height = a_height
		end

feature {GUI_BREAKING} -- Owner

	mark_added
			-- An owner took this breakpoint.
		require
			not_added: not is_added
		do
			is_added := True
		ensure
			added: is_added
		end

	apply
			-- This became the applied breakpoint.
		require
			not_applied: not is_applied
		do
			is_applied := True
			applied_actions.call (Void)
		ensure
			applied: is_applied
		end

	unapply
			-- This stopped being the applied breakpoint.
		require
			applied: is_applied
		do
			is_applied := False
			unapplied_actions.call (Void)
		ensure
			not_applied: not is_applied
		end

invariant
	bounds_non_negative: min_width >= 0 and max_width >= 0 and min_height >= 0 and max_height >= 0
	a_width_bound: min_width > 0 or max_width > 0
	widths_ordered: (min_width > 0 and max_width > 0) implies min_width <= max_width
	heights_ordered: (min_height > 0 and max_height > 0) implies min_height <= max_height
	applied_means_added: is_applied implies is_added

end
