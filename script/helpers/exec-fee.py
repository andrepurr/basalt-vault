#!/usr/bin/env python3
"""GMX Execution Fee Estimator — GM BTC/USDC only.

Computes deposit and withdrawal execution fees via GMX GasUtils formula.
Reads FRESH on-chain data via Multicall3. ETH price from Chainlink.
Zero dependencies: Python 3 stdlib only.

Market: GM BTC/USDC (Dolomite market ID 32)
  Wrapper:   0xc58ccFB7c8207Ab9b1b2cE89b292c5dB353E06D8 (WBTC/USDC -> dGM)
  Unwrapper: 0x2B9D148fABCAA522015492d205CAD9F2b4852758 (dGM -> WBTC/USDC)
  Oracle count: 3 (BTC long + USDC short + index)

Usage:
  python3 script/tools/exec-fee.py                      # interactive
  python3 script/tools/exec-fee.py --fee deposit 130    # CLI: deposit fee with 130% safety
  python3 script/tools/exec-fee.py --fee withdrawal     # CLI: withdrawal fee (default 130%)
  python3 script/tools/exec-fee.py --quote deposit 130  # verbose quote for operator logs

--fee reuses a disk cache (cache/exec-fee/ under project root) so repeated vm.ffi/forge
calls do not re-hit RPC. EXEC_FEE_FRESH=1 bypasses. EXEC_FEE_CACHE_TTL seconds (default 600).
"""

import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

# ═══════════════════════════════════════════════════════════════════
#  GM BTC/USDC CONSTANTS (Arbitrum One, verified on-chain)
# ═══════════════════════════════════════════════════════════════════

WRAPPER   = "0xc58ccFB7c8207Ab9b1b2cE89b292c5dB353E06D8"
UNWRAPPER = "0x2B9D148fABCAA522015492d205CAD9F2b4852758"

DATASTORE       = "0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8"
MULTICALL3      = "0xcA11bde05977b3631167028862bE2a173976CA11"
CHAINLINK_ETH   = "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612"
FLOAT_PRECISION = 10**30
GM_ORACLE_COUNT = 3

DS_KEYS = {
    "base_amount": "0x39288f227e5db9a793e9f4afb15aa22b77dbb7e410ffc973c816a19a6ed921cd",
    "per_oracle":  "0xf95915378e4358fb5f51ae0fd75853a15a29a978eb14b73d5c5b7d69d3b9fccc",
    "multiplier":  "0xce135f2a886cf6d862269f215b1e64498fa09cb04f90b771b163399df2a82b81",
    "deposit":     "0x584e21a67b50948de3f8d83d0226c3568896d123cdbe7a46d824d0f48aabf184",
    "withdrawal":  "0x2e365620be682b0eaff6521339d5f4a7d6a1c118d9766dad390735f03b07b738",
}

SEL_GET_UINT     = "0xbd02d0f5"
SEL_CALLBACK_GAS = "0x24f74697"
SEL_LATEST_ROUND = "0xfeaf968c"

# Order matters: run-tests.sh sets MAINNET_RPC_URL=http://127.0.0.1:8545 for forge+ffi; .env
# often has ARBITRUM_RPC_URL=Infura — must not win over local Anvil or fork tests rate-limit.
RPC_ENV_PRIORITY = (
    "EXEC_FEE_RPC_URL",
    "MAINNET_RPC_URL",
    "LOCAL_RPC_URL",
    "ONERPC_ARBITRUM_URL",
    "ARBITRUM_RPC_URL",
)

# ═══════════════════════════════════════════════════════════════════
#  ABI ENCODING + MULTICALL3
# ═══════════════════════════════════════════════════════════════════

def enc_u256(v): return f"{v:064x}"
def enc_b32(h): return h.replace("0x", "").zfill(64)
def enc_call(sel, *p): return "0x" + sel.replace("0x", "") + "".join(p)

