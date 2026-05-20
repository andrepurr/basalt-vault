import { useCallback, useEffect, useRef, type MouseEvent, type AnchorHTMLAttributes } from 'react';
import { flushSync } from 'react-dom';
import { useNavigate } from 'react-router';

interface TransitionLinkProps extends Omit<AnchorHTMLAttributes<HTMLAnchorElement>, 'href'> {
  to: string;
}

/**
 * <a> that wraps SPA navigation in document.startViewTransition().
 * Falls back to instant navigate if View Transitions API unavailable.
 * External URLs (https://) render as plain <a> with no SPA interception.
 */
export function TransitionLink({ to, onClick, children, ...rest }: TransitionLinkProps) {
  const isExternal = to.startsWith('http://') || to.startsWith('https://');
  const navigate = useNavigate();

  const handleClick = useCallback(
    (e: MouseEvent<HTMLAnchorElement>) => {
      if (isExternal) return;
      // Let browser handle ctrl/meta/middle clicks normally
      if (e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
      e.preventDefault();
      onClick?.(e);

      if (document.startViewTransition) {
        document.startViewTransition(() => {
          flushSync(() => {
            navigate(to);
          });
        });
      } else {
        navigate(to);
      }
    },
    [to, navigate, onClick, isExternal],
  );

  return (
    <a href={to} onClick={handleClick} {...rest}>
      {children}
    </a>
  );
}
