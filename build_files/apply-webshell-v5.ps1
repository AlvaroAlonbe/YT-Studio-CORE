param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectRoot
)

$ErrorActionPreference = "Stop"
$cpp = Join-Path $ProjectRoot "src\YTStudioNative.cpp"
$rc  = Join-Path $ProjectRoot "src\app.rc"
if (-not (Test-Path $cpp)) { throw "Missing source: $cpp" }
if (-not (Test-Path (Join-Path $ProjectRoot "src\app.ico"))) { throw "Missing generated app.ico" }

$src = [IO.File]::ReadAllText($cpp)
$nl = [Environment]::NewLine

$rcText = @'
#include <windows.h>
101 ICON "src\\app.ico"
'@
[IO.File]::WriteAllText($rc,$rcText,[Text.UTF8Encoding]::new($false))

if (-not $src.Contains('EventRegistrationToken g_adBlockToken{};')) {
    $anchor = 'EventRegistrationToken g_filesMessageToken{};'
    if (-not $src.Contains($anchor)) { throw "AdBlock token anchor missing" }
    $src = $src.Replace($anchor, $anchor + $nl + 'EventRegistrationToken g_adBlockToken{};' + $nl + 'bool g_adBlockInstalled = false;')
}
if (-not $src.Contains('void InstallAdBlocker();')) {
    $anchor = 'void PostFilesState();'
    if (-not $src.Contains($anchor)) { throw "AdBlock forward anchor missing" }
    $src = $src.Replace($anchor, $anchor + $nl + 'void InstallAdBlocker();')
}

if (-not $src.Contains('bool ShouldBlockAdRequest(')) {
$impl = @'
bool ShouldBlockAdRequest(const std::wstring& uri) {
    static const wchar_t* blocked[] = {
        L"doubleclick.net",
        L"googlesyndication.com",
        L"googleadservices.com",
        L"adservice.google.com",
        L"adservice.google.",
        L"pagead2.googlesyndication.com",
        L"tpc.googlesyndication.com",
        L"securepubads.g.doubleclick.net",
        L"static.doubleclick.net",
        L"partner.googleadservices.com",
        L"youtube.com/pagead/",
        L"youtube.com/ptracking",
        L"youtube.com/api/stats/ads",
        L"youtube.com/get_midroll_info",
        L"youtube.com/youtubei/v1/player/ad_break"
    };
    for (const wchar_t* item : blocked) {
        if (uri.find(item) != std::wstring::npos) return true;
    }
    return false;
}

void InstallAdBlocker() {
    if (g_adBlockInstalled || !g_youtubeWebView || !g_env) return;
    g_adBlockInstalled = true;

    g_youtubeWebView->AddWebResourceRequestedFilter(
        L"*", COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);

    g_youtubeWebView->add_WebResourceRequested(
        Callback<ICoreWebView2WebResourceRequestedEventHandler>(
            [](ICoreWebView2*, ICoreWebView2WebResourceRequestedEventArgs* args) -> HRESULT {
                if (!args) return S_OK;
                ComPtr<ICoreWebView2WebResourceRequest> request;
                if (FAILED(args->get_Request(request.GetAddressOf())) || !request) return S_OK;

                LPWSTR raw = nullptr;
                if (FAILED(request->get_Uri(&raw)) || !raw) return S_OK;
                std::wstring uri(raw);
                CoTaskMemFree(raw);

                if (!ShouldBlockAdRequest(uri)) return S_OK;

                ComPtr<ICoreWebView2WebResourceResponse> response;
                if (SUCCEEDED(g_env->CreateWebResourceResponse(
                        nullptr, 204, L"No Content",
                        L"Content-Type: text/plain\r\nCache-Control: no-store",
                        response.GetAddressOf())) && response) {
                    args->put_Response(response.Get());
                }
                return S_OK;
            }).Get(), &g_adBlockToken);

    const wchar_t* adScript = LR"JS(
(() => {
  if (window.__YTSC_ADBLOCK__) return;
  window.__YTSC_ADBLOCK__ = true;

  const style = document.createElement('style');
  style.id = 'ytsc-adblock-style';
  style.textContent = 'ytd-ad-slot-renderer,ytd-in-feed-ad-layout-renderer,ytd-display-ad-renderer,ytd-promoted-sparkles-web-renderer,ytd-promoted-video-renderer,ytd-action-companion-ad-renderer,ytd-banner-promo-renderer,ytd-statement-banner-renderer,ytd-brand-video-shelf-renderer,#masthead-ad,#player-ads,.video-ads,.ytp-ad-module,.ytp-ad-overlay-container,.ytp-ad-player-overlay,.ytp-ad-text-overlay,.ytd-player-legacy-desktop-watch-ads-renderer,tp-yt-paper-dialog ytd-mealbar-promo-renderer{display:none!important;visibility:hidden!important;min-height:0!important;height:0!important}';
  (document.documentElement || document.head).appendChild(style);

  const clean = () => {
    document.querySelectorAll('ytd-ad-slot-renderer,ytd-in-feed-ad-layout-renderer,ytd-display-ad-renderer,ytd-promoted-sparkles-web-renderer,ytd-promoted-video-renderer,#masthead-ad,#player-ads').forEach(el => el.remove());

    document.querySelectorAll('.ytp-ad-skip-button,.ytp-skip-ad-button,.ytp-ad-skip-button-modern,button.ytp-ad-skip-button-modern,[id^="skip-button"] button').forEach(btn => { try { btn.click(); } catch(e) {} });

    const player = document.querySelector('.html5-video-player');
    const video = document.querySelector('video');
    if (player && player.classList.contains('ad-showing') && video) {
      try {
        video.muted = true;
        video.playbackRate = 16;
        if (Number.isFinite(video.duration) && video.duration > 0.5) {
          video.currentTime = Math.max(0, video.duration - 0.15);
        }
      } catch(e) {}
    }
  };

  const observer = new MutationObserver(clean);
  const start = () => {
    clean();
    observer.observe(document.documentElement, {
      childList:true, subtree:true, attributes:true, attributeFilter:['class']
    });
    setInterval(clean, 650);
  };
  if (document.documentElement) start();
  else addEventListener('DOMContentLoaded', start, {once:true});
})();
)JS";

    g_youtubeWebView->AddScriptToExecuteOnDocumentCreated(
        adScript,
        Callback<ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler>(
            [](HRESULT, LPCWSTR) -> HRESULT { return S_OK; }).Get());
    g_youtubeWebView->ExecuteScript(adScript, nullptr);
}

