export type ExecutionOperation = 'deposit' | 'withdraw'

/* ─────────────────────────────────────────────────────────────────────
 *  GMX execution-fee estimator — TypeScript port of
 *  script/helpers/exec-fee.py. GM BTC/USDC only.
 *
 *  Formula (identical to the Python reference):
 *    est = gasLimit(op) + callbackGas
 *    adj = baseAmount + perOracle * oracleCount
 *          + (est * multiplier) / 1e30
 *    feeMin  = adj * gasPrice              // exact
 *    feeLow  = feeMin * 110 / 100          // +10% minimum buffer (risk of keeper skip)
 *    feeSafe = feeMin * 130 / 100          // +30% recommended default
 *    feeMax  = feeMin * 150 / 100          // +50% for volatile gas
 *
 *  feeHighWei is kept as an alias for feeMaxWei for backward compat.
 *
 *  Constants come from the GMX DataStore via on-chain multicall in
 *  the useExecutionFeeEstimate hook. This module is pure math.
 *
 *  NOTE: BasaltZapIn.sol creates the GMX deposit with
 *    callbackGasLimit: 0
 *  so `callbackGas` defaults to 0n for the Zap path. We still accept it
 *  as an input because the Python script wires it up from the wrapper
 *  contract and we want parity when someone feeds in a non-zero value.
 * ───────────────────────────────────────────────────────────────────── */

/** 10**30 — GMX's FLOAT_PRECISION constant. */
export const FLOAT_PRECISION = 10n ** 30n

export interface ExecutionFeeInputs {
  operation: ExecutionOperation
  /** GMX DataStore.getUint(baseAmount). */
  baseAmount: bigint
  /** GMX DataStore.getUint(perOracle). */
  perOracle: bigint
  /** GMX DataStore.getUint(multiplier). */
  multiplier: bigint
  /** eth_gasPrice result. */
  gasPrice: bigint
  /** GMX DataStore.getUint(deposit) gas limit — used when op='deposit'. */
  depositGasLimit: bigint
  /** GMX DataStore.getUint(withdrawal) gas limit — used when op='withdraw'. */
  withdrawalGasLimit: bigint
  /** Usually 3 for GM BTC/USDC (long + short + index oracle). */
  oracleCount: bigint
  /** Callback gas limit. 0 for Zap-mediated deposits. */
  callbackGas: bigint
  /** Optional ETH/USD price for USD display. */
  ethUsd?: number
}

export interface ExecutionFeeQuote {
  adjustedGas: bigint
  estimatedGas: bigint
  oracleCount: bigint
  callbackGas: bigint
  gasPrice: bigint
  feeMinWei: bigint
  feeLowWei: bigint   // +10% — minimum buffer, risk of keeper skip
  feeSafeWei: bigint  // +30% — recommended default
  feeMaxWei: bigint   // +50% — for volatile gas
  /** @deprecated alias for feeMaxWei — kept for legacy callers. */
  feeHighWei: bigint
  feeMinUsd?: number
  feeLowUsd?: number
  feeSafeUsd?: number
  feeMaxUsd?: number
  feeHighUsd?: number
}

function weiToUsd(value: bigint, ethUsd: number | undefined): number | undefined {
  if (ethUsd === undefined) return undefined
  return (Number(value) / 1e18) * ethUsd
}

/**
 * Pure function: given GMX constants and gas price, return min/safe/high
 * execution fee quotes in wei (and USD if ethUsd supplied).
 *
 * Mirrors compute() from exec-fee.py exactly.
 */
export function computeExecutionFee(inputs: ExecutionFeeInputs): ExecutionFeeQuote {
  const {
    operation,
    baseAmount,
    perOracle,
    multiplier,
    gasPrice,
    depositGasLimit,
    withdrawalGasLimit,
    oracleCount,
    callbackGas,
    ethUsd,
  } = inputs

  const gasLimit = operation === 'deposit' ? depositGasLimit : withdrawalGasLimit
  const estimatedGas = gasLimit + callbackGas
  const adjustedGas =
    baseAmount + perOracle * oracleCount + (estimatedGas * multiplier) / FLOAT_PRECISION

  const feeMinWei = adjustedGas * gasPrice
  const feeLowWei = (feeMinWei * 110n) / 100n   // +10% — minimum buffer, risk of keeper skip
  const feeSafeWei = (feeMinWei * 130n) / 100n  // +30% — recommended default
  const feeMaxWei = (feeMinWei * 150n) / 100n   // +50% — for volatile gas
  const feeHighWei = feeMaxWei                  // legacy alias

  return {
    adjustedGas,
    estimatedGas,
    oracleCount,
    callbackGas,
    gasPrice,
    feeMinWei,
    feeLowWei,
    feeSafeWei,
    feeMaxWei,
    feeHighWei,
    feeMinUsd: weiToUsd(feeMinWei, ethUsd),
    feeLowUsd: weiToUsd(feeLowWei, ethUsd),
    feeSafeUsd: weiToUsd(feeSafeWei, ethUsd),
    feeMaxUsd: weiToUsd(feeMaxWei, ethUsd),
    feeHighUsd: weiToUsd(feeMaxWei, ethUsd),
  }
}
