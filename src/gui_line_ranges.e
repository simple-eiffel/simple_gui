note
	description: "[
		Ranges of whole lines kept in order of their first line, one range to a first line:
		the folds a code editor finds by indentation, the folds it has closed, and the lines
		a control hides (1v-e-3).

		A range is a fold: its first line shows, and the lines after it through its last are
		what the fold hides when it is closed.

		`follow_texts' takes the ranges through an edit of the text they lie in, given the
		text before and after. A range the edit lies after stands. A range the edit lies
		before moves by the lines the edit added or took. An edit inside a range's first line
		that leaves the count of lines alone leaves the range. Any other edit that touches a
		range (its hidden lines, or a join or a split of its first line) removes it. The rule
		is here once, for the editor's closed folds and for a control's hidden lines, so the
		two never disagree.

		The order (ascending first lines, no two alike) is kept by `put' and by `follow';
		it is not in the invariant, which would walk every range at every call.
	]"
	author: "Larry Rix"

class
	GUI_LINE_RANGES

inherit
	GUI_SYNTAX_RANGES

	GUI_TEXT_COMPARISON

create
	make, make_from, make_by_indentation

feature {NONE} -- Initialization

	make
			-- No range.
		do
			create firsts.make (0)
			create lasts.make (0)
			is_disjoint := True
		ensure
			empty: count = 0
			disjoint: is_disjoint
		end

	make_from (a_ranges: GUI_SYNTAX_RANGES)
			-- The ranges of `a_ranges' that hide a line (last line after the first), in
			-- order; of those that start on one line, the one that reaches furthest.
		local
			i, n: INTEGER
		do
			make
			from
				i := 1
				n := a_ranges.count
			until
				i > n
			loop
				if a_ranges.last_line (i) > a_ranges.first_line (i) then
					put (a_ranges.first_line (i), a_ranges.last_line (i))
				end
				i := i + 1
			end
		ensure
			not_more: count <= a_ranges.count
		end

	make_by_indentation (a_text: READABLE_STRING_32; a_tab_width: INTEGER)
			-- The folds of `a_text' by indentation: a line followed by lines indented deeper
			-- folds through the last of them. Blank lines between them belong to the fold;
			-- blank lines after them do not. A tab reaches the next stop, the stops
			-- `a_tab_width' columns apart.
			-- Cost: one walk of each line's indent, and a search for each line break.
		require
			tab_width_positive: a_tab_width >= 1
		local
			l_firsts, l_lasts, l_indents, l_open: ARRAYED_LIST [INTEGER]
			l_start, j, n, l_line, l_indent, l_last_solid, k: INTEGER
			c: CHARACTER_32
			l_solid, l_done: BOOLEAN
		do
			make
			create l_firsts.make (64)
			create l_lasts.make (64)
			create l_indents.make (64)
			create l_open.make (16)
			from
				l_start := 1
				l_line := 1
				n := a_text.count
			until
				l_start > n
			loop
					-- the indent of the line, and whether anything but white space is on it
				from
					j := l_start
					l_indent := 0
					l_solid := False
					l_done := False
				until
					l_done
				loop
					if j > n then
						l_done := True
					else
						c := a_text [j]
						if c = ' ' then
							l_indent := l_indent + 1
							j := j + 1
						elseif c = '%T' then
							l_indent := (l_indent // a_tab_width + 1) * a_tab_width
							j := j + 1
						elseif c = '%R' then
							j := j + 1
						elseif c = '%N' then
							l_done := True
						else
							l_solid := True
							l_done := True
						end
					end
				end
				if l_solid then
						-- the open lines indented as deep or deeper end at the solid line before
					from
					until
						l_open.is_empty or else l_indents [l_open.last] < l_indent
					loop
						l_lasts [l_open.last] := l_last_solid
						l_open.finish
						l_open.remove
					end
					l_firsts.extend (l_line)
					l_lasts.extend (l_line)
					l_indents.extend (l_indent)
					l_open.extend (l_firsts.count)
					l_last_solid := l_line
				end
				j := a_text.index_of ('%N', j)
				if j = 0 then
					l_start := n + 1
				else
					l_start := j + 1
					l_line := l_line + 1
				end
			end
			from
			until
				l_open.is_empty
			loop
				l_lasts [l_open.last] := l_last_solid
				l_open.finish
				l_open.remove
			end
				-- the lines that fold are those with a line to hide
			from
				k := 1
			until
				k > l_firsts.count
			loop
				if l_lasts [k] > l_firsts [k] then
					firsts.extend (l_firsts [k])
					lasts.extend (l_lasts [k])
				end
				k := k + 1
			end
			note_disjoint
		end

feature -- Access

	count: INTEGER
			-- The number of ranges.
		do
			Result := firsts.count
		end

	first_line (i: INTEGER): INTEGER
			-- The first line of range `i'.
		do
			Result := firsts [i]
		end

	last_line (i: INTEGER): INTEGER
			-- The last line of range `i'.
		do
			Result := lasts [i]
		end

	index_starting_at (a_line: INTEGER): INTEGER
			-- The range that starts on `a_line'; 0 when none does.
		local
			l_low, l_high, l_middle: INTEGER
		do
			from
				l_low := 1
				l_high := firsts.count
			until
				l_low > l_high or Result > 0
			loop
				l_middle := l_low + (l_high - l_low) // 2
				if firsts [l_middle] = a_line then
					Result := l_middle
				elseif firsts [l_middle] < a_line then
					l_low := l_middle + 1
				else
					l_high := l_middle - 1
				end
			end
		ensure
			none_or_valid: Result = 0 or valid_index (Result)
			starts_there: Result > 0 implies first_line (Result) = a_line
		end

	index_hiding (a_line: INTEGER): INTEGER
			-- The range that hides `a_line' when closed (it starts before the line and
			-- reaches it); 0 when none does.
		require
			disjoint: is_disjoint
		local
			l_before: INTEGER
		do
			l_before := count_starting_before (a_line)
			if l_before > 0 and then lasts [l_before] >= a_line then
				Result := l_before
			end
		ensure
			none_or_valid: Result = 0 or valid_index (Result)
			hides_it: Result > 0 implies (first_line (Result) < a_line and a_line <= last_line (Result))
		end

	count_starting_before (a_line: INTEGER): INTEGER
			-- How many ranges start before `a_line': the number of the last of them.
		local
			l_low, l_high, l_middle: INTEGER
		do
			from
				l_low := 1
				l_high := firsts.count
			until
				l_low > l_high
			loop
				l_middle := l_low + (l_high - l_low) // 2
				if firsts [l_middle] < a_line then
					Result := l_middle
					l_low := l_middle + 1
				else
					l_high := l_middle - 1
				end
			end
		ensure
			in_range: 0 <= Result and Result <= count
			last_before: Result > 0 implies first_line (Result) < a_line
			next_is_not: Result < count implies first_line (Result + 1) >= a_line
		end

	merged: GUI_LINE_RANGES
			-- The ranges as the lines they hide together: where one starts on a line that
			-- another hides, or the two cross, the result has one range for both.
		local
			i, l_first, l_last: INTEGER
		do
			create Result.make
			from
				i := 1
			until
				i > count
			loop
				l_first := firsts [i]
				l_last := lasts [i]
				from
					i := i + 1
				until
					i > count or else firsts [i] > l_last
				loop
					l_last := l_last.max (lasts [i])
					i := i + 1
				end
				Result.put (l_first, l_last)
			end
		ensure
			disjoint: Result.is_disjoint
			not_more: Result.count <= count
		end

