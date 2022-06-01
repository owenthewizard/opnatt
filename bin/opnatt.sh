#!/usr/bin/env bash

# OPNsense has bash, so let's use it

source opnatt.conf
source opnatt-functions.sh

trap 'shutdown' SIGINT SIGQUIT SIGABRT SIGTERM

for mod in ${ng_modules[@]}; do
    log "loading $mod..."
    /sbin/kldload -n "$mod"
done

log "starting opnatt..."
log "configuration:"
log "  ONT_IF = $ONT_IF"
log "  RG_ETHER = $RG_ETHER"
log "  EAP_IDENTITY = $EAP_IDENTITY"

log "resetting netgraph..."
ng_clean

log "configuring EAP environment for supplicant mode..."
log "cabling should look like this:"
log "  ONT---[] [$ONT_IF]$HOST"

log "creating vlan node and ngeth0 interface..."
/usr/sbin/ngctl mkpeer "$ONT_IF:" vlan lower downstream
/usr/sbin/ngctl name "$ONT_IF:lower" vlan0
/usr/sbin/ngctl mkpeer vlan0: eiface vlan0 ether
/usr/sbin/ngctl msg vlan0: 'addfilter { vlan=0 hook="vlan0" }'
/usr/sbin/ngctl msg ngeth0: set "$RG_ETHER"

#log "enabling promisc for $ONT_IF..."

/sbin/ifconfig "$ONT_IF" ether "$RG_ETHER" -vlanhwtag -vlanhwfilter
/sbin/ifconfig "$ONT_IF" up promisc

log "starting wpa_supplicant..."

WPA_DAEMON_CMD="/usr/sbin/wpa_supplicant -Dwired -ingeth0 -B -C/var/run/wpa_supplicant -c/conf/opnatt/wpa/wpa_supplicant.conf"

# kill any existing wpa_supplicant process
wpa_pid=$(pgrep -f "wpa_supplicant.\*ngeth0")
if [[ -u "$wpa_pid" ]]; then 
    log "terminating existing wpa_supplicant on PID ${wpa_pid}..."
    kill "$wpa_pid"
fi

# start wpa_supplicant daemon
RES=$(eval ${WPA_DAEMON_CMD})
wpa_pid=$(pgrep -f "wpa_supplicant.\*ngeth0")
log "wpa_supplicant running on PID ${wpa_pid}..."

# Set WPA configuration parameters.
log "setting wpa_supplicant network configuration..."
wpa_cli set_network 0 identity \""$EAP_IDENTITY"\"
wpa_cli set_network 0 ca_cert \""$ca_cert"\"
wpa_cli set_network 0 client_cert \""$client_cert"\"
wpa_cli set_network 0 private_key \""$private_key"\"

# wait until wpa_cli has authenticated.
WPA_STATUS_CMD="wpa_cli status | grep 'suppPortStatus' | cut -d= -f2"
IP_STATUS_CMD="ifconfig ngeth0 | grep 'inet\ ' | cut -d' ' -f2"

log "waiting EAP for authorization..."

for i in {1..5}; do
    WPA_STATUS=$(eval ${WPA_STATUS_CMD})
    if [[ "$WPA_STATUS" = "Authorized" ]]; then
        log "EAP authorization completed..."
        IP_STATUS=$(eval ${IP_STATUS_CMD})
        if [[ -z "$IP_STATUS" ]] || [[ "$IP_STATUS" = "0.0.0.0" ]]; then
            log "no IP address assigned, force restarting DHCP..."
            /etc/rc.d/dhclient forcerestart ngeth0
            IP_STATUS=$(eval ${IP_STATUS_CMD})
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
