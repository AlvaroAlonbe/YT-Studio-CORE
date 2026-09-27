param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectRoot
)

$ErrorActionPreference = "Stop"
$cpp = Join-Path $ProjectRoot "src\YTStudioNative.cpp"
$html = Join-Path $ProjectRoot "web\editor.html"
if (-not (Test-Path $cpp)) { throw "Missing $cpp" }
if (-not (Test-Path $html)) { throw "Missing $html" }

$src = [IO.File]::ReadAllText($cpp)
$nl = [Environment]::NewLine

function Replace-One([string]$pattern,[string]$replacement,[string]$label) {
  $rx = [regex]::new($pattern,[Text.RegularExpressions.RegexOptions]::Singleline)
  $m = $rx.Match($script:src)
  if (-not $m.Success) { throw "V3 patch anchor missing: $label" }
  $script:src = $rx.Replace($script:src,$replacement,1)
}

# Larger spacing and clearer rounded cards.
$src = $src.Replace('const int topH = topVisible ? Ui(g_hwnd, 74) : 0;', 'const int topH = topVisible ? Ui(g_hwnd, 80) : 0;')
$src = $src.Replace('const int navH = navVisible ? Ui(g_hwnd, 54) : 0;', 'const int navH = navVisible ? Ui(g_hwnd, 60) : 0;')
$src = $src.Replace('const int margin = Ui(g_hwnd, 14);', 'const int margin = Ui(g_hwnd, 16);')
$src = $src.Replace('const int gap = Ui(g_hwnd, 10);', 'const int gap = Ui(g_hwnd, 12);')
$src = $src.Replace('const int tabH = Ui(g_hwnd, 40);', 'const int tabH = Ui(g_hwnd, 46);')
$src = $src.Replace('const int tabW = Ui(g_hwnd, MonitorLogicalWidth(g_hwnd) <= 1400 ? 96 : 110);', 'const int tabW = Ui(g_hwnd, MonitorLogicalWidth(g_hwnd) <= 1400 ? 106 : 132);')
$src = $src.Replace('int tabX = Ui(g_hwnd, MonitorLogicalWidth(g_hwnd) <= 1400 ? 265 : 300);', 'int tabX = Ui(g_hwnd, MonitorLogicalWidth(g_hwnd) <= 1400 ? 248 : 300);')
$src = $src.Replace('const int navSmallW = Ui(g_hwnd, 48);', 'const int navSmallW = Ui(g_hwnd, 52);')
$src = $src.Replace('const int navNormalW = Ui(g_hwnd, 48);', 'const int navNormalW = Ui(g_hwnd, 52);')
$src = $src.Replace('const int topH = Ui(hwnd, 74);', 'const int topH = Ui(hwnd, 80);')
$src = $src.Replace('const int navH = g_view == ViewMode::YouTube ? Ui(hwnd, 54) : 0;', 'const int navH = g_view == ViewMode::YouTube ? Ui(hwnd, 60) : 0;')
$src = $src.Replace('RECT orb{ 0, 0, Ui(hwnd, 62), Ui(hwnd, 74) };', 'RECT orb{ 0, 0, Ui(hwnd, 72), Ui(hwnd, 80) };')

$src = $src.Replace('g_font = CreateFontW(-Ui(g_hwnd, 14)', 'g_font = CreateFontW(-Ui(g_hwnd, 15)')
$src = $src.Replace('g_fontTitle = CreateFontW(-Ui(g_hwnd, 17)', 'g_fontTitle = CreateFontW(-Ui(g_hwnd, 18)')
$src = $src.Replace('g_fontIcon = CreateFontW(-Ui(g_hwnd, 19)', 'g_fontIcon = CreateFontW(-Ui(g_hwnd, 21)')

# True rounded child window regions: no square corners around owner-draw buttons.
$regionAnchor = 'void ShowNativeControls(bool showTop, bool showNav, bool showFiles) {'
if (-not $src.Contains('void SetRoundedControlRegion(HWND hwnd)')) {
$regionHelper = @'
void SetRoundedControlRegion(HWND hwnd) {
    if (!hwnd) return;
    RECT rc{}; GetClientRect(hwnd, &rc);
    const int radius = Ui(hwnd, 15);
    HRGN rgn = CreateRoundRectRgn(0, 0, rc.right + 1, rc.bottom + 1, radius, radius);
    if (rgn) SetWindowRgn(hwnd, rgn, TRUE);
}

'@
  if (-not $src.Contains($regionAnchor)) { throw "V3 region insertion anchor missing" }
  $src = $src.Replace($regionAnchor, $regionHelper + $regionAnchor)
}

