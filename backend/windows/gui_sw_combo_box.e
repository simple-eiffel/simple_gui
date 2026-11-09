note
	description: "[
		GUI_COMBO_BOX on Windows: simple_widgets' editable combo. A commit is reported through
		`on_commit': Return in the box, or picking one of the options.
	]"

class
	GUI_SW_COMBO_BOX

inherit
	SW_COMBO
		redefine
			choose_option
		end

create
	make_combo

feature {NONE} -- Initialization

	make_combo
		do
			make_with_options
			set_on_activate (agent commit)
		end

feature -- Access

	on_commit: detachable PROCEDURE
			-- Run when the user commits the text.

feature -- Element change

	set_on_commit (a_action: PROCEDURE)
		do
			on_commit := a_action
		ensure
			set: on_commit = a_action
		end

	choose_option (a_i: INTEGER)
			-- Take option `a_i', as the user picking it: a commit.
		do
			Precursor (a_i)
			commit
		end

	commit
			-- The user committed the text.
		do
			if attached on_commit as al_action then
				al_action.call
			end
		end

end
