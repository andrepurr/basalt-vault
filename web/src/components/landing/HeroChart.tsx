import { useEffect, useRef } from 'react';
import { useReducedMotion } from '../../hooks/useReducedMotion';
import styles from './HeroChart.module.css';

/** Mini animated LTV health curve for the hero section.
 *  Pure canvas — lightweight, no SVG DOM overhead. */
export function HeroChart() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const reduced = useReducedMotion();

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let animId: number;
    let t = 0;

    function resize() {
      if (!canvas) return;
      const dpr = window.devicePixelRatio || 1;
      canvas.width = canvas.offsetWidth * dpr;
      canvas.height = canvas.offsetHeight * dpr;
      ctx!.scale(dpr, dpr);
    }
    resize();
    window.addEventListener('resize', resize);

    const W = () => canvas.offsetWidth;
    const H = () => canvas.offsetHeight;

    // LTV curve: hyperbolic shape (LTV rises as price drops)
    function ltvAtX(x: number): number {
      const norm = 1 - x / W();
      return 0.15 + norm * norm * 0.55;
    }

    function draw() {
      if (!ctx || !canvas) return;
      const w = W(), h = H();
      ctx.clearRect(0, 0, w, h);

      // Grid lines
      ctx.strokeStyle = 'rgba(140, 140, 180, 0.06)';
      ctx.lineWidth = 1;
      for (let y = 0; y < h; y += 40) {
        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
      }
      for (let x = 0; x < w; x += 40) {
        ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke();
      }

      // Liquidation zone (top 30%)
      const liqY = h * 0.3;
      const grad = ctx.createLinearGradient(0, 0, 0, liqY);
      grad.addColorStop(0, 'rgba(196, 58, 26, 0.2)');
      grad.addColorStop(1, 'rgba(196, 58, 26, 0.02)');
      ctx.fillStyle = grad;
      ctx.fillRect(0, 0, w, liqY);

      // 70% dashed line
      ctx.strokeStyle = 'rgba(196, 58, 26, 0.5)';
      ctx.setLineDash([4, 4]);
      ctx.beginPath(); ctx.moveTo(0, liqY); ctx.lineTo(w, liqY); ctx.stroke();
      ctx.setLineDash([]);

      // Label
      ctx.font = '500 10px "Geist Mono", monospace';
      ctx.fillStyle = 'rgba(196, 58, 26, 0.7)';
      ctx.fillText('70% SAFE CAP', w - 90, liqY - 6);

      // Main LTV curve
      ctx.beginPath();
      ctx.moveTo(0, h);
      for (let x = 0; x <= w; x += 2) {
        const ltv = ltvAtX(x);
        const wave = reduced ? 0 : Math.sin(x * 0.02 + t * 2) * 3;
        ctx.lineTo(x, h - ltv * h + wave);
      }
      ctx.lineTo(w, h);
      ctx.closePath();

      // Gradient fill under curve
      const fillGrad = ctx.createLinearGradient(0, 0, 0, h);
      fillGrad.addColorStop(0, 'rgba(255, 106, 61, 0.25)');
      fillGrad.addColorStop(1, 'rgba(255, 106, 61, 0)');
      ctx.fillStyle = fillGrad;
      ctx.fill();

      // Curve stroke with glow
      ctx.shadowColor = 'rgba(255, 106, 61, 0.6)';
      ctx.shadowBlur = 12;
      ctx.strokeStyle = '#ff6a3d';
      ctx.lineWidth = 2.5;
      ctx.beginPath();
      for (let x = 0; x <= w; x += 2) {
        const ltv = ltvAtX(x);
        const wave = reduced ? 0 : Math.sin(x * 0.02 + t * 2) * 3;
        if (x === 0) ctx.moveTo(x, h - ltv * h + wave);
        else ctx.lineTo(x, h - ltv * h + wave);
      }
      ctx.stroke();
      ctx.shadowBlur = 0;

      // "Now" dot — animated position
      const nowX = w * 0.65;
      const nowLtv = ltvAtX(nowX);
      const nowWave = reduced ? 0 : Math.sin(nowX * 0.02 + t * 2) * 3;
      const nowY = h - nowLtv * h + nowWave;
      const pulseR = 6 + (reduced ? 0 : Math.sin(t * 3) * 2);

      // Glow ring
      ctx.beginPath();
      ctx.arc(nowX, nowY, pulseR + 8, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(255, 106, 61, 0.15)';
      ctx.fill();

      // Dot
      ctx.beginPath();
      ctx.arc(nowX, nowY, pulseR, 0, Math.PI * 2);
      ctx.fillStyle = '#ff6a3d';
      ctx.shadowColor = 'rgba(255, 106, 61, 0.8)';
      ctx.shadowBlur = 16;
      ctx.fill();
      ctx.shadowBlur = 0;

      // Label
      ctx.font = '500 11px "Geist Mono", monospace';
      ctx.fillStyle = '#ff6a3d';
      ctx.fillText('~ 50%', nowX + 14, nowY - 4);

      // Target line (50%)
      const targetY = h - 0.5 * h * 0.7;
      ctx.strokeStyle = 'rgba(100, 180, 100, 0.3)';
      ctx.setLineDash([2, 6]);
      ctx.beginPath(); ctx.moveTo(0, targetY); ctx.lineTo(w, targetY); ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = 'rgba(100, 180, 100, 0.5)';
      ctx.fillText('TARGET 50%', 8, targetY - 6);

      if (!reduced) {
        t += 0.016;
        animId = requestAnimationFrame(draw);
      }
    }

    draw();

    return () => {
      cancelAnimationFrame(animId);
      window.removeEventListener('resize', resize);
    };
  }, [reduced]);

  return (
    <div className={styles.chartWrap}>
      <canvas ref={canvasRef} className={styles.canvas} aria-hidden="true" />
      <div className={styles.axisX}>
        <span>−40%</span><span>−20%</span><span>spot</span><span>+10%</span>
      </div>
    </div>
  );
}
