# from curses.panel import new_panel
import os
import os.path as op
import time
dirName="D:/repos/ELA/docs/design/design_原型操作逻辑1"
def renameFiles(dirName='.'):
    items=os.listdir(dirName)
    index=0
    # there use os.chdir() to reset the current working directory;of course,you can use absolute path rather than fileName
    os.chdir(dirName)
    print(os.getcwd())
    for item in items:
        index+=1
        # new_name=str(index)+".jpg"
        char_list=[]
        for char in item:
            if char.isascii():
                char_list.append(char)
                # new_name=str(index)+".jpg"
        new_name=''.join(char_list)
        print(new_name)
        
        if not op.exists(new_name):
            os.rename(item,new_name)
            print(item,'-->',new_name)
        
        
if __name__=="__main__":
    
    print("test")
    renameFiles(dirName)

