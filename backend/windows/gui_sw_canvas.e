note
	description: "[
		GUI_CANVAS on Windows: simple_widgets' canvas that reads to screen readers as an image
		once the program names it (set_accessible_label, kept as its accessible name), as on
		GTK and AppKit (#126: the print preview's page reads as "Page 2 of 3", an image).
		Unnamed, it stays what SW_CANVAS is.

		1z-a: it takes the wheel (`on_wheel', where the pointer is and with the modifiers held,
		reported as event 68), and as a window's cover it is `is_bare': it draws only the image
		the program presented, so the image's transparent parts show the window under it.

		1z-d: a skeleton's canvas `is_busy': a progress bar with no value to screen readers, named
		or not, and bare.
	]"

class
	GUI_SW_CANVAS

inherit
	SW_CANVAS
		redefine
			accessible_role, handle_wheel, draw
		end

create
	make

feature -- Access

	on_wheel: detachable PROCEDURE [INTEGER, REAL_64, REAL_64, INTEGER]
			-- 1z-a: the wheel turned (the delta, 120 a notch, positive away from the user) with
			-- the pointer at (x, y), canvas-relative device pixels, and these modifiers held.

	is_bare: BOOLEAN
			-- 1z-a: does it draw only its presented image, with no surface or outline of its
			-- own (a window's cover)?

	is_busy: BOOLEAN
			-- 1z-d: does it read to screen readers as busy, a progress bar with no value (a
			-- skeleton's)?

feature -- Element change

	set_on_wheel (a_action: PROCEDURE [INTEGER, REAL_64, REAL_64, INTEGER])
			-- Report the wheel to `a_action'.
		do
			on_wheel := a_action
		ensure
			set: on_wheel = a_action
		end

	set_bare (a_on: BOOLEAN)
			-- Draw only the presented image (`a_on'), or as any canvas.
		do
			is_bare := a_on
		ensure
			set: is_bare = a_on
		end

	set_busy (a_on: BOOLEAN)
			-- Read as busy (`a_on'), or as any canvas.
		do
			is_busy := a_on
		ensure
			set: is_busy = a_on
		end

feature -- Input

	handle_wheel (a_delta: INTEGER): BOOLEAN
			-- A canvas takes the wheel when the program hears it: where the pointer last rested on
			-- it (a move sets the hover point before any wheel), with the modifiers held now.
		do
			if attached on_wheel as al_wheel then
				al_wheel.call (a_delta, hover_px - x, hover_py - y, modifiers)
				Result := True
			end
		end

feature -- Drawing

	draw (a_p: SW_PAINTER)
			-- Bare: the presented image alone. Otherwise as SW_CANVAS.
		do
			if is_bare then
				a_p.push_clip (x, y, width, height)
				if attached image as al_img and then al_img.is_valid and then al_img.width > 0 and then al_img.height > 0 then
					a_p.draw_image (al_img, x, y, al_img.width / image_scale, al_img.height / image_scale)
				end
				a_p.pop_clip
			else
				Precursor (a_p)
			end
		end

feature -- Accessibility

	accessible_role: INTEGER
			-- Busy: a progress bar (with no value: SW_CANVAS gives none); else an image once
			-- named; else as SW_CANVAS.
		do
			if is_busy then
				Result := {SW_ACCESSIBILITY}.Role_progress_bar
			elseif attached accessible_name_override as al_name and then not al_name.is_empty then
				Result := {SW_ACCESSIBILITY}.Role_image
			else
				Result := Precursor
			end
		end

end
