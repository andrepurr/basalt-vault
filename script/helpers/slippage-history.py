#!/usr/bin/env python3
"""Slippage history for Basalt Vault zapin/zapout operations.

Fetches on-chain events, correlates token transfers, calculates slippage.
Uses Dolomite oracle prices (GMX-derived, slightly conservative).

Usage: python3 slippage-history.py <zapin_addr> <zapout_addr> <deployer> \
           <gm> <usdc> <wbtc> <dolomite> <rpc> [--from-block N]
"""
import json, os, subprocess, sys, time

# Parse args
zapin, zapout, deployer, gm, usdc, wbtc, dolomite, rpc = sys.argv[1:9]
from_block = 456900000  # Default: ~Apr 27 2026 on Arbitrum
for i, a in enumerate(sys.argv):
    if a == '--from-block' and i + 1 < len(sys.argv):
        from_block = int(sys.argv[i + 1])

MC3 = '0xcA11bde05977b3631167028862bE2a173976CA11'
TRANSFER_TOPIC = '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef'
ZAPIN_TOPIC = '0x1a118596a670c543b6e28ae877c63c4990b37fb0cd4eeada3340bc630d8a78b6'
ZAPOUT_TOPIC = '0x5c5fb7e9e75e7505567076327e51998da6319b1ac5f33a70d95a7059cdb52e92'

deployer_padded = '0x' + deployer[2:].lower().zfill(64)
env_np = {k: v for k, v in os.environ.items() if 'proxy' not in k.lower()}

# ANSI
Y = '\033[33m'; C = '\033[36m'; G = '\033[32m'; R = '\033[31m'
B = '\033[1m'; D = '\033[2m'; N = '\033[0m'


def cast_logs(address, topics, from_blk, to_blk='latest'):
    """Fetch logs via cast logs --json."""
    cmd = ['cast', 'logs', '--rpc-url', rpc, '--from-block', str(from_blk)]
    if to_blk != 'latest':
        cmd += ['--to-block', str(to_blk)]
    cmd += ['--address', address]
    cmd += topics
    cmd += ['--json']
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=30, env=env_np)
    if not r.stdout.strip():
        # Retry with proxy
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if r.stdout.strip():
        return json.loads(r.stdout)
    return []


def cast_call_at_block(to, sig, block_num, *args):
    """Call contract at historical block with optional args."""
    cmd = ['cast', 'call', '--rpc-url', rpc, '--block', str(block_num), to, sig] + list(args)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=15, env=env_np)
    if not r.stdout.strip():
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    v = r.stdout.strip().split()[0] if r.stdout.strip() else '0'
    try:
        return int(v, 16) if v.startswith('0x') else int(v)
    except (ValueError, TypeError):
        return 0


def get_block_timestamp(block_num):
    """Get block timestamp."""
    cmd = ['cast', 'block', '--rpc-url', rpc, str(block_num), '--json']
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=15, env=env_np)
    if not r.stdout.strip():
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    if r.stdout.strip():
        d = json.loads(r.stdout)
        ts = d.get('timestamp', '0x0')
        return int(ts, 16) if isinstance(ts, str) else int(ts)
    return 0


print(f'\n  {B}{Y}◆ SLIPPAGE HISTORY{N}')
print(f'  {D}Scanning from block {from_block}...{N}')

# ═══════════════════════════════════════════════
#  FETCH EVENTS
# ═══════════════════════════════════════════════

zapin_events = cast_logs(zapin, [ZAPIN_TOPIC, deployer_padded], from_block)
zapout_events = cast_logs(zapout, [ZAPOUT_TOPIC, deployer_padded], from_block)

# For each ZapIn, find corresponding GM Transfer to deployer
gm_transfers = cast_logs(gm, [TRANSFER_TOPIC, '', deployer_padded], from_block)

print(f'  {D}Found: {len(zapin_events)} zapin, {len(zapout_events)} zapout, {len(gm_transfers)} GM receives{N}')

# ═══════════════════════════════════════════════
#  CORRELATE ZAPIN → GM RECEIVE
# ═══════════════════════════════════════════════

rows = []

