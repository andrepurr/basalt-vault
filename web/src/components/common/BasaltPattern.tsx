import { useId } from 'react';

interface BasaltPatternProps {
  opacity?: number;
}

export function BasaltPattern({ opacity = 0.06 }: BasaltPatternProps) {
  const uid = useId();
  const hexId = `basalt-hex-${uid}`;
  const hex2Id = `basalt-hex2-${uid}`;

  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 400 400"
      fill="none"
      aria-hidden="true"
      style={{
        position: 'absolute',
        inset: 0,
        width: '100%',
        height: '100%',
        pointerEvents: 'none',
        opacity,
        zIndex: 0,
      }}
      preserveAspectRatio="none"
    >
      <defs>
        <pattern id={hexId} x="0" y="0" width="60" height="52" patternUnits="userSpaceOnUse">
          <g stroke="currentColor" strokeWidth="1" fill="none" opacity="0.6">
            <path d="M30 1 L58 16 V42 L30 57 L2 42 V16 Z" />
          </g>
        </pattern>
        <pattern id={hex2Id} x="30" y="26" width="60" height="52" patternUnits="userSpaceOnUse">
          <g stroke="currentColor" strokeWidth="1" fill="none" opacity="0.6">
            <path d="M30 1 L58 16 V42 L30 57 L2 42 V16 Z" />
          </g>
        </pattern>
      </defs>
      <rect width="400" height="400" fill={`url(#${hexId})`} />
      <rect width="400" height="400" fill={`url(#${hex2Id})`} />
    </svg>
  );
}
