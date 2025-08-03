#!/bin/bash
clear

# Soundness CLI 一键脚本
# 支持选项：
# 1. 安装 Docker CLI
# 2. 生成密钥对
# 3. 导入密钥对
# 4. 列出密钥对
# 5. 验证并发送证明（优化：自动重试、文件验证）
# 6. 批量导入密钥对
# 7. 删除密钥对
# 8. 退出

set -e

check_requirements() {
    if ! command -v curl >/dev/null 2>&1; then
        echo "错误：需要安装 curl。请先安装 curl。"
        exit 1
    fi
    if ! command -v docker >/dev/null 2>&1; then
        echo "警告：Docker 未安装。选择 Docker 安装选项时将自动安装。"
    else
        if ! systemctl is-active --quiet docker; then
            echo "错误：Docker 服务未运行。尝试启动..."
            sudo systemctl start docker || {
                echo "错误：无法启动 Docker 服务，请检查系统配置。"
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
    echo "正在安装 Soundness CLI（通过 Docker）..."

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

    if [ ! -d "soundness-layer" ]; then
        echo "未找到 Soundness CLI 源代码，克隆仓库..."
        git clone https://github.com/SoundnessLabs/soundness-layer.git || {
            echo "错误：无法克隆 Soundness CLI 仓库，请检查网络连接或仓库地址。"
            exit 1
        }
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

    echo "检查并修复 docker-compose.yml..."
    cp docker-compose.yml docker-compose.yml.bak 2>/dev/null || echo "无现有 docker-compose.yml"

    # 创建临时标准文件
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

    # 如果现有文件存在，检查 version 和 user
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
        echo "当前 docker-compose.yml 内容："
        cat -A docker-compose.yml 2>/dev/null || echo "docker-compose.yml 不存在"
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
    read -p "请输入密钥对名称（例如 my-key）： " key_name
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
}

