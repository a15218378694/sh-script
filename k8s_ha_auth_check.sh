#!/bin/bash
#===============================================
# K8S高可用 - 鉴权服务检查脚本（ansible-agent版）
# 功能：通过 ansible-agent 远程检查 auth_server 进程
# 检查项：进程是否存在、进程数量、端口监听
# 用法: k8s_ha_auth_check.sh <master_node_ip>
# 输出：最后一行输出0（成功）/1（失败）
#===============================================
# 生产环境不建议使用 set -e，改为显式错误处理：

# 导入公共函数库（含颜色定义、日志、check_item）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/k8s_ha_config.sh"
source "${SCRIPT_DIR}/k8s_ha_lib.sh"

# 通过 ansible-agent 远程执行命令
# 用法: remote_exec "<命令>"
remote_exec() {
    local cmd="$1"
    log_info "执行命令: ${cmd}"
    log_info "执行IP: ${MASTER_IP}"
    ansible-agent -H "${MASTER_IP}" exec "${cmd}" 2>/dev/null
}

#===============================================
# 主流程
#===============================================
echo "============================================"
echo "    K8S 鉴权服务检查（auth_server 主机进程）"
echo "============================================"
echo "检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 检查参数
if [ -z "$1" ]; then
    echo "用法: $0 <master_node_ip>"
    echo "示例: $0 10.234.6.21"
    echo "1"
    exit 1
fi

MASTER_IP="$1"

# 预检查：ansible-agent 是否可用
log_step "【0】预检查：ansible-agent 连接"
echo ""
if ! command -v ansible-agent >/dev/null 2>&1; then
    check_item "ansible-agent 命令不存在" "fail"
    echo "1"
fi
check_item "ansible-agent 命令可用" "pass"

AGENT_CHECK=$(remote_exec "hostname" 2>/dev/null)
if [ -z "$AGENT_CHECK" ]; then
    check_item "ansible-agent 连接到 $MASTER_IP 失败" "fail"
    echo "1"
fi
check_item "ansible-agent 连接到 $MASTER_IP 成功（主机名: $AGENT_CHECK）" "pass"
echo ""

#--------------------------------------------
# 1. 检查 auth_server 服务（curl 端口检测），异常时自动启动
#--------------------------------------------
log_step "【1】检查 auth_server 服务（curl :8443）"
echo ""

echo "  [INFO] curl ${MASTER_IP}:8443 检查鉴权服务状态..."
HTTP_CODE=$(remote_exec "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 ${MASTER_IP}:8443/security/license" 2>/dev/null)

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 400 ] 2>/dev/null; then
    check_item "auth_server 服务运行正常（HTTP $HTTP_CODE）" "pass"
else
    echo "  ⚠ auth_server 无响应（HTTP ${HTTP_CODE:-无状态码}），正在尝试启动..."
    # 执行启动命令
    remote_exec "cd /home/baidu/work/c-offline-security-server && nohup bash start/c-offline-security-server-start.sh &"
    
    # 启动后循环 curl 检查，最多3次
    START_OK=0
    for i in 1 2 3; do
        echo "  [INFO] 第 ${i} 次检查：curl ${MASTER_IP}:8443 ..."
        sleep 5
        HTTP_CODE=$(remote_exec "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 ${MASTER_IP}:8443" 2>/dev/null)
        if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 400 ] 2>/dev/null; then
            echo "  [INFO] 第 ${i} 次检查通过（HTTP $HTTP_CODE）"
            START_OK=1
            break
        fi
    done
    
    if [ "$START_OK" -eq 1 ]; then
        check_item "auth_server 已自动启动成功（共尝试 ${i} 次）" "pass"
    else
        check_item "auth_server 启动失败（尝试3次均无响应），请手动排查" "fail"
    fi
fi

#--------------------------------------------
# 总结与输出
#--------------------------------------------
echo "============================================"
echo "    检查完成: $MASTER_IP"
echo "    通过: $CHECK_PASS"
echo "    警告: $CHECK_WARN"
echo "    失败: $CHECK_FAIL"
echo "============================================"

if [ "$CHECK_FAIL" -eq 0 ]; then
    echo "0"
    exit 0
else
    echo "1"
    exit 1
fi
