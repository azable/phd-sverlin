import { passkeyClient } from '@better-auth/passkey/client';
import { usernameClient } from 'better-auth/client/plugins';
import { createAuthClient } from 'better-auth/svelte';

/** Browser client for researcher passkeys and participant credentials. */
export const authClient = createAuthClient({
  plugins: [passkeyClient(), usernameClient({ displayUsername: false })]
});
