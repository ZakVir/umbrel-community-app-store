#!/bin/bash
set -euo pipefail

# Egress firewall for Antigravity Server on Umbrel
# Allows only DNS + HTTPS to Antigravity model APIs, blocks all other outbound.
# Set AGY_EGRESS_RESTRICT=0 to disable.
# Set AGY_EGRESS_ALLOW_HOSTS to override allowed hosts (comma-separated).

if [ "${AGY_EGRESS_RESTRICT:-1}" = "0" ] || [ "${AGY_EGRESS_RESTRICT:-1}" = "false" ]; then
  echo "[egress] AGY_EGRESS_RESTRICT=0, skipping firewall"
  exit 0
fi

# Check if we have NET_ADMIN capability
if ! iptables -L >/dev/null 2>&1; then
  echo "[egress] WARNING: iptables not available (missing NET_ADMIN), cannot restrict egress"
  exit 0
fi

echo "[egress] Setting up restrictive egress (only Antigravity model APIs)..."

# Default allowed hosts for model requests + OAuth (required for Google sign-in)
ALLOW_HOSTS="${AGY_EGRESS_ALLOW_HOSTS:-generativelanguage.googleapis.com,daily-cloudcode-pa.googleapis.com,accounts.google.com,oauth2.googleapis.com,storage.googleapis.com}"

# Flush existing OUTPUT rules (if any) - we will append, not flush all, to avoid breaking existing Docker rules
# Instead, create a custom chain
iptables -N AGY_EGRESS 2>/dev/null || iptables -F AGY_EGRESS

# Allow loopback
iptables -A AGY_EGRESS -o lo -j ACCEPT
# Allow established/related
iptables -A AGY_EGRESS -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# Allow DNS (UDP and TCP 53) - needed for host resolution
iptables -A AGY_EGRESS -p udp --dport 53 -j ACCEPT
iptables -A AGY_EGRESS -p tcp --dport 53 -j ACCEPT
# Allow DHCP? not needed
# Allow ICMP (ping) for diagnostics (optional, but helpful)
iptables -A AGY_EGRESS -p icmp -j ACCEPT
# Allow traffic to Docker bridge and LAN (for app_proxy and local network)
# Umbrel Docker network is 10.21.0.0/16, host LAN is typically 10.0.0.0/24 or 192.168.0.0/16
iptables -A AGY_EGRESS -d 10.21.0.0/16 -j ACCEPT
iptables -A AGY_EGRESS -d 10.0.0.0/8 -j ACCEPT
iptables -A AGY_EGRESS -d 172.16.0.0/12 -j ACCEPT
iptables -A AGY_EGRESS -d 192.168.0.0/16 -j ACCEPT
iptables -A AGY_EGRESS -d 127.0.0.0/8 -j ACCEPT

# For each allowed host, resolve and allow its IPs on 443
IFS=',' read -ra HOSTS <<< "$ALLOW_HOSTS"
for host in "${HOSTS[@]}"; do
  host=$(echo "$host" | xargs) # trim
  [ -z "$host" ] && continue
  echo "[egress] Resolving $host..."
  # Try getent, then dig, then host
  ips=""
  if command -v getent >/dev/null 2>&1; then
    ips=$(getent ahosts "$host" 2>/dev/null | awk '{print $1}' | sort -u || true)
  fi
  if [ -z "$ips" ] && command -v getent >/dev/null 2>&1; then
    ips=$(getent hosts "$host" 2>/dev/null | awk '{print $1}' | sort -u || true)
  fi
  if [ -z "$ips" ] && command -v dig >/dev/null 2>&1; then
    ips=$(dig +short "$host" 2>/dev/null | grep -E '^[0-9.]+$' || true)
  fi
  if [ -z "$ips" ]; then
    echo "[egress] WARNING: could not resolve $host, allowing via string match fallback (port 443 only)"
    # Fallback: allow 443 with string match on SNI (requires iptables string module)
    # This is best-effort; if it fails, the container will still be able to connect via IP after DNS
    iptables -A AGY_EGRESS -p tcp --dport 443 -m string --string "$host" --algo kmp -j ACCEPT 2>/dev/null || true
    continue
  fi
  for ip in $ips; do
    # Only IPv4 for now; IPv6 would need ip6tables
    if echo "$ip" | grep -q ":"; then
      # IPv6
      if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -A AGY_EGRESS -d "$ip" -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
        echo "[egress] Allow $host ($ip) tcp/443 (v6)"
      fi
    else
      iptables -A AGY_EGRESS -d "$ip" -p tcp --dport 443 -j ACCEPT
      echo "[egress] Allow $host ($ip) tcp/443"
    fi
  done
done

# Log dropped packets (optional, rate limited)
iptables -A AGY_EGRESS -m limit --limit 3/min -j LOG --log-prefix "[AGY_EGRESS DROP] " --log-level 4 2>/dev/null || true

# Final DROP for everything else
iptables -A AGY_EGRESS -j DROP

# Insert our chain at top of OUTPUT (if not already)
if ! iptables -C OUTPUT -j AGY_EGRESS 2>/dev/null; then
  iptables -I OUTPUT 1 -j AGY_EGRESS
fi
if command -v ip6tables >/dev/null 2>&1; then
  ip6tables -N AGY_EGRESS 2>/dev/null || ip6tables -F AGY_EGRESS
  ip6tables -A AGY_EGRESS -o lo -j ACCEPT
  ip6tables -A AGY_EGRESS -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  ip6tables -A AGY_EGRESS -p udp --dport 53 -j ACCEPT
  ip6tables -A AGY_EGRESS -p tcp --dport 53 -j ACCEPT
  ip6tables -A AGY_EGRESS -j DROP 2>/dev/null || true
  if ! ip6tables -C OUTPUT -j AGY_EGRESS 2>/dev/null; then
    ip6tables -I OUTPUT 1 -j AGY_EGRESS 2>/dev/null || true
  fi
fi

echo "[egress] Firewall active. Allowed hosts: $ALLOW_HOSTS"
echo "[egress] Current rules:"
iptables -L AGY_EGRESS -v -n 2>&1 | head -40 || true

# Background job to refresh DNS every 5 minutes (in case Google IPs change)
(
  while true; do
    sleep 300
    echo "[egress] Refreshing allowed IPs..."
    for host in "${HOSTS[@]}"; do
      host=$(echo "$host" | xargs)
      [ -z "$host" ] && continue
      ips=$(getent ahosts "$host" 2>/dev/null | awk '{print $1}' | sort -u || true)
      for ip in $ips; do
        if echo "$ip" | grep -q ":"; then continue; fi
        iptables -C AGY_EGRESS -d "$ip" -p tcp --dport 443 -j ACCEPT 2>/dev/null || iptables -I AGY_EGRESS 5 -d "$ip" -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
      done
    done
  done &
)

exit 0
