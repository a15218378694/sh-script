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




bash k8s_ha_prepare.sh
bash k8s_ha_drill.sh kind-ha-worker2
bash k8s_ha_pending_check.sh
bash k8s_ha_check.sh kind-ha-worker2 test

bash k8s_ha_check.sh kind-ha-worker2 prod

bash k8s_ha_recovery.sh
