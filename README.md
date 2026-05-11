
# B3 — Masquerading verso Internet con Linux Network Namespace

**Autore:** Tiziano Bacaloni
**Codice variante:** B3
**Repo:** https://github.com/.../nv-progettino-B3-Bacaloni

---

## 1. Obiettivo

Il progettino costruisce un router NAT minimale su WSL2 Ubuntu 24.04:
un network namespace privato (`ns2`) con indirizzo IP non routable
(`10.0.0.101`) viene collegato al main namespace che agisce da gateway,
applicando IP masquerading (`iptables MASQUERADE`) per permettere al
traffico di uscire su Internet attraverso `eth0`. L'obiettivo formativo
è capire cosa fa Docker quando un container in una rete bridge esce su
Internet, e cosa fa un NAT gateway cloud in scala più grande.

---

## 2. Architettura





Il pacchetto attraversa **due livelli di NAT** in sequenza:
1. iptables MASQUERADE: `10.0.0.101` → IP di `eth0` (main namespace WSL)
2. NAT Hyper-V/Windows: IP di `eth0` → IP pubblico del router di casa

---

## 3. Prerequisiti

| Componente | Versione |
|---|---|
| WSL2 Ubuntu | 24.04 LTS |
| iproute2 | preinstallato |
| iptables | preinstallato |
| conntrack-tools | `sudo apt install conntrack` |
| python3 | preinstallato (per Estensione A) |
| curl | preinstallato |

---

## 4. Come riprodurre passo per passo

### 4.1 Setup

```bash
# Clona repository
git clone https://github.com/Tizian0Bacal0ni/nv-progettino--B3---Bacaloni-

# Per sicurezza entro nella repository
cd nv-progettino--B3---bacaloni-

# Serve per usare i comandi rapidi su
chmod +x Scripts/setup.sh
chmod +x Scripts/teardown.sh


# Lancia il setup
sudo ./Scripts/setup.sh
# Atteso: namespace ns2 creato, veth configurate, ip_forward=1,
#         regola MASQUERADE aggiunta su POSTROUTING
```

### 4.2 Verifica connettività base

```bash
# Test 1: raggiungibilità del gateway da ns2
sudo ip netns exec ns2 ping -c 3 10.0.0.100
# Atteso: 0% packet loss

# Test 2: connettività Internet via IP
sudo ip netns exec ns2 ping -c 3 8.8.8.8
# Atteso: 0% packet loss — il masquerading funziona

# Test 3: connettività Internet via hostname
sudo ip netns exec ns2 ping -c 3 www.google.com
# Atteso: 0% packet loss — DNS funziona via /etc/netns/ns2/resolv.conf
```

### 4.3 Verifica NAT in azione — iptables (7A)

```bash
# 
sudo iptables -t nat -L POSTROUTING -n -v

```
IP Masquerading ina zione : i pacchetti che arrivano dalla rete locale 10.0.0.0/24 e devono uscire su eth0 vengono MASQUERATI, per cui  il loro IP sorgente, privato, viene sostituito automaticamente con l'IP pubblico di eth0

### 4.4 Verifica NAT in azione — conntrack (7B)

```bash
sudo conntrack -L | grep 8.8.8.8

#Serve per stamapre la tabella altrimenti non si vede nulla 
sudo conntrack -L

```
Si interroga la tabella di connection tracking del kernel Linux (nf_conntrack) che elenca  tutti i flussi attualmente tracciati , e filtra  solo le entry che coinvolgono l'indirizzo IP 8.8.8.8 
così da verificare  se esiste, o è esistita di recente, una connessione attiva tra un host della rete locale e il resolver DNS pubblico di Google, ispezionando lo stato del NAT/conntrack in tempo reale. Serve a confermare che  DNS/NTP esca correttamente attraverso il gateway e che il MASQUERADE su eth0 vada bene



### 4.5 Verifica NAT in azione — tcpdump parallelo (7C)

Serve aprire tre terminali contemporaneamente (quello su cui si era + altri 2)

```bash
# Terminale A — pacchetti PRIMA del NAT
sudo tcpdump -n -i veth0 icmp
# Atteso: src=10.0.0.101 (IP privato, non tradotto)

# Terminale B — pacchetti DOPO il NAT
sudo tcpdump -n -i eth0 icmp
# Atteso: src=172.20.130.147 (IP già tradotto da MASQUERADE)

# Terminale C- invio pacchetti da SNIFFare
 sudo ip netns exec ns2 ping -c 2 8.8.8.8
```

Confrontando gli IP sorgente  si vede chiaramente la differenza agli estremi del canale di comunicazione creato
tra ns2t, evidenziando che nel mezzo il masquerade avviene in maniera corretta. 

### 4.6 Ablazione 1 — solo ip_forward, senza MASQUERADE

