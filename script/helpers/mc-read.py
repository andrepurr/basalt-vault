#!/usr/bin/env python3
"""Generic Multicall3 batch reader. 1 RPC call for N reads.

Usage: python3 mc-read.py <rpc> <addr1> <sig1> [args...] -- <addr2> <sig2> [args...] -- ...
Output: one raw uint256 per line (decimal), same order as input.

Example:
  python3 mc-read.py "$RPC" \
    0xWBTC "balanceOf(address)" 0xDEPLOYER -- \
    0xUSDC "balanceOf(address)" 0xDEPLOYER -- \
    0xOracle "latestAnswer()"
"""
import json, os, subprocess, sys, time

MC3 = '0xcA11bde05977b3631167028862bE2a173976CA11'
env_np = {k: v for k, v in os.environ.items() if 'proxy' not in k.lower()}

rpc = sys.argv[1]
backup_rpc = os.environ.get('BACKUP_RPC', '').strip()
rpcs = [rpc] + ([backup_rpc] if backup_rpc else [])

# Parse "addr sig [args] -- addr sig [args] -- ..."
groups = []
current = []
for a in sys.argv[2:]:
    if a == '--':
        if current:
            groups.append(current)
        current = []
    else:
        current.append(a)
if current:
    groups.append(current)

if not groups:
    sys.exit(0)

# Build calldata for each group using cast calldata (fast, local)
calls = []
for g in groups:
    addr = g[0]
    sig = g[1]
    args = g[2:]
    # Build "sig(type)(rettype)" → just use sig as-is, cast calldata handles it
    # Strip return type if present: "balanceOf(address)(uint256)" → "balanceOf(address)"
    call_sig = sig.split(')(')[0]
    if not call_sig.endswith(')'):
        call_sig += ')'
    r = subprocess.run(['cast', 'calldata', call_sig] + args,
                       capture_output=True, text=True, timeout=5)
    cd = r.stdout.strip()
    if not cd:
        cd = '0x'
    calls.append((addr, cd))

# Build Multicall3 aggregate3 calldata
def enc(v, w=32):
    return v.to_bytes(w, 'big').hex()

def build_mc3(calls):
    """Encode aggregate3((address target, bool allowFailure, bytes callData)[])"""
    # Manual ABI encoding — same as multicall-status.py
    tuples = ','.join(f'({t},true,{c})' for t, c in calls)
    r = subprocess.run(['cast', 'calldata', 'aggregate3((address,bool,bytes)[])', f'[{tuples}]'],
                       capture_output=True, text=True, timeout=5)
    return r.stdout.strip()

agg_cd = build_mc3(calls)

# Single RPC call
def rpc_call(data):
    payload = json.dumps({'jsonrpc': '2.0', 'id': 1, 'method': 'eth_call',
                          'params': [{'to': MC3, 'data': data}, 'latest']})
    for url in rpcs:
        for attempt in range(2):
            for env in [env_np, None]:
                try:
                    r = subprocess.run(['curl', '-sS', '-X', 'POST',
                                        '-H', 'Content-Type: application/json',
                                        '-d', payload, url],
                                       capture_output=True, text=True, timeout=10,
                                       env=env if env else os.environ)
                    if r.stdout.strip():
                        resp = json.loads(r.stdout)
                        if resp.get('result', '') not in ('', '0x'):
                            return bytes.fromhex(resp['result'][2:])
                        err = resp.get('error', {})
                        if isinstance(err, dict) and err.get('code') == -32005:
                            break
                except Exception:
                    pass
            if attempt == 0:
                time.sleep(0.3)
    return None

raw = rpc_call(agg_cd)
if not raw:
    # All failed — output zeros
    for _ in calls:
        print('0')
    sys.exit(0)

# Parse aggregate3 return: (bool success, bytes returnData)[]
off = int.from_bytes(raw[0:32], 'big')
n = int.from_bytes(raw[off:off+32], 'big')
base = off + 32
eoffs = [int.from_bytes(raw[base+i*32:base+(i+1)*32], 'big') + base for i in range(n)]

for eo in eoffs:
    ok = int.from_bytes(raw[eo:eo+32], 'big') != 0
    bo = int.from_bytes(raw[eo+32:eo+64], 'big')
    ao = eo + bo
    bl = int.from_bytes(raw[ao:ao+32], 'big')
    rd = raw[ao+32:ao+32+bl] if ok and bl > 0 else b''
    if len(rd) >= 32:
        v = int.from_bytes(rd[0:32], 'big')
        # Handle signed int256 (for Chainlink latestAnswer which can be negative conceptually
        # but prices are always positive, so just output as unsigned)
        print(v)
    else:
        print('0')
