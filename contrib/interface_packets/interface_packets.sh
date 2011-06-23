#!/bin/sh
grep eth0 /proc/net/dev | awk '{ print $2"\n"$10}'
