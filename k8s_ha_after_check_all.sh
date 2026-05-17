#!/bin/bash
#===============================================
# K8S高可用恢复脚本（兜底检查）
# 功能：演练后的全量检查兜底（不执行恢复操作）
# 输出：最后一行输出0（成功）/1（失败）
#===============================================
# 生产环境不建议使用 set -e，改为显式错误处理：

# 导入统一配置和公共函数库
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/k8s_ha_config.sh"
source "${SCRIPT_DIR}/k8s_ha_lib.sh"

echo "============================================"
echo "    K8S高可用恢复（兜底检查）"
echo "============================================"
echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "命名空间: $(get_all_namespaces | tr '\n' ' ')"
echo "需要检查的Deployment:"
get_all_deployments_all_ns | while IFS= read -r item; do
    echo "  - $item"
done
echo ""

OVERALL_SUCCESS=0

# 1. 检查基础服务状态（兜底检查）
echo "[STEP] 检查节点基础服务状态（兜底检查）"
for node in $(kubectl get nodes --no-headers 2>/dev/null | grep Ready | awk '{print $1}'); do
    echo "[INFO] 检查节点: $node"
    check_node_services "$node"
    check_ep_ports "$node"
    echo ""
done
echo ""

# 2. 检查所有Deployment状态（纯检查，不重启）
echo "[STEP] 检查Deployment状态"
while IFS= read -r item; do
    ns="${item%%/*}"
    dep="${item##*/}"
    if ! check_deployment_ready "$ns" "$dep"; then
        OVERALL_SUCCESS=1
    fi
done < <(get_all_deployments_all_ns)
echo ""

# 3. 等待Pod恢复
echo "[STEP] 等待Pod稳定..."
sleep 10

# 4. 最终检查
echo "[STEP] 最终检查"
while IFS= read -r item; do
    ns="${item%%/*}"
    dep="${item##*/}"
    if ! check_deployment_ready "$ns" "$dep"; then
        OVERALL_SUCCESS=1
    fi
done < <(get_all_deployments_all_ns)

echo ""
if [ "$OVERALL_SUCCESS" -eq 0 ]; then
    echo "[INFO] 环境已全部恢复"
    echo "0"
else
    echo "[WARN] 部分资源未完全恢复，请手动检查"
    echo "1"
fi
exit "$OVERALL_SUCCESS"
