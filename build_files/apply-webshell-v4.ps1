param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectRoot
)

$ErrorActionPreference = "Stop"
$cpp = Join-Path $ProjectRoot "src\YTStudioNative.cpp"
$webDir = Join-Path $ProjectRoot "web"
if (-not (Test-Path $cpp)) { throw "Missing source: $cpp" }
New-Item -ItemType Directory -Force $webDir | Out-Null
Copy-Item "$PSScriptRoot\shell_v4.html" (Join-Path $webDir "shell.html") -Force
Copy-Item "$PSScriptRoot\files_v4.html" (Join-Path $webDir "files.html") -Force

$src = [IO.File]::ReadAllText($cpp)
$nl = [Environment]::NewLine

function Replace-One([string]$pattern,[string]$replacement,[string]$label) {
    $rx = [regex]::new($pattern,[Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $rx.IsMatch($script:src)) { throw "WebShell v4 anchor missing: $label" }
    $script:src = $rx.Replace($script:src,$replacement,1)
}

# File loading support for local HTML UI.
if (-not $src.Contains('#include <fstream>')) {
    $src = $src.Replace('#include <cmath>', '#include <cmath>' + $nl + '#include <fstream>' + $nl + '#include <iterator>')
}

# Web UI controllers.
$controllerAnchor = 'ComPtr<ICoreWebView2> g_editorWebView;'
if (-not $src.Contains($controllerAnchor)) { throw "WebShell v4 controller anchor missing" }
if (-not $src.Contains('ComPtr<ICoreWebView2Controller> g_shellController;')) {
$globals = @'
ComPtr<ICoreWebView2Controller> g_shellController;
ComPtr<ICoreWebView2> g_shellWebView;
ComPtr<ICoreWebView2Controller> g_filesController;
ComPtr<ICoreWebView2> g_filesWebView;
'@
    $src = $src.Replace($controllerAnchor, $controllerAnchor + $nl + $globals.TrimEnd())
}

$tokenAnchor = 'EventRegistrationToken g_fullscreenToken{};'
if (-not $src.Contains($tokenAnchor)) { throw "WebShell v4 token anchor missing" }
if (-not $src.Contains('EventRegistrationToken g_shellMessageToken{};')) {
$tokens = @'
EventRegistrationToken g_shellMessageToken{};
EventRegistrationToken g_filesMessageToken{};
bool g_shellReady = false;
bool g_filesReady = false;
'@
    $src = $src.Replace($tokenAnchor, $tokenAnchor + $nl + $tokens.TrimEnd())
}

# Forward declarations used by early state functions.
$forwardAnchor = 'std::vector<std::wstring> g_recentEdited;'
if (-not $src.Contains($forwardAnchor)) { throw "WebShell v4 state anchor missing" }
if (-not $src.Contains('void PostShellState();')) {
    $src = $src.Replace($forwardAnchor, $forwardAnchor + $nl + $nl + 'void PostShellState();' + $nl + 'void PostFilesState();')
}

# Replace native-only file state updater.
$updateFiles = @'
void UpdateFileButtons() {
    g_downloadCount = CountMediaFiles(DownloadsDir());
    g_editedCount = CountMediaFiles(EditedDir());
    g_recentDownloads = RecentMediaFiles(DownloadsDir());
    g_recentEdited = RecentMediaFiles(EditedDir());
    if (g_btnOpenDownloads) SetWindowTextW(g_btnOpenDownloads, L"ABRIR DESCARGAS");
    if (g_btnOpenEdited) SetWindowTextW(g_btnOpenEdited, L"ABRIR EDITADOS");
    PostShellState();
    PostFilesState();
}

int MonitorLogicalWidth
'@
Replace-One 'void UpdateFileButtons\(\) \{.*?\r?\n\}\r?\n\r?\nint MonitorLogicalWidth' $updateFiles 'UpdateFileButtons'

# Add UI helpers immediately after Ui().
$uiPattern = 'int Ui\(HWND hwnd, int px\) \{.*?\r?\n\}'
$rxUi = [regex]::new($uiPattern,[Text.RegularExpressions.RegexOptions]::Singleline)
$mUi = $rxUi.Match($src)
if (-not $mUi.Success) { throw "WebShell v4 Ui function missing" }
if (-not $src.Contains('int ShellHeight()')) {
$helpers = @'

int ShellHeight() {
    return g_fullscreen ? 0 : Ui(g_hwnd, 126);
}

std::wstring ReadUtf8TextFile(const std::wstring& path) {
    std::ifstream file(std::filesystem::path(path), std::ios::binary);
    if (!file) return L"";
    std::string bytes((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    if (bytes.size() >= 3 && static_cast<unsigned char>(bytes[0]) == 0xEF &&
        static_cast<unsigned char>(bytes[1]) == 0xBB && static_cast<unsigned char>(bytes[2]) == 0xBF) {
        bytes.erase(0, 3);
    }
    if (bytes.empty()) return L"";
    int n = MultiByteToWideChar(CP_UTF8, 0, bytes.data(), static_cast<int>(bytes.size()), nullptr, 0);
    if (n <= 0) return L"";
    std::wstring out(static_cast<size_t>(n), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, bytes.data(), static_cast<int>(bytes.size()), out.data(), n);
    return out;
}
'@
    $src = $src.Insert($mUi.Index + $mUi.Length, $helpers)
}

# Status now updates the HTML shell, not a GDI header.
$statusFn = @'
void SetStatus(const std::wstring& text) {
    g_status = text;
    PostShellState();
}

void OpenFolder
'@
Replace-One 'void SetStatus\(const std::wstring& text\) \{.*?\r?\n\}\r?\n\r?\nvoid OpenFolder' $statusFn 'SetStatus'

# Nav state now drives HTML buttons.
$navFn = @'
void UpdateNavState() {
    PostShellState();
}

void RecreateFonts
'@
Replace-One 'void UpdateNavState\(\) \{.*?\r?\n\}\r?\n\r?\nvoid RecreateFonts' $navFn 'UpdateNavState'

# Native buttons are retained only as dead compatibility objects if ever created; never shown.
$showFn = @'
void ShowNativeControls(bool, bool, bool) {
    for (HWND h : { g_tabYouTube,g_tabEditor,g_tabFiles,g_btnBack,g_btnForward,g_btnHome,g_btnReload,g_btnDownload,g_btnOpenDownloads,g_btnOpenEdited }) {
        if (h) ShowWindow(h, SW_HIDE);
    }
}

void Layout
'@
Replace-One 'void ShowNativeControls\(bool showTop, bool showNav, bool showFiles\) \{.*?\r?\n\}\r?\n\r?\nvoid Layout' $showFn 'ShowNativeControls'

# HTML shell occupies the complete app chrome. Content WebViews live below it.
$layoutFn = @'
void Layout() {
    if (!g_hwnd) return;
    RECT rc{}; GetClientRect(g_hwnd, &rc);
    const int w = rc.right;
    const int h = rc.bottom;
    const int shellH = ShellHeight();

    ShowNativeControls(false, false, false);

    if (g_shellController) {
        RECT shellBounds{0, 0, w, shellH};
        g_shellController->put_Bounds(shellBounds);
        g_shellController->put_IsVisible(g_fullscreen ? FALSE : TRUE);
    }

    RECT contentBounds{0, shellH, w, h};
    if (g_youtubeController) {
        g_youtubeController->put_Bounds(contentBounds);
        g_youtubeController->put_IsVisible(g_view == ViewMode::YouTube ? TRUE : FALSE);
    }
    if (g_editorController) {
        g_editorController->put_Bounds(contentBounds);
        g_editorController->put_IsVisible(g_view == ViewMode::Editor ? TRUE : FALSE);
    }
    if (g_filesController) {
        g_filesController->put_Bounds(contentBounds);
        g_filesController->put_IsVisible(g_view == ViewMode::Files ? TRUE : FALSE);
    }

    PostShellState();
    PostFilesState();
}

void SetView
'@
Replace-One 'void Layout\(\) \{.*?\r?\n\}\r?\n\r?\nvoid SetView' $layoutFn 'Layout'

# Web state bridge is inserted after IsVideoUrl(), where all conversion helpers are available.
$postState = @'
bool IsVideoUrl(const std::wstring& url) {
    return url.find(L"youtube.com/watch") != std::wstring::npos ||
           url.find(L"youtube.com/shorts/") != std::wstring::npos ||
           url.find(L"youtube.com/live/") != std::wstring::npos ||
           url.find(L"youtu.be/") != std::wstring::npos;
}

void PostShellState() {
    if (!g_shellWebView || !g_shellReady) return;

    BOOL canBack = FALSE, canForward = FALSE;
    if (g_youtubeWebView) {
        g_youtubeWebView->get_CanGoBack(&canBack);
        g_youtubeWebView->get_CanGoForward(&canForward);
    }
    const std::wstring url = CurrentYouTubeUrl();
    const bool video = IsVideoUrl(url);
    const char* view = g_view == ViewMode::YouTube ? "youtube" : (g_view == ViewMode::Editor ? "editor" : "files");

    UINT dpi = g_hwnd ? GetDpiForWindow(g_hwnd) : 96;
    std::wstring profile = std::to_wstring(MonitorLogicalWidth(g_hwnd) >= 1900 ? 1440 : 1080);
    profile = (MonitorLogicalWidth(g_hwnd) >= 3000 ? L"4K" : (MonitorLogicalWidth(g_hwnd) >= 1900 ? L"QHD" : L"FHD"));
    profile += L"  |  " + std::to_wstring(dpi) + L" DPI";

    std::string json = "{\"type\":\"state\",\"view\":\"";
    json += view;
    json += "\",\"status\":\"" + JsonEscapeUtf8(g_status) + "\"";
    json += ",\"profile\":\"" + JsonEscapeUtf8(profile) + "\"";
    json += ",\"canBack\":" + std::string(canBack ? "true" : "false");
    json += ",\"canForward\":" + std::string(canForward ? "true" : "false");
    json += ",\"isVideo\":" + std::string(video ? "true" : "false");
    json += ",\"helper\":" + std::string(g_helperAvailable ? "true" : "false");
    json += ",\"downloadActive\":" + std::string(g_downloadActive ? "true" : "false");
    json += ",\"downloadFailed\":" + std::string(g_downloadFailed ? "true" : "false");
    json += ",\"progress\":" + std::to_string(g_downloadProgress);
    json += ",\"downloadCount\":" + std::to_string(g_downloadCount);
    json += ",\"editedCount\":" + std::to_string(g_editedCount);
    json += "}";

    const std::wstring wide = Utf8ToWide(json);
    g_shellWebView->PostWebMessageAsJson(wide.c_str());
}

void PostFilesState() {
    if (!g_filesWebView || !g_filesReady) return;

    auto arrayJson = [](const std::vector<std::wstring>& items) {
        std::string out = "[";
        for (size_t i = 0; i < items.size(); ++i) {
            if (i) out += ",";
            out += "\"" + JsonEscapeUtf8(items[i]) + "\"";
        }
        out += "]";
        return out;
    };

    std::string json = "{\"type\":\"files\"";
    json += ",\"downloadCount\":" + std::to_string(g_downloadCount);
    json += ",\"editedCount\":" + std::to_string(g_editedCount);
    json += ",\"recentDownloads\":" + arrayJson(g_recentDownloads);
    json += ",\"recentEdited\":" + arrayJson(g_recentEdited);
    json += ",\"path\":\"" + JsonEscapeUtf8(VideosRoot()) + "\"}";
    const std::wstring wide = Utf8ToWide(json);
    g_filesWebView->PostWebMessageAsJson(wide.c_str());
}

void StartDownload
'@
Replace-One 'bool IsVideoUrl\(const std::wstring& url\) \{.*?\r?\n\}\r?\n\r?\nvoid StartDownload' $postState 'PostShellState'

# Create shell and files WebViews with a simple string-message command bridge.
$webControllers = @'
void CreateShellController(HWND hwnd) {
    if (!g_env) return;
    g_env->CreateCoreWebView2Controller(hwnd,
        Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
            [hwnd](HRESULT result, ICoreWebView2Controller* controller) -> HRESULT {
                if (FAILED(result) || !controller) return result;
                g_shellController = controller;
                HRESULT hr = g_shellController->get_CoreWebView2(g_shellWebView.GetAddressOf());
                if (FAILED(hr) || !g_shellWebView) return hr;

                ComPtr<ICoreWebView2Settings> settings;
                if (SUCCEEDED(g_shellWebView->get_Settings(settings.GetAddressOf())) && settings) {
                    settings->put_IsScriptEnabled(TRUE);
                    settings->put_IsWebMessageEnabled(TRUE);
                    settings->put_AreDefaultContextMenusEnabled(FALSE);
                    settings->put_AreDevToolsEnabled(TRUE);
                    settings->put_AreDefaultScriptDialogsEnabled(FALSE);
                }

                g_shellWebView->add_WebMessageReceived(
                    Callback<ICoreWebView2WebMessageReceivedEventHandler>(
                        [](ICoreWebView2*, ICoreWebView2WebMessageReceivedEventArgs* args) -> HRESULT {
                            if (!args) return S_OK;
                            LPWSTR raw = nullptr;
                            if (FAILED(args->TryGetWebMessageAsString(&raw)) || !raw) return S_OK;
                            std::wstring cmd(raw);
                            CoTaskMemFree(raw);

                            if (cmd == L"ready") {
                                g_shellReady = true;
                                PostShellState();
                            } else if (cmd == L"back") {
                                if (g_youtubeWebView) g_youtubeWebView->GoBack();
                            } else if (cmd == L"forward") {
                                if (g_youtubeWebView) g_youtubeWebView->GoForward();
                            } else if (cmd == L"home") {
                                NavigateHome();
                            } else if (cmd == L"reload") {
                                if (g_view == ViewMode::YouTube && g_youtubeWebView) g_youtubeWebView->Reload();
                                else if (g_view == ViewMode::Editor && g_editorWebView) g_editorWebView->Reload();
                                else if (g_view == ViewMode::Files) PostFilesState();
                            } else if (cmd == L"view:youtube") {
                                SetView(ViewMode::YouTube);
                            } else if (cmd == L"view:editor") {
                                SetView(ViewMode::Editor);
                            } else if (cmd == L"view:files") {
                                SetView(ViewMode::Files);
                            } else if (cmd == L"open:downloads") {
                                OpenFolder(DownloadsDir());
                            } else if (cmd == L"open:edited") {
                                OpenFolder(EditedDir());
                            } else if (cmd.rfind(L"download:", 0) == 0) {
                                const std::wstring fmt = cmd.substr(9);
                                if (fmt == L"4k" || fmt == L"1080" || fmt == L"720" || fmt == L"mp3") StartDownload(fmt.c_str());
                            }
                            return S_OK;
                        }).Get(), &g_shellMessageToken);

                const std::wstring shell = ReadUtf8TextFile(Join(ExeDir(), L"web\\shell.html"));
                g_shellReady = false;
                if (!shell.empty()) g_shellWebView->NavigateToString(shell.c_str());
                else g_shellWebView->NavigateToString(L"<html><body style='margin:0;background:#020711;color:#7eeaff;font:16px Segoe UI;display:grid;place-items:center'>UI SHELL NO DISPONIBLE</body></html>");
                Layout();
                return S_OK;
            }).Get());
}

void CreateFilesController(HWND hwnd) {
    if (!g_env) return;
    g_env->CreateCoreWebView2Controller(hwnd,
        Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
            [hwnd](HRESULT result, ICoreWebView2Controller* controller) -> HRESULT {
                if (FAILED(result) || !controller) return result;
                g_filesController = controller;
                HRESULT hr = g_filesController->get_CoreWebView2(g_filesWebView.GetAddressOf());
                if (FAILED(hr) || !g_filesWebView) return hr;

                ComPtr<ICoreWebView2Settings> settings;
                if (SUCCEEDED(g_filesWebView->get_Settings(settings.GetAddressOf())) && settings) {
                    settings->put_IsScriptEnabled(TRUE);
                    settings->put_IsWebMessageEnabled(TRUE);
                    settings->put_AreDefaultContextMenusEnabled(FALSE);
                    settings->put_AreDevToolsEnabled(TRUE);
                }

                g_filesWebView->add_WebMessageReceived(
                    Callback<ICoreWebView2WebMessageReceivedEventHandler>(
                        [](ICoreWebView2*, ICoreWebView2WebMessageReceivedEventArgs* args) -> HRESULT {
                            if (!args) return S_OK;
                            LPWSTR raw = nullptr;
                            if (FAILED(args->TryGetWebMessageAsString(&raw)) || !raw) return S_OK;
                            std::wstring cmd(raw);
                            CoTaskMemFree(raw);
                            if (cmd == L"ready") {
                                g_filesReady = true;
                                UpdateFileButtons();
                            } else if (cmd == L"open:downloads") {
                                OpenFolder(DownloadsDir());
                            } else if (cmd == L"open:edited") {
                                OpenFolder(EditedDir());
                            }
                            return S_OK;
                        }).Get(), &g_filesMessageToken);

                const std::wstring page = ReadUtf8TextFile(Join(ExeDir(), L"web\\files.html"));
                g_filesReady = false;
                if (!page.empty()) g_filesWebView->NavigateToString(page.c_str());
                else g_filesWebView->NavigateToString(L"<html><body style='background:#020711;color:white'>Biblioteca no disponible</body></html>");
                Layout();
                return S_OK;
            }).Get());
}

void InitWebViews
'@
Replace-One 'void InitWebViews' $webControllers 'CreateShellController'

# Start shell + files controllers once the primary YouTube controller exists.
$createNeedle = 'CreateEditorController(hwnd);'
if (-not $src.Contains($createNeedle)) { throw "WebShell v4 CreateEditorController call missing" }
$src = $src.Replace($createNeedle, 'CreateEditorController(hwnd);' + $nl + '                            CreateShellController(hwnd);' + $nl + '                            CreateFilesController(hwnd);')

# No native chrome controls are created.
$src = $src.Replace('CreateControls(hwnd); RecreateFonts(); UpdateFileButtons(); Layout();', 'RecreateFonts(); UpdateFileButtons(); Layout();')

# Timer only performs backend polling. CSS handles visual animation.
$timerCase = @'
    case WM_TIMER:
        if (wParam == 1) {
            g_hudPhase = (g_hudPhase + 1) % 36;
            if (g_downloadActive && (g_hudPhase % 4) == 0) PollDownloadJob();
            if (!g_downloadActive && g_downloadHoldTicks > 0) {
                --g_downloadHoldTicks;
                if (g_downloadHoldTicks == 0) {
                    g_downloadProgress = -1.0;
                    g_downloadFailed = false;
                    PostShellState();
                }
            }
            if (g_view == ViewMode::Files && (g_hudPhase % 8) == 0) UpdateFileButtons();
            PostShellState();
        }
        return 0;
    case WM_COMMAND:
'@
Replace-One '    case WM_TIMER:.*?    case WM_COMMAND:' $timerCase 'WM_TIMER'

# WM_PAINT is now only a background clear; visible interface is WebView2 HTML.
$paint = @'
    case WM_PAINT: {
        PAINTSTRUCT ps{};
        HDC hdc = BeginPaint(hwnd, &ps);
        RECT rc{}; GetClientRect(hwnd, &rc);
        FillRect(hdc, &rc, g_bgBrush);
        EndPaint(hwnd, &ps);
        return 0;
    }
    case WM_DESTROY:
'@
Replace-One '    case WM_PAINT: \{.*?    case WM_DESTROY:' $paint 'WM_PAINT'

# Close all WebView controllers cleanly.
$src = $src.Replace('if (g_editorController) g_editorController->Close();',
                    'if (g_editorController) g_editorController->Close();' + $nl +
                    '        if (g_shellController) g_shellController->Close();' + $nl +
                    '        if (g_filesController) g_filesController->Close();')
$src = $src.Replace('g_youtubeWebView.Reset(); g_editorWebView.Reset();',
                    'g_youtubeWebView.Reset(); g_editorWebView.Reset(); g_shellWebView.Reset(); g_filesWebView.Reset();')
$src = $src.Replace('g_youtubeController.Reset(); g_editorController.Reset(); g_env.Reset();',
                    'g_youtubeController.Reset(); g_editorController.Reset(); g_shellController.Reset(); g_filesController.Reset(); g_env.Reset();')

# Fullscreen state should immediately update shell visibility.
$src = $src.Replace('g_fullscreen = fs == TRUE; Layout(); return S_OK;', 'g_fullscreen = fs == TRUE; Layout(); PostShellState(); return S_OK;')

# Final source checks.
$checks = @(
    'g_shellController',
    'g_filesController',
    'CreateShellController',
    'CreateFilesController',
    'PostShellState',
    'PostFilesState',
    'web\\shell.html',
    'web\\files.html',
    'ShowNativeControls(false, false, false)'
)
foreach ($check in $checks) {
    if (-not $src.Contains($check)) { throw "WebShell v4 validation failed: $check" }
}

[IO.File]::WriteAllText($cpp, $src, [Text.UTF8Encoding]::new($false))

if (-not (Test-Path (Join-Path $webDir "shell.html"))) { throw "shell.html missing after patch" }
if (-not (Test-Path (Join-Path $webDir "files.html"))) { throw "files.html missing after patch" }

Write-Host "YT Studio CORE WebShell v4 applied"
