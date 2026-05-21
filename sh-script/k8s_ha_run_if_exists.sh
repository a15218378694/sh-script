#!/bin/sh
#===============================================
# 远程检查文件是否存在，存在则执行
# 用法: k8s_ha_run_if_exists.sh <node_ip>
# 输出：最后一行输出0
#===============================================

REMOTE_FILE="/home/baidu/stop.sh"

if [ -n "$1" ] && ansible-agent -H "$1" exec "test -f ${REMOTE_FILE}" >/dev/null 2>&1; then
    ansible-agent -H "$1" exec "sh ${REMOTE_FILE}"
fi
echo "0"
