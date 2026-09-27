#define WIN32_LEAN_AND_MEAN
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <windowsx.h>
#include <dwmapi.h>
#include <shlobj.h>
#include <shellapi.h>
#include <wrl.h>
#include <winhttp.h>
#include <string>
#include <filesystem>
#include <algorithm>
#include <vector>
#include <cwctype>
#include <cstdlib>
#include <cmath>
#include "WebView2.h"

#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "version.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "winhttp.lib")

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

namespace {
constexpr int ID_BACK = 1001;
constexpr int ID_FORWARD = 1002;
constexpr int ID_HOME = 1003;
constexpr int ID_RELOAD = 1004;
constexpr int ID_DOWNLOAD = 1005;
constexpr int ID_TAB_YOUTUBE = 1101;
constexpr int ID_TAB_EDITOR = 1102;
constexpr int ID_TAB_FILES = 1103;
constexpr int ID_OPEN_DOWNLOADS = 1201;
constexpr int ID_OPEN_EDITED = 1202;
constexpr int ID_DL_4K = 2101;
constexpr int ID_DL_1080 = 2102;
constexpr int ID_DL_720 = 2103;
constexpr int ID_DL_MP3 = 2104;

constexpr wchar_t kWindowClass[] = L"YTStudioCoreNativeV24Window";
constexpr wchar_t kHomeUrl[] = L"https://www.youtube.com/";
constexpr wchar_t kEditorUrl[] = L"http://127.0.0.1:30841/editor";
constexpr wchar_t kHelperToken[] = L"ytstudio-core-native-v241-30841";

enum class ViewMode { YouTube, Editor, Files };

HWND g_hwnd = nullptr;
HWND g_btnBack = nullptr;
HWND g_btnForward = nullptr;
HWND g_btnHome = nullptr;
HWND g_btnReload = nullptr;
HWND g_btnDownload = nullptr;
HWND g_tabYouTube = nullptr;
HWND g_tabEditor = nullptr;
HWND g_tabFiles = nullptr;
HWND g_btnOpenDownloads = nullptr;
HWND g_btnOpenEdited = nullptr;

HFONT g_font = nullptr;
HFONT g_fontTitle = nullptr;
HBRUSH g_bgBrush = nullptr;
HBRUSH g_topBrush = nullptr;
HBRUSH g_navBrush = nullptr;

ComPtr<ICoreWebView2Environment> g_env;
ComPtr<ICoreWebView2Controller> g_youtubeController;
ComPtr<ICoreWebView2Controller> g_editorController;
ComPtr<ICoreWebView2> g_youtubeWebView;
ComPtr<ICoreWebView2> g_editorWebView;

EventRegistrationToken g_historyToken{};
EventRegistrationToken g_navStartToken{};
EventRegistrationToken g_navDoneToken{};
EventRegistrationToken g_fullscreenToken{};

ViewMode g_view = ViewMode::YouTube;
bool g_fullscreen = false;
bool g_helperAvailable = false;
bool g_editorLoaded = false;
HANDLE g_helperProcess = nullptr;
UINT_PTR g_hudTimer = 0;
int g_hudPhase = 0;
std::wstring g_status = L"INICIANDO CORE";
std::wstring g_downloadJob;
std::wstring g_downloadText;
double g_downloadProgress = -1.0;
bool g_downloadActive = false;
bool g_downloadFailed = false;
int g_downloadHoldTicks = 0;
int g_downloadCount = 0;
int g_editedCount = 0;
std::vector<std::wstring> g_recentDownloads;
std::vector<std::wstring> g_recentEdited;

std::wstring ExeDir() {
    wchar_t buf[32768]{};
    DWORD n = GetModuleFileNameW(nullptr, buf, static_cast<DWORD>(_countof(buf)));
    if (!n || n >= _countof(buf)) return L".";
    return std::filesystem::path(buf).parent_path().wstring();
}

std::wstring Join(const std::wstring& a, const std::wstring& b) {
    return (std::filesystem::path(a) / b).wstring();
}

std::wstring VideosRoot() {
    PWSTR raw = nullptr;
    std::filesystem::path root;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Videos, KF_FLAG_CREATE, nullptr, &raw)) && raw) {
        root = raw;
        CoTaskMemFree(raw);
    } else {
        wchar_t home[32768]{};
        GetEnvironmentVariableW(L"USERPROFILE", home, static_cast<DWORD>(_countof(home)));
        root = std::filesystem::path(home) / L"Videos";
    }
    root /= L"YT Studio CORE";
    std::error_code ec;
    std::filesystem::create_directories(root / L"Descargas", ec);
    std::filesystem::create_directories(root / L"Editados", ec);
    return root.wstring();
}

