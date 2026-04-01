#!/bin/bash
# This script is used to setup the environment for the nfs deployment.
# 服务器节点安装nfs-kernel-server
apt-get update
apt-get install -y nfs-kernel-server

mkdir -p /nfs
chmod 777 /nfs
mount --bind /mnt/share /nfs

echo "/mnt/share /nfs none bind 0 0" >> /etc/fstab
echo "/mnt/share *(rw,sync,no_subtree_check,no_root_squash)" >> /etc/exports

exportfs -arv
systemctl status nfs-kernel-server
systemctl restart nfs-kernel-server
showmount -e localhost

mount | grep nfs

# 客户端节点安装nfs-common
apt-get update
apt-get install -y nfs-common

mkdir -p /nfs

mount -t nfs 192.168.4.6:/nfs /nfs
echo "192.168.4.6:/nfs /nfs nfs defaults 0 0" >> /etc/fstab

df -h | grep nfs