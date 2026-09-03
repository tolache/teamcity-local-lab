# TeamCity Local Lab

A minimal TeamCity lab in Docker Compose, running entirely on your machine: PostgreSQL, TeamCity server, and agent.

> [!CAUTION]
> **Lab only - never run this in production.** Throwaway credentials, ports open on `0.0.0.0`.

## Start

1. Adjust values in `.env` if needed.
2. Start the Docker Compose project:
    ```shell
    docker compose up -d
    ```

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