std::wstring DownloadsDir() { return Join(VideosRoot(), L"Descargas"); }
std::wstring EditedDir() { return Join(VideosRoot(), L"Editados"); }

bool IsMediaPath(const std::filesystem::path& p) {
    auto ext = p.extension().wstring();
    std::transform(ext.begin(), ext.end(), ext.begin(), ::towlower);
    return ext == L".mp4" || ext == L".mkv" || ext == L".webm" || ext == L".mov" ||
           ext == L".m4v" || ext == L".avi" || ext == L".mp3" || ext == L".ts" || ext == L".m2ts";
}

int CountMediaFiles(const std::wstring& folder) {
    int count = 0;
    std::error_code ec;
    for (const auto& e : std::filesystem::directory_iterator(folder, ec)) {
        if (ec) break;
        if (e.is_regular_file(ec) && IsMediaPath(e.path())) ++count;
    }
    return count;
}

std::vector<std::wstring> RecentMediaFiles(const std::wstring& folder, size_t limit = 4) {
    struct Item { std::filesystem::file_time_type t; std::wstring name; };
    std::vector<Item> items;
    std::error_code ec;
    for (const auto& e : std::filesystem::directory_iterator(folder, ec)) {
        if (ec) break;
        if (!e.is_regular_file(ec) || !IsMediaPath(e.path())) continue;
        auto t = e.last_write_time(ec);
        if (ec) { ec.clear(); continue; }
        items.push_back({t, e.path().filename().wstring()});
    }
    std::sort(items.begin(), items.end(), [](const Item& a, const Item& b) { return a.t > b.t; });
    std::vector<std::wstring> out;
    for (size_t i = 0; i < items.size() && i < limit; ++i) out.push_back(items[i].name);
    return out;
}

void UpdateFileButtons() {
    g_downloadCount = CountMediaFiles(DownloadsDir());
    g_editedCount = CountMediaFiles(EditedDir());
    g_recentDownloads = RecentMediaFiles(DownloadsDir());
    g_recentEdited = RecentMediaFiles(EditedDir());
    if (!g_btnOpenDownloads || !g_btnOpenEdited) return;
    SetWindowTextW(g_btnOpenDownloads, L"ABRIR DESCARGAS");
    SetWindowTextW(g_btnOpenEdited, L"ABRIR EDITADOS");
}

int MonitorLogicalWidth(HWND hwnd) {
    HMONITOR mon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi{}; mi.cbSize = sizeof(mi);
    if (GetMonitorInfoW(mon, &mi)) return mi.rcMonitor.right - mi.rcMonitor.left;
    return 1366;
}

int Ui(HWND hwnd, int px) {
    UINT dpi = hwnd ? GetDpiForWindow(hwnd) : 96;
    double res = 1.0;
    const int mw = hwnd ? MonitorLogicalWidth(hwnd) : 1366;
    if (mw >= 3400) res = 1.34;
    else if (mw >= 2400) res = 1.16;
    else if (mw >= 1800) res = 1.06;
    return static_cast<int>((MulDiv(px, static_cast<int>(dpi), 96) * res) + 0.5);
}

