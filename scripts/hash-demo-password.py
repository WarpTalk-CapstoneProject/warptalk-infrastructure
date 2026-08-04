#!/usr/bin/env python3
"""
Produce a WarpTalk password hash in the format PasswordHasher.Verify expects.

Mirrors warptalk-backend/auth/src/WarpTalk.AuthService.Infrastructure/Security/PasswordHasher.cs
with the defaults from PasswordHasherSettings.cs:
    PBKDF2 / SHA512, 100_000 iterations, 16-byte salt, 32-byte hash
    Format: v2$SHA512$100000$16$<saltBase64>$<hashBase64>

The password is read from a prompt (never echoed, never stored in shell history
and never written to a file). Run it once and paste the printed hash into the
seed script.

    python3 hash-demo-password.py
"""
import base64
import getpass
import hashlib
import os
import sys

SALT_SIZE = 16
HASH_SIZE = 32
ITERATIONS = 100_000
ALGORITHM = "SHA512"
VERSION_PREFIX = "v2"


def hash_password(password: str) -> str:
    salt = os.urandom(SALT_SIZE)
    digest = hashlib.pbkdf2_hmac("sha512", password.encode("utf-8"), salt, ITERATIONS, HASH_SIZE)
    return (
        f"{VERSION_PREFIX}${ALGORITHM}${ITERATIONS}${SALT_SIZE}$"
        f"{base64.b64encode(salt).decode()}${base64.b64encode(digest).decode()}"
    )


def main() -> int:
    password = getpass.getpass("Demo password: ")
    if not password:
        print("Password must not be empty.", file=sys.stderr)
        return 1
    if password != getpass.getpass("Confirm: "):
        print("Passwords do not match.", file=sys.stderr)
        return 1

    # Self-check: re-derive with the parsed parameters, the same way Verify does.
    encoded = hash_password(password)
    prefix, algorithm, iterations, salt_size, salt_b64, hash_b64 = encoded.split("$")
    recomputed = hashlib.pbkdf2_hmac(
        algorithm.lower(),
        password.encode("utf-8"),
        base64.b64decode(salt_b64),
        int(iterations),
        len(base64.b64decode(hash_b64)),
    )
    assert recomputed == base64.b64decode(hash_b64), "self-check failed"

    print()
    print(encoded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