# Add region after every relevant MoveWindow.
$handles = @(
  'g_tabYouTube','g_tabEditor','g_tabFiles','g_btnBack','g_btnForward',
  'g_btnHome','g_btnReload','g_btnDownload','g_btnOpenDownloads','g_btnOpenEdited'
)
foreach ($h in $handles) {
  $pattern = 'MoveWindow\(' + [regex]::Escape($h) + ',([^;]+)\);'
  $src = [regex]::Replace($src, $pattern, {
    param($m)
    if ($m.Value.Contains('SetRoundedControlRegion')) { return $m.Value }
    return $m.Value + ' SetRoundedControlRegion(' + $h + ');'
  })
}

# Crystal HUD card.
$hud = @'
void DrawHudChip(HDC hdc, RECT r, const wchar_t* text, COLORREF border, COLORREF fg) {
    const int radius = Ui(g_hwnd, 14);
    RECT box = r; InflateRect(&box, -Ui(g_hwnd, 2), -Ui(g_hwnd, 2));

    HDC mem = CreateCompatibleDC(hdc);
    HBITMAP bmp = CreateCompatibleBitmap(hdc, box.right - box.left, box.bottom - box.top);
    HGDIOBJ oldBmp = SelectObject(mem, bmp);
    RECT local{0,0,box.right-box.left,box.bottom-box.top};

    HBRUSH base = CreateSolidBrush(RGB(4, 13, 24));
    FillRect(mem, &local, base); DeleteObject(base);
    FillAuroraGradient(mem, local, RGB(9, 34, 48), RGB(4, 14, 28));

    HPEN outer = CreatePen(PS_SOLID, 1, border);
    HPEN inner = CreatePen(PS_SOLID, 1, RGB(70, 75, 132));
    HGDIOBJ oldP = SelectObject(mem, outer);
    HGDIOBJ oldB = SelectObject(mem, GetStockObject(NULL_BRUSH));
    RoundRect(mem, 0, 0, local.right-1, local.bottom-1, radius, radius);
    RECT in = local; InflateRect(&in, -2, -2);
    SelectObject(mem, inner);
    RoundRect(mem, in.left, in.top, in.right-1, in.bottom-1, radius-3, radius-3);

    HPEN shine = CreatePen(PS_SOLID, 1, RGB(95, 224, 255));
    SelectObject(mem, shine);
    MoveToEx(mem, Ui(g_hwnd, 12), Ui(g_hwnd, 2), nullptr);
    LineTo(mem, local.right - Ui(g_hwnd, 12), Ui(g_hwnd, 2));

    SelectObject(mem, oldP); SelectObject(mem, oldB);
    DeleteObject(outer); DeleteObject(inner); DeleteObject(shine);

    SetBkMode(mem, TRANSPARENT);
    SetTextColor(mem, fg);
    if (g_font) SelectObject(mem, g_font);
    DrawTextW(mem, text, -1, &local, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);

    BitBlt(hdc, box.left, box.top, local.right, local.bottom, mem, 0, 0, SRCCOPY);
    SelectObject(mem, oldBmp); DeleteObject(bmp); DeleteDC(mem);
}

void DrawCoreOrb
'@
Replace-One 'void DrawHudChip\(HDC hdc, RECT r, const wchar_t\* text, COLORREF border, COLORREF fg\) \{.*?\r?\n\}\r?\n\r?\nvoid DrawCoreOrb' $hud 'DrawHudChip'