std::wstring LocalAppDataPath() {
    wchar_t buf[32768]{};
    DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", buf, static_cast<DWORD>(_countof(buf)));
    if (n == 0 || n >= _countof(buf)) GetTempPathW(static_cast<DWORD>(_countof(buf)), buf);
    std::filesystem::path p(buf);
    p /= L"YTStudioCoreNative";
    p /= L"WebView2";
    std::error_code ec;
    std::filesystem::create_directories(p, ec);
    return p.wstring();
}

void SetStatus(const std::wstring& text) {
    g_status = text;
    if (g_hwnd) InvalidateRect(g_hwnd, nullptr, FALSE);
}

void OpenFolder(const std::wstring& folder) {
    std::error_code ec;
    std::filesystem::create_directories(folder, ec);
    ShellExecuteW(g_hwnd, L"open", folder.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
}
bool StartHelper() {
    const std::wstring base = ExeDir();
    const std::wstring python = Join(base, L"runtime\python.exe");
    const std::wstring helper = Join(base, L"helper_native.py");
    const std::wstring editor = Join(base, L"web\editor.html");
    if (!std::filesystem::exists(python) || !std::filesystem::exists(helper) || !std::filesystem::exists(editor)) {
        return false;
    }

    std::wstring cmd = L""" + python + L"" "" + helper + L""";
    STARTUPINFOW si{}; si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};
    BOOL ok = CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, FALSE,
        CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT, nullptr, base.c_str(), &si, &pi);
    if (!ok) return false;
    CloseHandle(pi.hThread);
    g_helperProcess = pi.hProcess;
    Sleep(850);
    return true;
}

void StopHelper() {
    if (!g_helperProcess) return;
    DWORD code = STILL_ACTIVE;
    if (GetExitCodeProcess(g_helperProcess, &code) && code == STILL_ACTIVE) {
        TerminateProcess(g_helperProcess, 0);
        WaitForSingleObject(g_helperProcess, 1000);
    }
    CloseHandle(g_helperProcess);
    g_helperProcess = nullptr;
}

std::string WideToUtf8(const std::wstring& value) {
    if (value.empty()) return {};
    int n = WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    if (n <= 0) return {};
    std::string out(static_cast<size_t>(n), ' ');
    WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), out.data(), n, nullptr, nullptr);
    return out;
}

std::wstring Utf8ToWide(const std::string& value) {
    if (value.empty()) return {};
    int n = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
    if (n <= 0) return {};
    std::wstring out(static_cast<size_t>(n), L' ');
    MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), out.data(), n);
    return out;
}

std::string JsonEscapeUtf8(const std::wstring& value) {
    const std::string raw = WideToUtf8(value);
    std::string out; out.reserve(raw.size() + 8);
    for (unsigned char c : raw) {
        switch (c) {
        case '\': out += "\\"; break;
        case '"': out += "\""; break;
        case '
': out += "\n"; break;
        case '': out += "\r"; break;
        case '	': out += "\t"; break;
        default: out.push_back(static_cast<char>(c)); break;
        }
    }
    return out;
}

