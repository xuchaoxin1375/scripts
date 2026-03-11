print("Hello, Lua!")
-- 按 Ctrl+C 或输入 os.exit() 退出
-- 定义一个简单的表格（Lua 的核心）
local site_info = {
    name = "My Server",
    port = 80,
    active = true
}

-- 定义一个函数
function CS(site)
    if site.active then
        print(site.name .. " is running on port " .. site.port)
    else
        print("Site is down.")
    end
end

CS(site_info)