#!/bin/bash

# Soundness CLI 管理脚本（Docker 版本）
# 日志文件
LOG_FILE="soundness_cli_script.log"

# 函数：记录日志
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 函数：检查命令是否成功
check_error() {
    if [ $? -ne 0 ]; then
        log_message "错误: $1"
        exit 1
    fi
}

# 函数：检查 Docker 和 Docker Compose 是否已安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_message "Docker 未安装，正在安装 Docker..."
        sudo apt-get update
        sudo apt-get install -y docker.io docker-compose-plugin
        sudo systemctl start docker
        sudo systemctl enable docker
        check_error "Docker 安装失败"
        log_message "Docker 安装成功"
    else
        log_message "Docker 已安装：$(docker --version)"
    fi
    if ! docker compose version &> /dev/null; then
        log_message "错误: Docker Compose 未安装"
        log_message "请运行 'sudo apt-get install docker-compose-plugin' 或确保 Docker Compose 可用"
        exit 1
    fi
    log_message "Docker Compose 已安装：$(docker compose version)"
}

# 函数：确保 Soundness CLI 源代码存在
ensure_source_code() {
    if [ ! -d "/root/soundness-layer" ]; then
        log_message "未找到 Soundness CLI 源代码，正在克隆..."
        cd /root
        git clone https://github.com/soundnesslabs/soundness-layer.git
        check_error "克隆 Soundness CLI 源代码失败"
        cd soundness-layer
        log_message "Soundness CLI 源代码已克隆到 /root/soundness-layer"
    else
        cd /root/soundness-layer
        log_message "Soundness CLI 源代码已存在：/root/soundness-layer"
    fi
    if [ ! -f "soundness-cli/Cargo.toml" ] && [ ! -f "Cargo.toml" ]; then
        log_message "错误: 未找到 Cargo.toml 文件"
        log_message "请确认 soundness-layer 仓库结构，是否包含 soundness-cli/Cargo.toml 或 Cargo.toml"
        exit 1
    fi
    log_message "Cargo.toml 已存在"
}

