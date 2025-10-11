import os
import os.path as op
import time
dirName="C:/Users/cxxu/AppData/Local/Packages/Microsoft.Windows.ContentDeliveryManager_cw5n1h2txyewy/LocalState/Assets"
def renameFiles(dirName='.'):
    items=os.listdir(dirName)
    index=0
    # there use os.chdir() to reset the current working directory;of course,you can use absolute path rather than fileName
    os.chdir(dirName)
    print(os.getcwd())
    for item in items:
        index+=1
        # newName=str(index)+".jpg"
        time_string = time.strftime(
        '%Y-%m-%d %H-%M-%S', time.localtime(time.time()))
        time_string=time_string+"  "+str(index)
        newName= time_string+'.jpg'
        if not op.exists(newName):
            os.rename(item,newName)

        print(item)
        
        
if __name__=="__main__":
    
    print("test")
    renameFiles(dirName)

