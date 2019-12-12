#!/bin/bash

function green(){
    echo -e "\033[32m\033[01m $1 \033[0m"
}
function red(){
    echo -e "\033[31m\033[01m $1 \033[0m"
}
function yellow(){
    echo -e "\033[33m\033[01m $1 \033[0m"
}

install(){
    # user input settings
    read -p "Port (443 may be inspected, test others): " -e -i 443 port
    read -p "MTU (recommended for udp2raw 1300, max is 1420): " -e -i 1300 mtu
    dns="1.1.1.1"
    read -p "Password: " -e -i 443 port
    
    # forwarding rules
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/10-ipv4-forward.conf
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # requirements and garbage cleanup
    echo "Downloading udp2raw..."
    wget https://github.com/wangyu-/udp2raw-tunnel/releases/download/20190716.test.0/udp2raw_binaries.tar.gz && tar xvf udp2raw_binaries.tar.gz
    version=$(cat /etc/os-release | awk -F '[".]' '$1=="VERSION="{print $2}')
    apt purge snapd unattended-upgrades -y
    add-apt-repository ppa:wireguard/wireguard
    apt update
    apt upgrade -y
    apt install ifupdown -y
    apt install wireguard resolvconf -y
    apt --purge autoremove -y
    
    # keys and settings
    cd /etc/wireguard
    umask 077
    wg genkey | tee sprivatekey | wg pubkey > spublickey
    wg genkey | tee cprivatekey | wg pubkey > cpublickey
    s1=$(cat sprivatekey)
    s2=$(cat spublickey)
    c1=$(cat cprivatekey)
    c2=$(cat cpublickey)
    serverip=$(curl ipv4.icanhazip.com)
    eth=$(ls /sys/class/net | awk '/^e/{print}')
    
cat > /etc/wireguard/wg0.conf <<-EOF
[Interface]
PrivateKey = $s1
Address = 10.0.0.1/24
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $eth -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $eth -j MASQUERADE
ListenPort = $port
DNS = $dns
MTU = $mtu

[Peer]
PublicKey = $c2
AllowedIPs = 10.0.0.2/32
EOF
    
cat > /etc/wireguard/client.conf <<-EOF
[Interface]
PrivateKey = $c1
Address = 10.0.0.2/24
DNS = $dns
MTU = $mtu

[Peer]
PublicKey = $s2
Endpoint = $serverip:$port
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    
    wg-quick up wg0
    systemctl enable wg-quick@wg0
    
    green "Running on UDP: DNS $dns, MTU $mtu"
    green "Now download /etc/wireguard/client.conf"
    green "It's recommended to reboot in order to finish the updates"
    
# server
./udp2raw_amd64 -s -l 0.0.0.0:443 -r 127.0.0.1:7777 -a -k "password" --raw-mode faketcp --cipher-mode none --fix-gro

# client
./udp2raw_mp.exe -c -l 0.0.0.0:3333 -r $serverip:443 -k "password" --raw-mode easy-faketcp --cipher-mode none --fix-gro

}

start_menu(){
    clear
    green " ===================================="
    green " Wireguard + udp2raw one-click setup          "
    green " Requires： Ubuntu >= 18.04 + root access  "
    green " About： based on TunSafe one-click setup by atrandys "
    green "https://github.com/atrandys/tunsafe"
    green " ===================================="
    echo
    green " 1. Wireguard installation"
    green " 2. Echo client configuration"
    yellow " 0. Exit"
    echo
    read -p "Please enter the number: " num
    case "$num" in
        1)
            install
        ;;
        2)
            cat /etc/wireguard/client.conf
        ;;
        0)
            exit 1
        ;;
        *)
            clear
            red "Incorrect number"
            sleep 1s
            start_menu
        ;;
    esac
}

start_menu
