#!/bin/bash
clear

# Soundness CLI 一键脚本（无 Docker 版，简化版）
# 版本：1.0.15
# 功能：
# 1. 安装/更新 Soundness CLI（通过 soundnessup）
# 2. 生成密钥对
# 3. 导入密钥对
# 4. 列出密钥对
# 5. 验证并发送证明
# 6. 退出

set -e

# 常量定义
SCRIPT_VERSION="1.0.15"
SOUNDNESS_DIR="/root/soundness-layer/soundness-cli"
SOUNDNESS_CONFIG_DIR=".soundness"
LOG_FILE="/root/soundness-script.log"
CACHE_DIR="/root/soundness-cache"
LANG=${LANG:-zh}

# 检查 /tmp 目录状态
check_tmp_dir() {
    local tmp_dir="${TMPDIR:-/tmp}"
    if [ ! -d "$tmp_dir" ] || [ ! -w "$tmp_dir" ]; then
        log_message "❌ 无法访问 $tmp_dir 目录"
        echo "建议："
        echo "  - 检查目录是否存在：ls -ld $tmp_dir"
        echo "  - 检查权限：chmod 1777 $tmp_dir"
        echo "  - 尝试使用 /var/tmp：export TMPDIR=/var/tmp"
        exit 1
    fi
    local disk_space=$(df -h "$tmp_dir" | awk 'NR==2 {print $4}' | grep -o '[0-9]\+[MG]' || echo "0")
    if [ -z "$disk_space" ] || [ "${disk_space%[MG]}" -lt 10 ]; then
        log_message "❌ /tmp 目录空间不足"
        echo "建议："
        echo "  - 检查磁盘空间：df -h $tmp_dir"
        echo "  - 清理临时文件：rm -f $tmp_dir/soundness.*"
        exit 1
    fi
    log_message "✅ /tmp 目录正常：空间 $disk_space，权限 $(ls -ld "$tmp_dir")"
}

# 清理临时文件
cleanup_temp_files() {
    log_message "清理临时文件..."
    local tmp_dir="${TMPDIR:-/tmp}"
    find "$tmp_dir" -maxdepth 1 -name 'soundness.*' -type f -delete 2>/dev/null
    log_message "✅ 临时文件清理完成。"
}

# 日志记录（带行号）
log_message() {
    local msg=$1
    local line=${BASH_LINENO[0]}
    echo "$(date '+%Y-%m-%d %H:%M:%S') [行 $line] - $msg" >> "$LOG_FILE"
    echo "$msg"
}

# 错误处理
handle_error() {
    local error_msg=$1
    local suggestions=$2
    log_message "❌ 错误：$error_msg"
    echo "建议："
    echo "$suggestions" | sed 's/;/\n  - /g'
    log_message "加入 Discord（https://discord.gg/soundnesslabs）获取支持。"
    cleanup_temp_files
    exit 1
}

# 重试命令（简化版）
retry_command() {
    local cmd=$1
    local max_retries=3
    local retry_count=0
    local output
    while [ $retry_count -lt $max_retries ]; do
        log_message "尝试 $((retry_count + 1))/$max_retries: $cmd"
        output=$(eval "$cmd" 2>&1)
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            echo "$output"
            return 0
        fi
        ((retry_count++))
        log_message "⚠️ 失败：$output"
        sleep 5
    done
    handle_error "命令失败：$cmd" "检查网络：ping raw.githubusercontent.com;验证命令参数;检查 key_store.json：cat $SOUNDNESS_DIR/$SOUNDNESS_CONFIG_DIR/key_store.json"
}

# 验证 JSON
validate_json() {
    local json=$1
    local context=$2
    echo "$json" | jq . >/dev/null 2>&1 || {
        log_message "无效 JSON（$context）：$json"
        handle_error "JSON 格式无效：$context" "检查 JSON 语法（使用双引号、正确转义）;运行 'echo \"$json\" | jq .' 检查;参考文档：https://github.com/SoundnessLabs/soundness-layer/tree/main/soundness-cli"
    }
}

# 确保目录存在
secure_directory() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        log_message "创建目录 $dir..."
        mkdir -p "$dir"
    fi
    chmod 755 "$dir"
    if [ -f "$dir/key_store.json" ]; then
        chmod 600 "$dir/key_store.json"
        log_message "已设置 $dir/key_store.json 权限为 600"
    fi
}

