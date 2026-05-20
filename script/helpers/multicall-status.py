#!/usr/bin/env python3
"""Vault status via Multicall3. 2 RPC calls total (~0.5s)."""
import json, os, subprocess, sys

factory, deployer, dolomite, ds, gm, usdc, wbtc, rpc = sys.argv[1:9]
MC3 = '0xcA11bde05977b3631167028862bE2a173976CA11'
CL_WBTC = '0xd0C7101eACbB49F3deCcCc166d238410D6D46d57'
CL_USDC = '0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3'

env_np = {k: v for k, v in os.environ.items() if 'proxy' not in k.lower()}

def cd(sig, *args):
    return subprocess.run(['cast', 'calldata', sig] + list(args),
                          capture_output=True, text=True).stdout.strip()

backup_rpc = os.environ.get('BACKUP_RPC', '').strip()
_rpcs = [rpc] + ([backup_rpc] if backup_rpc else [])

def rpc_call(to, data):
    import time
    payload = json.dumps({'jsonrpc':'2.0','id':1,'method':'eth_call',
                          'params':[{'to':to,'data':data},'latest']})
    for url in _rpcs:
        for attempt in range(2):
            for env in [env_np, None]:
                try:
                    r = subprocess.run(['curl','-sS','-X','POST','-H','Content-Type: application/json',
                                        '-d',payload,url], capture_output=True, text=True, timeout=10,
                                       env=env if env else os.environ)
                    if r.stdout.strip():
                        resp = json.loads(r.stdout)
                        err = resp.get('error', {})
                        if isinstance(err, dict) and err.get('code') == -32005:
                            break  # 429
                        if not resp.get('error') and resp.get('result','') not in ('','0x'):
                            return bytes.fromhex(resp['result'][2:])
                except: pass
            if attempt == 0:
                time.sleep(1)
    return None

def mc_call(calls):
    """calls = [(target, calldata_hex)] -> [bytes returnData]"""
    tuples = ','.join(f'({t},true,{c})' for t,c in calls)
    agg = cd('aggregate3((address,bool,bytes)[])', f'[{tuples}]')
    data = rpc_call(MC3, agg)
    if not data:
        print('  ⚠ RPC multicall failed (rate limit or timeout)', file=sys.stderr)
        return [b''] * len(calls)
    off = int.from_bytes(data[0:32],'big')
    n = int.from_bytes(data[off:off+32],'big')
    base = off + 32
    eoffs = [int.from_bytes(data[base+i*32:base+(i+1)*32],'big')+base for i in range(n)]
    results = []
    for eo in eoffs:
        ok = int.from_bytes(data[eo:eo+32],'big') != 0
        bo = int.from_bytes(data[eo+32:eo+64],'big')
        ao = eo + bo
        bl = int.from_bytes(data[ao:ao+32],'big')
        rd = data[ao+32:ao+32+bl] if ok else b''
        results.append(rd)
    return results

def u256(b): return int.from_bytes(b[0:32],'big') if len(b)>=32 else 0
def i256(b): return int.from_bytes(b[0:32],'big',signed=True) if len(b)>=32 else 0
def addr(b): return '0x'+b[12:32].hex() if len(b)>=32 else '0x0'

# ── Phase 1: resolve vault (1 RPC) ──
tid_r = mc_call([(factory, cd('nextTokenId()'))])[0]
tid = u256(tid_r)
if tid == 0: print("  No vault!"); sys.exit(0)

r1 = mc_call([
    (factory, cd('vaultByTokenId(uint256)', str(tid))),
])
vc = addr(r1[0])

r2 = mc_call([
    (vc, cd('basaltState()')),
])
vs = addr(r2[0])

r3 = mc_call([
    (vs, cd('dolomiteIsolationVault()')),
])
iso = addr(r3[0])

# ── Phase 2: all reads (1 RPC) ──
calls = []
labels = []
def add(t, c, l): calls.append((t,c)); labels.append(l)

