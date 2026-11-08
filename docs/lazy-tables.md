# Lazy tables: how they work, and why this way

`GUI_TABLE.set_row_source (count, cells)` gives a table a row count and a function from a row
number to its texts. The table asks for rows only as they come into view. This page records
**why** it is built the way it is, so a later engineer (human or AI) can change it from reasons
rather than habit. Design record: SIMPLE_GUI_SPEC.md, section 1f (port-coordination #34).

## When to use it

| Your rows | Use | Why |
|---|---|---|
| Up to a few thousand, all at hand | `extend_row` | Simplest; the table holds them, sorting by refilling is cheap. |
| Many (10,000 and up), or costly to make (a query, a file, a computation) | `set_row_source` | Only the rows in sight (plus a margin) are ever made; memory stays flat however many rows there are. |
| Many, costly, and the user scrolls back and forth | `set_row_source` over a row cache (see the row cache's own notes) | Rows seen this session come back from a session file instead of the source. |

Rules that follow from the design: the source must answer the same for a row until
`set_row_count` or a `refresh_` call, and may be asked any number of times in any order; the
program sorts (a header click is reported) and then calls `refresh_rows`.

## Why the table asks instead of the toolkit calling the program

EV_GRID, GTK's `GListModel` and AppKit's `NSTableViewDataSource` all call the program
**while drawing**. simple_gui's rule is that C never calls into Eiffel: the event queue is the
only way across, which keeps SCOOP safe (a GUI processor never blocks on a call it did not
start). So the backend draws an unanswered row empty and pushes **rows wanted** (event 16,
first and last row); `GUI_TABLE.dispatch` calls the program's function and hands each row down
(`table_set_row`). A row shows one loop turn after it is first wanted, the next frame at 60 Hz.

**Windows takes the same path** although its backend is Eiffel and could call the function
directly: one behavior on every platform means the shared tests test the same thing everywhere.

## Why the cache is bounded

EV_GRID (25.02, partial dynamic content) keeps every item it has ever drawn, so memory grows
with what has been scrolled past. Here each backend keeps at most **2,000 answered rows**; past
that the oldest go back to "unanswered" and are asked for again if they come back into sight.
2,000 is about forty screenfuls: far more than is ever in sight, small enough not to matter.
Rows still in sight are never the ones given back.

## Why each backend is built as it is

| Backend | Choice | Why this and not the obvious alternative |
|---|---|---|
| GTK | The table's existing `GtkStringList` holds a one-character placeholder per unanswered row; the cell's bind asks for its row. | A custom `GObject` implementing `GListModel` is the textbook way, but it is a new type with its own reference counting for no gain: a placeholder string per row is a few bytes, GTK still binds only the rows in sight, and answering is one `splice` that makes GTK rebind that row. |
| GTK | Asks are collected and sent as **one** event per idle. | A bind happens per cell per row; one event per bind would flood the queue during a scroll. |
| GTK | The selection is saved and restored around each splice. | A splice is a remove-and-insert to GTK's selection models, which would otherwise drop a selected row's selection when its text arrives. |
| Windows | Every unanswered row is **one shared** empty row object. | 100,000 rows cost one object and a list of references, not 100,000 objects. |
| Windows | After each pump and layout, the rows in sight **plus one viewful either side** are checked. | SW_DATA_GRID draws without calling out, so the backend looks after drawing; the margin makes a short scroll find its rows already there. |
| Windows | `SW_DATA_GRID.put_row` puts an answer in place. | `set_rows` copies every row; a lazy table answers rows one at a time. |
| All | A row asked for is **not asked for again** until answered or forgotten. | Without it a scroll asks for the same rows on every frame. |

## Measured

All three platforms pass the shared tests `a_row_source_asks_only_for_rows_in_view` (a 100,000-row
source asked for at most three viewfuls when shown, far fewer than 100,000 after scrolling to row
50,000), `refresh_rows_asks_again`, `a_row_source_selects_by_number` and `set_row_count_resizes`.
