import { createPublicClient, http, fallback } from 'viem';
import { arbitrum } from 'viem/chains';

export const arbClient = createPublicClient({
  chain: arbitrum,
  transport: fallback([
    http('https://1rpc.io/2bR5rWkgb3ersCn5A/arb'),
    http('https://arb1.arbitrum.io/rpc'),
    http('https://arbitrum.drpc.org'),
    http('https://rpc.ankr.com/arbitrum'),
    http('https://arbitrum.meowrpc.com'),
    http('https://arbitrum-one.publicnode.com'),
  ]),
});
