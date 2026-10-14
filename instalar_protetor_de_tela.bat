@echo off
title Instalador do Protetor de Tela Eye para Windows
chcp 65001 >nul
cd /d "%~dp0"

echo ========================================================
echo   Instalador do Protetor de Tela Eye para Windows
echo ========================================================
echo.

:: 1. Registra o caminho de instalacao no registro do Windows
echo [+] Registrando caminho do projeto no Windows...
reg add "HKCU\Software\EyeScreensaver" /v "InstallPath" /t REG_SZ /d "%CD%" /f >nul

:: 2. Recompila Eye.scr para garantir a versao mais recente
echo [+] Atualizando Eye.scr...
call compilar_scr.bat >nul 2>nul

:: 3. Configura Eye.scr como o protetor ativo no Registro do Windows
echo [+] Configurando Eye como protetor de tela ativo...
reg add "HKCU\Control Panel\Desktop" /v "SCRNSAVE.EXE" /t REG_SZ /d "%CD%\Eye.scr" /f >nul
reg add "HKCU\Control Panel\Desktop" /v "ScreenSaveActive" /t REG_SZ /d "1" /f >nul
reg add "HKCU\Control Panel\Desktop" /v "ScreenSaverIsSecure" /t REG_SZ /d "1" /f >nul

:: Servidor da webcam sobe junto com o login (necessario para o bloqueio por ausencia)
set "PYW="
for /f "delims=" %%i in ('where pythonw 2^>nul') do if not defined PYW set "PYW=%%i"
if defined PYW reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "EyeServer" /t REG_SZ /d "\"%PYW%\" \"%CD%pp.py\" --no-browser" /f >nul

:: Tenta copiar para System32 se tiver permissao (opcional)
copy /y "Eye.scr" "%SystemRoot%\System32\Eye.scr" >nul 2>nul

echo.
echo ========================================================
echo   INSTALACAO CONCLUIDA COM SUCESSO!
echo ========================================================
echo.
echo O Eye foi registrado como seu Protetor de Tela oficial!
echo.
echo Opcoes:
echo  [1] Testar o protetor de tela agora
echo  [2] Abrir Configuracoes de Protecao de Tela do Windows
echo  [3] Sair
echo.
set /p opt="Escolha uma opcao (1, 2 ou 3): "

if "%opt%"=="1" (
    echo Iniciando...
    start "" Eye.scr /s
    exit
)

if "%opt%"=="2" (
    echo Abrindo Configuracoes de Protecao de Tela...
    control desk.cpl,,@screensaver
    exit
)

exit