'@
    $anchor = 'void CreateShellController(HWND hwnd) {'
    if (-not $src.Contains($anchor)) { throw "AdBlock implementation anchor missing" }
    $src = $src.Replace($anchor, $impl + $anchor)
}

if (-not $src.Contains('InstallAdBlocker(); // YTSC_V5')) {
    $oldNav = @'
void UpdateNavState() {
    PostShellState();
}
'@
    $newNav = @'
void UpdateNavState() {
    InstallAdBlocker(); // YTSC_V5
    PostShellState();
}
'@
    if (-not $src.Contains($oldNav)) { throw "YouTube nav adblock hook anchor missing" }
    $src = $src.Replace($oldNav,$newNav)
}

if (-not $src.Contains('YTSC_ICON_V5')) {
    $anchor = 'case WM_CREATE:'
    if (-not $src.Contains($anchor)) { throw "WM_CREATE icon anchor missing" }
    $iconCode = @'
case WM_CREATE:
        {
            HINSTANCE mod = GetModuleHandleW(nullptr);
            HICON appBig = reinterpret_cast<HICON>(LoadImageW(
                mod, MAKEINTRESOURCEW(101) /* YTSC_ICON_V5 */, IMAGE_ICON, 0, 0, LR_DEFAULTSIZE));
            HICON appSmall = reinterpret_cast<HICON>(LoadImageW(
                mod, MAKEINTRESOURCEW(101), IMAGE_ICON, 20, 20, 0));
            if (appBig) SendMessageW(hwnd, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(appBig));
            if (appSmall) SendMessageW(hwnd, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(appSmall));
        }
'@
    $src = $src.Replace($anchor,$iconCode)
}

$checks = @(
  'ShouldBlockAdRequest',
  'InstallAdBlocker(); // YTSC_V5',
  'AddWebResourceRequestedFilter',
  'AddScriptToExecuteOnDocumentCreated',
  'YTSC_ICON_V5',
  'g_adBlockToken',
  'g_adBlockInstalled'
)
foreach ($check in $checks) {
    if (-not $src.Contains($check)) { throw "WebShell v5 validation failed: $check" }
}

[IO.File]::WriteAllText($cpp,$src,[Text.UTF8Encoding]::new($false))
Write-Host "YT Studio CORE v5: animated shell, icon and ad blocker applied"
