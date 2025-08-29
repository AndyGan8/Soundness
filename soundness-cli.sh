#!/bin/bash
clear# Soundness CLI 一键脚本（优化版）
# 版本：1.0.7
# 功能：
# 1. 安装/更新 Soundness CLI（通过 soundnessup 和 Docker）
# 2. 生成密钥对
# 3. 导入密钥对
# 4. 列出密钥对
# 5. 验证并发送证明
# 6. 批量导入密钥对
# 7. 删除密钥对
# 8. 退出

set -e# 常量定义
SCRIPT_VERSION="1.0.7"
SOUNDNESS_DIR="/root/soundness-layer/soundness-cli"
SOUNDNESS_CONFIG_DIR=".soundness"
DOCKER_COMPOSE_FILE="docker-compose.yml"
LOG_FILE="/root/soundness-script.log"
REMOTE_VERSION_URL="https://raw.githubusercontent.com/SoundnessLabs/soundness-layer/main/VERSION"
LANG=${LANG:-zh}# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        case $OS in
            "Ubuntu"*) PKG_MANAGER="apt-get" ;;
            "CentOS"*) PKG_MANAGER="yum" ;;
            *) PKG_MANAGER="apt-get"; log_message " 警告：不支持的操作系统 $OS，使用 apt-get" ;;
        esac
    else
        PKG_MANAGER="apt-get"
        log_message " 警告：无法检测操作系统，使用 apt-get"
    fi
}# 日志记录
log_message() {
    local msg=$1
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $msg" >> "$LOG_FILE"
    print_message "$msg"
}# 多语言消息输出
print_message() {
    local msg=$1
    if [ "$LANG" = "zh" ]; then
        case $msg in
            "welcome") echo "欢迎使用 Soundness CLI 一键脚本！" ;;
            "invalid_option") echo "无效选项，请输入 1-8。" ;;
            "error") echo " 错误：$2" ;;
            *) echo "$msg" ;;
        esac
    else
        echo "$msg"
    fi
}# 错误处理
handle_error() {
    local error_msg=$1
    local suggestions=$2
    log_message " 错误：$error_msg"
    log_message "建议："
    echo "$suggestions" | sed 's/;/\n  - /g'
    log_message "加入 Discord（https://discord.gg/soundnesslabs）获取支持。"
    exit 1
}# 重试命令
retry_command() {
    local cmd=$1
    local max_retries=$2
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
        log_message " 失败：$output"
        if [ $retry_count -lt $max_retries ]; then
            log_message "将在 5 秒后重试..."
            sleep 5
        else
            handle_error "命令失败：$cmd" "检查网络：ping raw.githubusercontent.com;验证命令参数;检查 Docker 服务：sudo systemctl status docker;检查 key_store.json：cat $SOUNDNESS_DIR/$SOUNDNESS_CONFIG_DIR/key_store.json;加入 Discord 获取支持"
        fi
    done
}# 确保目录存在
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
}# 验证输入
validate_input() {
    local input=$1
    local field=$2
    if ! echo "$input" | grep -qE '^[A-Za-z0-9_-]+$'; then
        handle_error "无效的 $field：$input" "仅允许字母、数字、下划线和连字符"
    fi
}# 备份 .bashrc
backup_bashrc() {
    local bashrc="/root/.bashrc"
    if [ -f "$bashrc" ]; then
        cp "$bashrc" "$bashrc.bak-$(date +%F-%H-%M-%S)"
        log_message "已备份 $bashrc"
    fi
}# 检查网络
check_network() {
    log_message "检查网络连接..."
    if ! ping -c 1 raw.githubusercontent.com >/dev/null 2>&1; then
        handle_error "无法连接到 GitHub" "检查网络：ping raw.githubusercontent.com;使用代理或 VPN"
    fi
    log_message " 网络连接正常。"
}# 检查服务器状态
check_server_status() {
    log_message "检查 Soundness 服务器状态..."
    if ! curl -s -I https://testnet.soundness.xyz >/dev/null; then
        log_message " 警告：Soundness 服务器可能不可用。"
    else
        log_message " Soundness 服务器正常。"
    fi
}# 检查依赖
check_requirements() {
    detect_os
    log_message "检查依赖..."
    if ! command -v curl >/dev/null 2>&1; then
        handle_error "需要安装 curl" "安装 curl：sudo $PKG_MANAGER install -y curl"
    fi
    if ! command -v git >/dev/null 2>&1; then
        log_message "安装 git..."
        sudo $PKG_MANAGER update && sudo $PKG_MANAGER install -y git
    fi
    if ! command -v jq >/dev/null 2>&1; then
        log_message "安装 jq..."
        sudo $PKG_MANAGER update && sudo $PKG_MANAGER install -y jq
    fi
    if ! command -v docker >/dev/null 2>&1; then
        log_message "警告：Docker 未安装，将在安装流程中自动安装。"
    elif ! systemctl is-active --quiet docker; then
        log_message "启动 Docker 服务..."
        sudo systemctl start docker || handle_error "无法启动 Docker 服务" "检查 Docker 配置：sudo systemctl status docker"
    fi
}# 安装 Rust 和 Cargo
install_rust_cargo() {
    log_message "检查 Rust 和 Cargo..."
    if ! command -v cargo >/dev/null 2>&1; then
        log_message "安装 Rust 和 Cargo..."
        retry_command "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y" 3
        export PATH=$HOME/.cargo/bin:$PATH
        backup_bashrc
        if ! grep -q '.cargo/bin' /root/.bashrc; then
            echo "export PATH=\$HOME/.cargo/bin:\$PATH" >> /root/.bashrc
            log_message "已将 Cargo PATH 写入 /root/.bashrc"
        fi
        source /root/.bashrc
    fi
    if ! cargo --version >/dev/null 2>&1; then
        handle_error "Cargo 安装失败" "检查安装路径：ls -l /root/.cargo/bin/cargo;验证 PATH：echo \$PATH;重新安装 Rust：curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -y"
    fi
    log_message " Rust 和 Cargo 已安装：$(cargo --version)"
}# 获取 soundnessup 版本
get_soundnessup_version() {
    local version=$(soundnessup version 2>/dev/null || soundnessup --version 2>/dev/null || echo "unknown")
    echo "$version"
}# 安装 soundnessup
install_soundnessup() {
    log_message "安装 soundnessup..."
    sudo rm -f /usr/local/bin/soundnessup /root/.local/bin/soundnessup /root/.soundness/bin/soundnessup
    local install_script="install_soundnessup.sh"
    retry_command "curl -sSL https://raw.githubusercontent.com/soundnesslabs/soundness-layer/main/soundnessup/install -o $install_script" 3
    chmod +x "$install_script"
    retry_command "bash $install_script" 3
    rm -f "$install_script"
    export PATH=$PATH:/usr/local/bin:/root/.local/bin:/root/.soundness/bin
    if ! command -v soundnessup >/dev/null 2>&1; then
        handle_error "soundnessup 安装失败" "检查安装路径：ls -l /usr/local/bin/soundnessup;验证 PATH：echo \$PATH;重新安装：curl --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/soundnesslabs/soundness-layer/main/soundnessup/install | bash"
    fi
    if ! soundnessup version >/dev/null 2>&1 && ! soundnessup --version >/dev/null 2>&1; then
        log_message " 警告：soundnessup version 命令不可用"
    fi
    log_message " soundnessup 已安装：$(get_soundnessup_version)"
}# 验证仓库完整性
verify_repo() {
    local repo_dir="$SOUNDNESS_DIR"
    if [ ! -f "$repo_dir/Cargo.toml" ] || [ ! -f "$repo_dir/Dockerfile" ]; then
        handle_error "仓库 $repo_dir 缺少必要文件" "检查网络连接;重新克隆仓库：git clone https://github.com/SoundnessLabs/soundness-layer.git"
    fi
    log_message " 仓库验证通过。"
}# 配置 docker-compose
generate_docker_compose() {
    log_message "生成 docker-compose.yml..."
    cat > "$SOUNDNESS_DIR/$DOCKER_COMPOSE_FILE" <<EOF
services:
  soundness-cli:
    build:
      context: .
      dockerfile: Dockerfile
    volumes:
      - $SOUNDNESS_DIR/$SOUNDNESS_CONFIG_DIR:/home/soundness/.soundness
      - $PWD:/workspace
      - /root/ligero_internal:/root/ligero_internal
    working_dir: /workspace
    environment:
      - RUST_LOG=info
    user: $(id -u):$(id -g)
    stdin_open: true
    tty: true
EOF
    if ! docker-compose -f "$SOUNDNESS_DIR/$DOCKER_COMPOSE_FILE" config >/dev/null 2>&1; then
        handle_error "docker-compose.yml 格式无效" "检查文件内容：cat $SOUNDNESS_DIR/$DOCKER_COMPOSE_FILE;恢复备份：mv $SOUNDNESS_DIR/$DOCKER_COMPOSE_FILE.bak $SOUNDNESS_DIR/$DOCKER_COMPOSE_FILE"
    fi
    log_message " docker-compose.yml 已生成。"
}# 配置 ligero_internal
setup_ligero_internal() {
    local ligero_dir="/root/ligero_internal"
    if [ ! -d "$ligero_dir" ]; then
        log_message "克隆 ligero_internal 仓库..."
        retry_command "git clone https://github.com/SoundnessLabs/ligero_internal.git $ligero_dir" 3
        cd "$ligero_dir/sdk"
        retry_command "make build" 3
        cd -
    fi
    log_message " ligero_internal 已配置。"
}# 安装 Soundness CLI
install_docker_cli() {
    log_message "开始安装/更新 Soundness CLI..."
    check_requirements
    check_network
    install_rust_cargo
    install_soundnessup
    if ! command -v docker >/dev/null 2>&1; then
        log_message "安装 Docker..."
        retry_command "curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh" 3
        sudo systemctl start docker
        sudo systemctl enable docker
        rm -f get-docker.sh
    fi
    if ! command -v docker-compose >/dev/null 2>&1; then
        log_message "安装 docker-compose..."
        retry_command "sudo curl -L https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose" 3
        sudo chmod +x /usr/local/bin/docker-compose
    fi
    if [ ! -d "$SOUNDNESS_DIR" ]; then
        log_message "克隆 Soundness CLI 仓库..."
        retry_command "git clone https://github.com/SoundnessLabs/soundness-layer.git ${SOUNDNESS_DIR}/.." 3
    else
        log_message "更新 Soundness CLI 仓库..."
        cd "${SOUNDNESS_DIR}/.."
        retry_command "git pull origin main" 3
        cd -
    fi
    cd "$SOUNDNESS_DIR"
    verify_repo
    generate_docker_compose
    secure_directory "$SOUNDNESS_DIR/$SOUNDNESS_CONFIG_DIR"
    log_message "更新 Soundness CLI..."
    retry_command "soundnessup update" 3
    if ! soundness-cli --help >/dev/null 2>&1; then
        log_message "尝试重新安装 Soundness CLI..."
        retry_command "soundnessup install" 3
    fi
    if ! soundness-cli --help >/dev/null 2>&1; then
        handle_error "Soundness CLI 安装失败" "检查 soundnessup 日志;验证 Docker 服务;检查 key_store.json：cat $SOUNDNESS_DIR/$SOUNDNESS_CONFIG_DIR/key_store.json;加入 Discord 获取支持"
    fi
    log_message " Soundness CLI 安装完成：$(soundness-cli --version 2>/dev/null || echo 'unknown')"
}# 生成密钥对
generate_key_pair() {
    cd "$SOUNDNESS_DIR"
    read -p "请输入密钥对名称（例如 andygan）： " key_name
    read -sp "请输入密码（留空则无密码，按 Enter 确认）： " password
    echo ""
    validate_input "$key_name" "密钥对名称"
    secure_directory "$SOUNDNESS_CONFIG_DIR"
    log_message "生成密钥对：$key_name..."
    if [ -n "$password" ]; then
        output=$(retry_command "echo \"$password\" | docker-compose run --rm -i soundness-cli generate-key --name \"$key_name\"" 3 2>&1)
    else
        output=$(retry_command "docker-compose run --rm -it soundness-cli generate-key --name \"$key_name\"" 3 2>&1)
    fi
    if [ $? -eq 0 ]; then
        log_message " 密钥对 $key_name 生成成功！"
        log_message "输出：$output"
        echo "$output"
        log_message "请将公钥提交到 Discord #testnet-access 频道，格式：!access <your_public_key>"
        log_message "访问 https://discord.gg/soundnesslabs 获取支持。"
    else
        handle_error "生成密钥对失败：$key_name" "检查 Docker 日志：docker logs <container_id>;验证 key_store.json：cat $SOUNDNESS_DIR/$SOUNDNESS_CONFIG_DIR/key_store.json;确认密码是否正确;加入 Discord 获取支持"
    fi
}# 导入密钥对
import_key_pair() {
    cd "$SOUNDNESS_DIR"
    if [ -f "$SOUNDNESS_CONFIG_DIR/key_store.json" ]; then
        log_message "当前存储的密钥对："
        output=$(retry_command "docker-compose run --rm -it soundness-cli list-keys" 3 2>&1)
        log_message "list-keys 输出：$output"
        echo "$output"
    else
        log_message "未找到 key_store.json，可能是首次导入。"
    fi
    read -p "请输入密钥对名称（例如 andygan）： " key_name
    read -p "请输入助记词（24 个单词）： " mnemonic
    read -sp "请输入密码（留空则无密码，按 Enter 确认）： " password
    echo ""
    validate_input "$key_name" "密钥对名称"
    if [ -z "$mnemonic" ]; then
        handle_error "助记词不能为空" "提供有效的 24 单词助记词"
    fi
    secure_directory "$SOUNDNESS_CONFIG_DIR"
    log_message "导入密钥对：$key_name..."
    if [ -n "$password" ]; then
        output=$(retry_command "echo \"$password\" | docker-compose run --rm -i soundness-cli import-key --name \"$key_name\" --mnemonic \"$mnemonic\"" 3 2>&1)
    else
        output=$(retry_command "docker-compose run --rm -it soundness-cli import-key --name \"$key_name\" --mnemonic \"$mnemonic\"" 3 2>&1)
    fi
    if [ $? -eq 0 ]; then
        log_message " 密钥对 $key_name 导入成功！"
        log_message "输出：$output"
        echo "$output"
    else
        handle_error "导入密钥对失败：$key_name" "检查助记词有效性;验证 key_store.json：cat $SOUNDNESS_DIR/$SOUNDNESS_CONFIG_DIR/key_store.json;检查 Docker 日志：docker logs <container_id>;确认密码是否正确;加入 Discord 获取支持"
    fi
}# 列出密钥对
list_key_pairs() {
    cd "$SOUNDNESS_DIR"
    log_message "列出所有存储的密钥对..."
    read -sp "请输入密码（留空则无密码，按 Enter 确认）： " password
    echo ""
    if [ -n "$password" ]; then
        output=$(retry_command "echo \"$password\" | docker-compose run --rm -i soundness-cli list-keys" 3 2>&1)
    else
        output=$(retry_command "docker-compose run --rm -it soundness-cli list-keys" 3 2>&1)
    fi
    if [ $? -eq 0 ]; then
        log_message " 列出密钥对成功！"
        log_message "输出：$output"
        echo "$output"
    else
        handle_error "列出密钥对失败" "检查 key_store.json：cat $SOUNDNESS_DIR/$SOUNDNESS_CONFIG_DIR/key_store.json;检查 Docker 日志：docker logs <container_id>;确认密码是否正确;加入 Discord 获取支持"
    fi
}# 验证并发送证明
send_proof() {
    cd "$SOUNDNESS_DIR"
    check_server_status
    log_message "准备发送证明..."
    if [ ! -f "$SOUNDNESS_CONFIG_DIR/key_store.json" ]; then
        handle_error "未找到 key_store.json" "先生成或导入密钥对（选项 2 或 3）"
    fi
    log_message "当前存储的密钥对："
    read -sp "请输入密码（留空则无密码，按 Enter 确认）： " password
    echo ""
    if [ -n "$password" ]; then
        output=$(retry_command "echo \"$password\" | docker-compose run --rm -i soundness-cli list-keys" 3 2>&1)
    else
        output=$(retry_command "docker-compose run --rm -it soundness-cli list-keys" 3 2>&1)
    fi
    log_message "list-keys 输出：$output"
    echo "$output"
    echo "请输入完整的 soundness-cli send 命令，例如："
    echo "soundness-cli send --proof-file=\"proof.bin\" --elf-file=\"program.elf\" --key-name=\"andygan\" --proving-system=\"ligetron\" --payload=\"{\\\"program\\\": \\\"/path/to/wasm\\\", ...}\" --game=\"8queens\""
    echo "注意：--payload 必须使用双引号(\")包裹 JSON 字符串，单引号(')可能导致解析失败！"
    read -r -p "命令： " full_command
    if [ -z "$full_command" ]; then
        handle_error "命令不能为空" "提供完整的 send 命令"
    fi
    log_message "输入的命令：$full_command"
    # 提取参数
    proof_file=$(echo "$full_command" | grep -oE -- '--proof-file="[^"]+"' | cut -d'"' -f2)
    elf_file=$(echo "$full_command" | grep -oE -- '--elf-file="[^"]+"' | cut -d'"' -f2)
    key_name=$(echo "$full_command" | grep -oE -- '--key-name="[^"]+"' | cut -d'"' -f2)
    proving_system=$(echo "$full_command" | grep -oE -- '--proving-system="[^"]+"' | cut -d'"' -f2)
    game=$(echo "$full_command" | grep -oE -- '--game="[^"]+"' | cut -d'"' -f2)
    # 提取 payload（支持单引号或双引号）
    payload=$(echo "$full_command" | grep -oE -- "--payload=(\"[^\"]*\"|'[^']*')" | sed -E "s/--payload=(\"|')//g; s/(\"|')\$//g")
    if [ -z "$proof_file" ] || [ -z "$key_name" ] || [ -z "$proving-system" ]; then
        handle_error "缺少必要参数" "提供 --proof-file、--key-name 和 --proving-system"
    fi
    if [ -z "$game" ] && [ -z "$elf_file" ]; then
        handle_error "必须提供 --game 或 --elf-file" "检查命令格式"
    fi
    if [ -z "$payload" ]; then
        handle_error "缺少 --payload 参数" "提供 --payload，使用双引号包裹 JSON;确保命令中包含 --payload;参考文档：https://github.com/SoundnessLabs/soundness-layer/tree/main/soundness-cli"
    fi
    # 规范化 payload（将单引号转为双引号）
    normalized_payload=$(echo "$payload" | sed "s/'/\"/g")
    # 验证 JSON
    echo "$normalized_payload" | jq . >/dev/null 2>&1 || {
        log_message "无效 JSON：$normalized_payload"
        handle_error "payload JSON 格式无效" "检查 JSON 语法（确保使用双引号、正确转义）;运行 'echo \"$normalized_payload\" | jq .' 检查;使用双引号包裹 JSON;参考文档：https://github.com/SoundnessLabs/soundness-layer/tree/main/soundness-cli"
    }
    wasm_path=$(echo "$normalized_payload" | jq -r '.program')
    shader_path=$(echo "$normalized_payload" | jq -r '.["shader-path"]')
    if [ -n "$wasm_path" ] && [ "$wasm_path" != "null" ] && [ ! -f "$wasm_path" ]; then
        wasm_dir=$(dirname "$wasm_path")
        secure_directory "$wasm_dir"
        log_message "下载 WASM 文件 $wasm_path..."
        wasm_urls=(
            "https://raw.githubusercontent.com/SoundnessLabs/soundness-layer/main/examples/8queen.wasm"
            "https://raw.githubusercontent.com/SoundnessLabs/soundness-layer/main/sdk/build/examples/8queen.wasm"
        )
        for url in "${wasm_urls[@]}"; do
            if retry_command "curl -s -o \"$wasm_path\" \"$url\"" 3; then
                chmod 644 "$wasm_path"
                break
            fi
        done
        [ ! -f "$wasm_path" ] && handle_error "无法下载 WASM 文件 $wasm_path" "检查网络;确认文件 URL;加入 Discord 获取支持"
    fi
    if [ -n "$shader_path" ] && [ "$shader_path" != "null" ]; then
        secure_directory "$shader_path"
    fi
    if [ -n "$elf_file" ] && [ ! -f "$elf_file" ]; then
        if ! echo "$elf_file" | grep -qE '^[A-Za-z0-9+/=-_]{20,}$'; then
            log_message "下载 ELF 文件 $elf_file..."
            elf_urls=(
                "https://raw.githubusercontent.com/SoundnessLabs/soundness-layer/main/examples/8queen.elf"
                "https://raw.githubusercontent.com/SoundnessLabs/soundness-layer/main/sdk/build/examples/8queen.elf"
            )
            for url in "${elf_urls[@]}"; do
                if retry_command "curl -s -o \"$elf_file\" \"$url\"" 3; then
                    chmod 644 "$elf_file"
                    break
                fi
            done
            [ ! -f "$elf_file" ] && handle_error "无法下载 ELF 文件 $elf_file" "检查网络;确认文件 URL;加入 Discord 获取支持"
        fi
    fi
    if [ -n "$proof_file" ] && [ ! -f "$proof_file" ] && ! echo "$proof_file" | grep -qE '^[A-Za-z0-9+/=-_]{20,}$'; then
        handle_error "proof-file $proof_file 无效" "检查文件是否存在或是否为有效的 Walrus Blob ID;访问 https://walruscan.io/blob/$proof_file"
    fi
    key_exists=$(retry_command "docker-compose run --rm -it soundness-cli list-keys" 3 | grep -w "$key_name")
    [ -z "$key_exists" ] && handle_error "密钥对 $key_name 不存在" "使用选项 3 或 6 导入密钥对;检查名称"
    case "$proving_system" in
        sp1|ligetron|risc0|noir|starknet|miden) ;;
        *) handle_error "不支持的 proving-system：$proving_system" "支持：sp1, ligetron, risc0, noir, starknet, miden" ;;
    esac
    setup_ligero_internal
    send_command="docker-compose run --rm -it soundness-cli send --proof-file=\"$proof_file\" --key-name=\"$key_name\" --proving-system=\"$proving_system\""
    [ -n "$elf_file" ] && send_command="$send_command --elf-file=\"$elf_file\""
    [ -n "$normalized_payload" ] && send_command="$send_command --payload \"$normalized_payload\""
    [ -n "$game" ] && send_command="$send_command --game \"$game\""
    if [ -n "$password" ]; then
        send_command="echo \"$password\" | $send_command"
    fi
    max_retries=3
    retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        log_message "发送证明（尝试 $((retry_count + 1))/$max_retries）：$send_command"
        output=$(retry_command "$send_command" 1)
        exit_code=$?
        if [ $exit_code -eq 0 ]; then
            log_message " 证明发送成功！"
            log_message "服务器响应：$output"
            sui_status=$(echo "$output" | jq -r '.sui_status // empty')
            if [ "$sui_status" = "error" ]; then
                message=$(echo "$output" | jq -r '.message // empty')
                ((retry_count++))
                log_message " Sui 网络处理失败（尝试 $((retry_count + 1))/$max_retries）：$message"
                [ $retry_count -lt $max_retries ] && sleep 5 && continue
                handle_error "Sui 网络处理失败" "检查 Sui 网络状态：https://suiscan.xyz/testnet;确认账户余额;验证 WASM 文件"
            fi
            proof_hash=$(echo "$output" | jq -r '.proof_data_blob_id // empty')
            if echo "$output" | grep -q "409 Conflict" || echo "$output" | grep -q "Proof with hash.*has already been processed"; then
                proof_hash=$(echo "$output" | jq -r '.message // empty' | grep -oE '[0-9a-f]{64}' || echo "unknown")
                log_message " 证明已提交：$output"
                handle_error "证明已处理（哈希：$proof_hash）" "检查 Walruscan：https://walruscan.io/blob/$proof_file;获取新 proof-file（运行 'docker-compose run --rm -it soundness-cli generate-proof --game=\"8queens\" --key-name=\"$key_name\" --proving-system=\"$proving_system\"' 或参考 Discord：https://discord.gg/soundnesslabs）;确认证明是否与账户关联"
            fi
            log_message " 证明成功处理！"
            echo "$output" | jq -r '.sui_transaction_digest // empty' | grep -v '^$' && echo "交易摘要：$(echo "$output" | jq -r '.sui_transaction_digest')"
            echo "$output" | jq -r '.suiscan_link // empty' | grep -v '^$' && echo "Suiscan 链接：$(echo "$output" | jq -r '.suiscan_link')"
            echo "$output" | jq -r '.walruscan_links[0] // empty' | grep -v '^$' && echo "Walruscan 链接：$(echo "$output" | jq -r '.walruscan_links[0]')"
            return
        fi
        ((retry_count++))
    done
    handle_error "发送证明失败" "检查 proof-file：https://walruscan.io/blob/$proof_file;验证 key-name;检查网络：ping testnet.soundness.xyz;更新 CLI（选项 1）;参考文档：https://github.com/SoundnessLabs/soundness-layer/tree/main/soundness-cli"
}# 批量导入密钥对
batch_import_keys() {
    cd "$SOUNDNESS_DIR"
    log_message "准备批量导入密钥对..."
    if [ -f "$SOUNDNESS_CONFIG_DIR/key_store.json" ]; then
        log_message "当前存储的密钥对："
        read -sp "请输入密码（留空则无密码，按 Enter 确认）： " password
        echo ""
        if [ -n "$password" ]; then
            output=$(retry_command "echo \"$password\" | docker-compose run --rm -i soundness-cli list-keys" 3 2>&1)
        else
            output=$(retry_command "docker-compose run --rm -it soundness-cli list-keys" 3 2>&1)
        fi
        log_message "list-keys 输出：$output"
        echo "$output"
    fi
    echo "请输入助记词列表（每行格式：key_name:mnemonic，完成后按 Ctrl+D）"
    echo "或提供文本文件路径（格式同上）"
    read -p "输入方式（1-手动输入，2-文件路径）： " input_method
    read -sp "请输入密码（留空则无密码，按 Enter 确认）： " password
    echo ""
    if [ "$input_method" = "1" ]; then
        keys_input=$(cat)
    elif [ "$input_method" = "2" ]; then
        read -p "文本文件路径： " file_path
        [ -f "$file_path" ] || handle_error "文件 $file_path 不存在" "检查文件路径"
        keys_input=$(cat "$file_path")
    else
        handle_error "无效的输入方式" "选择 1 或 2"
    fi
    secure_directory "$SOUNDNESS_CONFIG_DIR"
    success_count=0
    fail_count=0
    echo "$keys_input" | while IFS=: read -r key_name mnemonic; do
        key_name=$(echo "$key_name" | xargs)
        mnemonic=$(echo "$mnemonic" | xargs)
        if [ -z "$key_name" ] || [ -z "$mnemonic" ]; then
            log_message " 跳过无效行：$key_name:$mnemonic"
            ((fail_count++))
            continue
        fi
        validate_input "$key_name" "密钥对名称"
        log_message "导入密钥对：$key_name..."
        if [ -n "$password" ]; then
            output=$(retry_command "echo \"$password\" | docker-compose run --rm -i soundness-cli import-key --name \"$key_name\" --mnemonic \"$mnemonic\"" 3 2>&1)
        else
            output=$(retry_command "docker-compose run --rm -it soundness-cli import-key --name \"$key_name\" --mnemonic \"$mnemonic\"" 3 2>&1)
        fi
        if [ $? -eq 0 ]; then
            log_message " 密钥对 $key_name 导入成功！"
            ((success_count++))
        else
            log_message " 导入密钥对 $key_name 失败：$output"
            ((fail_count++))
        fi
    done
    log_message " 批量导入完成！成功：$success_count，失败：$fail_count"
    [ $fail_count -gt 0 ] && log_message "请检查失败的密钥对并重试。"
}# 删除密钥对
delete_key_pair() {
    cd "$SOUNDNESS_DIR"
    log_message "准备删除密钥对..."
    if [ ! -f "$SOUNDNESS_CONFIG_DIR/key_store.json" ]; then
        handle_error "未找到 key_store.json" "没有可删除的密钥对"
    fi
    log_message "当前存储的密钥对："
    read -sp "请输入密码（留空则无密码，按 Enter 确认）： " password
    echo ""
    if [ -n "$password" ]; then
        output=$(retry_command "echo \"$password\" | docker-compose run --rm -i soundness-cli list-keys" 3 2>&1)
    else
        output=$(retry_command "docker-compose run --rm -it soundness-cli list-keys" 3 2>&1)
    fi
    log_message "list-keys 输出：$output"
    read -p "请输入要删除的密钥对名称（例如 andygan）： " key_name
    validate_input "$key_name" "密钥对名称"
    key_exists=$(retry_command "docker-compose run --rm -it soundness-cli list-keys" 3 | grep -w "$key_name")
    [ -z "$key_exists" ] && handle_error "密钥对 $key_name 不存在" "检查名称;使用选项 4 查看密钥对"
    log_message " 警告：删除密钥对 $key_name 不可逆！"
    read -p "确认删除？(y/n)： " confirm
    [ "$confirm" != "y" ] && { log_message "操作取消。"; return; }
    jq "del(.keys.\"$key_name\")" "$SOUNDNESS_CONFIG_DIR/key_store.json" > "$SOUNDNESS_CONFIG_DIR/key_store.json.tmp"
    mv "$SOUNDNESS_CONFIG_DIR/key_store.json.tmp" "$SOUNDNESS_CONFIG_DIR/key_store.json"
    chmod 600 "$SOUNDNESS_CONFIG_DIR/key_store.json"
    log_message " 密钥对 $key_name 删除成功！"
}# 检查脚本版本
check_script_version() {
    local remote_version=$(curl -s "$REMOTE_VERSION_URL" 2>/dev/null || echo "unknown")
    if [ "$remote_version" = "unknown" ]; then
        log_message " 无法检查脚本版本，URL $REMOTE_VERSION_URL 不可用"
    elif [ -n "$remote_version" ] && [ "$remote_version" != "$SCRIPT_VERSION" ]; then
        log_message " 新版本 $remote_version 可用（当前版本：$SCRIPT_VERSION）。请从 https://github.com/SoundnessLabs/soundness-layer 更新脚本。"
    else
        log_message " 脚本版本 $SCRIPT_VERSION 为最新"
    fi
}# 显示菜单
show_menu() {
    clear
    print_message "welcome"
    cat << EOF
请选择操作：安装/更新 Soundness CLI（通过 soundnessup 和 Docker）
生成新的密钥对
导入密钥对
列出密钥对
验证并发送证明
批量导入密钥对
删除密钥对
退出
EOF
 read -p "请输入选项 (1-8)： " choice
}

# 主函数
main() {
    check_requirements
    check_script_version
    export PATH=$PATH:/usr/local/bin:/root/.local/bin:/root/.soundness/bin:$HOME/.cargo/bin
    source /root/.bashrc 2>/dev/null || true
    while true; do
        show_menu
        case $choice in
            1) install_docker_cli ;;
            2) generate_key_pair ;;
            3) import_key_pair ;;
            4) list_key_pairs ;;
            5) send_proof ;;
            6) batch_import_keys ;;
            7) delete_key_pair ;;
            8) log_message "退出脚本。"; exit 0 ;;
            *) print_message "invalid_option" ;;
        esac
        echo ""
        read -p "按 Enter 键返回菜单..."
    done
}main

