/**
 * Fetch GMX execution fee via arbClient (viem multicall + getGasPrice).
 * Port of script/helpers/exec-fee.py — same formula, same constants.
 * Single multicall RPC call + getGasPrice. Refetches every 10 min.
 */

import { useState, useEffect } from 'react';
import { parseAbi } from 'viem';
import { arbClient } from './arbClient';
import { computeExecutionFee, type ExecutionFeeQuote, type ExecutionOperation } from './execFee';

const DATASTORE = '0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8' as const;
const CHAINLINK_ETH = '0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612' as const;
const WRAPPER = '0xc58ccFB7c8207Ab9b1b2cE89b292c5dB353E06D8' as const;
const UNWRAPPER = '0x2B9D148fABCAA522015492d205CAD9F2b4852758' as const;

const DS_KEYS = {
  baseAmount: '0x39288f227e5db9a793e9f4afb15aa22b77dbb7e410ffc973c816a19a6ed921cd' as `0x${string}`,
  perOracle: '0xf95915378e4358fb5f51ae0fd75853a15a29a978eb14b73d5c5b7d69d3b9fccc' as `0x${string}`,
  multiplier: '0xce135f2a886cf6d862269f215b1e64498fa09cb04f90b771b163399df2a82b81' as `0x${string}`,
  deposit: '0x584e21a67b50948de3f8d83d0226c3568896d123cdbe7a46d824d0f48aabf184' as `0x${string}`,
  withdrawal: '0x2e365620be682b0eaff6521339d5f4a7d6a1c118d9766dad390735f03b07b738' as `0x${string}`,
};

const datastoreAbi = parseAbi(['function getUint(bytes32 key) external view returns (uint256)']);
const chainlinkAbi = parseAbi(['function latestRoundData() external view returns (uint80,int256,uint256,uint256,uint80)']);
const callbackAbi = parseAbi(['function callbackGasLimit() external view returns (uint256)']);

const REFETCH_MS = 10 * 60 * 1000; // 10 minutes

async function fetchExecFee(op: ExecutionOperation): Promise<{
  quote: ExecutionFeeQuote;
  ethUsd: number;
}> {
  const gasLimitKey = op === 'deposit' ? DS_KEYS.deposit : DS_KEYS.withdrawal;
  const callbackTarget = op === 'deposit' ? WRAPPER : UNWRAPPER;

  const [results, gasPrice] = await Promise.all([
    arbClient.multicall({
      contracts: [
        { address: DATASTORE, abi: datastoreAbi, functionName: 'getUint', args: [DS_KEYS.baseAmount] },
        { address: DATASTORE, abi: datastoreAbi, functionName: 'getUint', args: [DS_KEYS.perOracle] },
        { address: DATASTORE, abi: datastoreAbi, functionName: 'getUint', args: [DS_KEYS.multiplier] },
        { address: DATASTORE, abi: datastoreAbi, functionName: 'getUint', args: [gasLimitKey] },
        { address: CHAINLINK_ETH, abi: chainlinkAbi, functionName: 'latestRoundData' },
        { address: callbackTarget, abi: callbackAbi, functionName: 'callbackGasLimit' },
      ],
    }),
    arbClient.getGasPrice(),
  ]);

  const bv = (i: number): bigint => results[i].status === 'success' ? (results[i].result as bigint) : 0n;

  // Chainlink latestRoundData returns tuple — price is index 1
  const ethUsd = results[4].status === 'success'
    ? Number((results[4].result as readonly [bigint, bigint, bigint, bigint, bigint])[1]) / 1e8
    : 0;

  const quote = computeExecutionFee({
    operation: op,
    baseAmount: bv(0),
    perOracle: bv(1),
    multiplier: bv(2),
    depositGasLimit: bv(3),
    withdrawalGasLimit: bv(3),
    oracleCount: 3n,
    callbackGas: bv(5),
    gasPrice,
    ethUsd,
  });

  return { quote, ethUsd };
}

/** React hook: exec fee quote with 10-min auto-refetch. */
export function useExecFee(op: ExecutionOperation = 'deposit') {
  const [quote, setQuote] = useState<ExecutionFeeQuote | null>(null);
  const [ethUsd, setEthUsd] = useState(0);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const doFetch = () => {
      fetchExecFee(op)
        .then(({ quote, ethUsd }) => { setQuote(quote); setEthUsd(ethUsd); })
        .catch(err => { setError(err.message); import.meta.env.DEV && console.error('[Basalt] execFee error:', err); });
    };
    doFetch();
    const interval = setInterval(doFetch, REFETCH_MS);
    return () => clearInterval(interval);
  }, [op]);

  return { quote, ethUsd, error };
}
