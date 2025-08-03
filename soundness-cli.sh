#!/bin/bash
clear

# Soundness CLI 一键脚本
# 支持选项：
# 1. 安装/更新 Soundness CLI（通过 soundnessup 和 Docker）
# 2. 生成密钥对
# 3. 导入密钥对
# 4. 列出密钥对
# 5. 验证并发送证明（自动创建/下载 ligero_internal）
# 6. 批量导入密钥对
# 7. 删除密钥对
# 8. 退出

set -e

check_requirements() {
    if ! command -v curl >/dev/null 2>&1; then
        echo "错误：需要安装 curl。请先安装 curl：sudo apt-get install -y curl"
        exit 1
    fi
    if ! command -v docker >/dev/null 2>&1; then
        echo "警告：Docker 未安装。选择安装选项时将自动安装。"
    else
        if ! systemctl is-active --quiet docker; then
            echo "错误：Docker 服务未运行。尝试启动..."
            sudo systemctl start docker || {
                echo "错误：无法启动 Docker 服务，请检查系统配置：sudo systemctl status docker"
                exit 1
            }
        fi
    fi
    if ! command -v git >/dev/null 2>&1; then
        echo "安装 git..."
        sudo apt-get update && sudo apt-get install -y git
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "安装 jq..."
        sudo apt-get update && sudo apt-get install -y jq
    fi
}

