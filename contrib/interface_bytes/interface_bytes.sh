#!/bin/sh
sed -n 's/eth0://gp' /proc/net/dev | awk '{ print $1"\n"$9}'
