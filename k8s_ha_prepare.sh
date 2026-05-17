#!/bin/bash
#===============================================
# K8S高可用准备脚本
# 功能：演练前验证（副本数>=2、反亲和配置）
# 输出：最后一行输出0（成功）/1（失败）
#===============================================
# 生产环境不建议使用 set -e，改为显式错误处理：

# 导入统一配置和公共函数库
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/k8s_ha_config.sh"
source "${SCRIPT_DIR}/k8s_ha_lib.sh"

echo "============================================"
echo "    K8S高可用准备"
echo "============================================"
echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "需验证Deployment（副本数>=2 + 反亲和）:"
for item in "${HA_SCALE_DEPLOYS[@]}"; do
    echo "  - $item"
done
echo ""

# 1. 验证副本数 >= 2 和反亲和配置
echo "[STEP] 验证副本数 >= 2 和反亲和配置"
echo ""
PRE_CHECK_FAIL=0

for item in "${HA_SCALE_DEPLOYS[@]}"; do
    ns="${item%%/*}"
    dep="${item##*/}"
    echo "[INFO] 验证Deployment: $ns/$dep"
    
    # 检查Deployment是否存在
    if ! deploy_exists "$ns" "$dep"; then
        echo "[ERROR] $ns/$dep Deployment不存在"
        PRE_CHECK_FAIL=1
        continue
    fi
    
    # 验证副本数 >= TARGET_REPLICAS
    REPLICAS=$(get_replicas "$ns" "$dep")
    if [ -z "$REPLICAS" ] || [ "$REPLICAS" -lt "$TARGET_REPLICAS" ]; then
        echo "[ERROR] $ns/$dep 副本数不足 ($REPLICAS < $TARGET_REPLICAS)【千牛平台可能出bug】"
        PRE_CHECK_FAIL=1
    else
        echo "[INFO] $ns/$dep 副本数验证通过 ($REPLICAS >= $TARGET_REPLICAS) ✅"
    fi
    
    # 验证反亲和配置
    AFFINITY=$(kubectl get deployment "$dep" -n "$ns" -o jsonpath='{.spec.template.spec.affinity.podAntiAffinity}' 2>/dev/null)
    if [ -n "$AFFINITY" ] && [ "$AFFINITY" != "null" ]; then
        echo "[INFO] $ns/$dep: Pod反亲和配置已启用 ✅"
    else
        echo "[ERROR] $ns/$dep: Pod反亲和配置未启用 ❌（高可用演练必须配置反亲和）"
        PRE_CHECK_FAIL=1
    fi
    
    echo ""
done

# 输出验证结果
if [ "$PRE_CHECK_FAIL" -ne 0 ]; then
    echo "[ERROR] 验证未通过，请修复后重试"
    echo "1"
    exit 1
fi

echo "[INFO] 所有验证通过 ✅"
echo ""
echo "结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "0"
exit 0
