# simple_gui row cache

A session row cache for simple_gui's lazy tables (1f). Every row the table brings into view is
kept, so the program's own function makes each row once, however often the user scrolls back
or the table forgets it. It is a library of its own, so simple_gui gains no dependency from it.

```eiffel
create l_cache.make (3, agent make_row)        -- kept by row number, in a scratch file
l_cache.attach (l_table, 100_000)              -- l_table.set_row_source (100_000, agent l_cache.cells)
l_cache.set_volatile (3, agent clock_cell)     -- column 3 is made every time, never kept
...
l_cache.refresh_rows                           -- the data changed: forget, and refresh the table
l_cache.close                                  -- the scratch file is deleted
```

**Rows that survive sorting.** Keep rows by the program's own key for a row with `make_keyed`.
After a sort, `refresh_order` asks the table again, and every row comes back from the cache.

**Encryption, when the table shows sensitive data.** It is off by default. `make_encrypted`
(or `set_encrypted (True)` on a store before its first row) seals every row under a key held
only in memory, through simple_encryption's session seal, so a scratch file left behind by a
crash cannot be read. A row altered on disk is made again rather than shown wrong.

**Two stores, one choice.**
- **`GUI_ROW_FILE_STORE`** is the default: an append-only scratch file plus an in-memory index.
- **`GUI_ROW_SQL_STORE`** (`sql/simple_gui_row_cache_sql.ecf`, over simple_sql) is for a cache
  that must persist, be queried or be shared.

The reasons, with measurements, are in [docs/choosing-a-row-store.md](docs/choosing-a-row-store.md)
and in `GUI_ROW_STORE`'s note.

**ECFs:**
- `simple_gui_row_cache.ecf`, needing simple_gui, simple_file and simple_encryption (2.2.0, for
  the session seal). Its tests are
  `simple_gui_row_cache_tests`.
- `sql/simple_gui_row_cache_sql.ecf`, which adds simple_sql. Its tests are
  `simple_gui_row_cache_sql_tests`, the same shared tests run over the SQL store.

The design record is port-coordination's `docs/SIMPLE_GUI_SPEC.md`, the 1f addendum (#35).
