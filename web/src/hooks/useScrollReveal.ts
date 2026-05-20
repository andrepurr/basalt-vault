import { useRef } from 'react';
import { useScroll, useTransform, useSpring, type MotionValue } from 'motion/react';

interface ScrollRevealValues {
  ref: React.RefObject<HTMLDivElement | null>;
  y: MotionValue<number>;
  opacity: MotionValue<number>;
}

export function useScrollReveal(distance: number = 60): ScrollRevealValues {
  const ref = useRef<HTMLDivElement>(null);
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ['start end', 'end start'],
  });

  const rawY = useTransform(scrollYProgress, [0, 0.3], [distance, 0]);
  const rawOpacity = useTransform(scrollYProgress, [0, 0.3], [0, 1]);
  const y = useSpring(rawY, { stiffness: 100, damping: 30 });
  const opacity = useSpring(rawOpacity, { stiffness: 100, damping: 30 });

  return { ref, y, opacity };
}
