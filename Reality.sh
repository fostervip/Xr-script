#!/bin/bash

# Xray Reality 一键安装脚本
# 兼容 Xray 26.10.x 及更新版本（支持 Password (PublicKey) 格式）
# 协议：VLESS + REALITY + Vision

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

clear
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}     Xray Reality 一键安装脚本 (2026)        ${NC}"
echo -e "${GREEN}     兼容 Xray 26.10.x 新密钥输出格式         ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo

# 检查 root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}请使用 root 权限运行：sudo ./xray-reality.sh${NC}"
    exit 1
fi

# 1. 系统更新 + 开启 BBR
echo -e "${YELLOW}[1/7] 更新系统并开启 BBR...${NC}"
apt update -y >/dev/null 2>&1
apt upgrade -y >/dev/null 2>&1

# 开启 BBR
grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p >/dev/null 2>&1

if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
    echo -e "${GREEN}✓ BBR 已开启${NC}"
else
    echo -e "${YELLOW}⚠ BBR 开启可能失败，继续执行...${NC}"
fi

# 2. 安装 / 检查 Xray
echo -e "${YELLOW}[2/7] 检查并安装 Xray-core...${NC}"
if ! command -v xray >/dev/null 2>&1; then
    echo -e "${BLUE}正在安装 Xray...${NC}"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
else
    echo -e "${GREEN}✓ 检测到已安装 Xray: $(xray version | head -n1)${NC}"
fi

# 确认 xray 命令可用
if ! command -v xray >/dev/null 2>&1; then
    echo -e "${RED}Xray 安装失败，请检查网络后重试${NC}"
    exit 1
fi

# 3. 生成 UUID 和 Reality 密钥（兼容新旧格式）
echo -e "${YELLOW}[3/7] 生成 UUID 和 Reality 密钥...${NC}"

UUID=$(xray uuid)
echo -e "${GREEN}UUID: $UUID${NC}"

# 生成密钥
KEY_OUTPUT=$(xray x25519 2>&1)
echo -e "${BLUE}密钥原始输出：${NC}"
echo "$KEY_OUTPUT"
echo

# 提取 PrivateKey（兼容多种写法）
PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep -iE 'PrivateKey|Private key' | head -1 | sed -E 's/.*[:：]\s*//')

# 提取 PublicKey（兼容 Password (PublicKey) / PublicKey / Public key）
PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -iE 'Password \(PublicKey\)|Password|PublicKey|Public key' | head -1 | sed -E 's/.*[:：]\s*//')

# 生成 ShortId（8位十六进制）
SHORT_ID=$(openssl rand -hex 4 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 8)

if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" ]]; then
    echo -e "${RED}密钥提取失败！请手动执行 xray x25519 并把完整输出发给我${NC}"
    exit 1
fi

echo -e "${GREEN}PrivateKey : $PRIVATE_KEY${NC}"
echo -e "${GREEN}PublicKey  : $PUBLIC_KEY${NC}"
echo -e "${GREEN}ShortId    : $SHORT_ID${NC}"
echo

# 4. 选择伪装目标
echo -e "${YELLOW}[4/7] 选择 Reality 伪装目标网站${NC}"
echo "1) www.microsoft.com   (推荐)"
echo "2) www.apple.com"
echo "3) www.cloudflare.com"
echo "4) www.amazon.com"
echo "5) www.samsung.com"
echo "6) 自定义"
read -p "请输入选项 [1-6，默认1]: " DEST_CHOICE
DEST_CHOICE=${DEST_CHOICE:-1}

case $DEST_CHOICE in
    1) DEST="www.microsoft.com:443"; SNI="www.microsoft.com" ;;
    2) DEST="www.apple.com:443"; SNI="www.apple.com" ;;
    3) DEST="www.cloudflare.com:443"; SNI="www.cloudflare.com" ;;
    4) DEST="www.amazon.com:443"; SNI="www.amazon.com" ;;
    5) DEST="www.samsung.com:443"; SNI="www.samsung.com" ;;
    6)
        read -p "请输入目标地址 (例如 www.example.com:443): " DEST
        read -p "请输入 SNI (例如 www.example.com): " SNI
        ;;
    *) DEST="www.microsoft.com:443"; SNI="www.microsoft.com" ;;
esac

echo -e "${GREEN}已选择: $DEST${NC}"
echo

# 5. 写入配置文件
echo -e "${YELLOW}[5/7] 写入配置文件...${NC}"
mkdir -p /usr/local/etc/xray

cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$DEST",
          "xver": 0,
          "serverNames": [
            "$SNI"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORT_ID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom"
    }
  ]
}
EOF

echo -e "${GREEN}✓ 配置文件已写入 /usr/local/etc/xray/config.json${NC}"

# 6. 开放防火墙
echo -e "${YELLOW}[6/7] 配置防火墙...${NC}"
if command -v ufw >/dev/null 2>&1; then
    ufw allow 443/tcp >/dev/null 2>&1
    echo -e "${GREEN}✓ ufw 已放行 443 端口${NC}"
fi

# 云厂商安全组提醒
echo -e "${YELLOW}⚠ 请确保云服务器控制台安全组已放行 TCP 443 端口${NC}"

# 7. 测试并启动服务
echo -e "${YELLOW}[7/7] 测试配置并启动服务...${NC}"

if ! xray -test -config /usr/local/etc/xray/config.json; then
    echo -e "${RED}配置文件测试失败，请检查${NC}"
    exit 1
fi

systemctl enable xray >/dev/null 2>&1
systemctl restart xray

sleep 1
if systemctl is-active --quiet xray; then
    echo -e "${GREEN}✓ Xray 服务已成功启动并设置开机自启${NC}"
else
    echo -e "${RED}Xray 启动失败，查看日志：journalctl -u xray -n 30 --no-pager${NC}"
    exit 1
fi

# 输出客户端信息
echo
echo -e "${GREEN}==============================================${NC}"
echo -e "${GREEN}              安装完成！客户端参数             ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo
echo -e "协议          : ${YELLOW}VLESS${NC}"
echo -e "地址          : ${YELLOW}你的服务器公网IP${NC}"
echo -e "端口          : ${YELLOW}443${NC}"
echo -e "UUID          : ${YELLOW}$UUID${NC}"
echo -e "Flow          : ${YELLOW}xtls-rprx-vision${NC}"
echo -e "加密          : ${YELLOW}none${NC}"
echo -e "传输协议      : ${YELLOW}tcp${NC}"
echo -e "安全          : ${YELLOW}reality${NC}"
echo -e "SNI           : ${YELLOW}$SNI${NC}"
echo -e "Fingerprint   : ${YELLOW}chrome${NC}"
echo -e "PublicKey     : ${YELLOW}$PUBLIC_KEY${NC}"
echo -e "ShortId       : ${YELLOW}$SHORT_ID${NC}"
echo -e "SpiderX       : ${YELLOW}/${NC}"
echo
echo -e "${BLUE}配置文件位置  : /usr/local/etc/xray/config.json${NC}"
echo -e "${BLUE}查看实时日志  : journalctl -u xray -f${NC}"
echo -e "${BLUE}重启服务      : systemctl restart xray${NC}"
echo
echo -e "${GREEN}请将以上参数填入客户端（v2rayN / Nekobox / Streisand / Shadowrocket 等）${NC}"
echo
