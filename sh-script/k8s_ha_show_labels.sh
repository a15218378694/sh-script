#!/bin/sh
#===============================================
# 遍历 HA_SCALE_DEPLOYS/HA_SCALE_STSES，输出标签信息
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
    printf "deploy %s/%s: " "$ns" "$dep"
    kubectl get deployments.apps "$dep" -n "$ns" --show-labels | awk 'NR>1{print $NF}'
done

for item in $HA_SCALE_STSES; do
    ns="${item%%/*}"
    sts="${item##*/}"
    printf "sts %s/%s: " "$ns" "$sts"
    kubectl get statefulsets.apps "$sts" -n "$ns" --show-labels | awk 'NR>1{print $NF}'
done
IFS="$_oldifs"
set +f

echo "0"