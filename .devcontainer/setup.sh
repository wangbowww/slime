#!/bin/bash
echo "开始初始化环境..."
echo "配置 Bash 颜色..."
# 1. 配置 Bash 颜色（防止重复追加，先检查）
if ! grep -q "ls --color=auto" /root/.bashrc; then
    cat <<EOF >> /root/.bashrc
if [ -x /usr/bin/dircolors ]; then
    alias ls="ls --color=auto"
    alias grep="grep --color=auto"
fi
PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\\$ "
EOF
fi

echo "配置 Git..."
git config --global user.email "1562659113@qq.com"
git config --global user.name "wangbowww"
git config --global --add safe.directory /root/slime

echo "安装依赖..."
cd /root/slime
pip install -e .

echo "正在下载数据集 dapo-math-17k..."
hf download --repo-type dataset zhuzilin/dapo-math-17k \
  --local-dir /root/dapo-math-17k

echo "正在下载数据集 aime-2024..."
hf download --repo-type dataset zhuzilin/aime-2024 \
  --local-dir /root/aime-2024

echo "正在安装 debugpy..."
pip install debugpy

echo "环境初始化完成！"