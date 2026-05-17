#!/bin/sh
#===============================================
# K8S高可用恢复脚本（兜底检查）
# 功能：演练后的全量检查兜底
# 输出：最后一行输出0（成功）/1（失败）
#===============================================
# 生产环境不建议使用 set -e，改为显式错误处理：

# 导入统一配置和公共函数库
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/k8s_ha_config.sh"
. "${SCRIPT_DIR}/k8s_ha_lib.sh"

echo "============================================"
echo "    K8S高可用恢复（兜底检查）"
echo "============================================"
echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "命名空间: $(get_all_namespaces | tr '\n' ' ')"
echo "需要检查的Deployment:"
_oldifs1="$IFS"
IFS='
'
set -f
for item in $(get_all_deployments_all_ns); do
    echo "  - $item"
done
IFS="$_oldifs1"
set +f
echo ""

OVERALL_SUCCESS=0

# 1. 检查基础服务状态（兜底检查）
echo "[STEP] 检查节点基础服务状态（兜底检查）"
for node in $(kubectl get nodes --no-headers 2>/dev/null | grep Ready | awk '{print $1}'); do
    echo "[INFO] 检查节点: $node"
    check_node_services "$node"
    echo ""
done
echo ""

# 检查所有Deployment状态（自动修复）并记录结果
check_all_deployments() {
    local _oldifs="$IFS"
    IFS='
'
    set -f
    local item ns dep
    for item in $(get_all_deployments_all_ns); do
        ns="${item%%/*}"
        dep="${item##*/}"
        if ! check_deployment_ready "$ns" "$dep"; then
            return 1
        fi
    done
    IFS="$_oldifs"
    set +f
    return 0
}

# 2. 第一次检查
echo "[STEP] 检查Deployment状态（自动修复）"
if ! check_all_deployments; then
    OVERALL_SUCCESS=1
fi
echo ""

# 3. 等待Pod恢复
echo "[STEP] 等待Pod稳定..."
sleep 10

# 4. 最终检查
echo "[STEP] 最终检查"
if ! check_all_deployments; then
    OVERALL_SUCCESS=1
fi

echo ""
if [ "$OVERALL_SUCCESS" -eq 0 ]; then
    echo "[INFO] 环境已全部恢复"
    echo "0"
else
    echo "[WARN] 部分资源未完全恢复，请手动检查"
    echo "1"
fi
exit "$OVERALL_SUCCESS"
