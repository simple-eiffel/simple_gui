note
	description: "[
		A copy of a text that lives on another processor. No reference may cross from one
		processor's region into another's, so a class that keeps a text handed to it through
		a separate call copies it first. This is that copy, stated once.

		Inherit it beside the class's other parents; the feature is secret.

		STRING_32's `make_from_separate' does the same for a text known to be a
		READABLE_STRING_32; this one takes any string, as the mailbox promises.
	]"
	author: "Larry Rix"

deferred class
	GUI_SEPARATE_TEXT

feature {NONE} -- Conversion

	copied_text (a_text: separate READABLE_STRING_GENERAL): STRING_32
			-- A new string on this processor holding `a_text''s characters.
		local
			i, n: INTEGER
		do
			n := a_text.count
			create Result.make (n)
			from i := 1 until i > n loop
				Result.extend (a_text.code (i).to_character_32)
				i := i + 1
			end
		ensure
			same_count: Result.count = a_text.count
		end

end
