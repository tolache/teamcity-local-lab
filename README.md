# TeamCity Local Lab

A minimal TeamCity lab in Docker Compose, running entirely on your machine: PostgreSQL, TeamCity server, and agent.

> [!CAUTION]
> **Lab only - never run this in production.** Throwaway credentials, ports open on `0.0.0.0`.

## Start

1. Adjust values in `.env` if needed.
2. Run:
    ```shell
    docker compose up -d
    ```

## Accept the license agreement (optional)

On first start the setup wizard asks you to accept the
[TeamCity license agreement](https://www.jetbrains.com/legal/docs/teamcity/license/).
To get that out of the way beforehand, run this once before `docker compose up -d`:

```shell
./scripts/accept-eula.sh        # Windows: .\scripts\accept-eula.ps1
```

It prints the agreement link, asks whether you accept, and on `y` creates the
git-ignored `services/teamcity/server/data/config/internal.properties` with
`teamcity.licenseAgreement.accepted=true`. It starts nothing — that is still
`docker compose up -d`. Editing that property by hand does the same thing.

## Stop

```shell
docker compose stop
```

## Upgrade

1. `docker compose stop`
2. Bump `TC_VERSION` in `.env`
3. `docker compose up -d --build teamcity teamcity-agent`
4.  While the `teamcity` container is `Waiting`, go to http://localhost:8111 and upgrade finish the upgrade via UI.

## Delete

```shell
docker compose down
```
