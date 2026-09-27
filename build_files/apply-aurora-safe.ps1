param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectRoot
)

$ErrorActionPreference = "Stop"
$cpp = Join-Path $ProjectRoot "src\YTStudioNative.cpp"
if (-not (Test-Path $cpp)) { throw "YTStudioNative.cpp not found: $cpp" }

$src = [IO.File]::ReadAllText($cpp)
$nl = [Environment]::NewLine

if (-not $src.Contains('#pragma comment(lib, "msimg32.lib")')) {
  $src = $src.Replace('#pragma comment(lib, "winhttp.lib")', '#pragma comment(lib, "winhttp.lib")' + $nl + '#pragma comment(lib, "msimg32.lib")')
}

if (-not $src.Contains('HFONT g_fontIcon = nullptr;')) {
  $src = $src.Replace('HFONT g_fontTitle = nullptr;', 'HFONT g_fontTitle = nullptr;' + $nl + 'HFONT g_fontIcon = nullptr;')
}

$src = $src.Replace('const int topH = topVisible ? Ui(g_hwnd, 70) : 0;', 'const int topH = topVisible ? Ui(g_hwnd, 74) : 0;')
$src = $src.Replace('const int navH = navVisible ? Ui(g_hwnd, 50) : 0;', 'const int navH = navVisible ? Ui(g_hwnd, 54) : 0;')
$src = $src.Replace('const int margin = Ui(g_hwnd, 12);', 'const int margin = Ui(g_hwnd, 14);')
$src = $src.Replace('const int gap = Ui(g_hwnd, 7);', 'const int gap = Ui(g_hwnd, 10);')
$src = $src.Replace('const int tabH = Ui(g_hwnd, 38);', 'const int tabH = Ui(g_hwnd, 40);')
$src = $src.Replace('const int navNormalW = Ui(g_hwnd, 88);', 'const int navNormalW = Ui(g_hwnd, 48);')
$src = $src.Replace('const int topH = Ui(hwnd, 70);', 'const int topH = Ui(hwnd, 74);')
$src = $src.Replace('const int navH = g_view == ViewMode::YouTube ? Ui(hwnd, 52) : 0;', 'const int navH = g_view == ViewMode::YouTube ? Ui(hwnd, 54) : 0;')

$src = $src.Replace('g_btnHome = mk(L"INICIO", ID_HOME);', 'g_btnHome = mk(L"\xE80F", ID_HOME);')
$src = $src.Replace('g_btnReload = mk(L"RECARGAR", ID_RELOAD);', 'g_btnReload = mk(L"\xE72C", ID_RELOAD);')
$src = $src.Replace('g_btnHome = mk(L"⌂", ID_HOME);', 'g_btnHome = mk(L"\xE80F", ID_HOME);')
$src = $src.Replace('g_btnReload = mk(L"⟳", ID_RELOAD);', 'g_btnReload = mk(L"\xE72C", ID_RELOAD);')

$src = [regex]::Replace($src, 'g_bgBrush\s*=\s*CreateSolidBrush\(RGB\([^)]+\)\);', 'g_bgBrush = CreateSolidBrush(RGB(2, 7, 13));')
$src = [regex]::Replace($src, 'g_topBrush\s*=\s*CreateSolidBrush\(RGB\([^)]+\)\);', 'g_topBrush = CreateSolidBrush(RGB(4, 15, 25));')
$src = [regex]::Replace($src, 'g_navBrush\s*=\s*CreateSolidBrush\(RGB\([^)]+\)\);', 'g_navBrush = CreateSolidBrush(RGB(3, 11, 20));')

if (-not $src.Contains('void ApplyAuroraWindowStyle()')) {
  $uiPattern = 'int Ui\(HWND hwnd, int px\) \{[\s\S]*?return static_cast<int>\(\(MulDiv\(px, static_cast<int>\(dpi\), 96\) \* res\) \+ 0\.5\);\r?\n\}'
  $m = [regex]::Match($src, $uiPattern)
  if (-not $m.Success) { throw "Ui helper anchor not found" }

  $helpers = @'

void ApplyAuroraWindowStyle() {
    if (!g_hwnd) return;
    const BOOL dark = TRUE;
    const DWORD immersiveDarkMode = 20;
    const DWORD cornerPreference = 33;
    const int roundCorners = 2;
    DwmSetWindowAttribute(g_hwnd, immersiveDarkMode, &dark, sizeof(dark));
    DwmSetWindowAttribute(g_hwnd, cornerPreference, &roundCorners, sizeof(roundCorners));
}

void FillAuroraGradient(HDC hdc, const RECT& r, COLORREF top, COLORREF bottom) {
    TRIVERTEX v[2]{};
    v[0].x = r.left;  v[0].y = r.top;
    v[1].x = r.right; v[1].y = r.bottom;
    v[0].Red = GetRValue(top) << 8;       v[0].Green = GetGValue(top) << 8;       v[0].Blue = GetBValue(top) << 8;       v[0].Alpha = 0x0000;
    v[1].Red = GetRValue(bottom) << 8;    v[1].Green = GetGValue(bottom) << 8;    v[1].Blue = GetBValue(bottom) << 8;    v[1].Alpha = 0x0000;
    GRADIENT_RECT gr{0, 1};
    GradientFill(hdc, v, 2, &gr, 1, GRADIENT_FILL_RECT_V);
}

'@
  $src = $src.Insert($m.Index + $m.Length, $helpers)
}

