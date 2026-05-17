#!/bin/sh
#===============================================
# K8S高可用 - StatefulSet 检查脚本
# 功能：检查所有 StatefulSet 的 readyReplicas
#       用于 DaemonSet 检查后执行
# 输出：最后一行输出0（成功）/1（失败）
#===============================================

# 导入统一配置和公共函数库
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/k8s_ha_config.sh"
. "${SCRIPT_DIR}/k8s_ha_lib.sh"

echo "============================================"
echo "    K8S StatefulSet 健康检查"
echo "============================================"
echo "检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

#--------------------------------------------
# 检查所有 StatefulSet
#--------------------------------------------
log_step "【检查】验证所有 StatefulSet 运行状态"
echo ""

check_all_statefulsets_ready
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
