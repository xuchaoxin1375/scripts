

eng_alpha="a"
chinese_alpha="中"
## 方案0:isalpha(),无法区分中文字母(汉字)和英文字母A-Za-z
## 方案1:
def is_eng_alpha(char):
    return char.islower() or char.isupper()

## 方案2:(判断所给字符是否为英文字母)
def  is_eng_alpha2(char):
    if char>="a" and char<='z' or char>="A" and char<='Z':
        print("char is english alpha")
        return True
    else:
        print("char is not english alpha")
        return $False
if __name__=="__main__":
    is_eng_alpha2(eng_alpha)
    is_eng_alpha2(chinese_alpha)