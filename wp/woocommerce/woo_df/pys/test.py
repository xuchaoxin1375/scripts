# pwsh -NoProfile -Command Invoke-WebRequest -Uri 'https://www.bynder.fit%2C1 800w' -OutFile './imag50f8.webp' -TimeoutSec 30

cmd = [
# "pwsh",
"powershell.exe "
"-NoProfile",
"-Command",
'"',
"Invoke-WebRequest",

'"'
]
print(" ".join(cmd))