for sig, l in [
    ("depositState()","dep"),("withdrawState()","wd"),("rebalanceState()","reb"),
    ("pendingDepositAmountGmE18()","pend_gm"),("pendingDepositGmPriceE18()","pend_gm_price"),
    ("pendingDepositGmCollateralSnapshotE18()","pend_gm_col"),
    ("managementFeeBps()","mgmt_fee"),("targetLtvBps()","target_ltv"),
    ("highWaterMarkProfitUsdE18()","hwm"),("managerAccruedFeeUsdE18()","mgr_fee"),
    ("totalDepositedGmE18()","total_dep_gm"),("totalDepositedUsdE18()","total_dep_usd"),
    ("totalWithdrawnUsdE18()","total_wd_usd"),
    ("lastFinalizedNavUsdE18()","last_nav"),("lastFinalizedGmCollateralE18()","last_gm_col"),
    ("lastFinalizedWbtcDebtE8()","last_wbtc_debt"),
    ("globalActionCooldownEndBlock()","cooldown"),
    ("rebalanceThresholdUpBps()","reb_up"),("rebalanceThresholdDownBps()","reb_down"),
    ("rebalanceSlippageCapBps()","reb_slip"),("unwrapLongShareBps()","unwrap_long"),
    ("keeperDeadline()","keeper_dl"),
    ("pendingDepositDeadline()","pend_dep_dl"),
    ("pendingWithdrawSharesE18()","pend_wd_shares"),
    ("pendingWithdrawGmToSellE18()","pend_wd_gm"),
    ("pendingWithdrawDeadline()","pend_wd_dl"),
    ("pendingRebalanceKind()","pend_reb_kind"),
    ("pendingRebalanceDirection()","pend_reb_dir"),
    ("pendingRebalanceLtvSnapshotBps()","pend_reb_ltv"),
    ("pendingRebalanceDeadline()","pend_reb_dl"),
]: add(vs, cd(sig), l)

for mid, l in [(32,"gm_d"),(17,"usdc_d"),(4,"wbtc_d")]:
    add(dolomite, cd("getAccountWei((address,uint256),uint256)",f"({iso},100)",str(mid)), l)

for tok, l in [(usdc,"my_usdc"),(wbtc,"my_wbtc"),(gm,"my_gm")]:
    add(tok, cd("balanceOf(address)",deployer), l)

add(MC3, cd("getEthBalance(address)",deployer), "my_eth")
add(MC3, cd("getBlockNumber()"), "blk")
add(CL_WBTC, cd("latestAnswer()"), "cl_w")
add(CL_USDC, cd("latestAnswer()"), "cl_u")
add(dolomite, cd("getMarketPrice(uint256)","32"), "gm_pd")
add(dolomite, cd("getMarketPrice(uint256)","4"), "wbtc_pd")

raw_results = mc_call(calls)

R = {}
for i, (rd, l) in enumerate(zip(raw_results, labels)):
    if l in ('gm_d','usdc_d','wbtc_d'):
        R[l] = (u256(rd[:32]) != 0, u256(rd[32:64])) if len(rd)>=64 else (True,0)
    elif l in ('cl_w','cl_u'):
        R[l] = i256(rd)
    else:
        R[l] = u256(rd)

def n(k): return R.get(k,0) if not isinstance(R.get(k),tuple) else 0
def d(k): v=R.get(k,(True,0)); return v if isinstance(v,tuple) else (True,0)

sl = ['idle','pending']
ds=n('dep'); ws=n('wd'); rs=n('reb')
gm_p=n('gm_pd')/1e18; wbtc_p=n('wbtc_pd')/1e28
cl_w=n('cl_w')/1e8; cl_u=n('cl_u')/1e8
# Live Dolomite positions (source of truth for NAV/LTV)
gs,gv=d('gm_d'); us,uv=d('usdc_d'); ws2,wv=d('wbtc_d')
live_gm = gv/1e18 if gs else 0
live_wbtc_debt = wv/1e8 if not ws2 else 0
live_wbtc_surplus = wv/1e8 if ws2 else 0
cu=live_gm*gm_p; du=live_wbtc_debt*wbtc_p
nav=cu-du; ltv=du/cu*100 if cu else 0
# Snapshot (from VaultState — stale after rebalance)
snap_nav=n('last_nav')/1e18; snap_gc=n('last_gm_col')/1e18; snap_wd8=n('last_wbtc_debt')/1e8
def f(s,v,dc): return f'{"+" if s else "-"}{v/(10**dc):.{min(dc,6)}f}'