import_key_pair() {
    cd /root/soundness-layer/soundness-cli
    echo "当前存储的密钥对名称："
    if [ -f ".soundness/key_store.json" ]; then
        docker-compose run --rm soundness-cli list-keys
    else
        echo "未找到 .soundness/key_store.json，可能是首次导入。"
    fi
    read -p "请输入密钥对名称（或输入新名称以重新导入）： " key_name
    read -p "请输入助记词（mnemonic）： " mnemonic
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
        echo "❌ 错误：未找到 .soundness/key_store.json，请先生成或导入密钥对。"
        read -p "是否继续？(y/n)： " continue_choice
        if [ "$continue_choice" != "y" ]; then
            echo "操作取消。"
            return
        fi
    fi

    # 提示用户输入完整命令
    echo "请输入完整的 soundness-cli send 命令，例如："
    echo "soundness-cli send --proof-file=\"your-proof-id\" --game=\"8queens\" --key-name=\"my-key\" --proving-system=\"ligetron\" --payload='{\"program\": \"/path/to/wasm\", ...}'"
    read -r -p "命令： " full_command

    # 验证命令是否为空
    if [ -z "$full_command" ]; then
        echo "❌ 错误：命令不能为空。"
        return
    fi

    # 解析命令参数
    proof_file=$(echo "$full_command" | grep -oP '(?<=--proof-file=)(("[^"]*")|[^\s]+)' | tr -d '"')
    game=$(echo "$full_command" | grep -oP '(?<=--game=)(("[^"]*")|[^\s]+)' | tr -d '"')
    key_name=$(echo "$full_command" | grep -oP '(?<=--key-name=)(("[^"]*")|[^\s]+)' | tr -d '"')
    proving_system=$(echo "$full_command" | grep -oP '(?<=--proving-system=)(("[^"]*")|[^\s]+)' | tr -d '"')
    payload=$(echo "$full_command" | grep -oP "(?<=--payload=)('[^']*'|[^\s]+)" | sed "s/^'//;s/'$//")

    # 验证是否解析到所有必要参数
    if [ -z "$proof_file" ] || [ -z "$game" ] || [ -z "$key_name" ] || [ -z "$proving_system" ] || [ -z "$payload" ]; then
        echo "❌ 错误：无法解析完整的命令参数，请检查输入格式。"
        echo "必要参数：--proof-file, --game, --key-name, --proving-system, --payload"
        echo "您输入的命令：$full_command"
        return
    fi

    # 验证 payload 的 JSON 格式
    echo "$payload" | jq . >/dev/null 2>&1 || {
        echo "❌ 错误：payload JSON 格式无效，请检查输入。"
        echo "您输入的 payload：$payload"
        return
    }

    # 验证 WASM 文件和 shader-path 是否存在
    wasm_path=$(echo "$payload" | jq -r '.program')
    shader_path=$(echo "$payload" | jq -r '.["shader-path"]')
    if [ -n "$wasm_path" ] && [ "$wasm_path" != "null" ] && [ ! -f "$wasm_path" ]; then
        echo "❌ 错误：WASM 文件 $wasm_path 不存在！"
        echo "建议：确认文件路径是否正确，或检查 /root/ligero_internal 目录是否正确映射。"
        return
    fi
    if [ -n "$shader_path" ] && [ "$shader_path" != "null" ] && [ ! -d "$shader_path" ]; then
        echo "❌ 错误：shader 目录 $shader_path 不存在！"
        echo "建议：确认目录路径是否正确，或检查 /root/ligero_internal 目录是否正确映射。"
        return
    fi

    # 验证 proof-file 是否有效（尝试访问 Walrus）
    if ! curl -s -I "https://walruscan.io/blob/$proof_file" >/dev/null 2>&1; then
        echo "⚠️ 警告：无法访问 proof-file $proof_file，可能无效或 Walrus 服务不可用。"
        read -p "是否继续？(y/n)： " continue_proof
        if [ "$continue_proof" != "y" ]; then
            echo "操作取消。"
            return
        fi
    fi

    # 验证 key-name 是否存在
    if [ -f ".soundness/key_store.json" ]; then
        key_exists=$(docker-compose run --rm soundness-cli list-keys | grep -w "$key_name")
        if [ -z "$key_exists" ]; then
            echo "❌ 错误：密钥对 $key_name 不存在！"
            echo "建议：使用选项 3 或 6 导入密钥对，或检查 key-name 是否正确。"
            return
        fi
    fi

    # 确保 .soundness 目录存在
    if [ ! -d ".soundness" ]; then
        echo "创建 .soundness 目录..."
        mkdir .soundness
        chmod 777 .soundness
    fi

    # 执行 send 命令，添加重试机制（最多 3 次）
    max_retries=3
    retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        echo "正在发送证明（尝试 $((retry_count + 1))/$max_retries）：proof-file=$proof_file, game=$game, key-name=$key_name, proving-system=$proving_system..."
        output=$(docker-compose run --rm soundness-cli send \
            --proof-file="$proof_file" \
            --game="$game" \
            --key-name="$key_name" \
            --proving-system="$proving_system" \
            --payload="$payload" 2>&1)
        exit_code=$?

        # 检查执行结果
        if [ $exit_code -eq 0 ]; then
            echo "✅ 证明发送成功！"
            echo "服务器响应："
            echo "$output"
            
            # 解析服务器响应，检查 sui_status
            sui_status=$(echo "$output" | grep -oP '(?<="sui_status":")[^"]*')
            if [ "$sui_status" = "error" ]; then
                echo "⚠️ 警告：证明验证通过，但 Sui 网络处理失败（尝试 $((retry_count + 1))/$max_retries）。"
                echo "可能的原因："
                echo "  - Sui 网络连接问题或节点同步失败"
                echo "  - 账户余额不足以支付交易费用"
                echo "  - 提交的参数与 Sui 网络要求不匹配"
                echo "建议："
                echo "  - 检查 Sui 网络状态（可访问 https://suiscan.xyz/testnet）"
                echo "  - 确认账户余额是否足够（使用 sui client balance --address <your_address>）"
                echo "  - 验证 WASM 文件 ($wasm_path) 和 args 参数是否正确"
                echo "  - 联系 Soundness CLI 支持团队，提供以下信息："
                echo "    - Proof-file: $proof_file"
                echo "    - Game: $game"
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
                return
            fi
        else
            echo "❌ 错误：发送证明失败！"
            echo "错误详情："
            echo "$output"
            echo "可能的原因："
            echo "  - 无效的 proof-file ($proof_file)"
            echo "  - 无效的 key-name ($key_name)"
            echo "  - WASM 文件 ($wasm_path) 或 shader 目录 ($shader_path) 无效"
            echo "  - Docker 容器配置错误"
            echo "  - 网络连接问题或服务器不可用"
            echo "建议："
            echo "  - 检查 proof-file 是否有效（访问 https://walruscan.io/blob/$proof_file）"
            echo "  - 确认 key-name 是否在 .soundness/key_store.json 中（使用选项 4）"
            echo "  - 验证 WASM 文件和 shader 目录是否存在"
            echo "  - 检查网络连接（ping testnet.soundness.xyz）"
            echo "  - 确保 Docker 服务正常运行（sudo systemctl status docker）"
            echo "您输入的命令：$full_command"
            return
        fi
    done
}

