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

# 函数：确保 soundnessup 可执行
ensure_soundnessup() {
    if ! command -v soundnessup &> /dev/null; then
        log_message "未找到 soundnessup，尝试手动设置 PATH..."
        export PATH=$PATH:/usr/local/bin:$HOME/.soundness/bin
        source /root/.bashrc 2>/dev/null || source /root/.bash_profile 2>/dev/null || source /root/.profile 2>/dev/null
        if ! command -v soundnessup &> /dev/null; then
            log_message "错误: 无法找到 soundnessup，请检查安装路径"
            log_message "尝试查找 soundnessup 位置："
            find / -name soundnessup 2>/dev/null | tee -a "$LOG_FILE"
            exit 1
        fi
    fi
    log_message "soundnessup 已可用：$(which soundnessup)"
}

# 函数：确保 soundness-cli 可执行
ensure_soundness_cli() {
    if ! command -v soundness-cli &> /dev/null; then
        log_message "未找到 soundness-cli，尝试安装..."
        ensure_soundnessup
        log_message "运行 soundnessup install..."
        soundnessup install
        check_error "soundness-cli 安装失败"
        export PATH=$PATH:/usr/local/bin:$HOME/.soundness/bin
        if ! command -v soundness-cli &> /dev/null; then
            log_message "错误: 无法找到 soundness-cli，请检查安装路径"
            log_message "尝试查找 soundness-cli 位置："
            find / -name soundness-cli 2>/dev/null | tee -a "$LOG_FILE"
            exit 1
        fi
    fi
    log_message "soundness-cli 已可用：$(which soundness-cli)"
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

# 函数：安装/更新 Soundness CLI
install_update_cli() {
    log_message "步骤 1: 安装/更新 Soundness CLI"
    check_rust
    log_message "运行 soundnessup 安装程序..."
    curl -sSL https://raw.githubusercontent.com/soundnesslabs/soundness-layer/main/soundnessup/install | bash
    check_error "soundnessup 安装程序下载或运行失败"
    log_message "更新 shell 环境..."
    source /root/.bashrc 2>/dev/null || source /root/.bash_profile 2>/dev/null || source /root/.profile 2>/dev/null
    export PATH=$PATH:/usr/local/bin:$HOME/.soundness/bin
    ensure_soundnessup
    log_message "安装 Soundness CLI..."
    soundnessup install
    check_error "Soundness CLI 安装失败"
    log_message "尝试更新 Soundness CLI 到最新版本..."
    soundnessup update
    check_error "Soundness CLI 更新失败"
    log_message "Soundness CLI 安装/更新完成"
}

# 函数：生成密钥对
generate_key_pair() {
    log_message "步骤 2: 生成密钥对"
    ensure_soundness_cli
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
}

# 函数：导入密钥对
import_key_pair() {
    log_message "步骤 3: 导入密钥对"
    ensure_soundness_cli
    read -p "请输入要导入的密钥对名称（例如 my-key-import）: " IMPORT_KEY_NAME
    if [ -z "$IMPORT_KEY_NAME" ]; then
        IMPORT_KEY_NAME="my-key-import"
        log_message "未提供导入密钥名称，使用默认名称: $IMPORT_KEY_NAME"
    fi
    read -p "请输入助记词（或提供包含助记词的 JSON 文件路径，例如 key_store.json）： " MNEMONIC_INPUT
    if [ -f "$MNEMONIC_INPUT" ]; then
        log_message "检测到文件输入，尝试从 $MNEMONIC_INPUT 提取助记词..."
        MNEMONIC=$(extract_mnemonic "$MNEMONIC_INPUT")
        check_error "从文件提取助记词失败"
    else
        MNEMONIC="$MNEMONIC_INPUT"
    fi
    if [ -z "$MNEMONIC" ]; then
        log_message "错误: 未提供有效的助记词"
        exit 1
    fi
    log_message "导入密钥对（名称: $IMPORT_KEY_NAME）..."
    soundness-cli import-key --name "$IMPORT_KEY_NAME" --mnemonic "$MNEMONIC"
    check_error "密钥对导入失败"
    log_message "密钥对导入成功"
}

# 函数：列出密钥对
list_key_pairs() {
    log_message "步骤 4: 列出所有密钥对"
    ensure_soundness_cli
    soundness-cli list-keys
    check_error "列出密钥对失败"
    log_message "密钥对列表已显示"
}

# 函数：验证并发送证明
send_proof() {
    log_message "步骤 5: 验证并发送证明"
    ensure_soundness_cli
    read -p "请输入证明文件的 Walrus Blob ID: " PROOF_BLOB_ID
    read -p "请输入游戏名称（例如 8queens 或 tictactoe）: " GAME_NAME
    read -p "请输入密钥对名称（用于发送证明）: " PROOF_KEY_NAME
    read -p "请输入 JSON 有效载荷（例如 {\"key\": \"value\"}）: " JSON_PAYLOAD
    log_message "发送证明（Blob ID: $PROOF_BLOB_ID, 游戏: $GAME_NAME, 密钥: $PROOF_KEY_NAME）..."
    soundness-cli send --proof-file "$PROOF_BLOB_ID" --game "$GAME_NAME" --key-name "$PROOF_KEY_NAME" --proving-system ligetron --payload "$JSON_PAYLOAD"
    check_error "证明发送失败"
    log_message "证明发送成功"
}

# 函数：批量导入密钥对
batch_import_keys() {
    log_message "步骤 6: 批量导入密钥对"
    ensure_soundness_cli
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
            MNEMONIC=$(extract_mnemonic "$key_file")
            check_error "从 $key_file 提取助记词失败"
            soundness-cli import-key --name "$KEY_NAME" --mnemonic "$MNEMONIC"
            check_error "导入密钥文件 $key_file 失败"
        fi
    done
    log_message "批量导入密钥对完成"
}

# 函数：删除密钥对
delete_key_pair() {
    log_message "步骤 7: 删除密钥对"
    ensure_soundness_cli
    read -p "请输入要删除的密钥对名称: " DELETE_KEY_NAME
    if [ -z "$DELETE_KEY_NAME" ]; then
        log_message "错误: 未提供要删除的密钥名称"
        exit 1
    fi
    log_message "删除密钥对（名称: $DELETE_KEY_NAME）..."
    soundness-cli delete-key --name "$DELETE_KEY_NAME"
    check_error "删除密钥对失败"
    log_message "密钥对删除成功"
}

# 函数：删除 Soundness CLI
delete_cli() {
    log_message "步骤 8: 删除 Soundness CLI"
    read -p "确认删除 Soundness CLI？（输入 y 确认）: " CONFIRM
    if [ ! "$CONFIRM" = "y" ]; then
        log_message "取消删除 Soundness CLI"
        return
    fi
    log_message "删除 Soundness CLI..."
    rm -f /usr/local/bin/soundness-cli
    rm -f /usr/local/bin/soundnessup
    rm -rf $HOME/.soundness
    check_error "Soundness CLI 删除失败"
    log_message "Soundness CLI 删除成功"
}

# 主菜单
show_menu() {
    echo "Soundness CLI 管理菜单"
    echo "1. 安装/更新 Soundness CLI（通过 soundnessup）"
    echo "2. 生成密钥对"
    echo "3. 导入密钥对"
    echo "4. 列出密钥对"
    echo "5. 验证并发送证明"
    echo "6. 批量导入密钥对"
    echo "7. 删除密钥对"
    echo "8. 删除 Soundness CLI"
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
