#!/bin/sh
#===============================================
# K8S高可用演练 - 公共函数库
# 所有脚本通过 source 引用此文件
#===============================================

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

# 通过IP获取对应的K8s节点名称
# 用法: get_node_by_ip <ip>
# 输出: 节点名（空则未找到）
get_node_by_ip() {
    local ip="$1"
    kubectl get nodes -o jsonpath="{range .items[*]}{.status.addresses[?(@.type==\"InternalIP\")].address}{\"\\t\"}{.metadata.name}{\"\\n\"}{end}" 2>/dev/null | \
        awk -F'\t' -v ip="$ip" '$1==ip {print $2; exit}' 2>/dev/null
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
    local ns dep
    local _oldifs="$IFS"
    IFS='
'
    set -f
    for ns in $(get_all_namespaces); do
        [ -z "$ns" ] && continue
        for dep in $(get_all_deployments "$ns"); do
            [ -n "$dep" ] && echo "$ns/$dep"
        done
    done | sort -u
    IFS="$_oldifs"
    set +f
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
    local _oldifs="$IFS"
    IFS='
'
    set -f
    for ns in $(get_all_namespaces); do
        [ -z "$ns" ] && continue
        "$func" "$ns" "$@"
    done
    IFS="$_oldifs"
    set +f
}

#===============================================
# 基础服务检查函数
#===============================================

# 通过节点名称获取对应的K8s节点IP
# 用法: get_node_ip <node_name>
# 输出: 节点IP（空则未找到）
get_node_ip() {
    local node_name="$1"
    kubectl get nodes -o jsonpath="{range .items[*]}{.metadata.name}{\"\\t\"}{.status.addresses[?(@.type==\"InternalIP\")].address}{\"\\n\"}{end}" 2>/dev/null | \
        awk -F'\t' -v name="$node_name" '$1==name {print $2; exit}' 2>/dev/null
}

# 检查节点上的 kubelet 和 docker 服务状态
# 用法: check_node_services <node_name>
# 参数: node_name - 节点名称（必填）
check_node_services() {
    local node_name="$1"
    local node_ip
    node_ip=$(get_node_ip "$node_name")

    if [ -z "$node_ip" ]; then
        check_item "节点 ${node_name} 无法获取IP" "fail"
        return 1
    fi

    echo "[INFO] 检查节点 ${node_name} (${node_ip}) 的基础服务..."

    # 检查节点是否 Ready
    local node_status
    node_status=$(kubectl get node "$node_name" --no-headers 2>/dev/null | awk '{print $2}')
    if [ "$node_status" = "Ready" ]; then
        check_item "节点 ${node_name} 状态: Ready" "pass"
    else
        check_item "节点 ${node_name} 状态异常: $node_status" "fail"
    fi

    # 通过 ansible-agent 检查 kubelet 和 docker 服务
    if ! command -v ansible-agent >/dev/null 2>&1; then
        check_item "ansible-agent 命令不存在，跳过服务检查" "warn"
        return
    fi

    # 检查 kubelet 服务
    local kubelet_status
    kubelet_status=$(ansible-agent -H "${node_ip}" exec "systemctl is-active kubelet" 2>/dev/null)
    if [ "$kubelet_status" = "active" ]; then
        check_item "节点 ${node_name} (${node_ip}) kubelet 服务运行正常（active）" "pass"
    else
        check_item "节点 ${node_name} (${node_ip}) kubelet 服务异常（${kubelet_status:-执行失败}）" "fail"
    fi

    # 检查 docker 服务
    local docker_status
    docker_status=$(ansible-agent -H "${node_ip}" exec "systemctl is-active docker" 2>/dev/null)
    if [ "$docker_status" = "active" ]; then
        check_item "节点 ${node_name} (${node_ip}) docker 服务运行正常（active）" "pass"
    else
        check_item "节点 ${node_name} (${node_ip}) docker 服务异常（${docker_status:-执行失败}）" "fail"
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
log_info() { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }
log_step() { printf "${BLUE}[STEP]${NC} %s\n" "$1"; }

# 输出检查项（累加 CHECK_PASS/CHECK_WARN/CHECK_FAIL）
check_item() {
    local desc="$1"
    local status="$2"
    case "$status" in
        pass)
            CHECK_PASS=$((CHECK_PASS + 1))
            ;;
        warn)
            printf "  ⚠ %s\n" "$desc"
            CHECK_WARN=$((CHECK_WARN + 1))
            ;;
        fail)
            printf "  ✗ %s\n" "$desc"
            CHECK_FAIL=$((CHECK_FAIL + 1))
            ;;
    esac
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
        # 尝试恢复，根据恢复结果返回
        if recover_deployment "$ns" "$dep"; then
            # 修复成功，减少 CHECK_FAIL（因为之前 check_item ... "fail" 增加了）
            CHECK_FAIL=$((CHECK_FAIL - 1))
            check_item "$ns/$dep: 恢复后Pod状态正常" "pass"
            return 0
        else
            return 1
        fi
    fi
}

