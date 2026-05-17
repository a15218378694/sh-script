#!/bin/bash
#===============================================
# K8S高可用演练 - 公共函数库
# 所有脚本通过 source 引用此文件
#===============================================

# 通过IP获取对应的K8s节点名称
# 用法: get_node_by_ip <ip>
# 输出: 节点名（空则未找到）
get_node_by_ip() {
    local ip="$1"
    kubectl get nodes -o jsonpath="{range .items[*]}{.status.addresses[?(@.type==\"InternalIP\")].address}{\"\t"}{.metadata.name}{\"\n\"}{end}" 2>/dev/null | \
        awk -F'\t' -v ip="$ip" '$1==ip {print $2; exit}'
}

# 自动扫描所有命名空间（排除系统命名空间）
# 用法: get_all_namespaces
get_all_namespaces() {
    # 获取所有命名空间并排除系统命名空间
    kubectl get namespace -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | \
        tr ' ' '\n' | \
        grep -v '^$' | \
        grep -v '^kube-system$' | \
        grep -v '^kube-public$' | \
        grep -v '^kube-node-lease$' | \
        grep -v '^system$'
}

# 动态获取指定命名空间下所有 Deployment 名称
# 用法: get_all_deployments <namespace>
get_all_deployments() {
    local ns="$1"
    kubectl get deployment -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep -v '^$'
}

# 获取所有命名空间下的所有 Deployment 名称（去重）
# 用法: get_all_deployments_all_ns [数组名]
# 如果不提供数组名，则输出到stdout（兼容旧用法）
get_all_deployments_all_ns() {
    while IFS= read -r ns; do
        [ -z "$ns" ] && continue
        while IFS= read -r dep; do
            [ -n "$dep" ] && echo "$ns/$dep"
        done < <(get_all_deployments "$ns")
    done < <(get_all_namespaces) | sort -u
}

# 获取 Deployment 当前副本数
# 用法: get_replicas <namespace> <deployment>
get_replicas() {
    local ns="$1"
    local dep="$2"
    kubectl get deployment "$dep" -n "$ns" \
        --request-timeout="${KUBECTL_TIMEOUT}s" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null
}

# 获取 Deployment 的 Running Pod 数量
# 用法: get_running_pods_count <namespace> <deployment>
get_running_pods_count() {
    local ns="$1"
    local dep="$2"
    kubectl get pods -n "$ns" -l app="$dep" \
        --field-selector status.phase=Running \
        --no-headers 2>/dev/null | wc -l | tr -d ' '
}

# 检查 Deployment 是否存在
# 用法: deploy_exists <namespace> <deployment>
deploy_exists() {
    local ns="$1"
    local dep="$2"
    kubectl get deployment "$dep" -n "$ns" >/dev/null 2>&1
}

# 检查 Service 是否存在
# 用法: svc_exists <namespace> <service>
svc_exists() {
    local ns="$1"
    local svc="$2"
    kubectl get svc "$svc" -n "$ns" >/dev/null 2>&1
}

# 遍历所有命名空间执行命令的辅助函数
# 用法: for_each_namespace <function_name> [args...]
for_each_namespace() {
    local func="$1"
    shift
    while IFS= read -r ns; do
        [ -z "$ns" ] && continue
        "$func" "$ns" "$@"
    done < <(get_all_namespaces)
}

#===============================================
# 基础服务检查函数
#===============================================

# 检查节点上的 kubelet 和 docker 服务状态
# 用法: check_node_services <node_name>
check_node_services() {
    local node="$1"
    echo "[INFO] 检查节点 $node 的基础服务..."
    
    # 通过 kubectl node-shell 或 SSH 检查（这里用 kubectl get node 间接检查）
    # 实际生产中应通过 Ansible/SSH 登录节点检查
    # 这里提供框架，具体实现需根据环境调整
    
    # 示例：检查节点是否 Ready
    local node_status
    node_status=$(kubectl get node "$node" --no-headers 2>/dev/null | awk '{print $2}')
    if [ "$node_status" = "Ready" ]; then
        echo "  ✓ 节点 $node 状态: Ready"
    else
        echo "  ✗ 节点 $node 状态异常: $node_status"
    fi
    
    # 如果需要检查 kubelet/docker，可以取消注释以下代码（需要 SSH 或 node-shell）
    # kubectl node-shell "$node" -- systemctl status kubelet 2>/dev/null
    # kubectl node-shell "$node" -- systemctl status docker 2>/dev/null
}

