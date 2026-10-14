#!/bin/sh

_lib_8311 2>/dev/null || . /lib/8311.sh

pon_hash() {
    {
        ip li                  # 列出所有网络接口
        brctl show            # 显示网桥配置
    } | sha256sum | awk '{print $1}'
}
# One fw_printenv per round instead of one per variable: each call reads the
# U-Boot environment from flash, and this runs every 5 seconds.
config_hash() {
	fw_printenv 2>/dev/null |
		grep -E '^8311_(uvlan|fix_vlans|mvlansource|multicast_vlan|vlan_trans_rules|igmp_version|vlandebug|forceuvlan|forcemerule|force_me309)=' |
		sort | sha256sum | awk '{print $1}'
}

FIX_ENABLED=$(fwenv_get_8311 "fix_vlans")
[ "$FIX_ENABLED" -eq 0 ] 2>/dev/null && exit 0


FIXES=""
[ "$FIX_ENABLED" -ne 0 ] && FIXES="/usr/sbin/8311-fix-vlans.sh"

LAST_HASH=""
LAST_CFG_HASH=""
# The VLAN info shown in LuCI queries omcid through the OMCI pipe and was the
# most expensive part of the loop; refresh it every 12 rounds (~1 min) and
# right after the fix-vlans script ran.
VLAN_INFO_EVERY=12
ROUND=0

echo "8311 VLANs daemon: start monitoring" | to_console
sleep 10
while true ; do
	CMD="$FIXES"
	RAN_FIX=false
	if [ -n "$CMD" ] && [ -d "/sys/devices/virtual/net/gem-omci" ]; then
		HASH=$(pon_hash)
		CFG_HASH=$(config_hash)
		if [ "$HASH" != "$LAST_HASH" ] || [ "$CFG_HASH" != "$LAST_CFG_HASH" ]; then
			echo "8311 VLANs daemon: new configuration detected, ran fix-vlans script." | to_console
			flock /tmp/8311-fix-vlans.lock -c "$CMD" 2>&1
			LAST_HASH="$HASH"
			LAST_CFG_HASH="$CFG_HASH"
			RAN_FIX=true
		fi
	fi

	# the decode talks to omcid through the OMCI pipe, which blocks while
	# holding the pipe lock if omcid is not running (e.g. failsafe)
	if { $RAN_FIX || [ $((ROUND % VLAN_INFO_EVERY)) -eq 0 ]; } && [ -n "$(pidof omcid)" ]; then
		/usr/sbin/8311-tc-vlan-decode.sh > /tmp/8311-vlans.tmp && mv /tmp/8311-vlans.tmp /tmp/8311-vlans
	fi
	ROUND=$((ROUND + 1))

	sleep 5
done