# 函数：确保 Docker Compose 文件和 .dockerignore 存在
ensure_docker_compose_file() {
    if [ ! -f "docker-compose.yml" ]; then
        log_message "未找到 docker-compose.yml，正在创建默认文件..."
        cat << EOF > docker-compose.yml
version: '3.8'
services:
  soundness-cli:
    build:
      context: .
      dockerfile: Dockerfile
    volumes:
      - .:/app
    working_dir: /app
    environment:
      - RUST_LOG=info
EOF
        log_message "已创建默认 docker-compose.yml"
    fi
    if [ ! -f "Dockerfile" ]; then
        log_message "未找到 Dockerfile，正在创建默认文件..."
        cat << EOF > Dockerfile
FROM rust:slim
WORKDIR /app
COPY ./soundness-cli /app
RUN apt-get update && apt-get install -y --no-install-recommends \\
    libssl3 ca-certificates && \\
    rm -rf /var/lib/apt/lists/*
RUN cargo install --path .
ENTRYPOINT ["soundness-cli"]
EOF
        log_message "已创建默认 Dockerfile"
    fi
    if [ ! -f ".dockerignore" ]; then
        log_message "未找到 .dockerignore，正在创建默认文件..."
        cat << EOF > .dockerignore
*.log
*.txt
target/
.git/
EOF
        log_message "已创建默认 .dockerignore"
    fi
}

# 函数：构建 Docker 镜像
build_docker_image() {
    log_message "构建 Docker 镜像..."
    docker compose build
    check_error "Docker 镜像构建失败"
    log_message "Docker 镜像构建成功"
}

# 函数：从 JSON 文件提取助记词
extract_mnemonic() {
    local file="$1"
    if ! command -v jq &> /dev/null; then
        log_message "错误: 需要安装 jq 来解析 JSON 文件"
        log_message "请运行 'sudo apt-get install jq' 或手动提供助记词"
        exit 1
    fi
    if [ ! -f "$file" ]; then
        log_message "错误: 文件 $file 不存在"
        echo "文件 $file 不存在。请运行选项 2 生成密钥对以获取助记词，或提供正确的文件路径。"
        exit 1
    fi
    if [ ! -s "$file" ]; then
        log_message "错误: 文件 $file 为空"
        exit 1
    fi
    MNEMONIC=$(jq -r '.mnemonic' "$file" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$MNEMONIC" ]; then
        log_message "错误: 无法从 $file 提取助记词，或文件格式不正确（需要包含 'mnemonic' 字段）"
        exit 1
    fi
    echo "$MNEMONIC"
}

# 函数：安装/更新 Soundness CLI（Docker 方式）
install_update_cli() {
    log_message "步骤 1: 安装/更新 Soundness CLI（通过 Docker）"
    check_docker
    ensure_source_code
    ensure_docker_compose_file
    build_docker_image
    log_message "Soundness CLI 安装/更新完成（Docker 镜像已准备）"
}

# 函数：生成密钥对
generate_key_pair() {
    log_message "步骤 2: 生成密钥对"
    check_docker
    ensure_source_code
    read -p "请输入密钥对名称（例如 my-key）: " KEY_NAME
    if [ -z "$KEY_NAME" ]; then
        KEY_NAME="my-key"
        log_message "未提供密钥名称，使用默认名称: $KEY_NAME"
    fi
    log_message "生成密钥对（名称: $KEY_NAME）..."
    echo '注意: 输入密码时，屏幕不会显示任何字符（为了安全）。'
    docker compose run --rm soundness-cli generate-key --name "$KEY_NAME" > key_info.txt
    check_error "密钥对生成失败"
    log_message "密钥对生成成功，信息已保存到 /root/soundness-layer/key_info.txt"
    log_message "请妥善保存 key_info.txt 中的助记词和公钥！"
}

# 函数：导入密钥对
import_key_pair() {
    log_message "步骤 3: 导入密钥对（通过助记词）"
    check_docker
    ensure_source_code
    read -p "请输入要导入的密钥对名称（例如 my-key-import）: " IMPORT_KEY_NAME
    if [ -z "$IMPORT_KEY_NAME" ]; then
        IMPORT_KEY_NAME="my-key-import"
        log_message "未提供导入密钥名称，使用默认名称: $IMPORT_KEY_NAME"
    fi
    echo "导入密钥对需要助记词（通常为 12 或 24 个单词，例如 'word1 word2 word3 ...'）。"
    echo "您可以："
    echo "1. 直接输入助记词。"
    echo "2. 提供包含助记词的 JSON 文件路径（需包含 'mnemonic' 字段，例如 {'mnemonic': 'word1 word2 ...'}）。"
    echo "3. 如果没有助记词，请选择选项 2 生成密钥对以获取助记词（保存在 /root/soundness-layer/key_info.txt）。"
    read -p "请输入助记词或 JSON 文件路径: " MNEMONIC_INPUT
    if [ -f "$MNEMONIC_INPUT" ]; then
        log_message "检测到文件输入，尝试从 $MNEMONIC_INPUT 提取助记词..."
        MNEMONIC=$(extract_mnemonic "$MNEMONIC_INPUT")
        check_error "从文件提取助记词失败"
    else
        MNEMONIC="$MNEMONIC_INPUT"
    fi
    if [ -z "$MNEMONIC" ]; then
        log_message "错误: 未提供有效的助记词"
        echo "未提供助记词。请运行选项 2 生成密钥对，或提供有效的助记词。"
        exit 1
    fi
    log_message "导入密钥对（名称: $IMPORT_KEY_NAME）..."
    docker compose run --rm soundness-cli import-key --name "$IMPORT_KEY_NAME" --mnemonic "$MNEMONIC"
    check_error "密钥对导入失败"
    log_message "密钥对导入成功"
}

# 函数：列出密钥对
list_key_pairs() {
    log_message "步骤 4: 列出所有密钥对"
    check_docker
    ensure_source_code
    docker compose run --rm soundness-cli list-keys
    check_error "列出密钥对失败"
    log_message "密钥对列表已显示"
}

# 函数：验证并发送证明
send_proof() {
    log_message "步骤 5: 验证并发送证明"
    check_docker
    ensure_source_code
    read -p "请输入证明文件的 Walrus Blob ID: " PROOF_BLOB_ID
    read -p "请输入游戏名称（例如 8queens 或 tictactoe）: " GAME_NAME
    read -p "请输入密钥对名称（用于发送证明）: " PROOF_KEY_NAME
    read -p "请输入 JSON 有效载荷（例如 {\"key\": \"value\"}）: " JSON_PAYLOAD
    log_message "发送证明（Blob ID: $PROOF_BLOB_ID, 游戏: $GAME_NAME, 密钥: $PROOF_KEY_NAME）..."
    docker compose run --rm soundness-cli send --proof-file "$PROOF_BLOB_ID" --game "$GAME_NAME" --key-name "$PROOF_KEY_NAME" --proving-system ligetron --payload "$JSON_PAYLOAD"
    check_error "证明发送失败"
    log_message "证明发送成功"
}

# 函数：批量导入密钥对
batch_import_keys() {
    log_message "步骤 6: 批量导入密钥对"
    check_docker
    ensure_source_code
    read -p "请输入包含密钥文件的目录路径: " KEY_DIR
    if [ ! -d "$KEY_DIR" ]; then
        log_message "错误: 目录 $KEY_DIR 不存在"
        echo "目录 $KEY_DIR 不存在。请提供有效的目录路径。"
        exit 1
    fi
    log_message "批量导入密钥对（目录: $KEY_DIR）..."
    shopt -s nullglob
    json_files=("$KEY_DIR"/*.json)
    if [ ${#json_files[@]} -eq 0 ]; then
        log_message "错误: 目录 $KEY_DIR 中没有 JSON 文件"
        echo "目录 $KEY_DIR 中没有 JSON 文件。请确保目录包含有效的 JSON 文件（包含 'mnemonic' 字段）。"
        exit 1
    fi
    for key_file in "${json_files[@]}"; do
        KEY_NAME=$(basename "$key_file" .json)
        log_message "导入密钥文件: $key_file（名称: $KEY_NAME）"
        MNEMONIC=$(extract_mnemonic "$key_file")
        check_error "从 $key_file 提取助记词失败"
        docker compose run --rm soundness-cli import-key --name "$KEY_NAME" --mnemonic "$MNEMONIC"
        check_error "导入密钥文件 $key_file 失败"
    done
    log_message "批量导入密钥对完成"
}

# 函数：删除密钥对
delete_key_pair() {
    log_message "步骤 7: 删除密钥对"
    check_docker
    ensure_source_code
    read -p "请输入要删除的密钥对名称: " DELETE_KEY_NAME
    if [ -z "$DELETE_KEY_NAME" ]; then
        log_message "错误: 未提供要删除的密钥名称"
        echo "未提供密钥名称。请提供有效的密钥对名称。"
        exit 1
    fi
    log_message "删除密钥对（名称: $DELETE_KEY_NAME）..."
    docker compose run --rm soundness-cli delete-key --name "$DELETE_KEY_NAME"
    check_error "删除密钥对失败"
    log_message "密钥对删除成功"
}

# 函数：删除 Soundness CLI（Docker 方式）
delete_cli() {
    log_message "步骤 8: 删除 Soundness CLI（Docker 镜像和文件）"
    read -p "确认删除 Soundness CLI 的 Docker 镜像和相关文件？（输入 y 确认）: " CONFIRM
    if [ ! "$CONFIRM" = "y" ]; then
        log_message "取消删除 Soundness CLI"
        return
    fi
    log_message "删除 Docker 镜像和相关文件..."
    cd /root/soundness-layer
    docker compose down
    docker image rm soundness-cli 2>/dev/null
    rm -f docker-compose.yml Dockerfile .dockerignore
    rm -rf /root/soundness-layer
    rm -rf $HOME/.soundness
    check_error "Soundness CLI 删除失败"
    log_message "Soundness CLI 删除成功"
}

# 主菜单
show_menu() {
    echo "Soundness CLI 管理菜单（Docker 版本）"
    echo "1. 安装/更新 Soundness CLI（通过 Docker）"
    echo "2. 生成密钥对"
    echo "3. 导入密钥对（通过助记词）"
    echo "4. 列出密钥对"
    echo "5. 验证并发送证明"
    echo "6. 批量导入密钥对"
    echo "7. 删除密钥对"
    echo "8. 删除 Soundness CLI（Docker 镜像和文件）"
    echo "9. 退出"
    echo
}

# 主循环
while true; do
    show_menu
    read -p "请选择一个选项 (1-9): " choice
    case $choice in
        1)
            install_update_cli
            ;;
        2)
            generate_key_pair
            ;;
        3)
            import_key_pair
            ;;
        4)
            list_key_pairs
            ;;
        5)
            send_proof
            ;;
        6)
            batch_import_keys
            ;;
        7)
            delete_key_pair
            ;;
        8)
            delete_cli
            ;;
        9)
            log_message "脚本执行完成，退出"
            exit 0
            ;;
        *)
            echo "无效选项，请选择 1-9"
            ;;
    esac
    echo
    read -p "按 Enter 继续..."
done
