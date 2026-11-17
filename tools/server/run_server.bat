@echo off
rem cat game dedicated server (windows). edit the settings, then double click.
rem open udp PORT (cats) and QUERY_PORT (steam server list) in windows firewall / your router.
set NAME=cat server
rem house / forest / docks / trail / arena
set MAP=house
set PORT=24680
set QUERY_PORT=27016
set MAX=16
set MOTD=
cd /d "%~dp0"
set EXE=CatGameServer.exe
if exist CatGameServer.console.exe set EXE=CatGameServer.console.exe
:loop
%EXE% --headless -- --server --name "%NAME%" --map %MAP% --port %PORT% --query-port %QUERY_PORT% --max %MAX% --motd "%MOTD%"
echo server stopped, restarting in 5 s (close this window to quit)
timeout /t 5 >nul
goto loop
