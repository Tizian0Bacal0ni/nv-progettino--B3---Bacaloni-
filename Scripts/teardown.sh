#!/usr/bin/env bash
# teardown.sh — Rimuove tutto l'ambiente NAT/masquerading del progettino B3
# Tiziano Bacaloni — variante B3
# Uso: sudo ./scripts/teardown.sh


#!/usr/bin/env bash
# teardown.sh — Rimuove tutto l'ambiente NAT/masquerading del progettino B3

set -euo pipefail   


echo "[1/8] Rimozione regola iptables MASQUERADE su POSTROUTING..."
iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE \
  2>/dev/null && echo "  OK" || echo "  (non presente, skip)"

echo "[2/8] Rimozione regola DNAT su PREROUTING (Estensione A)..."
iptables -t nat -D PREROUTING -p tcp --dport 8080 \
  -j DNAT --to 10.0.0.101:8000 \
  2>/dev/null && echo "  OK" || echo "  (non presente, skip)"

echo "[3/8] Rimozione regola DNAT su OUTPUT (Estensione A loopback)..."
iptables -t nat -D OUTPUT -p tcp -d 127.0.0.1 --dport 8080 \
  -j DNAT --to 10.0.0.101:8000 \
  2>/dev/null && echo "  OK" || echo "  (non presente, skip)"

echo "[4/8] Rimozione regole FORWARD per veth0 (Estensione A/B)..."
iptables -D FORWARD -i veth0 -j ACCEPT \
  2>/dev/null && echo "  OK veth0 in" || echo "  (non presente, skip)"
iptables -D FORWARD -o veth0 -j ACCEPT \
  2>/dev/null && echo "  OK veth0 out" || echo "  (non presente, skip)"

echo "[5/8] Rimozione regole DROP inter-namespace (Estensione B)..."
iptables -D FORWARD -i veth0 -o veth2 -j DROP \
  2>/dev/null && echo "  OK ns2->ns3" || echo "  (non presente, skip)"
iptables -D FORWARD -i veth2 -o veth0 -j DROP \
  2>/dev/null && echo "  OK ns3->ns2" || echo "  (non presente, skip)"

echo "[6/8] Rimozione namespace ns2 (rimuove automaticamente veth1)..."
ip netns del ns2 \
  2>/dev/null && echo "  OK" || echo "  (non presente, skip)"

echo "[7/8] Rimozione namespace ns3 e veth2 (Estensione B)..."
ip netns del ns3 \
  2>/dev/null && echo "  OK ns3" || echo "  (non presente, skip)"
ip link del veth2 \
  2>/dev/null && echo "  OK veth2" || echo "  (non presente, skip)"

echo "[8/8] Rimozione /etc/netns/ns2 (DNS override)..."
rm -rf /etc/netns/ns2 \
  && echo "  OK" || echo "  (non presente, skip)"

echo "[9/8] Svuoto contrack"
sudo conntrack -F

# Per essere sicuro

sudo iptables -t nat -F
sudo iptables -t nat -L POSTROUTING -n -v  # verifica: deve essere vuota

#Esco dalla cartella del progetto
cd ~

#La rimuvoo
rm -rf nv-progettino--B3---Bacaloni-

echo ""
echo "=== Teardown completato ==="
echo "Verifica stato residuo:"
echo "  ip netns list              -> deve essere vuoto"
echo "  ip link show veth0         -> deve dare 'not found'"
echo "  iptables -t nat -L -n -v   -> nessuna regola B3"