# 恢复 Deployment（检查失败后调用）
# 用法: recover_deployment <namespace> <deployment>
# 返回值: 0=修复成功, 1=修复失败
recover_deployment() {
    local ns="$1"
    local dep="$2"
    local replicas

    # 获取期望副本数
    replicas=$(kubectl get deployment "$dep" -n "$ns" -o jsonpath='{.spec.replicas}' --request-timeout="${KUBECTL_TIMEOUT}s" 2>/dev/null)
    replicas=${replicas:-1}

    log_warn "$ns/$dep: 删除未就绪的 Pod 以触发重启"
    local _oldifs="$IFS"
    IFS='
'
    set -f
    local line pod_name pod_status
    # 通过 Pod 名称前缀匹配（Deployment 的 Pod 名称格式为 dep-xxx-xxx）
    for line in $(kubectl get pods -n "$ns" --no-headers 2>/dev/null | awk -v dep="$dep" '$1 ~ "^" dep "-" {print $0}'); do
        [ -z "$line" ] && continue
        pod_name=$(echo "$line" | awk '{print $1}')
        pod_status=$(echo "$line" | awk '{print $3}')
        case "$pod_status" in
            Pending|Failed|Unknown)
                kubectl delete pod "$pod_name" -n "$ns" --request-timeout="${KUBECTL_TIMEOUT}s" >/dev/null 2>&1
                check_item "$ns/$pod_name: 已删除（状态: $pod_status）" "warn"
                ;;
        esac
    done
    IFS="$_oldifs"
    set +f

    # 检查修复结果
    sleep 15
    local ready_replicas
    ready_replicas=$(kubectl get deployment "$dep" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    ready_replicas=${ready_replicas:-0}

    if [ "$ready_replicas" -eq "$replicas" ]; then
        return 0
    elif [ "$ready_replicas" -eq $((replicas - 1)) ]; then
        check_item "$ns/$dep: Pod 就绪数少一个 ($ready_replicas/$replicas)，请检查" "warn"
        return 0
    else
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
    local _oldifs="$IFS"
    IFS='
'
    set -f

    for item in $(get_all_deployments_all_ns); do
        _found=1
        ns="${item%%/*}"
        dep="${item##*/}"
        if ! check_deployment_ready "$ns" "$dep"; then
            overall_fail=1
        fi
    done

    if [ "$_found" -eq 0 ]; then
        log_warn "未找到任何 Deployment，跳过检查"
    fi

    IFS="$_oldifs"
    set +f
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
    local ns ds
    local _oldifs="$IFS"
    IFS='
'
    set -f
    for ns in $(get_all_namespaces); do
        [ -z "$ns" ] && continue
        for ds in $(get_all_daemonsets "$ns"); do
            [ -n "$ds" ] && echo "$ns/$ds"
        done
    done | sort -u
    IFS="$_oldifs"
    set +f
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
    local _oldifs="$IFS"
    IFS='
'
    set -f

    for item in $(get_all_daemonsets_all_ns); do
        _found=1
        ns="${item%%/*}"
        ds="${item##*/}"
        if ! check_daemonset_ready "$ns" "$ds"; then
            overall_fail=1
        fi
    done

    if [ "$_found" -eq 0 ]; then
        log_warn "未找到任何 DaemonSet，跳过检查"
    fi

    IFS="$_oldifs"
    set +f
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
    local ns sts
    local _oldifs="$IFS"
    IFS='
'
    set -f
    for ns in $(get_all_namespaces); do
        [ -z "$ns" ] && continue
        for sts in $(get_all_statefulsets "$ns"); do
            [ -n "$sts" ] && echo "$ns/$sts"
        done
    done | sort -u
    IFS="$_oldifs"
    set +f
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
        # 尝试修复，根据恢复结果返回
        if recover_statefulset "$ns" "$sts"; then
            # 修复成功后，readyReplicas 可能比 replicas 少一个，也算成功
            ready_replicas=$(kubectl get statefulset "$sts" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
            ready_replicas=${ready_replicas:-0}
            if [ "$ready_replicas" -eq "$replicas" ]; then
                return 0
            elif [ "$ready_replicas" -eq $((replicas - 1)) ]; then
                check_item "$ns/$sts: Pod就绪数少一个 ($ready_replicas/$replicas)，请检查" "warn"
                return 0
            else
                return 1
            fi
        else
            return 1
        fi
    fi
}

# 恢复 StatefulSet（检查失败后调用）
# 用法: recover_statefulset <namespace> <statefulset>
# 返回值: 0=修复成功, 1=修复失败
recover_statefulset() {
    local ns="$1"
    local sts="$2"
    local replicas

    # 获取期望副本数
    replicas=$(kubectl get statefulset "$sts" -n "$ns" -o jsonpath='{.spec.replicas}' --request-timeout="${KUBECTL_TIMEOUT}s" 2>/dev/null)
    replicas=${replicas:-1}

    # 判断是否为 Redis（名称或标签包含 redis）
    local is_redis=0
    echo "$sts" | grep -i 'redis' >/dev/null 2>&1 && is_redis=1
    if [ "$is_redis" -eq 0 ]; then
        local image
        image=$(kubectl get statefulset "$sts" -n "$ns" -o jsonpath='{.spec.template.spec.containers[*].image}' 2>/dev/null)
        echo "$image" | grep -i 'redis' >/dev/null 2>&1 && is_redis=1
    fi

    if [ "$is_redis" -eq 1 ]; then
        log_warn "$ns/$sts: 检测到 Redis，执行缩容到0再扩容到$replicas"
        # 如果是unit-private命名空间
        if [ "$ns" == "unit-private" ]; then
            kubectl scale sts redis-redis -n  unit-private --replicas 0
            kubectl delete pod -n  unit-private redis-init-cluster
            kubectl apply -f init.yaml -n  unit-private 
            kubectl scale sts redis-redis -n  unit-private --replicas 6
        else
            kubectl scale statefulset "$sts" -n "$ns" --replicas=0 --request-timeout="${KUBECTL_TIMEOUT}s" >/dev/null 2>&1
            sleep 3
            kubectl scale statefulset "$sts" -n "$ns" --replicas="$replicas" --request-timeout="${KUBECTL_TIMEOUT}s" >/dev/null 2>&1
            sleep 15
        fi
        check_item "$ns/$sts: Redis 已缩容到0再扩容到$replicas" "warn"
    else
        log_warn "$ns/$sts: 删除未就绪的 Pod 以触发重启"
        local _oldifs="$IFS"
        IFS='
'
        set -f
        local line pod_name pod_status
        # 通过 Pod 名称前缀匹配（StatefulSet 的 Pod 名称格式为 sts-0, sts-1, ...）
        for line in $(kubectl get pods -n "$ns" --no-headers 2>/dev/null | awk -v sts="$sts" '$1 ~ "^" sts "-[0-9]+" {print $0}'); do
            [ -z "$line" ] && continue
            pod_name=$(echo "$line" | awk '{print $1}')
            pod_status=$(echo "$line" | awk '{print $3}')
            case "$pod_status" in
                Pending|Failed|Unknown)
                    kubectl delete pod "$pod_name" -n "$ns" --request-timeout="${KUBECTL_TIMEOUT}s" >/dev/null 2>&1
                    check_item "$ns/$pod_name: 已删除（状态: $pod_status）" "warn"
                    ;;
            esac
        done
        IFS="$_oldifs"
        set +f
    fi

    # 检查修复结果
    sleep 15
    local ready_replicas
    ready_replicas=$(kubectl get statefulset "$sts" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    ready_replicas=${ready_replicas:-0}

    if [ "$ready_replicas" -eq "$replicas" ]; then
        return 0
    else
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
    local _oldifs="$IFS"
    IFS='
'
    set -f

    for item in $(get_all_statefulsets_all_ns); do
        _found=1
        ns="${item%%/*}"
        sts="${item##*/}"
        if ! check_statefulset_ready "$ns" "$sts"; then
            overall_fail=1
        fi
    done

    if [ "$_found" -eq 0 ]; then
        log_warn "未找到任何 StatefulSet，跳过检查"
    fi

    IFS="$_oldifs"
    set +f
    return "$overall_fail"
}

#===============================================
# Pod 健康检查函数
#===============================================

# 检查所有非系统命名空间下的 Pod 状态
# 检查 Pod 是否为 Pending / Failed / Unknown 等异常状态
# 用法: check_all_pods_healthy
# 返回值: 0=全部正常, 1=存在异常
check_all_pods_healthy() {
    local overall_fail=0
    local _found=0
    local _oldifs="$IFS"
    local line ns name ready status restarts age
    local _pods

    _pods=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null)
    if [ -z "$_pods" ]; then
        log_warn "未找到任何 Pod，跳过检查"
        return 0
    fi

    IFS='
'
    set -f
    for line in $_pods; do
        # 跳过系统命名空间
        ns=$(echo "$line" | awk '{print $1}')
        case "$ns" in
            kube-system|kube-public|kube-node-lease|system) continue ;;
        esac

        _found=1
        name=$(echo "$line" | awk '{print $2}')
        ready=$(echo "$line" | awk '{print $3}')
        status=$(echo "$line" | awk '{print $4}')

        case "$status" in
            Pending|Failed|Unknown)
                check_item "$ns/$name: 状态异常 ($status)" "fail"
                overall_fail=1
                ;;
            *)
                check_item "$ns/$name: 状态正常 ($status)" "pass"
                ;;
        esac
    done
    IFS="$_oldifs"
    set +f

    if [ "$_found" -eq 0 ]; then
        log_warn "未找到任何非系统命名空间下的 Pod，跳过检查"
    fi

    return "$overall_fail"
}
