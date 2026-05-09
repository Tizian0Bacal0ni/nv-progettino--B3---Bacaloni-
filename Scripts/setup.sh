#!/usr/bin/env bash
# setup.sh — Crea l'ambiente NAT/masquerading per il progettino B3
# Tiziano Bacaloni — variante B3
# Uso: sudo ./scripts/setup.sh

set -euo pipefail

echo "[1/7] Creazione namespace ns2..."
ip netns add ns2

echo "[2/7] Creazione coppia veth (veth0 <-> veth1)..."
ip link add veth0 type veth peer name veth1
ip link set veth1 netns ns2

echo "[3/7] Configurazione veth0 nel main namespace..."
ip addr add 10.0.0.100/24 dev veth0
ip link set veth0 up

echo "[4/7] Configurazione veth1 e loopback in ns2..."
ip netns exec ns2 ip addr add 10.0.0.101/24 dev veth1
ip netns exec ns2 ip link set veth1 up
ip netns exec ns2 ip link set lo up

echo "[5/7] Configurazione default route in ns2..."
ip netns exec ns2 ip route add default via 10.0.0.100

echo "[6/7] Abilitazione ip_forward nel main namespace..."
sysctl -w net.ipv4.ip_forward=1

echo "[7/7] Aggiunta regola iptables MASQUERADE..."
iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE

echo "[DNS] Configurazione resolv.conf per ns2..."
mkdir -p /etc/netns/ns2
echo "nameserver 8.8.8.8" > /etc/netns/ns2/resolv.conf

echo ""
echo "=== Setup completato ==="
echo "  ns2 IP:       10.0.0.101"
echo "  gateway:      10.0.0.100 (veth0)"
echo "  ip_forward:   $(cat /proc/sys/net/ipv4/ip_forward)"
echo "  MASQUERADE:   attiva su POSTROUTING -> eth0"
echo ""
echo "Test rapido:"
echo "  sudo ip netns exec ns2 ping -c 3 8.8.8.8"
