# Damn Vulnerable DeFi

This repository contains **my personal solution to the Damn Vulnerable DeFi challenges**.  
The code is free to use, learn from, and modify.  
Feel free to take ideas, experiment, and adapt it to your own projects or studies.

## Install

1. Clone the repository.
2. Checkout the latest release (for example, `git checkout v4.1.0`)
3. Rename the `.env.sample` file to `.env` and add a valid RPC URL. This is only needed for the challenges that fork mainnet state.
4. Either install [Foundry](https://book.getfoundry.sh/getting-started/installation), or use the [provided devcontainer](./.devcontainer/) (In VSCode, open the repository as a devcontainer with the command "Devcontainer: Open Folder in Container...")
5. Run `forge build` to initialize the project.

## Usage

Each challenge is made up of:

- A prompt located in `src/<challenge-name>/README.md`.
- A set of contracts located in `src/<challenge-name>/`.
- A [Foundry test](https://book.getfoundry.sh/forge/tests) located in `test/<challenge-name>/<ChallengeName>.t.sol`.


## Disclaimer

All code, practices and patterns in this repository are DAMN VULNERABLE and for educational purposes only.

DO NOT USE IN PRODUCTION.
