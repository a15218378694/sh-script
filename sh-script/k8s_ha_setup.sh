#!/bin/sh
#===============================================
# 自动补齐 HA_SCALE_DEPLOYS 的副本数和反亲和配置
# 副本数已>=2的跳过，已配置反亲和的跳过
# 用法: k8s_ha_setup.sh
#===============================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/k8s_ha_config.sh"
. "${SCRIPT_DIR}/k8s_ha_lib.sh"

echo "============================================"
echo "    K8S HA 自动配置（扩容 + 反亲和）"
echo "============================================"

_oldifs="$IFS"
IFS='
'
set -f
for item in $HA_SETUP_DEPLOYS; do
    ns="${item%%/*}"
    dep="${item##*/}"

    if ! deploy_exists "$ns" "$dep"; then
        log_warn "$ns/$dep: Deployment不存在，跳过"
        continue
    fi

    # 1. 检查并扩容副本
    REPLICAS=$(get_replicas "$ns" "$dep")
    if [ -z "$REPLICAS" ]; then
        log_warn "$ns/$dep: 获取副本数失败，跳过"
        continue
    fi

    if [ "$REPLICAS" -lt "$TARGET_REPLICAS" ]; then
        log_info "$ns/$dep: 副本数=$REPLICAS < $TARGET_REPLICAS，扩容到$TARGET_REPLICAS"
        kubectl scale deployment "$dep" -n "$ns" --replicas="$TARGET_REPLICAS" --request-timeout="${KUBECTL_TIMEOUT}s" >/dev/null 2>&1
    else
        log_info "$ns/$dep: 副本数=$REPLICAS >= $TARGET_REPLICAS，跳过"
    fi

    # 2. 检查并配置硬反亲和
    AFFINITY=$(kubectl get deployment "$dep" -n "$ns" -o jsonpath='{.spec.template.spec.affinity.podAntiAffinity}' 2>/dev/null)
    if [ -z "$AFFINITY" ] || [ "$AFFINITY" = "null" ]; then
        log_info "$ns/$dep: 未配置反亲和，添加硬反亲和"
        kubectl patch deployment "$dep" -n "$ns" --type strategic -p "{\"spec\":{\"template\":{\"spec\":{\"affinity\":{\"podAntiAffinity\":{\"requiredDuringSchedulingIgnoredDuringExecution\":[{\"labelSelector\":{\"matchExpressions\":[{\"key\":\"app\",\"operator\":\"In\",\"values\":[\"$dep\"]}]},\"topologyKey\":\"kubernetes.io/hostname\"}]}}}}}}" --request-timeout="${KUBECTL_TIMEOUT}s" >/dev/null 2>&1
    else
        log_info "$ns/$dep: 已配置反亲和，跳过"
    fi

    echo ""
done
IFS="$_oldifs"
set +f

echo "============================================"
echo "    配置完成"
echo "============================================"
