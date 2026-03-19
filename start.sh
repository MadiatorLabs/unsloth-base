#!/bin/bash
set -e

PERSISTENT="/workspace"

# ============================================
# Phase 1: Storage Setup
# ============================================
echo "[Unsloth] Setting up storage..."

# Create persistent directory structure
mkdir -p "$PERSISTENT/unsloth/cache/huggingface"
mkdir -p "$PERSISTENT/unsloth/outputs"
mkdir -p "$PERSISTENT/unsloth/exports"
mkdir -p "$PERSISTENT/unsloth/assets/datasets/uploads"
mkdir -p "$PERSISTENT/unsloth/assets/datasets/recipes"
mkdir -p "$PERSISTENT/unsloth/auth"
mkdir -p "$PERSISTENT/unsloth/runs"

# Create the studio directory structure
mkdir -p /root/.unsloth/studio

# Symlink data directories to persistent storage
ln -sfn "$PERSISTENT/unsloth/cache"   /root/.unsloth/studio/cache
ln -sfn "$PERSISTENT/unsloth/outputs" /root/.unsloth/studio/outputs
ln -sfn "$PERSISTENT/unsloth/exports" /root/.unsloth/studio/exports
ln -sfn "$PERSISTENT/unsloth/assets"  /root/.unsloth/studio/assets
ln -sfn "$PERSISTENT/unsloth/auth"    /root/.unsloth/studio/auth
ln -sfn "$PERSISTENT/unsloth/runs"    /root/.unsloth/studio/runs

# Symlink venvs to image-baked locations
ln -sfn /opt/unsloth-venv    /root/.unsloth/studio/.venv
ln -sfn /opt/unsloth-venv-t5 /root/.unsloth/studio/.venv_t5

# Set HuggingFace cache to persistent storage
export HF_HOME="$PERSISTENT/unsloth/cache/huggingface"

# ============================================
# Phase 2: Credential Setup
# ============================================
if [ -z "$UNSLOTH_ADMIN_PASSWORD" ]; then
    echo "============================================"
    echo "  ERROR: UNSLOTH_ADMIN_PASSWORD is not set"
    echo ""
    echo "  Set it in RunPod template environment"
    echo "  variables before deploying."
    echo "============================================"
    exit 1
fi

# Only write password on first run (no existing auth.db)
if [ ! -f "$PERSISTENT/unsloth/auth/auth.db" ]; then
    echo "$UNSLOTH_ADMIN_PASSWORD" > "$PERSISTENT/unsloth/auth/.bootstrap_password"
    echo "[Unsloth] Admin password set for first run."
else
    echo "[Unsloth] Existing auth database found, skipping password setup."
fi

# ============================================
# Phase 3: Start Background Services
# ============================================
echo "[Unsloth] Starting background services..."

# SSH daemon (RunPod base image provides sshd, we ensure it's running)
if command -v sshd &> /dev/null; then
    /usr/sbin/sshd 2>/dev/null || true
fi

# TensorBoard
tensorboard --logdir="$PERSISTENT/unsloth/runs" --port=6006 --bind_all > /dev/null 2>&1 &

# Jupyter Lab
jupyter lab \
    --allow-root \
    --no-browser \
    --port=8888 \
    --ip=0.0.0.0 \
    --IdentityProvider.token="${JUPYTER_PASSWORD:-}" \
    --ServerApp.allow_origin='*' \
    --notebook-dir="$PERSISTENT" \
    > /dev/null 2>&1 &

# ============================================
# Phase 4: Start Unsloth Studio (foreground)
# ============================================
echo "═══════════════════════════════════════════════════════"
echo "  Unsloth Studio is starting!"
echo ""
echo "  Web UI:      https://${RUNPOD_POD_ID}-8000.proxy.runpod.net"
echo "  Jupyter:     https://${RUNPOD_POD_ID}-8888.proxy.runpod.net"
echo "  (RUNPOD_POD_ID is auto-provided by RunPod)"
echo "  Storage:     $PERSISTENT/unsloth/"
echo "═══════════════════════════════════════════════════════"

# Run Studio (signal forwarding for graceful shutdown, crash resilience)
cd /opt/unsloth/studio/backend
/root/.unsloth/studio/.venv/bin/python run.py --host 0.0.0.0 --port 8000 &
STUDIO_PID=$!
trap "kill $STUDIO_PID 2>/dev/null" SIGTERM SIGINT
wait $STUDIO_PID || true

echo "============================================="
echo "  Unsloth Studio crashed — check logs above."
echo "  SSH and JupyterLab are still available."
echo "  To restart:"
echo "    cd /opt/unsloth/studio/backend"
echo "    /root/.unsloth/studio/.venv/bin/python run.py --host 0.0.0.0 --port 8000"
echo "============================================="

sleep infinity
