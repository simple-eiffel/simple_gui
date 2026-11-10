# List

`GUI_LIST` is a single column of text rows, from which the user selects one. Use it when the choices are many, or change while the program runs, and the user benefits from seeing several at once. For a few fixed choices in little room, use a [dropdown](dropdown.md) or a [radio group](radio-group.md); for rows with several columns, use a [table](table.md); for a hierarchy, use a [tree](tree.md).

## Example

```eiffel
class BOOKS create make
feature
	app: GUI_APPLICATION
	books: GUI_LIST
	shown: GUI_LABEL

	make
		local
			l_window: GUI_WINDOW
			l_stack: GUI_STACK
		do
			create app.make ("Books", "org.example.books")
			create l_window.make ("Books", 320, 260)
			create l_stack.make_vertical
			create books.make
			books.set_accessible_label ("Books")
			books.extend ("Genesis")
			books.extend ("Exodus")
			books.extend ("Leviticus")
			create shown.make ("Pick a book.")
			books.selection_actions.extend (agent on_book)
			l_stack.extend_stretching (books)
			l_stack.extend (shown)
			l_window.set_content (l_stack)
			l_window.show
			app.run
		end

	on_book (a_row: INTEGER)
		do
			if a_row > 0 then
				shown.set_text ({STRING_32} "You picked " + books.i_th (a_row))
			end
		end
end
```

## Try it

A window opens with a list of three books, none selected, and the line "Pick a book." under it. Click **Exodus**: `selection_actions` fires with 2, and the line says "You picked Exodus".

## API

| Feature | What it does |
|---|---|
| `make` | An empty list. Ensures `count = 0`. |
| `extend (a_text)` | Adds a row at the end. Ensures `count = old count + 1` and `i_th (count)` is `a_text`. |
| `wipe_out` | Removes every row. Ensures `count = 0` and `selected_index = 0`. |
| `count` | How many rows there are. |
| `i_th (i)` | The text of row `i`. Requires 1 <= `i` <= `count`. |
| `selected_index` | The selected row, or 0 when none is. |
| `scroll_to_row (i)` | Scrolls so row `i` is in view, with no event; the selection does not change. Requires 1 <= `i` <= `count`. |
| `select_row (i)` | Selects row `i`, with no event. Requires 1 <= `i` <= `count`. Ensures `selected_index = i`. |
| `clear_selection` | Selects nothing. Ensures `selected_index = 0`. |
| `selection_actions` | `GUI_ACTIONS [TUPLE [row: INTEGER]]`: run when the user selects a row. |
| `set_multiple_selection (a_on)` | Lets the user select several rows at once (Command or Control, and Shift, with a click), or goes back to one. Requires `is_gui_thread`. Ensures `is_multiple_selection = a_on`. |
| `is_multiple_selection` | May the user select several rows? |
| `selected_rows` | Every selected row, in order, as an `ARRAYED_LIST [INTEGER]`. Ensures every number is in 1 to `count`. |
| `set_reorderable (a_on)`, `is_reorderable`, `reorder_actions`, `move_row (a_from, a_to)` | Let the user move rows by dragging. See [Reordering](reordering.md). |
| `set_row_pebble_function (a_function)` | Lets each row carry a pebble for [pick and drop](pick-and-drop.md). A drop on the list sets `last_drop_row`. |

Inherited: `set_accessible_label`, `set_context_menu`, `set_tooltip` and the rest of the [common features](widget.md).

**Events:** `selection_actions` fires with the row number when the user selects a row. Rows are 1-based; check for 0, which is sent when the user clears the selection (Linux and macOS; on Windows a click always selects a row). A list reports a selection only when it changes: choosing the row that is already selected sends nothing. `select_row` and `scroll_to_row` never fire it: its postcondition is `selection_actions.fire_count = old selection_actions.fire_count`.

**Several rows.** After `set_multiple_selection (True)` the user can select more than one row, with Command or Control and Shift. Read all of them with `selected_rows`, for example when the user presses a button such as **Delete**. `selection_actions` still run with one number: the first selected row, or 0 when none is. They run when the selection changes, so use them to learn that the selection changed and read `selected_rows` for what it is. `selected_index` is the single-selection feature; in this mode use `selected_rows`. On Linux, turning the mode on clears the selection.

**Moving rows, and pick and drop.** A list can let the user reorder its rows by dragging: see [Reordering](reordering.md). Its rows can also be sources and targets for [pick and drop](pick-and-drop.md), and a list can take files and text from other programs: see [Drag and drop between programs](drag-and-drop-between-programs.md).

**Accessibility:** the role is `list`, and each row is a `list-item` read by its text. The list has no visible text of its own, so give it `set_accessible_label` with what the rows are ("Books", "Recent files").

## On each platform

| | Linux (GTK 4) | macOS (AppKit) | Windows (simple_widgets) |
|---|---|---|---|
| Native control | `GtkListBox` (single selection, `boxed-list` style) in a `GtkScrolledWindow` | `NSTableView` with one column and no header, inset style, in a bordered `NSScrollView` | `SW_TEXT_LIST`: a drawn list that names its rows for screen readers |
| Looks or behaves differently | At least 80 pixels tall. A cleared selection sends row 0. | A cleared selection sends row 0. | Starts 120 pixels tall. A click always selects a row, so the user has no way to clear the selection and row 0 does not arrive. |

## Design guidance

- A list scrolls on its own. Give it room with `extend_stretching`, and never put it in a [scroll area](scroll-area.md).
- Give it an accessible label, and a visible caption above it when the window has more than one list.
- To change the rows, call `wipe_out` and `extend` again; then `select_row` to restore a selection, without an event.
- After `select_row`, call `scroll_to_row` with the same row when a long list may have it out of view. It leaves the selection alone.
- Read `selected_index` when the user presses a button such as **Open**, rather than acting on every selection change.
- Add a [context menu](widget.md) for actions on a row (rename, delete) with `set_context_menu`.
- Turn on `set_multiple_selection` only when an action works on several rows (delete, move, export). Show the count of selected rows near the button that acts on them.
- Turn on `set_reorderable` only when the order is the user's to decide, and keep **Move up** and **Move down** buttons beside it (see [Reordering](reordering.md)).

## Gallery

| Linux | macOS | Windows |
|---|---|---|
| ![list on Linux](images/linux/list.png) | ![list on macOS](images/macos/list.png) | ![list on Windows](images/windows/list.png) |
