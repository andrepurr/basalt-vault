#!/usr/bin/env python3
"""Compare two vault snapshots and print a before/after diff table.

Usage: python3 snap-diff.py '{"nav":...}' '{"nav":...}'
   or: python3 snap-diff.py /tmp/before.json /tmp/after.json
"""
import json, sys, os

def load(arg):
    if os.path.isfile(arg):
        return json.load(open(arg))
    return json.loads(arg)

b, a = load(sys.argv[1]), load(sys.argv[2])

sl = ['IDLE', 'PENDING']
def st(v): return sl[v] if v < len(sl) else str(v)

def delta(before, after, fmt='.4f', scale=1, suffix=''):
    bv, av = before / scale, after / scale
    d = av - bv
    sign = '+' if d >= 0 else ''
    return f'{bv:{fmt}}{suffix}', f'{av:{fmt}}{suffix}', f'{sign}{d:{fmt}}{suffix}'

def delta_usd(before, after):
    return delta(before, after, '.2f', 1, '')

rows = []

# NAV
bv, av, dv = delta_usd(b['nav_usd'], a['nav_usd'])
rows.append(('NAV', f'${bv}', f'${av}', f'${dv}'))

# GM collateral
bv, av, dv = delta(b['gm_col'], a['gm_col'], '.6f', 1e18, ' GM')
bvu, avu, dvu = delta_usd(b['gm_col_usd'], a['gm_col_usd'])
rows.append(('GM coll', f'{bv} (${bvu})', f'{av} (${avu})', dvu))

# WBTC debt
bv, av, dv = delta(b['wbtc_debt'], a['wbtc_debt'], '.8f', 1e8, ' WBTC')
bvu, avu, dvu = delta_usd(b['wbtc_debt_usd'], a['wbtc_debt_usd'])
rows.append(('WBTC debt', f'{bv} (${bvu})', f'{av} (${avu})', dvu))

# LTV
bv, av, dv = delta(b['ltv'], a['ltv'], '.2f', 1, '%')
rows.append(('LTV', bv, av, dv))

# Dolomite positions
bv, av, dv = delta(b['gm_dol'], a['gm_dol'], '.6f', 1e18, ' GM')
rows.append(('Dol GM', bv, av, dv))
bv, av, dv = delta(b['usdc_dol'], a['usdc_dol'], '.2f', 1e6, ' USDC')
rows.append(('Dol USDC', bv, av, dv))
bv, av, dv = delta(b['wbtc_dol'], a['wbtc_dol'], '.8f', 1e8, ' WBTC')
rows.append(('Dol WBTC', bv, av, dv))

# Wallet
bv, av, dv = delta(b['my_usdc'], a['my_usdc'], '.2f', 1e6, '')
rows.append(('Wallet USDC', f'${bv}', f'${av}', f'${dv}'))
bv, av, dv = delta(b['my_gm'], a['my_gm'], '.6f', 1e18, '')
rows.append(('Wallet GM', bv, av, dv))
bv, av, dv = delta(b['my_eth'], a['my_eth'], '.6f', 1e18, '')
rows.append(('Wallet ETH', bv, av, dv))

# Prices
gp_b, gp_a = b['gm_price']/1e18, a['gm_price']/1e18
wp_b, wp_a = b['wbtc_price']/1e28, a['wbtc_price']/1e28
rows.append(('GM price', f'${gp_b:.6f}', f'${gp_a:.6f}', f'{(gp_a-gp_b)/gp_b*100:+.3f}%' if gp_b else ''))
rows.append(('WBTC price', f'${wp_b:,.2f}', f'${wp_a:,.2f}', f'{(wp_a-wp_b)/wp_b*100:+.3f}%' if wp_b else ''))

# States
rows.append(('States', f'd={st(b["dep_st"])} w={st(b["wd_st"])} r={st(b["reb_st"])}',
                        f'd={st(a["dep_st"])} w={st(a["wd_st"])} r={st(a["reb_st"])}', ''))

# Totals
bv, av, dv = delta_usd(b['total_dep_usd']/1e18, a['total_dep_usd']/1e18)
rows.append(('Total dep $', f'${bv}', f'${av}', f'${dv}'))
bv, av, dv = delta_usd(b['total_wd_usd']/1e18, a['total_wd_usd']/1e18)
rows.append(('Total wd $', f'${bv}', f'${av}', f'${dv}'))

# Print
W1, W2, W3, W4 = 12, 28, 28, 16
print()
print(f'{"":─<{W1+W2+W3+W4+6}}')
print(f'  {"":>{W1}} {"BEFORE":>{W2}} {"AFTER":>{W3}} {"DELTA":>{W4}}')
print(f'{"":─<{W1+W2+W3+W4+6}}')
for label, bv, av, dv in rows:
    print(f'  {label:>{W1}} {bv:>{W2}} {av:>{W3}} {dv:>{W4}}')
print(f'{"":─<{W1+W2+W3+W4+6}}')
print()