Serve avere aperti due terminali (quello su cui si lavora + un altro)
```bash
# Rimuovi MASQUERADE
sudo iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE

# Avvio dello sniffer sul terminale di lavoro
sudo tcpdump -n -i eth0 icmp

# Run test sul terminale B
sudo ip netns exec ns2 ping -c 3 8.8.8.8

# Ripristino
sudo iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
```
A conferma di quanto accennato al punto precedente, in questo caso l'eliminazione del MAQUERADE dalla tabella NAT DI iptables
impedisce la conclusione della comunicazione: questo perchè l'inidirzzo con cui i pacchetti passano da veth0 a eth0,
attraverso il canale di comunicazione tra i due spazi, rimane identico, per cui rimane **privato** e per tanto invisibile
agli occhi della rete INternet


### 4.7 Ablazione 2 — solo MASQUERADE, senza ip_forward

Servono 3 terminali: quello di lavoro + altri 2
```bash
# Disabilita ip_forward
sudo sysctl -w net.ipv4.ip_forward=0

# Attivazione sniffer lato veth0 (estremità del cavo interna a namespace)
 sudo tcpdump -n -i veth0 icmp

#ATtivazione sniffer lato eth0 ( interfaccia che punta verso internet)
 sudo tcpdump -n -i eth0 icmp

# Ping a google sul Terminale C
sudo ip netns exec ns2 ping -c 3 8.8.8.8

# Ripristina
sudo sysctl -w net.ipv4.ip_forward=1
```
Il test chiaramente fallisce, nel senso che lo sniffer interno a ns2 vede i pacchetti con IP di partenza privato perchè escono da ns2 verso 
il mainspace passando da li. Al contrario eth0  non vede nulla e registra solo silenzion perché non gli vengono forwardati: nonostante
il MASQUERADE sia attivo il kernel droppa i pacchetti prima che si attivi la carena POSTROUTING di iptables


### 4.8 Estensione A — DNAT per esporre un servizio in ns2

```bash
# 1. Pulisco regole precedenti per evitare duplicati, che mi hanno dato parecchi problemi ma non ho capito ancora come mai
sudo iptables -t nat -F
sudo iptables -F FORWARD

# 2. Attivo, IP forwarding --> l'ho fatto anche prima ma preferisco duplicarlo per essere più sicuro quando vado a fare la Demo visto che soesso me lo scordo
sudo sysctl -w net.ipv4.ip_forward=1

# 3. Regola DNAT per traffico in ingresso 
sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 \
  -j DNAT --to-destination 10.0.0.101:8000

# 4. Hairpin NAT--> senza questa non risucivo ed il curl falliva in continuazione 
sudo iptables -t nat -A OUTPUT -p tcp --dport 8080 \
  -j DNAT --to-destination 10.0.0.101:8000

# 5. MASQUERADE per tutto il discorso visto prima
sudo iptables -t nat -A POSTROUTING -d 10.0.0.101 -p tcp --dport 8000 \
  -j MASQUERADE

# 6. Forward t--> Garantiscono che i pacchetti DNAT-ati possano effettivamente attraversare l'host
sudo iptables -A FORWARD -i veth0 -j ACCEPT
sudo iptables -A FORWARD -o veth0 -j ACCEPT

# 7. Verifica che il server sia vivo in ns2
echo "[*] Verifica server in ns2..."
sudo ip netns exec ns2 ss -tlnp | grep 8000 \
  && echo "[OK] Server attivo" \
  || echo "[WARN] Server non attivo, riavvio..."

# 8. Test
echo ""
echo "[*] Test curl..."
curl -v http://10.0.0.100:8080
```

Il test dimostra come usare DNAT per rendere accessibile dall'esterno un servizio che gira all'interno di un network namespace isolato (ns2), simulando ciò che fa un router o firewall in port forwarding. Il namespace è opaco per chi opera al di fuori della subnet virtuale: senza regole esplicite, nessun pacchetto esterno raggiunge il servizio interno. L'unico modo per esporlo è configurare il main namespace come gateway NAT, abilitando il forwarding kernel e riscrivendo la destinazione dei pacchetti — esattamente il meccanismo usato da Docker per pubblicare le porte dei container tramite iptables.


### 4.9 Estensione B — ns2 e ns3 isolati ma entrambi con Internet

```bash
# Crea ns3 con subnet separata
sudo ip netns add ns3
sudo ip link add veth2 type veth peer name veth3
sudo ip link set veth3 netns ns3
sudo ip addr add 10.0.1.100/24 dev veth2 && sudo ip link set veth2 up
sudo ip netns exec ns3 ip addr add 10.0.1.101/24 dev veth3
sudo ip netns exec ns3 ip link set veth3 up && sudo ip netns exec ns3 ip link set lo up
sudo ip netns exec ns3 ip route add default via 10.0.1.100
sudo iptables -t nat -A POSTROUTING -s 10.0.1.0/24 -o eth0 -j MASQUERADE

# Isolamento inter-namespace
sudo iptables -A FORWARD -i veth0 -o veth2 -j DROP
sudo iptables -A FORWARD -i veth2 -o veth0 -j DROP

# Verifica: entrambi escono su Internet
sudo ip netns exec ns2 ping -c 2 8.8.8.8   # 0% loss
sudo ip netns exec ns3 ping -c 2 8.8.8.8   # 0% loss

# Verifica: non si vedono tra loro
sudo ip netns exec ns2 ping -c 2 10.0.1.101  # 100% loss
sudo ip netns exec ns3 ping -c 2 10.0.0.101  # 100% loss
```
Creo un secondo namespace privato (ns3) con la propria subnet, lo connetto a Internet tramite NAT, ma lo isol0 completamente da ns2 così che, pur essendo connessi tra loro, non si vedano e non possano parlarsi , nonostante al contrario siano entrambi connessi all'esterno, tipo due VLAN dietro lo stesso router.

