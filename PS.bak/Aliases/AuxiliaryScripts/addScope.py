fileName = "../alias.ps1"
d = print
with open(fileName) as f:
    # read only one line
    # contentLine=f.readline()
    # # d(contentLine)

    # read all content:every line as a element of the result list
    contentLines = f.readlines()
    # d(contentLines)

    # read whole file and return a string (contain all content)
    # contentRead=f.read()
    # d(contentRead)
retList = []
for item in contentLines:
    if item.startswith("s") or item.startswith("S"):
        # d(item)
        item_new = item.strip()+" -Scope global\n"
        # d(item_new)
        retList.append(item_new)
        
with open(fileName+"_ScopeGlobal", "w") as fout:
    retStr = "".join(retList)
    d(retStr)
    fout.write(retStr)