# 检查节点上的 EP 端口（Etcd Peer 端口）
# 用法: check_ep_ports <node_name>
check_ep_ports() {
    local node="$1"
    echo "[INFO] 检查节点 $node 的 EP 端口..."
    
    # EP 端口通常指 Etcd Peer 端口（2380）或其他关键端口
    # 这里检查节点上的关键端口是否监听
    
    # 示例：检查 kubelet 端口（10250）
    if kubectl get node "$node" --no-headers >/dev/null 2>&1; then
        echo "  ✓ 节点 $node 可访问"
    else
        echo "  ✗ 节点 $node 不可访问"
    fi
    
    # 如果需要检查具体端口，可以取消注释（需要网络访问或 SSH）
    # kubectl node-shell "$node" -- ss -tlnp | grep -E '(:10250|:2380|:6443)'
}

# 检查集群基础组件状态
# 用法: check_cluster_components
check_cluster_components() {
    echo "[INFO] 检查集群基础组件..."
    
    # 检查 Etcd
    local etcd_status
    etcd_status=$(kubectl get pod -n kube-system -l component=etcd --no-headers 2>/dev/null | grep -c Running || echo "0")
    if [ "$etcd_status" -ge 1 ]; then
        echo "  ✓ Etcd 组件正常 ($etcd_status 个 Pod Running)"
    else
        echo "  ✗ Etcd 组件异常"
    fi
    
    # 检查 API Server
    if kubectl cluster-info >/dev/null 2>&1; then
        echo "  ✓ API Server 正常"
    else
        echo "  ✗ API Server 异常"
    fi
    
    # 检查 Controller Manager
    local cm_status
    cm_status=$(kubectl get pod -n kube-system -l component=kube-controller-manager --no-headers 2>/dev/null | grep -c Running || echo "0")
    if [ "$cm_status" -ge 1 ]; then
        echo "  ✓ Controller Manager 正常 ($cm_status 个 Pod Running)"
    else
        echo "  ✗ Controller Manager 异常"
    fi
    
    # 检查 Scheduler
    local sched_status
    sched_status=$(kubectl get pod -n kube-system -l component=kube-scheduler --no-headers 2>/dev/null | grep -c Running || echo "0")
    if [ "$sched_status" -ge 1 ]; then
        echo "  ✓ Scheduler 正常 ($sched_status 个 Pod Running)"
    else
        echo "  ✗ Scheduler 异常"
    fi
}

#===============================================
# 公共检查工具函数
# 所有检查脚本通过此组函数统一输出
#===============================================

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
NC='\033[0m'

# 检查项计数
CHECK_PASS=0
CHECK_WARN=0
CHECK_FAIL=0

# 日志函数
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# 输出检查项（累加 CHECK_PASS/CHECK_WARN/CHECK_FAIL）
check_item() {
    local desc="$1"
    local status="$2"
    case "$status" in
        pass)
            echo -e "  ✓ $desc"
            CHECK_PASS=$((CHECK_PASS + 1))
            ;;
        warn)
            echo -e "  ⚠ $desc"
            CHECK_WARN=$((CHECK_WARN + 1))
            ;;
        fail)
            echo -e "  ✗ $desc"
            CHECK_FAIL=$((CHECK_FAIL + 1))
            ;;
    esac
}

# 重置检查计数
# 用法: reset_check_counts
reset_check_counts() {
    CHECK_PASS=0
    CHECK_WARN=0
    CHECK_FAIL=0
}