# ── Snap mode: JSON output for before/after diffs ──
if len(sys.argv) > 9 and sys.argv[9] == '--snap':
    snap = {
        'nav': n('last_nav'), 'gm_col': gv if gs else 0, 'wbtc_debt': wv if not ws2 else 0,
        'dep_st': n('dep'), 'wd_st': n('wd'), 'reb_st': n('reb'),
        'gm_dol': gv if gs else -gv,
        'usdc_dol': uv if us else -uv,
        'wbtc_dol': wv if ws2 else -wv,
        'my_usdc': n('my_usdc'), 'my_wbtc': n('my_wbtc'), 'my_gm': n('my_gm'), 'my_eth': n('my_eth'),
        'gm_price': n('gm_pd'), 'wbtc_price': n('wbtc_pd'),
        'cl_wbtc': n('cl_w'), 'cl_usdc': n('cl_u'),
        'total_dep_gm': n('total_dep_gm'), 'total_dep_usd': n('total_dep_usd'),
        'total_wd_usd': n('total_wd_usd'),
        'hwm': n('hwm'), 'mgr_fee': n('mgr_fee'),
        'target_ltv': n('target_ltv'), 'cooldown': n('cooldown'), 'blk': n('blk'),
        'pend_gm': n('pend_gm'),
        'vc': vc, 'vs': vs, 'iso': iso, 'tid': tid,
        # Config (bps)
        'mgmt_fee_bps': n('mgmt_fee'), 'reb_up_bps': n('reb_up'), 'reb_down_bps': n('reb_down'),
        'reb_slip_bps': n('reb_slip'), 'unwrap_long_bps': n('unwrap_long'), 'keeper_dl': n('keeper_dl'),
        # Pending details
        'pend_gm_price': n('pend_gm_price'), 'pend_gm_col': n('pend_gm_col'),
        'pend_dep_dl': n('pend_dep_dl'),
        'pend_wd_shares': n('pend_wd_shares'), 'pend_wd_gm': n('pend_wd_gm'), 'pend_wd_dl': n('pend_wd_dl'),
        'pend_reb_kind': n('pend_reb_kind'), 'pend_reb_dir': n('pend_reb_dir'),
        'pend_reb_ltv': n('pend_reb_ltv'), 'pend_reb_dl': n('pend_reb_dl'),
        # Snapshots
        'last_nav': n('last_nav'), 'last_gm_col': n('last_gm_col'), 'last_wbtc_debt': n('last_wbtc_debt'),
    }
    # Computed from live Dolomite positions
    gp = snap['gm_price'] / 1e18
    wp = snap['wbtc_price'] / 1e28
    gc_live = snap['gm_col'] / 1e18  # gm_col = live Dolomite GM (E18)
    wd_live = snap['wbtc_debt'] / 1e8  # wbtc_debt = live Dolomite WBTC debt (E8)
    snap['nav_usd'] = gc_live * gp - wd_live * wp
    snap['gm_col_usd'] = gc_live * gp
    snap['wbtc_debt_usd'] = wd_live * wp
    snap['ltv'] = (wd_live * wp / (gc_live * gp) * 100) if gc_live * gp > 0 else 0
    print(json.dumps(snap))
    sys.exit(0)

print()
print('========== VAULT ==========')
print(f'  NFT #{tid}  VC: {vc}')
print(f'  ISO: {iso}')
print()
print('-- State --')
print(f'  deposit: {sl[ds] if ds<2 else ds}  withdraw: {sl[ws] if ws<2 else ws}  rebalance: {sl[rs] if rs<2 else rs}')
print(f'  cooldown: {n("cooldown")} (now: {n("blk")})')
print()
print('-- NAV & LTV (live Dolomite) --')
print(f'  NAV:            ${nav:.4f}')
print(f'  GM collateral:  {live_gm:.6f} GM (${cu:.4f})')
print(f'  WBTC debt:      {live_wbtc_debt:.8f} WBTC (${du:.4f})')
if live_wbtc_surplus > 0:
    print(f'  WBTC surplus:   {live_wbtc_surplus:.8f} WBTC')
print(f'  LTV:            {ltv:.2f}%')
print(f'  (snapshot NAV:  ${snap_nav:.4f}  GM: {snap_gc:.6f}  debt: {snap_wd8:.8f})')
print()
print('-- Fees --')
print(f'  mgmt fee:       {n("mgmt_fee")} bps')
print(f'  accrued mgr:    ${n("mgr_fee")/1e18:.6f}')
print(f'  HWM profit:     ${n("hwm")/1e18:.6f}')
print(f'  total dep GM:   {n("total_dep_gm")/1e18:.6f}')
print(f'  total dep USD:  ${n("total_dep_usd")/1e18:.4f}')
print(f'  total wd USD:   ${n("total_wd_usd")/1e18:.4f}')
print()
print('-- Config --')
print(f'  target LTV:     {n("target_ltv")} bps')
print(f'  reb threshold:  up={n("reb_up")} down={n("reb_down")} bps')
print(f'  reb slip cap:   {n("reb_slip")} bps')
print(f'  unwrap long:    {n("unwrap_long")} bps')
print(f'  keeper dl:      {n("keeper_dl")}')
print()
print('-- Pending --')
print(f'  dep GM: {n("pend_gm")/1e18:.6f}  price: ${n("pend_gm_price")/1e18:.6f}  col: {n("pend_gm_col")/1e18:.6f}')
print()
print('-- Dolomite --')
print(f'  GM: {f(gs,gv,18)}  USDC: {f(us,uv,6)}  WBTC: {f(ws2,wv,8)}')
print()
print('-- Wallet --')
print(f'  USDC: {n("my_usdc")/1e6:.2f}  WBTC: {n("my_wbtc")/1e8:.8f}  GM: {n("my_gm")/1e18:.6f}  ETH: {n("my_eth")/1e18:.6f}')
print()
print('-- Prices (Dolomite) --')
print(f'  WBTC: ${wbtc_p:,.2f}   USDC: ${cl_u:.4f}   GM: ${gm_p:.6f}')
print()
