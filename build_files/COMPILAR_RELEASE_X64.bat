@echo off
setlocal
cd /d "%~dp0"

set "NUGET=%~dp0nuget.exe"
if not exist "%NUGET%" (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest https://dist.nuget.org/win-x86-commandline/latest/nuget.exe -OutFile '%NUGET%'"
  if errorlevel 1 goto :fail
)

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" goto :fail

for /f "usebackq tokens=*" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\MSBuild.exe`) do set "MSBUILD=%%I"
if not defined MSBUILD goto :fail

"%NUGET%" restore "YTStudioCoreNative.sln" -PackagesDirectory "packages" -NonInteractive
if errorlevel 1 goto :fail

"%MSBUILD%" "YTStudioCoreNative.sln" /m /t:Build /p:Configuration=Release /p:Platform=x64 /v:minimal
if errorlevel 1 goto :fail

if not exist "dist" mkdir "dist"
copy /y "helper_native.py" "dist\helper_native.py" >nul
if not exist "dist\web" mkdir "dist\web"
xcopy /e /i /y "web\*" "dist\web\" >nul

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "$ErrorActionPreference='Stop';" ^
 "New-Item -ItemType Directory -Force 'dist\runtime','dist\tools' | Out-Null;" ^
 "if(-not (Test-Path 'dist\runtime\python.exe')){Invoke-WebRequest 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip' -OutFile 'python_embed.zip'; Expand-Archive 'python_embed.zip' -DestinationPath 'dist\runtime' -Force};" ^
 "if(-not (Test-Path 'dist\tools\yt-dlp.exe')){Invoke-WebRequest 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe' -OutFile 'dist\tools\yt-dlp.exe'};" ^
 "if(-not (Test-Path 'dist\tools\ffmpeg.exe')){Invoke-WebRequest 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' -OutFile 'ffmpeg.zip'; if(Test-Path 'ffmpeg_tmp'){Remove-Item 'ffmpeg_tmp' -Recurse -Force}; Expand-Archive 'ffmpeg.zip' -DestinationPath 'ffmpeg_tmp' -Force; $f=Get-ChildItem 'ffmpeg_tmp' -Recurse -Filter 'ffmpeg.exe'|Select-Object -First 1; $p=Get-ChildItem 'ffmpeg_tmp' -Recurse -Filter 'ffprobe.exe'|Select-Object -First 1; if(-not $f){throw 'ffmpeg.exe missing'}; Copy-Item $f.FullName 'dist\tools\ffmpeg.exe' -Force; if($p){Copy-Item $p.FullName 'dist\tools\ffprobe.exe' -Force}}"
if errorlevel 1 goto :fail

if not exist "dist\YTStudioCoreNative.exe" goto :fail
if not exist "dist\helper_native.py" goto :fail
if not exist "dist\web\editor.html" goto :fail
if not exist "dist\runtime\python.exe" goto :fail
if not exist "dist\tools\yt-dlp.exe" goto :fail
if not exist "dist\tools\ffmpeg.exe" goto :fail

echo.
echo COMPILACION Y PORTABLE OK
echo EJECUTA: dist\YTStudioCoreNative.exe
pause
exit /b 0

:fail
echo.
echo ERROR DE COMPILACION O EMPAQUETADO
pause
exit /b 1
