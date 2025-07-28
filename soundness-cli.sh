#!/bin/bash
clear

# Soundness CLI 一键脚本
# 支持选项：1. 安装 Docker CLI, 2. 生成密钥对, 3. 导入密钥对, 4. 列出密钥对

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

    if [ ! -f "docker-compose.yml" ]; then
        echo "错误：缺少 docker-compose.yml 文件，尝试下载..."
        curl -O https://raw.githubusercontent.com/SoundnessLabs/soundness-layer/main/soundness-cli/docker-compose.yml || {
            echo "错误：无法下载 docker-compose.yml 文件。"
            exit 1
        }
    fi
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

    if [ -d "target" ]; then
        echo "清理 target 目录以减少构建上下文..."
        rm -rf target
    fi

    if [ -f "docker-compose.yml" ]; then
        echo "检查并修复 docker-compose.yml..."
        cp docker-compose.yml docker-compose.yml.bak
        if ! grep -q "^version:" docker-compose.yml; then
            echo "version: '3.8'" > docker-compose.yml.tmp
            cat docker-compose.yml >> docker-compose.yml.tmp
        else
            cp docker-compose.yml docker-compose.yml.tmp
        fi
        awk '/^version:/{print; next} /^services:/{print; seen=0; next} /^[[:space:]]*soundness-cli:/{if (!seen) {print; seen=1} else {skip=1; next}} skip&&/^[[:space:]]/{next} {skip=0; print}' docker-compose.yml.tmp > docker-compose.yml
        rm -f docker-compose.yml.tmp
        if ! grep -q "user: root" docker-compose.yml; then
            echo "添加 user: root 到 docker-compose.yml..."
            cp docker-compose.yml docker-compose.yml.tmp
            sed '/^  soundness-cli:/a \    user: root' docker-compose.yml.tmp > docker-compose.yml
            rm -f docker-compose.yml.tmp
        else
            echo "docker-compose.yml 已包含 user: root，无需添加。"
        fi
        if ! error=$(docker-compose -f docker-compose.yml config 2>&1 >/dev/null); then
            echo "错误：docker-compose.yml 格式无效："
            echo "$error"
            echo "恢复备份文件..."
            mv docker-compose.yml.bak docker-compose.yml
            echo "当前 docker-compose.yml 内容："
            cat docker-compose.yml
            exit 1
        fi
        echo "docker-compose.yml 已修复并验证。"
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
    echo "列出所有存储的密钥对..."
    docker-compose run --rm soundness-cli list-keys
}

show_menu() {
    echo "=== Soundness CLI 一键脚本 ==="
    echo "请选择操作："
    echo "1. 安装 Soundness CLI（通过 Docker）"
    echo "2. 生成新的密钥对"
    echo "3. 导入密钥对"
    echo "4. 列出密钥对"
    echo
