
@echo off

@REM net use W: http://localhost:5244/dav  /p:yes /savecred

@REM set log_home=C:\exes\alist\log
set log_home=C:\repos\scripts\startup\log
@REM 设置日志存储路径文件名
set log_file=%log_home%\MapLog.txt
set log_err=%log_home%\ErrLog.txt

@REM 可以检查alist挂载情况


@REM net use W: http://localhost:5244/dav  /p:yes /savecred >  %log_home%\MapLog.txt 2> %log_home%\MapErrLog.txt

net use W: http://localhost:5244/dav  /p:yes /savecred >>  %log_file% 2> %log_err%
@REM 重定向 2>&1 是将错误输出也重定向到标准输出

echo %date% %time% >> %log_file%
net use>>%log_file%

@REM echo %date% %time% >> C:\users\cxxu\desktop\filename.txt