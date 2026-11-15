/* simple_gui, Windows backend, 1z-b: the media player's playback, Media Foundation's media
   engine (IMFMediaEngine) in frame-server mode. Inline-C header; nothing to build.

   The engine is made without MF_MEDIA_ENGINE_PLAYBACK_HWND, so it owns no window: it decodes,
   plays the sound itself, and serves video frames. The pump asks for them (sgw_media_tick):
   OnVideoStreamTick says when a new frame is due, and TransferVideoFrame copies it into a WIC
   bitmap (software decoding: no DXGI device manager is given), from which simple_widgets paints
   it. One drawn window, no child HWND.

   The engine's IMFMediaEngineNotify calls come on Media Foundation's own threads. They only
   queue (kind, value) pairs under the player's lock; the pump drains them (sgw_media_next) and
   pushes event 66. The pump turns often enough while a player is busy (GUI_BACKEND's
   `ms_to_next_media'), so nothing needs to wake it from another thread.

   Every function is called from one Eiffel class, GUI_SW_MEDIA_ENGINE, so this header is in
   one generated C file and has no shared mutable data (the inline-C statics rule).

   ISE compiles C for Windows 2000 (WINVER 0x0500), which hides the media engine; only the
   Media Foundation and WIC includes see Windows 10, as in simple_audio's audio_mf.h. The GUIDs
   used are copied here from the SDK headers, so no GUID library is needed. */
#ifndef SIMPLE_GUI_WIN_MEDIA_H
#define SIMPLE_GUI_WIN_MEDIA_H

#ifndef COBJMACROS
#define COBJMACROS
#endif
#include <windows.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#include <float.h>
#pragma push_macro("WINVER")
#pragma push_macro("_WIN32_WINNT")
#undef WINVER
#undef _WIN32_WINNT
#define WINVER 0x0A00
#define _WIN32_WINNT 0x0A00
#include <mfapi.h>
#include <mfmediaengine.h>
#include <wincodec.h>
#pragma pop_macro("_WIN32_WINNT")
#pragma pop_macro("WINVER")

#pragma comment(lib, "mfplat.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")

