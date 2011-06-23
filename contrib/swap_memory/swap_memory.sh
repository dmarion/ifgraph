#!/bin/sh
free | grep ^Swap | awk '{print $2"\n"$3"\n"$4}'
