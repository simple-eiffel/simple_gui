# simple_gui Control Guide

simple_gui gives an Eiffel program native controls on each platform: GTK 4 on Linux, AppKit on macOS, and simple_widgets on Windows. You write the program once. Each page below shows one control: what it is, a short program that uses it, its features and events, how it looks and behaves on each platform, and how to use it well.

Start with **[Getting started](getting-started.md)**: the application, a window, the event loop, and how worker processors talk to the GUI.

## Basics
- [Getting started](getting-started.md): application, window, loop, mailbox
- [Window](window.md): title, content, toolbar, status bar, closing
- [Common features](widget.md): enabling, showing, size, accessibility, tooltips, context menus, direction
- [Label](label.md): text the user reads
- [Button](button.md): an action
- [Check box](check-box.md): an option, on or off
- [Separator](separator.md): a line between groups
- [Image](image.md): a picture from a file or PNG bytes

## Input
- [Text field](text-field.md): one line of text
- [Text area](text-area.md): several lines of text
- [Search field](search-field.md): text to search for
- [Combo box](combo-box.md): text typed or picked from options
- [Spin box](spin-box.md): an exact whole number
- [Slider](slider.md): a number chosen by dragging
- [Color chooser](color-chooser.md): a color

## Choice
- [Dropdown](dropdown.md): one of many, in little room
- [Radio group](radio-group.md): one of a few, all in view
- [Segmented control](segmented.md): one of a few short choices, joined
- [Switch](switch.md): a setting that takes effect at once
- [List](list.md): one of a list of texts

## Date and time
- [Date picker](date-picker.md): a date, typed or stepped
- [Time picker](time-picker.md): a time of day
- [Calendar](calendar.md): a date from a month grid

## Containers
- [Stack](stack.md): widgets in a row or a column
- [Grid](grid.md): widgets in rows and columns
- [Splitter](splitter.md): two panes the user resizes
- [Tabs](tabs.md): pages, one at a time
- [Scroll area](scroll-area.md): a part of something larger
- [Group box](group-box.md): a titled frame
- [Expander](expander.md): content the user shows or hides

## Tables and trees
- [Table](table.md): rows and columns, filled or lazy (100,000 rows and more)
- [Tree](tree.md): a hierarchy
- [Tree table](tree-table.md): a hierarchy with columns

## Feedback
- [Progress bar](progress-bar.md): how far along a task is
- [Level bar](level-bar.md): how full something is
- [Status bar](status-bar.md): one line at the window's bottom

## Menus and toolbars
- [Menus](menus.md): the menu bar, standard items, shortcuts, context menus
- [Toolbar](toolbar.md): buttons at the window's top
- [Menu button](menu-button.md): a button that opens a menu

## Dialogs
- [Dialogs](dialogs.md): files, folders, messages, questions, text, fonts, About

## Drawing
- [Canvas](canvas.md): your own drawing with Cairo, at the screen's scale

## Advanced
- [Popover](popover.md): a transient panel pointing at a control
- [Token field](token-field.md): items typed as chips
- [Path control](path-control.md): a path as clickable parts
- [Rating](rating.md): stars
- [Rich text area](rich-text-area.md): styled text

## Rules every control keeps
- **Native:** each control is the platform's own. Nothing is drawn to imitate a platform.
- **Code is silent:** setting a value from the program (`set_text`, `select_row`, `set_value`) never fires an event. Only the user's actions do.
- **Accessible by default:** every control has a label for screen readers (its visible text unless you set one). A placeholder is never the label. Each page names the control's accessibility role.
- **Layout by containers:** stacks and grids place widgets, with leading and trailing margins, so a right-to-left window mirrors correctly.
- **Testable:** `GUI_TEST_DRIVER` acts as a user would, takes snapshots, and reads the accessibility tree. Every control in this guide has shared tests that pass on all three platforms.