install_docker_cli() {
    echo "正在安装/更新 Soundness CLI..."

    # 安装 soundnessup
    if ! command -v soundnessup >/dev/null 2>&1; then
        echo "安装 soundnessup 工具..."
        curl -sSL https://raw.githubusercontent.com/soundnesslabs/soundness-layer/main/soundnessup/install -o install_soundnessup.sh || {
            echo "错误：无法下载 soundnessup 安装脚本，请检查网络连接：ping raw.githubusercontent.com"
            echo "手动安装步骤："
            echo "  1. 下载脚本：curl -sSL https://raw.githubusercontent.com/soundnesslabs/soundness-layer/main/soundnessup/install -o install_soundnessup.sh"
            echo "  2. 检查脚本：cat install_soundnessup.sh"
            echo "  3. 运行脚本：bash install_soundnessup.sh"
            echo "  4. 加入 Discord（https://discord.gg/soundnesslabs）获取支持"
            exit 1
        }
        chmod +x install_soundnessup.sh
        bash install_soundnessup.sh || {
            echo "错误：运行 soundnessup 安装脚本失败"
            echo "请检查 install_soundnessup.sh 内容：cat install_soundnessup.sh"
            exit 1
        }
        rm -f install_soundnessup.sh

        # 显式设置 PATH
        export PATH=$PATH:/usr/local/bin:/root/.local/bin:/root/.soundness/bin
        # 检查可能的安装路径
        soundnessup_path=""
        for path in /usr/local/bin/soundnessup /root/.local/bin/soundnessup /root/.soundness/bin/soundnessup; do
            if [ -f "$path" ] && [ -x "$path" ]; then
                soundnessup_path="$path"
                break
            fi
        done

        if [ -n "$soundnessup_path" ]; then
            echo "✅ 找到 soundnessup：$soundnessup_path"
            # 移动到 /usr/local/bin
            if [ "$soundnessup_path" != "/usr/local/bin/soundnessup" ]; then
                echo "移动 soundnessup 到 /usr/local/bin..."
                sudo mv "$soundnessup_path" /usr/local/bin/soundnessup
                sudo chmod +x /usr/local/bin/soundnessup
            fi
        else
            echo "错误：soundnessup 未找到，可能安装失败。"
            echo "检查以下路径："
            echo "  ls -l /usr/local/bin/soundnessup"
            echo "  ls -l /root/.local/bin/soundnessup"
            echo "  ls -l /root/.soundness/bin/soundnessup"
            echo "手动修复步骤："
            echo "  1. 重新运行安装：curl -sSL https://raw.githubusercontent.com/soundnesslabs/soundness-layer/main/soundnessup/install | bash"
            echo "  2. 检查 PATH：echo \$PATH"
            echo "  3. 验证：/usr/local/bin/soundnessup --help"
            echo "  4. 加入 Discord（https://discord.gg/soundnesslabs）获取支持"
            exit 1
        fi

        # 验证 soundnessup 是否可用
        if ! soundnessup --help >/dev/null 2>&1; then
            echo "错误：soundnessup 安装后不可用。"
            echo "请检查："
            echo "  1. 文件权限：ls -l /usr/local/bin/soundnessup"
            echo "  2. PATH 环境：echo \$PATH"
            echo "  3. 手动运行：/usr/local/bin/soundnessup --help"
            echo "  4. 加入 Discord（https://discord.gg/soundnesslabs）获取支持"
            exit 1
        fi
        echo "✅ soundnessup 已正确安装。"

        # 持久化 PATH
        if ! grep -q '/usr/local/bin' /root/.bashrc; then
            echo "export PATH=\$PATH:/usr/local/bin:/root/.local/bin:/root/.soundness/bin" >> /root/.bashrc
            echo "已将 PATH 更新写入 /root/.bashrc"
        fi
        source /root/.bashrc
    else
        echo "✅ soundnessup 已存在，正在验证..."
        if ! soundnessup --help >/dev/null 2>&1; then
            echo "错误：soundnessup 不可用，请检查："
            echo "  1. 文件权限：ls -l /usr/local/bin/soundnessup"
            echo "  2. PATH 环境：echo \$PATH"
            echo "  3. 手动运行：/usr/local/bin/soundnessup --help"
            echo "  4. 重新安装：curl -sSL https://raw.githubusercontent.com/soundnesslabs/soundness-layer/main/soundnessup/install | bash"
            exit 1
        fi
        echo "✅ soundnessup 已正确安装。"
    fi

    # 更新 Soundness CLI
    echo "更新 Soundness CLI 到最新版本..."
    soundnessup update || {
        echo "错误：无法更新 Soundness CLI，尝试重新安装..."
        soundnessup install || {
            echo "错误：无法安装 Soundness CLI，请检查网络连接或 soundnessup 工具。"
            echo "手动修复步骤："
            echo "  1. 检查网络：ping raw.githubusercontent.com"
            echo "  2. 手动运行：soundnessup install"
            echo "  3. 验证版本：soundnessup --help"
            echo "  4. 加入 Discord（https://discord.gg/soundnesslabs）获取支持"
            exit 1
        }
    }
    echo "Soundness CLI 更新完成。"

    # 安装 Docker（如果需要）
    if ! command -v docker >/dev/null 2>&1; then
        echo "安装 Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        sudo systemctl start docker
        sudo systemctl enable docker
        echo "Docker 安装完成。"
    fi

    if ! command -v docker-compose >/dev/null 2>&1; then
        echo "安装 docker-compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        echo "docker-compose 安装完成。"
    fi

    # 克隆或更新仓库
    if [ ! -d "soundness-layer" ]; then
        echo "未找到 Soundness CLI 源代码，克隆仓库..."
        git clone https://github.com/SoundnessLabs/soundness-layer.git || {
            echo "错误：无法克隆 Soundness CLI 仓库，请检查网络连接或仓库地址。"
            exit 1
        }
    else
        echo "更新 Soundness CLI 仓库..."
        cd soundness-layer
        git pull origin main || {
            echo "错误：无法更新仓库，请检查网络连接或仓库状态。"
            exit 1
        }
        cd ..
    fi
    cd soundness-layer/soundness-cli

    if [ ! -f "Dockerfile" ]; then
        echo "错误：缺少 Dockerfile 文件，尝试下载..."
        curl -O https://raw.githubusercontent.com/SoundnessLabs/soundness-layer/main/soundness-cli/Dockerfile || {
            echo "错误：无法下载 Dockerfile 文件。"
            exit 1
        }
    fi
    if [ ! -f "Cargo.toml" ]; then
        echo "错误：缺少 Cargo.toml 文件，请确认仓库完整性。"
        exit 1
    fi

    # 配置 docker-compose.yml
    echo "检查并修复 docker-compose.yml..."
    cp docker-compose.yml docker-compose.yml.bak 2>/dev/null || echo "无现有 docker-compose.yml"

    cat > docker-compose.yml.tmp <<EOF
