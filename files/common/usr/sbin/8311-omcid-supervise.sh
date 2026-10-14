#!/bin/sh
# procd runs omcid through this script (see /etc/init.d/omcid.sh):
#   8311-omcid-supervise.sh <omcid binary> [omcid arguments]
#
# omcid cannot be restarted in place after it died abnormally: the restarted
# omcid fails to set the LCT traps up again (lct_trap_unset / PPTP LCT UNI
# errors), management traffic no longer reaches the CPU and an XGS-PON stick in
# O5 stays unreachable and offline until it is power cycled. So when omcid is
# killed by a signal (a crash, or SIGKILL from the OOM killer), record it and
# reboot instead:
#
# - on a one-time trial boot (img_activate) at once, the next boot is the
#   committed bank;
# - otherwise not before 10 minutes of uptime, so a crash loop cannot cycle
#   faster than that;
# - after 3 such reboots in a row without omcid staying up for 30 minutes in
#   between, stop rebooting and leave omcid to procd.
#
# A stop through procd (SIGTERM) is passed on to omcid, which gets 5 s before
# SIGKILL like procd gave it before. A plain exit status, a failsafe flag or
# fwenv 8311_omcid_crash_reboot=0 also leave omcid to procd's respawn.

_lib_8311 2>/dev/null || . /lib/8311.sh

OMCID=$1
shift

CRASH_LOG=/ptconf/8311/omcid-crash.log
STREAK=/ptconf/8311/omcid-crash-streak
MIN_UPTIME=600
STREAK_RESET=1800
MAX_STREAK=3
STOP_GRACE=5

uptime_s() {
	cut -d. -f1 /proc/uptime
}

PID=
RESET_PID=
stop_omcid() {
	[ -n "$RESET_PID" ] && kill "$RESET_PID" 2>/dev/null
	if [ -n "$PID" ]; then
		kill -TERM "$PID" 2>/dev/null
		t=0
		while kill -0 "$PID" 2>/dev/null && [ "$t" -lt "$STOP_GRACE" ]; do
			sleep 1
			t=$((t + 1))
		done
		kill -KILL "$PID" 2>/dev/null
		wait "$PID" 2>/dev/null
	fi
	exit 0
}
trap stop_omcid TERM INT HUP

"$OMCID" "$@" &
PID=$!

# omcid staying up for 30 minutes ends a crash streak. A separate sh named
# omcid-streak-reset, so ps does not show what looks like a second supervisor.
sh -c 'trap "kill \$! 2>/dev/null; exit 0" TERM; sleep "$1" & wait $!; kill -0 "$2" 2>/dev/null && rm -f "$3"' \
	omcid-streak-reset "$STREAK_RESET" "$PID" "$STREAK" </dev/null >/dev/null 2>&1 &
RESET_PID=$!

wait "$PID"
RC=$?
trap - TERM INT HUP
kill "$RESET_PID" 2>/dev/null

UPTIME=$(uptime_s)

case "$RC" in
	132) SIG=SIGILL ;;
	133) SIG=SIGTRAP ;;
	134) SIG=SIGABRT ;;
	136) SIG=SIGFPE ;;
	137) SIG=SIGKILL ;;
	138) SIG=SIGBUS ;;
	139) SIG=SIGSEGV ;;
	140) SIG=SIGSYS ;;
	*)
		echo "omcid (pid $PID) exited with status $RC at uptime ${UPTIME}s, leaving it to procd" | to_console
		exit "$RC"
	;;
esac

MSG="omcid (pid $PID) died from $SIG at uptime ${UPTIME}s"

record() {
	mkdir -p "${CRASH_LOG%/*}"
	{ tail -n 19 "$CRASH_LOG" 2>/dev/null; echo "$(date '+%F %T') $1"; } > "$CRASH_LOG.tmp" &&
		mv "$CRASH_LOG.tmp" "$CRASH_LOG"
}

if [ "$(fwenv_get_8311 "omcid_crash_reboot" "1")" = "0" ]; then
	echo "$MSG, crash reboot disabled, leaving it to procd" | to_console
	exit "$RC"
fi

if [ -f /root/.failsafe ] || [ -f /tmp/.failsafe ] || [ -f /ptconf/.failsafe ]; then
	echo "$MSG, failsafe flag present, leaving it to procd" | to_console
	exit "$RC"
fi

COUNT=$(cat "$STREAK" 2>/dev/null)
[ "$COUNT" -ge 0 ] 2>/dev/null || COUNT=0
if [ "$COUNT" -ge "$MAX_STREAK" ]; then
	echo "$MSG after $COUNT crash reboots in a row, not rebooting again, leaving it to procd" | to_console
	record "$MSG, not rebooting ($COUNT crash reboots in a row)"
	exit "$RC"
fi
echo $((COUNT + 1)) > "$STREAK.tmp" && mv "$STREAK.tmp" "$STREAK"
record "$MSG, rebooting"

# a restart or stop while waiting below reboots right away
trap 'sync; reboot; exit 0' TERM INT HUP

ACTIVE=$(active_fwbank)
COMMIT=$(fwenv_get "commit_bank")
if [ -n "$ACTIVE" ] && [ -n "$COMMIT" ] && [ "$ACTIVE" != "$COMMIT" ]; then
	echo "$MSG on a trial boot of bank $ACTIVE, rebooting to commit_bank $COMMIT" | to_console
elif [ "$UPTIME" -lt "$MIN_UPTIME" ]; then
	echo "$MSG, rebooting at uptime ${MIN_UPTIME}s because omcid cannot recover in place" | to_console
	while [ "$(uptime_s)" -lt "$MIN_UPTIME" ]; do
		sleep 10
	done
else
	echo "$MSG, rebooting because omcid cannot recover in place" | to_console
fi

# give the remote syslog a moment to ship the crash dump before going down
sleep 3
sync
reboot
