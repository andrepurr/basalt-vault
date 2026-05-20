// Landing page content — engineering-grade voice: terse, precise, numerical.

/** Mechanics steps — the four-move vault lifecycle. */
export const mechanicsSteps: {
  number: string;
  title: string;
  description: string;
}[] = [
  {
    number: '01',
    title: 'Zap in',
    description:
      'You deposit USDC. The thin Zap router swaps it to GM (the GMX v2 BTC/USDC market token).',
  },
  {
    number: '02',
    title: 'Loop',
    description:
      'GM lands as collateral on a Dolomite isolation account. The vault borrows WBTC against it and wraps that WBTC into more GM, until LTV hits target.',
  },
  {
    number: '03',
    title: 'Settle',
    description:
      'GMX settles in ~2s. Basalt keeper finalizes in ~2s after that. If stuck past the grace period, the vault owner can cancel and recover funds.',
  },
  {
    number: '04',
    title: 'Earn',
    description:
      'You hold a single ERC-721 representing the vault. 20% of profit above the high-water mark accrues to fee-share holders via FeeSplitter.',
  },
];

/** Parameters table rows: [name, value, description]. */
export const parameterRows: [string, string, string][] = [
  ['Deposit token', 'USDC', 'Native USDC on Arbitrum One'],
  ['Yield source', 'GM BTC/USDC', 'GMX v2 liquidity pool — trading fees + funding'],
  ['Hedge', 'WBTC debt', 'Borrowed on Dolomite to cancel BTC delta'],
  ['Chain', 'Arbitrum', 'L2 — low gas, ~0.25s block time'],
  ['Target LTV', '50%', 'Configurable 48–52%, auto-rebalanced'],
  ['Safe cap', '70%', 'Above this the NFT owner can rebalance directly'],
  ['Liquidation', '~83.8%', 'Dolomite liquidation threshold'],
  ['Performance fee', '20%', 'Above the high-water mark only'],
];

/** Hero stat entries — honest about strategy characteristics. */
export const heroStats: { label: string; value: string }[] = [
  { label: 'Backtest APY', value: '19.7%' },
  { label: 'Max drawdown', value: '-5.7%' },
  { label: 'Delta', value: '~0' },
  { label: 'Liquidation', value: '83.8%' },
];

/** Protocol trust badges — TVL data from DeFiLlama, updated 2026-04-29. */
export const protocolBadges: { name: string; detail: string }[] = [
  { name: 'GMX v2', detail: '$200M+ TVL' },
  { name: 'Dolomite', detail: '$150M+ TVL' },
  { name: 'GM BTC/USDC', detail: 'Top risk-adjusted yield' },
];

