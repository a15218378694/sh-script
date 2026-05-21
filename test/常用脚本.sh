kubectl scale  --replicas=2 -n default
# 获取所有namespace的pod，要看到状态
kubectl get pod -A
# 获取所有namespace的处于Running的pod的总数量
kubectl get pod -A -o wide | grep Running | wc -l
# 获取所有namespace的处于Pending的pod的总数量
kubectl get pod -A -o wide | grep Pending | wc -l
kubectl get deployment auth
# 获取单个pod信息
kubectl get pod auth-784446444-48444 -o wide -n default

kubectl describe pod auth-784446444-48444 -n default


bash k8s_ha_prepare.sh
bash k8s_ha_drill.sh kind-ha-worker2
bash k8s_ha_pending_check.sh
bash k8s_ha_check.sh kind-ha-worker2 test

bash k8s_ha_check.sh kind-ha-worker2 prod

bash k8s_ha_recovery.sh


# 查看该节点上所有 Pod 及其运行状态
kubectl get pods --all-namespaces --field-selector spec.nodeName=<节点名称> -o wide

# 查看节点上所有 Pod 的体积大小，找出那个特别大的“刺头”
kubectl get pods --all-namespaces --field-selector spec.nodeName=<节点名称> -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,SIZE:.status.containerStatuses[0].restartCount" --sort-by=.status.containerStatuses[0].restartCount
# 或者更直接地，在宿主机上查看 /var/log/pods 目录的体积
du -sh /var/log/pods/* | sort -rh | head -10



# 1. 先中断当前的 drain 命令 (Ctrl+C)

# 2. 找出卡住的 Pod 后，给它打上万能容忍标签 (替换实际的 NAMESPACE 和 POD_NAME)
kubectl annotate pod <POD_NAME> -n <NAMESPACE> scheduler.alpha.kubernetes.io/tolerations='[{"key":"node.kubernetes.io/all","effect":"NoSchedule","operator":"Exists"}]'

# 3. 重新执行 drain 命令，此时应该能秒过
kubectl drain <节点名称> --ignore-daemonsets --delete-emptydir-data --force