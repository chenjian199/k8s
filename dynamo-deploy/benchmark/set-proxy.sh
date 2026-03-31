#!/bin/bash
# Set proxy
echo 'PS1="\[\e[34m\]\u@\h\[\e[0m\]:\[\e[32m\]\w\[\e[0m\]\\$ "' >> ~/.bashrc
echo 'export http_proxy=http://127.0.0.1:7890' >> ~/.bashrc
echo 'export https_proxy=http://127.0.0.1:7890' >> ~/.bashrc
echo 'export ALL_PROXY=socks5h://127.0.0.1:7891' >> ~/.bashrc
echo 'export no_proxy="127.0.0.1,::1,localhost,worker06,worker14,10.0.0.0/8,192.168.0.0/16,*.svc,*.cluster.local"' >> ~/.bashrc
source ~/.bashrc