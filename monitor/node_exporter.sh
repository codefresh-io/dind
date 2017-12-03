#!/bin/bash
#

DIR=$(dirname $0)

DISABLED_COLLECTORS=(arp bcache bonding buddyinfo conntrack cpu diskstats drbd edac entropy filefd filesystem gmond hwmon infiniband \
        interrupts ipvs ksmd loadavg logind mdadm megacli meminfo meminfo_numa mountstats netdev netstat nfs ntp qdisc \
        runit sockstat stat supervisord systemd tcpstat time uname vmstat wifi xfs zfs timex )

DISABLE_COLLECTORS_ARGS=""
for i in ${DISABLED_COLLECTORS[@]}; do
   DISABLE_COLLECTORS_ARGS="${DISABLE_COLLECTORS_ARGS} --no-collector.${i}"
done

TEXTFILE_DIRECTORY=${DIR}/metrics
mkdir -p ${TEXTFILE_DIRECTORY}
echo "Starting node_exporter at $(date):
   TEXTFILE_DIRECTORY = ${TEXTFILE_DIRECTORY}
"

node_exporter ${DISABLE_COLLECTORS_ARGS} --collector.textfile --collector.textfile.directory=${TEXTFILE_DIRECTORY}
