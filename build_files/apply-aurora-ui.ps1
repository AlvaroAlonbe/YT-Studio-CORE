param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectRoot
)

$ErrorActionPreference = "Stop"
$nl = [Environment]::NewLine
$cpp = Join-Path $ProjectRoot "src\YTStudioNative.cpp"
if (-not (Test-Path $cpp)) { throw "YTStudioNative.cpp not found at $cpp" }

$src = [IO.File]::ReadAllText($cpp)

function Require-Contains([string]$needle, [string]$label) {
  if (-not $src.Contains($needle)) { throw "UI patch anchor not found: $label" }
}

if (-not $src.Contains("#include <commctrl.h>")) {
  $src = $src.Replace("#include <windowsx.h>", "#include <windowsx.h>" + $nl + "#include <commctrl.h>")
}
if (-not $src.Contains('#pragma comment(lib, "comctl32.lib")')) {
  $src = $src.Replace('#pragma comment(lib, "winhttp.lib")', '#pragma comment(lib, "winhttp.lib")' + $nl + '#pragma comment(lib, "comctl32.lib")')
}

$src = $src.Replace('L"INICIO"', 'L"\xE80F"')
$src = $src.Replace('L"RECARGAR"', 'L"\xE72C"')

$src = [regex]::Replace($src, 'g_bgBrush\s*=\s*CreateSolidBrush\(RGB\([^)]+\)\);', 'g_bgBrush = CreateSolidBrush(RGB(3, 9, 16));')
$src = [regex]::Replace($src, 'g_topBrush\s*=\s*CreateSolidBrush\(RGB\([^)]+\)\);', 'g_topBrush = CreateSolidBrush(RGB(5, 17, 28));')
$src = [regex]::Replace($src, 'g_navBrush\s*=\s*CreateSolidBrush\(RGB\([^)]+\)\);', 'g_navBrush = CreateSolidBrush(RGB(4, 13, 23));')

$anchor = 'std::vector<std::wstring> g_recentEdited;'
Require-Contains $anchor "global UI state"

if (-not $src.Contains("LRESULT CALLBACK AuroraButtonProc")) {
$aurora = @'

void EnableAuroraBackdrop() {
    if (!g_hwnd) return;
    const BOOL dark = TRUE;
    const DWORD immersiveDarkMode = 20;
    const DWORD cornerPreference = 33;
    const DWORD systemBackdropType = 38;
    const int roundCorners = 2;
    const int micaBackdrop = 2;
    DwmSetWindowAttribute(g_hwnd, immersiveDarkMode, &dark, sizeof(dark));
    DwmSetWindowAttribute(g_hwnd, cornerPreference, &roundCorners, sizeof(roundCorners));
    DwmSetWindowAttribute(g_hwnd, systemBackdropType, &micaBackdrop, sizeof(micaBackdrop));
}

LRESULT CALLBACK AuroraButtonProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam,
                                  UINT_PTR, DWORD_PTR) {
    switch (msg) {
    case WM_MOUSEMOVE: {
        if (!GetPropW(hwnd, L"YT_AURORA_HOT")) {
            SetPropW(hwnd, L"YT_AURORA_HOT", reinterpret_cast<HANDLE>(1));
            TRACKMOUSEEVENT tme{ sizeof(tme), TME_LEAVE, hwnd, 0 };
            TrackMouseEvent(&tme);
            InvalidateRect(hwnd, nullptr, FALSE);
        }
        break;
    }
    case WM_MOUSELEAVE:
        RemovePropW(hwnd, L"YT_AURORA_HOT");
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
    case WM_LBUTTONDOWN:
    case WM_LBUTTONUP:
        InvalidateRect(hwnd, nullptr, FALSE);
        break;
    case WM_ERASEBKGND:
        return 1;
    case WM_PAINT: {
        PAINTSTRUCT ps{};
        HDC dc = BeginPaint(hwnd, &ps);
        RECT rc{}; GetClientRect(hwnd, &rc);

        const bool enabled = IsWindowEnabled(hwnd) != FALSE;
        const bool hot = GetPropW(hwnd, L"YT_AURORA_HOT") != nullptr;
        const bool down = (GetKeyState(VK_LBUTTON) & 0x8000) && hot;
        const int radius = Ui(hwnd, 12);

        HBRUSH fill = CreateSolidBrush(
            !enabled ? RGB(13, 20, 30) :
            down ? RGB(17, 40, 58) :
            hot ? RGB(11, 34, 50) : RGB(7, 24, 37));
        HPEN edge = CreatePen(PS_SOLID, Ui(hwnd, hot ? 2 : 1),
            !enabled ? RGB(55, 70, 82) :
            hot ? RGB(73, 224, 255) : RGB(43, 143, 177));

        HGDIOBJ oldBrush = SelectObject(dc, fill);
        HGDIOBJ oldPen = SelectObject(dc, edge);
        RoundRect(dc, rc.left, rc.top, rc.right, rc.bottom, radius, radius);

        RECT inner = rc;
        InflateRect(&inner, -Ui(hwnd, 2), -Ui(hwnd, 2));
        HPEN innerPen = CreatePen(PS_SOLID, 1,
            hot ? RGB(125, 98, 255) : RGB(45, 74, 112));
        SelectObject(dc, GetStockObject(NULL_BRUSH));
        SelectObject(dc, innerPen);
        RoundRect(dc, inner.left, inner.top, inner.right, inner.bottom,
                  (std::max)(Ui(hwnd, 8), radius - Ui(hwnd, 3)),
                  (std::max)(Ui(hwnd, 8), radius - Ui(hwnd, 3)));

        wchar_t text[128]{};
        GetWindowTextW(hwnd, text, static_cast<int>(_countof(text)));
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, !enabled ? RGB(95, 111, 126) :
                     hot ? RGB(230, 250, 255) : RGB(205, 236, 246));

        HFONT iconFont = nullptr;
        HGDIOBJ oldFont = nullptr;
        if (hwnd == g_btnHome || hwnd == g_btnReload) {
            iconFont = CreateFontW(-Ui(hwnd, 20), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                DEFAULT_PITCH | FF_DONTCARE, L"Segoe MDL2 Assets");
            oldFont = SelectObject(dc, iconFont);
        } else if (g_font) {
            oldFont = SelectObject(dc, g_font);
        }

        DrawTextW(dc, text, -1, &rc, DT_SINGLELINE | DT_CENTER | DT_VCENTER | DT_NOPREFIX);

        if (oldFont) SelectObject(dc, oldFont);
        if (iconFont) DeleteObject(iconFont);
        SelectObject(dc, oldBrush);
        SelectObject(dc, oldPen);
        DeleteObject(innerPen);
        DeleteObject(edge);
        DeleteObject(fill);
        EndPaint(hwnd, &ps);
        return 0;
    }
    }
    return DefSubclassProc(hwnd, msg, wParam, lParam);
}

