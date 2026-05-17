#!/bin/bash
#===============================================
# K8S高可用演练 - 统一配置
# 所有脚本通过 source 引用此文件
#===============================================

# 命名空间列表（自动扫描，无需手动配置）
# 脚本将自动获取集群中所有非系统命名空间的列表
# 如需排除特定命名空间，请在 k8s_ha_lib.sh 的 get_all_namespaces 函数中配置

# 需要验证副本数>=2的 Deployment 列表（格式：namespace/deployment）
# 演练/恢复不依赖此列表，依赖动态发现所有命名空间下的全量deploy
# 数组格式，安全遍历
HA_SCALE_DEPLOYS=(
    "default/unit-adaptor-service"
    "kube-system/coredns"
    "tianniu/docker-distribution"
    "unit-private/aicp-nlu"
    "unit-private/backend"
    "unit-private/core"
    "unit-private/transfer"
    "unit-private/unit-nlu"
    "unit-private/unit-private-assoc"
    "unit-private/unit-private-basequ"
    "unit-private/unit-private-chat"
    "unit-private/unit-private-prenlu-online"
    "unit-private/unit-private-qexpand"
    "unit-private/unit-private-querysim"
    "unit-private/unit-private-rewrite"
    "unit-private/unit-private-similarity-platform"
    "unit-private/unit-private-similarity-server"
    "unit-private/unit-private-smart"
    "unit-private/unit-private-wordweight"
    "unit-private/vector-search"
    "digital-human/a2a-common"
    "digital-human/alita-web"
    "digital-human/asr-adaptor"
    "digital-human/asr-proxy"
    "digital-human/auth-web"
    "digital-human/character-web"
    "digital-human/dh-user"
    "digital-human/digital-human-agent-aicp"
    "digital-human/digital-human-agent-aicp-external"
    "digital-human/digital-human-cloud"
    "digital-human/digital-human-console"
    "digital-human/digital-human-llm-dm"
    "digital-human/digital-human-plat"
    "digital-human/digital-human-resource-pool"
    "digital-human/janus-nginx"
    "digital-human/leaflet-web"
    "digital-human/render-proxy-a2a-real-time"
    "digital-human/render-proxy-ue5-huishang"
    "digital-human/tts-adaptor"
)

# 目标副本数（扩容到多少副本）
TARGET_REPLICAS=2

# kubectl 请求超时时间（秒）
KUBECTL_TIMEOUT=30

# 高可用节点标签键
NODE_LABEL_KEY="high-availability"

# 每轮演练间休眠秒数
SLEEP_BETWEEN=30
