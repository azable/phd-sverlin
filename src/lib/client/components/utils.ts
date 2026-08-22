/**
 * Client design-system styling and component-prop helpers.
 *
 * @packageDocumentation
 */

import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

/** Merge conditional class values and resolve conflicting Tailwind utilities. */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}

/** Add a typed DOM element reference to component props. */
export type WithElementRef<T, U extends HTMLElement = HTMLElement> = T & {
  ref?: U | null;
};

/** Remove a snippet-style `child` prop from a component contract. */
export type WithoutChild<T> = Omit<T, 'child'>;

/** Remove a `children` prop from a component contract. */
export type WithoutChildren<T> = Omit<T, 'children'>;

/** Remove both singular and plural child props from a component contract. */
export type WithoutChildrenOrChild<T> = WithoutChildren<WithoutChild<T>>;
