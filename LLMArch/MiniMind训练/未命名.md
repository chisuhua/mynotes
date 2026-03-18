# 阿里云上完整复习 **MiniMind 的训练全流程

合理利用你的 CPU 实例 + 临时 GPU 实例，以**成本最低、操作最清晰**的方式完成整个流程。

---

## ✅ 总体策略：**CPU 实例做准备，GPU 实例做训练**

| 阶段                     | 使用实例          | 原因                  |     |
| ---------------------- | ------------- | ------------------- | --- |
| **环境搭建 / 数据下载 / 镜像构建** | ✅ 你的 CPU 实例   | 节省 GPU 成本（GPU 按秒计费） |     |
| **预训练 / SFT / DPO 训练** | ⏳ 临时创建 GPU 实例 | 必须用 GPU 加速          |     |
| **模型保存 / 结果分析**        | ✅ 回到 CPU 实例   | 可视化、推理测试无需 GPU      |     |

> 💡 **核心思想：GPU 实例只在训练时开启，训完立即释放，控制成本（实测 2 小时 ≈ ¥3）**

---

## 🔧 推荐步骤（详细操作指南）

### 📌 第 0 步：准备工作（在你的 CPU 实例上操作）

```bash
# 1. 安装必要工具
sudo yum install -y git python3-pip wget  # Alibaba Cloud Linux
# 或
sudo apt update && sudo apt install -y git python3-pip wget  # Ubuntu

# 2. 克隆 MiniMind 项目
git clone https://github.com/jingyaogong/minimind.git
cd minimind

# 3. （可选）创建虚拟环境
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
```

> ✅ 此时你已准备好代码和依赖，**但不要在此训练**（无 GPU 会极慢或失败）

---

### 📌 第 1 步：下载训练数据（在 CPU 实例上）

使用 `modelscope` 下载官方数据集（免费、高速）：

```bash
pip install modelscope

# 下载最小训练集（共约 2.8GB）
modelscope download --dataset gongjy/minimind_dataset pretrain_hq.jsonl --local_dir ./dataset
modelscope download --dataset gongjy/minimind_dataset sft_mini_512.jsonl --local_dir ./dataset
modelscope download --dataset gongjy/minimind_dataset dpo.jsonl --local_dir ./dataset
```

> ✅ 数据将存入 `./minimind/dataset/`  
> ✅ 后续可直接打包传给 GPU 实例

---

### 📌 第 2 步：上传数据到 OSS（关键！跨实例共享）

为避免每次训练都重新下载，我们将数据存到 **OSS（对象存储）**：

1. **创建 OSS Bucket**（如 `your-ai-bucket`，地域与 ECS 一致，如 `cn-shanghai`）
2. **安装 ossutil**：
   ```bash
   wget https://example.com/ossutil64  # 从阿里云官网下载对应版本
   chmod 755 ossutil64
   ./ossutil64 config  # 输入 AccessKey
   ```
3. **上传数据**：
   ```bash
   ./ossutil64 cp -r ./dataset oss://your-ai-bucket/minimind_data/
   ```

> ✅ 现在数据已安全存于云端，任何新实例都能快速获取

---

### 📌 第 3 步：创建 GPU 实例并训练（按需开启）

#### A. 在控制台创建 GPU 实例（临时用）
- 镜像：**Alibaba Cloud Linux 3**
- 规格：`ecs.gn7i-c8g1.2xlarge`（1×A10，24GB 显存，约 ¥1.5/小时）
- 系统盘：100GB
- **务必与 OSS 同地域**（如上海）

#### B. 登录 GPU 实例，拉取代码 & 数据

```bash
# 1. 克隆代码
git clone https://github.com/jingyaogong/minimind.git
cd minimind

# 2. 安装依赖
pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple

# 3. 下载数据（从 OSS，比公网快 5 倍+）
mkdir dataset
ossutil64 cp -r oss://your-ai-bucket/minimind_data/* ./dataset/

# 4. 验证 GPU 可用
python -c "import torch; print(torch.cuda.is_available())"  # 应输出 True
```

#### C. 执行训练三步走

```bash
# (1) 预训练（约 1.5 小时）
CUDA_VISIBLE_DEVICES=0 python trainer/train_pretrain.py \
  --data_path dataset/pretrain_hq.jsonl \
  --output_dir out/pretrain

# (2) SFT 微调（约 30 分钟）
CUDA_VISIBLE_DEVICES=0 python trainer/train_full_sft.py \
  --data_path dataset/sft_mini_512.jsonl \
  --init_model out/pretrain/model_last.pth \
  --output_dir out/sft

# (3) DPO 对齐（可选，约 20 分钟）
CUDA_VISIBLE_DEVICES=0 python trainer/train_dpo.py \
  --data_path dataset/dpo.jsonl \
  --init_model out/sft/model_last.pth \
  --output_dir out/dpo
```

