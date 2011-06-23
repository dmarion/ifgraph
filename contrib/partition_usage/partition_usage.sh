#!/bin/sh
df -m | grep ${1} | awk '{print $2"\n"$3"\n"$4}'
