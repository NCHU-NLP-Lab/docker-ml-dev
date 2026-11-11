#!/usr/bin/env bash
set -Eeuo pipefail

fail() { printf 'ml-dev: %s\n' "$*" >&2; exit 1; }

[[ ${NAME:-} =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || fail 'Set NAME to a valid Linux username.'
[[ ${NAME} != root ]] || fail 'NAME must not be root.'
[[ -n ${PASSWORD:-} ]] || fail 'Set a non-empty PASSWORD (prefer --env-file).'
[[ ${PASSWORD} != *$'\n'* && ${PASSWORD} != *$'\r'* ]] || fail 'PASSWORD must not contain newlines.'
[[ ${ENABLE_SUDO:-1} =~ ^[01]$ ]] || fail 'ENABLE_SUDO must be 0 or 1.'

export SSH_PORT=${SSH_PORT:-22} JUPYTER_PORT=${JUPYTER_PORT:-8888} VSCODE_PORT=${VSCODE_PORT:-8080}
for option in SSH_PORT JUPYTER_PORT VSCODE_PORT; do
    value=${!option}
    [[ ${value} =~ ^[1-9][0-9]{0,4}$ ]] && (( value <= 65535 )) || fail "Invalid ${option}."
done
[[ ${SSH_PORT} != "${JUPYTER_PORT}" && ${SSH_PORT} != "${VSCODE_PORT}" && ${JUPYTER_PORT} != "${VSCODE_PORT}" ]] \
    || fail 'SSH, Jupyter and code-server need distinct ports.'
for option in USER_UID USER_GID; do
    value=${!option:-}
    [[ -z ${value} ]] || { [[ ${value} =~ ^[1-9][0-9]{3,8}$ ]] && (( value >= 1000 )); } \
        || fail "${option} must be an integer >= 1000."
done

# Safe validation mode for CI and checking configuration before provisioning.
if [[ ${1:-} == --check-config ]]; then
    exit 0
fi
[[ $# -eq 0 ]] || fail 'Unknown startup argument.'
[[ ${EUID} -eq 0 ]] || fail 'Development services must initialize as root.'

# This marker is container-local, never in a shared user home.
install -d -m 700 /var/lib/ml-dev
if [[ -f /var/lib/ml-dev/username ]]; then
    [[ $(cat /var/lib/ml-dev/username) == "${NAME}" ]] || fail 'Cannot change NAME on an existing container.'
    id "${NAME}" >/dev/null || fail 'The initialized account is missing.'
    [[ -z ${USER_UID:-} || $(id -u "${NAME}") == "${USER_UID}" ]] || fail 'USER_UID differs from the existing account.'
    [[ -z ${USER_GID:-} || $(id -g "${NAME}") == "${USER_GID}" ]] || fail 'USER_GID differs from the existing account.'
else
    ! getent passwd "${NAME}" >/dev/null || fail 'NAME conflicts with an account in the base image.'
    user_options=(-m -s /bin/bash)
    if [[ -n ${USER_UID:-} ]]; then
        ! getent passwd "${USER_UID}" >/dev/null || fail 'USER_UID is already allocated.'
        user_options+=(-u "${USER_UID}")
    fi
    if [[ -n ${USER_GID:-} ]]; then
        ! getent group "${USER_GID}" >/dev/null || fail 'USER_GID is already allocated.'
        groupadd -g "${USER_GID}" "${NAME}"
        user_options+=(-g "${USER_GID}")
    else
        user_options+=(-U)
    fi
    useradd "${user_options[@]}" "${NAME}"
    printf '%s\n' "${NAME}" > /var/lib/ml-dev/username
fi

# Quoted stdin avoids shell evaluation and avoids putting the password in argv.
printf '%s:%s\n' "${NAME}" "${PASSWORD}" | chpasswd
if [[ ${ENABLE_SUDO:-1} == 1 ]]; then
    usermod -aG sudo "${NAME}"
elif id -nG "${NAME}" | tr ' ' '\n' | grep -qx sudo; then
    gpasswd -d "${NAME}" sudo
fi

export ML_DEV_HOME=/home/${NAME}
if [[ -d /user_data ]]; then
    export ML_DEV_HOME=/user_data
    usermod -d "${ML_DEV_HOME}" "${NAME}"
fi
# Only initialize the top-level directory, never recursively chown research data.
# NFS roots must be provisioned with the right ownership on the storage server.
if [[ $(stat -c %u "${ML_DEV_HOME}") == 0 ]]; then
    chown "$(id -u "${NAME}"):$(id -g "${NAME}")" "${ML_DEV_HOME}" \
        || fail 'Provision the home directory ownership on the storage server first.'
fi
runuser -u "${NAME}" -- test -w "${ML_DEV_HOME}" || fail 'The user cannot write the home directory; check UID/GID and mount permissions.'
for file in .bashrc .profile; do
    if [[ ! -e ${ML_DEV_HOME}/${file} ]]; then
        runuser -u "${NAME}" -- cp -n "/etc/skel/${file}" "${ML_DEV_HOME}/${file}"
    fi
done

# Generate separate host keys at runtime, not identical keys baked into images.
install -d -m 755 /run/sshd
install -d -m 700 /run/ml-dev
ssh-keygen -A
cat > /run/ml-dev/sshd_config <<EOF
Port ${SSH_PORT}
ListenAddress 0.0.0.0
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
KbdInteractiveAuthentication no
UsePAM yes
AllowUsers ${NAME}
AllowTcpForwarding yes
X11Forwarding no
Subsystem sftp internal-sftp
PidFile /run/ml-dev/sshd.pid
EOF
/usr/sbin/sshd -t -f /run/ml-dev/sshd_config

# Login shells should use the same NVIDIA runtime paths as Jupyter/code-server.
python - <<'PY'
import os
import shlex
from pathlib import Path
keys = ("PATH", "LD_LIBRARY_PATH", "CUDA_HOME", "CUDA_PATH")
Path("/etc/profile.d/ml-dev-runtime.sh").write_text("\n".join(
    "export " + key + "=" + shlex.quote(os.environ[key])
    for key in keys if key in os.environ
) + "\n")
PY

# Jupyter reads the token from the environment, not a command-line argument.
export JUPYTER_TOKEN=${PASSWORD}
export HOME=${ML_DEV_HOME} USER=${NAME} LOGNAME=${NAME}
cd "${ML_DEV_HOME}"
exec /usr/bin/supervisord -c /etc/ml-dev/supervisord.conf
