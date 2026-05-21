@REM Make sure the cmd scripts use 'CRLF'(not LF)
@REM pip config set global.index-url https://pypi.mirrors.ustc.edu.cn/simple/
@REM pip config set global.index-url https://mirrors.aliyun.com/pypi/simple/
pip config set global.index-url https://mirrors.pku.edu.cn/pypi/web/simple 

pip install scrapling
pip install scrapling[shell]
pip install scrapling[fetchers]

@REM update related packages
pip install scrapling curl_cffi -U

@REM install browsers...
patchright install
@REM playwright install

pause