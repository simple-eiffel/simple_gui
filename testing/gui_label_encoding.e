note
	description: "[
		Labels written in a source file saved WITHOUT a UTF-8 byte-order mark (2026-11-11, from the
		printing guide's example): the compiler reads such a file one character per byte, so a raw
		ellipsis becomes three characters even in a STRING_32 manifest; the code-point escape
		%/8230/ is the same character in any file.
	]"

class
	GUI_LABEL_ENCODING

feature -- Labels

	raw_ellipsis_label: STRING_32
			-- "Save" and an ellipsis typed straight into this BOM-less file.
		do
			Result := {STRING_32} "Save…"
		end

	escaped_ellipsis_label: STRING_32
			-- "Print" and the ellipsis by its code point.
		do
			Result := {STRING_32} "Print%/8230/"
		end

end