# Double-buffered animated crystal buttons.
$button = @'
void DrawOwnerButton(const DRAWITEMSTRUCT* dis) {
    if (!dis) return;

    HDC target = dis->hDC;
    RECT r = dis->rcItem;
    const int w = r.right - r.left;
    const int h = r.bottom - r.top;
    if (w <= 2 || h <= 2) return;

    HDC hdc = CreateCompatibleDC(target);
    HBITMAP bmp = CreateCompatibleBitmap(target, w, h);
    HGDIOBJ oldBmp = SelectObject(hdc, bmp);
    RECT box{0,0,w,h};

    const int id = GetDlgCtrlID(dis->hwndItem);
    const bool disabled = (dis->itemState & ODS_DISABLED) != 0;
    const bool pressed = (dis->itemState & ODS_SELECTED) != 0;
    const bool focused = (dis->itemState & ODS_FOCUS) != 0;
    const bool active = IsActiveButton(id);
    const bool accent = id == ID_DOWNLOAD;
    const bool folder = id == ID_OPEN_DOWNLOADS || id == ID_OPEN_EDITED;
    const bool icon = id == ID_HOME || id == ID_RELOAD;

    HBRUSH clear = CreateSolidBrush(RGB(3, 10, 18));
    FillRect(hdc, &box, clear); DeleteObject(clear);

    RECT glass = box; InflateRect(&glass, -Ui(g_hwnd, 2), -Ui(g_hwnd, 2));
    const int radius = Ui(g_hwnd, 15);
    HRGN clip = CreateRoundRectRgn(glass.left, glass.top, glass.right + 1, glass.bottom + 1, radius, radius);
    int saved = SaveDC(hdc); SelectClipRgn(hdc, clip);

    COLORREF top = RGB(10, 31, 45), bottom = RGB(4, 13, 25);
    COLORREF border = RGB(43, 132, 168), glow = RGB(67, 75, 132), text = RGB(220, 244, 255);
    if (active) { top = RGB(10, 54, 70); bottom = RGB(5, 24, 38); border = RGB(52, 230, 255); glow = RGB(122, 84, 255); }
    if (accent) { top = RGB(37, 30, 91); bottom = RGB(17, 16, 54); border = RGB(121, 86, 255); glow = RGB(35, 210, 255); }
    if (folder) { top = RGB(8, 42, 56); bottom = RGB(4, 18, 31); border = RGB(47, 194, 228); }
    if (pressed) { top = RGB(18, 70, 86); bottom = RGB(7, 30, 43); }
    if (disabled) { top = RGB(11, 18, 27); bottom = RGB(5, 10, 17); border = RGB(47, 65, 76); glow = RGB(35, 40, 55); text = RGB(90, 109, 119); }

    FillAuroraGradient(hdc, glass, top, bottom);

    const int travel = (std::max)(1, w + Ui(g_hwnd, 60));
    const int sweep = (g_hudPhase * Ui(g_hwnd, 7) + id * 13) % travel - Ui(g_hwnd, 30);
    HPEN sweepPen = CreatePen(PS_SOLID, Ui(g_hwnd, 5), active ? RGB(61, 194, 255) : RGB(61, 91, 155));
    HGDIOBJ sweepOld = SelectObject(hdc, sweepPen);
    MoveToEx(hdc, sweep, glass.top, nullptr);
    LineTo(hdc, sweep + Ui(g_hwnd, 28), glass.bottom);
    SelectObject(hdc, sweepOld); DeleteObject(sweepPen);

    RestoreDC(hdc, saved); DeleteObject(clip);

    HPEN outer = CreatePen(PS_SOLID, Ui(g_hwnd, active || focused ? 2 : 1), border);
    HPEN inner = CreatePen(PS_SOLID, 1, glow);
    HGDIOBJ oldP = SelectObject(hdc, outer);
    HGDIOBJ oldB = SelectObject(hdc, GetStockObject(NULL_BRUSH));
    RoundRect(hdc, glass.left, glass.top, glass.right-1, glass.bottom-1, radius, radius);
    RECT in = glass; InflateRect(&in, -Ui(g_hwnd, 2), -Ui(g_hwnd, 2));
    SelectObject(hdc, inner);
    RoundRect(hdc, in.left, in.top, in.right-1, in.bottom-1, radius-4, radius-4);

    HPEN shine = CreatePen(PS_SOLID, 1, disabled ? RGB(44, 55, 63) : RGB(130, 230, 255));
    SelectObject(hdc, shine);
    MoveToEx(hdc, glass.left + Ui(g_hwnd, 12), glass.top + Ui(g_hwnd, 3), nullptr);
    LineTo(hdc, glass.right - Ui(g_hwnd, 12), glass.top + Ui(g_hwnd, 3));

    SelectObject(hdc, oldP); SelectObject(hdc, oldB);
    DeleteObject(outer); DeleteObject(inner); DeleteObject(shine);

    wchar_t txt[128]{}; GetWindowTextW(dis->hwndItem, txt, 127);
    SetBkMode(hdc, TRANSPARENT); SetTextColor(hdc, text);
    if (icon && g_fontIcon) SelectObject(hdc, g_fontIcon); else if (g_font) SelectObject(hdc, g_font);
    DrawTextW(hdc, txt, -1, &box, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX);

    if (active) {
        const int pulse = Ui(g_hwnd, 2 + (g_hudPhase % 4 == 0 ? 1 : 0));
        HPEN ap = CreatePen(PS_SOLID, pulse, RGB(47, 232, 255));
        HGDIOBJ op = SelectObject(hdc, ap);
        MoveToEx(hdc, glass.left + Ui(g_hwnd, 18), glass.bottom - Ui(g_hwnd, 4), nullptr);
        LineTo(hdc, glass.right - Ui(g_hwnd, 18), glass.bottom - Ui(g_hwnd, 4));
        SelectObject(hdc, op); DeleteObject(ap);
    }

    BitBlt(target, r.left, r.top, w, h, hdc, 0, 0, SRCCOPY);
    SelectObject(hdc, oldBmp); DeleteObject(bmp); DeleteDC(hdc);
}