def build_mc(calls):
    n = len(calls)
    elems = []
    for target, cd in calls:
        b = bytes.fromhex(cd.replace("0x", ""))
        pad = b.hex().ljust((len(b) + 31) // 32 * 64, '0')
        elems.append(enc_b32(target) + enc_u256(64) + enc_u256(len(b)) + pad)
    offs, cur = [], n * 32
    for e in elems:
        offs.append(enc_u256(cur)); cur += len(e) // 2
    return "0x" + "bce38bd7" + enc_u256(0) + enc_u256(64) + enc_u256(n) + "".join(offs) + "".join(elems)

def parse_mc(h, count):
    h = h.replace("0x", "")
    if len(h) < 64:
        raise RuntimeError(f"Multicall returned empty/short response ({len(h)} hex chars)")
    ao = int(h[:64], 16) * 2
    results = []
    eos = ao + 64
    for i in range(count):
        eo = int(h[eos + i*64: eos + (i+1)*64], 16) * 2 + ao + 64
        ok = int(h[eo:eo+64], 16)
        bo = int(h[eo+64:eo+128], 16) * 2
        ba = eo + bo
        bl = int(h[ba:ba+64], 16)
        results.append((bool(ok), h[ba+64:ba+64+bl*2]))
    return results

# ═══════════════════════════════════════════════════════════════════
#  RPC
# ═══════════════════════════════════════════════════════════════════

def _clean(v): return v.strip().strip('"').strip("'")

def get_rpc():
    for v in RPC_ENV_PRIORITY:
        val = os.environ.get(v)
        if val: return _clean(val)
    for v in RPC_ENV_PRIORITY:
        for p in [".env", "../.env", os.path.join(os.path.dirname(__file__), "..", "..", ".env")]:
            try:
                with open(p) as f:
                    for line in f:
                        if line.strip().startswith(f"{v}="):
                            return _clean(line.split("=", 1)[1])
            except FileNotFoundError: pass
    print("No RPC found"); sys.exit(1)

# ═══════════════════════════════════════════════════════════════════
#  DISK CACHE (vm.ffi starts a new Python process per call; tests call
#  --fee many times — one RPC batch, then reuse until TTL.)
#  EXEC_FEE_FRESH=1 — ignore cache. EXEC_FEE_CACHE_TTL — seconds (default 600).
# ═══════════════════════════════════════════════════════════════════

def _project_root():
    return os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))

def _fee_cache_path(rpc: str, op: str, mult: int) -> str:
    tag = hashlib.sha256(rpc.encode("utf-8")).hexdigest()[:12]
    d = os.path.join(_project_root(), "cache", "exec-fee")
    return os.path.join(d, f"{tag}-{op}-{mult}.txt")

def _read_fee_cache(path: str, stale_ok: bool = False):
    if os.environ.get("EXEC_FEE_FRESH", "").strip().lower() in ("1", "true", "yes"):
        return None
    try:
        ttl = int(os.environ.get("EXEC_FEE_CACHE_TTL", "3600"))
    except ValueError:
        ttl = 3600
    try:
        st = os.stat(path)
    except OSError:
        return None
    if not stale_ok and time.time() - st.st_mtime > ttl:
        return None
    with open(path, encoding="utf-8") as f:
        return f.read().strip()

def _write_fee_cache(path: str, line: str) -> None:
    d = os.path.dirname(path)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(line)

def _build_opener():
    proxy = os.environ.get("ALL_PROXY") or os.environ.get("https_proxy") or ""
    if proxy.startswith("socks"):
        # socks5 proxy — use subprocess + cast rpc as fallback
        return None
    if proxy:
        handler = urllib.request.ProxyHandler({"https": proxy, "http": proxy})
        return urllib.request.build_opener(handler)
    return urllib.request.build_opener()

_opener = _build_opener()

def _env_for_direct_rpc():
    """Strip *proxy* env vars so JSON-RPC to public Arbitrum endpoints works in ffi/CI.

    When ALL_PROXY is socks, urllib is disabled and curl+ALL_PROXY often returns
    empty stdout; direct HTTPS usually works.
    """
    return {k: v for k, v in os.environ.items() if "proxy" not in k.lower()}

