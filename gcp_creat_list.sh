#!/bin/bash

# --- 变量配置 ---

# 实例创建部分
TARGET_PROJECT="xenon-muse-473222-j2"
ZONE="us-central1-c"
MACHINE_TYPE="e2-micro"
SOURCE_MACHINE_IMAGE="projects/xenon-muse-473222-j2/global/machineImages/x-ui-926"
INSTANCE_NAME_PREFIX="x-ui-926-instance" # 新实例名称的前缀
NUM_INSTANCES=8 # 要创建的实例数量

# IP 地址列出和格式化部分
IP_FORMAT_ZONE="us-central1-c" # 用于列出IP的区域
IP_PORT="1119" # SOCKS5 代理端口
SOCKS5_USER="socks5"
SOCKS5_PASS="socks5"

# --- 检查 gcloud 是否可用 ---
if ! command -v gcloud &> /dev/null
then
    echo "gcloud command could not be found. Please ensure you have the Google Cloud SDK installed and configured."
    exit 1
fi

# --- 阶段 1: 创建实例 ---
echo "--- Starting to create ${NUM_INSTANCES} instances ---"

for i in $(seq -w 1 ${NUM_INSTANCES}); do
    INSTANCE_NAME="${INSTANCE_NAME_PREFIX}-${i}"

    echo "Creating instance: ${INSTANCE_NAME} in zone ${ZONE}..."

    gcloud compute instances create "${INSTANCE_NAME}" \
        --project="${TARGET_PROJECT}" \
        --zone="${ZONE}" \
        --machine-type="${MACHINE_TYPE}" \
        --source-machine-image="${SOURCE_MACHINE_IMAGE}" \
        --create-disk=auto-delete=yes,boot=yes,mode=rw,size=20,type=pd-balanced \
        --network-tier=PREMIUM \
        --stack-type=IPV4_ONLY \
        --subnet=default \
        --metadata=enable-osconfig=TRUE \
        --maintenance-policy=MIGRATE \
        --provisioning-model=STANDARD \
        --service-account=605288342581-compute@developer.gserviceaccount.com \
        --scopes=https://www.googleapis.com/auth/cloud-platform \
        --enable-display-device \
        --tags=http-server,https-server,lb-health-check \
        --no-shielded-secure-boot \
        --shielded-vtpm \
        --shielded-integrity-monitoring \
        --labels=goog-ops-agent-policy=v2-x86-template-1-4-0,goog-ec-src=vm_add-gcloud \
        --quiet

    # --- 可选：Windows 密码设置 ---
    # 如果您创建的是 Windows 实例，并且需要设置密码，请取消下面的注释并填写
    # YOUR_USERNAME="your_admin_user" # 替换为您想要的管理员用户名
    # YOUR_PASSWORD="your_strong_password_123!" # 替换为您想要的强密码
    # echo "Setting Windows password for ${INSTANCE_NAME}..."
    # gcloud compute reset-windows-password "${INSTANCE_NAME}" \
    #     --project="${TARGET_PROJECT}" \
    #     --zone="${ZONE}" \
    #     --user="${YOUR_USERNAME}" \
    #     --password="${YOUR_PASSWORD}" \
    #     --quiet

    echo "Instance ${INSTANCE_NAME} created successfully."
    echo ""
    sleep 5 # 短暂等待，避免瞬间大量请求
done

echo "--- Finished creating instances ---"
echo ""

# --- 增加 10 秒的等待时间 ---
echo "Waiting for 10 seconds before listing IP addresses..."
sleep 10

# --- 阶段 2: 列出公网 IP 地址并格式化 ---
echo "--- Listing public IP addresses in SOCKS5 format ---"

gcloud compute instances list \
    --zones=${IP_FORMAT_ZONE} \
    --format="value(networkInterfaces[0].accessConfigs[0].natIP, name)" \
    --project=${TARGET_PROJECT} \
  | while read -r ip_address instance_name; do
      # 仅当 ip_address 不为空时才进行处理
      if [[ -n "$ip_address" ]]; then
          echo "socks5://${SOCKS5_USER}:${SOCKS5_PASS}@${ip_address}:${IP_PORT}"
      fi
    done

echo "--- Finished listing IP addresses ---"

exit 0
