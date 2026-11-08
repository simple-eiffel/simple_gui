# Changelog

## 0.1.0 (2026-11-08)

- First API (spec: simple-eiffel/port-coordination docs/SIMPLE_GUI_SPEC.md): GUI_APPLICATION, GUI_WINDOW, GUI_STACK, GUI_GRID, GUI_LABEL, GUI_BUTTON, GUI_TEXT_FIELD, GUI_LIST, GUI_CANVAS, GUI_MENU_MODEL, GUI_MENU, GUI_DIALOGS, GUI_MAILBOX, GUI_WAKE, GUI_TEST_DRIVER.
- The contract between backends is the deferred class GUI_BACKEND_API.
- GTK 4 backend (Linux): 16 of 16 tests pass under WSLg (Ubuntu 24.04, GTK 4.14).
- AppKit backend (macOS): in progress (MACMINI).