version: '3.8'
services:
  soundness-cli:
    build:
      context: .
      dockerfile: Dockerfile
    volumes:
      - ./.soundness:/home/soundness/.soundness
      - \${PWD}/.soundness:/workspace
      - /root/ligero_internal:/root/ligero_internal
    working_dir: /workspace
    environment:
      - RUST_LOG=info
    user: root
    stdin_open: true
    tty: true
EOF

    if [ -f "docker-compose.yml" ]; then
        if ! grep -q "^version: '3.8'" docker-compose.yml; then
            echo "添加 version: '3.8'..."
            echo "version: '3.8'" > docker-compose.yml.new
            grep -v "^version:" docker-compose.yml >> docker-compose.yml.new
            mv docker-compose.yml.new docker-compose.yml
        fi
        if ! grep -q "user: root" docker-compose.yml; then
            echo "添加 user: root..."
            sed '/^  soundness-cli:/a \    user: root' docker-compose.yml > docker-compose.yml.new
            mv docker-compose.yml.new docker-compose.yml
        fi
    else
        mv docker-compose.yml.tmp docker-compose.yml
    fi

    if ! error=$(docker-compose -f docker-compose.yml config 2>&1 >/dev/null); then
        echo "错误：docker-compose.yml 格式无效："
        echo "$error"
        echo "恢复备份文件..."
        mv docker-compose.yml.bak docker-compose.yml 2>/dev/null || echo "无备份文件可恢复"
        exit 1
    fi
    rm -f docker-compose.yml.tmp
    echo "docker-compose.yml 已修复并验证。"

    if [ -d "target" ]; then
        echo "清理 target 目录以减少构建上下文..."
        rm -rf target
    fi

    chmod -R 777 .
    if [ ! -d ".soundness" ]; then
        echo "创建 .soundness 目录..."
        mkdir .soundness
        chmod 777 .soundness
    fi

    echo "构建 Soundness CLI Docker 镜像..."
    docker-compose build
    echo "Soundness CLI Docker 镜像构建完成。"
}

generate_key_pair() {
    cd /root/soundness-layer/soundness-cli
    read -p "请输入密钥对名称（例如 andygan）： " key_name
    if [ -z "$key_name" ]; then
        echo "错误：密钥对名称不能为空。"
        exit 1
    fi
    echo "正在生成新的密钥对：$key_name..."
    chmod -R 777 .
    if [ ! -d ".soundness" ]; then
        echo "创建 .soundness 目录..."
        mkdir .soundness
        chmod 777 .soundness
    fi
    docker-compose run --rm soundness-cli generate-key --name "$key_name"
    echo "请将公钥提交到 Discord #testnet-access 频道，格式：!access <your_public_key>"
    echo "访问 https://discord.gg/soundnesslabs 获取支持。"
}

import_key_pair() {
    cd /root/soundness-layer/soundness-cli
    echo "当前存储的密钥对名称："
    if [ -f ".soundness/key_store.json" ]; then
        docker-compose run --rm soundness-cli list-keys
    else
        echo "未找到 .soundness/key_store.json，可能是首次导入。"
    fi
    read -p "请输入密钥对名称（或输入新名称以重新导入，例如 andygan）： " key_name
    read -p "请输入助记词（mnemonic，24 个单词）： " mnemonic
    if [ -z "$key_name" ] || [ -z "$mnemonic" ]; then
        echo "错误：密钥对名称和助记词不能为空。"
        exit 1
    fi
    echo "正在导入密钥对：$key_name..."
    chmod -R 777 .
    if [ ! -d ".soundness" ]; then
        echo "创建 .soundness 目录..."
        mkdir .soundness
        chmod 777 .soundness
    fi
    docker-compose run --rm soundness-cli import-key --name "$key_name" --mnemonic "$mnemonic"
}

