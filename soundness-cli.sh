#!/bin/bash

# Soundness CLI 管理脚本
# 日志文件
LOG_FILE="/root/soundness_cli_script.log"

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
        log_message "Rust 安装成功：$(rustc --version)"
    else
        log_message "Rust 已安装：$(rustc --version)"
    fi
}

# 函数：确保 PATH 包含 Soundness CLI 路径
ensure_path() {
    if [[ ":$PATH:" != *":/usr/local/bin:$HOME/.soundness/bin:"* ]]; then
        log_message "更新 PATH 以包含 Soundness CLI..."
        export PATH=$PATH:/usr/local/bin:$HOME/.soundness/bin
        echo 'export PATH=$PATH:/usr/local/bin:$HOME/.soundness/bin' >> /root/.bashrc
        source /root/.bashrc
        log_message "PATH 已更新：$PATH"
    fi
}

# 函数：确保 soundnessup 可执行
ensure_soundnessup() {
    if ! command -v soundnessup &> /dev/null; then
        log_message "未找到 soundnessup，正在安装..."
        curl -sSL https://raw.githubusercontent.com/soundnesslabs/soundness-layer/main/soundnessup/install | bash
        check_error "soundnessup 安装失败"
        ensure_path
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
        log_message "错误: 未找到 soundness-cli，请先运行选项 1 安装 Soundness CLI"
        exit 1
    fi
    log_message "soundness-cli 已可用：$(soundness-cli --version)"
    # 初始化 ~/.soundness 目录
    if [ ! -d "$HOME/.soundness" ]; then
        log_message "初始化 ~/.soundness 目录..."
        mkdir -p "$HOME/.soundness"
        check_error "无法创建 ~/.soundness 目录"
    fi
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
        echo "文件 $file 不存在。请运行选项 3 生成密钥对以获取助记词，或提供正确的文件路径。"
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

# 函数：安装 Soundness CLI
install_cli() {
    log_message "步骤 1: 安装 Soundness CLI"
    check_rust
    ensure_soundnessup
    if command -v soundness-cli &> /dev/null; then
        log_message "Soundness CLI 已安装：$(soundness-cli --version)"
        echo "Soundness CLI 已安装。如果需要更新，请选择选项 2。"
        return
    fi
    log_message "安装 Soundness CLI..."
    # 安装依赖以避免 pkg-config 和 libssl-dev 问题
    sudo apt-get update
    sudo apt-get install -y pkg-config libssl-dev
    check_error "依赖安装失败"
    soundnessup install
    check_error "Soundness CLI 安装失败"
    ensure_path
    ensure_soundness_cli
    log_message "Soundness CLI 安装完成"
}

# 函数：更新 Soundness CLI
update_cli() {
    log_message "步骤 2: 更新 Soundness CLI"
    check_rust
    ensure_soundnessup
    if ! command -v soundness-cli &> /dev/null; then
        log_message "错误: Soundness CLI 未安装，请先运行选项 1 安装"
        exit 1
    fi
    log_message "更新 Soundness CLI 到最新版本..."
    soundnessup update
    check_error "Soundness CLI 更新失败"
    ensure_path
    ensure_soundness_cli
    log_message "Soundness CLI 更新完成"
}

# 函数：生成密钥对并提示 Discord 提交
generate_key_pair() {
    log_message "步骤 3: 生成密钥对"
    ensure_soundness_cli
    echo "生成密钥对前，请确认您是否已在 Soundness Labs Discord 获取 Onboarded 角色："
    echo "1. 加入 Discord：https://discord.gg/soundnesslabs"
    echo "2. 如果您有 Onboarded 角色，密钥对可能已在入职时生成，无需重新生成。"
    echo "3. 如果您有邀请码，需生成新密钥对并在 Discord 的 #testnet-access 频道提交公钥。"
    read -p "您是否已有 Onboarded 角色？（y/n）: " HAS_ONBOARDED
    if [ "$HAS_ONBOARDED" = "y" ]; then
        log_message "用户确认已有 Onboarded 角色，跳过密钥生成"
        echo "您已有 Onboarded 角色，请使用现有密钥对（运行选项 5 列出密钥对）。"
        return
    fi
    read -p "请输入密钥对名称（例如 my-key）: " KEY_NAME
    if [ -z "$KEY_NAME" ]; then
        KEY_NAME="my-key"
        log_message "未提供密钥名称，使用默认名称: $KEY_NAME"
    fi
    log_message "生成密钥对（名称: $KEY_NAME）..."
    echo '注意: 输入密码时，屏幕不会显示任何字符（为了安全）。'
    script -q -c "soundness-cli generate-key --name $KEY_NAME" /root/key_info.txt
    check_error "密钥对生成失败"
    # 提取公钥
    PUBLIC_KEY=$(grep "Public key:" /root/key_info.txt | awk -F": " '{print $2}' | tr -d '\n')
    if [ -z "$PUBLIC_KEY" ]; then
        log_message "错误: 无法从 key_info.txt 提取公钥"
        exit 1
    fi
    log_message "密钥对生成成功，公钥: $PUBLIC_KEY"
    log_message "密钥信息已保存到 /root/key_info.txt"
    echo "密钥对生成成功，信息已保存到 /root/key_info.txt"
    echo "请妥善保存助记词（在 /root/key_info.txt 中）！"
    echo "请在 Soundness Labs Discord 的 #testnet-access 频道提交以下命令："
    echo "  !access $PUBLIC_KEY"
    echo "等待 ✅ 确认后，您已注册测试网访问权限。"
}

# 函数：导入密钥对并自动生成 JSON 文件
import_key_pair() {
    log_message "步骤 4: 导入密钥对（通过助记词）"
    ensure_soundness_cli
    read -p "请输入要导入的密钥对名称（例如 my-key-import）: " IMPORT_KEY_NAME
    if [ -z "$IMPORT_KEY_NAME" ]; then
        IMPORT_KEY_NAME="my-key-import"
        log_message "未提供导入密钥名称，使用默认名称: $IMPORT_KEY_NAME"
    fi
    echo "导入密钥对需要助记词（通常为 12 或 24 个单词，例如 'word1 word2 word3 ...'）。"
    echo "您可以："
    echo "1. 直接输入助记词。"
    echo "2. 提供包含助记词的 JSON 文件路径（需包含 'mnemonic' 字段，例如 {'mnemonic': 'word1 word2 ...'}）。"
    echo "3. 如果没有助记词，请选择选项 3 生成密钥对以获取助记词（保存在 /root/key_info.txt）。"
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
        echo "未提供助记词。请运行选项 3 生成密钥对，或提供有效的助记词。"
        exit 1
    fi
    # 自动生成 JSON 文件
    JSON_FILE="/root/key_info_${IMPORT_KEY_NAME}.json"
    log_message "保存助记词到 JSON 文件：$JSON_FILE"
    echo "{\"mnemonic\": \"$MNEMONIC\"}" > "$JSON_FILE"
    check_error "无法保存助记词到 $JSON_FILE"
    log_message "助记词已保存到 $JSON_FILE"
    log_message "导入密钥对（名称: $IMPORT_KEY_NAME）..."
    soundness-cli import-key --name "$IMPORT_KEY_NAME" --mnemonic "$MNEMONIC"
    check_error "密钥对导入失败"
    log_message "密钥对导入成功"
    echo "助记词已保存到 $JSON_FILE，请妥善保存！"
    # 显示公钥并提示 Discord 提交
    PUBLIC_KEY=$(soundness-cli list-keys | grep "$IMPORT_KEY_NAME" | awk '{print $NF}' | tr -d '\n')
    if [ ! -z "$PUBLIC_KEY" ]; then
        log_message "导入的密钥对公钥: $PUBLIC_KEY"
        echo "请在 Soundness Labs Discord 的 #testnet-access 频道提交以下命令："
        echo "  !access $PUBLIC_KEY"
        echo "等待 ✅ 确认后，您已注册测试网访问权限。"
    fi
}

# 函数：列出密钥对
list_key_pairs() {
    log_message "步骤 5: 列出所有密钥对"
    ensure_soundness_cli
    if [ ! -f "$HOME/.soundness/key_store.json" ]; then
        log_message "密钥存储文件 $HOME/.soundness/key_store.json 不存在，初始化为空..."
        echo "{}" > "$HOME/.soundness/key_store.json"
        check_error "无法初始化密钥存储文件"
    fi
    soundness-cli list-keys
    check_error "列出密钥对失败"
    log_message "密钥对列表已显示"
}

# 函数：验证并发送证明
send_proof() {
    log_message "步骤 6: 验证并发送证明"
    ensure_soundness_cli
    echo "请确保您已在 Soundness Labs Discord 的 #Soundness-Cockpit 频道赢得游戏并获取 Walrus Blob ID。"
    echo "参考：https://soundness.xyz/testnet"
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
    log_message "步骤 7: 批量导入密钥对"
    ensure_soundness_cli
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
        soundness-cli import-key --name "$KEY_NAME" --mnemonic "$MNEMONIC"
        check_error "导入密钥文件 $key_file 失败"
        # 显示公钥并提示 Discord 提交
        PUBLIC_KEY=$(soundness-cli list-keys | grep "$KEY_NAME" | awk '{print $NF}' | tr -d '\n')
        if [ ! -z "$PUBLIC_KEY" ]; then
            log_message "导入的密钥对公钥: $PUBLIC_KEY"
            echo "请在 Soundness Labs Discord 的 #testnet-access 频道提交以下命令："
            echo "  !access $PUBLIC_KEY"
            echo "等待 ✅ 确认后，您已注册测试网访问权限。"
        fi
    done
    log_message "批量导入密钥对完成"
}

# 函数：删除密钥对
delete_key_pair() {
    log_message "步骤 8: 删除密钥对"
    ensure_soundness_cli
    read -p "请输入要删除的密钥对名称: " DELETE_KEY_NAME
    if [ -z "$DELETE_KEY_NAME" ]; then
        log_message "错误: 未提供要删除的密钥名称"
        echo "未提供密钥名称。请提供有效的密钥对名称。"
        exit 1
    fi
    log_message "删除密钥对（名称: $DELETE_KEY_NAME）..."
    soundness-cli delete-key --name "$DELETE_KEY_NAME"
    check_error "删除密钥对失败"
    log_message "密钥对删除成功"
}

# 函数：删除 Soundness CLI
delete_cli() {
    log_message "步骤 9: 删除 Soundness CLI"
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
    echo "1. 安装 Soundness CLI（通过 soundnessup）"
    echo "2. 更新 Soundness CLI"
    echo "3. 生成密钥对并提交到 Discord"
    echo "4. 导入密钥对（通过助记词）"
    echo "5. 列出密钥对"
    echo "6. 验证并发送证明"
    echo "7. 批量导入密钥对"
    echo "8. 删除密钥对"
    echo "9. 删除 Soundness CLI"
    echo "10. 退出"
    echo
}

# 初始化 PATH
source /root/.bashrc 2>/dev/null
export PATH=$PATH:/usr/local/bin:$HOME/.soundness/bin

# 主循环
while true; do
    show_menu
    read -p "请选择一个选项 (1-10): " choice
    case $choice in
        1)
            install_cli
            ;;
        2)
            update_cli
            ;;
        3)
            generate_key_pair
            ;;
        4)
            import_key_pair
            ;;
        5)
            list_key_pairs
            ;;
        6)
            send_proof
            ;;
        7)
            batch_import_keys
            ;;
        8)
            delete_key_pair
            ;;
        9)
            delete_cli
            ;;
        10)
            log_message "脚本执行完成，退出"
            exit 0
            ;;
        *)
            echo "无效选项，请选择 1-10"
            ;;
    esac
    echo
    read -p "按 Enter 继续..."
done
