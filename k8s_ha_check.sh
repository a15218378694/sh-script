#!/bin/bash
#===============================================
# K8S高可用演练 - 完整性检查脚本（单节点版）
# 功能：验证单个节点的HA演练完整性
#        机器开机后自动执行（检查基础服务状态）
# 用法：k8s_ha_check.sh <node_ip> [test]
#   test - 测试环境（跳过Pod分布检查）
#   prod - 生产环境（全量检查）[默认]
# 输出：最后一行输出0（成功）/1（失败）
#===============================================
# 生产环境不建议使用 set -e，改为显式错误处理：

# 导入统一配置和公共函数库
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/k8s_ha_config.sh"
source "${SCRIPT_DIR}/k8s_ha_lib.sh"

# 动态获取所有命名空间下的所有 Deployment（格式: namespace/deployment）
HA_DRILL_ALL=()
get_all_deployments_all_ns HA_DRILL_ALL

#===============================================
# 主函数：检查一个节点
# 用法：check_node <node_name> [test|prod]
#===============================================
check_node() {
    local NODE="$1"
    local ENV_TYPE="${2:-prod}"
    
    if [ -z "$NODE" ]; then
        log_error "未提供节点名称"
        return 1
    fi
    
    echo "========================================="
    echo "[Check] 开始检查节点: $NODE"
    echo "========================================="
    echo ""
    
    # ----------------------------------------------------------
    # Step 1: 恢复节点调度（开机后自动恢复）
    # ----------------------------------------------------------
    log_step "[Step 1/4] 恢复节点 $NODE 调度状态 ..."
    CORDON_STATUS=$(kubectl get node "$NODE" --no-headers 2>/dev/null | grep -c SchedulingDisabled || true)
    if [ "$CORDON_STATUS" -gt 0 ]; then
        log_info "节点 $NODE 处于不可调度状态，正在恢复..."
        kubectl uncordon "$NODE" 2>/dev/null
        if [ "$?" -eq 0 ]; then
            log_info "节点 $NODE 已恢复调度 ✅"
        else
            log_warn "节点 $NODE 恢复调度失败"
        fi
    else
        log_info "节点 $NODE 已是可调度状态"
    fi
    echo ""
    
    # ----------------------------------------------------------
    # Step 2: 检查基础服务状态（kubelet、docker、EP端口）
    # ----------------------------------------------------------
    log_step "[Step 2/4] 检查节点 $NODE 基础服务状态 ..."
    echo ""
    check_node_services "$NODE"
    check_ep_ports "$NODE"
    echo ""
    
    # ----------------------------------------------------------
    # Step 3: 检查集群基础组件
    # ----------------------------------------------------------
    log_step "[Step 3/4] 检查集群基础组件 ..."
    echo ""
    check_cluster_components
    echo ""
    
    # ----------------------------------------------------------
    # Step 4: 验证Pod恢复状态
    # ----------------------------------------------------------
    log_step "[Step 4/4] 验证Pod恢复状态 ..."
    echo ""

    for item in "${HA_DRILL_ALL[@]}"; do
        ns="${item%%/*}"
        dep="${item##*/}"
        echo "验证Deployment: $ns/$dep"

        # 通过 readyReplicas 检查（check_deployment_ready 内部会累加 CHECK_FAIL）
        check_deployment_ready "$ns" "$dep" >/dev/null

        # 检查Pod分布（验证调度到多个节点，测试环境跳过）
        if [ "$ENV_TYPE" != "test" ]; then
            NODE_DIST=$(kubectl get pods -n "$ns" -l app="$dep" --field-selector status.phase=Running -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort | uniq | wc -l | tr -d ' ')
            if [ "$NODE_DIST" -ge 2 ]; then
                check_item "$ns/$dep: Pod分布在不同节点 ($NODE_DIST 个节点)" "pass"
            else
                check_item "$ns/$dep: Pod集中在同一节点 ($NODE_DIST)" "warn"
            fi
        fi

        echo ""
    done
    
    # 输出总结
    echo ""
    echo "========================================="
    echo "    检查完成: $NODE"
    echo "    通过: $CHECK_PASS"
    echo "    警告: $CHECK_WARN"
    echo "    失败: $CHECK_FAIL"
    echo "========================================="
    
    # 统一使用 CHECK_FAIL 判断检查结果（check_deployment_ready 内部已累加 CHECK_FAIL）
    if [ "$CHECK_FAIL" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

#===============================================
# 主流程
#===============================================
echo "============================================"
echo "    K8S高可用演练 - 完整性检查（单节点版）"
echo "============================================"
echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 检查参数
if [ -z "$1" ]; then
    echo "用法: $0 <node_ip> [test|prod]"
    echo "  test - 测试环境（跳过Pod分布检查）"
    echo "  prod - 生产环境（全量检查）"
    echo ""
    echo "示例: $0 10.0.0.1 prod"
    echo ""
    echo "可用节点及IP:"
    kubectl get nodes -o wide --no-headers 2>/dev/null | grep -v control-plane | grep Ready | awk '{print "  - " $1 " (IP: " $6 ")"}'
    echo "1"
    exit 1
fi

NODE_IP="$1"
NODE_NAME=$(get_node_by_ip "$NODE_IP")
ENV_TYPE="${2:-prod}"

if [ -z "$NODE_NAME" ]; then
    echo "[ERROR] 无法通过IP $NODE_IP 找到对应的K8s节点"
    echo "1"
    exit 1
fi

echo "节点IP: $NODE_IP"
echo "节点名: $NODE_NAME"
echo "环境类型: $ENV_TYPE"
echo ""

# 执行检查
check_node "$NODE_NAME" "$ENV_TYPE"
CHECK_RESULT="$?"

echo ""
echo "============================================"
if [ "$CHECK_RESULT" -eq 0 ]; then
    echo "    结果: 成功 ✅"
else
    echo "    结果: 失败 ❌"
fi
echo "结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"

if [ "$CHECK_RESULT" -eq 0 ]; then
    echo "0"
else
    echo "1"
fi
exit "$CHECK_RESULT"