list_key_pairs() {
    cd /root/soundness-layer/soundness-cli
    echo "列出所有存储的密钥对..."
    docker-compose run --rm soundness-cli list-keys
}

send_proof() {
    cd /root/soundness-layer/soundness-cli
    echo "准备发送证明到 Soundness CLI..."

    # 显示当前密钥对（如果存在）
    if [ -f ".soundness/key_store.json" ]; then
        echo "当前存储的密钥对名称："
        docker-compose run --rm soundness-cli list-keys
    else
        echo "❌ 错误：未找到 .soundness/key_store.json，请先生成或导入密钥对（使用选项 2 或 3）。"
        read -p "是否继续？(y/n)： " continue_choice
        if [ "$continue_choice" != "y" ]; then
            echo "操作取消。"
            return
        fi
    fi

    # 提示用户输入完整命令
    echo "请输入完整的 soundness-cli send 命令，例如："
    echo "soundness-cli send --proof-file=\"path-or-blob-id\" --elf-file=\"path-or-blob-id\" --key-name=\"andygan\" --proving-system=\"ligetron\" --payload='{\"program\": \"/path/to/wasm\", ...}' --game=\"8queens\""
    read -r -p "命令： " full_command

    # 验证命令是否为空
    if [ -z "$full_command" ]; then
        echo "❌ 错误：命令不能为空。"
        return
    fi

    # 解析命令参数
    proof_file=$(echo "$full_command" | grep -oP '(?<=--proof-file=)(("[^"]*")|[^\s]+)' | tr -d '"')
    elf_file=$(echo "$full_command" | grep -oP '(?<=--elf-file=)(("[^"]*")|[^\s]+)' | tr -d '"')
    key_name=$(echo "$full_command" | grep -oP '(?<=--key-name=)(("[^"]*")|[^\s]+)' | tr -d '"')
    proving_system=$(echo "$full_command" | grep -oP '(?<=--proving-system=)(("[^"]*")|[^\s]+)' | tr -d '"')
    payload=$(echo "$full_command" | grep -oP "(?<=--payload=)('[^']*'|[^\s]+)" | sed "s/^'//;s/'$//")
    game=$(echo "$full_command" | grep -oP '(?<=--game=)(("[^"]*")|[^\s]+)' | tr -d '"')

    # 验证必要参数
    if [ -z "$proof_file" ] || [ -z "$key_name" ] || [ -z "$proving_system" ]; then
        echo "❌ 错误：必须提供 --proof-file、--key-name 和 --proving-system 参数。"
        echo "您输入的命令：$full_command"
        return
    fi

    # 验证 game 或 elf-file 是否提供
    if [ -z "$game" ] && [ -z "$elf_file" ]; then
        echo "❌ 错误：必须提供 --game 或 --elf-file 参数。"
        echo "使用示例："
        echo "  - soundness-cli send --proof-file proof.bin --game 8queens --key-name andygan --proving-system ligetron"
        echo "  - soundness-cli send --proof-file proof.bin --elf-file program.elf --key-name andygan --proving-system ligetron"
        return
    fi

    # 验证 payload 的 JSON 格式（如果提供）
    if [ -n "$payload" ]; then
        echo "$payload" | jq . >/dev/null 2>&1 || {
            echo "❌ 错误：payload JSON 格式无效，请检查输入。"
            echo "您输入的 payload：$payload"
            return
        }
    fi

    # 验证 WASM 文件和 shader 目录（如果 payload 提供）
    if [ -n "$payload" ]; then
        wasm_path=$(echo "$payload" | jq -r '.program')
        shader_path=$(echo "$payload" | jq -r '.["shader-path"]')
        if [ -n "$wasm_path" ] && [ "$wasm_path" != "null" ]; then
            wasm_dir=$(dirname "$wasm_path")
            if [ ! -d "$wasm_dir" ]; then
                echo "⚠️ 警告：ligero_internal 目录 $wasm_dir 不存在，尝试创建..."
                mkdir -p "$wasm_dir"
                chmod 755 "$wasm_dir"
            fi
            if [ ! -f "$wasm_path" ]; then
                echo "⚠️ 警告：WASM 文件 $wasm_path 不存在，尝试下载..."
                wasm_urls=(
                    "https://raw.githubusercontent.com/SoundnessLabs/soundness-layer/main/examples/8queen.wasm"
                    "https://raw.githubusercontent.com/SoundnessLabs/soundness-layer/main/sdk/build/examples/8queen.wasm"
                )
                downloaded=false
                for url in "${wasm_urls[@]}"; do
                    if curl -s -o "$wasm_path" "$url"; then
                        echo "✅ 成功下载 WASM 文件到 $wasm_path 从 $url"
                        chmod 644 "$wasm_path"
                        downloaded=true
                        break
                    fi
                done
                if [ "$downloaded" = false ]; then
                    echo "❌ 错误：无法下载 WASM 文件 $wasm_path"
                    echo "建议："
                    echo "  - 确认网络连接（ping raw.githubusercontent.com）"
                    echo "  - 检查 https://github.com/SoundnessLabs/soundness-layer 是否包含 8queen.wasm"
                    echo "  - 加入 Discord（https://discord.gg/soundnesslabs）获取支持和 8queen.wasm 文件"
                    echo "  - 尝试编译 ligero_internal 源码（cd /root/ligero_internal/sdk && make build）"
                    echo "  - 更新 payload 中的 program 路径为现有 WASM 文件"
                    return
                fi
            fi
        fi
        if [ -n "$shader_path" ] && [ "$shader_path" != "null" ] && [ ! -d "$shader_path" ]; then
            echo "⚠️ 警告：shader 目录 $shader_path 不存在，尝试创建..."
            mkdir -p "$shader_path"
            chmod 755 "$shader_path"
            echo "提示：已创建空 shader 目录 $shader_path"
            echo "请在 Discord（https://discord.gg/soundnesslabs）确认是否需要特定着色器文件。"
        fi
    fi

    # 验证 ELF 文件（如果提供）
    if [ -n "$elf_file" ] && [ ! -f "$elf_file" ]; then
        if ! echo "$elf_file" | grep -qE '^[A-Za-z0-9+/=-_]{20,}$'; then
            echo "⚠️ 警告：ELF 文件 $elf_file 不存在，尝试下载..."
            elf_urls=(
                "https://raw.githubusercontent.com/SoundnessLabs/soundness-layer/main/examples/8queen.elf"
                "https://raw.githubusercontent.com/SoundnessLabs/soundness-layer/main/sdk/build/examples/8queen.elf"
            )
            downloaded=false
            for url in "${elf_urls[@]}"; do
                if curl -s -o "$elf_file" "$url"; then
                    echo "✅ 成功下载 ELF 文件到 $elf_file 从 $url"
                    chmod 644 "$elf_file"
                    downloaded=true
                    break
                fi
            done
            if [ "$downloaded" = false ]; then
                echo "❌ 错误：无法下载 ELF 文件 $elf_file"
                echo "建议："
                echo "  - 确认网络连接（ping raw.githubusercontent.com）"
                echo "  - 检查 https://github.com/SoundnessLabs/soundness-layer 是否包含 8queen.elf"
                echo "  - 加入 Discord（https://discord.gg/soundnesslabs）获取支持和 8queen.elf 文件"
                echo "  - 尝试编译 ligero_internal 源码（cd /root/ligero_internal/sdk && make build）"
                return
            fi
        fi
    fi

    # 验证 proof-file（文件路径或 Walrus Blob ID）
    if [ -n "$proof_file" ] && [ ! -f "$proof_file" ]; then
        if ! echo "$proof_file" | grep -qE '^[A-Za-z0-9+/=-_]{20,}$'; then
            echo "❌ 错误：proof-file $proof_file 不是本地文件，也不是有效的 Walrus Blob ID。"
            echo "建议："
            echo "  - 检查 proof-file 是否正确（访问 https://walruscan.io/blob/$proof_file）"
            echo "  - 确认 Walrus Blob ID 格式（通常为 40+ 字符的 base64 字符串）"
            echo "  - 在 Discord（https://discord.gg/soundnesslabs）获取支持"
            read -p "是否继续？(y/n)： " continue_proof
            if [ "$continue_proof" != "y" ]; then
                echo "操作取消。"
                return
            fi
        fi
    fi

    # 验证 key-name 是否存在
    if [ -f ".soundness/key_store.json" ]; then
        key_exists=$(docker-compose run --rm soundness-cli list-keys | grep -w "$key_name")
        if [ -z "$key_exists" ]; then
            echo "❌ 错误：密钥对 $key_name 不存在！"
            echo "建议：使用选项 3 或 6 导入密钥对，或检查 key-name 是否正确（例如 'andygan'）。"
            return
        fi
    fi

    # 验证 proving-system
    case "$proving_system" in
        sp1|ligetron|risc0|noir|starknet|miden) ;;
        *) echo "❌ 错误：不支持的 proving-system：$proving_system。支持的系统：sp1, ligetron, risc0, noir, starknet, miden"
           return ;;
    esac

    # 确保 .soundness 目录存在
    if [ ! -d ".soundness" ]; then
        echo "创建 .soundness 目录..."
        mkdir .soundness
        chmod 777 .soundness
    fi

    # 构建 send 命令
    send_command="docker-compose run --rm soundness-cli send --proof-file=\"$proof_file\" --key-name=\"$key_name\" --proving-system=\"$proving_system\""
    if [ -n "$elf_file" ]; then
        send_command="$send_command --elf-file=\"$elf_file\""
    fi
    if [ -n "$payload" ]; then
        send_command="$send_command --payload='$payload'"
    fi
    if [ -n "$game" ]; then
        send_command="$send_command --game=\"$game\""
    fi

    # 执行 send 命令，添加重试机制（最多 3 次）
    max_retries=3
    retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        echo "正在发送证明（尝试 $((retry_count + 1))/$max_retries）：proof-file=$proof_file, key-name=$key_name, proving-system=$proving_system..."
        output=$(eval "$send_command" 2>&1)
        exit_code=$?

        # 检查执行结果
        if [ $exit_code -eq 0 ]; then
            echo "✅ 证明发送成功！"
            echo "服务器响应："
            echo "$output"
            
            # 解析服务器响应
            sui_status=$(echo "$output" | grep -oP '(?<="sui_status":")[^"]*')
            message=$(echo "$output" | grep -oP '(?<="message":")[^"]*')
            proof_verification_status=$(echo "$output" | grep -oP '(?<="proof_verification_status":)[^,]*')
            sui_transaction_digest=$(echo "$output" | grep -oP '(?<="sui_transaction_digest":")[^"]*')
            suiscan_link=$(echo "$output" | grep -oP '(?<="suiscan_link":")[^"]*')
            walruscan_links=$(echo "$output" | grep -oP '(?<="walruscan_links":\[\")[^"]*')

            if [ "$sui_status" = "error" ]; then
                echo "⚠️ 警告：证明验证通过，但 Sui 网络处理失败（尝试 $((retry_count + 1))/$max_retries）。"
                echo "服务器消息：$message"
                echo "可能的原因："
                echo "  - Sui 网络连接问题或节点同步失败"
                echo "  - 账户余额不足以支付交易费用"
                echo "  - 提交的参数（如 args 或 WASM 文件）与要求不匹配"
                echo "建议："
                echo "  - 检查 Sui 网络状态（https://suiscan.xyz/testnet）"
                echo "  - 确认账户余额（sui client balance --address <your_address>）"
                echo "  - 验证 WASM 文件 ($wasm_path) 是否正确"
                echo "  - 检查 payload 中的 args 参数格式"
                echo "  - 加入 Discord（https://discord.gg/soundnesslabs）获取支持"
                echo "    - Proof-file: $proof_file"
                echo "    - Key-name: $key_name"
                echo "    - Proving-system: $proving_system"
                echo "    - 服务器响应："
                echo "$output"
                ((retry_count++))
                if [ $retry_count -lt $max_retries ]; then
                    echo "将在 5 秒后重试..."
                    sleep 5
                    continue
                else
                    echo "❌ 错误：已达到最大重试次数 ($max_retries)，Sui 网络处理仍失败。"
                    return
                fi
            else
                echo "🎉 证明已成功发送并在 Sui 网络上处理完成！"
                if [ -n "$sui_transaction_digest" ]; then
                    echo "交易摘要：$sui_transaction_digest"
                fi
                if [ -n "$suiscan_link" ]; then
                    echo "Suiscan 链接：$suiscan_link"
                fi
                if [ -n "$walruscan_links" ]; then
                    echo "Walruscan 链接：$walruscan_links"
                fi
                return
            fi
        else
            echo "❌ 错误：发送证明失败！"
            echo "错误详情："
            echo "$output"
            echo "可能的原因："
            echo "  - 无效的 proof-file ($proof_file)"
            echo "  - 无效的 key-name ($key_name)"
            echo "  - WASM 文件 ($wasm_path) 或 ELF 文件 ($elf_file) 无效"
            echo "  - CLI 版本过旧"
            echo "  - 网络连接问题或服务器不可用（https://testnet.soundness.xyz）"
            echo "建议："
            echo "  - 检查 proof-file 是否有效（https://walruscan.io/blob/$proof_file）"
            echo "  - 确认 key-name 是否在 .soundness/key_store.json 中（使用选项 4）"
            echo "  - 验证 WASM 文件和 shader 目录是否存在"
            echo "  - 检查网络连接（ping testnet.soundness.xyz）"
            echo "  - 确保 CLI 已更新到最新版本（选项 1）"
            echo "  - 加入 Discord（https://discord.gg/soundnesslabs）获取支持"
            echo "您输入的命令：$full_command"
            return
        fi
    done
}