void CreateControls
'@
Replace-One 'void DrawOwnerButton\(const DRAWITEMSTRUCT\* dis\) \{.*?\r?\n\}\r?\n\r?\nvoid CreateControls' $button 'DrawOwnerButton'

# Animate buttons only; never invalidate the whole native header.
$timerOld = 'RECT orb\{[^\r\n]+\};\s*InvalidateRect\(hwnd, &orb, FALSE\);'
$timerNew = @'
RECT orb{ 0, 0, Ui(hwnd, 72), Ui(hwnd, 80) };
            InvalidateRect(hwnd, &orb, FALSE);
            for (HWND h : { g_tabYouTube,g_tabEditor,g_tabFiles,g_btnBack,g_btnForward,g_btnHome,g_btnReload,g_btnDownload }) {
                if (h && IsWindowVisible(h)) InvalidateRect(h, nullptr, FALSE);
            }
'@
if ([regex]::IsMatch($src,$timerOld)) {
  $src = [regex]::Replace($src,$timerOld,$timerNew,1)
} elseif (-not $src.Contains('InvalidateRect(h, nullptr, FALSE);')) {
  throw "V3 timer animation anchor missing"
}

# Fallback editor: crystal glass card + animation.
$fallbackPattern = 'g_editorWebView->NavigateToString\(\s*L"<!doctype html>.*?\);'
$fallback = @'
g_editorWebView->NavigateToString(
                        L"<!doctype html><html><head><meta charset='utf-8'><style>"
                        L"*{box-sizing:border-box}html,body{margin:0;width:100%;height:100%;overflow:hidden;font-family:Segoe UI,Arial;background:#020711;color:#eafaff}"
                        L"body{display:grid;place-items:center;background:radial-gradient(circle at 20% 0%,#123651 0,#06101d 34%,#020711 72%)}"
                        L"body:before,body:after{content:'';position:fixed;width:520px;height:520px;border-radius:50%;filter:blur(110px);opacity:.22;animation:float 7s ease-in-out infinite alternate;pointer-events:none}"
                        L"body:before{background:#22dfff;left:-160px;top:-180px}body:after{background:#7656ff;right:-160px;bottom:-200px;animation-delay:-3s}"
                        L".card{position:relative;width:min(760px,72vw);padding:46px 50px;border-radius:28px;border:1px solid #3db7df88;background:linear-gradient(160deg,#0d2232cc,#081421b8 58%,#12102aa8);box-shadow:0 30px 90px #000a,inset 0 1px #bdf6ff55,inset 0 0 38px #2ccff315;backdrop-filter:blur(24px);overflow:hidden;text-align:center}"
                        L".card:before{content:'';position:absolute;inset:0;border-radius:28px;background:linear-gradient(115deg,transparent 20%,#55e7ff18 43%,#8f69ff22 52%,transparent 67%);transform:translateX(-120%);animation:sweep 3.8s linear infinite}"
                        L"h1{margin:0 0 18px;color:#48e6ff;font-size:42px;letter-spacing:1.5px;text-shadow:0 0 24px #32dfff55}p{font-size:18px;color:#d7edf7;line-height:1.55}.tag{display:inline-block;margin-top:12px;padding:10px 16px;border-radius:14px;border:1px solid #6e7cff66;background:#0a1830aa;color:#bfeeff}b{color:#fff}"
                        L"@keyframes sweep{to{transform:translateX(120%)}}@keyframes float{to{transform:translate(70px,40px) scale(1.1)}}"
                        L"</style></head><body><div class='card'><h1>EDITOR CORE</h1><p>Los componentes locales aun no estan preparados.</p><p>Ejecuta <b>PREPARAR_COMPONENTES.cmd</b>, cierra YT Studio CORE y vuelve a abrirlo.</p><div class='tag'>AURORA CRYSTAL DARK</div></div></body></html>");