feature -- Status report

	valid_index (i: INTEGER): BOOLEAN
			-- Is `i' the number of a range?
		do
			Result := 1 <= i and i <= firsts.count
		end

	is_disjoint: BOOLEAN
			-- Does every range start after the last line of the one before it? (Kept as the
			-- ranges change; once lost it comes back only when the ranges are wiped out.)

	has_start (a_line: INTEGER): BOOLEAN
			-- Does a range start on `a_line'?
		do
			Result := index_starting_at (a_line) > 0
		ensure
			definition: Result = (index_starting_at (a_line) > 0)
		end

	is_hidden (a_line: INTEGER): BOOLEAN
			-- Does a range hide `a_line' when closed?
		require
			disjoint: is_disjoint
		do
			Result := index_hiding (a_line) > 0
		ensure
			definition: Result = (index_hiding (a_line) > 0)
		end

	is_same_as (a_other: GUI_SYNTAX_RANGES): BOOLEAN
			-- Are these the ranges of `a_other', in its order?
		local
			i: INTEGER
		do
			Result := count = a_other.count
			from
				i := 1
			until
				not Result or i > count
			loop
				Result := firsts [i] = a_other.first_line (i) and lasts [i] = a_other.last_line (i)
				i := i + 1
			end
		ensure
			same_count: Result implies count = a_other.count
		end