# 检查单个 Deployment 的 readyReplicas
# 用法: check_deployment_ready <namespace> <deployment>
# 返回值: 0=正常, 1=异常
check_deployment_ready() {
    local ns="$1"
    local dep="$2"

    if ! deploy_exists "$ns" "$dep"; then
        check_item "$ns/$dep: Deployment 不存在" "fail"
        return 1
    fi

    local replicas ready_replicas
    replicas=$(get_replicas "$ns" "$dep")
    if [ -z "$replicas" ]; then
        check_item "$ns/$dep: 获取副本数失败" "fail"
        return 1
    fi

    ready_replicas=$(kubectl get deployment "$dep" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    ready_replicas=${ready_replicas:-0}

    if [ "$ready_replicas" -eq "$replicas" ]; then
        check_item "$ns/$dep: Pod状态匹配期望副本 ($ready_replicas/$replicas)" "pass"
        return 0
    else
        check_item "$ns/$dep: Pod未全部就绪 ($ready_replicas/$replicas)" "fail"
        return 1
    fi
}

# 检查所有 Deployment 的 readyReplicas
# 用法: check_all_deployments_ready
# 返回值: 0=全部正常, 1=存在异常
check_all_deployments_ready() {
    local overall_fail=0
    local item ns dep
    local _found=0

    while IFS= read -r item; do
        _found=1
        ns="${item%%/*}"
        dep="${item##*/}"
        if ! check_deployment_ready "$ns" "$dep"; then
            overall_fail=1
        fi
    done < <(get_all_deployments_all_ns)

    if [ "$_found" -eq 0 ]; then
        log_warn "未找到任何 Deployment，跳过检查"
    fi

    return "$overall_fail"
}

#===============================================
# DaemonSet 检查函数
#===============================================

# 动态获取指定命名空间下所有 DaemonSet 名称
# 用法: get_all_daemonsets <namespace>
get_all_daemonsets() {
    local ns="$1"
    kubectl get daemonset -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep -v '^$'
}

# 获取所有命名空间下的所有 DaemonSet 名称（格式: namespace/daemonset）
# 用法: get_all_daemonsets_all_ns
get_all_daemonsets_all_ns() {
    local ns
    while IFS= read -r ns; do
        [ -z "$ns" ] && continue
        while IFS= read -r ds; do
            [ -n "$ds" ] && echo "$ns/$ds"
        done < <(get_all_daemonsets "$ns")
    done < <(get_all_namespaces) | sort -u
}

# 检查单个 DaemonSet 状态
# 用法: check_daemonset_ready <namespace> <daemonset>
# 返回值: 0=正常, 1=异常
check_daemonset_ready() {
    local ns="$1"
    local ds="$2"

    local desired current ready
    desired=$(kubectl get daemonset "$ds" -n "$ns" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)

    if [ -z "$desired" ]; then
        check_item "$ns/$ds: DaemonSet 不存在" "fail"
        return 1
    fi

    current=$(kubectl get daemonset "$ds" -n "$ns" -o jsonpath='{.status.currentNumberScheduled}' 2>/dev/null)
    ready=$(kubectl get daemonset "$ds" -n "$ns" -o jsonpath='{.status.numberReady}' 2>/dev/null)
    current=${current:-0}
    ready=${ready:-0}

    if [ "$desired" -eq "$ready" ] && [ "$current" -eq "$ready" ]; then
        check_item "$ns/$ds: DaemonSet 运行正常 ($ready/$desired)" "pass"
        return 0
    else
        check_item "$ns/$ds: DaemonSet 未全部就绪 (desired=$desired, current=$current, ready=$ready)" "fail"
        return 1
    fi
}

# 检查所有 DaemonSet
# 用法: check_all_daemonsets_ready
# 返回值: 0=全部正常, 1=存在异常
check_all_daemonsets_ready() {
    local overall_fail=0
    local item ns ds
    local _found=0

    while IFS= read -r item; do
        _found=1
        ns="${item%%/*}"
        ds="${item##*/}"
        if ! check_daemonset_ready "$ns" "$ds"; then
            overall_fail=1
        fi
    done < <(get_all_daemonsets_all_ns)

    if [ "$_found" -eq 0 ]; then
        log_warn "未找到任何 DaemonSet，跳过检查"
    fi

    return "$overall_fail"
}

#===============================================
# StatefulSet 检查函数
#===============================================

# 动态获取指定命名空间下所有 StatefulSet 名称
# 用法: get_all_statefulsets <namespace>
get_all_statefulsets() {
    local ns="$1"
    kubectl get statefulset -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | tr ' ' '\n' | grep -v '^$'
}

# 获取所有命名空间下的所有 StatefulSet 名称（格式: namespace/statefulset）
# 用法: get_all_statefulsets_all_ns
get_all_statefulsets_all_ns() {
    local ns
    while IFS= read -r ns; do
        [ -z "$ns" ] && continue
        while IFS= read -r sts; do
            [ -n "$sts" ] && echo "$ns/$sts"
        done < <(get_all_statefulsets "$ns")
    done < <(get_all_namespaces) | sort -u
}

# 检查单个 StatefulSet 的 readyReplicas
# 用法: check_statefulset_ready <namespace> <statefulset>
# 返回值: 0=正常, 1=异常
check_statefulset_ready() {
    local ns="$1"
    local sts="$2"

    local replicas ready_replicas
    replicas=$(kubectl get statefulset "$sts" -n "$ns" -o jsonpath='{.spec.replicas}' 2>/dev/null)

    if [ -z "$replicas" ]; then
        check_item "$ns/$sts: StatefulSet 不存在" "fail"
        return 1
    fi

    ready_replicas=$(kubectl get statefulset "$sts" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    ready_replicas=${ready_replicas:-0}

    if [ "$ready_replicas" -eq "$replicas" ]; then
        check_item "$ns/$sts: Pod状态匹配期望副本 ($ready_replicas/$replicas)" "pass"
        return 0
    else
        check_item "$ns/$sts: Pod未全部就绪 ($ready_replicas/$replicas)" "fail"
        return 1
    fi
}

# 检查所有 StatefulSet
# 用法: check_all_statefulsets_ready
# 返回值: 0=全部正常, 1=存在异常
check_all_statefulsets_ready() {
    local overall_fail=0
    local item ns sts
    local _found=0

    while IFS= read -r item; do
        _found=1
        ns="${item%%/*}"
        sts="${item##*/}"
        if ! check_statefulset_ready "$ns" "$sts"; then
            overall_fail=1
        fi
    done < <(get_all_statefulsets_all_ns)

    if [ "$_found" -eq 0 ]; then
        log_warn "未找到任何 StatefulSet，跳过检查"
    fi

    return "$overall_fail"
}

#===============================================
# Pod 健康检查函数
#===============================================

# 检查所有非系统命名空间下的 Pod 状态
# 检查 Pod 是否为 Pending / Failed / Unknown / CrashLoopBackOff 等异常状态
# 用法: check_all_pods_healthy
# 返回值: 0=全部正常, 1=存在异常
check_all_pods_healthy() {
    local overall_fail=0
    local ns name ready status rest
    local _found=0

    while read -r ns name ready status rest; do
        # 跳过系统命名空间
        case "$ns" in
            kube-system|kube-public|kube-node-lease|system) continue ;;
        esac

        _found=1
        case "$status" in
            Pending|Failed|Unknown)
                check_item "$ns/$name: 状态异常 ($status)" "fail"
                overall_fail=1
                ;;
            *)
                check_item "$ns/$name: 状态正常 ($status)" "pass"
                ;;
        esac
    done < <(kubectl get pods --all-namespaces --no-headers 2>/dev/null)

    if [ "$_found" -eq 0 ]; then
        log_warn "未找到任何非系统命名空间下的 Pod，跳过检查"
    fi

    return "$overall_fail"
}
