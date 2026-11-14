note
	description: "[
		A GUI_STACK on Windows: one simple_widgets box that lays out as a column (SW_COLUMN's
		layout) or a row (SW_ROW's), and can turn from one into the other with its children
		kept (1y: `GUI_STACK.set_vertical', which a breakpoint uses). Both parents keep their
		own layout code; this class only chooses which runs.
	]"

class
	GUI_SW_STACK

inherit
	SW_ROW
		rename
			make as make_row,
			padding as row_padding,
			set_padding as set_row_padding,
			default_gap as row_default_gap,
			effective_gap as row_effective_gap,
			preferred_width as row_preferred_width,
			preferred_height as row_preferred_height,
			arrange as row_arrange,
			widget_at as row_widget_at,
			draw as row_draw,
			shows_style as row_shows_style
		end

	SW_COLUMN
		rename
			make as make_column
		redefine
			set_padding, preferred_width, preferred_height, arrange, widget_at, draw, shows_style
		select
			preferred_width, preferred_height, arrange, widget_at, draw, shows_style
		end

create
	make

feature {NONE} -- Initialization

	make (a_vertical: BOOLEAN)
			-- An empty column (`a_vertical') or row.
		do
			make_column
			is_vertical := a_vertical
		ensure
			set: is_vertical = a_vertical
			empty: children.is_empty
		end

feature -- Access

	is_vertical: BOOLEAN
			-- Does this lay out as a column? (Otherwise as a row.)

feature -- Element change

	set_vertical (a_on: BOOLEAN)
			-- Lay out as a column (`a_on') or a row from now on.
		do
			is_vertical := a_on
		ensure
			set: is_vertical = a_on
		end

	set_padding (a_pad: REAL_64)
			-- <Precursor> Both layouts keep it.
		do
			Precursor {SW_COLUMN} (a_pad)
			set_row_padding (a_pad)
		ensure then
			row_too: row_padding = a_pad
		end

feature -- Layout

	preferred_width (a_p: SW_PAINTER): REAL_64
		do
			if is_vertical then
				Result := Precursor {SW_COLUMN} (a_p)
			else
				Result := row_preferred_width (a_p)
			end
		end

	preferred_height (a_p: SW_PAINTER; a_width: REAL_64): REAL_64
		do
			if is_vertical then
				Result := Precursor {SW_COLUMN} (a_p, a_width)
			else
				Result := row_preferred_height (a_p, a_width)
			end
		end

	arrange (a_p: SW_PAINTER)
		do
			if is_vertical then
				Precursor {SW_COLUMN} (a_p)
			else
				row_arrange (a_p)
			end
		end

feature -- Drawing

	shows_style (a_part: INTEGER): BOOLEAN
		do
			if is_vertical then
				Result := Precursor {SW_COLUMN} (a_part)
			else
				Result := row_shows_style (a_part)
			end
		end

	draw (a_p: SW_PAINTER)
		do
			if is_vertical then
				Precursor {SW_COLUMN} (a_p)
			else
				row_draw (a_p)
			end
		end

feature -- Hit testing

	widget_at (a_px, a_py: REAL_64): detachable SW_WIDGET
		do
			if is_vertical then
				Result := Precursor {SW_COLUMN} (a_px, a_py)
			else
				Result := row_widget_at (a_px, a_py)
			end
		end

end
