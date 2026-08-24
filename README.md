# Introduction

This file is human-written. It provides useful instructions to help people get started.

This project holds the sources necessary for creating a full-on, secure, AWS organization managed through Control Tower and implementing AWS best-practices.

# Other Docs

Additional documentation is available in:

- [AGENTS.md](./AGENTS.md)
- [Architecture](docs/architecture.md)
- [Deployment](docs/deployment.md)
- [Control Tower Design](docs/control-tower-design.md)
- [Identities and Responsibilities](docs/identities_and_responsibilities.md)
- [Identity Center Security](docs/identity_center_security.md)

# Installing Environment

This project leverages `uv` to manage required Python packages. To install UV and set up the project, run:

`./install.sh`

# Config

# Creating the Infra

More details are available in the [Deployment](docs/deployment.md) document.

 ```bash
   ./tf.sh --phase bootstrap --apply
   ./tf.sh --phase identity-center --apply
   ./tf.sh --phase aft --apply
 ```
