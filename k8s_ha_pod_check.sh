#!/bin/bash
#===============================================
# K8S高可用 - Pod 健康检查脚本
# 功能：检查所有非系统命名空间的 Pod 状态
#       不能有 Pending / Failed / Unknown / CrashLoopBackOff 等异常
#       用于 StatefulSet 检查后执行
# 输出：最后一行输出0（成功）/1（失败）
#===============================================

# 导入统一配置和公共函数库
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/k8s_ha_config.sh"
source "${SCRIPT_DIR}/k8s_ha_lib.sh"

echo "============================================"
echo "    K8S Pod 健康检查"
echo "============================================"
echo "检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

#--------------------------------------------
# 检查所有 Pod
#--------------------------------------------
log_step "【检查】验证所有非系统命名空间 Pod 状态"
echo ""

reset_check_counts
check_all_pods_healthy
OVERALL_FAIL=$?

#--------------------------------------------
# 总结与输出
#--------------------------------------------
echo ""
echo "============================================"
echo "    检查完成"
echo "    通过: $CHECK_PASS"
echo "    警告: $CHECK_WARN"
echo "    失败: $CHECK_FAIL"
echo "============================================"

if [ "$OVERALL_FAIL" -eq 0 ]; then
    echo "0"
    exit 0
else
    echo "1"
    exit 1
fi
