RAM Sentinel
A shell daemon that monitors free RAM on Linux and alerts when it drops
below a threshold. Built for sysadmins and security work on Kali - logs
to syslog/logfile, captures the top memory-consuming processes at trigger
time (useful for spotting a runaway process or memory-exhaustion condition,
not just knowing "RAM is low"), and runs as a proper systemd service.
Features
Configurable threshold, poll interval, and alert cooldown (no more
spam-notifications every 15s while RAM stays low)
Logs to both a logfile and syslog (`logger`), so output survives even
when backgrounded

Captures top 5 processes by `%MEM` on every alert
`-n` log-only mode for headless/SSH sessions where `notify-send` has
no display to talk to
`-o` one-shot mode for running from cron instead of a persistent loop
PID-file guarded - refuses to start a second instance
Graceful shutdown on SIGINT/SIGTERM (cleans up its own pidfile)
`shellcheck`-clean

systemd user service for real daemonization (auto-restart, survives
logout/reboot) instead of `nohup ... &`
Install (systemd, recommended)
```bash
chmod +x install.sh
./install.sh
```
Installs the script to `~/.local/bin`, the unit to
`~/.config/systemd/user`, and starts it immediately. Check status with:
```bash
systemctl --user status ram-sentinel
journalctl --user -u ram-sentinel -f
```
Manual usage
```bash
chmod +x ram-sentinel.sh

# defaults: 500MB threshold, 15s interval, 300s cooldown
./ram-sentinel.sh

# custom threshold/interval, log-only (no GUI notifications) - good over SSH
./ram-sentinel.sh -t 1024 -i 10 -n

# one-shot check for a cron job
*/5 * * * * /path/to/ram-sentinel.sh -t 500 -n -o
```
Run `./ram-sentinel.sh -h` for the full flag list.
Tests
```bash
./tests/test_ram_sentinel.sh
```
Covers: input validation, help output, forced-trigger alert + process
logging, and the single-instance/PID-file guard.
Original vs. this version
	original	this version
Config	hardcoded in the script	CLI flags (`-t -i -c -l -p -n -o`)
Alerting	fires every interval while low	cooldown-debounced
Headless/SSH	`notify-send` fails silently	detected, falls back to log-only
Diagnosis	none	top 5 processes by %MEM logged on trigger
Logging	stdout only	logfile + syslog
Daemonization	`nohup ... &`	systemd user service, auto-restart
Multiple instances	unguarded	PID-file guarded
Shutdown	none	traps SIGINT/SIGTERM, cleans up
Validation	none	rejects non-numeric args
Tests	none	7-case test suite
This project is open-source and licensed under the MIT License.
