/* simple_gui_win_dialog_cancel.h - tests only (GUI_TEST_DRIVER.cancel_dialogs_after): cancel
   the system file dialog this process is about to show, as GTK's timer does for its own
   (2026-11-11, when Windows moved from drawn sheets to the system's dialogs).

   A thread waits for this process's next visible dialog window (class #32770, the Open,
   Save and folder dialogs' frame), lets it stand `ms' milliseconds, then presses Cancel.
   No state outside the thread's own job. */

#ifndef SIMPLE_GUI_WIN_DIALOG_CANCEL_H
#define SIMPLE_GUI_WIN_DIALOG_CANCEL_H

#ifdef _WIN32
#include <windows.h>
#include <stdlib.h>
#include <wchar.h>

typedef struct { int ms; DWORD pid; HWND found; } SGW_CANCEL;

static BOOL CALLBACK sgw_cancel_each(HWND h, LPARAM l)
{
    SGW_CANCEL* j = (SGW_CANCEL*) l;
    DWORD pid = 0;
    wchar_t cls[16];
    GetWindowThreadProcessId(h, &pid);
    if (pid == j->pid && IsWindowVisible(h) && GetClassNameW(h, cls, 16) && wcscmp(cls, L"#32770") == 0) {
        j->found = h;
        return FALSE;
    }
    return TRUE;
}

static DWORD WINAPI sgw_cancel_thread(LPVOID p)
{
    SGW_CANCEL* j = (SGW_CANCEL*) p;
    int i;
    for (i = 0; i < 300 && !j->found; i++) {
        Sleep(50);
        EnumWindows(sgw_cancel_each, (LPARAM) j);
    }
    if (j->found) {
        Sleep((DWORD) j->ms);
        PostMessageW(j->found, WM_COMMAND, IDCANCEL, 0);
    }
    free(j);
    return 0;
}

static void sgw_cancel_dialog_after(int a_ms)
{
    SGW_CANCEL* j = (SGW_CANCEL*) calloc(1, sizeof(SGW_CANCEL));
    HANDLE t;
    if (!j) return;
    j->ms = a_ms;
    j->pid = GetCurrentProcessId();
    t = CreateThread(NULL, 0, sgw_cancel_thread, j, 0, NULL);
    if (t) CloseHandle(t); else free(j);
}
#endif

#endif /* SIMPLE_GUI_WIN_DIALOG_CANCEL_H */