static const GUID sgw_media_iid_unknown =
    {0x00000000, 0x0000, 0x0000, {0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};
static const GUID sgw_media_iid_notify =
    {0xfee7c112, 0xe776, 0x42b5, {0x9b, 0xbf, 0x00, 0x48, 0x52, 0x4e, 0x2b, 0xd5}};
static const GUID sgw_media_iid_factory =
    {0x4d645ace, 0x26aa, 0x4688, {0x9b, 0xe1, 0xdf, 0x35, 0x16, 0x99, 0x0b, 0x93}};
static const GUID sgw_media_clsid_factory =
    {0xb44392da, 0x499b, 0x446b, {0xa4, 0xcb, 0x00, 0x5f, 0xea, 0xd0, 0xe6, 0xd5}};
static const GUID sgw_media_attr_callback =
    {0xc60381b8, 0x83a4, 0x41f8, {0xa3, 0xd0, 0xde, 0x05, 0x07, 0x68, 0x49, 0xa9}};
static const GUID sgw_media_attr_output_format =
    {0x5066893c, 0x8cf9, 0x42bc, {0x8b, 0x8a, 0x47, 0x22, 0x12, 0xe5, 0x27, 0x26}};
static const GUID sgw_media_clsid_wic =
    {0xcacaf262, 0x9370, 0x4615, {0xa1, 0x3b, 0x9f, 0x55, 0x39, 0xda, 0x4c, 0x0a}};
static const GUID sgw_media_iid_wic =
    {0xec5ec8a9, 0xc395, 0x4314, {0x9c, 0x77, 0x54, 0xd7, 0xa9, 0x35, 0xff, 0x70}};
static const GUID sgw_media_wic_bgra =
    {0x6fddc324, 0x4e03, 0x4bfe, {0xb1, 0x85, 0x3d, 0x77, 0x76, 0x8d, 0xc9, 0x0f}};
static const GUID sgw_media_wic_pbgra =
    {0x6fddc324, 0x4e03, 0x4bfe, {0xb1, 0x85, 0x3d, 0x77, 0x76, 0x8d, 0xc9, 0x10}};

#define SGW_MEDIA_QCAP 64
#define SGW_MEDIA_FAILURE 600

typedef struct sgw_media {
    IMFMediaEngineNotify notify;      /* first: the engine calls back through it */
    volatile LONG refs;
    CRITICAL_SECTION lock;
    IMFMediaEngine *engine;
    IWICImagingFactory *wic;
    IWICBitmap *frame;                /* the frame transferred last */
    int frame_w, frame_h, has_frame, pbgra;
    int q[SGW_MEDIA_QCAP][2];         /* (kind, value) for event 66, under `lock' */
    int qh, qt;
    int loops, opened, told_ready, told_failed;
    char failure[SGW_MEDIA_FAILURE];  /* UTF-8 */
    HRESULT last_hr;                  /* the last failed call, for the trace */
} sgw_media;

static int sgw_media_tracing(void) {
    char l_value[8];
    return GetEnvironmentVariableA("SIMPLE_GUI_MEDIA_TRACE", l_value, sizeof l_value) > 0;
}

static void sgw_media_trace(const char *a_what, HRESULT a_hr) {
    if (sgw_media_tracing()) {
        fprintf(stderr, "    [media] %s: 0x%08lX\n", a_what, (unsigned long) a_hr);
        fflush(stderr);
    }
}

/* Queue (kind, value) for the pump; any thread. */
static void sgw_media_queue(sgw_media *m, int a_kind, int a_value) {
    int n;
    EnterCriticalSection(&m->lock);
    n = (m->qt + 1) % SGW_MEDIA_QCAP;
    if (n != m->qh) {
        m->q[m->qt][0] = a_kind;
        m->q[m->qt][1] = a_value;
        m->qt = n;
    }
    LeaveCriticalSection(&m->lock);
}

/* The next queued (kind, value), on the pump's thread; 0 when none. */
static int sgw_media_next(sgw_media *m, int *a_kind, int *a_value) {
    int l_found = 0;
    if (!m) return 0;
    EnterCriticalSection(&m->lock);
    if (m->qh != m->qt) {
        *a_kind = m->q[m->qh][0];
        *a_value = m->q[m->qh][1];
        m->qh = (m->qh + 1) % SGW_MEDIA_QCAP;
        l_found = 1;
    }
    LeaveCriticalSection(&m->lock);
    return l_found;
}

static double sgw_media_seconds(double a_value) {
    return (_isnan(a_value) || !_finite(a_value) || a_value < 0.0) ? 0.0 : a_value;
}

static int sgw_media_duration_ms(sgw_media *m) {
    if (!m || !m->engine || !m->told_ready) return 0;
    return (int) floor(sgw_media_seconds(IMFMediaEngine_GetDuration(m->engine)) * 1000.0 + 0.5);
}

/* Why it failed, in words: the media error's code and the system's text for its HRESULT. */
static void sgw_media_describe_failure(sgw_media *m, int a_code, HRESULT a_hr) {
    static const char *const l_names[] = {"", "the loading was aborted", "a network error",
        "the media could not be decoded", "the media cannot be opened or is not supported",
        "the media is encrypted"};
    WCHAR l_text[300];
    char l_utf8[400];
    DWORD n;
    l_utf8[0] = 0;
    n = FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL, (DWORD) a_hr,
        0, l_text, 300, NULL);
    while (n > 0 && (l_text[n - 1] == L'\r' || l_text[n - 1] == L'\n' || l_text[n - 1] == L' ' || l_text[n - 1] == L'.')) l_text[--n] = 0;
    if (n > 0) WideCharToMultiByte(CP_UTF8, 0, l_text, -1, l_utf8, sizeof l_utf8, NULL, NULL);
    EnterCriticalSection(&m->lock);
    _snprintf(m->failure, SGW_MEDIA_FAILURE - 1, "%s (Media Foundation error %d, 0x%08lX%s%s)",
        (a_code >= 1 && a_code <= 5) ? l_names[a_code] : "the media could not be played",
        a_code, (unsigned long) a_hr, l_utf8[0] ? ": " : "", l_utf8);
    m->failure[SGW_MEDIA_FAILURE - 1] = 0;
    LeaveCriticalSection(&m->lock);
}

