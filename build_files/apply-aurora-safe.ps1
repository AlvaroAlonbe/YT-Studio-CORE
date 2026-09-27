param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectRoot
)

$ErrorActionPreference = "Stop"
$cpp = Join-Path $ProjectRoot "src\YTStudioNative.cpp"
if (-not (Test-Path $cpp)) { throw "YTStudioNative.cpp not found: $cpp" }

$src = [IO.File]::ReadAllText($cpp)
$nl = [Environment]::NewLine

# Icon-only Home / Reload, using Unicode symbols supported by Segoe UI.
$src = $src.Replace('L"INICIO"', 'L"⌂"')
$src = $src.Replace('L"RECARGAR"', 'L"⟳"')

# Aurora dark surfaces, preserving the existing native drawing logic.
$src = [regex]::Replace($src, 'g_bgBrush\s*=\s*CreateSolidBrush\(RGB\([^)]+\)\);', 'g_bgBrush = CreateSolidBrush(RGB(3, 8, 15));')
$src = [regex]::Replace($src, 'g_topBrush\s*=\s*CreateSolidBrush\(RGB\([^)]+\)\);', 'g_topBrush = CreateSolidBrush(RGB(5, 18, 29));')
$src = [regex]::Replace($src, 'g_navBrush\s*=\s*CreateSolidBrush\(RGB\([^)]+\)\);', 'g_navBrush = CreateSolidBrush(RGB(4, 13, 24));')

# More breathing room and compact icon buttons.
$src = $src.Replace('const int topH = topVisible ? Ui(g_hwnd, 70) : 0;', 'const int topH = topVisible ? Ui(g_hwnd, 74) : 0;')
$src = $src.Replace('const int navH = navVisible ? Ui(g_hwnd, 50) : 0;', 'const int navH = navVisible ? Ui(g_hwnd, 54) : 0;')
$src = $src.Replace('const int margin = Ui(g_hwnd, 12);', 'const int margin = Ui(g_hwnd, 14);')
$src = $src.Replace('const int gap = Ui(g_hwnd, 7);', 'const int gap = Ui(g_hwnd, 10);')
$src = $src.Replace('const int tabH = Ui(g_hwnd, 38);', 'const int tabH = Ui(g_hwnd, 40);')
$src = $src.Replace('const int navNormalW = Ui(g_hwnd, 88);', 'const int navNormalW = Ui(g_hwnd, 48);')

# New safe helper inserted only after Ui() already exists.
$anchor = 'std::wstring LocalAppDataPath() {'
if (-not $src.Contains($anchor)) { throw "Safe UI insertion anchor not found" }

if (-not $src.Contains('void RoundAuroraControl(HWND hwnd)')) {
$helper = @'
void EnableAuroraBackdropSafe() {
    if (!g_hwnd) return;
    const BOOL dark = TRUE;
    const DWORD immersiveDarkMode = 20;
    const DWORD cornerPreference = 33;
    const DWORD systemBackdropType = 38;
    const int roundCorners = 2;
    const int mainWindowBackdrop = 2;
    DwmSetWindowAttribute(g_hwnd, immersiveDarkMode, &dark, sizeof(dark));
    DwmSetWindowAttribute(g_hwnd, cornerPreference, &roundCorners, sizeof(roundCorners));
    DwmSetWindowAttribute(g_hwnd, systemBackdropType, &mainWindowBackdrop, sizeof(mainWindowBackdrop));
}

void RoundAuroraControl(HWND hwnd) {
    if (!hwnd) return;
    RECT rc{};
    GetClientRect(hwnd, &rc);
    const int radius = Ui(hwnd, 12);
    HRGN region = CreateRoundRectRgn(0, 0, rc.right + 1, rc.bottom + 1, radius, radius);
    if (region) SetWindowRgn(hwnd, region, TRUE);
}

'@
  $src = $src.Replace($anchor, $helper + $anchor)
}

# Apply backdrop each layout pass.
$layoutAnchor = 'void Layout() {' + $nl + '    if (!g_hwnd) return;'
if ($src.Contains($layoutAnchor) -and -not $src.Contains($layoutAnchor + $nl + '    EnableAuroraBackdropSafe();')) {
  $src = $src.Replace($layoutAnchor, $layoutAnchor + $nl + '    EnableAuroraBackdropSafe();')
}

# Round all visible native controls after their size is assigned.
$handles = @(
  'g_tabYouTube','g_tabEditor','g_tabFiles',
  'g_btnBack','g_btnForward','g_btnHome','g_btnReload','g_btnDownload',
  'g_btnOpenDownloads','g_btnOpenEdited'
)

foreach ($h in $handles) {
  $pattern = 'MoveWindow\(' + [regex]::Escape($h) + ',([^;]+)\);'
  $src = [regex]::Replace($src, $pattern, {
      param($m)
      if ($m.Value.Contains('RoundAuroraControl')) { return $m.Value }
      return $m.Value + ' RoundAuroraControl(' + $h + ');'
  })
}

if (-not $src.Contains('void RoundAuroraControl(HWND hwnd)')) { throw "Rounded control helper missing" }
if (-not $src.Contains('RoundAuroraControl(g_btnHome)')) { throw "Home rounding missing" }
if (-not $src.Contains('L"⌂"')) { throw "Home icon missing" }
if (-not $src.Contains('L"⟳"')) { throw "Reload icon missing" }

[IO.File]::WriteAllText($cpp, $src, [Text.UTF8Encoding]::new($false))
Write-Host "Safe Aurora UI patch applied"
