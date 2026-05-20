#!/usr/bin/env python3
"""Format vault getters from snap JSON.
Usage: echo '<snap_json>' | python3 format-getters.py <group>
Groups: states nav config fees pending wallet all
"""
import json, sys

d = json.load(sys.stdin)
group = sys.argv[1] if len(sys.argv) > 1 else 'all'

# ANSI colors
C = '\033[36m'   # cyan   - values
Y = '\033[33m'   # yellow - headers
G = '\033[32m'   # green  - ok states
R = '\033[31m'   # red    - warning
D = '\033[2m'    # dim    - dots/units
B = '\033[1m'    # bold
N = '\033[0m'    # reset

SL = {0: f'{G}idle{N}', 1: f'{Y}pending{N}'}
REB_KIND = {0: 'none', 1: 'unwrap_long', 2: 'wrap_short'}
REB_DIR = {0: 'none', 1: 'increase_ltv', 2: 'decrease_ltv'}

def row(label, val, unit=''):
    # Strip ANSI for length calculation
    import re
    clean_val = re.sub(r'\033\[[0-9;]*m', '', str(val))
    clean_unit = re.sub(r'\033\[[0-9;]*m', '', str(unit))
    pad = max(1, 40 - len(label) - len(clean_val))
    dots = D + '·' * pad + N
    u = f' {D}{unit}{N}' if unit else ''
    print(f'  {label} {dots} {C}{val}{N}{u}')

def bps(v):
    v = int(v)
    return f'{v} bps ({v/100:.1f}%)'

def e18(v): return f'{int(v)/1e18:.6f}'
def e8(v): return f'{int(v)/1e8:.8f}'
def usd18(v): return f'${int(v)/1e18:.4f}'

def hdr(title):
    print(f'\n  {Y}{B}── {title} {"─" * max(1, 34 - len(title))}{N}')

gp = d.get('gm_price', 0) / 1e18
wp = d.get('wbtc_price', 0) / 1e28


def show_states():
    hdr('States')
    for k, label in [('dep_st', 'deposit'), ('wd_st', 'withdraw'), ('reb_st', 'rebalance')]:
        v = d.get(k, 0)
        row(label, SL.get(v, f'{R}unknown({v}){N}'))
    cd = d.get('cooldown', 0)
    blk = d.get('blk', 0)
    active = f'{R}ACTIVE (ends {cd}){N}' if cd > blk else f'{G}clear{N}'
    row('cooldown', active, f'block {blk}')


def show_nav():
    hdr('NAV & Position (live Dolomite)')
    nav = d.get('nav_usd', 0)
    gc = d.get('gm_col', 0) / 1e18
    wd = d.get('wbtc_debt', 0) / 1e8
    ltv = d.get('ltv', 0)
    ltv_color = G if ltv < 60 else (Y if ltv < 80 else R)
    row('NAV', f'${nav:.4f}')
    row('GM collateral', f'{gc:.6f} GM', f'${gc * gp:.4f}')
    row('WBTC debt', f'{wd:.8f}', f'${wd * wp:.4f}')
    row('LTV', f'{ltv_color}{ltv:.2f}%{N}')
    hdr('Snapshot (last finalized)')
    row('NAV', usd18(d.get('last_nav', 0)))
    row('GM collateral', e18(d.get('last_gm_col', 0)))
    row('WBTC debt', e8(d.get('last_wbtc_debt', 0)))


def show_config():
    hdr('Config')
    row('target LTV', bps(d.get('target_ltv', 0)))
    row('management fee', bps(d.get('mgmt_fee_bps', 0)))
    row('reb threshold UP', bps(d.get('reb_up_bps', 0)))
    row('reb threshold DOWN', bps(d.get('reb_down_bps', 0)))
    row('reb slippage cap', bps(d.get('reb_slip_bps', 0)))
    row('unwrap long share', bps(d.get('unwrap_long_bps', 0)))
    row('keeper deadline', f'{d.get("keeper_dl", 0)}s')


def show_fees():
    hdr('Fees & Totals')
    row('management fee', bps(d.get('mgmt_fee_bps', 0)))
    row('accrued manager fee', usd18(d.get('mgr_fee', 0)))
    row('HWM profit', usd18(d.get('hwm', 0)))
    hdr('Deposit/Withdraw Totals')
    row('total deposited GM', e18(d.get('total_dep_gm', 0)))
    row('total deposited USD', usd18(d.get('total_dep_usd', 0)))
    row('total withdrawn USD', usd18(d.get('total_wd_usd', 0)))


def show_pending():
    ds = d.get('dep_st', 0)
    ws = d.get('wd_st', 0)
    rs = d.get('reb_st', 0)

    hdr('Pending Deposit')
    if ds == 0:
        print(f'  {D}(idle){N}')
    else:
        row('GM amount', e18(d.get('pend_gm', 0)))
        row('GM price snapshot', usd18(d.get('pend_gm_price', 0)))
        row('GM collateral snap', e18(d.get('pend_gm_col', 0)))
        row('deadline', str(d.get('pend_dep_dl', 0)), 'block')

    hdr('Pending Withdraw')
    if ws == 0:
        print(f'  {D}(idle){N}')
    else:
        row('shares', e18(d.get('pend_wd_shares', 0)))
        row('GM to sell', e18(d.get('pend_wd_gm', 0)))
        row('deadline', str(d.get('pend_wd_dl', 0)), 'block')

    hdr('Pending Rebalance')
    if rs == 0:
        print(f'  {D}(idle){N}')
    else:
        row('kind', REB_KIND.get(d.get('pend_reb_kind', 0), '?'))
        row('direction', REB_DIR.get(d.get('pend_reb_dir', 0), '?'))
        row('LTV snapshot', bps(d.get('pend_reb_ltv', 0)))
        row('deadline', str(d.get('pend_reb_dl', 0)), 'block')


def show_wallet():
    hdr('Wallet Balances')
    usdc_v = d.get('my_usdc', 0) / 1e6
    wbtc_v = d.get('my_wbtc', 0) / 1e8
    gm_v = d.get('my_gm', 0) / 1e18
    eth_v = d.get('my_eth', 0) / 1e18
    row('USDC', f'{usdc_v:.2f}', f'${usdc_v:.2f}')
    row('WBTC', f'{wbtc_v:.8f}', f'${wbtc_v * wp:,.2f}')
    row('GM', f'{gm_v:.6f}', f'${gm_v * gp:.4f}')
    row('ETH', f'{eth_v:.6f}')
    hdr('Prices (Dolomite oracle)')
    row('WBTC', f'${wp:,.2f}')
    row('GM', f'${gp:.6f}')
    cu = d.get('cl_usdc', 0) / 1e8
    row('USDC (Chainlink)', f'${cu:.4f}')


def show_addresses():
    hdr('Addresses')
    row('VaultCore', d.get('vc', '?'))
    row('VaultState', d.get('vs', '?'))
    row('Isolation Vault', d.get('iso', '?'))


GROUPS = {
    'states':  [show_states],
    'nav':     [show_nav],
    'config':  [show_config],
    'fees':    [show_fees],
    'pending': [show_pending],
    'wallet':  [show_wallet],
    'addr':    [show_addresses],
    'all':     [show_states, show_nav, show_config, show_fees, show_pending, show_wallet, show_addresses],
}

fns = GROUPS.get(group, GROUPS['all'])
tid = d.get('tid', '?')
print(f'\n  {B}{Y}◆ VAULT GETTERS{N}  {D}(NFT #{tid}){N}')
for fn in fns:
    fn()
print()
