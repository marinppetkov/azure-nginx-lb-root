#!/bin/bash
apt update
apt install nginx -y
apt install net-tools -y
echo 200 web >> /etc/iproute2/rt_tables
ip rule add from $(hostname -I | cut -f2 -d' ') table web prio 1
ip route add default via 10.0.2.1 dev eth1 table web