def rpc_req(rpc, payload):
    data = json.dumps(payload).encode()
    if _opener is None:
        # socks proxy: stdlib urllib has no socks; was curl+ALL_PROXY (often empty body)
        import subprocess
        def _curl(env):
            return subprocess.run(
                [
                    "curl", "-sS", "-X", "POST",
                    "-H", "Content-Type: application/json",
                    "-d", data.decode(), rpc,
                ],
                capture_output=True,
                timeout=30,
                env=env,
            )
        noprox = _env_for_direct_rpc()
        result = _curl(noprox)
        if result.returncode == 0 and result.stdout.strip():
            return json.loads(result.stdout)
        # Retry with full env (user may need explicit proxy for RPC)
        result = _curl(os.environ)
        if result.returncode == 0 and result.stdout.strip():
            return json.loads(result.stdout)
        err = (result.stderr or b"").decode().strip() or f"exit={result.returncode}"
        print(f"curl failed: {err}", file=sys.stderr)
        sys.exit(1)
    r = urllib.request.Request(rpc, data, {"Content-Type": "application/json"})
    try:
        with _opener.open(r, timeout=15) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        if e.code == 429:
            return {"error": {"code": -32005, "message": "429 Too Many Requests"}}
        raise

def rpc_res(item):
    if "error" in item: raise RuntimeError(item["error"].get("message", str(item["error"])))
    return item.get("result", "0x")

def pu(raw, i):
    ok, d = raw[i]
    return int(d[:64], 16) if ok and d else 0

def p_cl(raw, i):
    ok, d = raw[i]
    return int(d[64:128], 16) / 1e8 if ok and d else 0

# ═══════════════════════════════════════════════════════════════════
#  FETCH & COMPUTE
# ═══════════════════════════════════════════════════════════════════

def fetch(rpc, op):
    calls = []
    for k in ("base_amount", "per_oracle", "multiplier", "deposit" if op == "deposit" else "withdrawal"):
        calls.append((DATASTORE, enc_call(SEL_GET_UINT, enc_b32(DS_KEYS[k]))))
    calls.append((CHAINLINK_ETH, "0x" + SEL_LATEST_ROUND.replace("0x", "")))
    calls.append((WRAPPER if op == "deposit" else UNWRAPPER, "0x" + SEL_CALLBACK_GAS.replace("0x", "")))

    # Sequential calls (Infura throttles batch requests)
    import time
    BACKUP_RPC = os.environ.get("BACKUP_RPC", "").strip()

    def _rpc_one(payload, _rpc=rpc):
        rpcs = [_rpc] + ([BACKUP_RPC] if BACKUP_RPC else [])
        last_err = None
        for url in rpcs:
            for attempt in range(2):
                try:
                    r = rpc_req(url, payload)
                except Exception as e:
                    last_err = e
                    if attempt == 0:
                        time.sleep(1)
                    break
                if isinstance(r, dict):
                    err = r.get("error")
                    if isinstance(err, dict) and err.get("code") == -32005:
                        break  # try next RPC
                    if "error" in r and not r.get("result"):
                        break
                    res = r.get("result", "")
                    if res and res != "0x":
                        return r
                    if attempt == 0:
                        time.sleep(1)
                        continue
                if isinstance(r, list) and r:
                    item = r[0] if isinstance(r[0], dict) else r
                    if isinstance(item, dict) and item.get("result", "") not in ("", "0x"):
                        return item
                if attempt == 0:
                    time.sleep(1)
        raise RuntimeError(f"All RPCs failed: {last_err or '429/empty'}")

    mc_resp = _rpc_one({"jsonrpc": "2.0", "method": "eth_call",
                        "params": [{"to": MULTICALL3, "data": build_mc(calls)}, "latest"], "id": 1})
    gp_resp = _rpc_one({"jsonrpc": "2.0", "method": "eth_gasPrice", "params": [], "id": 2})

    raw = parse_mc(rpc_res(mc_resp), len(calls))
    gp = int(rpc_res(gp_resp), 16)

    return {
        "base_amount": pu(raw, 0), "per_oracle": pu(raw, 1),
        "multiplier": pu(raw, 2), "gas_limit": pu(raw, 3),
        "eth_usd": p_cl(raw, 4), "callback_gas": pu(raw, 5), "gas_price": gp,
    }

