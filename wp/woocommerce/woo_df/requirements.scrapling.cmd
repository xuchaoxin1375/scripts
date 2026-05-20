@REM Make sure the cmd scripts use 'CRLF'(not LF)
@REM pip config set global.index-url https://pypi.mirrors.ustc.edu.cn/simple/
pip config set global.index-url http://mirrors.aliyun.com/pypi/simple/

uv pip install scrapling
uv pip install scrapling[shell]
uv pip install scrapling[fetchers]

@REM update related packages
uv pip install scrapling curl_cffi -U

@REM install browsers...
patchright install
@REM playwright install

pause