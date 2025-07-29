#!/bin/bash
clear

# Soundness CLI 一键脚本
# 支持选项：1. 安装 Docker CLI, 2. 生成密钥对, 3. 导入密钥对, 4. 列出密钥对, 5. 验证并发送证明

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

# ... 其他函数（install_docker_cli, generate_key_pair, import_key_pair, list_key_pairs）保持不变 ...

send_proof() {
    cd /root/soundness-layer/soundness-cli
    echo "准备发送证明到 Soundness CLI..."

    # 显示当前密钥对（如果存在）
    if [ -f ".soundness/key_store.json" ]; then
        echo "当前存储的密钥对名称："
        docker-compose run --rm soundness-cli list-keys
    else
        echo "警告：未找到 .soundness/key_store.json，请先生成或导入密钥对。"
    fi

    # 提示用户输入完整命令
    echo "请输入完整的 soundness-cli send 命令，例如："
    echo "soundness-cli send --proof-file=\"your-proof-id\" --game=\"8queens\" --key-name=\"my-key\" --proving-system=\"ligetron\" --payload='{\"program\": \"/path/to/wasm\", ...}'"
    read -r -p "命令： " full_command

    # 验证命令是否为空
    if [ -z "$full_command" ]; then
        echo "错误：命令不能为空。"
        exit 1
    fi

    # 解析命令参数
    proof_file=$(echo "$full_command" | grep -oP '(?<=--proof-file=)(("[^"]*")|[^\s]+)' | tr -d '"')
    game=$(echo "$full_command" | grep -oP '(?<=--game=)(("[^"]*")|[^\s]+)' | tr -d '"')
    key_name=$(echo "$full_command" | grep -oP '(?<=--key-name=)(("[^"]*")|[^\s]+)' | tr -d '"')
    proving_system=$(echo "$full_command" | grep -oP '(?<=--proving-system=)(("[^"]*")|[^\s]+)' | tr -d '"')
    payload=$(echo "$full_command" | grep -oP "(?<=--payload=)('[^']*'|[^\s]+)" | sed "s/^'//;s/'$//")

    # 验证是否解析到所有必要参数
    if [ -z "$proof_file" ] || [ -z "$game" ] || [ -z "$proving_system" ] || [ -z "$payload" ]; then
        echo "错误：无法解析完整的命令参数，请检查输入格式。必要参数：--proof-file, --game, --proving-system, --payload"
        echo "您输入的命令：$full_command"
        exit 1
    fi

    # 验证 payload 的 JSON 格式
    echo "$payload" | jq . >/dev/null 2>&1 || {
        echo "错误：payload JSON 格式无效，请检查输入。"
        echo "您输入的 payload：$payload"
        exit 1
    }

    # 确保 .soundness 目录存在
    if [ ! -d ".soundness" ]; then
        echo "创建 .soundness 目录..."
        mkdir .soundness
        chmod 777 .soundness
    fi

    # 执行 send 命令
    echo "正在发送证明：proof-file=$proof_file, game=$game, key-name=$key_name, proving-system=$proving_system..."
    docker-compose run --rm soundness-cli send \
        --proof-file="$proof_file" \
        --game="$game" \
        --key-name="$key_name" \
        --proving-system="$proving_system" \
        --payload="$payload" || {
        echo "错误：发送证明失败，请检查输入参数或查看错误日志。"
        echo "您输入的命令：$full_command"
        exit 1
    }
    echo "证明发送成功！"
}

show_menu() {
    echo "=== Soundness CLI 一键脚本 ==="
    echo "请选择操作："
    echo "1. 安装 Soundness CLI (通过 Docker)"
    echo "2. 生成新的密钥对"
    echo "3. 导入密钥对"
    echo "4. 列出密钥对"
    echo "5. 验证并发送证明"
    echo "6. 退出"
    read -p "请输入选项 (1-6)： " choice
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
                echo "退出脚本。"
                exit 0
                ;;
            *)
                echo "无效选项，请输入 1-6。"
                ;;
        esac
        echo ""
        read -p "按 Enter 键返回菜单..."
    done
}

main
