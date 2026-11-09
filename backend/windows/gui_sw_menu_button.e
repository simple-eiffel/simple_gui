note
	description: "[
		GUI_MENU_BUTTON on Windows: a button that opens a menu (simple_widgets' drawn popup)
		filled, when opened, by `filler' (the backend's: it holds the menu's items).
	]"

class
	GUI_SW_MENU_BUTTON

inherit
	SW_BUTTON
		redefine
			handle_click, draw, preferred_width
		end

create
	make_menu

feature {NONE} -- Initialization

	make_menu (a_text: READABLE_STRING_GENERAL)
		do
			make (a_text, Void)
		end

feature -- Access

	filler: detachable PROCEDURE [SW_MENU]
			-- Puts the menu's items in a new menu.

feature -- Element change

	set_filler (a_action: PROCEDURE [SW_MENU])
		do
			filler := a_action
		end

feature -- Layout and drawing

	preferred_width (a_p: SW_PAINTER): REAL_64
			-- Room for the chevron.
		do
			Result := Precursor (a_p) + 16.0
		end

	draw (a_p: SW_PAINTER)
			-- The button, with a drawn chevron at its trailing edge (no glyph: every font draws it).
		local
			cx, cy: REAL_64
		do
			Precursor (a_p)
			if label.is_empty then
				cx := x + width / 2.0 - 5.0
			else
				cx := x + width - 20.0
			end
			cy := y + height / 2.0 - 2.0
			a_p.set_color (a_p.theme.ink_muted)
			a_p.line (cx, cy, cx + 5.0, cy + 5.0, 1.6)
			a_p.line (cx + 5.0, cy + 5.0, cx + 10.0, cy, 1.6)
		end

feature -- Input

	handle_click (a_px, a_py: REAL_64): BOOLEAN
			-- Open the menu.
		local
			l_menu: SW_MENU
		do
			if is_enabled and then attached filler as al_fill then
				create l_menu.make
				al_fill.call ([l_menu])
				pending_menu := l_menu
				Result := True
			else
				Result := Precursor (a_px, a_py)
			end
		end

end