$fontPattern = 'void RecreateFonts\(\) \{[\s\S]*?\r?\n\}\r?\n\r?\nvoid ShowNativeControls'
$fontReplacement = @'
void RecreateFonts() {
    if (g_font) { DeleteObject(g_font); g_font = nullptr; }
    if (g_fontTitle) { DeleteObject(g_fontTitle); g_fontTitle = nullptr; }
    if (g_fontIcon) { DeleteObject(g_fontIcon); g_fontIcon = nullptr; }

    g_font = CreateFontW(-Ui(g_hwnd, 14), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Text");
    g_fontTitle = CreateFontW(-Ui(g_hwnd, 17), 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI Variable Display");
    g_fontIcon = CreateFontW(-Ui(g_hwnd, 19), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_DONTCARE, L"Segoe MDL2 Assets");

    for (HWND h : { g_btnBack,g_btnForward,g_btnDownload,g_tabYouTube,g_tabEditor,g_tabFiles,g_btnOpenDownloads,g_btnOpenEdited }) {
        if (h) SendMessageW(h, WM_SETFONT, reinterpret_cast<WPARAM>(g_font), TRUE);
    }
    for (HWND h : { g_btnHome,g_btnReload }) {
        if (h) SendMessageW(h, WM_SETFONT, reinterpret_cast<WPARAM>(g_fontIcon), TRUE);
    }
}

void ShowNativeControls
'@
if (-not [regex]::IsMatch($src, $fontPattern)) { throw "RecreateFonts block not found" }
$src = [regex]::Replace($src, $fontPattern, $fontReplacement, 1)

$chipPattern = 'void DrawHudChip\(HDC hdc, RECT r, const wchar_t\* text, COLORREF border, COLORREF fg\) \{[\s\S]*?\r?\n\}\r?\n\r?\nvoid DrawCoreOrb'
$chipReplacement = @'
void DrawHudChip(HDC hdc, RECT r, const wchar_t* text, COLORREF border, COLORREF fg) {
    const int radius = Ui(g_hwnd, 16);
    HRGN clip = CreateRoundRectRgn(r.left, r.top, r.right + 1, r.bottom + 1, radius, radius);
    int saved = SaveDC(hdc);
    SelectClipRgn(hdc, clip);
    FillAuroraGradient(hdc, r, RGB(8, 31, 45), RGB(4, 15, 28));
    RestoreDC(hdc, saved);
    DeleteObject(clip);

    HPEN outer = CreatePen(PS_SOLID, 1, border);
    HPEN inner = CreatePen(PS_SOLID, 1, RGB(78, 72, 135));
    HGDIOBJ oldP = SelectObject(hdc, outer);
    HGDIOBJ oldB = SelectObject(hdc, GetStockObject(NULL_BRUSH));
    RoundRect(hdc, r.left, r.top, r.right, r.bottom, radius, radius);

    RECT in = r; InflateRect(&in, -2, -2);
    SelectObject(hdc, inner);
    RoundRect(hdc, in.left, in.top, in.right, in.bottom, radius - 3, radius - 3);

    HPEN shine = CreatePen(PS_SOLID, 1, RGB(124, 226, 255));
    SelectObject(hdc, shine);
    MoveToEx(hdc, r.left + Ui(g_hwnd, 12), r.top + Ui(g_hwnd, 3), nullptr);
    LineTo(hdc, r.right - Ui(g_hwnd, 12), r.top + Ui(g_hwnd, 3));

    SelectObject(hdc, oldP); SelectObject(hdc, oldB);
    DeleteObject(outer); DeleteObject(inner); DeleteObject(shine);

    SetBkMode(hdc, TRANSPARENT);
    SetTextColor(hdc, fg);
    if (g_font) SelectObject(hdc, g_font);
    DrawTextW(hdc, text, -1, &r, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
}

void DrawCoreOrb
'@
if (-not [regex]::IsMatch($src, $chipPattern)) { throw "DrawHudChip block not found" }
$src = [regex]::Replace($src, $chipPattern, $chipReplacement, 1)

$buttonPattern = 'void DrawOwnerButton\(const DRAWITEMSTRUCT\* dis\) \{[\s\S]*?\r?\n\}\r?\n\r?\nvoid CreateControls'
$buttonReplacement = @'
void DrawOwnerButton(const DRAWITEMSTRUCT* dis) {
    if (!dis) return;

    HDC hdc = dis->hDC;
    RECT r = dis->rcItem;
    const int id = GetDlgCtrlID(dis->hwndItem);
    const bool disabled = (dis->itemState & ODS_DISABLED) != 0;
    const bool pressed = (dis->itemState & ODS_SELECTED) != 0;
    const bool focused = (dis->itemState & ODS_FOCUS) != 0;
    const bool active = IsActiveButton(id);
    const bool accent = id == ID_DOWNLOAD;
    const bool folder = id == ID_OPEN_DOWNLOADS || id == ID_OPEN_EDITED;
    const bool icon = id == ID_HOME || id == ID_RELOAD;

    COLORREF top = RGB(10, 33, 48);
    COLORREF bottom = RGB(4, 14, 27);
    COLORREF border = RGB(31, 126, 162);
    COLORREF glow = RGB(74, 77, 142);
    COLORREF text = RGB(218, 244, 255);

    if (active) {
        top = RGB(10, 62, 79); bottom = RGB(5, 27, 43);
        border = RGB(44, 225, 255); glow = RGB(124, 91, 255);
    }
    if (accent) {
        top = RGB(50, 42, 112); bottom = RGB(24, 18, 67);
        border = RGB(138, 97, 255); glow = RGB(45, 215, 255);
    }
    if (folder) {
        top = RGB(8, 45, 60); bottom = RGB(4, 20, 33);
        border = RGB(45, 192, 225);
    }
    if (pressed) {
        top = RGB(17, 76, 94); bottom = RGB(6, 34, 50);
    }
    if (disabled) {
        top = RGB(12, 20, 29); bottom = RGB(6, 11, 19);
        border = RGB(48, 67, 79); glow = RGB(38, 43, 59); text = RGB(91, 112, 123);
    }

    const int radius = Ui(g_hwnd, 16);
    HRGN clip = CreateRoundRectRgn(r.left, r.top, r.right + 1, r.bottom + 1, radius, radius);
    int saved = SaveDC(hdc);
    SelectClipRgn(hdc, clip);
    FillAuroraGradient(hdc, r, top, bottom);
    RestoreDC(hdc, saved);
    DeleteObject(clip);

    HPEN outer = CreatePen(PS_SOLID, Ui(g_hwnd, active || focused ? 2 : 1), border);
    HPEN inner = CreatePen(PS_SOLID, 1, glow);
    HGDIOBJ oldP = SelectObject(hdc, outer);
    HGDIOBJ oldB = SelectObject(hdc, GetStockObject(NULL_BRUSH));
    RoundRect(hdc, r.left, r.top, r.right, r.bottom, radius, radius);

    RECT in = r; InflateRect(&in, -2, -2);
    SelectObject(hdc, inner);
    RoundRect(hdc, in.left, in.top, in.right, in.bottom, radius - 3, radius - 3);

    HPEN shine = CreatePen(PS_SOLID, 1, disabled ? RGB(45, 57, 66) : RGB(118, 226, 255));
    SelectObject(hdc, shine);
    MoveToEx(hdc, r.left + Ui(g_hwnd, 10), r.top + Ui(g_hwnd, 3), nullptr);
    LineTo(hdc, r.right - Ui(g_hwnd, 10), r.top + Ui(g_hwnd, 3));

    SelectObject(hdc, oldP); SelectObject(hdc, oldB);
    DeleteObject(outer); DeleteObject(inner); DeleteObject(shine);

    wchar_t txt[128]{};
    GetWindowTextW(dis->hwndItem, txt, 127);
    SetBkMode(hdc, TRANSPARENT);
    SetTextColor(hdc, text);
    if (icon && g_fontIcon) SelectObject(hdc, g_fontIcon);
    else if (g_font) SelectObject(hdc, g_font);
    DrawTextW(hdc, txt, -1, &r, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);

    if (active) {
        HPEN ap = CreatePen(PS_SOLID, Ui(g_hwnd, 2), RGB(44, 229, 255));
        HGDIOBJ op = SelectObject(hdc, ap);
        MoveToEx(hdc, r.left + Ui(g_hwnd, 14), r.bottom - Ui(g_hwnd, 4), nullptr);
        LineTo(hdc, r.right - Ui(g_hwnd, 14), r.bottom - Ui(g_hwnd, 4));
        SelectObject(hdc, op);
        DeleteObject(ap);
    }
}

void CreateControls
'@
if (-not [regex]::IsMatch($src, $buttonPattern)) { throw "DrawOwnerButton block not found" }
$src = [regex]::Replace($src, $buttonPattern, $buttonReplacement, 1)

$src = [regex]::Replace($src, '\r?\nvoid EnableAuroraBackdropSafe\(\) \{[\s\S]*?\r?\n\}\r?\n\r?\nvoid RoundAuroraControl\(HWND hwnd\) \{[\s\S]*?\r?\n\}\r?\n', $nl)
$src = $src.Replace('; RoundAuroraControl(g_tabYouTube)', '')
$src = $src.Replace('; RoundAuroraControl(g_tabEditor)', '')
$src = $src.Replace('; RoundAuroraControl(g_tabFiles)', '')
$src = $src.Replace('; RoundAuroraControl(g_btnBack)', '')
$src = $src.Replace('; RoundAuroraControl(g_btnForward)', '')
$src = $src.Replace('; RoundAuroraControl(g_btnHome)', '')
$src = $src.Replace('; RoundAuroraControl(g_btnReload)', '')
$src = $src.Replace('; RoundAuroraControl(g_btnDownload)', '')
$src = $src.Replace('; RoundAuroraControl(g_btnOpenDownloads)', '')
$src = $src.Replace('; RoundAuroraControl(g_btnOpenEdited)', '')

$paintOld = 'RECT top{ 0,0,rc.right,topH }; FillRect(hdc, &top, g_topBrush);' + $nl + '            if (navH) { RECT nav{ 0,topH,rc.right,topH + navH }; FillRect(hdc, &nav, g_navBrush); }'
$paintNew = 'RECT top{ 0,0,rc.right,topH }; FillAuroraGradient(hdc, top, RGB(6, 24, 38), RGB(3, 12, 23));' + $nl + '            if (navH) { RECT nav{ 0,topH,rc.right,topH + navH }; FillAuroraGradient(hdc, nav, RGB(5, 18, 31), RGB(2, 9, 17)); }'
if (-not $src.Contains($paintOld)) { throw "Paint gradient anchor not found" }
$src = $src.Replace($paintOld, $paintNew)

$src = $src.Replace('g_hudTimer = SetTimer(hwnd, 1, 120, nullptr);', 'g_hudTimer = SetTimer(hwnd, 1, 240, nullptr);')
$timerOld = 'RECT top{}; GetClientRect(hwnd, &top); top.bottom = Ui(hwnd, 122);' + $nl + '            InvalidateRect(hwnd, &top, FALSE);'
$timerNew = 'RECT orb{ 0, 0, Ui(hwnd, 62), Ui(hwnd, 74) };' + $nl + '            InvalidateRect(hwnd, &orb, FALSE);'
if (-not $src.Contains($timerOld)) { throw "Timer invalidation anchor not found" }
$src = $src.Replace($timerOld, $timerNew)

$createAnchor = 'g_navBrush = CreateSolidBrush(RGB(3, 11, 20));'
if (-not $src.Contains($createAnchor)) { throw "WM_CREATE brush anchor not found" }
$src = $src.Replace($createAnchor, $createAnchor + $nl + '        ApplyAuroraWindowStyle();')

$destroyOld = 'if (g_font) DeleteObject(g_font); if (g_fontTitle) DeleteObject(g_fontTitle);'
$destroyNew = 'if (g_font) DeleteObject(g_font); if (g_fontTitle) DeleteObject(g_fontTitle); if (g_fontIcon) DeleteObject(g_fontIcon);'
if ($src.Contains($destroyOld)) { $src = $src.Replace($destroyOld, $destroyNew) }

$checks = @(
  'L"\xE80F"',
  'L"\xE72C"',
  'Segoe MDL2 Assets',
  'FillAuroraGradient',
  'void DrawOwnerButton',
  'Ui(hwnd, 74)',
  'Ui(hwnd, 54)',
  'SetTimer(hwnd, 1, 240'
)
foreach ($check in $checks) {
  if (-not $src.Contains($check)) { throw "Final UI validation failed: $check" }
}

[IO.File]::WriteAllText($cpp, $src, [Text.UTF8Encoding]::new($false))
Write-Host "Aurora Crystal Dark UI v2 applied successfully"
