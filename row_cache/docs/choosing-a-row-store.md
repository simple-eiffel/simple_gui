# Choosing a row store

A `GUI_ROW_CACHE` keeps the rows a lazy table (simple_gui 1f) has shown, so the program makes
each row once. Where it keeps them is a `GUI_ROW_STORE`, and there are two. This note is for
whoever picks one later, human or AI: it gives the reasons, so the choice comes from the need
rather than from habit.

> "The right tool for the right job." (Larry, 2026-11-08, quoting Peter Kiewit)

## The short answer

- **Session only, rows read back by their key:** `GUI_ROW_FILE_STORE`. It is the default
  (`GUI_ROW_CACHE.make`, `make_keyed`).
- **The cache must outlive the session, be queried by more than its key, or take more than
  one writer:** `GUI_ROW_SQL_STORE` (`make_with_store`, with `simple_gui_row_cache_sql.ecf`).
- **No need decides:** the file store.

## What each store is

**`GUI_ROW_FILE_STORE`:**
- **Storage:** an append-only scratch file plus an in-memory index from key to (offset, length).
- **Writing:** a `put` copies the row's UTF-8 into a 64 KB buffer, which goes to the end of the
  file in one write when full.
- **Reading:** an `item` is one indexed read through a handle kept open, or a copy from the
  buffer for rows not yet written.
- **Forgetting:** `forget` drops keys from the index; `forget_all` also empties the file.
- **Closing:** `close` deletes the file.
- **Needs:** simple_file.

**`GUI_ROW_SQL_STORE`:**
- **Storage:** one SQLite table, `rows (k TEXT PRIMARY KEY, cells TEXT) WITHOUT ROWID`, over
  simple_sql.
- **Writing:** writes are batched in transactions of 500.
- **The scratch form:** `make` turns journaling and syncing off and deletes the database on
  `close`.
- **The persistent form:** `make_persistent (path)` keeps SQLite's defaults and the file.
- **Needs:** simple_sql, eiffel_sqlite_2025 and SQLite. It has its own ECF so that only programs
  that choose it pull them in.

## Strengths and weaknesses

| | File store | SQL store |
|---|---|---|
| Writes, per row | a memory copy; one file write per 64 KB | an SQL statement per row (simple_sql compiles each one, see below), committed every 500 |
| Random reads, per row | an index lookup and one read through an open handle | an SQL query through SQLite's B-tree and page cache |
| Lifetime | the session: the index lives in memory | the session, or beyond (`make_persistent`) |
| Querying | by key only | anything SQL can ask |
| Writers | one: the GUI processor that owns the store | several (SQLite's locking) |
| Memory | about 40 bytes of index per row (100,000 rows: about 4 MB) | SQLite's page cache, capped at 2 MB here |
| Disk | the rows' UTF-8, plus space from replaced rows until `forget_all` | the rows plus B-tree overhead |
| Dependency | simple_file | simple_sql, SQLite |
| Failure | a failed write stops the store keeping rows (`has_failed`); the cache makes rows again | the same |

**Two things worth knowing:**
- **Keep files open for reads.** The first file store reopened the file for every read (as
  simple_file's `read_block` does), and SQLite read faster. Keeping one handle open made the
  file store's reads about five times faster.
- **simple_sql doesn't prepare statements in SQLite's sense.** `compile_sql` keeps the SQL text,
  and `execute` substitutes the bound values into it as literals and compiles it again each
  time. That is most of the SQL store's write cost. A store over SQLite's own prepared
  statements (eiffel_sqlite_2025) would write faster. Weigh that against simple_sql's other
  services before writing one.

## Measurements

These are for 100,000 rows of five cells (about 45 characters a row) and 1,000 reads at
random keys. Each figure is the middle of three runs, on macOS (Apple M4 Mac mini, native arm64,
EiffelStudio 25.02).
Making the rows' texts alone, without storing them, takes the "making" time; subtract it to
get the store's own cost.

**macOS, contracts off (the shipped build: `ec.sh release`):**

| | File store | SQL store |
|---|---|---|
| Put 100,000 rows (with ~200 ms of making them) | ~405 ms | ~930 ms |
| The store's own cost per put | **~2 µs** | **~7 µs** |
| Read 1,000 random keys | **2 to 5 ms** (2 to 5 µs a row) | **~8.6 ms** (~8.6 µs a row) |
| Size on disk | 4.4 MB | 6.0 MB |

**macOS, contracts on (`ec.sh test`):**

| | File store | SQL store |
|---|---|---|
| Put 100,000 rows (with ~450 ms of making them) | ~940 ms | ~4,580 ms |
| Read 1,000 random keys | 5 to 8 ms | ~26 ms |

**What the numbers mean:**
- **Both are fast enough for a table.** A viewful plus its margins is a few hundred rows, which
  either store reads in well under a 16 ms frame. Neither store will make the table feel slow;
  the program's own row function decides that.
- **The file store is the better fit for a session cache.** It writes about 3.5 times as fast
  and reads about twice as fast, with a quarter less disk and nothing to link but simple_file.
- **The SQL store's costs buy its reasons.** It costs more because of what it gives: a file
  that survives the session, SQL queries, and safe sharing. Choose it for those, not for speed.
- **The file store's reads vary more** (2 to 5 ms between runs, against SQLite's steady 8.6 ms).
  It relies on the system's file cache, where SQLite keeps its own page cache.

Windows and Linux numbers follow from PROD.

## Encryption

Encryption is optional and off by default, for both stores (Larry, 2026-11-08). When it is on,
each record is sealed under a key made for the session and held only in memory, so a file left
behind by a crash cannot be read. It comes through simple_encryption's `session_seal` and
`session_open` (see port-coordination's SIMPLE_GUI_SPEC.md, 1f addendum). With it on, a
persistent SQL store can only be read in the session that wrote it.

## Scratch files

- **Location:** the user's temporary folder, named `simple_gui_rows_<process>_<n>.dat` or
  `.sqlite`. That is `$TMPDIR` on macOS, `$XDG_RUNTIME_DIR` (else `/tmp`) on Linux, and `%TEMP%`
  on Windows.
- **Owner-only:** on macOS and Linux the file is created with mode 0600 (`O_EXCL`, which also
  refuses a planted link). On Windows it relies on `%TEMP%` being private to the user.
- **Lifetime:** `close` deletes the file.
- **Leftovers:** a program that ends without `close`, or crashes, leaves its file behind. The
  next store made in any program sweeps up the files whose process has ended.