# 验证输入
validate_input() {
    local input=$1
    local field=$2
    if ! echo "$input" | grep -qE '^[A-Za-z0-9_-]+$'; then
        handle_error "无效的 $field：$input" "仅允许字母、数字、下划线和连字符"
    fi
}

# 检查依赖
check_requirements() {
    log_message "检查依赖..."
    if ! command -v curl >/dev/null 2>&1; then
        handle_error "需要安装 curl" "安装 curl：sudo apt-get install -y curl"
    fi
    if ! command -v jq >/dev/null 2>&1; then
        log_message "安装 jq..."
        sudo apt-get update && sudo apt-get install -y jq
    fi
}

# 安装 Rust 和 Cargo
install_rust_cargo() {
    log_message "检查 Rust 和 Cargo..."
    if ! command -v cargo >/dev/null 2>&1; then
        log_message "安装 Rust 和 Cargo..."
        retry_command "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y" 3
        export PATH="$HOME/.cargo/bin:$PATH"
        if ! grep -q '.cargo/bin' /root/.bashrc; then
            echo "export PATH=\$HOME/.cargo/bin:\$PATH" >> /root/.bashrc
            log_message "已将 Cargo PATH 写入 /root/.bashrc"
        fi
        source /root/.bashrc 2>/dev/null || true
    fi
    if ! cargo --version >/dev/null 2>&1; then
        handle_error "Cargo 安装失败" "检查安装路径：ls -l /root/.cargo/bin/cargo;验证 PATH：echo \$PATH;重新安装 Rust：curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -y"
    fi
    log_message "✅ Rust 和 Cargo 已安装：$(cargo --version)"
}

# 安装 soundnessup
install_soundnessup() {
    log_message "安装 soundnessup..."
    sudo rm -f /usr/local/bin/soundnessup /root/.local/bin/soundnessup /root/.soundness/bin/soundnessup
    retry_command "curl -sSL https://raw.githubusercontent.com/soundnesslabs/soundness-layer/main/soundnessup/install -o install_soundnessup.sh" 3
    chmod +x install_soundnessup.sh
    retry_command "bash install_soundnessup.sh" 3
    rm -f install_soundnessup.sh
    export PATH="$PATH:/usr/local/bin:/root/.local/bin:/root/.soundness/bin"
    if ! command -v soundnessup >/dev/null 2>&1; then
        handle_error "soundnessup 安装失败" "检查安装路径：ls -l /usr/local/bin/soundnessup;验证 PATH：echo \$PATH;重新安装：curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/soundnesslabs/soundness-layer/main/soundnessup/install | bash"
    fi
    log_message "✅ soundnessup 已安装：$(soundnessup --version 2>/dev/null || echo 'unknown')"
}

# 安装 Soundness CLI
install_cli() {
    log_message "开始安装/更新 Soundness CLI..."
    check_requirements
    install_rust_cargo
    install_soundnessup
    secure_directory "$SOUNDNESS_DIR/$SOUNDNESS_CONFIG_DIR"
    secure_directory "$CACHE_DIR"
    log_message "安装 Soundness CLI..."
    retry_command "soundnessup install" 3
    if ! soundness-cli --help >/dev/null 2>&1; then
        handle_error "Soundness CLI 安装失败" "检查 soundnessup 日志;验证 PATH：echo \$PATH;检查 key_store.json：cat $SOUNDNESS_DIR/$SOUNDNESS_CONFIG_DIR/key_store.json"
    fi
    log_message "更新 Soundness CLI..."
    retry_command "soundnessup update" 3
    log_message "✅ Soundness CLI 安装完成：$(soundness-cli --version 2>/dev/null || echo 'unknown')"
}

# 安全输入密码
secure_password_input() {
    check_tmp_dir
    local tmp_dir="${TMPDIR:-/tmp}"
    local temp_file
    temp_file=$(mktemp "$tmp_dir/soundness.XXXXXX" 2>/dev/null) || {
        handle_error "mktemp 命令失败" "检查 /tmp 目录：ls -ld $tmp_dir;检查磁盘空间：df -h $tmp_dir;尝试使用 /var/tmp：export TMPDIR=/var/tmp"
    }
    if [ ! -f "$temp_file" ] || [ ! -w "$temp_file" ]; then
        handle_error "无法创建或写入临时密码文件 $temp_file" "检查磁盘空间：df -h $tmp_dir;检查权限：ls -ld $tmp_dir;尝试使用 /var/tmp：export TMPDIR=/var/tmp"
    }
    read -sp "请输入密码（留空则无密码，按 Enter 确认）： " password
    echo ""
    echo "$password" > "$temp_file"
    chmod 600 "$temp_file"
    log_message "创建临时文件：$temp_file"
    echo "$temp_file"
}