for zi in zapin_events:
    zi_block = int(zi['blockNumber'], 16)
    zi_tx = zi['transactionHash']
    data = zi['data'].replace('0x', '')
    usdc_in_e6 = int(data[:64], 16)
    is_long = bool(int(data[64:128], 16))

    # Find GM Transfer within next 200 blocks (GMX keeper ~2-90s)
    gm_received_e18 = 0
    gm_block = zi_block
    gm_tx = '?'
    for gt in gm_transfers:
        gt_block = int(gt['blockNumber'], 16)
        if zi_block < gt_block <= zi_block + 800:  # ~200s window
            gm_received_e18 = int(gt['data'], 16)
            gm_block = gt_block
            gm_tx = gt['transactionHash']
            break

    # Get prices at GM receive block (or zapin block if no GM found)
    price_block = gm_block if gm_received_e18 > 0 else zi_block
    gm_price_raw = cast_call_at_block(dolomite, 'getMarketPrice(uint256)(uint256)', price_block, '32')
    gm_price_usd = gm_price_raw / 1e18 if gm_price_raw > 0 else 0

    # Slippage calculation
    usdc_in = usdc_in_e6 / 1e6
    gm_out = gm_received_e18 / 1e18
    gm_value_usd = gm_out * gm_price_usd
    expected_gm = usdc_in / gm_price_usd if gm_price_usd > 0 else 0
    slippage_pct = ((gm_out - expected_gm) / expected_gm * 100) if expected_gm > 0 else 0

    ts = get_block_timestamp(zi_block)
    date_str = time.strftime('%m-%d %H:%M', time.gmtime(ts)) if ts > 0 else '?'

    rows.append({
        'type': 'ZapIn',
        'date': date_str,
        'input': f'{usdc_in:.2f} USDC',
        'output': f'{gm_out:.6f} GM',
        'value_out': gm_value_usd,
        'value_in': usdc_in,
        'slippage': slippage_pct,
        'route': 'long' if is_long else 'short',
        'tx_in': zi_tx,
        'tx_out': gm_tx,
        'block': zi_block,
        'gm_price': gm_price_usd,
        'wait_blocks': gm_block - zi_block if gm_received_e18 > 0 else -1,
    })

for zo in zapout_events:
    zo_block = int(zo['blockNumber'], 16)
    zo_tx = zo['transactionHash']
    data = zo['data'].replace('0x', '')
    wbtc_in_e8 = int(data[:64], 16)
    usdc_out_e6 = int(data[64:128], 16)

    # Get WBTC price at block
    wbtc_price_raw = cast_call_at_block(dolomite, 'getMarketPrice(uint256)(uint256)', zo_block, '4')
    wbtc_price_usd = wbtc_price_raw / 1e28 if wbtc_price_raw > 0 else 0

    wbtc_in = wbtc_in_e8 / 1e8
    usdc_out = usdc_out_e6 / 1e6
    expected_usdc = wbtc_in * wbtc_price_usd
    slippage_pct = ((usdc_out - expected_usdc) / expected_usdc * 100) if expected_usdc > 0 else 0

    ts = get_block_timestamp(zo_block)
    date_str = time.strftime('%m-%d %H:%M', time.gmtime(ts)) if ts > 0 else '?'

    rows.append({
        'type': 'ZapOut',
        'date': date_str,
        'input': f'{wbtc_in:.8f} WBTC',
        'output': f'{usdc_out:.2f} USDC',
        'value_in': wbtc_in * wbtc_price_usd,
        'value_out': usdc_out,
        'slippage': slippage_pct,
        'route': 'uni-v3',
        'tx_in': zo_tx,
        'tx_out': zo_tx,
        'block': zo_block,
        'gm_price': 0,
        'wait_blocks': 0,
    })

# Sort by block
rows.sort(key=lambda r: r['block'])

if not rows:
    print(f'\n  {D}No zapin/zapout operations found{N}\n')
    sys.exit(0)

# ═══════════════════════════════════════════════
#  DISPLAY TABLE
# ═══════════════════════════════════════════════

print(f'\n  {Y}{B}{"#":>3}  {"Date":10} {"Op":6} {"Input":>18} {"Output":>18} {"$In":>8} {"$Out":>8} {"Slip":>7} {"Route"}{N}')
print(f'  {D}{"─" * 95}{N}')

total_in = 0
total_out = 0
total_slip_weighted = 0

for i, r in enumerate(rows, 1):
    slip = r['slippage']
    sc = G if slip >= -0.5 else (Y if slip >= -2 else R)
    print(f'  {C}{i:>3}{N}  {r["date"]:10} {B}{r["type"]:6}{N} {r["input"]:>18} {r["output"]:>18}'
          f' {D}${r["value_in"]:>7.2f}{N} {D}${r["value_out"]:>7.2f}{N}'
          f' {sc}{slip:>+6.2f}%{N} {D}{r["route"]}{N}')

    if r['wait_blocks'] > 0:
        print(f'       {D}GMX keeper: +{r["wait_blocks"]} blocks  GM price: ${r["gm_price"]:.6f}{N}')

    total_in += r['value_in']
    total_out += r['value_out']
    if r['value_in'] > 0:
        total_slip_weighted += r['slippage'] * r['value_in']

print(f'  {D}{"─" * 95}{N}')
avg_slip = total_slip_weighted / total_in if total_in > 0 else 0
net = total_out - total_in
print(f'  {B}Total:{N}  in=${total_in:.2f}  out=${total_out:.2f}  net={R if net < 0 else G}${net:+.2f}{N}'
      f'  avg slip={R if avg_slip < -1 else Y}{avg_slip:+.2f}%{N}')
print()
