#!/bin/bash

#判断系统
if [ ! -e '/etc/redhat-release' ]; then
echo "仅支持centos7"
exit
fi
if  [ -n "$(grep ' 6\.' /etc/redhat-release)" ] ;then
echo "仅支持centos7"
exit
fi

#更新内核
update_kernel(){

    yum -y install epel-release curl
    sed -i "0,/enabled=0/s//enabled=1/" /etc/yum.repos.d/epel.repo
    yum remove -y kernel-devel
    rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
    rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-2.el7.elrepo.noarch.rpm
    yum --disablerepo="*" --enablerepo="elrepo-kernel" list available
    yum -y --enablerepo=elrepo-kernel install kernel-ml
    sed -i "s/GRUB_DEFAULT=saved/GRUB_DEFAULT=0/" /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg
    wget https://elrepo.org/linux/kernel/el7/x86_64/RPMS/kernel-ml-devel-4.19.1-1.el7.elrepo.x86_64.rpm
    rpm -ivh kernel-ml-devel-4.19.1-1.el7.elrepo.x86_64.rpm
    yum -y --enablerepo=elrepo-kernel install kernel-ml-devel
    read -p "需要重启VPS，再次执行脚本选择安装wireguard，是否现在重启 ? [Y/n] :" yn
	[ -z "${yn}" ] && yn="y"
	if [[ $yn == [Yy] ]]; then
		echo -e "VPS 重启中..."
		reboot
	fi
}

#centos7安装wireguard
wireguard_install(){
    curl -Lo /etc/yum.repos.d/wireguard.repo https://copr.fedorainfracloud.org/coprs/jdoss/wireguard/repo/epel-7/jdoss-wireguard-epel-7.repo
    yum install -y epel-release
    yum install -y wireguard-dkms wireguard-tools
    

    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.accept_ra=2" >> /etc/sysctl.conf

    firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=10.0.0.0/24 masquerade'
    firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -i wg0 -o eth0 -j ACCEPT
    firewall-cmd --permanent --add-rich-rule='rule family=ipv6 source address=fd10:db31:203:ab31::1/64 masquerade'
    firewall-cmd --permanent --direct --add-rule ipv6 filter FORWARD 0 -i wg0 -o eth0 -j ACCEPT
    firewall-cmd --permanent --add-port=9999/udp
    firewall-cmd --reload

    mkdir -p /etc/wireguard
    cd /etc/wireguard
    wg genkey | tee sprivatekey | wg pubkey > spublickey
    wg genkey | tee cprivatekey | wg pubkey > cpublickey
    chmod 777 -R /etc/wireguard
    systemctl enable wg-quick@wg0
}

# Bash执行选项  kernel 升级内核  默认安装 wireguard
if [[ $# > 0 ]];then
	key="$1"
	case $key in
		kernel)
		update_kernel
		;;
	esac
else
	wireguard_install
	# 定义修改端口号，适合已经安装WireGuard而不想改端口
port=9999
mtu=1420
ip_list=(2 5 8 178 186 118 158 198 168 9)

#定义文字颜色
Green="\033[32m"  && Red="\033[31m" && GreenBG="\033[42;37m" && RedBG="\033[41;37m" && Font="\033[0m"

#定义提示信息
Info="${Green}[信息]${Font}"  &&  OK="${Green}[OK]${Font}"  &&  Error="${Red}[错误]${Font}"

# 检查是否安装 WireGuard
if [ ! -f '/usr/bin/wg' ]; then
    clear
    echo -e "${RedBG}   一键安装 WireGuard 脚本 For Debian_9 Ubuntu Centos_7   ${Font}"
    echo -e "${GreenBG}     开源项目：https://github.com/hongwenjun/vps_setup    ${Font}"
    help_info
    echo -e "${Red}::  检测到你的vps没有安装wireguard，请选择复制一键脚本安装   ${Font}"
    exit 1
fi

host=$(hostname -s)
# 获得服务器ip，自动获取
if [ ! -f '/usr/bin/curl' ]; then
    apt update && apt install -y curl
fi
serverip=$(curl -4 ip.sb)

# 安装二维码插件
if [ ! -f '/usr/bin/qrencode' ]; then
    apt -y install qrencode
fi


# wg配置文件目录 /etc/wireguard
mkdir -p /etc/wireguard
chmod 777 -R /etc/wireguard
cd /etc/wireguard

# 然后开始生成 密匙对(公匙+私匙)。
wg genkey | tee sprivatekey | wg pubkey > spublickey
wg genkey | tee cprivatekey | wg pubkey > cpublickey

# 生成服务端配置文件
cat <<EOF >wg0.conf
[Interface]
PrivateKey = $(cat sprivatekey)
Address = 10.0.0.1/24, fd10:db31:203:ab31::1/64 
ListenPort = $port
DNS = 8.8.8.8, 2001:4860:4860::8888 
MTU = $mtu
[Peer]
PublicKey = $(cat cpublickey)
AllowedIPs = 10.0.0.188/32, fd10:db31:203:ab31::2
EOF

# 生成简洁的客户端配置
cat <<EOF >client.conf
[Interface]
PrivateKey = $(cat cprivatekey)
Address = 10.0.0.188/24
Address = fd10:db31:203:ab31::2/64
DNS = 8.8.8.8, 2001:4860:4860::8888
#  MTU = $mtu
#  PreUp =  start   .\route\routes-up.bat
#  PostDown = start  .\route\routes-down.bat
[Peer]
PublicKey = $(cat spublickey)
Endpoint = $serverip:$port
AllowedIPs = 0.0.0.0/0, ::0/0
PersistentKeepalive = 25
EOF

# 添加 2-9 号多用户配置
for i in {2..9}
do
    ip=10.0.0.${ip_list[$i]}
    ip6=fd10:db31:203:ab31::${ip_list[$i]}
    wg genkey | tee cprivatekey | wg pubkey > cpublickey

    cat <<EOF >>wg0.conf
[Peer]
PublicKey = $(cat cpublickey)
AllowedIPs = $ip/32, $ip6
EOF

    cat <<EOF >wg_${host}_$i.conf
[Interface]
PrivateKey = $(cat cprivatekey)
Address = $ip/24
Address = $ip6/64
DNS = 8.8.8.8, 2001:4860:4860::8888
[Peer]
PublicKey = $(cat spublickey)
Endpoint = $serverip:$port
AllowedIPs = 0.0.0.0/0, ::0/0
PersistentKeepalive = 25
EOF
    cat /etc/wireguard/wg_${host}_$i.conf| qrencode -o wg_${host}_$i.png
done

#  vps网卡如果不是eth0，修改成实际网卡
ni=$(ls /sys/class/net | awk {print} | grep -e eth. -e ens. -e venet.)
if [ $ni != "eth0" ]; then
    sed -i "s/eth0/${ni}/g"  /etc/wireguard/wg0.conf
fi

# 重启wg服务器
wg-quick down wg0
wg-quick up wg0
fi
