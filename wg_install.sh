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
    read -p "Choose your main port (80, 443, 8443, 3785 are included by default, select among them): " -e -i 3785 port
    read -p "MTU (max is 1420, recommended for udp2raw 1200): " -e -i 1420 mtu
    read -p "Purge snapd and unattended-upgrades with their dependencies (N/y): " -e -i "n" purge
    case ${purge:0:1} in
        y|Y )
            # garbage cleanup
            apt purge snapd unattended-upgrades -y
            apt --purge autoremove -y
        ;;
        * )
        ;;
    esac
    dns="1.1.1.1"
    
    # forwarding rules
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/10-ipv4-forward.conf
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # requirements
    version=$(cat /etc/os-release | awk -F '[".]' '$1=="VERSION="{print $2}')
    apt update
    apt upgrade -y
    apt install ifupdown wireguard resolvconf -y

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
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $eth -j MASQUERADE; iptables -t nat -A PREROUTING -i $eth -d $serverip -p udp -m multiport --dports 80,443,8443 -j REDIRECT --to-ports $port; iptables -A PREROUTING -t nat -i $eth -p udp --dport 53 -j DNAT --to-destination $dns:53
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $eth -j MASQUERADE; iptables -t nat -D PREROUTING -i $eth -d $serverip -p udp -m multiport --dports 80,443,8443 -j REDIRECT --to-ports $port; iptables -D PREROUTING -t nat -i $eth -p udp --dport 53 -j DNAT --to-destination $dns:53
ListenPort = $port
MTU = $mtu

[Peer]
PublicKey = $c2
AllowedIPs = 10.0.0.2/32
EOF
    
cat > /etc/wireguard/client.conf <<-EOF
[Interface]
PrivateKey = $c1
Address = 10.0.0.2/24
DNS = 10.0.0.1
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
}

start_menu(){
    clear
    green " ===================================="
    green " Wireguard one-click setup          "
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
