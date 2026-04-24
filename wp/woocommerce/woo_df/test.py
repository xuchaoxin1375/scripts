from comutils import FastOffsetCipher
enc=FastOffsetCipher()
et=enc.encrypt('goodnight.com')
print(et,"->",enc.decrypt(et))