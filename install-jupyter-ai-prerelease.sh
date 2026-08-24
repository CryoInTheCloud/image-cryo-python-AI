#!/bin/bash -l
# ---------------------------------------------------------------------------
# Post-build installer: upgrade Jupyter AI to a PyPI-only pre-release.
#
# WHY THIS EXISTS
#   environment.yml / conda-linux-64.lock pin `jupyter-ai ~=3.0.0`, because that
#   is the newest release available on conda-forge. Jupyter AI 3.2.0a0 (and its
#   whole `jupyter-ai-*` pre-release dependency family: acp-client 0.3.x,
#   persona-manager 0.2.x, router 0.1.x, tools 0.7.x, jupyterlab-chat 0.25.x,
#   jupyter-server-mcp 0.3.x, ...) only exists on PyPI.
#
# WHY uv AND NOT plain pip
#   Upgrading to 3.2.0a0 forces ~10 conda-installed packages to be replaced by
#   pre-release wheels at once. pip's resolver tends to upgrade packages one at
#   a time and can leave the environment in a half-upgraded, inconsistent state
#   (a classic way to "break" a conda env). uv resolves the *entire* pre-release
#   graph in a single pass and only then writes, so the env moves atomically
#   from one consistent state to another.
#
# This script is invoked from the repo2docker `appendix`, AFTER the conda env is
# (re)created from the lockfile. It can also be run by hand inside a running
# container to iterate.
# ---------------------------------------------------------------------------
set -euo pipefail

# At build time repo2docker exports NB_PYTHON_PREFIX; at run time the active
# conda env exports CONDA_PREFIX. Both point at the same prefix.
PREFIX="${NB_PYTHON_PREFIX:-${CONDA_PREFIX:-}}"
if [[ -z "${PREFIX}" ]]; then
  echo "ERROR: neither NB_PYTHON_PREFIX nor CONDA_PREFIX is set." >&2
  exit 1
fi

# Overridable knobs.
JUPYTER_AI_VERSION="${JUPYTER_AI_VERSION:-3.2.0a0}"
# The [jupyternaut] extra pulls the default model-provider persona
# (jupyter-ai-jupyternaut + jupyter-ai-litellm) so Jupyter AI is actually usable
# out of the box. Set JUPYTER_AI_EXTRAS="" to install the bare package.
JUPYTER_AI_EXTRAS="${JUPYTER_AI_EXTRAS:-[jupyternaut]}"

echo ">>> Installing uv (standalone binary) ..."
export UV_INSTALL_DIR="${UV_INSTALL_DIR:-/tmp/uv-bin}"
export UV_UNMANAGED_INSTALL="${UV_INSTALL_DIR}"   # install just the binary, no shell shims
curl -LsSf https://astral.sh/uv/install.sh | sh
UV="${UV_INSTALL_DIR}/uv"
"${UV}" --version

SPEC="jupyter-ai${JUPYTER_AI_EXTRAS}==${JUPYTER_AI_VERSION}"
echo ">>> Upgrading to ${SPEC} in prefix ${PREFIX} via uv (pre-releases allowed) ..."
# --python           : target the conda interpreter, not a uv-managed one
# --prerelease=allow : 3.2.0a0 + its jupyter-ai-* deps are pre-releases
"${UV}" pip install \
  --python "${PREFIX}/bin/python" \
  --prerelease=allow \
  "${SPEC}"

echo ">>> Verifying installed versions ..."
"${PREFIX}/bin/python" - <<'PY'
import importlib.metadata as m
for pkg in [
    "jupyter-ai",
    "jupyter-ai-acp-client",
    "jupyter-ai-persona-manager",
    "jupyter-ai-router",
    "jupyter-ai-tools",
    "jupyter-ai-chat-commands",
    "jupyterlab-chat",
    "jupyter-server-mcp",
    "jupyterlab",
]:
    try:
        print(f"  {pkg:28s} {m.version(pkg)}")
    except m.PackageNotFoundError:
        print(f"  {pkg:28s} (not installed)")
PY

echo ">>> Checking environment consistency (uv pip check) ..."
"${UV}" pip check --python "${PREFIX}/bin/python" || {
  echo "WARNING: uv pip check reported issues (see above)." >&2
}

echo ">>> Jupyter AI ${JUPYTER_AI_VERSION} install complete."
