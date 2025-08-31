#!/bin/bash

# --- 設定變數 ---
# 目標 AWS 區域
REGION="us-west-2"
# 刪除 EC2 後要 ping 的內網 IP
PING_IP="10.241.43.97"
# Ping 的超時時間 (秒)
TIMEOUT_SECONDS=120

# --- 步驟 1: 查找並過濾 EC2 執行個體 ---
echo "正在區域 $REGION 中查找執行中或已停止的 EC2 執行個體..."

# 查找所有非 "terminated" 狀態的執行個體 ID
INSTANCE_IDS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --query "Reservations[*].Instances[?State.Name!='terminated'].InstanceId" \
  --output text)

# --- 步驟 2: 根據查找結果執行操作 ---

# 檢查 INSTANCE_IDS 變數是否為空
if [ -z "$INSTANCE_IDS" ]; then
  # 如果為空，表示沒有找到執行個體
  echo "在區域 $REGION 中沒有找到任何需要刪除的 EC2 執行個體。"
  exit 0
else
  # 如果不為空，表示找到了執行個體
  echo "在區域 $REGION 中找到以下 EC2 執行個體，準備刪除："
  echo "$INSTANCE_IDS"
  
  # 刪除 (終止) 找到的執行個體
  aws ec2 terminate-instances \
    --region "$REGION" \
    --instance-ids $INSTANCE_IDS \
    --output json > /dev/null # 將成功時的 JSON 輸出導向到 null，保持介面乾淨

  # 檢查終止命令的執行結果
  if [ $? -ne 0 ]; then
    echo "錯誤：發送刪除 EC2 執行個體的指令失敗，腳本終止。"
    exit 1
  fi
  
  echo "成功發送刪除指令。現在開始監控內網 IP: $PING_IP"
  
  # --- 步驟 3: Ping 內網 IP 並設定超時 ---
  
  # 記錄開始時間
  START_TIME=$(date +%s)

  # 迴圈檢查，直到超時
  while true; do
    # 記錄當前時間
    CURRENT_TIME=$(date +%s)
    # 計算已經過的時間
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))

    # 檢查是否超時
    if [ "$ELAPSED_TIME" -ge "$TIMEOUT_SECONDS" ]; then
      echo "失敗：操作超時！在 $TIMEOUT_SECONDS 秒內無法 ping 通 $PING_IP。"
      exit 1
    fi

    # 執行 ping 指令
    # -c 1: 只發送一個封包
    # -W 1: 等待回應的時間為 1 秒
    # >/dev/null 2>&1: 隱藏所有輸出，我們只關心結束代碼
    ping -c 1 -W 1 "$PING_IP" >/dev/null 2>&1
    
    # 檢查 ping 指令的結束代碼
    if [ $? -eq 0 ]; then
      # 如果結束代碼為 0，表示 ping 成功
      echo "成功！已成功 ping 通 $PING_IP。"
      exit 0
    else
      # 如果 ping 失敗，則等待 1 秒後重試
      # 使用 \r 來讓游標回到行首，實現動態更新進度
      echo -ne "無法連線，正在重試... (已過 $ELAPSED_TIME / $TIMEOUT_SECONDS 秒)\r"
      sleep 1
    fi
  done
fi