batch_import_keys() {
    cd /root/soundness-layer/soundness-cli
    echo "准备批量导入密钥对..."

    if [ -f ".soundness/key_store.json" ]; then
        echo "当前存储的密钥对名称："
        docker-compose run --rm soundness-cli list-keys
    else
        echo "未找到 .soundness/key_store.json，将创建新的密钥存储。"
    fi

    echo "请输入助记词（mnemonic）列表，每行包含一个 '名称:助记词' 对，格式如下："
    echo "key_name1:mnemonic_phrase1"
    echo "key_name2:mnemonic_phrase2"
    echo "您可以："
    echo "1. 手动输入（每行一个，完成后按 Ctrl+D 保存）"
    echo "2. 提供包含助记词的文本文件路径"
    read -p "请选择输入方式（1-手动输入，2-文件路径）： " input_method

    if [ "$input_method" = "1" ]; then
        echo "请输入助记词列表（每行格式：key_name:mnemonic，完成后按 Ctrl+D）："
        keys_input=$(cat)
    elif [ "$input_method" = "2" ]; then
        read -p "请输入文本文件路径： " file_path
        if [ -f "$file_path" ]; then
            keys_input=$(cat "$file_path")
        else
            echo "❌ 错误：文件 $file_path 不存在！"
            return
        fi
    else
        echo "❌ 错误：无效的输入方式，请选择 1 或 2。"
        return
    fi

    if [ ! -d ".soundness" ]; then
        echo "创建 .soundness 目录..."
        mkdir .soundness
        chmod 777 .soundness
    fi

    success_count=0
    fail_count=0
    echo "$keys_input" | while IFS=: read -r key_name mnemonic; do
        if [ -z "$key_name" ] || [ -z "$mnemonic" ]; then
            echo "⚠️ 警告：跳过无效行（缺少 key_name 或 mnemonic）：$key_name:$mnemonic"
            ((fail_count++))
            continue
        fi

        key_name=$(echo "$key_name" | xargs)
        mnemonic=$(echo "$mnemonic" | xargs)

        echo "正在导入密钥对：$key_name..."
        output=$(docker-compose run --rm soundness-cli import-key --name "$key_name" --mnemonic "$mnemonic" 2>&1)
        exit_code=$?

        if [ $exit_code -eq 0 ]; then
            echo "✅ 密钥对 $key_name 导入成功！"
            ((success_count++))
        else
            echo "❌ 错误：导入密钥对 $key_name 失败！"
            echo "错误详情："
            echo "$output"
            echo "可能的原因："
            echo "  - 助记词格式无效（需 24 个单词，符合 BIP39 标准）"
            echo "  - 密钥对名称已存在"
            echo "  - Docker 容器配置错误"
            echo "建议："
            echo "  - 检查助记词是否正确"
            echo "  - 确保 key_name 未被占用"
            echo "  - 验证 Docker 服务状态（sudo systemctl status docker）"
            ((fail_count++))
        fi
    done

    echo "🎉 批量导入完成！"
    echo "成功导入：$success_count 个密钥对"
    echo "失败：$fail_count 个密钥对"
    if [ $fail_count -gt 0 ]; then
        echo "请检查失败的密钥对并重试。"
    fi
}

