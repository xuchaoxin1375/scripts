[toc]



## abstract

在当前的批量建站方案下,建站人员需要做的工作已经大幅减少,早期需要人工点击的操作基本全面实现了脚本化和自动化,这包括:

- 收集并统一采集人员提交的域名到**在线表格**(google表格或者金山表格,腾讯表格起步较晚,功能不是那么完善不推荐)

- 域名提交购买(这一步只能手动,或者麻烦购买人员帮忙定期看在线表格,购买后修改状态为**待部署**)

- 宝塔面板中添加对应的网站(可以通过api批量添加,无需手动添加,联通相应的伪静态都一并配置好)

- cloudflare(简称cf)中的域名设置(此环节脚本实现,无需手动,但是注意api执行可能出现失败,如果检查网站打不开,可以再次执行或排查其他问题)

  - 往cloudflare账号面板中添加刚购买的域名

    > 其实这一步不需要域名已购买,但是购买后添加方便和后续步骤连续操作,建议是购买后在执行此步骤);

    > 这个步骤结束后可以获取到激活cf域名代理保护所需要的域名服务器组合(nameservers),比如(jeremy.ns.cloudflare.com ,aitana.ns.cloudflare.com)

  - 配置域名邮箱,安全相关的开关

- 域名供应商中的域名dns修改(以spaceship为例,此环节可以通过脚本调用api实现配置),就是利用前面cf中查询到的`nameservers`组合,然后稍等几分钟(少数情况会更久),cloudflare就可以验证你对域名的所有权,从而激活cf代理保护,隐藏服务器的真实ip

部署经过累次迭代,上述的流程简化为一条powershell命令

> ```powershell
> Deploy-WpSitesOnline
> 
> ```

但是为了支持多服务器多cloudflare账号,且为了准确添加站点到指定服务器上,现在需要用户指定服务器和cloudflare账户

为了支持多服务器之间的灵活选择和切换,请在相关的配置文件(cf_config.json和server_config.json)中填写必要的信息(账号名,密钥,api key等)

例如

```powershell
Deploy-WpSitesOnline -HostName server2 -CfAccount account2 
```

此命令依赖于如下配置

### 代码下载或克隆

代码无论是采集还是建站,都从仓库下载

```powershell
git clone https://gitee.com/xuchaoxin1375/scripts.git C:/repos/scripts
setx PsModulePath C:/repos/scripts/PS
```

详情参考: [ReadMe.md(woo_df)](..\ReadMe.md) 

### 相关配置

- 小组人员拼音映射

  创建一个`spiderTeam.json`配置文件,便于将人员名字映射成拼音缩写(或者其他规则也行),例如

  ```json
  {
      "张三": "zs",
      "李四": "ls",
      "DFTableStructure": "Domain,User"
  }
  ```
  
  
  
- 相关api的配置(宝塔,cloudflare,spaceship提供的密钥组合)

  - 其中宝塔和spaceship的密钥填写在各自的json配置文件中(写在配置文件中的好处是便于多账号管理和切换),务必存放在本地,不要上传到可能泄露的地方

  - cloudflare的密钥配置可以用全局key(global key),相对简单,可以直接写在环境变量中,可以根据需要配置以下环境变量

    ```bash
    CF_API_EMAIL
    CF_API_TOKEN_DNS_EDIT
    CF_API_KEY
    CF_ACCOUNT_ID
    ```

- 域名表(默认位置为桌面的`table.conf`文件中),最少3列,最多4列,分别是[域名/url,域名申请人,模板代号,网站标题)

  ```conf
  https://www.domain1.com	张三	7.es	Descubre libros que ....undo
  https://www.domain2.com	李四	2.us	
  ```

  其中网站标题是可选的,如果有,则在本地批量部署的时候会将其设置为站点标题,例如上述例子配置了2个站,第一个站域名是`domain1.com`,人员是'张三',将使用`7.es`这个模板,站点标题为`Descubre libros que ....undo`

  

## FAQ

在环境配置正确,并且执行命令`Deploy-WpSitesOnline`顺利的理想情况下,公网(https)链接马上就能访问网站了(无论网站是不是已经有上传的网站还是默认的'站点创建成功'提示,都标明此环节部署成功)

但是cloudflare的证书生效有延迟(ssl加密模式目前脚本默认设置为**灵活**,如果不是(默认可能是**完全**),会要求你自己部署证书,否则访问网站的时候会**404**或其他错误,比如500系列的服务器错误);

- 如果浏览器访问网站时提示ssl相关错误,则一般等待几分钟到半天不等,证书激活后就可以访问(解决:等待就行,部分怎么等都不行的可以换个账号手动配置)
- 但是如果cloudflare配置不完整(脚本调用api执行过程中有异常),则可能导致访问错误提示404/520..这类错误(解决:手动运行命令行`Add-CFZoneConfig`,触发从新配置cloudflare,然后重新访问)