batch_import_keys() {
    cd /root/soundness-layer/soundness-cli
    echo "准备批量导入密钥对..."

    # 显示当前密钥对（如果存在）
    if [ -f ".soundness/key_store.json" ]; then
        echo "当前存储的密钥对名称："
        docker-compose run --rm soundness-cli list-keys
    else
        echo "未找到 .soundness/key_store.json，将创建新的密钥存储。"
    fi

    # 提示用户输入包含助记词的文件或手动输入
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
        if [ ! -f "$file_path" ]; then
            echo "❌ 错误：文件 $file_path 不存在！"
            return
        fi
        keys_input=$(cat "$file_path")
    else
        echo "❌ 错误：无效的输入方式，请选择 1 或 2。"
        return
    fi

    # 确保 .soundness 目录存在
    if [ ! -d ".soundness" ]; then
        echo "创建 .soundness 目录..."
        mkdir .soundness
        chmod 777 .soundness
    fi

    # 处理每一行输入
    success_count=0
    fail_count=0
    echo "$keys_input" | while IFS=: read -r key_name mnemonic; do
        # 跳过空行
        if [ -z "$key_name" ] || [ -z "$mnemonic" ]; then
            echo "⚠️ 警告：跳过无效行（缺少 key_name 或 mnemonic）：$key_name:$mnemonic"
            ((fail_count++))
            continue
        fi

        # 清理输入，去除前后空格
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
            echo "  - 助记词格式无效"
            echo "  - 密钥对名称已存在"
            echo "  - Docker 容器配置错误"
            echo "建议："
            echo "  - 检查助记词是否符合 BIP39 标准"
            echo "  - 确保 key_name 未被占用"
            echo "  - 验证 Docker 服务状态（sudo systemctl status docker）"
            ((fail_count++))
        fi
    done

    # 总结导入结果
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

    # 检查是否存在密钥对
    if [ ! -f ".soundness/key_store.json" ]; then
        echo "❌ 错误：未找到 .soundness/key_store.json，没有可删除的密钥对。"
        return
    fi

    # 显示当前密钥对
    echo "当前存储的密钥对名称："
    docker-compose run --rm soundness-cli list-keys

    # 提示用户输入要删除的密钥对名称
    read -p "请输入要删除的密钥对名称： " key_name
    if [ -z "$key_name" ]; then
        echo "❌ 错误：密钥对名称不能为空。"
        return
    fi

    # 确认删除操作
    echo "⚠️ 警告：删除密钥对 $key_name 是不可逆的操作！"
    echo "请确保您已备份助记词，否则将无法恢复相关资金。"
    read -p "是否确认删除？(y/n)： " confirm
    if [ "$confirm" != "y" ]; then
        echo "操作取消。"
        return
    fi

    # 检查密钥对是否存在
    key_exists=$(docker-compose run --rm soundness-cli list-keys | grep -w "$key_name")
    if [ -z "$key_exists" ]; then
        echo "❌ 错误：密钥对 $key_name 不存在！"
        return
    fi

    # 执行删除操作（假设 soundness-cli 有 delete-key 命令）
    echo "正在删除密钥对：$key_name..."
    output=$(docker-compose run --rm soundness-cli delete-key --name "$key_name" 2>&1)
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "✅ 密钥对 $key_name 删除成功！"
    else
        echo "❌ 错误：删除密钥对 $key_name 失败！"
        echo "错误详情："
        echo "$output"
        echo "可能的原因："
        echo "  - soundness-cli 不支持 delete-key 命令"
        echo "  - 密钥对名称无效"
        echo "  - Docker 容器配置错误"
        echo "建议："
        echo "  - 检查 soundness-cli 是否支持 delete-key 命令"
        echo "  - 确认 key_name 是否正确"
        echo "  - 验证 Docker 服务状态（sudo systemctl status docker）"
        echo "  - 手动编辑 .soundness/key_store.json 删除密钥对（需谨慎）"
    fi
}

show_menu() {
    echo "=== Soundness CLI 一键脚本 ==="
    echo "请选择操作："
    echo "1. 安装 Soundness CLI (通过 Docker)"
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
