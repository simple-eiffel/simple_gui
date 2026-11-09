/* simple_gui, Windows backend: the little it asks of Win32 directly (the rest is drawn by
   simple_widgets). Inline-C header; nothing to build. */
#ifndef SIMPLE_GUI_WIN_H
#define SIMPLE_GUI_WIN_H

#include <windows.h>
#include <wchar.h>
#include <string.h>

/* Installed font families for the drawn font chooser: GDI's EnumFontFamiliesExW over every
   character set, each family once, vertical ("@") faces left out. Written into the caller's
   buffer as UTF-16 names each followed by U+001F (the first character is a U+001F too, so a
   name can be found as U+001F name U+001F), NUL-ended. Answers the length in WCHARs, or -1
   when the buffer was too small. */
typedef struct { WCHAR *buf; int cap; int len; int overflow; } sgw_fonts;

static int CALLBACK sgw_font_cb(const LOGFONTW *lf, const TEXTMETRICW *tm, DWORD type, LPARAM p) {
    sgw_fonts *f = (sgw_fonts *) p;
    const WCHAR *name = lf->lfFaceName;
    WCHAR key[LF_FACESIZE + 3];
    int n = (int) wcslen(name);
    (void) tm; (void) type;
    if (n == 0 || name[0] == L'@') return 1;
    key[0] = 0x1F; wcscpy(key + 1, name); key[n + 1] = 0x1F; key[n + 2] = 0;
    f->buf[f->len] = 0;
    if (wcsstr(f->buf, key)) return 1;              /* this family is in already */
    if (f->len + n + 2 >= f->cap) { f->overflow = 1; return 0; }
    wcscpy(f->buf + f->len, name);
    f->len += n;
    f->buf[f->len++] = 0x1F;
    return 1;
}

static int sgw_font_families(WCHAR *buf, int cap) {
    LOGFONTW lf;
    HDC dc;
    sgw_fonts f;
    if (cap < 2) return -1;
    memset(&lf, 0, sizeof lf);
    lf.lfCharSet = DEFAULT_CHARSET;
    f.buf = buf; f.cap = cap; f.len = 1; f.overflow = 0;
    buf[0] = 0x1F;
    dc = GetDC(NULL);
    EnumFontFamiliesExW(dc, &lf, (FONTENUMPROCW) sgw_font_cb, (LPARAM) &f, 0);
    ReleaseDC(NULL, dc);
    buf[f.len] = 0;
    return f.overflow ? -1 : f.len;
}

#endif
