#!/usr/bin/env bash
set -euo pipefail
set -x

export ANSIBLE_HOST_KEY_CHECKING=${ANSIBLE_HOST_KEY_CHECKING:-False}

mkdir -p /tmp/ansible
printf '%s\n' "$SSH_PRIVATE_KEY" > /tmp/ansible/ssh_key
chmod 600 /tmp/ansible/ssh_key

# get instance IP via terraform output using jq or grep fallback
IP=""
if command -v jq >/dev/null 2>&1; then
  IP=$(terraform -chdir=terraform output -json 2>/dev/null | jq -r '.web_instance_public_ip.value // .web_instance_public_ip // ""' | grep -Eo '^[0-9]+(\.[0-9]+){3}$' || true)
fi
if [ -z "$IP" ]; then
  IP=$(terraform -chdir=terraform output -raw web_instance_public_ip 2>/dev/null || true)
  IP=$(printf '%s' "$IP" | grep -Eo '^[0-9]+(\.[0-9]+){3}$' || true)
fi

if [ -z "$IP" ]; then
  echo "Error: terraform output 'web_instance_public_ip' is empty. Ensure Terraform applied and output exists."
  terraform -chdir=terraform output || true
  exit 1
fi
if ! printf '%s' "$IP" | grep -Eo '^[0-9]+(\.[0-9]+){3}$' >/dev/null; then
  MASKED_IP=$(printf '%s' "$IP" | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/\1.xxx/')
  echo "Error: terraform output did not return a valid IPv4 address. Masked value: '$MASKED_IP'"
  terraform -chdir=terraform output || true
  exit 1
fi

printf "[webservers]\nec2 ansible_host=%s ansible_user=ec2-user ansible_private_key_file=/tmp/ansible/ssh_key\n" "$IP" > /tmp/ansible/inventory.ini
ansible-playbook -i /tmp/ansible/inventory.ini ansible/playbook.yml -vvv