### 4.10 Teardown

```bash
sudo ./scripts/teardown.sh
# Atteso: namespace ns2 (e ns3 se creato) eliminati, regole iptables
#         ripulite, /etc/netns/ rimosso
```

---

## 5. Verifica del funzionamento

| Test | Comando | Output atteso |
|---|---|---|
| Gateway raggiungibile | `ip netns exec ns2 ping -c 3 10.0.0.100` | 0% loss |
| Internet via IP | `ip netns exec ns2 ping -c 3 8.8.8.8` | 0% loss |
| Internet via hostname | `ip netns exec ns2 ping -c 3 www.google.com` | 0% loss |
| MASQUERADE attiva | `iptables -t nat -L POSTROUTING -n -v` | pkts/bytes > 0 |
| Entry conntrack | `conntrack -L \| grep 8.8.8.8` | 2 flow entries |
| Ablazione 1 | ping senza MASQUERADE | 100% loss |
| Ablazione 2 | ping senza ip_forward | 100% loss |
| DNAT (Ext. A) | `curl http://10.0.0.100:8080` | listing HTML |
| Isolamento ns3 (Ext. B) | `ip netns exec ns2 ping 10.0.1.101` | 100% loss |

---

## 6. Riflessioni e punti aperti

**Quanti livelli di NAT attraversa un pacchetto da ns2 a 8.8.8.8?**
Due: il MASQUERADE del main namespace WSL traduce `10.0.0.101` nell'IP
di `eth0`; il NAT di Windows/Hyper-V traduce poi quell'IP nell'IP
pubblico del router. Un pacchetto generato da ns2 attraversa quindi
due traduzioni d'indirizzo prima di raggiungere Internet.

**Rischio di MASQUERADE "all-out" senza `-s`:**
Senza limitare la regola a `-s 10.0.0.0/24`, essa si applica a tutto
il traffico in uscita su `eth0`, incluso quello originato dal main
namespace. In ambienti con routing multi-subnet (es. VPC peering cloud)
questo maschera traffico che dovrebbe essere instradato normalmente,
rompendo le sessioni esistenti al prossimo flush di conntrack.

**Analogia con NAT gateway cloud:**
Concettualmente identico: una macchina con `ip_forward=1` e una regola
SNAT sull'interfaccia di uscita. AWS NAT Gateway fa esattamente questo,
ma su hardware dedicato con conntrack distribuito, Elastic IP statico
e ridondanza geografica automatica. La differenza è ingegneristica,
non concettuale.

**Perché MASQUERADE non basta per esporre un servizio in ns2:**
MASQUERADE è Source NAT — traduce l'IP sorgente dei pacchetti in uscita.
Per accettare connessioni in entrata serve Destination NAT (DNAT) nella
catena PREROUTING, che traduce l'IP destinazione dei pacchetti in arrivo
verso l'IP privato del servizio. I due meccanismi sono complementari e
indipendenti, come dimostrato nell'Estensione A.

**Difficoltà incontrate:**
- Il DNAT verso `127.0.0.1` non funziona perché il traffico loopback
  bypassa PREROUTING; soluzione: usare direttamente l'IP di `veth0`
  (`10.0.0.100`) oppure abilitare `route_localnet` e aggiungere una
  regola OUTPUT.
- Con `ip_forward=1` e due subnet configurate, il main namespace forwarda
  automaticamente tra ns2 e ns3; l'isolamento richiede regole DROP
  esplicite sulla catena FORWARD.
- In assenza di una corretta pulizia della shell di comando in caso di lavoro
  non consecutivo ma ,ad esempio, spalamato su più giorni, la quantità di errori incontrata
  aumenta in modo rilevante: al punto 4.8 ad esempio si incorre nell'errore di vedere occupata la porta
  800 e, per poter procedere, bisogna predisporre un repulisti generale.
-Collegato al punto precedente

---

## 7. Riferimenti

- [Linux ip-netns manpage](https://man7.org/linux/man-pages/man8/ip-netns.8.html)
- [iptables-extensions manpage](https://man7.org/linux/man-pages/man8/iptables-extensions.8.html)
- [conntrack-tools user manual](https://conntrack-tools.netfilter.org/manual.html)
- [Fedora Magazine — NAT part 2: the conntrack tool](https://fedoramagazine.org/network-address-translation-part-2-the-conntrack-tool/)
- B3-Bacaloni.md — documento di specifica del progettino
- Slide del corso: deck Namespace e Masquerading