/* ---------- IMFMediaEngineNotify ---------- */

static HRESULT STDMETHODCALLTYPE sgw_media_query(IMFMediaEngineNotify *a_this, REFIID a_iid, void **a_out) {
    if (!a_out) return E_POINTER;
    if (IsEqualIID(a_iid, &sgw_media_iid_unknown) || IsEqualIID(a_iid, &sgw_media_iid_notify)) {
        *a_out = a_this;
        a_this->lpVtbl->AddRef(a_this);
        return S_OK;
    }
    *a_out = NULL;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE sgw_media_add_ref(IMFMediaEngineNotify *a_this) {
    return (ULONG) InterlockedIncrement(&((sgw_media *) a_this)->refs);
}

static ULONG STDMETHODCALLTYPE sgw_media_release(IMFMediaEngineNotify *a_this) {
    sgw_media *m = (sgw_media *) a_this;
    LONG n = InterlockedDecrement(&m->refs);
    if (n == 0) {
        DeleteCriticalSection(&m->lock);
        free(m);
    }
    return (ULONG) n;
}

/* On Media Foundation's thread: queue what the pump reports. Never calls the engine back, but
   for the error it is reporting. */
static HRESULT STDMETHODCALLTYPE sgw_media_event(IMFMediaEngineNotify *a_this, DWORD a_event, DWORD_PTR a_one, DWORD a_two) {
    sgw_media *m = (sgw_media *) a_this;
    switch (a_event) {
    case MF_MEDIA_ENGINE_EVENT_LOADEDMETADATA:
        sgw_media_queue(m, 1, 0);
        break;
    case MF_MEDIA_ENGINE_EVENT_ENDED:
        if (!m->loops) sgw_media_queue(m, 3, 0);
        break;
    case MF_MEDIA_ENGINE_EVENT_ERROR:
        sgw_media_describe_failure(m, (int) a_one, (HRESULT) a_two);
        sgw_media_queue(m, 4, 0);
        break;
    default:
        break;
    }
    return S_OK;
}

static IMFMediaEngineNotifyVtbl sgw_media_notify_vtbl = {
    sgw_media_query, sgw_media_add_ref, sgw_media_release, sgw_media_event
};

/* ---------- the player ---------- */

/* A player with its engine, or NULL when Media Foundation is not there (Windows N without the
   Media Feature Pack). */
static sgw_media *sgw_media_new(void) {
    sgw_media *m;
    IMFMediaEngineClassFactory *l_factory = NULL;
    IMFAttributes *l_attributes = NULL;
    HRESULT hr;
    hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    (void) hr;   /* already initialized on this thread, in whichever model: fine either way */
    hr = MFStartup(MF_VERSION, MFSTARTUP_FULL);
    if (FAILED(hr)) { sgw_media_trace("MFStartup", hr); return NULL; }
    m = (sgw_media *) calloc(1, sizeof (sgw_media));
    if (!m) { MFShutdown(); return NULL; }
    m->notify.lpVtbl = &sgw_media_notify_vtbl;
    m->refs = 1;
    InitializeCriticalSection(&m->lock);
    hr = CoCreateInstance(&sgw_media_clsid_factory, NULL, CLSCTX_INPROC_SERVER, &sgw_media_iid_factory, (void **) &l_factory);
    if (SUCCEEDED(hr)) hr = MFCreateAttributes(&l_attributes, 2);
    if (SUCCEEDED(hr)) hr = IMFAttributes_SetUnknown(l_attributes, &sgw_media_attr_callback, (IUnknown *) &m->notify);
    if (SUCCEEDED(hr)) hr = IMFAttributes_SetUINT32(l_attributes, &sgw_media_attr_output_format, 87 /* DXGI_FORMAT_B8G8R8A8_UNORM */);
    if (SUCCEEDED(hr)) hr = IMFMediaEngineClassFactory_CreateInstance(l_factory, 0, l_attributes, &m->engine);
    if (SUCCEEDED(hr)) hr = CoCreateInstance(&sgw_media_clsid_wic, NULL, CLSCTX_INPROC_SERVER, &sgw_media_iid_wic, (void **) &m->wic);
    if (l_attributes) IMFAttributes_Release(l_attributes);
    if (l_factory) IMFMediaEngineClassFactory_Release(l_factory);
    if (FAILED(hr)) {
        sgw_media_trace("creating the media engine", hr);
        if (m->engine) { IMFMediaEngine_Shutdown(m->engine); IMFMediaEngine_Release(m->engine); }
        if (m->wic) IWICImagingFactory_Release(m->wic);
        m->notify.lpVtbl->Release(&m->notify);
        MFShutdown();
        return NULL;
    }
    IMFMediaEngine_SetPreload(m->engine, MF_MEDIA_ENGINE_PRELOAD_AUTOMATIC);
    return m;
}

/* Shut the engine down and let the player go (the engine's reference to the callback goes
   with it). */
static void sgw_media_free(sgw_media *m) {
    if (!m) return;
    if (m->engine) {
        IMFMediaEngine_Shutdown(m->engine);
        IMFMediaEngine_Release(m->engine);
        m->engine = NULL;
    }
    if (m->frame) { IWICBitmap_Release(m->frame); m->frame = NULL; }
    if (m->wic) { IWICImagingFactory_Release(m->wic); m->wic = NULL; }
    m->notify.lpVtbl->Release(&m->notify);
    MFShutdown();
}

/* Open `a_text' (UTF-8): a file path (made absolute) or, with `a_is_url', a URL. Ready (1) or
   failed (4) is queued later by the engine. */
static void sgw_media_open(sgw_media *m, const char *a_text, int a_is_url) {
    WCHAR l_given[2048], l_full[2048];
    const WCHAR *l_source = l_given;
    BSTR l_url;
    HRESULT hr;
    if (!m || !m->engine) return;
    EnterCriticalSection(&m->lock);
    m->qh = m->qt = 0;
    m->failure[0] = 0;
    m->told_ready = m->told_failed = 0;
    m->has_frame = 0;
    m->opened = 1;
    LeaveCriticalSection(&m->lock);
    if (!MultiByteToWideChar(CP_UTF8, 0, a_text, -1, l_given, 2048)) l_given[0] = 0;
    if (!a_is_url && GetFullPathNameW(l_given, 2048, l_full, NULL) > 0) l_source = l_full;
    l_url = SysAllocString(l_source);
    hr = l_url ? IMFMediaEngine_SetSource(m->engine, l_url) : E_OUTOFMEMORY;
    if (l_url) SysFreeString(l_url);
    if (FAILED(hr)) {
        sgw_media_trace("SetSource", hr);
        sgw_media_describe_failure(m, 4, hr);
        sgw_media_queue(m, 4, 0);
    }
}

static void sgw_media_play(sgw_media *m) {
    if (m && m->engine && m->opened) {
        if (IMFMediaEngine_IsEnded(m->engine)) IMFMediaEngine_SetCurrentTime(m->engine, 0.0);
        IMFMediaEngine_Play(m->engine);
    }
}

static void sgw_media_pause(sgw_media *m) { if (m && m->engine && m->opened) IMFMediaEngine_Pause(m->engine); }

static void sgw_media_seek(sgw_media *m, int a_ms) {
    if (m && m->engine && m->opened) IMFMediaEngine_SetCurrentTime(m->engine, (a_ms < 0 ? 0 : a_ms) / 1000.0);
}

static void sgw_media_stop(sgw_media *m) {
    if (m && m->engine && m->opened) {
        IMFMediaEngine_Pause(m->engine);
        IMFMediaEngine_SetCurrentTime(m->engine, 0.0);
    }
}

static int sgw_media_position_ms(sgw_media *m) {
    if (!m || !m->engine || !m->opened) return 0;
    return (int) floor(sgw_media_seconds(IMFMediaEngine_GetCurrentTime(m->engine)) * 1000.0 + 0.5);
}

static int sgw_media_is_playing(sgw_media *m) {
    if (!m || !m->engine || !m->opened) return 0;
    return !IMFMediaEngine_IsPaused(m->engine) && !IMFMediaEngine_IsEnded(m->engine);
}

static double sgw_media_rate(sgw_media *m) {
    return sgw_media_is_playing(m) ? IMFMediaEngine_GetPlaybackRate(m->engine) : 0.0;
}

static double sgw_media_volume(sgw_media *m) { return (m && m->engine) ? IMFMediaEngine_GetVolume(m->engine) : 0.0; }
static void sgw_media_set_volume(sgw_media *m, double a_volume) {
    if (m && m->engine) IMFMediaEngine_SetVolume(m->engine, a_volume < 0.0 ? 0.0 : (a_volume > 1.0 ? 1.0 : a_volume));
}
static int sgw_media_is_muted(sgw_media *m) { return (m && m->engine && IMFMediaEngine_GetMuted(m->engine)) ? 1 : 0; }
static void sgw_media_set_muted(sgw_media *m, int a_on) { if (m && m->engine) IMFMediaEngine_SetMuted(m->engine, a_on ? TRUE : FALSE); }
static void sgw_media_set_loops(sgw_media *m, int a_on) {
    if (m) {
        m->loops = a_on ? 1 : 0;
        if (m->engine) IMFMediaEngine_SetLoop(m->engine, a_on ? TRUE : FALSE);
    }
}

/* The natural video size, 0 by 0 for audio alone or before the metadata. */
static int sgw_media_video_width(sgw_media *m) {
    DWORD w = 0, h = 0;
    if (m && m->engine && m->opened && IMFMediaEngine_HasVideo(m->engine)) IMFMediaEngine_GetNativeVideoSize(m->engine, &w, &h);
    return (int) w;
}
static int sgw_media_video_height(sgw_media *m) {
    DWORD w = 0, h = 0;
    if (m && m->engine && m->opened && IMFMediaEngine_HasVideo(m->engine)) IMFMediaEngine_GetNativeVideoSize(m->engine, &w, &h);
    return (int) h;
}
static int sgw_media_has_video(sgw_media *m) {
    return (m && m->engine && m->opened && m->told_ready && IMFMediaEngine_HasVideo(m->engine)) ? 1 : 0;
}

/* The pump told ready (so `sgw_media_duration_ms' and `sgw_media_has_video' answer). */
static void sgw_media_mark_ready(sgw_media *m) { if (m) m->told_ready = 1; }

static const char *sgw_media_failure(sgw_media *m) { return m ? m->failure : ""; }

/* A new frame, when one is due: transferred into the WIC bitmap. 1 when there is a new one. */
static int sgw_media_tick(sgw_media *m) {
    LONGLONG l_pts = 0;
    DWORD w = 0, h = 0;
    RECT l_rect;
    MFARGB l_black = {0, 0, 0, 255};
    HRESULT hr;
    if (!m || !m->engine || !m->opened || !m->wic || !IMFMediaEngine_HasVideo(m->engine)) return 0;
    if (IMFMediaEngine_OnVideoStreamTick(m->engine, &l_pts) != S_OK) return 0;
    IMFMediaEngine_GetNativeVideoSize(m->engine, &w, &h);
    if (w == 0 || h == 0 || w > 8192 || h > 8192) return 0;
    if (!m->frame || m->frame_w != (int) w || m->frame_h != (int) h) {
        if (m->frame) { IWICBitmap_Release(m->frame); m->frame = NULL; }
        hr = IWICImagingFactory_CreateBitmap(m->wic, w, h, m->pbgra ? &sgw_media_wic_pbgra : &sgw_media_wic_bgra,
            WICBitmapCacheOnLoad, &m->frame);
        if (FAILED(hr)) { sgw_media_trace("CreateBitmap", hr); m->frame = NULL; return 0; }
        m->frame_w = (int) w;
        m->frame_h = (int) h;
        m->has_frame = 0;
    }
    SetRect(&l_rect, 0, 0, (int) w, (int) h);
    hr = IMFMediaEngine_TransferVideoFrame(m->engine, (IUnknown *) m->frame, NULL, &l_rect, &l_black);
    if (FAILED(hr)) {
        if (m->last_hr != hr) sgw_media_trace("TransferVideoFrame", hr);
        m->last_hr = hr;
        if (!m->pbgra) {
                /* the other 32-bit layout, once */
            m->pbgra = 1;
            IWICBitmap_Release(m->frame);
            m->frame = NULL;
        }
        return 0;
    }
    m->has_frame = 1;
    return 1;
}

static int sgw_media_frame_width(sgw_media *m) { return (m && m->has_frame) ? m->frame_w : 0; }
static int sgw_media_frame_height(sgw_media *m) { return (m && m->has_frame) ? m->frame_h : 0; }

/* Copy the last frame into a Cairo ARGB32 image (`a_data', `a_stride', `a_w' by `a_h', the
   frame's size), opaque. 1 when copied. */
static int sgw_media_copy_frame(sgw_media *m, unsigned char *a_data, int a_stride, int a_w, int a_h) {
    WICRect l_rect;
    IWICBitmapLock *l_lock = NULL;
    UINT l_size = 0, l_stride = 0;
    BYTE *l_bits = NULL;
    int y, x;
    if (!m || !m->has_frame || !m->frame || !a_data || a_w != m->frame_w || a_h != m->frame_h) return 0;
    l_rect.X = 0; l_rect.Y = 0; l_rect.Width = a_w; l_rect.Height = a_h;
    if (FAILED(IWICBitmap_Lock(m->frame, &l_rect, WICBitmapLockRead, &l_lock))) return 0;
    IWICBitmapLock_GetStride(l_lock, &l_stride);
    IWICBitmapLock_GetDataPointer(l_lock, &l_size, &l_bits);
    if (l_bits) {
        for (y = 0; y < a_h; y++) {
            unsigned char *l_to = a_data + (size_t) y * a_stride;
            memcpy(l_to, l_bits + (size_t) y * l_stride, (size_t) a_w * 4);
            for (x = 0; x < a_w; x++) l_to[x * 4 + 3] = 255;
        }
    }
    IWICBitmapLock_Release(l_lock);
    return l_bits ? 1 : 0;
}

/* The mean color over a 16 by 16 patch at the last frame's center, 0xFFRRGGBB; 0 with none. */
static unsigned int sgw_media_frame_color(sgw_media *m) {
    WICRect l_rect;
    IWICBitmapLock *l_lock = NULL;
    UINT l_size = 0, l_stride = 0;
    BYTE *l_bits = NULL;
    unsigned long r = 0, g = 0, b = 0, n = 0;
    int x, y;
    if (!m || !m->has_frame || !m->frame || m->frame_w < 16 || m->frame_h < 16) return 0;
    l_rect.X = m->frame_w / 2 - 8; l_rect.Y = m->frame_h / 2 - 8; l_rect.Width = 16; l_rect.Height = 16;
    if (FAILED(IWICBitmap_Lock(m->frame, &l_rect, WICBitmapLockRead, &l_lock))) return 0;
    IWICBitmapLock_GetStride(l_lock, &l_stride);
    IWICBitmapLock_GetDataPointer(l_lock, &l_size, &l_bits);
    if (l_bits) {
        for (y = 0; y < 16; y++) {
            for (x = 0; x < 16; x++) {
                BYTE *p = l_bits + (size_t) y * l_stride + (size_t) x * 4;   /* BGRA */
                b += p[0]; g += p[1]; r += p[2]; n++;
            }
        }
    }
    IWICBitmapLock_Release(l_lock);
    if (!n) return 0;
    return 0xFF000000u | (unsigned) ((r / n) << 16) | (unsigned) ((g / n) << 8) | (unsigned) (b / n);
}

#endif
