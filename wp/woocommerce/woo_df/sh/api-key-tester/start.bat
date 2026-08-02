@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
set "PORT=8899"
set "PIDFILE=%~dp0.server.pid"

if "%~1"=="" goto start
if /i "%~1"=="start" goto start
if /i "%~1"=="stop" goto stop
if /i "%~1"=="status" goto status
echo 用法: start.bat start^|stop^|status
exit /b 1

:start
call :isrunning
if %RUNNING%==1 (
  echo 服务已在运行: http://localhost:%PORT%
  start "" "http://localhost:%PORT%"
  exit /b 0
)
echo 正在启动服务...
powershell -NoProfile -Command "$p = Start-Process -FilePath node -ArgumentList server.js,%PORT% -WorkingDirectory '%~dp0' -WindowStyle Hidden -PassThru -RedirectStandardOutput '%~dp0.server.log' -RedirectStandardError '%~dp0.server.err.log'; $p.Id | Out-File -Encoding ascii '%~dp0.server.pid'"
timeout /t 1 /nobreak >nul
call :isrunning
if %RUNNING%==1 (
  echo ✓ 服务已启动: http://localhost:%PORT%
  start "" "http://localhost:%PORT%"
) else (
  echo ✕ 启动失败，请确认已安装 Node.js 并查看 .server.log
  if exist "%~dp0.server.log" type "%~dp0.server.log"
)
exit /b 0

:stop
if not exist "%PIDFILE%" (
  echo 服务未在运行
  exit /b 0
)
set /p PID=<"%PIDFILE%"
if defined PID taskkill /F /PID %PID% >nul 2>&1
del "%PIDFILE%" 2>nul
echo ✓ 服务已停止
exit /b 0

:status
call :isrunning
if %RUNNING%==1 ( echo 运行中: http://localhost:%PORT% ) else ( echo 未运行 )
exit /b 0

:isrunning
set "RUNNING=0"
if not exist "%PIDFILE%" exit /b 0
set /p PID=<"%PIDFILE%"
tasklist /FI "PID eq %PID%" 2>nul | find /I "%PID%" >nul && set "RUNNING=1"
exit /b 0
