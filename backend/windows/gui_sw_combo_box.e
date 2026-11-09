note
	description: "[
		GUI_COMBO_BOX on Windows: simple_widgets' editable combo. The user commits the text with
		Return, by leaving the box, or by picking an option; a commit is reported through
		`on_commit' only when it changed the text from the last commit or `set_program_text'.
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
			create committed_text.make_empty
			set_on_activate (agent commit)
			on_focus_change.extend (agent (a_focused: BOOLEAN)
				do
					if not a_focused then
						commit
					end
				end)
		ensure
			nothing_committed: committed_text.is_empty
		end

feature -- Access

	on_commit: detachable PROCEDURE
			-- Run when the user commits a changed text.

	committed_text: STRING_32
			-- The text as last committed, or as the program set it.

feature -- Element change

	set_on_commit (a_action: PROCEDURE)
		do
			on_commit := a_action
		ensure
			set: on_commit = a_action
		end

	set_program_text (a_text: READABLE_STRING_GENERAL)
			-- Show `a_text', taken as committed: no report.
		do
			set_text (a_text)
			committed_text := text.twin
		ensure
			shown: text.same_string_general (a_text)
			committed: committed_text.same_string (text)
		end

	choose_option (a_i: INTEGER)
			-- Take option `a_i', as the user picking it: a commit.
		do
			Precursor (a_i)
			commit
		end

	commit
			-- The user committed the text: report it if it changed.
		do
			if not text.same_string (committed_text) then
				committed_text := text.twin
				if attached on_commit as al_action then
					al_action.call
				end
			end
		ensure
			committed: committed_text.same_string (text)
		end

invariant
	committed_exists: committed_text /= Void

end
