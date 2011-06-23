#!/bin/sh
free | grep ^Mem | awk '{print $2"\n"$3"\n"$4}'
