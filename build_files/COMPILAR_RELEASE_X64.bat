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

echo.
echo COMPILACION OK
echo EXE: dist\YTStudioCoreNative.exe
pause
exit /b 0

:fail
echo.
echo ERROR DE COMPILACION
pause
exit /b 1
