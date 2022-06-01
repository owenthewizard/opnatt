log() {
    /usr/bin/logger -s -t "opnatt" "$@"
}

function ng_clean() {
    /usr/sbin/ngctl shutdown waneapfilter: &> /dev/null
    /usr/sbin/ngctl shutdown laneapfilter: &> /dev/null
    /usr/sbin/ngctl shutdown "$ONT_IF:" &> /dev/null
    /usr/sbin/ngctl shutdown o2m: &> /dev/null
    /usr/sbin/ngctl shutdown vlan0: &> /dev/null
    /usr/sbin/ngctl shutdown ngeth0: &> /dev/null
}

function bail() {
    log "Encountered an error, exiting!"
    log "You will NOT have WAN connectivity!"
    ng_clean
    exit 1
}

function shutdown() {
    log "Caught a termination signal, quiting!"
    ng_clean
    exit 0
}
