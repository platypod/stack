<a id="readme-top"></a>


<!-- PROJECT SHIELDS -->
[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]
[![LinkedIn][linkedin-shield]][linkedin-url]



<!-- PROJECT LOGO -->
<br />
<div align="center">
  <a href="https://github.com/Pittinic/platypod">
    <img src="docs/images/logo.png" alt="Logo" width="80" height="80">
  </a>

<h3 align="center">platypod</h3>

  <p align="center">
    Kubernetes-based project packaging numerous miscellaneous services ranging from media management to dev and cyber tools, fully instrumented for observability.
    <br />
    <a href="https://github.com/Pittinic/platypod"><strong>Explore the docs »</strong></a>
    <br />
    <br />
    <a href="https://github.com/Pittinic/platypod">View Demo</a>
    ·
    <a href="https://github.com/Pittinic/platypod/issues/new?labels=bug&template=bug-report---.md">Report Bug</a>
    ·
    <a href="https://github.com/Pittinic/platypod/issues/new?labels=enhancement&template=feature-request---.md">Request Feature</a>
  </p>
</div>



<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#built-with">Built With</a></li>
      </ul>
      <ul>
        <li><a href="#modules">Modules</a></li>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li>
      <a href="#user-guide">User Guide</a>
      <ul>
        <li><a href="#configuration">Configuration</a></li>
        <li><a href="#deployment">Deployment</a></li>
        <li><a href="#usage">Usage</a></li>
      </ul>
    </li>
    <li><a href="docs/README.md">Documentation</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>



<!-- ABOUT THE PROJECT -->
## About The Project

