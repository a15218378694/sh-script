#!/bin/sh
#===============================================
# 遍历 HA_SCALE_DEPLOYS 中的 Deployment，输出标签信息
# 用法: k8s_ha_show_labels.sh
# 输出：最后一行输出0
#===============================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/k8s_ha_config.sh"

_oldifs="$IFS"
IFS='
'
set -f
for item in $HA_SCALE_DEPLOYS; do
    ns="${item%%/*}"
    dep="${item##*/}"
    kubectl get deployments.apps "$dep" -n "$ns" --show-labels
done
IFS="$_oldifs"
set +f


echo "0"