bool LocalHttp(const wchar_t* method, const std::wstring& path, const std::string& body, bool auth, std::string& response) {
    response.clear();
    HINTERNET session = WinHttpOpen(L"YTStudioCoreNative/2.4.1", WINHTTP_ACCESS_TYPE_NO_PROXY,
        WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!session) return false;
    WinHttpSetTimeouts(session, 800, 800, 1200, 1800);
    HINTERNET connect = WinHttpConnect(session, L"127.0.0.1", 30841, 0);
    if (!connect) { WinHttpCloseHandle(session); return false; }
    HINTERNET request = WinHttpOpenRequest(connect, method, path.c_str(), nullptr,
        WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, 0);
    if (!request) { WinHttpCloseHandle(connect); WinHttpCloseHandle(session); return false; }

    std::wstring headers = L"Content-Type: application/json
";
    if (auth) headers += std::wstring(L"X-YT-Studio-Token: ") + kHelperToken + L"
";
    BOOL ok = WinHttpSendRequest(request, headers.c_str(), static_cast<DWORD>(-1L),
        body.empty() ? WINHTTP_NO_REQUEST_DATA : const_cast<char*>(body.data()),
        static_cast<DWORD>(body.size()), static_cast<DWORD>(body.size()), 0);
    if (ok) ok = WinHttpReceiveResponse(request, nullptr);

    DWORD status = 0, statusSize = sizeof(status);
    if (ok) WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
        WINHTTP_HEADER_NAME_BY_INDEX, &status, &statusSize, WINHTTP_NO_HEADER_INDEX);

    if (ok) {
        for (;;) {
            DWORD available = 0;
            if (!WinHttpQueryDataAvailable(request, &available) || available == 0) break;
            std::string chunk(static_cast<size_t>(available), ' ');
            DWORD read = 0;
            if (!WinHttpReadData(request, chunk.data(), available, &read)) { ok = FALSE; break; }
            chunk.resize(read); response += chunk;
        }
    }
    WinHttpCloseHandle(request); WinHttpCloseHandle(connect); WinHttpCloseHandle(session);
    return ok && status >= 200 && status < 300;
}