def compute(data):
    est = data["gas_limit"] + data["callback_gas"]
    adj = data["base_amount"] + data["per_oracle"] * GM_ORACLE_COUNT + est * data["multiplier"] // FLOAT_PRECISION
    fee = adj * data["gas_price"]
    return {"adjusted_gas": adj, "callback_gas": data["callback_gas"],
            "fee_min": fee, "fee_safe": fee * 120 // 100, "fee_high": fee * 130 // 100}

# ═══════════════════════════════════════════════════════════════════
#  DISPLAY
# ═══════════════════════════════════════════════════════════════════

def show(data, op, t):
    f = compute(data)
    eu = data["eth_usd"]
    print(f"\n  GM BTC/USDC  (ID 32)  {'DEPOSIT' if op == 'deposit' else 'WITHDRAW'}  [{t:.2f}s]")
    print(f"  gas: {data['gas_price']/1e9:.4f} gwei   ETH: ${eu:,.2f}")
    print(f"  callback: {f['callback_gas']:,}   adjusted: {f['adjusted_gas']:,}")
    for l, v, n in [("Min", f["fee_min"], "exact"), ("Safe", f["fee_safe"], "+20%"), ("High", f["fee_high"], "+30%")]:
        print(f"  {l:5s}  {v/1e18:.6f} ETH   ${v/1e18*eu:.2f}   {n}")

def show_quote(data, op, mult, t):
    f = compute(data)
    fee = f["adjusted_gas"] * data["gas_price"] * mult // 100
    eth = fee / 1e18
    usd = eth * data["eth_usd"]
    print(f"\n  Execution fee quote [{op}]  ({t:.2f}s)")
    print(f"  gas price:        {data['gas_price']/1e9:.4f} gwei")
    print(f"  callback gas:     {f['callback_gas']:,}")
    print(f"  adjusted gas:     {f['adjusted_gas']:,}")
    print(f"  safety multiplier {mult}%")
    print(f"  fee:              {eth:.6f} ETH   (${usd:.2f})")
    print(f"  raw wei:          {fee}")

# ═══════════════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════════════

def main():
    rpc = get_rpc()

    if len(sys.argv) >= 2 and sys.argv[1] == "--fee":
        op = sys.argv[2] if len(sys.argv) > 2 else "deposit"
        if op in ("withdraw", "withdraws"): op = "withdrawal"
        mult = int(sys.argv[3]) if len(sys.argv) > 3 else 130
        cpath = _fee_cache_path(rpc, op, mult)
        cached = _read_fee_cache(cpath)
        if cached:
            print(cached)
            return
        try:
            data = fetch(rpc, op)
            f = compute(data)
            fee_wei = f['adjusted_gas'] * data['gas_price'] * mult // 100
            fee_usd = fee_wei / 1e18 * data['eth_usd']
            line = f"{f['adjusted_gas']} {fee_wei} {fee_usd:.2f}"
            _write_fee_cache(cpath, line)
            print(line)
        except Exception as e:
            # RPC failed — try stale cache as fallback
            stale = _read_fee_cache(cpath, stale_ok=True)
            if stale:
                print(f"  (stale cache, RPC down: {e})", file=sys.stderr)
                print(stale)
            else:
                # Try deposit cache as rough estimate for withdrawal
                if op == "withdrawal":
                    dep_path = _fee_cache_path(rpc, "deposit", mult)
                    dep_stale = _read_fee_cache(dep_path, stale_ok=True)
                    if dep_stale:
                        print(f"  (using deposit fee as estimate, RPC down)", file=sys.stderr)
                        print(dep_stale)
                        return
                raise
        return

    if len(sys.argv) >= 2 and sys.argv[1] == "--quote":
        op = sys.argv[2] if len(sys.argv) > 2 else "deposit"
        if op in ("withdraw", "withdraws"):
            op = "withdrawal"
        mult = int(sys.argv[3]) if len(sys.argv) > 3 else 130
        t0 = time.time()
        data = fetch(rpc, op)
        show_quote(data, op, mult, time.time() - t0)
        return

    print(f"\n  GM BTC/USDC Execution Fee Calculator")
    print(f"  1) Deposit   2) Withdrawal   q) Quit")
    while True:
        try:
            c = input("\n  > ").strip().lower()
        except (KeyboardInterrupt, EOFError):
            print(); return
        if c in ("q", "quit"): return
        elif c in ("1", "d", "deposit"):
            t0 = time.time(); show(fetch(rpc, "deposit"), "deposit", time.time() - t0)
        elif c in ("2", "w", "withdraw", "withdrawal"):
            t0 = time.time(); show(fetch(rpc, "withdrawal"), "withdrawal", time.time() - t0)
        else: print("  1 or 2")

if __name__ == "__main__":
    main()