delete_key_pair() {
    cd /root/soundness-layer/soundness-cli
    echo "准备删除密钥对..."

    if [ ! -f ".soundness/key_store.json" ]; then
        echo "❌ 错误：未找到 .soundness/key_store.json，没有可删除的密钥对。"
        return
    fi

    echo "当前存储的密钥对名称："
    docker-compose run --rm soundness-cli list-keys

    read -p "请输入要删除的密钥对名称（例如 andygan）： " key_name
    if [ -z "$key_name" ]; then
        echo "❌ 错误：密钥对名称不能为空。"
        return
    fi

    echo "⚠️ 警告：删除密钥对 $key_name 是不可逆的操作！"
    echo "请确保您已备份助记词，否则将无法恢复相关资金。"
    read -p "是否确认删除？(y/n)： " confirm
    if [ "$confirm" != "y" ]; then
        echo "操作取消。"
        return
    fi

    key_exists=$(docker-compose run --rm soundness-cli list-keys | grep -w "$key_name")
    if [ -z "$key_exists" ]; then
        echo "❌ 错误：密钥对 $key_name 不存在！"
        return
    fi

    echo "正在删除密钥对：$key_name..."
    if [ -f ".soundness/key_store.json" ]; then
        jq "del(.keys.\"$key_name\")" .soundness/key_store.json > .soundness/key_store.json.tmp
        mv .soundness/key_store.json.tmp .soundness/key_store.json
        echo "✅ 密钥对 $key_name 删除成功！"
    else
        echo "❌ 错误：.soundness/key_store.json 不存在！"
    fi
}

show_menu() {
    echo "=== Soundness CLI 一键脚本 ==="
    echo "请选择操作："
    echo "1. 安装/更新 Soundness CLI（通过 soundnessup 和 Docker）"
    echo "2. 生成新的密钥对"
    echo "3. 导入密钥对"
    echo "4. 列出密钥对"
    echo "5. 验证并发送证明"
    echo "6. 批量导入密钥对"
    echo "7. 删除密钥对"
    echo "8. 退出"
    read -p "请输入选项 (1-8)： " choice
}

main() {
    check_requirements
    # 确保 PATH 包含 soundnessup 的路径
    export PATH=$PATH:/usr/local/bin:/root/.local/bin:/root/.soundness/bin
    source /root/.bashrc
    while true; do
        show_menu
        case $choice in
            1)
                install_docker_cli
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
                echo "退出脚本。"
                exit 0
                ;;
            *)
                echo "无效选项，请输入 1-8。"
                ;;
        esac
        echo ""
        read -p "按 Enter 键返回菜单..."
    done
}

main
