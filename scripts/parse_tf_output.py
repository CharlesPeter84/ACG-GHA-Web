#!/usr/bin/env python3
import sys
import json

try:
    data = json.load(sys.stdin)
    v = data.get('web_instance_public_ip', {})
    if isinstance(v, dict):
        print(v.get('value', ''), end='')
    else:
        print(v or '', end='')
except Exception:
    print('', end='')
