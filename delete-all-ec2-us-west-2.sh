#!/bin/bash

# 設定目標區域
REGION="us-west-2"

# 查找 us-west-2 區域中所有非已終止狀態的 EC2 執行個體 ID
INSTANCE_IDS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --query "Reservations[*].Instances[?State.Name!='terminated'].InstanceId" \
  --output text)

# 檢查 INSTANCE_IDS 變數是否為空
if [ -z "$INSTANCE_IDS" ]; then
  # 如果為空，表示沒有找到執行個體
  echo "在區域 $REGION 中沒有找到正在執行或已停止的 EC2 執行個體。"
else
  # 如果不為空，表示找到了執行個體
  echo "在區域 $REGION 中找到以下 EC2 執行個體，正在嘗試刪除..."
  echo "$INSTANCE_IDS"
  
  # 刪除 (終止) 找到的執行個體
  aws ec2 terminate-instances \
    --region "$REGION" \
    --instance-ids $INSTANCE_IDS \
    --output json

  # 檢查終止命令的結束代碼
  if [ $? -eq 0 ]; then
    echo "成功發送刪除請求。請注意，執行個體終止需要一些時間。"
  else
    echo "刪除執行個體時發生錯誤。"
  fi
fi