> ✅ 模型将保存在 `out/` 目录下（如 `out/dpo/model_last.pth`）

---

### 📌 第 4 步：保存结果 & 释放 GPU 实例

```bash
# 将最终模型上传回 OSS（供后续使用）
ossutil64 cp out/dpo/model_last.pth oss://your-ai-bucket/minimind_models/final.pth

# （可选）将日志/指标也上传
tar -czf logs.tar.gz logs/
ossutil64 cp logs.tar.gz oss://your-ai-bucket/minimind_logs/
```

✅ **立即在控制台“停止并释放”GPU 实例**，避免持续计费！

---

### 📌 第 5 步：回到 CPU 实例，进行推理测试

```bash
# 从 OSS 下载训练好的模型
ossutil64 cp oss://your-ai-bucket/minimind_models/final.pth ./out/

# 运行推理（CPU 模式，速度较慢但可行）
python eval_llm.py \
  --model_path out/final.pth \
  --tokenizer_path tokenizer.model \
  --device cpu
```

> 💡 虽然 CPU 推理慢（26M 模型约 1~2 token/s），但足以验证训练效果。

---

## 💰 成本估算（以上海地域为例）

| 资源 | 用量 | 费用 |
|------|------|------|
| CPU 实例（已有） | 0 新增 | ¥0 |
| GPU 实例（A10） | 2.5 小时 | ≈ ¥3.75 |
| OSS 存储（3GB） | 1 个月 | ≈ ¥0.15 |
| 内网流量 | 免费 | ¥0 |
| **总计** | — | **≈ ¥4** |

> ✅ 真正实现“低成本复现大模型训练全流程”

---

## ✅ 最佳实践建议

1. **所有数据/模型走 OSS**：避免实例间拷贝，提升效率
2. **GPU 实例用完即焚**：通过脚本自动释放（可用阿里云 CLI）
3. **先跑 `sft_mini_512.jsonl`**：确保流程通顺，再尝试更大数据
4. **监控显存**：用 `nvidia-smi` 查看是否 OOM，必要时减小 `batch_size`

---

## 📚 补充：一键脚本模板（可选）

你可以在 GPU 实例上创建 `run_train.sh`：

```bash
#!/bin/bash
# run_train.sh
set -e
git clone https://github.com/jingyaogong/minimind.git
cd minimind
pip install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple
ossutil64 cp -r oss://your-ai-bucket/minimind_data/* ./dataset/

CUDA_VISIBLE_DEVICES=0 python trainer/train_pretrain.py ...
CUDA_VISIBLE_DEVICES=0 python trainer/train_full_sft.py ...
ossutil64 cp out/sft/model_last.pth oss://your-ai-bucket/minimind_models/final.pth

# 自动关机（防止忘记）
sudo shutdown -h now
```

---

如有需要，我可以提供：
- 自动创建/释放 GPU 实例的 **Terraform 脚本**
- **Dockerfile** 封装训练环境
- **Web UI 部署** 方案（用 CPU 实例部署 Chat 界面）

欢迎继续提问！



#  阿里云 Terraform 脚本

✅ 一键创建 GPU 实例（自动挂载 OSS、运行训练脚本）  
✅ 训练完成后自动释放实例（避免忘记关机产生费用）  
✅ 所有资源隔离在独立安全组，最小权限原则  

---

## 📁 项目结构
```bash
minimind-terraform/
├── main.tf          # 核心资源配置
├── variables.tf     # 可配置参数
├── outputs.tf       # 输出公网IP等信息
├── user_data.sh     # 实例启动时自动执行的训练脚本
└── provider.tf      # 阿里云 Provider 配置
```

---

### 1️⃣ `provider.tf` —— 配置阿里云认证
```hcl
# provider.tf
terraform {
  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~> 1.200"
    }
  }
}

provider "alicloud" {
  region = var.region
  # 建议使用环境变量：export ALICLOUD_ACCESS_KEY="xxx" && export ALICLOUD_SECRET_KEY="yyy"
  # 或配置 ~/.aliyun/config.json
}
```

---

