# DGX Spark development image

This ARM64 image extends `nvcr.io/nvidia/pytorch:26.10-py3`, listed in
[NVIDIA's DGX Spark collection](https://catalog.ngc.nvidia.com/orgs/nvidia/-/collections/dgx-spark/-/artifacts).
It keeps NVIDIA's Python, PyTorch, CUDA, NCCL and JupyterLab installation and adds
SSH and code-server 4.145.2 (ARM64 release with a pinned SHA-256).
It does not install the old x86 CUDA wheels or replace NVIDIA's torch build.

The [26.10 release notes](https://docs.nvidia.com/deeplearning/frameworks/pytorch-release-notes/rel-26-10.html)
describe Python 3.12, CUDA 13.4.3 and NVIDIA's PyTorch 2.15.0a0 build. This is an
NGC framework build, not a promise of compatibility with packages pinned to an
upstream stable torch release. Check dependencies before installing research frameworks.

**Validation status:** the source and host-only configuration tests can be checked
without Docker. The image still needs a successful ARM64 build, service smoke test,
and actual GB10 CUDA execution before laboratory deployment. Hosted CI has no GB10.

## Build on Spark

Keep DGX OS and its supported NVIDIA driver/Container Toolkit. The host driver
must support this image's CUDA runtime; do not disable NVIDIA's driver requirement
checks. A container does not install or upgrade the host driver.

From the repository root:

```bash
docker buildx build --platform linux/arm64 --load \
  -f image/dgx-spark-pytorch26.10-jupyterlab-vscode.Dockerfile \
  -t ml-dev:dgx-spark-pytorch26.10 image
```

The build intentionally rejects AMD64. `BASE_IMAGE` is an overridable build arg
so a validated NGC digest can be pinned for deployment; changing the base requires
repeating GPU and service tests. No registry digest has been guessed or hardcoded.
NGC authentication may be required by the registry; use `docker login nvcr.io`
with an authorized NGC account if anonymous access is denied.

## Run a persistent development container

Create an administrator-owned `alice.env`, restrict it with `chmod 600 alice.env`,
and set the following values (use a real, strong password, not this placeholder):

```dotenv
NAME=alice
PASSWORD=replace-this-password
```

Do not commit this file. Avoid putting real passwords in command-line arguments.
Docker administrators can still inspect container environment variables.

```bash
docker run -d --name alice --gpus all --shm-size=8g \
  --ulimit memlock=-1 --ulimit stack=67108864 \
  --env-file alice.env \
  --mount type=volume,src=alice,dst=/user_data \
  -p 22001:22 -p 127.0.0.1:28888:8888 -p 127.0.0.1:28080:8080 \
  ml-dev:dgx-spark-pytorch26.10
```

SSH to `alice@<spark-lan-ip>` on port `22001`. For web access, forward host ports
`28888` and `28080` through an authorized management-host SSH connection. A tunnel
through the container's SSH connection instead targets its internal ports `8888`
and `8080`. Jupyter's token and code-server's password are `PASSWORD`.
The web services use HTTP; the example keeps published web ports on host loopback.

`/user_data` is the persistent home when mounted; otherwise the home is
`/home/<NAME>` in the container's writable layer. Save research data on persistent
mounts. Mounting the volume does not automatically make it shared across nodes.

The existing CLI's `NAME`, `PASSWORD`, `/user_data`, and ports 22/8888/8080 are
supported. No TTY is needed to keep services running. Unlike the legacy startup
script, services are supervised, their logs remain visible, and container stop
signals are forwarded. Fail2ban is not run inside this image; access controls and
rate limiting belong on the host. No privileged mode is required.

Optional environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `USER_UID`, `USER_GID` | Automatically allocated | Explicit numeric IDs >=1000; must not conflict with base-image accounts/groups |
| `ENABLE_SUDO` | `1` | Preserve the existing CLI's password-based container sudo; set `0` to disable |
| `SSH_PORT` | `22` | Actual sshd listening port |
| `JUPYTER_PORT` | `8888` | Actual Jupyter listening port, with fallback disabled |
| `VSCODE_PORT` | `8080` | Actual code-server listening port |

All services bind `0.0.0.0` **inside the container**. The documented launch uses
bridge networking. If an administrator opts into host networking, publish flags
are ignored: set unique actual service ports and host firewall rules first.
Setting UID/GID does not configure NFS. For NFS, provision ownership on the server
before starting containers; initialization never recursively changes research data.
Existing volume content with different ownership must be migrated deliberately.
SSH host keys are generated per container and retained across restart; recreating
the container generates new keys.

## Verify before deployment

Host-only checks (no containers or host configuration changes):

```bash
python3 -m unittest discover -s image/tests -v
bash -n image/script_files/spark_start.sh image/tests/smoke_spark.sh
```

On an ARM64 Docker host, the service smoke test creates a uniquely named disposable
test container and volume, and removes only those test resources afterward:

```bash
bash image/tests/smoke_spark.sh ml-dev:dgx-spark-pytorch26.10
```

On the **Spark**, verify GPU access and real kernel execution (not only import):

```bash
docker run --rm --no-healthcheck --gpus all ml-dev:dgx-spark-pytorch26.10 nvidia-smi
docker run --rm -i --no-healthcheck --gpus all ml-dev:dgx-spark-pytorch26.10 python - <<'PY'
import platform
import torch
assert platform.machine() == "aarch64"
assert torch.cuda.is_available()
print("torch:", torch.__version__, "CUDA:", torch.version.cuda)
print("GPU:", torch.cuda.get_device_name(0), "capability:", torch.cuda.get_device_capability(0))
x = torch.ones((256, 256), device="cuda")
y = x @ x
torch.cuda.synchronize()
torch.testing.assert_close(y.cpu(), torch.full((256, 256), 256.0))
print("CUDA matrix multiplication passed")
PY
```

Also run a CUDA calculation in the actual researcher session. For SSH use a login
shell (`bash -lc`) when launching noninteractive commands that need NVIDIA's runtime
PATH/LD_LIBRARY_PATH. GPU memory remains local to each Spark. This image alone does
not configure paired containers, shared Python environments, NFS, RDMA or multi-node
NCCL. Those are separate infrastructure and application validation steps.

## Publish to Docker Hub

The existing server images remain unchanged. The new destination tag is:

```text
nchunlplab/ml-dev:dgx-spark-pytorch26.10-jupyterlab-vscode
```

The Spark job uses the existing **Build and Publish** workflow (`build.yml`).
There is no separate Spark publishing workflow or `publish` checkbox.

1. In repository **Settings → Secrets and variables → Actions**, confirm the existing
   `DOCKER_PASSWORD` secret contains a Docker Hub access token authorized to push to
   `nchunlplab/ml-dev`. Set the Actions **variable** `DOCKERHUB_USERNAME` to the
   token owner's Docker Hub login (defaults to `nchunlplab`, matching the existing
   workflow). If `nchunlplab` is an organization, use an authorized member's login
   here; the image namespace stays `nchunlplab/ml-dev`. Never commit the token.
   A working existing secret does not need to be replaced.
2. Push the reviewed changes to GitHub and merge into `main`. That push automatically
   starts **Build and Publish**: the Spark job builds ARM64, runs its service tests,
   and publishes the new Spark tag if they pass. No manual publishing step is needed.
3. Pull requests targeting `main` build/test without logging in or publishing any
   images. A push only to a feature branch does not publish. The existing monthly
   schedule and manual workflow trigger on `main` also build and publish. As before,
   a push that changes only files matching the workflow's Markdown ignore rule
   does not trigger a build.

GPU validation on an actual Spark is still required; CI's service checks do not
establish GB10 compatibility. The Spark job pushes only the dedicated Spark tag,
never `latest` or an existing CUDA tag. The original image jobs continue publishing
their own tags. Re-publishing replaces the Spark tag; record the pushed digest and
use that digest when deploying both nodes.

NGC images are large: the runner needs space for base layers, the build cache and
the loaded result. If the hosted ARM runner lacks disk space or is unavailable,
set Actions variable `SPARK_BUILD_RUNNER` to the label of a suitably provisioned
ARM64 Linux runner with Docker. Only use a self-hosted runner for trusted code;
this workflow also runs on pull requests targeting `main`. No automatic host cleanup or
host package removal is performed.

Alternatively, after local Spark validation, an authorized administrator can run:

```bash
docker login --username <authorized-docker-hub-user>
docker tag ml-dev:dgx-spark-pytorch26.10 nchunlplab/ml-dev:dgx-spark-pytorch26.10-jupyterlab-vscode
docker push nchunlplab/ml-dev:dgx-spark-pytorch26.10-jupyterlab-vscode
```

The current `ml-docker create` obtains its image list from Docker Hub, so a local
build alone will not appear in that menu. After publication, select this Spark tag.
The legacy tag listing only fetches one page; if the tag is absent, use the explicit
`docker run` above with the published name. CLI tag discovery improvements are
outside this image change. The legacy CLI also prints the supplied password, so
prefer the documented `--env-file` launch until that behavior is fixed.
