ha预检查
bash k8s_ha_prepare.sh
驱逐 -> 关机 -> 重启 -> 检查
# 节点1
bash ./k8s_ha_drill.sh kind-ha-worker
bash ./k8s_ha_check.sh kind-ha-worker
# 节点2
bash ./k8s_ha_drill.sh kind-ha-worker2
bash ./k8s_ha_check.sh kind-ha-worker2
# 节点3
bash ./k8s_ha_drill.sh kind-ha-worker3
bash ./k8s_ha_check.sh kind-ha-worker3
# 节点4
bash ./k8s_ha_drill.sh kind-ha-worker4
bash ./k8s_ha_check.sh kind-ha-worker4
# 节点5
bash ./k8s_ha_drill.sh kind-ha-worker5
bash ./k8s_ha_check.sh kind-ha-worker5
# 全部节点检查完毕，最后兜底检查
bash ./k8s_ha_recovery.sh