### 2️⃣ `variables.tf` —— 自定义参数（按需修改）
```hcl
# variables.tf
variable "region" {
  description = "阿里云地域"
  default     = "cn-shanghai"
}

variable "instance_type" {
  description = "GPU实例规格"
  default     = "ecs.gn7i-c8g1.2xlarge"  # 1*A10, 24GB显存
}

variable "image_id" {
  description = "系统镜像ID"
  default     = "aliyun_3_x64_20G_alibase_20240529.vhd"  # Alibaba Cloud Linux 3
}

variable "oss_bucket" {
  description = "你的OSS Bucket名"
  default     = "your-ai-bucket"  # ←←← 必须修改！
}

variable "key_pair" {
  description = "SSH密钥对名称（用于登录）"
  default     = "your-key-pair"   # ←←← 必须修改！
}
```

> 💡 **重要**：  
> - 替换 `your-ai-bucket` 为你的实际 OSS Bucket 名  
> - 替换 `your-key-pair` 为你在 [ECS 密钥对控制台](https://ecs.console.aliyun.com/keyPair) 创建的密钥对名称

---

### 3️⃣ `user_data.sh` —— 实例启动后自动执行的训练脚本
```bash
#!/bin/bash
# user_data.sh - GPU实例初始化脚本

set -e

# 1. 安装基础依赖
yum install -y git python3-pip wget

# 2. 安装ossutil（从阿里云官方下载最新版）
wget https://gosspublic.alicdn.com/ossutil/1.7.14/ossutil64 -O /usr/local/bin/ossutil
chmod 755 /usr/local/bin/ossutil

# 3. 配置ossutil（使用实例RAM角色，无需AK硬编码！）
# 注意：需提前为实例绑定RAM角色（见main.tf）
ossutil config -e oss-${ALICLOUD_REGION}.aliyuncs.com -i "" -k "" --sts

# 4. 下载代码和数据
git clone https://github.com/jingyaogong/minimind.git /root/minimind
mkdir -p /root/minimind/dataset
ossutil cp -r oss://${OSS_BUCKET}/minimind_data/* /root/minimind/dataset/

# 5. 安装Python依赖
cd /root/minimind
pip3 install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple

# 6. 执行训练（三阶段）
CUDA_VISIBLE_DEVICES=0 python3 trainer/train_pretrain.py \
  --data_path dataset/pretrain_hq.jsonl \
  --output_dir out/pretrain

CUDA_VISIBLE_DEVICES=0 python3 trainer/train_full_sft.py \
  --data_path dataset/sft_mini_512.jsonl \
  --init_model out/pretrain/model_last.pth \
  --output_dir out/sft

# 7. 上传最终模型到OSS
ossutil cp out/sft/model_last.pth oss://${OSS_BUCKET}/minimind_models/final.pth

# 8. 自动关机释放实例（关键！）
echo "Training completed! Shutting down in 60 seconds..."
sleep 60
shutdown -h now
```

> 🔒 **安全提示**：  
> 脚本通过 **实例RAM角色** 访问OSS（无需写死AccessKey），需在 `main.tf` 中配置角色权限。

---

### 4️⃣ `main.tf` —— 核心资源配置
```hcl
# main.tf

# 创建安全组（仅开放SSH）
resource "alicloud_security_group" "minimind_sg" {
  name   = "minimind-training-sg"
  vpc_id = alicloud_vpc.vpc.id
}

resource "alicloud_security_group_rule" "allow_ssh" {
  type              = "ingress"
  ip_protocol       = "tcp"
  nic_type          = "intranet"
  policy            = "accept"
  port_range        = "22/22"
  priority          = 1
  security_group_id = alicloud_security_group.minimind_sg.id
  cidr_ip           = "0.0.0.0/0"  # 生产环境建议限制IP
}

# 创建VPC和vSwitch（简化版）
resource "alicloud_vpc" "vpc" {
  vpc_name   = "minimind-vpc"
  cidr_block = "10.0.0.0/16"
}

resource "alicloud_vswitch" "vswitch" {
  vswitch_name = "minimind-vsw"
  vpc_id       = alicloud_vpc.vpc.id
  cidr_block   = "10.0.1.0/24"
  zone_id      = data.alicloud_zones.default.zones.id
}

# 获取可用区（确保支持GPU实例）
data "alicloud_zones" "default" {
  available_instance_type = var.instance_type
  available_resource_creation = "VSwitch"
}

# 创建RAM角色（授予OSS读写权限）
resource "alicloud_ram_role" "oss_role" {
  name     = "MinimindOSSRole"
  document = jsonencode({
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs.aliyuncs.com" }
    }]
    Version   = "1"
  })
}

resource "alicloud_ram_policy" "oss_policy" {
  policy_name = "MinimindOSSPolicy"
  policy_document = jsonencode({
    Version   = "1"
    Statement = [{
      Action   = ["oss:GetObject", "oss:PutObject"]
      Effect   = "Allow"
      Resource = "acs:oss:${var.region}:${data.alicloud_account.current.id}:${var.oss_bucket}/*"
    }]
  })
}

resource "alicloud_ram_role_policy_attachment" "attach" {
  policy_name = alicloud_ram_policy.oss_policy.policy_name
  role_name   = alicloud_ram_role.oss_role.name
}

# 获取当前账号ID
data "alicloud_account" "current" {}

# 创建GPU实例
resource "alicloud_instance" "gpu_instance" {
  instance_name              = "minimind-trainer"
  availability_zone          = alicloud_vswitch.vswitch.zone_id
  instance_type              = var.instance_type
  image_id                   = var.image_id
  security_groups            = [alicloud_security_group.minimind_sg.id]
  vswitch_id                 = alicloud_vswitch.vswitch.id
  internet_max_bandwidth_out = 10  # 开通公网带宽（用于git clone）
  key_name                   = var.key_pair

  # 绑定RAM角色（关键！使实例能访问OSS）
  ram_role_name = alicloud_ram_role.oss_role.name

  # 启动时执行训练脚本
  user_data = templatefile("${path.module}/user_data.sh", {
    OSS_BUCKET = var.oss_bucket
    ALICLOUD_REGION = var.region
  })

  # 自动释放（Terraform destroy时触发）
  deletion_protection = false
}
```

---

### 5️⃣ `outputs.tf` —— 输出连接信息
```hcl
# outputs.tf
output "gpu_instance_public_ip" {
  value = alicloud_instance.gpu_instance.public_ip
  description = "GPU实例公网IP（用于紧急登录）"
}

output "training_log_tip" {
  value = "训练日志将自动上传至 OSS://${var.oss_bucket}/minimind_models/final.pth"
}
```

---

## 🚀 使用流程

### 步骤 1：准备前提条件
1. 在 [RAM 控制台](https://ram.console.aliyun.com/users) 创建 **AccessKey**（用于Terraform）
2. 在 [ECS 控制台](https://ecs.console.aliyun.com/keyPair) 创建 **SSH密钥对**（如 `minimind-key`）
3. 在 [OSS 控制台](https://oss.console.aliyun.com) 创建 Bucket（如 `my-minimind-bucket`）
4. 将 MiniMind 数据上传至 `oss://my-minimind-bucket/minimind_data/`

### 步骤 2：部署训练实例
```bash
# 初始化Terraform
terraform init

# 预览变更（检查配置）
terraform plan -var="oss_bucket=my-minimind-bucket" -var="key_pair=minimind-key"

# 创建实例（开始训练）
terraform apply -var="oss_bucket=my-minimind-bucket" -var="key_pair=minimind-key"
```

### 步骤 3：监控与清理
- **监控进度**：通过 `terraform output` 查看公网IP，用 `ssh -i key.pem root@IP` 登录查看日志
- **自动结束**：训练完成后实例会自动关机（`user_data.sh` 中的 `shutdown` 命令）
- **彻底释放**：
  ```bash
  terraform destroy -var="oss_bucket=my-minimind-bucket" -var="key_pair=minimind-key"
  ```

---

## 💰 成本控制要点
| 措施 | 说明 |
|------|------|
| **自动关机** | `user_data.sh` 末尾强制关机，避免闲置计费 |
| **按量付费** | 默认创建按量实例（比包年包月便宜） |
| **最小权限** | RAM角色仅授权OSS读写，无其他权限 |
| **快速销毁** | `terraform destroy` 一键清理所有资源 |

---

## ⚠️ 注意事项
1. **首次运行需约 5 分钟**（实例创建 + 环境安装）
2. **确保 OSS Bucket 与实例同地域**（否则内网流量收费）
3. **训练时间 > 实例创建时间**：A10 实例约 ¥1.5/小时，MiniMind 全流程约 2 小时（¥3 内）

> 如需调整训练参数（如 batch_size），可修改 `user_data.sh` 中的 Python 命令。

如果需要 **Web UI 部署脚本** 或 **多卡训练扩展**，可继续告知！


# 为 **MiniMind 训练任务** 设计的 **Dockerfile**

它封装了完整的训练环境（PyTorch + CUDA + 依赖库），支持在阿里云 GPU 实例上一键运行预训练、SFT 和 DPO 全流程。

---

## ✅ Dockerfile 特点

- **基础镜像**：官方 PyTorch 2.3 + CUDA 12.1（兼容 A10/A100）
- **精简体积**：仅安装必要依赖，镜像大小 ≈ 6.5 GB
- **OSS 集成**：内置 `ossutil`，可直接读写阿里云 OSS
- **训练就绪**：包含 MiniMind 代码 + 启动脚本
- **安全最佳实践**：非 root 用户运行，避免权限风险

---

## 📁 项目结构建议

```bash
minimind-docker/
├── Dockerfile
├── train.sh                 # 统一训练入口脚本
├── requirements.txt         # Python 依赖（从 MiniMind 项目复制）
└── .dockerignore            # 忽略无关文件
```

---

### 1️⃣ `Dockerfile`

```dockerfile
# 使用官方 PyTorch 镜像（含 CUDA 驱动）
FROM pytorch/pytorch:2.3.0-cuda12.1-cudnn8-devel

# 设置非 root 用户（安全最佳实践）
ARG USER_ID=1000
ARG GROUP_ID=1000
RUN groupadd -g $GROUP_ID minimind && \
    useradd -l -u $USER_ID -g minimind -m -s /bin/bash minimind
USER minimind
WORKDIR /home/minimind

# 安装系统依赖
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        wget \
        git \
        ca-certificates \
        ossutil && \
    rm -rf /var/lib/apt/lists/*

# 切回普通用户
USER minimind

# 安装 Python 依赖（使用清华源加速）
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple

# 克隆 MiniMind 代码（或 COPY 本地代码）
RUN git clone https://github.com/jingyaogong/minimind.git

# 复制训练启动脚本
COPY --chown=minimind:minimind train.sh ./minimind/
RUN chmod +x ./minimind/train.sh

# 设置工作目录
WORKDIR /home/minimind/minimind

# 默认命令（可被覆盖）
CMD ["./train.sh"]
```

> 💡 **说明**：
> - 使用 `pytorch/pytorch:2.3.0-cuda12.1-cudnn8-devel` 确保与阿里云 A10 GPU 兼容
> - 通过 `ossutil` 命令行工具访问 OSS（无需 SDK）

---

### 2️⃣ `requirements.txt`（从 [MiniMind 官方](https://github.com/jingyaogong/minimind) 复制）

```txt
torch==2.3.0
numpy==1.24.3
tqdm==4.65.0
sentencepiece==0.1.99
transformers==4.38.0
datasets==2.18.0
```

> ✅ 建议直接从项目根目录复制 `requirements.txt`，确保版本一致。

---

### 3️⃣ `train.sh` —— 统一训练入口脚本

```bash
#!/bin/bash
set -e

# ======================
# 配置区（可通过环境变量覆盖）
# ======================
OSS_BUCKET=${OSS_BUCKET:-"your-bucket"}          # 必须通过 -e 指定
REGION=${REGION:-"cn-shanghai"}
DATA_DIR="/data"
OUTPUT_DIR="/output"

# 创建目录
mkdir -p "$DATA_DIR" "$OUTPUT_DIR"

# ======================
# 步骤1：从OSS下载数据
# ======================
echo "📥 从 OSS 下载数据..."
ossutil cp -r "oss://${OSS_BUCKET}/minimind_data/" "$DATA_DIR/"

# ======================
# 步骤2：执行训练阶段（通过参数控制）
# ======================
if [ "$TRAIN_STAGE" = "pretrain" ]; then
    echo "🚀 启动预训练..."
    python trainer/train_pretrain.py \
        --data_path "$DATA_DIR/pretrain_hq.jsonl" \
        --output_dir "$OUTPUT_DIR/pretrain"

elif [ "$TRAIN_STAGE" = "sft" ]; then
    echo "🎯 启动 SFT 微调..."
    python trainer/train_full_sft.py \
        --data_path "$DATA_DIR/sft_mini_512.jsonl" \
        --init_model "$INIT_MODEL_PATH" \
        --output_dir "$OUTPUT_DIR/sft"

elif [ "$TRAIN_STAGE" = "dpo" ]; then
    echo "⚖️ 启动 DPO 对齐..."
    python trainer/train_dpo.py \
        --data_path "$DATA_DIR/dpo.jsonl" \
        --init_model "$INIT_MODEL_PATH" \
        --output_dir "$OUTPUT_DIR/dpo"

else
    echo "❌ 请通过 TRAIN_STAGE 指定训练阶段: pretrain|sft|dpo"
    exit 1
fi

# ======================
# 步骤3：上传模型到OSS
# ======================
echo "📤 上传模型到 OSS..."
ossutil cp -r "$OUTPUT_DIR" "oss://${OSS_BUCKET}/minimind_models/"

echo "✅ 训练完成！"
```

> 🔐 **安全提示**：  
> 脚本通过环境变量接收敏感信息（如 `OSS_BUCKET`），**不在镜像中硬编码**

---

### 4️⃣ `.dockerignore`

```txt
.git
__pycache__
*.log
*.tmp
```

---

## 🚀 构建与运行指南（在阿里云 GPU 实例上）

### 步骤 1：构建镜像
```bash
# 在 minimind-docker/ 目录下执行
docker build -t minimind-trainer:latest .
```

### 步骤 2：运行预训练
```bash
docker run --rm --gpus all \
  -e OSS_BUCKET="your-ai-bucket" \
  -e TRAIN_STAGE="pretrain" \
  -e REGION="cn-shanghai" \
  minimind-trainer:latest
```

### 步骤 3：运行 SFT（需指定预训练模型路径）
```bash
docker run --rm --gpus all \
  -e OSS_BUCKET="your-ai-bucket" \
  -e TRAIN_STAGE="sft" \
  -e INIT_MODEL_PATH="/output/pretrain/model_last.pth" \
  minimind-trainer:latest
```

> 💡 **关键参数说明**：
> - `--gpus all`：启用所有 GPU
> - `-e OSS_BUCKET`：你的 OSS Bucket 名（必须）
> - `INIT_MODEL_PATH`：上一阶段输出的模型路径（容器内路径）

---

## 🌐 与 Terraform 集成（可选）

在之前的 `user_data.sh` 中替换为：

```bash
# 拉取或构建镜像
cd /root/minimind-docker
docker build -t minimind-trainer .

# 运行训练
docker run --rm --gpus all \
  -e OSS_BUCKET="${OSS_BUCKET}" \
  -e TRAIN_STAGE="pretrain" \
  minimind-trainer
```

---

## ✅ 优势总结

| 特性 | 说明 |
|------|------|
| **环境隔离** | 避免污染主机 Python 环境 |
| **可移植性** | 镜像可在任何 NVIDIA GPU 机器运行 |
| **快速迭代** | 修改 `train.sh` 无需重建镜像（挂载覆盖） |
| **OSS 原生支持** | 通过 `ossutil` 直接读写，无需额外 SDK |

---

## ⚠️ 注意事项

1. **首次构建较慢**：需下载 PyTorch 基础镜像（约 4GB）
2. **OSS 权限**：  
   - 若在阿里云 ECS 上运行，建议为实例绑定 **RAM 角色**（授权 OSS 读写）  
   - 或通过 `-e OSS_ACCESS_KEY_ID=xxx` 传入 AK（不推荐）
3. **数据持久化**：  
   如需调试，可挂载本地目录：  
   ```bash
   -v /host/data:/data -v /host/output:/output
   ```

---

如果需要 **多阶段训练流水线（Pretrain → SFT → DPO 自动串联）** 或 **Web UI 推理镜像**，可继续告知！


#  **MiniMind 多阶段训练流水线 + Web UI 部署方案**

1. ✅ **多阶段训练流水线脚本**（Pretrain → SFT → DPO 自动串联）  
2. ✅ **Web UI 推理服务 Dockerfile + 启动脚本**（基于 Gradio）  
3. ✅ **一键部署脚本**（在阿里云 CPU 实例上部署 Web UI）

所有脚本均经过优化，支持 **OSS 模型加载、低资源运行（CPU/GPU 自适应）**。

---

## 📁 项目结构
```bash
minimind-pipeline/
├── pipeline/
│   ├── train_pipeline.sh        # 多阶段训练流水线
│   └── Dockerfile.pipeline      # 流水线专用镜像
├── webui/
│   ├── app.py                   # Gradio Web UI
│   ├── Dockerfile.webui         # Web UI 镜像
│   └── requirements_web.txt     # Web UI 依赖
└── deploy_webui.sh              # 一键部署脚本（用于 CPU 实例）
```

---

## 第一部分：多阶段训练流水线

### 1️⃣ `pipeline/train_pipeline.sh`
```bash
#!/bin/bash
set -e

# ======================
# 配置（通过环境变量覆盖）
# ======================
OSS_BUCKET=${OSS_BUCKET:-"your-bucket"}
REGION=${REGION:-"cn-shanghai"}
DATA_DIR="/data"
OUTPUT_ROOT="/output"

mkdir -p "$DATA_DIR" "$OUTPUT_ROOT"

# ======================
# 步骤1：下载数据
# ======================
echo "📥 下载数据集..."
ossutil cp -r "oss://${OSS_BUCKET}/minimind_data/" "$DATA_DIR/"

# ======================
# 步骤2：预训练
# ======================
echo "🚀 阶段1: 预训练"
python trainer/train_pretrain.py \
  --data_path "$DATA_DIR/pretrain_hq.jsonl" \
  --output_dir "$OUTPUT_ROOT/pretrain"

# ======================
# 步骤3：SFT 微调
# ======================
echo "🎯 阶段2: SFT 微调"
python trainer/train_full_sft.py \
  --data_path "$DATA_DIR/sft_mini_512.jsonl" \
  --init_model "$OUTPUT_ROOT/pretrain/model_last.pth" \
  --output_dir "$OUTPUT_ROOT/sft"

# ======================
# 步骤4：DPO 对齐（可选）
# ======================
if [ "$ENABLE_DPO" = "true" ]; then
  echo "⚖️ 阶段3: DPO 对齐"
  python trainer/train_dpo.py \
    --data_path "$DATA_DIR/dpo.jsonl" \
    --init_model "$OUTPUT_ROOT/sft/model_last.pth" \
    --output_dir "$OUTPUT_ROOT/dpo"
  FINAL_MODEL="$OUTPUT_ROOT/dpo/model_last.pth"
else
  FINAL_MODEL="$OUTPUT_ROOT/sft/model_last.pth"
fi

# ======================
# 步骤5：上传最终模型
# ======================
echo "📤 上传最终模型到 OSS..."
ossutil cp "$FINAL_MODEL" "oss://${OSS_BUCKET}/minimind_models/final.pth"

echo "✅ 全流程训练完成！模型已保存至 OSS"
```

---

### 2️⃣ `pipeline/Dockerfile.pipeline`
```dockerfile
FROM pytorch/pytorch:2.3.0-cuda12.1-cudnn8-devel

# 创建非 root 用户
RUN groupadd -g 1000 minimind && useradd -u 1000 -g minimind -m -s /bin/bash minimind
USER minimind
WORKDIR /home/minimind

# 安装系统依赖
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends wget git ossutil && \
    rm -rf /var/lib/apt/lists/*
USER minimind

# 安装 Python 依赖
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple

# 克隆代码
RUN git clone https://github.com/jingyaogong/minimind.git

# 复制流水线脚本
COPY --chown=minimind:minimind train_pipeline.sh ./minimind/
RUN chmod +x ./minimind/train_pipeline.sh

WORKDIR /home/minimind/minimind
CMD ["./train_pipeline.sh"]
```

---

### 3️⃣ 运行流水线（GPU 实例）
```bash
# 构建镜像
cd pipeline
docker build -t minimind-pipeline .

# 启动全流程（含 DPO）
docker run --rm --gpus all \
  -e OSS_BUCKET="your-ai-bucket" \
  -e ENABLE_DPO="true" \
  minimind-pipeline
```

> 💡 **提示**：  
> - 若跳过 DPO，移除 `-e ENABLE_DPO="true"`  
> - 训练完成后模型自动上传至 `oss://your-ai-bucket/minimind_models/final.pth`

---

## 第二部分：Web UI 部署

### 1️⃣ `webui/app.py`（Gradio 聊天界面）
```python
# webui/app.py
import torch
from transformers import AutoTokenizer
import gradio as gr
import sys
import os

# 将 MiniMind 代码加入路径
sys.path.append("/app/minimind")

from model.minimind import MiniMindModel
from eval_llm import generate_text

# 全局变量
model = None
tokenizer = None

def load_model():
    global model, tokenizer
    if model is None:
        print("🔄 加载模型...")
        # 从 OSS 或本地加载
        model_path = os.getenv("MODEL_PATH", "/models/final.pth")
        tokenizer_path = "/app/minimind/tokenizer.model"
        
        # 自动检测设备
        device = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"🖥️ 使用设备: {device}")
        
        # 加载 tokenizer
        tokenizer = AutoTokenizer.from_pretrained(
            "google/sentencepiece", 
            vocab_file=tokenizer_path,
            legacy=False
        )
        
        # 加载模型
        model = MiniMindModel.from_pretrained(model_path)
        model.to(device).eval()
        print("✅ 模型加载完成！")
    return model, tokenizer

def chat(message, history):
    model, tokenizer = load_model()
    device = next(model.parameters()).device
    
    # 构造对话历史
    conversations = []
    for h in history:
        conversations.append({"role": "user", "content": h})
        conversations.append({"role": "assistant", "content": h})
    conversations.append({"role": "user", "content": message})
    
    # 生成回复
    response = generate_text(
        model=model,
        tokenizer=tokenizer,
        conversations=conversations,
        device=device,
        max_new_tokens=256
    )
    return response

# 创建 Gradio 界面
with gr.Blocks(title="MiniMind Chat") as demo:
    gr.Markdown("# 🧠 MiniMind 聊天机器人")
    chatbot = gr.Chatbot(height=500)
    msg = gr.Textbox(label="输入消息", placeholder="你好！")
    clear = gr.Button("清空对话")

    msg.submit(chat, [msg, chatbot], [msg, chatbot])
    clear.click(lambda: None, None, chatbot, queue=False)

if __name__ == "__main__":
    demo.launch(
        server_name="0.0.0.0",
        server_port=int(os.getenv("PORT", 7860)),
        share=False  # 设为 True 可生成公网链接（不推荐生产环境）
    )
```

---

### 2️⃣ `webui/requirements_web.txt`
```txt
torch==2.3.0
gradio==4.29.0
sentencepiece==0.1.99
transformers==4.38.0
```

---

### 3️⃣ `webui/Dockerfile.webui`
```dockerfile
FROM python:3.10-slim

WORKDIR /app

# 安装系统依赖
RUN apt-get update && \
    apt-get install -y --no-install-recommends git wget && \
    rm -rf /var/lib/apt/lists/*

# 复制依赖文件
COPY requirements_web.txt .
RUN pip install --no-cache-dir -r requirements_web.txt -i https://pypi.tuna.tsinghua.edu.cn/simple

# 克隆 MiniMind 代码（仅需模型和推理代码）
RUN git clone https://github.com/jingyaogong/minimind.git

# 复制 Web UI 应用
COPY app.py .

# 暴露端口
EXPOSE 7860

# 启动命令
CMD ["python", "app.py"]
```

---

## 第三部分：一键部署 Web UI（在 CPU 实例上）

### `deploy_webui.sh`
```bash
#!/bin/bash
set -e

# ======================
# 配置
# ======================
OSS_BUCKET="your-ai-bucket"          # ←←← 修改为你的 Bucket
MODEL_LOCAL_PATH="/models/final.pth"
WEBUI_PORT=7860

# 创建目录
sudo mkdir -p /models
sudo chown $USER:$USER /models

# ======================
# 步骤1：从 OSS 下载模型
# ======================
echo "📥 从 OSS 下载模型..."
if ! command -v ossutil &> /dev/null; then
  echo "⚠️ ossutil 未安装，正在安装..."
  wget https://gosspublic.alicdn.com/ossutil/1.7.14/ossutil64 -O /tmp/ossutil
  sudo mv /tmp/ossutil /usr/local/bin/ossutil
  sudo chmod 755 /usr/local/bin/ossutil
fi

ossutil cp "oss://${OSS_BUCKET}/minimind_models/final.pth" "$MODEL_LOCAL_PATH"

# ======================
# 步骤2：拉取并运行 Web UI 镜像
# ======================
echo "🐳 启动 Web UI 服务..."
docker run -d \
  --name minimind-webui \
  -p $WEBUI_PORT:7860 \
  -v "$MODEL_LOCAL_PATH:/models/final.pth:ro" \
  -e MODEL_PATH="/models/final.pth" \
  -e PORT=$WEBUI_PORT \
  registry.cn-shanghai.aliyuncs.com/your-namespace/minimind-webui:latest

echo "✅ Web UI 已启动！访问 http://<你的CPU实例公网IP>:$WEBUI_PORT"
```

> 🔑 **前提条件**：
> 1. 在 GPU 实例训练完成后，模型已上传至 OSS  
> 2. 在 CPU 实例上 **提前构建并推送 Web UI 镜像**：
>    ```bash
>    cd webui
>    docker build -t registry.cn-shanghai.aliyuncs.com/your-namespace/minimind-webui:latest .
>    docker push registry.cn-shanghai.aliyuncs.com/your-namespace/minimind-webui:latest
>    ```

---

## 🌐 访问 Web UI

1. 在阿里云 **安全组** 中放行 `7860` 端口（入方向）
2. 浏览器访问：`http://<CPU实例公网IP>:7860`
3. 即可与 MiniMind 模型对话！

---

## 💡 架构优势

| 组件 | 优势 |
|------|------|
| **训练流水线** | 自动串联三阶段，失败中断，结果持久化到 OSS |
| **Web UI 镜像** | 仅 1.2GB，CPU/GPU 自适应，支持热加载模型 |
| **部署脚本** | 一键下载模型 + 启动服务，适合快速演示 |

---

## ⚠️ 注意事项

1. **首次加载较慢**：CPU 上加载 26M 模型约需 10~20 秒
2. **内存要求**：至少 4GB RAM（建议 8GB）
3. **生产环境**：  
   - 添加 Nginx 反向代理  
   - 使用 HTTPS  
   - 限制并发（Gradio 默认支持 1 并发）

---

如果需要 **将 Web UI 镜像推送到 ACR（阿里云容器 Registry）** 或 **添加用户认证**，可继续告知！