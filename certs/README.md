# Lab TLS material

This directory holds the TLS material the lab needs. **Nothing here is committed** except this file - you generate your own from your own local [mkcert](https://github.com/FiloSottile/mkcert) CA.

| File                            | Used by                                                                                                                                                                       |
|---------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `docker-host-mkcert-rootCA.crt` | Baked into the `tolache/teamcity-server` and `tolache/teamcity-agent` images, into both the OS trust store and the JVM `cacerts`, so TeamCity trusts the lab's TLS endpoints. |
| `nginx.pem` / `nginx-key.pem`   | Served by nginx, which terminates TLS for the MinIO console (9001), the MinIO S3 API (9000), the Garage S3 API (3900), and LDAPS (636).                                       |

## Setting them up

- macOS / Linux: `./scripts/setup-certs.sh`
- Windows: `pwsh ./scripts/setup-certs.ps1`

Re-running is a no-op. Pass `--force` (or `-Force`) to re-mint regardless. The certificate is re-minted automatically when it is within 30 days of expiry, when your mkcert CA has changed, or when the script's list of hostnames has changed.

If these files are missing, `docker compose build` and `docker compose up` both fail immediately with a message pointing back at the scripts above.
