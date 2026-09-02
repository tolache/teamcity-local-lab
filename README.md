# TeamCity Local Lab

A TeamCity lab in Docker Compose, running entirely on your machine: PostgreSQL, Perforce Helix Core, LDAP. Artifact storage behind NGINX: MinIO, Garage, and a Docker registry.

> [!CAUTION]
> **Lab only - never run this in production.** Throwaway credentials, privileged containers, ports open on `0.0.0.0`.

## First start

1. Install Docker Desktop and sign in. Give it ~10 GB of memory in **Settings** > **Resources** (the whole lab idles around 3 GB, but `TC_HEAP` in `.env` lets TeamCity grow to 5 GB under load - lower both if your machine is tight).
2. In Docker Desktop: **Settings** > **Kubernetes** > enable, cluster provisioning method **kind** > **Apply**.
3. Install mkcert:
   - macOS: `brew install mkcert`
   - Windows: `winget install FiloSottile.mkcert`
   - Ubuntu: `sudo apt install mkcert`
4. Set up certificates (answer the password prompt / trust dialog):
   - macOS / Linux: `./scripts/setup-certs.sh`
   - Windows: `pwsh ./scripts/setup-certs.ps1`
5. Start it (the first run builds three images, so give it a while): `docker compose up -d`
6. While the `teamcity` container is `Waiting`, open [http://localhost:8110](http://localhost:8110) and accept EULA.
7. Confirm `docker compose up -d` exited successfully. The lab is ready to use.

## Daily use

### Start

```shell
docker compose up -d
```

### Stop

```shell
docker compose stop
```

### Upgrade

1. `docker compose stop`
2. Bump `TC_VERSION` in `.env`
3. `docker compose up -d --build teamcity teamcity-agent`
4.  While the `teamcity` container is `Waiting`, go to http://localhost:8110 and upgrade finish the upgrade via UI.

## [Optional] Cloud agents (local Kubernetes)

Adds ephemeral build agents. Kubernetes is just the practical way to get that locally.

1. Optional, for a dedicated namespace:
   ```shell
   kubectl create namespace teamcity-agents
   ```
2. Create a token for TeamCity, and copy the last line of output:
   ```shell
   kubectl create serviceaccount teamcity-local -n default
   kubectl create clusterrolebinding teamcity-local-cluster-admin --clusterrole=cluster-admin --serviceaccount=default:teamcity-local
   kubectl create token teamcity-local -n default --duration=87600h
   ```
3. In TeamCity: **Administration** > **Agents** > **Cloud Profiles** > create a profile of type **Kubernetes** (*not* Kubernetes Executor), and fill in:

   | Field                     | Value                                           |
   |---------------------------|-------------------------------------------------|
   | Kubernetes API server URL | `https://desktop-control-plane:6443`            |
   | Authentication strategy   | Token                                           |
   | Token                     | the output of step 2                            |
   | Kubernetes namespace      | `teamcity-agents`, or leave empty for `default` |
   | Certificate Authority     | leave empty                                     |

4. Click **Add image** and fill in:

   | Field                | Value                                                                 |
   |----------------------|-----------------------------------------------------------------------|
   | Agent image prefix   | anything, e.g. `k8s`                                                  |
   | Pod specification    | Use custom pod template                                               |
   | Pod template content | contents of `services/teamcity/agent/cloud-profile-pod-template.yaml` |
   | Server URL           | `http://teamcity:8111`                                                |

   > [!NOTE]
   > The Server URL is the container port (8111), not the published one, and plain HTTP. It is the same URL the Compose agent uses.

5. **Test connection**, save, then run a build on the new agent.

## URLs and logins

TeamCity and build agents run inside the Docker network, so they use the in-lab address, not `localhost`.

| Service         | From your machine      | From TeamCity / agents | Login                                                                                                     | Notes                                              |
|-----------------|------------------------|------------------------|-----------------------------------------------------------------------------------------------------------|----------------------------------------------------|
| TeamCity        | http://localhost:8110  | `http://teamcity:8111` | your own                                                                                                  |                                                    |
| MinIO S3        | https://localhost:9000 | `https://nginx:9000`   | `minioadmin` / `minioadmin`                                                                               | region `us-west-2`; create a bucket in the console |
| MinIO console   | https://localhost:9001 | -                      | `minioadmin` / `minioadmin`                                                                               |                                                    |
| Garage S3       | https://localhost:3900 | `https://nginx:3900`   | `GK0cc9dc5750022571c8fe1344a7248d69` / `e42f5acd27dc21fe5d9618d57b883b2c20e02f77a378968801f9f1c86838cced` | region `my-custom-region`; bucket `default-bucket` |
| Docker registry | `localhost:4999`       | `https://nginx:4999`   | `teamcity` / `teamcity`                                                                                   |                                                    |
| Perforce        | `localhost:1666`       | `perforce:1666`        | `p4admin` / `SuperSecret123!`                                                                             |                                                    |
| LDAP            | -                      | `ldaps://nginx:636`    | `cn=admin,dc=teamcity,dc=test` / `teamcity`                                                               |                                                    |
| LDAP console    | http://localhost:8090  | -                      | `cn=admin,dc=teamcity,dc=test` / `teamcity`                                                               |                                                    |
| LDAP users      | -                      | -                      | `tc_admin`, `maintainer`, `developer` / `teamcity` for all three                                          |                                                    |
| PostgreSQL      | `localhost:5431`       | `postgres:5432`        | `teamcity` / `teamcity`                                                                                   |                                                    |

## Troubleshooting

| Symptom                                                      | Fix                                                                                 |
|--------------------------------------------------------------|-------------------------------------------------------------------------------------|
| `service "certs-check" didn't complete successfully: exit 1` | Run step 4, then `docker compose up -d` again                                       |
| Build fails: `docker-host-mkcert-rootCA.crt is missing`      | Run step 4                                                                          |
| `network kind declared as external, but could not be found`  | Run step 2, or `docker network create kind`                                         |
| Browser says the certificate is untrusted                    | `mkcert -install`, then fully restart the browser                                   |
| `pull access denied for tolache/teamcity-server`             | Expected - the images are local-only, Compose builds them                           |
| TeamCity can't reach S3                                      | Use `https://nginx:9000`, not `localhost` - it's resolved inside the Docker network |
| Not enough RAM                                               | Adjust `TC_HEAP` / `TC_MEM_LIMIT` in `.env`                                         |

## Notes

- **Certificates** aren't committed - you generate your own. Re-running step 4 is safe; add `--force` (`-Force`) to re-mint.
- **The `tolache/*` images are local-only** and add debugging tools on top of the JetBrains images. The blocks marked `optional tooling` in `services/teamcity/{server,agent}/Dockerfile` are safe to delete.
- **LDAP** is seeded from `services/ldap/ldifs/`. To re-seed: stop, delete `services/ldap/data` and `services/ldap/config`, start again.
- **Ports publish on `0.0.0.0`**. Prefix the `ports:` entries with `127.0.0.1:` if you work on untrusted networks.
