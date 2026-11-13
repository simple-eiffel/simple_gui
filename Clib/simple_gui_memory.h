/* simple_gui_memory.h - how much memory this process holds, for the tests that keep it flat
   (2026-11-13). Windows: the commit charge (private bytes); Linux: the resident set;
   macOS: the resident size. -1 when the system will not say. */
#ifndef SIMPLE_GUI_MEMORY_H
#define SIMPLE_GUI_MEMORY_H

#if defined(_WIN32)
#include <windows.h>
#include <psapi.h>
static long long sg_process_bytes(void) {
    /* Found at run time: ISE compiles for Windows 2000, where psapi.h binds the call to psapi.dll. */
    typedef BOOL (WINAPI *sg_memory_info_fn)(HANDLE, PPROCESS_MEMORY_COUNTERS, DWORD);
    static sg_memory_info_fn l_info = 0;
    PROCESS_MEMORY_COUNTERS l_c;
    if (!l_info)
        l_info = (sg_memory_info_fn) GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "K32GetProcessMemoryInfo");
    if (!l_info) return -1;
    ZeroMemory(&l_c, sizeof(l_c));
    l_c.cb = sizeof(l_c);
    return l_info(GetCurrentProcess(), &l_c, sizeof(l_c)) ? (long long) l_c.PagefileUsage : -1;
}
#elif defined(__APPLE__)
#include <mach/mach.h>
static long long sg_process_bytes(void) {
    struct mach_task_basic_info l_i;
    mach_msg_type_number_t l_n = MACH_TASK_BASIC_INFO_COUNT;
    return task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t) &l_i, &l_n) == KERN_SUCCESS
        ? (long long) l_i.resident_size : -1;
}
#else
#include <stdio.h>
#include <unistd.h>
static long long sg_process_bytes(void) {
    long long l_size = 0, l_resident = -1;
    FILE *l_f = fopen("/proc/self/statm", "r");
    if (!l_f) return -1;
    if (fscanf(l_f, "%lld %lld", &l_size, &l_resident) != 2) l_resident = -1;
    fclose(l_f);
    return l_resident < 0 ? -1 : l_resident * (long long) sysconf(_SC_PAGESIZE);
}
#endif

#endif
