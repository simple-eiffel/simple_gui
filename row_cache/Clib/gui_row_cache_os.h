/* simple_gui row_cache: the few system calls its scratch files need.
   The process id, whether a process still runs (to sweep files left by ended processes),
   and creating a file readable and writable by its owner only. */
#ifndef GUI_ROW_CACHE_OS_H
#define GUI_ROW_CACHE_OS_H

#ifdef _WIN32
#include <windows.h>

static int grc_process_id(void) { return (int) GetCurrentProcessId(); }

static int grc_process_running(int a_pid)
{
	HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD) a_pid);
	DWORD l_code = 0;
	int l_running;
	if (!h) return GetLastError() == ERROR_ACCESS_DENIED;
	l_running = GetExitCodeProcess(h, &l_code) && l_code == STILL_ACTIVE;
	CloseHandle(h);
	return l_running;
}

/* The user's %TEMP% is already private to the user; the file is made by the first write. */
static int grc_create_owner_only(const void *a_path) { (void) a_path; return 1; }

/* Milliseconds from an arbitrary start (for the measurements). */
static double grc_now_ms(void)
{
	LARGE_INTEGER l_freq, l_now;
	QueryPerformanceFrequency(&l_freq);
	QueryPerformanceCounter(&l_now);
	return (double) l_now.QuadPart * 1000.0 / (double) l_freq.QuadPart;
}

#else
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>

static int grc_process_id(void) { return (int) getpid(); }

static int grc_process_running(int a_pid) { return kill((pid_t) a_pid, 0) == 0 || errno == EPERM; }

/* A new file, mode 0600; 0 when it already exists (O_EXCL also refuses a planted link). */
static int grc_create_owner_only(const void *a_path)
{
	int fd = open((const char *) a_path, O_CREAT | O_EXCL | O_WRONLY, 0600);
	if (fd < 0) return 0;
	close(fd);
	return 1;
}

#include <time.h>
/* Milliseconds from an arbitrary start (for the measurements). */
static double grc_now_ms(void)
{
	struct timespec l_now;
	clock_gettime(CLOCK_MONOTONIC, &l_now);
	return (double) l_now.tv_sec * 1000.0 + (double) l_now.tv_nsec / 1.0e6;
}
#endif


/* A file kept open for reads at 64-bit offsets (a store reads many small rows: reopening the
   file for each costs more than the read). NULL when it will not open. */
#include <stdio.h>
#ifdef _WIN32
#include <wchar.h>
static void *grc_open_read(const void *a_path) { return (void *) _wfopen((const wchar_t *) a_path, L"rb"); }
static int grc_seek(void *a_file, long long a_offset) { return _fseeki64((FILE *) a_file, (__int64) a_offset, SEEK_SET); }
#else
#include <sys/types.h>
static void *grc_open_read(const void *a_path) { return (void *) fopen((const char *) a_path, "rb"); }
static int grc_seek(void *a_file, long long a_offset) { return fseeko((FILE *) a_file, (off_t) a_offset, SEEK_SET); }
#endif

/* Bytes read into `a_dest' from `a_offset' (-2 when the seek fails). A seek drops stdio's
   buffer, so bytes appended through another handle since the last read are seen. */
static int grc_read_at(void *a_file, void *a_dest, long long a_offset, int a_count)
{
	if (grc_seek(a_file, a_offset) != 0) return -2;
	return (int) fread(a_dest, 1, (size_t) a_count, (FILE *) a_file);
}

static void grc_close_file(void *a_file) { if (a_file) fclose((FILE *) a_file); }

#endif
