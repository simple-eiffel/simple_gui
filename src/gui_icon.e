note
	description: "[
		The icon vocabulary (1n): neutral names every platform draws in its own way - GTK's
		Adwaita symbolic icons, SF Symbols on macOS, simple_widgets' drawn glyphs on Windows.
		A program names an icon ("delete", "settings") and gets the platform's own picture of it.
	]"

class
	GUI_ICON

feature -- Access

	names: ARRAY [STRING_32]
			-- Every icon name, in the order the guide lists them.
		once
			Result := <<
				{STRING_32} "add", {STRING_32} "remove", {STRING_32} "close", {STRING_32} "check",
				{STRING_32} "chevron-right", {STRING_32} "chevron-left", {STRING_32} "chevron-up", {STRING_32} "chevron-down",
				{STRING_32} "back", {STRING_32} "forward",
				{STRING_32} "search", {STRING_32} "settings", {STRING_32} "delete", {STRING_32} "edit",
				{STRING_32} "folder", {STRING_32} "document", {STRING_32} "open", {STRING_32} "save",
				{STRING_32} "copy", {STRING_32} "cut", {STRING_32} "paste", {STRING_32} "undo", {STRING_32} "redo",
				{STRING_32} "refresh",
				{STRING_32} "play", {STRING_32} "pause", {STRING_32} "stop", {STRING_32} "more", {STRING_32} "menu",
				{STRING_32} "info", {STRING_32} "warning", {STRING_32} "error", {STRING_32} "help",
				{STRING_32} "star", {STRING_32} "picture", {STRING_32} "home", {STRING_32} "user", {STRING_32} "mail",
				{STRING_32} "calendar", {STRING_32} "clock", {STRING_32} "lock", {STRING_32} "bell",
				{STRING_32} "download", {STRING_32} "upload", {STRING_32} "print", {STRING_32} "filter", {STRING_32} "sort"
			>>
		ensure
			forty_seven: Result.count = 47
		end

	is_known (a_name: READABLE_STRING_GENERAL): BOOLEAN
			-- Is `a_name' in the vocabulary?
		do
			Result := across names as ic some ic.same_string_general (a_name) end
		end

end
