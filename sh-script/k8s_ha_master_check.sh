#!/bin/sh
#===============================================
# K8S高可用 - Master节点服务检查脚本（ansible-agent版）
# 功能：通过 ansible-agent 远程检查 master 节点核心服务
# 检查项：etcd、kube-apiserver、kube-controller-manager、kube-scheduler
# 用法: k8s_ha_master_check.sh <master_node_ip>
# 输出：最后一行输出0（成功）/1（失败）
#===============================================
# 生产环境不建议使用 set -e，改为显式错误处理：

# 导入公共函数库（含颜色定义、日志、check_item）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/k8s_ha_config.sh"
. "${SCRIPT_DIR}/k8s_ha_lib.sh"

# 通过 ansible-agent 远程执行命令
# 用法: remote_exec "<命令>"
remote_exec() {
    local cmd="$1"
    ansible-agent -H "${MASTER_IP}" exec "${cmd}" 2>/dev/null
}

# 检查并重启 systemd 服务
# 用法: check_service <服务名> <显示名>
check_service() {
    local service_name="$1"
    local display_name="$2"
    
    local status_output
    status_output=$(remote_exec "systemctl is-active ${service_name}")
    
    if [ "$status_output" = "active" ]; then
        check_item "${display_name} 服务运行正常（active）" "pass"
    else
        check_item "${display_name} 服务异常（${status_output:-执行失败}），尝试重启..." "warn"
        
        # 尝试重启服务
        remote_exec "systemctl restart ${service_name}"
        sleep 15
        
        # 再次检查服务状态
        status_output=$(remote_exec "systemctl is-active ${service_name}")
        if [ "$status_output" = "active" ]; then
            check_item "${display_name} 服务重启成功（active）" "pass"
        else
            check_item "${display_name} 服务重启失败（${status_output:-状态未知}）" "fail"
        fi
    fi
}

#===============================================
# 主流程
#===============================================
echo "============================================"
echo "    K8S Master节点服务检查（ansible-agent）"
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

AGENT_CHECK=$(remote_exec "hostname")
if [ -z "$AGENT_CHECK" ]; then
    check_item "ansible-agent 连接到 $MASTER_IP 失败" "fail"
    echo "1"
fi
check_item "ansible-agent 连接到 $MASTER_IP 成功（主机名: $AGENT_CHECK）" "pass"
echo ""

#--------------------------------------------
# 1. 检查 etcd 服务
#--------------------------------------------
log_step "【1】检查 etcd 服务状态"
echo ""
check_service "etcd" "etcd"
echo ""

#--------------------------------------------
# 2. 检查 kube-apiserver 服务
#--------------------------------------------
log_step "【2】检查 kube-apiserver 服务状态"
echo ""
check_service "kube-apiserver" "kube-apiserver"
echo ""

#--------------------------------------------
# 3. 检查 kube-controller-manager 服务
#--------------------------------------------
log_step "【3】检查 kube-controller-manager 服务状态"
echo ""
check_service "kube-controller-manager" "kube-controller-manager"
echo ""

#--------------------------------------------
# 4. 检查 kube-scheduler 服务
#--------------------------------------------
log_step "【4】检查 kube-scheduler 服务状态"
echo ""
check_service "kube-scheduler" "kube-scheduler"
echo ""

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
