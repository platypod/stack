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
    <img src="images/logo.png" alt="Logo" width="80" height="80">
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
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#installation">Installation</a></li>
      </ul>
    </li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#roadmap">Roadmap</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
    <li><a href="#contact">Contact</a></li>
    <li><a href="#acknowledgments">Acknowledgments</a></li>
  </ol>
</details>



<!-- ABOUT THE PROJECT -->
## About The Project

[![Product Name Screen Shot][product-screenshot]](https://example.com)

- For a list of the current features, see the <a href="#roadmap">Roadmap</a>.

- This project serves two purposes:
  - offering **free, convenient features on a home or cloud server** (as long as the electricity bills are paid).
  - giving a pretense for **practising with some technologies** and tools, as well as **packaging a documented demonstration** for those.

- The core technologies are Kubernetes, Traefik and Pulumi:
  - **Kubernetes** manages every service's configuration and virtualisation.
  - **Traefik** exposes every service behind a reverse proxy.
  - **Pulumi** simplifies the deployment operations.
  - Other than that, each feature is offered by a distinctive technology, explained and documented in a dedicated file in the [doc](https://github.com/Pittinic/platypod/blob/main/doc) folder.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Built With

[![Pulumi][Pulumi]][Pulumi-url]
[![Kubernetes][Kubernetes]][Kubernetes-url]
[![Traefik][Traefik]][Traefik-url]

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- GETTING STARTED -->
## Getting Started

To get a copy up and running, follow these steps.

<p align="right">(<a href="#readme-top">back to top</a>)</p>


### Prerequisites

* Install [kubernetes](https://kubernetes.io/docs/setup/) on your server (be it a single-pod instance for local dev, a massive cloud cluster or anything in-between).
* Install [pulumi](https://www.pulumi.com/docs/iac/download-install/) on your local environment. Pulumi will use a local kubeconfig if available, but can also be explicitly configured as shown [here](https://www.pulumi.com/registry/packages/kubernetes/installation-configuration/).
* Install [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git) to be able to clone the repo in the next step.

<p align="right">(<a href="#readme-top">back to top</a>)</p>


### Installation

1. Clone the repo
   ```sh
   git clone https://github.com/Pittinic/platypod.git
   ```
2. Remove git remote url to avoid accidental pushes to base project
   ```sh
   git remote rm origin
   ```

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- USAGE EXAMPLES -->
## Usage

We will create a [Pulumi stack](https://www.pulumi.com/docs/iac/concepts/stacks/) to create an isolated and configurated instance of a deployment.
1. Create a folder named ***src/<stack-name>***.
2. Customize the variables defined in ***src/base/values/\*.yaml*** however you'd like.
    - Either in a single file or several.
    - Filenames do not matter, only their extension (.yml or .yaml).
    - Whatever you do not redefine will keep its default value.
3. Create an environment variable called `PULUMI_CONFIG_PASSPHRASE` to store your pulumi passphrase.
4. Create your stack by running:
    ```sh
    pulumi stack init <stack-name> [--non-interactive]
    ```
 5. Update your stack by running:
    ```sh
    pulumi up --stack=<stack-name> [--non-interactive --skip-preview]
    ```
    Note that you can refine this step, for instance by adding a commit message to the operation. See [pulumi up](https://www.pulumi.com/docs/iac/cli/commands/pulumi_up/)'s documentation.
 6. Delete the stack to decommission it with:
    ```sh
    pulumi destroy stack=<stack-name>  [--non-interactive --yes]
    pulumi stack rm <stack-name> [--yes]
    ```

<p align="right">(<a href="#readme-top">back to top</a>)</p>



<!-- ROADMAP -->
## Roadmap

- [ ] Core services
  - [x] **Pulumi** -> *deployment*
  - [x] **Traefik** -> *reverse-proxy*
  - [x] **Let's Encrypt** -> *tls/https*
  - [ ] **Homarr** -> *home-page*
- [ ] Security
  - [ ] **Adguard** -> *DNS-sinkhole*
  - [ ] **Authelia** -> *SSO*
  - [ ] **OpenLDAP** -> *RBAC*
  - [ ] **Kalinux** -> *pentest-env*
- [ ] Observability
  - [ ] **Alloy** -> *collector*
  - [ ] **Loki** -> *logs*
  - [ ] **Tempo** -> *traces*
  - [ ] **Prometheus** or **Mimir** -> *metrics*
  - [ ] **Grafana** -> *dashboards*
- [ ] Download
  - [ ] **Transmission** -> *torrent*
  - [ ] **Deluge** -> *torrent*
  - [ ] **Sabnzbd** -> *direct-download*
- [ ] Media
  - [ ] **Jellyfin** -> *streaming*
  - [ ] **Prowlarr** -> *indexer*
  - [ ] **Radarr** -> *movies*
  - [ ] **Sonarr** -> *series*
  - [ ] **Readarr** -> *books*
  - [ ] **Jellyseerr** -> *requester*
  - [ ] **Tdarr** -> *transcoding*
  - [ ] **Flaresolverr** -> *cloudflare*
  - [ ] **Invidious** -> *youtube*
  - [ ] **SftpGo** -> *files*
- [ ] Games
  - [ ] **Minecraft** -> *cubes*
  - [ ] **DockerScorch** -> *dos*
- [ ] Dev
  - [ ] **Airflow** -> *orchestrator*
  - [ ] **OpenMetadata** or **DataHub** -> *metadata*
  - [ ] **Structurizr** -> *c4-model*
- [ ] Home
  - [ ] **HomeAssistant** -> *automation*
  - [ ] **HomeBridge** -> *homekit*
- [ ] To think about
  - [ ] Global 404 page?
  - [ ] Write documentations for each service specificities
  - [ ] Write documentations for common k8s and pulumi commands

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

* [Pulumi Slack Community](https://pulumi-community.slack.com/) for their quick and helpful answers.
* [Orbstack](https://docs.orbstack.dev/) for its ease of use, including on a headless macos setup.

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
[product-screenshot]: images/screenshot.png
[Pulumi]: https://img.shields.io/badge/pulumi-%238A3391?style=for-the-badge&logo=pulumi
[Pulumi-url]: https://www.pulumi.com/
[Kubernetes]: https://img.shields.io/badge/kubernetes-%23326CE5?style=for-the-badge&logo=kubernetes&logoColor=FFFFFF
[Kubernetes-url]: https://kubernetes.io/
[Traefik]: https://img.shields.io/badge/traefik-%2324A1C1?style=for-the-badge&logo=traefikproxy&logoColor=FFFFFF
[Traefik-url]: https://doc.traefik.io/traefik/