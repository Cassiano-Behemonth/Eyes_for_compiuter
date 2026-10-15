@echo off
title Eye - Protetor de Tela Windows
chcp 65001 >nul
cd /d "%~dp0"

echo ===================================================
echo   Iniciando Eye - Protetor de Tela Windows
echo ===================================================

:: 1. Registra o caminho no Windows para que o Eye.scr funcione de qualquer lugar
reg add "HKCU\Software\EyeScreensaver" /v "InstallPath" /t REG_SZ /d "%CD%" /f >nul 2>nul

:: 2. Encerra com precisão instâncias anteriores do app.py e trava de arquivo
powershell -NoProfile -Command "if (Test-Path '.eye_instance.pid') { $p = Get-Content '.eye_instance.pid' -ErrorAction SilentlyContinue; if ($p) { Stop-Process -Id $p -Force -ErrorAction SilentlyContinue } }; Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*app.py*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }" >nul 2>nul
if exist ".eye_instance.lock" del /f /q ".eye_instance.lock" >nul 2>nul
if exist ".eye_instance.pid" del /f /q ".eye_instance.pid" >nul 2>nul

:: 3. Encerra instancias antigas do Edge Kiosk se ficaram presas em segundo plano
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name = 'msedge.exe'\" | Where-Object { $_.CommandLine -like '*EyeEdgeKioskProfile*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }" >nul 2>nul

:: Aguarda a liberação dos drivers de hardware da câmera pelo Windows
timeout /t 1 /nobreak >nul 2>nul

:: 4. Inicia o servidor Python com sensor de webcam em segundo plano
set "PY_CMD=pythonw"
where pythonw >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    set "PY_CMD=python"
)

echo [+] Iniciando sensor de webcam e servidor local...
start "" %PY_CMD% app.py --no-browser

:: 5. Aguarda o servidor HTTP e a webcam estarem prontos
set /a tentativas=0
:loop_check
set /a tentativas+=1
if %tentativas% GTR 25 goto abrir_navegador

curl -s --connect-timeout 1 http://127.0.0.1:54321/api/presence >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    timeout /t 1 /nobreak >nul 2>nul
    goto loop_check
)

:abrir_navegador
:: 6. Abre o Microsoft Edge em tela cheia (modo kiosk/app)
echo [+] Abrindo Protetor de Tela em tela cheia...
set "EDGE_EXE=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
if not exist "%EDGE_EXE%" set "EDGE_EXE=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
if not exist "%EDGE_EXE%" set "EDGE_EXE=%LocalAppData%\Microsoft\Edge\Application\msedge.exe"

if exist "%EDGE_EXE%" (
    start "" "%EDGE_EXE%" --user-data-dir="%TEMP%\EyeEdgeKioskProfile" --no-first-run --no-default-browser-check --app="http://127.0.0.1:54321" --start-fullscreen
) else (
    start "" "http://127.0.0.1:54321"
)

exit
