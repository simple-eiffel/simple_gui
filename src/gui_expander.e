note
	description: "[
		A title the user clicks to show or hide one widget below it (GtkExpander; a
		disclosure triangle with a title on macOS; a drawn expander on Windows). A new
		expander is collapsed. `expand' and `collapse' never fire `toggle_actions'; only the
		user's clicks do.
	]"

class
	GUI_EXPANDER

inherit
	GUI_SINGLE_CONTAINER
		redefine
			default_accessible_label, dispatch
		end

create
	make

feature {NONE} -- Initialization

	make (a_title: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
			has_application: has_application
		local
			l_c: C_STRING
		do
			create children.make (1)
			create toggle_actions.make
			title := a_title.to_string_32
			l_c := backend.to_c (a_title)
			register (backend.expander (l_c.item))
		ensure
			titled: title.same_string_general (a_title)
			collapsed: not is_expanded
		end

feature -- Access

	title: STRING_32

	is_expanded: BOOLEAN
			-- Is the content shown?
		do
			Result := backend.expander_is_expanded (id)
		end

	toggle_actions: GUI_ACTIONS [TUPLE [is_expanded: BOOLEAN]]
			-- Run when the user shows or hides the content.

feature -- Element change

	set_title (a_title: READABLE_STRING_GENERAL)
		require
			gui_thread: is_gui_thread
		local
			l_c: C_STRING
		do
			title := a_title.to_string_32
			l_c := backend.to_c (a_title)
			backend.expander_set_title (id, l_c.item)
		ensure
			titled: title.same_string_general (a_title)
		end

	expand
			-- Show the content, without a toggled event.
		require
			gui_thread: is_gui_thread
		do
			if is_collapsing then
					-- an animated collapse on its way slides back down
				open_sliding
			else
				backend.expander_set_expanded (id, True)
			end
		ensure
			shown: is_expanded
			no_event: toggle_actions.fire_count = old toggle_actions.fire_count
		end

	collapse
			-- Hide the content, without a toggled event.
		require
			gui_thread: is_gui_thread
		do
			backend.expander_set_expanded (id, False)
		ensure
			collapsed: not is_expanded
			no_event: toggle_actions.fire_count = old toggle_actions.fire_count
		end

feature -- Animated opening and closing (1x-e)

	is_collapsing: BOOLEAN
			-- Is an animated collapse on its way? (`is_expanded' stays True until it ends.)

	animates_toggles: BOOLEAN
			-- Do the user's own clicks open and close the content with the slide too? (Off until
			-- `set_animates_toggles'.)

	set_animates_toggles (a_on: BOOLEAN)
			-- Let the user's clicks slide the content down and up (`a_on'), or show and hide it
			-- at once.
		require
			gui_thread: is_gui_thread
		do
			animates_toggles := a_on
		ensure
			set: animates_toggles = a_on
		end

	expand_animated
			-- Show the content, sliding it down from the top over the application's
			-- `animation_duration' (at once while motion is reduced); no toggled event. A collapse
			-- on its way turns back from where it is.
		require
			gui_thread: is_gui_thread
		do
			open_sliding
		ensure
			shown: is_expanded
			not_collapsing: not is_collapsing
			no_event: toggle_actions.fire_count = old toggle_actions.fire_count
		end

	collapse_animated
			-- Hide the content, sliding it up to the top over the application's
			-- `animation_duration' (at once while motion is reduced); `is_expanded' until the end;
			-- no toggled event.
		require
			gui_thread: is_gui_thread
		do
			close_sliding
		ensure
			reduced_means_collapsed: (old application.reduces_motion) implies not is_expanded
			no_event: toggle_actions.fire_count = old toggle_actions.fire_count
		end

feature {GUI_APPLICATION} -- Events

	dispatch (a_type, a_a, a_b, a_c: INTEGER)
			-- 12: the user opened (1) or closed (0) the content; the toolkit has already shown or
			-- hidden it. With `animates_toggles' it slides instead.
		do
			if a_type = 12 then
				if animates_toggles and then attached content as al_c then
					if a_a = 1 then
						is_collapsing := False
						al_c.hide
						al_c.show_animated (al_c.Effect_slide_from_top)
					elseif al_c.is_shown then
							-- open again, quietly, to slide it closed
						backend.expander_set_expanded (id, True)
						close_sliding
					end
				end
				toggle_actions.call ([a_a = 1])
			end
		end

feature {NONE} -- Sliding

	watched: detachable GUI_WIDGET
			-- The content whose animated show and hide this expander follows.

	open_sliding
			-- Expand, sliding the content down from where it is.
		do
			is_collapsing := False
			if attached content as al_c then
				if not is_expanded then
					al_c.hide
					backend.expander_set_expanded (id, True)
				end
				al_c.show_animated (al_c.Effect_slide_from_top)
			else
				backend.expander_set_expanded (id, True)
			end
		ensure
			open_now: is_expanded
			not_collapsing: not is_collapsing
		end

	close_sliding
			-- Slide the content up, then collapse (`content_animation_ended').
		do
			if is_expanded and then attached content as al_c and then al_c.is_shown then
				if watched /= al_c then
					al_c.animation_finished_actions.extend (agent content_animation_ended (al_c, ?))
					watched := al_c
				end
				is_collapsing := True
					-- with reduced motion this hides at once and its end collapses at once; the
					-- content is shown again after `hide_animated' has kept its word (hidden)
				is_hiding_content := True
				al_c.hide_animated (al_c.Effect_slide_from_top)
				is_hiding_content := False
				if is_show_pending then
					is_show_pending := False
					al_c.show
				end
			else
				is_collapsing := False
				backend.expander_set_expanded (id, False)
			end
		end

	content_animation_ended (a_content: GUI_WIDGET; a_kind: INTEGER)
			-- `a_content''s animated show or hide has ended: a hide this expander started
			-- collapses it, and the content is shown again (whole) for the next opening.
		do
			if a_kind = a_content.Kind_hidden and is_collapsing and content = a_content then
				is_collapsing := False
				backend.expander_set_expanded (id, False)
				if is_hiding_content then
					is_show_pending := True
				else
					a_content.show
				end
			end
		end

	is_hiding_content: BOOLEAN
			-- Is `close_sliding' inside the content's `hide_animated'?

	is_show_pending: BOOLEAN
			-- Must the content be shown again once that call returns?

feature {NONE} -- Implementation

	backend_set_content (a_child: INTEGER)
		do
			backend.expander_set_content (id, a_child)
		end

	default_accessible_label: STRING_32
		do
			Result := title
		end

end
