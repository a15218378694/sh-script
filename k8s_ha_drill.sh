#!/bin/bash
#===============================================
# K8S高可用演练脚本（单节点版）
# 功能：对**一个节点**执行：
#       封闭(Cordon) → 驱逐(Drain)
#       之后运维平台会关机重启机器
# 用法：k8s_ha_drill.sh <node_ip>
# 输出：最后一行输出0（成功）/1（失败）
#===============================================

# 生产环境不建议使用 set -e，改为显式错误处理

# 导入统一配置和公共函数库
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/k8s_ha_config.sh"
source "${SCRIPT_DIR}/k8s_ha_lib.sh"

# 动态获取所有命名空间下的所有 Deployment（格式: namespace/deployment）
HA_DRILL_ALL=()
get_all_deployments_all_ns HA_DRILL_ALL

#===============================================
# 主函数：演练一个节点
# 用法：drill_node <node_ip>
#===============================================
drill_node() {
    local NODE="$1"
    
    if [ -z "$NODE" ]; then
        log_error "未提供节点名称"
        return 1
    fi
    
    echo "========================================="
    echo "[Drill] 开始演练节点: $NODE"
    echo "========================================="
    
    # ----------------------------------------------------------
    # Step 1: 封闭节点（禁止新Pod调度上来）
    # ----------------------------------------------------------
    log_step "[Step 1/3] 封闭节点 $NODE ..."
    kubectl cordon "$NODE" 2>/dev/null
    if [ "$?" -eq 0 ]; then
        log_info "节点 $NODE 已封闭"
    else
        log_warn "节点 $NODE 可能已被封闭"
    fi
    
    # ----------------------------------------------------------
    # Step 2: 驱逐（驱逐Pod）
    # ----------------------------------------------------------
    log_step "[Step 2/3] 驱逐节点 $NODE ..."
    kubectl drain "$NODE" \
        --ignore-daemonsets \
        --delete-emptydir-data \
        --timeout=300s
    if [ "$?" -eq 0 ]; then
        log_info "节点 $NODE 驱逐完成"
    else
        log_warn "节点 $NODE 驱逐可能未完全完成"
    fi
    
    # ----------------------------------------------------------
    # Step 3: 输出结果，等待运维平台关机重启
    # ----------------------------------------------------------
    log_step "[Step 3/3] 演练完成，等待运维平台关机重启..."
    echo "节点 $NODE 已封闭并驱逐完成"
    echo "请通过运维平台关机重启节点 $NODE"
    echo ""
    echo "节点重启后，将自动执行 k8s_ha_check.sh 进行验证"
    
    return 0
}

#===============================================
# 主流程
#===============================================
echo "============================================"
echo "    K8S高可用演练（单节点版）"
echo "============================================"
echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 检查参数
if [ -z "$1" ]; then
    echo "用法: $0 <node_ip>"
    echo "示例: $0 10.0.0.1"
    echo "可用节点及IP:"
    kubectl get nodes -o wide --no-headers 2>/dev/null | grep -v control-plane | grep Ready | awk '{print "  - " $1 " (IP: " $6 ")"}'
    echo "1"
    exit 1
fi

NODE_IP="$1"

# 通过IP获取节点名
NODE_NAME=$(get_node_by_ip "$NODE_IP")
if [ -z "$NODE_NAME" ]; then
    echo "[ERROR] 无法通过IP $NODE_IP 找到对应的K8s节点"
    echo "1"
    exit 1
fi

echo "节点IP: $NODE_IP"
echo "节点名: $NODE_NAME"
echo ""

# 执行演练
drill_node "$NODE_NAME"
DRILL_RESULT="$?"

echo ""
echo "============================================"
if [ "$DRILL_RESULT" -eq 0 ]; then
    echo "    演练完成: $NODE_NAME"
    echo "    结果: 成功 ✅"
else
    echo "    演练完成: $NODE_NAME"
    echo "    结果: 失败 ❌"
fi
echo "结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"

if [ "$DRILL_RESULT" -eq 0 ]; then
    echo "0"
else
    echo "1"
fi
exit "$DRILL_RESULT"
