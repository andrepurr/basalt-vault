import { type ButtonHTMLAttributes } from 'react';
import { TransitionLink } from './TransitionLink';
import clsx from 'clsx';
import styles from './Button.module.css';

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger';
  size?: 'sm' | 'md' | 'lg';
  href?: string;
}

export function Button({
  variant = 'primary',
  size = 'md',
  href,
  className,
  children,
  ...rest
}: ButtonProps) {
  const cls = clsx(styles.btn, styles[variant], styles[size], className);

  if (href) {
    return (
      <TransitionLink to={href} className={cls}>
        {children}
      </TransitionLink>
    );
  }

  return (
    <button className={cls} {...rest}>
      {children}
    </button>
  );
}
