# WPA-Sec-Windows-Docker

WPA-Sec help_crack.py running in Docker with NVIDIA GPU (CUDA).

## Prereqs
- Windows with Docker Desktop + WSL2 backend
- NVIDIA GPU drivers installed on Windows
- NVIDIA Container Toolkit enabled for WSL2 Docker (see below)
- Docker Desktop WSL integration enabled for your distro (Settings > Resources > WSL Integration)

## Install NVIDIA Container Toolkit (WSL2)
Run these in your WSL distro (Ubuntu, Debian, etc.), not in PowerShell.

```
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /etc/apt/keyrings/nvidia-container-toolkit.gpg
sudo chmod a+r /etc/apt/keyrings/nvidia-container-toolkit.gpg

distribution=$(. /etc/os-release; echo ${ID}${VERSION_ID})
curl -fsSL https://nvidia.github.io/libnvidia-container/${distribution}/libnvidia-container.list \
  | sed 's#deb https://#deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# If you get a 404 above, set distribution manually.
# Examples:
# - Ubuntu 22.04: distribution=ubuntu22.04
# - Debian 11:    distribution=debian11
# Debian 13 (trixie) is not published yet; use debian11 for now.
#
# If the non-"stable" URL 404s, use the stable path:
# curl -fsSL https://nvidia.github.io/libnvidia-container/stable/debian11/libnvidia-container.list \
#   | sed 's#deb https://#deb [signed-by=/etc/apt/keyrings/nvidia-container-toolkit.gpg] https://#g' \
#   | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

If `systemctl` is not available in your WSL distro:

```
sudo service docker restart
```

If you see `Failed to restart docker.service: Unit docker.service not found.`, just restart Docker Desktop and run:

```
wsl --shutdown
```

Then in PowerShell:

```
wsl --shutdown
```

Reopen WSL and verify:

```
nvidia-container-cli -V
docker info | grep -i nvidia
```

## Quick start
1) Put the project in a folder and create a work dir:

```
mkdir work
```

2) Build the image:

```
docker compose build
```

3) Run the client:

```
docker compose run --rm wpa-sec -co="--backend-ignore-opencl"
```

The script downloads dictionaries and writes results into `./work`.

## Optional checks
Verify GPU access inside the container:

```
docker compose run --rm --entrypoint nvidia-smi wpa-sec
```

Verify OpenCL visibility (may be 0 on WSL2):

```
docker compose run --rm --entrypoint clinfo wpa-sec
```

Verify hashcat CUDA backend:

```
docker compose run --rm --entrypoint hashcat wpa-sec -I
```

## Local crack (pcap/pcapng)
Put your capture files in `./local` and make sure you have wordlists in `./work`.
The script converts captures to `*.22000` and runs hashcat over all wordlists in `./work`.
If you add `.rule` files in `./local/rules`, they will be applied automatically.
Resume/potfile are stored in `./local` (`potfile.txt`, `hashcat.restore`).
Use resume after interruption (restores the last session, then continues with remaining lists):

```
run_local.cmd --restore
```
or:

```
run_local.cmd --resume
```

PowerShell:

```
.\run_local.ps1
```

CMD:

```
run_local.cmd
```

Add hashcat options if needed (do not pass `-m` or backend flags):

```
.\run_local.ps1 -ArgsLine "-O --session local"
```

Optimized kernels shortcut:

```
run_local.cmd --optimized
```

Limit candidate length (e.g., max 16 chars) and enable optimized kernels:

```
run_local.cmd -O --pw-max 16
```

Quiet mode (minimal output):

```
run_local.cmd --quiet
```

Quiet mode with periodic status (seconds):

```
run_local.cmd --status-timer 30
```

Show per-wordlist counts and estimated time (use with `--speed-khs` for best results):

```
run_local.cmd --show-estimate --speed-khs 1140
```

Estimate total candidates and time (rough, ignores rule expansion):

```
run_local.cmd --estimate
```

Fast estimate (sampling, less accurate):

```
run_local.cmd --estimate-fast
```

You can provide a manual speed override in kH/s:

```
run_local.cmd --estimate --speed-khs 350
```

Estimate only (do not start cracking):

```
run_local.cmd --estimate-fast --speed-khs 350 --estimate-only
```

## Notes
- The container downloads the latest `help_crack.py` on each run and ships with hashcat 7.0.0 (CUDA backend).
- Artifacts are created in the working directory (`./work`): `help_crack.res`, `help_crack.hash`, `help_crack.key`, `help_crack.rules`, downloaded dictionaries (`*.gz`), and `prdict.txt.gz`.
- On WSL2, OpenCL is often unavailable; use CUDA backend with: `-co="--backend-ignore-opencl"`.
- If you see `NVRTC_ERROR_INVALID_OPTION`, update the CUDA base image to a newer tag (RTX 50 series needs CUDA 12.8+).
- Pass extra options to help_crack.py, for example:

```
docker compose run --rm wpa-sec -co="--force"
```