# 生成密钥对
generate_key_pair() {
    cd "$SOUNDNESS_DIR"
    read -p "请输入密钥对名称（例如 andygan）： " key_name
    validate_input "$key_name" "密钥对名称"
    temp_file=$(secure_password_input)
    if [ ! -f "$temp_file" ]; then
        handle_error "无法访问临时密码文件" "检查磁盘空间：df -h /tmp;检查权限：ls -l /tmp"
    fi
    password=$(cat "$temp_file")
    rm -f "$temp_file"
    log_message "密码长度：${#password}"
    secure_directory "$SOUNDNESS_DIR/$SOUNDNESS_CONFIG_DIR"
    log_message "生成密钥对：$key_name..."
    if [ -n "$password" ]; then
        output=$(retry_command "echo \"$password\" | soundness-cli generate-key --name \"$key_name\"" 3)
    else
        output=$(retry_command "soundness-cli generate-key --name \"$key_name\"" 3)
    fi
    log_message "✅ 密钥对 $key_name 生成成功！输出：$output"
    echo "$output"
    log_message "请将公钥提交到 Discord #testnet-access 频道，格式：!access <your_public_key>"
}

# 导入密钥对
import_key_pair() {
    cd "$SOUNDNESS_DIR"
    read -p "请输入密钥对名称（例如 andygan）： " key_name
    read -p "请输入助记词（24 个单词）： " mnemonic
    validate_input "$key_name" "密钥对名称"
    if [ -z "$mnemonic" ]; then
        handle_error "助记词不能为空" "提供有效的 24 单词助记词"
    fi
    temp_file=$(secure_password_input)
    if [ ! -f "$temp_file" ]; then
        handle_error "无法访问临时密码文件" "检查磁盘空间：df -h /tmp;检查权限：ls -l /tmp"
    fi
    password=$(cat "$temp_file")
    rm -f "$temp_file"
    log_message "密码长度：${#password}"
    secure_directory "$SOUNDNESS_DIR/$SOUNDNESS_CONFIG_DIR"
    log_message "导入密钥对：$key_name..."
    if [ -n "$password" ]; then
        output=$(retry_command "echo \"$password\" | soundness-cli import-key --name \"$key_name\" --mnemonic \"$mnemonic\"" 3)
    else
        output=$(retry_command "soundness-cli import-key --name \"$key_name\" --mnemonic \"$mnemonic\"" 3)
    fi
    log_message "✅ 密钥对 $key_name 导入成功！输出：$output"
    echo "$output"
}

# 列出密钥对
list_key_pairs() {
    cd "$SOUNDNESS_DIR"
    log_message "列出所有存储的密钥对..."
    temp_file=$(secure_password_input)
    if [ ! -f "$temp_file" ]; then
        handle_error "无法访问临时密码文件" "检查磁盘空间：df -h /tmp;检查权限：ls -l /tmp"
    fi
    password=$(cat "$temp_file")
    rm -f "$temp_file"
    log_message "密码长度：${#password}"
    if [ -n "$password" ]; then
        output=$(retry_command "echo \"$password\" | soundness-cli list-keys" 3)
    else
        output=$(retry_command "soundness-cli list-keys" 3)
    fi
    log_message "✅ 列出密钥对成功！输出：$output"
    echo "$output"
}

