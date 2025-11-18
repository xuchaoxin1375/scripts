# 使用playwright下载
from imgdown import ImageDownloader

downloader = ImageDownloader(download_method="playwright")
urls = [
    "https://nginx-reverse-connect-imageproxy-e7yvr.ondigitalocean.app/images/%2FMultimedia_NEU%2FImport%2F701295%2FIM0010183.jpg",
    "https://www.bigw.com.au/medias/sys_master/images/images/h23/h39/100487658078238.jpg",
    "https://www.bigw.com.au/medias/sys_master/images/images/h23/h39/100487658078238.jpg",
    "https://www.bigw.com.au/medias/sys_master/images/images/hf7/h05/100887797104670.jpg",
    "https://www.bigw.com.au/medias/sys_master/images/images/h6a/h5f/100887801561118.jpg",
    "https://www.bigw.com.au/medias/sys_master/images/images/h4b/h75/98165934653470.jpg",
    "https://www.bigw.com.au/medias/sys_master/images/images/hb7/h90/100486475644958.jpg",
    "https://www.bigw.com.au/medias/sys_master/images/images/h30/hb1/100487992180766.jpg",
]
downloader.download_only_url(urls, output_dir="./images")
