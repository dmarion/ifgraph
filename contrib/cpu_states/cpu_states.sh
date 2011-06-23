#!/bin/sh
grep "cpu " /proc/stat | awk '{ print $2+$3+$4+$5"\n"$2"\n"$3"\n"$4"\n"$5 }'
