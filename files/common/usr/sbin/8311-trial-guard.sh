#!/bin/sh
# Started from rc.local. When this boot is a one-time trial of the other
# firmware bank (fw_setenv img_activate <bank>) and the stick does not stay
# reachable for management, reboot: U-Boot then falls back to commit_bank, so a
# bad trial upgrade can be undone without power cycling the stick.
#
# Reachable means omcid is running and the ping host (8311_ping_ip, default the
# LCT gateway) answers ping or, for routers that drop ICMP, ARP. A link that is
# merely up is not enough: after a failed omcid start the LCT can report
# carrier while its traffic never reaches the CPU. The same omcid has to stay
# reachable for HOLD seconds; an omcid crash on a trial boot is handled by
# 8311-omcid-supervise.sh, which reboots right away.
#
# 8311_trial_timeout: seconds to wait (default 600, at least the failsafe delay
# plus 180), 0 disables the guard. Committing the bank or a failsafe flag ends it.

_lib_8311 2>/dev/null || . /lib/8311.sh

HOLD=120

uptime_s() {
	cut -d. -f1 /proc/uptime
}

ACTIVE=$(active_fwbank)

trial() {
	COMMIT=$(fwenv_get "commit_bank")
	[ -n "$ACTIVE" ] && [ -n "$COMMIT" ] && [ "$ACTIVE" != "$COMMIT" ]
}

failsafe() {
	[ -f /root/.failsafe ] || [ -f /tmp/.failsafe ] || [ -f /ptconf/.failsafe ]
}

reachable() {
	local host dev
	host=$(get_8311_ping_host)
	[ -n "$host" ] || return 1
	ping -c 1 -W 2 "$host" >/dev/null 2>&1 && return 0
	dev=$(ip route get "$host" 2>/dev/null | sed -n 's/.* dev \([^ ]*\).*/\1/p')
	[ -n "$dev" ] && arping -q -c 1 -w 2 -I "$dev" "$host" >/dev/null 2>&1
}

trial || exit 0

TIMEOUT=$(fwenv_get_8311 "trial_timeout" "600")
case "$TIMEOUT" in
	""|*[!0-9]*) TIMEOUT=600 ;;
esac
if [ "$TIMEOUT" -eq 0 ]; then
	echo "Trial boot of bank $ACTIVE: guard disabled by 8311_trial_timeout=0" | to_console
	exit 0
fi
[ "$TIMEOUT" -le 3600 ] || TIMEOUT=3600

# omcid only starts after the failsafe delay
DELAY=$(fwenv_get_8311 "failsafe_delay" "15")
case "$DELAY" in
	""|*[!0-9]*) DELAY=15 ;;
esac
[ "$DELAY" -le 300 ] || DELAY=300
[ "$TIMEOUT" -ge $((DELAY + 180)) ] || TIMEOUT=$((DELAY + 180))

echo "Trial boot of bank $ACTIVE (commit_bank is $COMMIT): reverting unless management stays reachable for ${HOLD}s within ${TIMEOUT}s" | to_console

DEADLINE=$(($(uptime_s) + TIMEOUT))
GOOD_PID=
GOOD_SINCE=
while [ "$(uptime_s)" -lt "$DEADLINE" ]; do
	if ! trial; then
		echo "Trial boot of bank $ACTIVE: bank committed, guard done" | to_console
		exit 0
	fi
	if failsafe; then
		echo "Trial boot of bank $ACTIVE: failsafe flag present, not guarding" | to_console
		exit 0
	fi

	OMCID_PID=$(pidof omcid)
	if [ -n "$OMCID_PID" ] && reachable; then
		if [ "$OMCID_PID" != "$GOOD_PID" ]; then
			GOOD_PID=$OMCID_PID
			GOOD_SINCE=$(uptime_s)
		fi
		if [ $(($(uptime_s) - GOOD_SINCE)) -ge "$HOLD" ]; then
			echo "Trial boot of bank $ACTIVE stayed reachable for ${HOLD}s, keeping it until reboot; set commit_bank=$ACTIVE to make it permanent" | to_console
			exit 0
		fi
	else
		GOOD_PID=
		GOOD_SINCE=
	fi
	sleep 10
done

echo "Trial boot of bank $ACTIVE not reachable for ${HOLD}s within ${TIMEOUT}s, rebooting to commit_bank $COMMIT" | to_console
sleep 3
sync
reboot