'@
$rxFallback = [regex]::new($fallbackPattern,[Text.RegularExpressions.RegexOptions]::Singleline)
if (-not $rxFallback.IsMatch($src)) { throw "V3 fallback editor anchor missing" }
$src = $rxFallback.Replace($src,$fallback,1)

# Stronger native header gradient.
$src = $src.Replace(
  'RECT top{ 0,0,rc.right,topH }; FillAuroraGradient(hdc, top, RGB(6, 24, 38), RGB(3, 12, 23));',
  'RECT top{ 0,0,rc.right,topH }; FillAuroraGradient(hdc, top, RGB(7, 28, 44), RGB(3, 10, 20));'
)

[IO.File]::WriteAllText($cpp,$src,[Text.UTF8Encoding]::new($false))

# Actual editor UI: cards, rounded controls and animated aurora.
$web = [IO.File]::ReadAllText($html)
if (-not $web.Contains('Aurora Crystal Dark v3')) {
$css = @'

/* Aurora Crystal Dark v3 */
:root{--radius:20px}
body:after{content:"";position:fixed;inset:-25%;pointer-events:none;background:radial-gradient(circle at 22% 20%,#28ddff1f 0,transparent 18%),radial-gradient(circle at 78% 76%,#805cff1f 0,transparent 19%);filter:blur(28px);animation:auroraDrift 9s ease-in-out infinite alternate;z-index:0}
.main,.top{position:relative;z-index:1}
.card{background:linear-gradient(155deg,#0b1a29d9,#07111fbe 58%,#110f27b6);border:1px solid #52c5ee55;border-radius:20px;box-shadow:0 24px 70px #000a,inset 0 1px #d7fbff38,inset 0 0 42px #25d5ff0f;backdrop-filter:blur(22px);-webkit-backdrop-filter:blur(22px)}
.section{border:1px solid #2f90b344!important;background:linear-gradient(160deg,#0a1b29b8,#07111ca6)!important;border-radius:14px!important;box-shadow:inset 0 1px #d4fbff20,inset 0 0 22px #37d9ff0a}
.back,.miniBtn,.btn,.actionBtn,.select{border-radius:12px!important;box-shadow:inset 0 1px #d8fbff28,0 8px 18px #0004;transition:transform .18s ease,border-color .18s ease,box-shadow .18s ease,background .18s ease}
.back:hover,.miniBtn:hover,.btn:hover,.actionBtn:hover{transform:translateY(-1px);box-shadow:inset 0 1px #fff4,0 10px 24px #0007,0 0 22px #29dbff2a}
.btn.active{background:linear-gradient(135deg,#123b56cc,#171b45cc)!important;border-color:#45e6ff!important;box-shadow:0 0 22px #2bdfff2b,inset 0 1px #e4fcff55!important}
.cutBtn{background:linear-gradient(135deg,#12689f,#20bfd8,#3650c8);background-size:220% 220%;animation:buttonAura 5s ease infinite}
.aiBtn{background:linear-gradient(135deg,#5a45de,#9a4cff,#2b9cff);background-size:220% 220%;animation:buttonAura 5s ease infinite reverse}
.core{animation:corePulse 2.4s ease-in-out infinite}
@keyframes auroraDrift{to{transform:translate3d(6%,4%,0) scale(1.08)}}
@keyframes buttonAura{0%,100%{background-position:0 50%}50%{background-position:100% 50%}}
@keyframes corePulse{50%{box-shadow:0 0 28px #23d9ffbb,inset 0 0 20px #7c5cff55;transform:scale(1.04)}}
'@
  $web = $web.Replace('</style>',$css + $nl + '</style>')
}
[IO.File]::WriteAllText($html,$web,[Text.UTF8Encoding]::new($false))

# Final guards.
$cppNow = [IO.File]::ReadAllText($cpp)
$webNow = [IO.File]::ReadAllText($html)
$checks = @('SetRoundedControlRegion','CreateCompatibleDC(target)','InvalidateRect(h, nullptr, FALSE);','AURORA CRYSTAL DARK','Ui(g_hwnd, 46)')
foreach ($check in $checks) { if (-not $cppNow.Contains($check)) { throw "V3 validation failed: $check" } }
if (-not $webNow.Contains('Aurora Crystal Dark v3')) { throw "V3 editor CSS validation failed" }

Write-Host "Aurora Crystal Dark v3 applied"
