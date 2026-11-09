note
	description: "[
		GUI_COLOR_CHOOSER on Windows: a button showing the color as a swatch which, clicked,
		asks `on_request' to open simple_widgets' color picker (in the window's sheet), as
		GtkColorDialogButton and NSColorWell open theirs. Screen readers read a button named
		Color whose value is the color as #RRGGBB.
	]"

class
	GUI_SW_COLOR_BUTTON

inherit
	SW_BUTTON
		redefine
			draw, preferred_width, default_accessible_name, accessible_value
		end

create
	make_color

feature {NONE} -- Initialization

	make_color (a_rgb: NATURAL_32)
		do
			make ("", Void)
			rgb := a_rgb
			set_on_click (agent request)
		ensure
			set: rgb = a_rgb
		end

feature -- Access

	rgb: NATURAL_32
			-- 0xRRGGBB.

	on_request: detachable PROCEDURE
			-- Opens the picker (the backend's: it knows the window).

	hex: STRING_32
			-- `rgb' as #RRGGBB.
		do
			Result := {STRING_32} "#" + rgb.to_hex_string.substring (3, 8)
		end

feature -- Element change

	set_rgb (a_rgb: NATURAL_32)
		require
			rgb_only: a_rgb <= 0xFFFFFF
		do
			rgb := a_rgb
		ensure
			set: rgb = a_rgb
		end

	set_on_request (a_action: PROCEDURE)
		do
			on_request := a_action
		end

feature -- Layout and drawing

	preferred_width (a_p: SW_PAINTER): REAL_64
		do
			Result := 48.0
		end

	draw (a_p: SW_PAINTER)
			-- The button, with the color as a swatch inside it.
		do
			Precursor (a_p)
			a_p.set_color (rgb)
			a_p.rrect_fill (x + 8.0, y + 7.0, width - 16.0, height - 14.0, 3.0)
		end

feature -- Accessibility

	default_accessible_name: STRING_32
		do
			Result := {STRING_32} "Color"
		end

	accessible_value: detachable STRING_32
		do
			Result := hex
		end

feature {NONE} -- Implementation

	request
		do
			if attached on_request as al_action then
				al_action.call
			end
		end

end