# 验证并发送证明
send_proof() {
    cd "$SOUNDNESS_DIR"
    if [ ! -f "$SOUNDNESS_DIR/$SOUNDNESS_CONFIG_DIR/key_store.json" ]; then
        handle_error "未找到 key_store.json" "先生成或导入密钥对（选项 2 或 3）"
    fi
    log_message "当前存储的密钥对："
    temp_file=$(secure_password_input)
    if [ ! -f "$temp_file" ]; then
        handle_error "无法访问临时密码文件" "检查磁盘空间：df -h /tmp;检查权限：ls -l /tmp"
    fi
    password=$(cat "$temp_file")
    rm -f "$temp_file"
    log_message "密码长度：${#password}"
    if [ -n "$password" ]; then
        output=$(retry_command "echo \"$password\" | soundness-cli list-keys" 3)
    else
        output=$(retry_command "soundness-cli list-keys" 3)
    fi
    log_message "密钥对列表：$output"
    echo "$output"
    echo "请输入以下参数："
    read -p "密钥对名称（例如 andygan）： " key_name
    validate_input "$key_name" "密钥对名称"
    read -p "证明文件路径或 Walrus Blob ID（例如 proof.bin 或 hvskvOF...）： " proof_file
    read -p "ELF 文件路径或 Blob ID（留空则使用 game 模式）： " elf_file
    read -p "游戏模式（例如 8queens，留空则使用 ELF 文件）： " game
    read -p "证明系统（例如 ligetron）： " proving_system
    read -p "Payload JSON（例如 {\"program\": \"/path/to/wasm\"}）： " payload
    if [ -z "$proof_file" ] || [ -z "$key_name" ] || [ -z "$proving_system" ]; then
        handle_error "缺少必要参数" "提供 --proof-file、--key-name 和 --proving-system"
    fi
    if [ -z "$game" ] && [ -z "$elf_file" ]; then
        handle_error "必须提供 --game 或 --elf_file" "检查输入"
    fi
    if [ -z "$payload" ]; then
        handle_error "缺少 --payload 参数" "提供 --payload，使用双引号包裹 JSON"
    fi
    case "$proving_system" in
        sp1|ligetron|risc0|noir|starknet|miden) ;;
        *) handle_error "不支持的 proving-system：$proving_system" "支持：sp1, ligetron, risc0, noir, starknet, miden" ;;
    esac
    normalized_payload=$(echo "$payload" | sed "s/'/\"/g")
    validate_json "$normalized_payload" "send_proof payload"
    if [ "$proving_system" = "ligetron" ]; then
        if ! echo "$normalized_payload" | jq -e '.program' >/dev/null; then
            handle_error "Ligetron payload 缺少 program 字段" "确保 payload 包含 program 字段，使用双引号"
        fi
    fi
    wasm_path=$(echo "$normalized_payload" | jq -r '.program')
    if [ -n "$wasm_path" ] && [ "$wasm_path" != "null" ] && [ ! -f "$wasm_path" ]; then
        wasm_file=$(basename "$wasm_path")
        cached_wasm="$CACHE_DIR/$wasm_file"
        if [ -f "$cached_wasm" ]; then
            log_message "使用缓存的 WASM 文件：$cached_wasm"
            cp "$cached_wasm" "$wasm_path"
        else
            secure_directory "$(dirname "$wasm_path")"
            secure_directory "$CACHE_DIR"
            log_message "下载 WASM 文件 $wasm_path..."
            retry_command "curl -s -o \"$wasm_path\" https://raw.githubusercontent.com/SoundnessLabs/soundness-layer/main/examples/8queen.wasm" 3
            [ -f "$wasm_path" ] && {
                chmod 644 "$wasm_path"
                cp "$wasm_path" "$cached_wasm"
                log_message "已缓存 WASM 文件到 $cached_wasm"
            } || handle_error "无法下载 WASM 文件 $wasm_path" "检查网络;确认文件 URL"
        fi
    fi
    if [ -n "$elf_file" ] && [ ! -f "$elf_file" ] && ! echo "$elf_file" | grep -qE '^[A-Za-z0-9+/=-_]{20,}$'; then
        elf_file_name=$(basename "$elf_file")
        cached_elf="$CACHE_DIR/$elf_file_name"
        if [ -f "$cached_elf" ]; then
            log_message "使用缓存的 ELF 文件：$cached_elf"
            cp "$cached_elf" "$elf_file"
        else
            secure_directory "$CACHE_DIR"
            log_message "下载 ELF 文件 $elf_file..."
            retry_command "curl -s -o \"$elf_file\" https://raw.githubusercontent.com/SoundnessLabs/soundness-layer/main/examples/8queen.elf" 3
            [ -f "$elf_file" ] && {
                chmod 644 "$elf_file"
                cp "$elf_file" "$cached_elf"
                log_message "已缓存 ELF 文件到 $cached_elf"
            } || handle_error "无法下载 ELF 文件 $elf_file" "检查网络;确认文件 URL"
        fi
    fi
    if [ -n "$proof_file" ] && [ ! -f "$proof_file" ] && ! echo "$proof_file" | grep -qE '^[A-Za-z0-9+/=-_]{20,}$'; then
        handle_error "proof-file $proof_file 无效" "检查文件是否存在或是否为有效的 Walrus Blob ID;访问 https://walruscan.io/blob/$proof_file"
    fi
    key_exists=$(retry_command "soundness-cli list-keys" 3 | grep -w "$key_name")
    [ -z "$key_exists" ] && handle_error "密钥对 $key_name 不存在" "使用选项 2 或 3 导入密钥对;检查名称"
    send_command="soundness-cli send --proof-file=\"$proof_file\" --key-name=\"$key_name\" --proving-system=\"$proving_system\""
    [ -n "$elf_file" ] && send_command="$send_command --elf-file=\"$elf_file\""
    [ -n "$normalized_payload" ] && send_command="$send_command --payload \"$normalized_payload\""
    [ -n "$game" ] && send_command="$send_command --game \"$game\""
    if [ -n "$password" ]; then
        temp_file=$(secure_password_input)
        if [ ! -f "$temp_file" ]; then
            handle_error "无法访问临时密码文件" "检查磁盘空间：df -h /tmp;检查权限：ls -l /tmp"
        fi
        send_command="echo \"$password\" | $send_command"
    fi
    log_message "发送证明：$send_command"
    output=$(eval "$send_command" 2>&1)
    exit_code=$?
    if [ -n "$temp_file" ]; then
        rm -f "$temp_file"
        log_message "已清理临时文件：$temp_file"
    fi
    if [ $exit_code -eq 0 ]; then
        log_message "✅ 证明发送成功！服务器响应：$output"
        echo "$output" | jq -r '.sui_transaction_digest // empty' | grep -v '^$' && echo "交易摘要：$(echo "$output" | jq -r '.sui_transaction_digest')"
        echo "$output" | jq -r '.suiscan_link // empty' | grep -v '^$' && echo "Suiscan 链接：$(echo "$output" | jq -r '.suiscan_link')"
        echo "$output" | jq -r '.walruscan_links[0] // empty' | grep -v '^$' && echo "Walruscan 链接：$(echo "$output" | jq -r '.walruscan_links[0]')"
    else
        if echo "$output" | grep -q "Invalid Ligetron payload format"; then
            handle_error "Ligetron payload 格式错误：$output" "检查 payload JSON（确保键使用双引号）;运行 'echo \"$normalized_payload\" | jq .' 检查;参考文档：https://github.com/SoundnessLabs/soundness-layer/tree/main/soundness-cli"
        fi
        handle_error "发送证明失败" "检查 proof-file：https://walruscan.io/blob/$proof_file;验证 key-name;检查网络：ping testnet.soundness.xyz;更新 CLI（选项 1）"
    fi
}

