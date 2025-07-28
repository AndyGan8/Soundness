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
        if ! systemctl is-active --quiet docker; then
            echo "错误：Docker 服务未运行。尝试启动..."
            sudo systemctl start docker
            if [ $? -ne 0 ]; then
                echo "错误：无法启动 Docker 服务，请检查系统配置。"
                exit 1
            fi
        fi
    fi
    if ! command -v git &> /dev/null; then
        echo "安装 git..."
        sudo apt-get update && sudo apt-get install -y git
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

    # 检查并克隆 Soundness CLI 源代码
    if [ ! -d "soundness-layer" ]; then
        echo "未找到 Soundness CLI 源代码，克隆仓库..."
        git clone https://github.com/SoundnessLabs/soundness-layer.git
        if [ $? -ne 0 ]; then
            echo "错误：无法克隆 Soundness CLI 仓库，请检查网络连接或仓库地址。"
            exit 1
        fi
    fi
    cd soundness-layer/soundness-cli

    # 检查必要文件
    if [ ! -f "docker-compose.yml" ]; then
        echo "错误：缺少 docker-compose.yml 文件，尝试下载..."
        curl -O https://raw.githubusercontent.com/SoundnessLabs/soundness-layer/main/soundness-cli/docker-compose.yml
        if [ $? -ne 0 ]; then
            echo "错误：无法下载 docker-compose.yml 文件。"
            exit 1
        fi
    fi
    if [ ! -f "Dockerfile" ]; then
        echo "错误：缺少 Dockerfile 文件，尝试下载..."
        curl -O https://raw.githubusercontent.com/SoundnessLabs/soundness-layer/main/soundness-cli/Dockerfile
        if [ $? -ne 0 ]; then
            echo "错误：无法下载 Dockerfile 文件。"
            exit 1
        fi
    fi
    if [ ! -f "Cargo.toml" ]; then
        echo "错误：缺少 Cargo.toml 文件，请确认仓库完整性。"
        exit 1
    fi

    # 清理大文件
    if [ -d "target" ]; then
        echo "清理 target 目录以减少构建上下文..."
        rm -rf target
    fi

    # 自动修复 docker-compose.yml 的重复键并添加 user: root
    if [ -f "docker-compose.yml" ]; then
        echo "检查并修复 docker-compose.yml..."
        # 检查是否存在重复的 soundness-cli 键
        if grep -A1 "services:" docker-compose.yml | grep -q "soundness-cli:" && grep -A2 "services:" docker-compose.yml | grep -q "soundness-cli:"; then
            echo "检测到重复的 soundness-cli 键，修复中..."
            cp docker-compose.yml docker-compose.yml.bak
            # 保留第一个 soundness-cli，移除后续重复
            awk '/services:/{print; next} /soundness-cli:/{if (!seen) {print; seen=1} else {next}} {print}' docker-compose.yml.bak > docker-compose.yml
        fi
        # 添加 user: root（如果尚未存在）
        if ! grep -q "user: root" docker-compose.yml; then
            echo "添加 user: root 到 docker-compose.yml..."
            cp docker-compose.yml docker-compose.yml.bak
            sed -i '/^  soundness-cli:/a \    user: root' docker-compose.yml
            echo "docker-compose.yml 已更新，添加 user: root。"
        else
            echo "docker-compose.yml 已包含 user: root，无需修改。"
        fi
        # 验证 YAML 格式
        docker-compose -f docker-compose.yml config >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "错误：docker-compose.yml 格式无效，恢复备份..."
            mv docker-compose.yml.bak docker-compose.yml
            exit 1
        fi
    fi

    # 确保目录权限
    chmod -R 777 .
    if [ ! -d ".soundness" ]; then
        echo "创建 .soundness 目录..."
        mkdir .soundness
        chmod 777 .soundness
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
    chmod -R 777 .
    if [ ! -d ".soundness" ]; then
        echo "创建 .soundness 目录..."
        mkdir .soundness
        chmod 777 .soundness
    fi
    docker-compose run --rm soundness-cli generate-key --name "$key_name"
}

# 导入密钥对
import_key_pair() {
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
