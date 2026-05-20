import { http, createConfig, fallback } from 'wagmi';
import { arbitrum } from 'wagmi/chains';
import { injected } from 'wagmi/connectors';

export const config = createConfig({
  chains: [arbitrum],
  connectors: [injected()],
  transports: {
    [arbitrum.id]: fallback([
      http('https://1rpc.io/2bR5rWkgb3ersCn5A/arb'),
      http('https://arb1.arbitrum.io/rpc'),
      http('https://arbitrum.drpc.org'),
      http('https://rpc.ankr.com/arbitrum'),
      http('https://arbitrum-one.publicnode.com'),
    ]),
  },
});
