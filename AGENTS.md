# AGENTS.md

## Project Context

This repo contains a SvelteKit application (root), and a Haskell application under `compile/`. There is a script in the root directory
to run the Haskell application (`./compile.sh`), which compiles the Haskell code and runs the resulting executable. Upon running the
Haskell application, a JSON descriptor is outputted to `static/`, which is then consumed by the SvelteKit application to render a UI. The Haskell application is responsible for generating the data that the SvelteKit application uses to display information to the user.

## How To Navigate

- The SvelteKit application is located in the root directory, and its source code can be found in the `src/` directory.
- The Haskell application is located in the `compile/` directory, and its source code can be found in the `src/` directory within `compile/`.

## Commands

- To run the Haskell application, use `./compile.sh` from the root directory. This will compile the Haskell code and execute the resulting binary, which generates a JSON file in `static/`.
- To run the SvelteKit application, use `npm run dev` from the root directory. This will start the development server, with hot-reloading.

## Engineering Rules

## Verification

Before finishing:

- If modifying the Haskell application, run `./compile.sh` from the root directory to compile and run the Haskell application.
