import type { AuthSession, AuthUser, Principal } from '$lib/server/auth';

declare global {
  namespace App {
    interface Locals {
      session: AuthSession | null;
      user: AuthUser | null;
      principal: Principal | null;
    }
  }
}

export {};
