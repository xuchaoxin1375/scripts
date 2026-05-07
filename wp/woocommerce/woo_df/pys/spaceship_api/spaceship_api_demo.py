##
from spaceship_api import APIClient, get_auth

DESKTOP = r"C:/Users/Administrator/Desktop"
DEPLOY_CONFIGS = "C:/repos/configs/deploy_configs"
# 鉴权信息配置文件(json格式)
SS_CONFIG_PATH = rf"{DEPLOY_CONFIGS}/spaceship_config.json"

##
auth = get_auth(SS_CONFIG_PATH)

##
# key = auth["api_key"]
# secret = auth["api_secret"]
selected_account = auth["account"]
for account in auth["accounts"]:
    acc = account["account"]
    if acc == selected_account:
        key = account["api_key"]
        secret = account["api_secret"]
print(["selected_account", selected_account], ["api key:", key], ["secret:", secret])
##
api = APIClient(key, secret)


##
api.list_domains(take=3, skip=0, order_by="expirationDate")

##
api.list_domains_names_only(take=3)

##
