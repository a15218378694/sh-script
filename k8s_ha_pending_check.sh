#!/bin/bash
#===============================================
# K8S高可用 - 驱逐后 Pod 恢复检查脚本
# 功能：驱逐后检查所有 Deployment 的 Pod 是否恢复
#       通过 readyReplicas 判断（兼容 StatefulSet localPV 场景）
# 用法: k8s_ha_pending_check.sh
# 输出：最后一行输出0（正常）/1（存在未恢复Pod）
#===============================================
# 生产环境不建议使用 set -e，改为显式错误处理：

# 导入统一配置和公共函数库
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/k8s_ha_config.sh"
source "${SCRIPT_DIR}/k8s_ha_lib.sh"

#===============================================
# 主流程
#===============================================

# 驱逐后等待 60 秒，让 Pod 完成调度，避免误报
log_info "驱逐后等待 60 秒，等待 Pod 完成调度..."
sleep 60
echo ""

echo "============================================"
echo "    K8S 驱逐后 Pod 恢复检查"
echo "============================================"
echo "检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

#--------------------------------------------
# 检查所有 Deployment 的 readyReplicas
#--------------------------------------------
log_step "【检查】验证所有 Deployment Pod 恢复状态"
echo ""

reset_check_counts
check_all_deployments_ready
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
