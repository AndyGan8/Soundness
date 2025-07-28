#!/bin/bash
clear

# Soundness CLI 一键脚本
# 支持选项：1. 安装 Docker CLI, 2. 生成密钥对, 3. 导入密钥对, 4. 列出密钥对

# 设置错误处理
set -e

# 检查是否安装了必要的工具
check_requirements() {
    if ! command -v curl &> /dev/null; then
        echo "错误：需要安装 curl。请先安装 curl。"
        exit 1
    fi
    if ! command -v docker &> /dev/null; then
        echo "警告：Docker 未安装。选择 Docker 安装选项时将自动安装。"
    else
        # 检查 Docker 服务是否运行
        if ! systemctl is-active --quiet docker; then
            echo "错误：Docker 服务未运行。尝试启动..."
            sudo systemctl start docker
            if [ $? -ne 0 ]; then
                echo "错误：无法启动 Docker 服务，请检查系统配置。"
                exit 1
            fi
        fi
    fi
}

# 安装 Soundness CLI 使用 Docker
install_docker_cli() {
    echo "正在安装 Soundness CLI（通过 Docker）..."

    # 检查并安装 Docker（如果未安装）
    if ! command -v docker &> /dev/null; then
        echo "安装 Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        # 启动 Docker 服务
        sudo systemctl start docker
        sudo systemctl enable docker
        echo "Docker 安装完成。"
    fi

    # 检查并安装 docker-compose（如果未安装）
    if ! command -v docker-compose &> /dev/null; then
        echo "安装 docker-compose..."
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        echo "docker-compose 安装完成。"
    fi

    # 检查并下载 docker-compose.yml 和 Dockerfile
    echo "检查 docker-compose.yml 和 Dockerfile..."
    if [ ! -f "docker-compose.yml" ]; then
        echo "未找到 docker-compose.yml，自动下载..."
        curl -O https://raw.githubusercontent.com/SoundnessLabs/soundness-layer/main/soundness-cli/docker-compose.yml
        if [ $? -ne 0 ]; then
            echo "错误：无法下载 docker-compose.yml 文件，请检查网络连接或仓库地址。"
            exit 1
        fi
    fi
    if [ ! -f "Dockerfile" ]; then
        echo "未找到 Dockerfile，自动下载..."
        curl -O https://raw.githubusercontent.com/SoundnessLabs/soundness-layer/main/soundness-cli/Dockerfile
        if [ $? -ne 0 ]; then
            echo "错误：无法下载 Dockerfile 文件，请检查网络连接或仓库地址。"
            exit 1
        fi
    fi

    # 拉取并构建 Soundness CLI Docker 镜像
    echo "构建 Soundness CLI Docker 镜像..."
    docker-compose build
    echo "Soundness CLI Docker 镜像构建完成。"
}

# 生成新的密钥对
generate_key_pair() {
    read -p "请输入密钥对名称（例如 my-key）： " key_name
    if [ -z "$key_name" ]; then
        echo "错误：密钥对名称不能为空。"
        exit 1
    fi
    echo "正在生成新的密钥对：$key_name..."
    # 确保 key_store.json 存在
    if [ ! -f "key_store.json" ]; then
        echo "未找到 key_store.json，创建空文件..."
        touch key_store.json
        chmod 600 key_store.json
    fi
    docker-compose run --rm soundness-cli generate-key --name "$key_name"
}

# 导入密钥对
import_key_pair() {
    read -p "请输入密钥对名称： " key_name
    read -p "请输入助记词（mnemonic）： " mnemonic
    if [ -z "$key_name" ] || [ -z "$mnemonic" ]; then
        echo "错误：密钥对名称和助记词不能为空。"
        exit 1
    fi
    echo "正在导入密钥对：$key_name..."
    # 确保 key_store.json 存在
    if [ ! -f "key_store.json" ]; then
        echo "未找到 key_store.json，创建空文件..."
        touch key_store.json
        chmod 600 key_store.json
    fi
    docker-compose run --rm soundness-cli import-key --name "$key_name" --mnemonic "$mnemonic"
}

# 列出密钥对
list_key_pairs() {
    echo "列出所有存储的密钥对..."
    docker-compose run --rm soundness-cli list-keys
}

# 显示菜单并获取用户选择
show_menu() {
    echo "=== Soundness CLI 一键脚本 ==="
    echo "请选择操作："
    echo "1. 安装 Soundness CLI（通过 Docker）"
    echo "2. 生成新的密钥对"
    echo "3. 导入密钥对"
    echo "4. 列出密钥对"
    echo "5. 退出"
    read -p "请输入选项 (1-5)： " choice
}

# 主逻辑
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
                echo "退出脚本。"
                exit 0
                ;;
            *)
                echo "无效选项，请输入 1-5。"
                ;;
        esac
        echo ""
        read -p "按 Enter 键返回菜单..."
    done
}

# 运行主逻辑
main
