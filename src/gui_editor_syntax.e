note
	description: "[
		What knows the syntax of a code editor's text (1v-e-1): a parser, most likely on a
		worker, that GUI_CODE_EDITOR.set_syntax puts in the place of the rules and the
		highlighter agent. simple_gui names no parser; a library that has one (the one over
		simple_tree_sitter) inherits this class.

		The editor calls these features on the GUI processor, and none of them may wait:
		an implementer hands the work to its worker and returns. It answers later, again
		on the GUI processor, by calling the editor: `apply_spans', `set_folds'.

		Versions are the implementer's business. The editor counts none and its calls carry
		none: the implementer raises its own counter in `text_replaced' and `text_edited',
		and drops a result whose version is not the newest before it calls the editor.

		The edits reported are true ones: each, applied to the text as last reported, gives
		the text now. They need not be the edits the user made ("aa" from "a" does not say
		which "a" is new), and several changes that reach the editor as one event are
		reported as one edit that covers them all.
	]"
	author: "Larry Rix"

deferred class
	GUI_EDITOR_SYNTAX

feature -- Access

	editor: detachable GUI_CODE_EDITOR
			-- The editor this works for, if any. One object works for one editor at a time.
		deferred
		end

feature -- Attachment (called by the editor)

	attach (an_editor: GUI_CODE_EDITOR)
			-- Start working for `an_editor', whose text is the whole text now.
		require
			free: editor = Void
			chosen_by_the_editor: an_editor.syntax = Current
		deferred
		ensure
			working_for_it: editor = an_editor
		end

	detach
			-- Stop, and make no further calls to the editor.
		require
			working: editor /= Void
		deferred
		ensure
			free: editor = Void
		end

feature -- Changes (called by the editor)

	text_replaced (a_text: READABLE_STRING_32)
			-- The whole text is `a_text' now (`set_text', or every line is to be colored
			-- again: the theme changed).
		require
			working: editor /= Void
		deferred
		end

	text_edited (a_start, a_removed: INTEGER; an_inserted: READABLE_STRING_32)
			-- The `a_removed' characters from position `a_start' gave way to `an_inserted'.
			-- `a_start' is from 1 to the old count plus 1 and the removed characters lie in
			-- the old text (the preconditions of TS_DOCUMENT.edit; the old count is the
			-- implementer's to know).
		require
			working: editor /= Void
			start_positive: a_start >= 1
			removed_not_negative: a_removed >= 0
			a_true_edit: a_removed > 0 or not an_inserted.is_empty
		deferred
		end

feature -- Coloring by the view (called by the editor, from 1v-e-6 on)

	spans_wanted (a_first_line, a_last_line: INTEGER)
			-- The editor wants lines `a_first_line' to `a_last_line' colored: answer, now or
			-- later, with the editor's `apply_spans' for a range that covers them. The editor
			-- asks for the lines in view first and the rest a slice at a time, and asks again
			-- for nothing it has not had an answer to.
		require
			working: editor /= Void
			lines_ordered: 1 <= a_first_line and a_first_line <= a_last_line
		deferred
		end

feature -- Brackets (called by the editor, from 1v-e-2 on)

	bracket_wanted (a_position: INTEGER)
			-- The bracket at `a_position' wants its partner; answer, now or later, with the
			-- editor's `show_bracket_pair' or `hide_bracket_pair'.
		require
			working: editor /= Void
			position_positive: a_position >= 1
		deferred
		end

end