std::string JsonStringValue(const std::string& json, const char* key) {
    const std::string needle = std::string(""") + key + """;
    size_t p = json.find(needle); if (p == std::string::npos) return {};
    p = json.find(':', p + needle.size()); if (p == std::string::npos) return {};
    p = json.find('"', p + 1); if (p == std::string::npos) return {};
    ++p; std::string out; bool esc = false;
    for (; p < json.size(); ++p) {
        char c = json[p];
        if (esc) { if (c == 'n') out.push_back('
'); else if (c == 'r') out.push_back(''); else if (c == 't') out.push_back('	'); else out.push_back(c); esc = false; continue; }
        if (c == '\') { esc = true; continue; }
        if (c == '"') break;
        out.push_back(c);
    }
    return out;
}

double JsonNumberValue(const std::string& json, const char* key, double fallback = 0.0) {
    const std::string needle = std::string(""") + key + """;
    size_t p = json.find(needle); if (p == std::string::npos) return fallback;
    p = json.find(':', p + needle.size()); if (p == std::string::npos) return fallback;
    ++p; while (p < json.size() && (json[p] == ' ' || json[p] == '	')) ++p;
    char* end = nullptr; double v = std::strtod(json.c_str() + p, &end);
    return end == json.c_str() + p ? fallback : v;
}

std::wstring CurrentYouTubeUrl();
bool IsVideoUrl(const std::wstring& url);
void PollDownloadJob();

void UpdateNavState() {
    if (!g_youtubeWebView) return;
    BOOL canBack = FALSE, canForward = FALSE;
    g_youtubeWebView->get_CanGoBack(&canBack);
    g_youtubeWebView->get_CanGoForward(&canForward);
    EnableWindow(g_btnBack, canBack);
    EnableWindow(g_btnForward, canForward);
    const std::wstring url = CurrentYouTubeUrl();
    const bool video = IsVideoUrl(url);
    if (g_downloadActive) {
        EnableWindow(g_btnDownload, FALSE);
        int pct = static_cast<int>((std::max)(0.0, (std::min)(100.0, g_downloadProgress)) + 0.5);
        std::wstring t = L"DESCARGANDO " + std::to_wstring(pct) + L"%";
        SetWindowTextW(g_btnDownload, t.c_str());
    } else {
        EnableWindow(g_btnDownload, video ? TRUE : FALSE);
        SetWindowTextW(g_btnDownload, video ? L"DESCARGAR VIDEO" : L"DESCARGAR");
    }
}

void RecreateFonts() {
    if (g_font) { DeleteObject(g_font); g_font = nullptr; }
    if (g_fontTitle) { DeleteObject(g_fontTitle); g_fontTitle = nullptr; }
    g_font = CreateFontW(-Ui(g_hwnd, 14), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    g_fontTitle = CreateFontW(-Ui(g_hwnd, 17), 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Display");
    for (HWND h : { g_btnBack,g_btnForward,g_btnHome,g_btnReload,g_btnDownload,g_tabYouTube,g_tabEditor,g_tabFiles,g_btnOpenDownloads,g_btnOpenEdited }) {
        if (h) SendMessageW(h, WM_SETFONT, reinterpret_cast<WPARAM>(g_font), TRUE);
    }
}

void ShowNativeControls(bool showTop, bool showNav, bool showFiles) {
    for (HWND h : { g_tabYouTube,g_tabEditor,g_tabFiles }) ShowWindow(h, showTop ? SW_SHOW : SW_HIDE);
    for (HWND h : { g_btnBack,g_btnForward,g_btnHome,g_btnReload,g_btnDownload }) ShowWindow(h, (showTop && showNav) ? SW_SHOW : SW_HIDE);
    for (HWND h : { g_btnOpenDownloads,g_btnOpenEdited }) ShowWindow(h, (showTop && showFiles) ? SW_SHOW : SW_HIDE);
}

void Layout() {
    if (!g_hwnd) return;
    RECT rc{}; GetClientRect(g_hwnd, &rc);
    const int w = rc.right;
    const int h = rc.bottom;
    const bool topVisible = !g_fullscreen;
    const bool navVisible = topVisible && g_view == ViewMode::YouTube;
    const bool filesVisible = topVisible && g_view == ViewMode::Files;
    const int topH = topVisible ? Ui(g_hwnd, 70) : 0;
    const int navH = navVisible ? Ui(g_hwnd, 50) : 0;
    const int contentTop = topH + navH;
    const int margin = Ui(g_hwnd, 12);
    const int gap = Ui(g_hwnd, 7);
    const int tabH = Ui(g_hwnd, 38);
    const int tabW = Ui(g_hwnd, MonitorLogicalWidth(g_hwnd) <= 1400 ? 96 : 110);
    const int tabY = topVisible ? (topH - tabH) / 2 : 0;
    int tabX = Ui(g_hwnd, MonitorLogicalWidth(g_hwnd) <= 1400 ? 265 : 300);

    ShowNativeControls(topVisible, navVisible, filesVisible);

    if (topVisible) {
        MoveWindow(g_tabYouTube, tabX, tabY, tabW, tabH, TRUE); tabX += tabW + gap;
        MoveWindow(g_tabEditor, tabX, tabY, tabW, tabH, TRUE); tabX += tabW + gap;
        MoveWindow(g_tabFiles, tabX, tabY, tabW, tabH, TRUE);
    }

    if (navVisible) {
        const int y = topH + Ui(g_hwnd, 8);
        const int bh = navH - Ui(g_hwnd, 16);
        const int navSmallW = Ui(g_hwnd, 48);
        const int navNormalW = Ui(g_hwnd, 88);
        int x = margin;
        MoveWindow(g_btnBack, x, y, navSmallW, bh, TRUE); x += navSmallW + gap;
        MoveWindow(g_btnForward, x, y, navSmallW, bh, TRUE); x += navSmallW + gap;
        MoveWindow(g_btnHome, x, y, navNormalW, bh, TRUE); x += navNormalW + gap;
        MoveWindow(g_btnReload, x, y, navNormalW, bh, TRUE);
        MoveWindow(g_btnDownload, w - Ui(g_hwnd, 142) - margin, y, Ui(g_hwnd, 142), bh, TRUE);
    }

    if (filesVisible) {
        const int cardW = (std::min)(Ui(g_hwnd, 400), (w - 3 * margin) / 2);
        const int bh = Ui(g_hwnd, 52);
        const int y = contentTop + Ui(g_hwnd, 360);
        const int total = cardW * 2 + gap;
        const int x0 = (w - total) / 2;
        MoveWindow(g_btnOpenDownloads, x0, y, cardW, bh, TRUE);
        MoveWindow(g_btnOpenEdited, x0 + cardW + gap, y, cardW, bh, TRUE);
    }
