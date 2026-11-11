note
	description: "[
		GUI_RICH_TEXT_AREA on Windows: simple_widgets' text box with a style per character
		(bold, italic, underline, color, size). Weight, slant and size are real glyphs: the
		box's text styles, set at the largest size used, each smaller run scaled down from it
		(down to the shaper's least scale). Color and underline are marks, drawn over
		those same glyphs in exactly the color asked. The user's edits keep the styles in step:
		the old text and the new are compared, and the changed middle takes the style of the
		character before it. Positions are 1-based characters, ranges inclusive.

		Cost: the text styles lay the whole text out again when they are set, so they are
		set only when a weight, a slant or a size changed (`is_glyph_stale'); a change of
		color rebuilds the marks alone (`is_style_stale'), and the layout stands.
		Keeping the styles in step compares the two texts a block at a time
		(GUI_TEXT_COMPARISON) and edits the list of styles as one block (SW_LIST_BLOCKS).
	]"

class
	GUI_SW_RICH_TEXT_AREA

inherit
	SW_TEXT_BOX
		redefine
			changed, set_text, ensure_layout
		end

	GUI_TEXT_COMPARISON

create
	make_rich

feature {NONE} -- Initialization

	make_rich (a_body_size: REAL_64)
			-- An empty box whose unsized text is `a_body_size' (the theme's body size).
		require
			positive: a_body_size > 0.0
		do
			body_points := a_body_size
			make ("")
			create styles.make (0)
			create known_text.make_empty
		ensure
			empty: styles.is_empty
			body_set: body_points = a_body_size
		end

feature -- Access

	body_points: REAL_64
			-- The size of text with no size of its own.

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
			if styles.count /= text.count then
				sync
			end
			from i := a_start until i > an_end loop
				inspect a_trait
				when 1 then styles.i_th (i).bold := a_on
				when 2 then styles.i_th (i).italic := a_on
				else styles.i_th (i).underline := a_on
				end
				i := i + 1
			end
			is_style_stale := True
			if a_trait <= 2 then
				is_glyph_stale := True
			end
		end

	set_color (a_start, an_end, a_rgb: INTEGER)
		require
			range: 1 <= a_start and a_start <= an_end and an_end <= text.count
		local
			i: INTEGER
		do
			if styles.count /= text.count then
				sync
			end
			from i := a_start until i > an_end loop
				styles.i_th (i).color := a_rgb
				i := i + 1
			end
			is_style_stale := True
		end

	set_size (a_start, an_end: INTEGER; a_points: REAL_64)
		require
			range: 1 <= a_start and a_start <= an_end and an_end <= text.count
		local
			i: INTEGER
		do
			if styles.count /= text.count then
				sync
			end
			from i := a_start until i > an_end loop
				styles.i_th (i).size := a_points
				i := i + 1
			end
			is_style_stale := True
			is_glyph_stale := True
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

	is_style_stale: BOOLEAN
			-- Do the box's marks (color, underline) lag behind `styles'? They are rebuilt
			-- once, at the next layout, however many ranges were set since (a highlighter
			-- sets thousands in a row).

	is_glyph_stale: BOOLEAN
			-- Do the box's text styles (weight, slant, size) lag behind `styles'? Setting
			-- them lays the whole text out again, so a change of color alone leaves them be.

	has_glyph_styles: BOOLEAN
			-- Did the last `apply_text_styles' set some character bold, italic or sized?
			-- (False: `styles' holds colors and underlines only, and an edit needs no new
			-- text styles.)

	changed
			-- An edit: keep the styles in step, then report.
		do
			sync
			is_style_stale := True
			is_glyph_stale := is_glyph_stale or has_glyph_styles
			Precursor
		end

	ensure_layout (a_p: SW_PAINTER; a_wrap: REAL_64)
			-- Bring the box's text styles up to date first (the layout is shaped by them),
			-- and its marks after (they are painted over it).
		do
			if is_glyph_stale then
				sync
				apply_text_styles
				is_glyph_stale := False
			end
			Precursor (a_p, a_wrap)
			if is_style_stale then
				sync
				refresh_marks
			end
		end

	refresh_marks
			-- Rebuild the marks from `styles'. (A descendant that shows part of a long text
			-- marks only that part, when it draws.)
		require
			matched: styles.count = text.count
		do
			apply_marks (1, styles.count)
			is_style_stale := False
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
			set_text_styles (Void)
			set_text_size (0.0)
			is_style_stale := False
			is_glyph_stale := False
			has_glyph_styles := False
		ensure
			matched: styles.count = text.count
			fresh: not is_style_stale and not is_glyph_stale
			plain: not has_glyph_styles
		end

	sync
			-- Match `styles' to an edited text: the common start and end keep theirs; the
			-- changed middle takes the style of the character before it.
			-- The texts are compared a block at a time and `styles' is edited as one block.
		local
			p, s, i, l_old, l_new, l_limit, l_inserted: INTEGER
			l_like: TUPLE [bold, italic, underline: BOOLEAN; color: INTEGER; size: REAL_64]
			l_blocks: SW_LIST_BLOCKS [TUPLE [bold, italic, underline: BOOLEAN; color: INTEGER; size: REAL_64]]
		do
			if not text.same_string (known_text) then
				l_old := known_text.count
				l_new := text.count
				l_limit := l_old.min (l_new)
				p := shared_head (text, known_text, l_limit)
				s := shared_tail (text, known_text, l_limit - p)
				if p >= 1 then
					l_like := styles.i_th (p)
				else
					l_like := [False, False, False, -1, 0.0]
				end
				l_inserted := l_new - s - p
				create l_blocks
				l_blocks.splice (styles, p, l_old - s - p, l_inserted, l_like)
					-- a style of its own for each new character: they are set one by one
				from i := p + 1 until i > p + l_inserted loop
					styles.put_i_th ([l_like.bold, l_like.italic, l_like.underline, l_like.color, l_like.size], i)
					i := i + 1
				end
				known_text := text.twin
			end
		ensure
			matched: styles.count = text.count
		end

	apply_text_styles
			-- Per run of equal style: weight, slant and size as the box's text styles (real
			-- glyphs, at the largest size used, smaller runs scaled down from it). The box
			-- lays its text out again.
		require
			matched: styles.count = text.count
		local
			i, j, l_weight: INTEGER
			a: TUPLE [bold, italic, underline: BOOLEAN; color: INTEGER; size: REAL_64]
			l_base, l_size: REAL_64
			l_styles: like new_text_styles
		do
			l_base := body_points
			across styles as c loop
				l_base := l_base.max (c.size)
			end
			l_styles := new_text_styles
			from i := 1 until i > styles.count loop
				a := styles.i_th (i)
				from j := i until j + 1 > styles.count or else not same_look (a, styles.i_th (j + 1)) loop
					j := j + 1
				end
				l_size := a.size
				if l_size <= 0.0 then
					l_size := body_points
				end
				if a.bold or a.italic or l_size < l_base then
					l_weight := 0
					if a.bold then
						l_weight := l_styles.Weight_bold
					end
					l_styles.add_setting (i, j - i + 1, (l_size / l_base).max (l_styles.Min_scale).min (1.0),
						0.0, False, l_weight, a.italic, 0)
				end
				i := j + 1
			end
			if l_base > body_points then
				set_text_size (l_base)
			else
				set_text_size (0.0)
			end
			if l_styles.is_empty then
				set_text_styles (Void)
			else
				set_text_styles (l_styles)
			end
			has_glyph_styles := not l_styles.is_empty or l_base > body_points
		end

	apply_marks (a_first, a_last: INTEGER)
			-- One mark per run of equal style among characters `a_first' to `a_last' that
			-- has a color or an underline, drawn over the glyphs; no mark anywhere else
			-- (`a_last' < `a_first': none at all).
		require
			matched: styles.count = text.count
			first_in_text: a_first >= 1
			last_in_text: a_last <= styles.count
		do
			marks.clear
			marks.clamp_to (text.count)
			add_marks (a_first, a_last)
		end

	add_marks (a_first, a_last: INTEGER)
			-- As `apply_marks', beside the marks there are: for a view of several
			-- stretches (the code editor's, around its closed folds).
		require
			matched: styles.count = text.count
			first_in_text: a_first >= 1
			last_in_text: a_last <= styles.count
		local
			i, j: INTEGER
			l_mark: SW_MARK
			a: TUPLE [bold, italic, underline: BOOLEAN; color: INTEGER; size: REAL_64]
		do
			from i := a_first until i > a_last loop
				a := styles.i_th (i)
				from j := i until j + 1 > a_last or else not same_look (a, styles.i_th (j + 1)) loop
					j := j + 1
				end
				if a.underline or a.color >= 0 then
					create l_mark.make ({SW_MARK}.Hue_blue)
					if a.color >= 0 then
						l_mark := l_mark.with_ink (a.color.to_natural_32)
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
			Result := a.bold = b.bold and a.italic = b.italic and a.underline = b.underline
				and a.color = b.color and a.size = b.size
		end

invariant
	styles_exist: styles /= Void
	styles_match_known_text: styles.count = known_text.count
	body_positive: body_points > 0.0

end
