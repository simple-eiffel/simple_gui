note
	description: "[
		GUI_RICH_TEXT_AREA on Windows: simple_widgets' text box with a style per character
		(bold, italic, underline, color, size), drawn as marks: bold, italic, underline and
		exact-color ink show in the text. Point size is kept and read back but not yet drawn
		(simple_widgets' text box lays out one size). The user's edits keep the styles in step:
		the old text and the new are compared, and the changed middle takes the style of the
		character before it. Positions are 1-based characters, ranges inclusive.
	]"

class
	GUI_SW_RICH_TEXT_AREA

inherit
	SW_TEXT_BOX
		redefine
			changed, set_text
		end

create
	make_rich

feature {NONE} -- Initialization

	make_rich
		do
			make ("")
			create styles.make (0)
			create known_text.make_empty
		ensure
			empty: styles.is_empty
		end

feature -- Access

	styles: ARRAYED_LIST [TUPLE [bold, italic, underline: BOOLEAN; color: INTEGER; size: REAL_64]]
			-- One per character: color -1 is the theme's ink, size 0 the box's own.

	style_at (i: INTEGER): TUPLE [bold, italic, underline: BOOLEAN; color: INTEGER; size: REAL_64]
		require
			valid: 1 <= i and i <= text.count
		do
			sync
			Result := styles.i_th (i)
		end

feature -- Element change

	set_text (a_text: READABLE_STRING_GENERAL)
			-- New text, plain.
		do
			Precursor (a_text)
			reset_styles
		end

	set_trait (a_start, an_end, a_trait: INTEGER; a_on: BOOLEAN)
			-- 1 bold, 2 italic, 3 underline over [a_start, an_end].
		require
			range: 1 <= a_start and a_start <= an_end and an_end <= text.count
			known: 1 <= a_trait and a_trait <= 3
		local
			i: INTEGER
		do
			sync
			from i := a_start until i > an_end loop
				inspect a_trait
				when 1 then styles.i_th (i).bold := a_on
				when 2 then styles.i_th (i).italic := a_on
				else styles.i_th (i).underline := a_on
				end
				i := i + 1
			end
			redraw_marks
		end

	set_color (a_start, an_end, a_rgb: INTEGER)
		require
			range: 1 <= a_start and a_start <= an_end and an_end <= text.count
		local
			i: INTEGER
		do
			sync
			from i := a_start until i > an_end loop
				styles.i_th (i).color := a_rgb
				i := i + 1
			end
			redraw_marks
		end

	set_size (a_start, an_end: INTEGER; a_points: REAL_64)
		require
			range: 1 <= a_start and a_start <= an_end and an_end <= text.count
		local
			i: INTEGER
		do
			sync
			from i := a_start until i > an_end loop
				styles.i_th (i).size := a_points
				i := i + 1
			end
		end

feature -- Selection (1-based, inclusive; end = start - 1 when nothing is selected)

	selection_first: INTEGER
		do
			Result := caret.min (sel_anchor) + 1
		end

	selection_last: INTEGER
		do
			Result := caret.max (sel_anchor)
		end

	select_characters (a_start, an_end: INTEGER)
		require
			range: 1 <= a_start and a_start <= an_end + 1 and an_end <= text.count
		do
			sel_anchor := a_start - 1
			caret := an_end
		end

feature {NONE} -- Implementation

	known_text: STRING_32
			-- The text `styles' was last matched to.

	changed
			-- An edit: keep the styles in step, then report.
		do
			sync
			redraw_marks
			Precursor
		end

	reset_styles
		local
			i: INTEGER
		do
			styles.wipe_out
			from i := 1 until i > text.count loop
				styles.extend ([False, False, False, -1, 0.0])
				i := i + 1
			end
			known_text := text.twin
			marks.clear
		ensure
			matched: styles.count = text.count
		end

	sync
			-- Match `styles' to an edited text: the common start and end keep theirs; the
			-- changed middle takes the style of the character before it.
		local
			p, s, i, l_old, l_new: INTEGER
			l_like: TUPLE [bold, italic, underline: BOOLEAN; color: INTEGER; size: REAL_64]
		do
			if not text.same_string (known_text) then
				l_old := known_text.count
				l_new := text.count
				from p := 0 until p >= l_old or p >= l_new or else known_text.item (p + 1) /= text.item (p + 1) loop
					p := p + 1
				end
				from s := 0 until s >= l_old - p or s >= l_new - p or else known_text.item (l_old - s) /= text.item (l_new - s) loop
					s := s + 1
				end
					-- drop the old middle
				from i := l_old - s until i <= p loop
					styles.go_i_th (i)
					styles.remove
					i := i - 1
				end
					-- insert the new middle, styled like the character before it
				if p >= 1 and p <= styles.count then
					l_like := styles.i_th (p)
				else
					l_like := [False, False, False, -1, 0.0]
				end
				from i := 1 until i > l_new - s - p loop
					styles.go_i_th (p + i - 1)
					styles.put_right ([l_like.bold, l_like.italic, l_like.underline, l_like.color, l_like.size])
					i := i + 1
				end
				known_text := text.twin
			end
		ensure
			matched: styles.count = text.count
		end

	redraw_marks
			-- One mark per run of equal visible style.
		local
			i, j: INTEGER
			l_mark: SW_MARK
			a, b: TUPLE [bold, italic, underline: BOOLEAN; color: INTEGER; size: REAL_64]
		do
			marks.clear
			marks.clamp_to (text.count)
			from i := 1 until i > styles.count loop
				a := styles.i_th (i)
				from j := i until j + 1 > styles.count or else not same_look (a, styles.i_th (j + 1)) loop
					j := j + 1
				end
				if a.bold or a.italic or a.underline or a.color >= 0 then
					create l_mark.make ({SW_MARK}.Hue_blue)
					if a.color >= 0 then
						l_mark := l_mark.with_ink (a.color.to_natural_32)
					end
					if a.bold then
						l_mark := l_mark.bold
					end
					if a.italic then
						l_mark := l_mark.italic
					end
					if a.underline then
						l_mark := l_mark.underlined
					end
					marks.mark_range_with (i - 1, j, "rich", l_mark).do_nothing
				end
				i := j + 1
			end
		end

	same_look (a, b: TUPLE [bold, italic, underline: BOOLEAN; color: INTEGER; size: REAL_64]): BOOLEAN
		do
			Result := a.bold = b.bold and a.italic = b.italic and a.underline = b.underline and a.color = b.color
		end

invariant
	styles_exist: styles /= Void

end
