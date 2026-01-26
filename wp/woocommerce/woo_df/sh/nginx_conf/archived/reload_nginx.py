import subprocess
import sys

NGINX_PATH = "nginx"

def test_and_reload_nginx():
    """
    模拟 'nginx -t && nginx -s reload' 的逻辑。
    首先测试配置 (nginx -t)，如果成功，则执行重载 (nginx -s reload)。

    注意：您可能需要替换 '/usr/sbin/nginx' 为您宝塔安装的 Nginx 完整路径。
    例如：'/www/server/nginx/sbin/nginx'
    """

    # 假设 Nginx 可执行文件在 PATH 中，否则请使用完整路径

    # --- 第一步：测试配置 (nginx -t) ---
    print("--- 1. 正在测试 Nginx 配置文件语法 (nginx -t) ---")

    test_command = [NGINX_PATH, "-t"]

    try:
        # 在这里我们不使用 check=True，而是手动检查返回代码，
        # 因为我们想在配置失败时打印特定信息
        test_result = subprocess.run(test_command, capture_output=True, text=True)

        # 检查返回代码：0 表示成功
        if test_result.returncode == 0:
            print("✅ 配置文件语法测试通过。")
            # Nginx -t 的输出通常很有用，即使成功也打印
            if test_result.stdout or test_result.stderr:
                print("测试输出:\n", test_result.stdout, test_result.stderr)
        else:
            # 测试失败，直接退出函数
            print(f"❌ 配置文件测试失败，错误代码: {test_result.returncode}")
            print("请检查配置中的语法错误。")
            print("错误详情:\n", test_result.stderr)
            return  # 停止执行后续的 reload

    except FileNotFoundError:
        print(f"致命错误：找不到 Nginx 可执行文件 '{NGINX_PATH}'。请检查路径是否正确。")
        return
    except Exception as e:
        print(f"测试 Nginx 时发生未知错误: {e}")
        return

    # --- 第二步：重载配置 (nginx -s reload) ---
    print("--- 2. 配置测试成功，正在重载 Nginx (nginx -s reload) ---")

    reload_command = [NGINX_PATH, "-s", "reload"]

    try:
        reload_result = subprocess.run(
            reload_command,
            capture_output=True,
            text=True,
            check=True,  # 确保 reload 成功
        )

        print("🎉 Nginx 重载成功。")
        if reload_result.stdout:
            print("重载输出:\n", reload_result.stdout)

    except subprocess.CalledProcessError as e:
        # reload 失败（尽管测试通过，但执行时仍可能失败，如权限问题）
        print(f"❌ Nginx 重载失败，退出代码: {e.returncode}")
        print("标准错误:\n", e.stderr)
    except Exception as e:
        print(f"重载 Nginx 时发生未知错误: {e}")


# 执行函数
test_and_reload_nginx()
