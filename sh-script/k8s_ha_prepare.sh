#!/bin/sh
#===============================================
# K8S高可用准备脚本
# 功能：演练前验证（副本数>=2、反亲和配置）
# 输出：最后一行输出0（成功）/1（失败）
#===============================================
# 生产环境不建议使用 set -e，改为显式错误处理：

# 导入统一配置和公共函数库
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/k8s_ha_config.sh"
. "${SCRIPT_DIR}/k8s_ha_lib.sh"

echo "============================================"
echo "    K8S高可用准备"
echo "============================================"
echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "需验证Deployment（副本数>=2 + 反亲和）:"
_oldifs="$IFS"
IFS='
'
set -f
for item in $HA_SCALE_DEPLOYS; do
    echo "  - $item"
done
IFS="$_oldifs"
set +f
echo ""

# 1. 验证副本数 >= 2 和反亲和配置
echo "[STEP] 验证副本数 >= 2 和反亲和配置"
echo ""

_oldifs2="$IFS"
IFS='
'
set -f
for item in $HA_SCALE_DEPLOYS; do
    ns="${item%%/*}"
    dep="${item##*/}"
    log_info "验证Deployment: $ns/$dep"

    # 检查Deployment是否存在
    if ! deploy_exists "$ns" "$dep"; then
        check_item "$ns/$dep: Deployment不存在" "fail"
        continue
    fi

    # 验证副本数 >= TARGET_REPLICAS
    REPLICAS=$(get_replicas "$ns" "$dep")
    if [ -z "$REPLICAS" ] || [ "$REPLICAS" -lt "$TARGET_REPLICAS" ]; then
        check_item "$ns/$dep: 副本数不足 ($REPLICAS < $TARGET_REPLICAS)" "fail"
    else
        check_item "$ns/$dep: 副本数验证通过 ($REPLICAS >= $TARGET_REPLICAS)" "pass"
    fi

    # 验证反亲和配置
    AFFINITY=$(kubectl get deployment "$dep" -n "$ns" -o jsonpath='{.spec.template.spec.affinity.podAntiAffinity}' 2>/dev/null)
    if [ -n "$AFFINITY" ] && [ "$AFFINITY" != "null" ]; then
        check_item "$ns/$dep: Pod反亲和配置已启用" "pass"
    else
        check_item "$ns/$dep: Pod反亲和配置未启用（高可用演练必须配置反亲和）" "fail"
    fi

    echo ""
done
IFS="$_oldifs2"
set +f

# 输出验证结果
if [ "$CHECK_FAIL" -ne 0 ]; then
    echo "[ERROR] 验证未通过，请修复后重试"
    echo "1"
    exit 1
fi

echo "[INFO] 所有验证通过 ✅"
echo ""
echo "结束时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "0"
exit 0
