# LiteLLM

This directory mirrors the lightweight `cpa/` layout:

- `get-litellm.sh`: install or upgrade LiteLLM proxy CLI with `uv`
- `run.sh`: start LiteLLM with the local `config.yaml`
- `stop.sh`: stop all running LiteLLM CLI processes
- `config.yaml`: minimal proxy config with hardcoded upstream settings

## Prerequisites

- `uv`
- `litellm[proxy]` installed via `./get-litellm.sh`

## Usage

```bash
./get-litellm.sh
./run.sh --detailed_debug
./stop.sh
```

Default bind address is `0.0.0.0:4000`.

The hardcoded LiteLLM master key is `sk-1234`.

Override with environment variables if needed:

```bash
HOST=127.0.0.1 PORT=4010 ./run.sh
```
