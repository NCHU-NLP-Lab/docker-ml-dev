#!/usr/bin/env bash
# CPU/service integration test, runnable on an ARM64 Docker host without a GPU.
# Creates and removes ONLY a uniquely named test container and test volume.
set -Eeuo pipefail
image=${1:-ml-dev:dgx-spark-pytorch26.10}
container="ml-dev-spark-test-$$"
volume="${container}-data"
cleanup() {
    docker rm -f "${container}" >/dev/null 2>&1 || true
    docker volume rm "${volume}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run --rm --no-healthcheck "${image}" python -c \
    'import platform, torch; assert platform.machine() == "aarch64"; print(torch.__version__, torch.version.cuda)'
docker volume create "${volume}" >/dev/null
docker run -d --name "${container}" --mount "type=volume,src=${volume},dst=/user_data" \
    -e NAME=sparktest -e 'PASSWORD=test-only-$literal;not-a-command' \
    -e USER_UID=20001 -e USER_GID=20001 -e ENABLE_SUDO=0 \
    -e SSH_PORT=22001 -e JUPYTER_PORT=22002 -e VSCODE_PORT=22003 "${image}" >/dev/null

wait_healthy() {
    for ((attempt=0; attempt<90; attempt++)); do
        if docker exec "${container}" python /usr/local/bin/ml-dev-healthcheck >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    docker logs "${container}"
    return 1
}
wait_healthy
test "$(docker exec "${container}" id -u sparktest)" = 20001
docker exec -i "${container}" python - <<'PY'
import os
import urllib.error
import urllib.request

url = "http://127.0.0.1:22002/api/contents"
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
try:
    opener.open(url, timeout=5)
except urllib.error.HTTPError as error:
    assert error.code in (401, 403), error.code
else:
    raise AssertionError("Jupyter allowed unauthenticated contents access")
request = urllib.request.Request(url, headers={"Authorization": "token " + os.environ["PASSWORD"]})
with opener.open(request, timeout=5) as response:
    assert response.status == 200
PY
docker exec -u sparktest "${container}" sh -c 'printf persistent > /user_data/restart-test'
host_key=$(docker exec "${container}" ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub)
docker restart "${container}" >/dev/null
wait_healthy
test "$(docker exec -u sparktest "${container}" cat /user_data/restart-test)" = persistent
test "$(docker exec "${container}" ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub)" = "${host_key}"
# Authenticate against the container's sshd as the researcher; no Docker socket
# is exposed. A temporary in-container key also checks non-root SSH access.
docker exec -u sparktest "${container}" bash -c '
    mkdir -p /user_data/.ssh && chmod 700 /user_data/.ssh
    ssh-keygen -q -t ed25519 -N "" -f /user_data/.ssh/test_key
    cp /user_data/.ssh/test_key.pub /user_data/.ssh/authorized_keys
    chmod 600 /user_data/.ssh/authorized_keys
    ssh-keyscan -p 22001 127.0.0.1 > /user_data/.ssh/known_hosts
    ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -p 22001 \
        -i /user_data/.ssh/test_key sparktest@127.0.0.1 "test \$(id -u) = 20001"
'
docker stop --time 20 "${container}" >/dev/null
test "$(docker inspect -f '{{.State.ExitCode}}' "${container}")" = 0
echo 'ARM64 imports, services, custom ports, UID, persistence, restart, SSH and graceful stop passed.'
