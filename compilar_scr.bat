@echo off
title Compilar Eye.scr para Windows
chcp 65001 >nul
cd /d "%~dp0"

echo Compilando Eye.scr usando o compilador nativo do Windows (.NET Framework)...
set "CSC=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"

if not exist "%CSC%" (
    set "CSC=C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)

if not exist "%CSC%" (
    echo [!] Compilador csc.exe nao encontrado.
    pause
    exit /b 1
)

"%CSC%" /target:winexe /out:Eye.scr /r:System.Windows.Forms.dll windows\Eye.cs

if %ERRORLEVEL% EQU 0 (
    echo [OK] Eye.scr compilado com sucesso!
    echo Voce pode clicar com o botao direito nele e escolher "Testar" ou "Instalar".
) else (
    echo [!] Erro ao compilar Eye.scr.
)

pause
