note
	description: "[
		A GUI_ASPECT_FRAME on Windows (1y-b): its height follows its width at `ratio', and its one
		child gets the largest size of that ratio that fits the space given, centered.
	]"

class
	GUI_SW_ASPECT_FRAME

inherit
	SW_COLUMN
		rename
			make as make_column
		redefine
			preferred_height, arrange
		end

create
	make

feature {NONE} -- Initialization

	make (a_ratio: REAL_64)
			-- Empty, keeping `a_ratio' (width over height).
		require
			positive: a_ratio > 0.0
		do
			make_column
			ratio := a_ratio
		ensure
			set: ratio = a_ratio
		end

feature -- Access

	ratio: REAL_64
			-- Width over height.

feature -- Element change

	set_ratio (a_ratio: REAL_64)
		require
			positive: a_ratio > 0.0
		do
			ratio := a_ratio
		ensure
			set: ratio = a_ratio
		end

feature -- Layout

	preferred_height (a_p: SW_PAINTER; a_width: REAL_64): REAL_64
			-- `a_width' at the ratio.
		do
			if a_width > 0.0 then
				Result := a_width / ratio
			else
				Result := Precursor (a_p, a_width)
			end
		end

	arrange (a_p: SW_PAINTER)
			-- The child at the largest size of the ratio that fits, centered.
		local
			l_w, l_h: REAL_64
		do
			l_w := width
			l_h := l_w / ratio
			if l_h > height then
				l_h := height
				l_w := l_h * ratio
			end
			across laid_out as ic loop
				ic.set_bounds (x + (width - l_w) / 2.0, y + (height - l_h) / 2.0, l_w, l_h)
				ic.arrange (a_p)
			end
			vanish_hidden
		end

invariant
	positive: ratio > 0.0

end
