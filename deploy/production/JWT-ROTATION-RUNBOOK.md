# JWT signing-key rotation

WarpTalk signs new access tokens with `JWT_SECRET`. All .NET APIs also accept
the semicolon-separated keys in `JWT_PREVIOUS_SECRETS`, which permits a
zero-downtime symmetric-key rotation.

1. Generate a new random key of at least 64 characters.
2. Set `JWT_PREVIOUS_SECRETS` to the current `JWT_SECRET`. Keep any still-live
   previous key after it, separated by `;`.
3. Replace `JWT_SECRET` with the new key on every App VM.
4. Redeploy all .NET services and the gateway in one release.
5. Verify a newly issued token and a token issued immediately before rotation.
6. Wait longer than the maximum access-token lifetime plus the 30-second clock
   skew. Refresh tokens are opaque, hashed, and unaffected.
7. Remove the expired key from `JWT_PREVIOUS_SECRETS` and redeploy.

Never rotate only Auth: validators and the issuer must receive the same key set.
The application rejects placeholder or shorter-than-32-character previous
keys. If a signing key is suspected compromised, revoke refresh-token families,
rotate immediately, and remove the compromised key without the overlap window.