feature -- Element change

	put (a_first, a_last: INTEGER)
			-- A range from `a_first' through `a_last'. Where one starts on `a_first' already,
			-- it reaches the further of the two last lines.
		require
			first_positive: a_first >= 1
			last_not_before: a_last >= a_first
		local
			k: INTEGER
		do
			k := index_starting_at (a_first)
			if k > 0 then
				lasts [k] := lasts [k].max (a_last)
			else
				k := count_starting_before (a_first) + 1
				firsts.go_i_th (k)
				lasts.go_i_th (k)
				if k > firsts.count then
					firsts.extend (a_first)
					lasts.extend (a_last)
				else
					firsts.put_left (a_first)
					lasts.put_left (a_last)
				end
			end
			if is_disjoint then
				is_disjoint := (k = 1 or else lasts [k - 1] < a_first)
					and (k = count or else lasts [k] < firsts [k + 1])
			end
		ensure
			starts_there: has_start (a_first)
			reaches: last_line (index_starting_at (a_first)) >= a_last
			one_more_at_most: count = old count or count = old count + 1
		end

	remove_starting_at (a_line: INTEGER)
			-- No range starts on `a_line'.
		local
			k: INTEGER
		do
			k := index_starting_at (a_line)
			if k > 0 then
				remove_range (k)
			end
		ensure
			gone: not has_start (a_line)
		end

	wipe_out
			-- No range.
		do
			firsts.wipe_out
			lasts.wipe_out
			is_disjoint := True
		ensure
			empty: count = 0
			disjoint: is_disjoint
		end

feature -- Following an edit

	follow_texts (a_old, a_new: READABLE_STRING_32)
			-- The ranges lay in `a_old'; take them through the edit that made it `a_new'.
			-- The edit is what lies between the start and the end the two texts share; where
			-- those overlap (a stretch that repeats) the end gives way.
			-- Cost: one comparison of memory and the line breaks before the edit.
		local
			l_limit, l_head, l_tail, l_removed, l_inserted, l_from, l_through, l_end: INTEGER
			l_clean: BOOLEAN
		do
			l_limit := a_old.count.min (a_new.count)
			l_head := shared_head (a_new, a_old, l_limit)
			if count > 0 and (l_head < l_limit or a_old.count /= a_new.count) then
				l_tail := shared_tail (a_new, a_old, l_limit).min (l_limit - l_head)
				l_removed := a_old.count - l_head - l_tail
				l_inserted := a_new.count - l_head - l_tail
				l_from := 1 + line_breaks_in (a_old, 1, l_head)
				l_through := l_from + line_breaks_in (a_old, l_head + 1, l_head + l_removed)
				l_end := l_head + l_removed
					-- clean: the edit ends at the start of a line, and what follows it in
					-- the new text still starts one
				l_clean := l_end = 0 or else a_old [l_end] = '%N'
				if l_clean then
					if l_inserted > 0 then
						l_clean := a_new [l_head + l_inserted] = '%N'
					else
						l_clean := l_head = 0 or else a_old [l_head] = '%N'
					end
				end
				follow (l_from, l_through, l_clean,
					line_breaks_in (a_new, l_head + 1, l_head + l_inserted) - (l_through - l_from))
			end
		ensure
			not_more: count <= old count
		end

	follow (a_from, a_through: INTEGER; a_is_clean: BOOLEAN; a_delta: INTEGER)
			-- Take the ranges through an edit: its start was on line `a_from' and its end on
			-- line `a_through', lines as before the edit; it changed the count of lines by
			-- `a_delta'. `a_is_clean': the edit ended at the start of `a_through', and what
			-- follows still starts a line (whole lines were added or taken above it).
		require
			from_positive: a_from >= 1
			through_not_before: a_through >= a_from
			removes_no_more_than_it_spans: a_delta >= a_from - a_through
		local
			i, l_first, l_last: INTEGER
		do
			from
				i := 1
			until
				i > firsts.count
			loop
				l_first := firsts [i]
				l_last := lasts [i]
				if a_from > l_last then
						-- the edit lies after the range
					i := i + 1
				elseif a_through < l_first or (a_through = l_first and a_is_clean) then
						-- the edit lies before the range
					firsts [i] := l_first + a_delta
					lasts [i] := l_last + a_delta
					i := i + 1
				elseif a_through = l_first and a_delta = 0 then
						-- in the first line, and no line more or fewer
					i := i + 1
				else
					remove_range (i)
				end
			end
		ensure
			not_more: count <= old count
		end

feature {NONE} -- Implementation

	firsts: ARRAYED_LIST [INTEGER]
			-- The first line of each range, ascending, no two alike.

	lasts: ARRAYED_LIST [INTEGER]
			-- The last line of each range, beside `firsts'.

	remove_range (i: INTEGER)
			-- Range `i' is no more.
		require
			valid: valid_index (i)
		do
			firsts.go_i_th (i)
			firsts.remove
			lasts.go_i_th (i)
			lasts.remove
		ensure
			one_fewer: count = old count - 1
		end

	note_disjoint
			-- Set `is_disjoint' from the ranges.
		local
			i: INTEGER
		do
			is_disjoint := True
			from
				i := 2
			until
				not is_disjoint or i > firsts.count
			loop
				is_disjoint := lasts [i - 1] < firsts [i]
				i := i + 1
			end
		end

invariant
	one_last_for_each_first: firsts.count = lasts.count

end
