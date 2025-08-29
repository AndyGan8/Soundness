#!/bin/bash

# Soundness CLI 管理脚本
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

# 函数：检查 Rust 是否已安装
check_rust() {
    if ! command -v rustc &> /dev/null; then
        log_message "Rust 未安装，正在安装 Rust..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        check_error "Rust 安装失败"
        source $HOME/.cargo/env
        log_message "Rust 安装成功"
    else
        log_message "Rust 已安装"
    fi
}

# 开始脚本
log_message "开始执行 Soundness CLI 管理脚本"

# 1. 安装/更新 Soundness CLI（通过 soundnessup）
log_message "步骤 1: 安装/更新 Soundness CLI"
check_rust
log_message "运行 soundnessup 安装程序..."
curl -sSL https://raw.githubusercontent.com/soundnesslabs/soundness-layer/main/soundnessup/install | bash
check_error "soundnessup 安装程序下载或运行失败"
log_message "更新 shell 环境..."
source ~/.bashrc
soundnessup install
check_error "Soundness CLI 安装失败"
log_message "尝试更新 Soundness CLI 到最新版本..."
soundnessup update
check_error "Soundness CLI 更新失败"
log_message "Soundness CLI 安装/更新完成"

# 2. 生成密钥对
log_message "步骤 2: 生成密钥对"
read -p "请输入密钥对名称（例如 my-key）: " KEY_NAME
if [ -z "$KEY_NAME" ]; then
    KEY_NAME="my-key"
    log_message "未提供密钥名称，使用默认名称: $KEY_NAME"
fi
log_message "生成密钥对（名称: $KEY_NAME）..."
echo '注意: 输入密码时，屏幕不会显示任何字符（为了安全）。'
script -q -c "soundness-cli generate-key --name $KEY_NAME" key_info.txt
check_error "密钥对生成失败"
log_message "密钥对生成成功，信息已保存到 key_info.txt"
log_message "请妥善保存 key_info.txt 中的助记词和公钥！"

# 3. 导入密钥对
log_message "步骤 3: 导入密钥对"
read -p "请输入要导入的密钥对名称（例如 my-key-import）: " IMPORT_KEY_NAME
if [ -z "$IMPORT_KEY_NAME" ]; then
    IMPORT_KEY_NAME="my-key-import"
    log_message "未提供导入密钥名称，使用默认名称: $IMPORT_KEY_NAME"
fi
read -p "请输入密钥文件的路径（例如 key_store.json）: " KEY_FILE
if [ ! -f "$KEY_FILE" ]; then
    log_message "错误: 密钥文件 $KEY_FILE 不存在"
    exit 1
fi
log_message "导入密钥对（名称: $IMPORT_KEY_NAME）..."
soundness-cli import-key --name "$IMPORT_KEY_NAME" --file "$KEY_FILE"
check_error "密钥对导入失败"
log_message "密钥对导入成功"

# 4. 列出密钥对
log_message "步骤 4: 列出所有密钥对"
soundness-cli list-keys
check_error "列出密钥对失败"
log_message "密钥对列表已显示"

# 5. 验证并发送证明
log_message "步骤 5: 验证并发送证明"
read -p "请输入证明文件的 Walrus Blob ID: " PROOF_BLOB_ID
read -p "请输入游戏名称（例如 8queens 或 tictactoe）: " GAME_NAME
read -p "请输入密钥对名称（用于发送证明）: " PROOF_KEY_NAME
read -p "请输入 JSON 有效载荷（例如 {\"key\": \"value\"}）: " JSON_PAYLOAD
log_message "发送证明（Blob ID: $PROOF_BLOB_ID, 游戏: $GAME_NAME, 密钥: $PROOF_KEY_NAME）..."
soundness-cli send --proof-file "$PROOF_BLOB_ID" --game "$GAME_NAME" --key-name "$PROOF_KEY_NAME" --proving-system ligetron --payload "$JSON_PAYLOAD"
check_error "证明发送失败"
log_message "证明发送成功"

# 6. 批量导入密钥对
log_message "步骤 6: 批量导入密钥对"
read -p "请输入包含密钥文件的目录路径: " KEY_DIR
if [ ! -d "$KEY_DIR" ]; then
    log_message "错误: 目录 $KEY_DIR 不存在"
    exit 1
fi
log_message "批量导入密钥对（目录: $KEY_DIR）..."
for key_file in "$KEY_DIR"/*.json; do
    if [ -f "$key_file" ]; then
        KEY_NAME=$(basename "$key_file" .json)
        log_message "导入密钥文件: $key_file（名称: $KEY_NAME）"
        soundness-cli import-key --name "$KEY_NAME" --file "$key_file"
        check_error "导入密钥文件 $key_file 失败"
    fi
done
log_message "批量导入密钥对完成"

# 7. 删除密钥对
log_message "步骤 7: 删除密钥对"
read -p "请输入要删除的密钥对名称: " DELETE_KEY_NAME
if [ -z "$DELETE_KEY_NAME" ]; then
    log_message "错误: 未提供要删除的密钥名称"
    exit 1
fi
log_message "删除密钥对（名称: $DELETE_KEY_NAME）..."
soundness-cli delete-key --name "$DELETE_KEY_NAME"
check_error "删除密钥对失败"
log_message "密钥对删除成功"

# 8. 删除 Soundness CLI
log_message "步骤 8: 删除 Soundness CLI"
read -p "确认删除 Soundness CLI？（输入 y 确认）: " CONFIRM
if [ "$CONFIRM" = "y" ]; then
    log_message "删除 Soundness CLI..."
    rm -f /usr/local/bin/soundness-cli
    rm -f /usr/local/bin/soundnessup
    rm -rf $HOME/.soundness
    check_error "Soundness CLI 删除失败"
    log_message "Soundness CLI 删除成功"
else
    log_message "取消删除 Soundness CLI"
fi

# 9. 退出
log_message "脚本执行完成，退出"
exit 0
