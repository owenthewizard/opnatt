#!/usr/bin/env bash

# OPNsense **DOESN'T** have bash, so make sure you install it!

source /conf/opnatt/bin/opnatt.conf
source /conf/opnatt/bin/opnatt-functions.sh

log "starting opnatt..."
log "configuration:"
log "  ONT_IF = $ONT_IF"
log "  RG_ETHER = $RG_ETHER"
log "  EAP_IDENTITY = $EAP_IDENTITY"

if [[ "$USE_NETGRAPH" -eq 1 ]]; then
    log "configuring supplicant for netgraph..."
    WAN_IF="ngeth0"
    log "cabling should look like this:"
    log <<EOF
┌──────────┐
│ OPNsense │
├───┬──┬───┤
│WAN│  │LAN│
└─┬─┘  └─┬─┘
  │      │
┌─┴─┐    │
│ONT│    .
└───┘
EOF

    trap 'shutdown' SIGINT SIGQUIT SIGABRT SIGTERM

    # shellcheck disable=SC2068
    for mod in ${ng_modules[@]}; do
        log "loading $mod..."
        /sbin/kldload -n "$mod"
    done

    log "resetting netgraph..."
    ng_clean

    log "creating vlan node and ngeth0 interface..."
    /usr/sbin/ngctl mkpeer "$ONT_IF:" vlan lower downstream
    /usr/sbin/ngctl name "$ONT_IF:lower" vlan0
    /usr/sbin/ngctl mkpeer vlan0: eiface vlan0 ether
    /usr/sbin/ngctl msg vlan0: 'addfilter { vlan=0 hook="vlan0" }'
    /usr/sbin/ngctl msg ngeth0: set "$RG_ETHER"

    log "enabling promisc for $ONT_IF and disabling vlanhwfilter..."
    /sbin/ifconfig "$ONT_IF" up promisc -vlanhwtag -vlanhwfilter
else
    log "configuring supplicant for switch..."
    WAN_IF="$ONT_IF"
    log "cabling should look like this:"
    log <<EOF
  ┌──────────┐
  │ OPNsense │
  ├───┬──┬───┤
  │WAN│  │LAN│
  └─┬─┘  └─┬─┘
    └─┐  ┌─┘
┌───┬─┴─┬┴┬─┬─┐
│100│100│1│1│1│
└─┬─┴───┴─┴┬┴┬┘
  │        │ │
┌─┴─┐      │ │
│ONT│      . .
└───┘
EOF
    log "(example cabling shows switch ports used for LAN)"
fi

log "spoofing $ONT_IF MAC..."
/sbin/ifconfig "$ONT_IF" ether "$RG_ETHER"

log "starting wpa_supplicant..."

# kill any existing wpa_supplicant process
wpa_pid=$(pgrep -f "wpa_supplicant.\"\*\"$WAN_IF")
if [[ -n "$wpa_pid" ]]; then
    log "terminating existing wpa_supplicant on PID ${wpa_pid}..."
    kill "$wpa_pid"
fi

# start wpa_supplicant daemon
/usr/sbin/wpa_supplicant -Dwired -ingeth0 -B -C/var/run/wpa_supplicant -c/conf/opnatt/wpa/wpa_supplicant.conf
wpa_pid=$(pgrep -f "wpa_supplicant.\"\*\"$WAN_IF")
log "wpa_supplicant running on PID ${wpa_pid}..."

# Set WPA configuration parameters.
log "setting wpa_supplicant network configuration..."
wpa_cli set_network 0 identity \""$EAP_IDENTITY"\"
wpa_cli set_network 0 ca_cert \""$ca_cert"\"
wpa_cli set_network 0 client_cert \""$client_cert"\"
wpa_cli set_network 0 private_key \""$private_key"\"

wpa_cli logon

# wait until wpa_cli has authenticated.
log "waiting EAP for authorization..."

for i in {1..5}; do
    if [[ "$(wpa_status)" = "Authorized" ]]; then
        log "EAP authorization completed..."
        IP_STATUS="$(ip_status)"
        if [[ -z "$IP_STATUS" ]] || [[ "$IP_STATUS" = "0.0.0.0" ]]; then
            log "no IP address assigned, force restarting DHCP..."
            /etc/rc.d/dhclient forcerestart "$WAN_IF"
            IP_STATUS="$(ip_status)"
        fi
        log "IP address is ${IP_STATUS}..."
        break
    else
        n=$((i * 4))
        log "not authorized, sleeping for ${n} seconds... (${i}/5)"
        sleep $((i * 4))
    fi
done

log "ngeth0 should now be available to configure as your WAN..."
log "done!"