# 显示菜单
show_menu() {
    clear
    echo "欢迎使用 Soundness CLI 一键脚本！版本：$SCRIPT_VERSION"
    echo "当前状态："
    echo "  - Soundness CLI 版本：$(soundness-cli --version 2>/dev/null || echo '未安装')"
    echo "  - Rust 状态：$(cargo --version 2>/dev/null || echo '未安装')"
    echo "  - 密钥对数量：$( [ -f "$SOUNDNESS_DIR/$SOUNDNESS_CONFIG_DIR/key_store.json" ] && jq '.keys | length' "$SOUNDNESS_DIR/$SOUNDNESS_CONFIG_DIR/key_store.json" 2>/dev/null || echo 0)"
    echo "请选择操作："
    echo "1. 安装/更新 Soundness CLI"
    echo "2. 生成新的密钥对"
    echo "3. 导入密钥对"
    echo "4. 列出密钥对"
    echo "5. 验证并发送证明"
    echo "6. 退出"
    read -p "请输入选项 (1-6)： " choice
}

# 主函数
main() {
    cleanup_temp_files
    export PATH="$PATH:/usr/local/bin:/root/.local/bin:/root/.soundness/bin:$HOME/.cargo/bin"
    source /root/.bashrc 2>/dev/null || true
    while true; do
        show_menu
        case $choice in
            1) install_cli ;;
            2) generate_key_pair ;;
            3) import_key_pair ;;
            4) list_key_pairs ;;
            5) send_proof ;;
            6) log_message "退出脚本。"; cleanup_temp_files; exit 0 ;;
            *) echo "无效选项，请输入 1-6。" ;;
        esac
        echo ""
        read -p "按 Enter 键返回菜单..."
    done
}

# 清理敏感历史记录和临时文件
trap 'cleanup_temp_files; history -c && history -w' EXIT

main