[![Platypod][product-screenshot]](https://platypodemo.com)

- For a list of the current features, see the <a href="#roadmap">Roadmap</a>.

- This project serves two purposes:
  - offering **free, convenient features on a home or cloud server** (as long as the electricity bills are paid).
  - giving a pretense for **practising with some technologies** and tools, as well as **packaging a documented demonstration** for those.

- The core technologies are Kubernetes and Traefik:
  - **Kubernetes** manages every service's configuration and virtualisation.
  - **Traefik** exposes every service behind a reverse proxy.
  - Other than that, each feature is offered by a distinctive technology, explained and documented in a dedicated file in each module's own folder.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Built With

[![Kubernetes][Kubernetes]][Kubernetes-url]
[![Traefik][Traefik]][Traefik-url]
[![LetsEncrypt][LetsEncrypt]][LetsEncrypt-url]
[![Homepage][Homepage]][Homepage-url]

[![Authelia][Authelia]][Authelia-url]
[![AdGuardHome][AdGuardHome]][AdGuardHome-url]
[![LLDAP][LLDAP]][LLDAP-url]

[![OpenTelemetryCollector][OpenTelemetryCollector]][OpenTelemetryCollector-url]
[![Grafana][Grafana]][Grafana-url]
[![Loki][Loki]][Loki-url]
[![Tempo][Tempo]][Tempo-url]
[![VictoriaMetrics][VictoriaMetrics]][VictoriaMetrics-url]

[![Bookstack][Bookstack]][Bookstack-url]
[![CyberChef][CyberChef]][CyberChef-url]
[![DBeaver][DBeaver]][DBeaver-url]
[![ItTools][ItTools]][ItTools-url]
[![MariaDB][MariaDB]][MariaDB-url]
[![PostgreSQL][PostgreSQL]][PostgreSQL-url]
[![Vaultwarden][Vaultwarden]][Vaultwarden-url]
[![WhoAmI][WhoAmI]][WhoAmI-url]

[![Deluge][Deluge]][Deluge-url]
[![QBitTorrent][QBitTorrent]][QBitTorrent-url]
[![Transmission][Transmission]][Transmission-url]

[![Bazarr][Bazarr]][Bazarr-url]
[![FlareSolverr][FlareSolverr]][FlareSolverr-url]
[![Jellyfin][Jellyfin]][Jellyfin-url]
[![JellySeerr][JellySeerr]][JellySeerr-url]
[![Prowlarr][Prowlarr]][Prowlarr-url]
[![Radarr][Radarr]][Radarr-url]
[![Readarr][Readarr]][Readarr-url]
[![Sonarr][Sonarr]][Sonarr-url]

[![RommApp][RommApp]][RommApp-url]
[![Pokeclicker][Pokeclicker]][Pokeclicker-url]
[![Sphaze][Sphaze]][Sphaze-url]

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- MODULES -->
### Modules

The features are packaged in modules by thematics as follows:
- [Persistence](src/persistence)
- [Core](src/core)
- [Security](src/security)
- [Observability](src/observability)
- [Dev Tools](src/dev-tools)
- [Files](src/files)
- [Media](src/media)
- [Games](src/games)

Each link redirects to the module's subfolder, which includes a detailed README.md file.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- GETTING STARTED -->
## Getting Started

To get a copy up and running, follow these steps.

<p align="right">(<a href="#readme-top">back to top</a>)</p>


### Prerequisites

1. A running Kubernetes cluster. This project uses [Talos Linux](https://www.talos.dev/) VMs provisioned via Terraform — see [`infra/`](../infra/README.md) for the full setup.
2. Install the required tools (helm, helmfile, kubectl, helm-diff):
    ```bash
    make install-deps
    ```
3. Install [Traefik's CRDs](https://doc.traefik.io/traefik/providers/kubernetes-crd/) on the cluster:
    ```bash
    make install-crds          # dev
    make install-crds ENV=prd  # prod
    ```
4. If using NFS storage (prod), install the CSI driver on the cluster:
    ```bash
    curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/v4.5.0/deploy/install-driver.sh | bash -s v4.5.0 --
    ```
5. Install [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git) to be able to clone the repo.

<p align="right">(<a href="#readme-top">back to top</a>)</p>


### Installation

1. Clone the repo
   ```sh
   git clone https://github.com/Pittinic/platypod.git
   ```
2. Remove git remote url to avoid accidental pushes to base project,
unless you know what you're doing and you plan on contributing
and/or keeping up with updates, of course.
   ```sh
   git remote rm origin
   ```
3. Customize whatever you wish to your heart's content.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- USER GUIDE -->
## User Guide

The project is meant to be driven from code, namely by editing yaml files.

Some convenience scripts are provided in the bin folder to handle deployment.
They rely on Bash, Helm and a couple other commands I shall list to ensure they are installed before running.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Configuration
1. Create a folder **values/\<env\>**.
2. Inside this folder, create a **values.yaml** file.
3. **Overwrite** whatever configuration you'll like.

Examples are provided in fake "[dev](values/dev)" and "[prd](values/prd)" environments in this repository.

Please mind the storage provisionning: default features are offered and detailed in the
[persistence module](src/00-persistence), but may be deactivated and replaced with existing
[Persistent Volume Claims](https://kubernetes.io/docs/concepts/storage/persistent-volumes/).

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Deployment

**First-time dev setup** (one-shot):
```bash
make setup-dev
```
This runs in order: mkcert CA trust + wildcard TLS secret, Traefik CRDs, core module deploy, dnsmasq configuration. Requires a running dev cluster (`make apply ENV=dev` in `infra/`).

**Deploy the full stack:**
```bash
make deploy              # dev
make deploy ENV=prd      # prod
```

**Deploy or redeploy a single module:**
```bash
make deploy MODULE=core
make deploy MODULE=security
# ...
```

**Other useful commands:**
```bash
make diff MODULE=core    # dry-run: show what would change
make destroy MODULE=core # uninstall a single module
make status              # list deployed releases and their status
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Usage

All services are exposed via Traefik and protected by Authelia SSO. Start from the homepage:

| Environment | URL |
|-------------|-----|
| dev | https://homepage.platypod.local/ |
| prod | https://homepage.platypod.ovh/ |

Log in with your Authelia credentials. The homepage lists all available services with links.

To list all exposed URLs directly:
```bash
kubectl get ingressroutes --namespace <namespace>
```

#### Dev — accessing persistent volume data

Talos nodes have no SSH. Use `talosctl` to browse and transfer files on the worker node:

```bash
export TALOSCONFIG=../infra/.generated/dev/talosconfig

# Browse
talosctl -n 192.168.122.102 ls /var/local/platypod/volumes/

# Read a file
talosctl -n 192.168.122.102 read /var/local/platypod/volumes/apps/some-file

# Copy from node to local machine
talosctl -n 192.168.122.102 cp /var/local/platypod/volumes/apps/some-file ./some-file

# Copy from local machine to node
talosctl -n 192.168.122.102 cp ./some-file /var/local/platypod/volumes/apps/some-file
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- ROADMAP -->
## Roadmap

- Core services
  - [x] **Traefik** (*reverse-proxy*)
  - [x] **Let's Encrypt** (*tls/https*)
  - [x] **Homepage** -> *home-page*
- Security
  - [x] **Adguard** -> *DNS-sinkhole*
  - [x] **Authelia** -> *SSO*
  - [x] **LLDAP** -> *LDAP / RBAC*
- Observability
  - [x] **OtelCollector** -> *collector*
  - [x] **Loki** -> *logs*
  - [x] **Tempo** -> *traces*
  - [x] **Mimir** -> *metrics* (en remplacement de VictoriaMetrics)
  - [x] **Uptime-Kuma** -> *uptime-monitoring*
  - [x] **Grafana** -> *dashboards*
- Dev
  - [x] **Bookstack** -> *documentation-space*
  - [x] **CyberChef** -> *data-transformation*
  - [x] **DBeaver** -> *database-interface*
  - [x] **IT-Tools** -> *various-tools*
  - [x] **Outline** -> *wiki*
  - [x] **Vaultwarden** -> *password-manager*
  - [x] **Wiki.js** -> *wiki*
  - [x] **WhoAmI** -> *testing-tool*
  - [ ] **Airflow** -> *orchestrator*
  - [ ] **OpenMetadata** or **DataHub** -> *metadata*
- Download
  - [x] **Transmission** -> *torrent*
  - [x] **QBitTorrent** -> *torrent*
  - [x] **Deluge** -> *torrent*
  - [ ] **SABnzbd** -> *usenet-download*
- Media
  - [x] **Jellyfin** -> *streaming*
  - [x] **Prowlarr** -> *indexer*
  - [x] **Radarr** -> *movies*
  - [x] **Sonarr** -> *series*
  - [x] **Readarr** -> *books*
  - [x] **Bazarr** -> *subtitles*
  - [x] **Jellyseerr** -> *requester*
  - [x] **Kavita** -> *comic/book/manga-reader* (remplace Komga)
  - [x] **Suwayomi** -> *manga-downloader* (alimente Kavita)
  - [x] **Tdarr** -> *hardware-transcoding*
  - [x] **Flaresolverr** -> *cloudflare*
  - [ ] **Invidious** -> *youtube*
  - [ ] **SftpGo** -> *files*
- Games
  - [x] **RommApp** -> *consoles-emulator*
  - [x] **Pokeclicker** -> *idle-game*
  - [ ] **Minecraft** -> *cubes*
- Home
  - [ ] **HomeAssistant** -> *automation*
  - [ ] **HomeBridge** -> *homekit*
- To think about
  - [ ] Global 404 page?
  - [x] Write documentations for each service specificities -> see [`docs/`](docs/README.md) and per-module `src/<module>/README.md`

See the [open issues](https://github.com/Pittinic/platypod/issues) for a full list of proposed features (and known issues).

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- CONTRIBUTING -->
## Contributing

Contributions are welcomed, either as issues tagged "enhancement" or pull requests. Ideally, please follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/#summary) standards.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feat/<feature>`)
3. Commit your Changes (`git commit -m '<type>[optional scope]: <description>'`)
4. Push to the Branch (`git push origin feat/<feature>`)
5. Open a Pull Request

<p align="right">(<a href="#readme-top">back to top</a>)</p>


### Top contributors:

![Alt](https://repobeats.axiom.co/api/embed/3d9d54b9dfdd2cf4d9ed9e36d9192e1ba4249493.svg "Repobeats analytics image")


<!-- LICENSE -->
## License

Distributed under the MIT License. See `LICENSE.txt` for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- CONTACT -->
## Contact

Project Link: [https://github.com/Pittinic/platypod](https://github.com/Pittinic/platypod)

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- ACKNOWLEDGMENTS -->
## Acknowledgments

* [Talos Linux](https://www.talos.dev/) for a clean, immutable Kubernetes OS.
* [vfkit](https://github.com/crc-org/vfkit) and [socket_vmnet](https://github.com/lima-vm/socket_vmnet) for lightweight macOS virtualisation.
* [mkcert](https://github.com/FiloSottile/mkcert) for zero-friction local TLS.

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->
[contributors-shield]: https://img.shields.io/github/contributors/Pittinic/platypod.svg?style=for-the-badge
[contributors-url]: https://github.com/Pittinic/platypod/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/Pittinic/platypod.svg?style=for-the-badge
[forks-url]: https://github.com/Pittinic/platypod/network/members
[stars-shield]: https://img.shields.io/github/stars/Pittinic/platypod.svg?style=for-the-badge
[stars-url]: https://github.com/Pittinic/platypod/stargazers
[issues-shield]: https://img.shields.io/github/issues/Pittinic/platypod.svg?style=for-the-badge
[issues-url]: https://github.com/Pittinic/platypod/issues
[license-shield]: https://img.shields.io/github/license/Pittinic/platypod.svg?style=for-the-badge
[license-url]: https://github.com/Pittinic/platypod/blob/master/LICENSE.txt
[linkedin-shield]: https://img.shields.io/badge/-LinkedIn-black.svg?style=for-the-badge&logo=linkedin&colorB=555
[linkedin-url]: https://linkedin.com/in/nicolas-pittion-rossillon-947534166
[product-screenshot]: docs/images/demo.gif
[Kubernetes]: https://img.shields.io/badge/kubernetes-%23326CE5?style=for-the-badge&logo=kubernetes&logoColor=FFFFFF
[Kubernetes-url]: https://kubernetes.io/
[Traefik]: https://img.shields.io/badge/traefik-%2324A1C1?style=for-the-badge&logo=traefikproxy&logoColor=FFFFFF
[Traefik-url]: https://doc.traefik.io/traefik/
[LetsEncrypt]: https://img.shields.io/badge/letsencrypt-%23003A70?style=for-the-badge&logo=letsencrypt&logoColor=FFFFFF
[LetsEncrypt-url]: https://letsencrypt.org/docs/
[Homepage]: https://img.shields.io/badge/homepage-%23009BD5?style=for-the-badge&logo=homepage&logoColor=FFFFFF
[Homepage-url]: https://github.com/gethomepage/homepage
[Authelia]: https://img.shields.io/badge/authelia-%23113155?style=for-the-badge&logo=authelia&logoColor=FFFFFF
[Authelia-url]: https://github.com/authelia/authelia
[AdGuardHome]: https://img.shields.io/badge/adguard-%2368BC71?style=for-the-badge&logo=adguard&logoColor=FFFFFF
[AdGuardHome-url]: https://github.com/AdguardTeam/AdGuardHome
[LLDAP]: https://img.shields.io/badge/lldap-%23326CE5?style=for-the-badge&logoColor=FFFFFF
[LLDAP-url]: https://github.com/lldap/lldap
[OpenTelemetryCollector]: https://img.shields.io/badge/opentelemetry-%23FFFFFF?style=for-the-badge&logo=opentelemetry&logoColor=000000
[OpenTelemetryCollector-url]: https://github.com/open-telemetry/opentelemetry-collector-contrib
[Grafana]: https://img.shields.io/badge/grafana-%23F46800?style=for-the-badge&logo=grafana&logoColor=FFFFFF
[Grafana-url]: https://github.com/grafana/grafana
[Loki]: https://img.shields.io/badge/loki-%23F46800?style=for-the-badge&logo=grafana&logoColor=FFFFFF
[Loki-url]: https://github.com/grafana/loki
[Tempo]: https://img.shields.io/badge/tempo-%23F46800?style=for-the-badge&logo=grafana&logoColor=FFFFFF
[Tempo-url]: https://github.com/grafana/tempo
[VictoriaMetrics]: https://img.shields.io/badge/victoria_metrics-%23621773?style=for-the-badge&logo=victoriametrics&logoColor=FFFFFF
[VictoriaMetrics-url]: https://github.com/VictoriaMetrics/VictoriaMetrics
[Bookstack]: https://img.shields.io/badge/bookstack-%230288D1?style=for-the-badge&logo=bookstack&logoColor=FFFFFF
[Bookstack-url]: https://github.com/BookStackApp/BookStack
[CyberChef]: https://img.shields.io/badge/cyberchef-%23333333?style=for-the-badge&logoColor=FFFFFF
[CyberChef-url]: https://github.com/gchq/CyberChef
[DBeaver]: https://img.shields.io/badge/dbeaver-%23382923?style=for-the-badge&logo=dbeaver&logoColor=FFFFFF
[DBeaver-url]: https://github.com/dbeaver/dbeaver
[Vaultwarden]: https://img.shields.io/badge/vaultwarden-%23175DDC?style=for-the-badge&logo=bitwarden&logoColor=FFFFFF
[Vaultwarden-url]: https://github.com/dani-garcia/vaultwarden
[ItTools]: https://img.shields.io/badge/it_tools-%23336644?style=for-the-badge
[ItTools-url]: https://github.com/CorentinTh/it-tools
[MariaDB]: https://img.shields.io/badge/mariadb-%23003545?style=for-the-badge&logo=mariadb&logoColor=FFFFFF
[MariaDB-url]: https://github.com/mariadb
[PostgreSQL]: https://img.shields.io/badge/postgresql-%234169E1?style=for-the-badge&logo=postgresql&logoColor=FFFFFF
[PostgreSQL-url]: https://github.com/postgres/postgres
[WhoAmI]: https://img.shields.io/badge/whoami-%2324A1C1?style=for-the-badge&logo=traefikproxy&logoColor=FFFFFF
[WhoAmI-url]: https://github.com/traefik/whoami
[Deluge]: https://img.shields.io/badge/deluge-%23094491?style=for-the-badge&logo=deluge&logoColor=FFFFFF
[Deluge-url]: https://github.com/deluge-torrent/deluge
[QBitTorrent]: https://img.shields.io/badge/qbittorrent-%232F67BA?style=for-the-badge&logo=qbittorrent&logoColor=FFFFFF
[QBitTorrent-url]: https://github.com/qbittorrent/qBittorrent
[Transmission]: https://img.shields.io/badge/transmission-%23D70008?style=for-the-badge&logo=transmission&logoColor=FFFFFF
[Transmission-url]: https://github.com/transmission/transmission
[Bazarr]: https://img.shields.io/badge/bazarr-%23DA3B8A?style=for-the-badge&logo=linuxserver&logoColor=FFFFFF
[Bazarr-url]: https://docs.linuxserver.io/images/docker-bazarr/
[FlareSolverr]: https://img.shields.io/badge/flaresolverr-%23888888?style=for-the-badge
[FlareSolverr-url]: https://github.com/FlareSolverr/FlareSolverr
[Jellyfin]: https://img.shields.io/badge/jellyfin-%2300A4DC?style=for-the-badge&logo=jellyfin&logoColor=FFFFFF
[Jellyfin-url]: https://github.com/jellyfin/jellyfin
[JellySeerr]: https://img.shields.io/badge/jellyseerr-%239955BB?style=for-the-badge
[JellySeerr-url]: https://github.com/fallenbagel/jellyseerr
[Prowlarr]: https://img.shields.io/badge/prowlarr-%23DA3B8A?style=for-the-badge&logo=linuxserver&logoColor=FFFFFF
[Prowlarr-url]: https://docs.linuxserver.io/images/docker-prowlarr/
[Radarr]: https://img.shields.io/badge/radarr-%23FFCB3D?style=for-the-badge&logo=radarr&logoColor=FFFFFF
[Radarr-url]: https://docs.linuxserver.io/images/docker-radarr/
[Readarr]: https://img.shields.io/badge/readarr-%23DA3B8A?style=for-the-badge&logo=linuxserver&logoColor=FFFFFF
[Readarr-url]: https://docs.linuxserver.io/images/docker-readarr/
[Sonarr]: https://img.shields.io/badge/sonarr-%232596BE?style=for-the-badge&logo=sonarr&logoColor=FFFFFF
[Sonarr-url]: https://docs.linuxserver.io/images/docker-sonarr/
[Tdarr]: https://img.shields.io/badge/tdarr-%23888888?style=for-the-badge
[Tdarr-url]: https://github.com/HaveAGitGat/Tdarr
[RommApp]: https://img.shields.io/badge/rommapp-%23888888?style=for-the-badge
[RommApp-url]: https://github.com/rommapp/romm
[Pokeclicker]: https://img.shields.io/badge/pokeclicker-%23CC0000?style=for-the-badge&logoColor=FFFFFF
[Pokeclicker-url]: https://github.com/pokeclicker/pokeclicker
[Sphaze]: https://img.shields.io/badge/sphaze-%23AA8855?style=for-the-badge
[Sphaze-url]: https://github.com/platypod/sphaze