void ApplyAuroraButton(HWND hwnd) {
    if (!hwnd) return;
    SetWindowSubclass(hwnd, AuroraButtonProc, 0xA041, 0);
    RECT rc{}; GetClientRect(hwnd, &rc);
    const int r = Ui(hwnd, 12);
    HRGN region = CreateRoundRectRgn(0, 0, rc.right + 1, rc.bottom + 1, r, r);
    SetWindowRgn(hwnd, region, TRUE);
}

'@
  $src = $src.Replace($anchor, $anchor + $aurora)
}

$src = $src.Replace('const int topH = topVisible ? Ui(g_hwnd, 70) : 0;', 'const int topH = topVisible ? Ui(g_hwnd, 74) : 0;')
$src = $src.Replace('const int navH = navVisible ? Ui(g_hwnd, 50) : 0;', 'const int navH = navVisible ? Ui(g_hwnd, 54) : 0;')
$src = $src.Replace('const int margin = Ui(g_hwnd, 12);', 'const int margin = Ui(g_hwnd, 14);')
$src = $src.Replace('const int gap = Ui(g_hwnd, 7);', 'const int gap = Ui(g_hwnd, 9);')
$src = $src.Replace('const int tabH = Ui(g_hwnd, 38);', 'const int tabH = Ui(g_hwnd, 40);')
$src = $src.Replace('const int navNormalW = Ui(g_hwnd, 88);', 'const int navNormalW = Ui(g_hwnd, 48);')

$layoutAnchor = 'void Layout() {' + $nl + '    if (!g_hwnd) return;'
$layoutPatched = $layoutAnchor + $nl + '    EnableAuroraBackdrop();'
if ($src.Contains($layoutAnchor) -and -not $src.Contains($layoutPatched)) {
  $src = $src.Replace($layoutAnchor, $layoutPatched)
}

$handles = @(
  'g_tabYouTube','g_tabEditor','g_tabFiles',
  'g_btnBack','g_btnForward','g_btnHome','g_btnReload','g_btnDownload',
  'g_btnOpenDownloads','g_btnOpenEdited'
)
foreach ($h in $handles) {
  $pattern = 'MoveWindow\(' + [regex]::Escape($h) + ',([^;]+)\);'
  $src = [regex]::Replace($src, $pattern, {
      param($m)
      if ($m.Value.Contains('ApplyAuroraButton')) { return $m.Value }
      return $m.Value + ' ApplyAuroraButton(' + $h + ');'
  })
}

if (-not $src.Contains("LRESULT CALLBACK AuroraButtonProc")) { throw "Aurora renderer injection failed" }
if (-not $src.Contains("ApplyAuroraButton(g_btnHome)")) { throw "Home button rounding patch failed" }
if (-not $src.Contains('L"\xE80F"')) { throw "Home icon patch failed" }
if (-not $src.Contains('L"\xE72C"')) { throw "Reload icon patch failed" }

[IO.File]::WriteAllText($cpp, $src, [Text.UTF8Encoding]::new($false))
Write-Host "Aurora glass UI patch applied to $cpp"
