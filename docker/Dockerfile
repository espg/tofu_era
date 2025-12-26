# CAE JupyterHub Custom Image
# Extends pangeo-notebook with VSCode support and additional tools

ARG BASE_TAG=2025.01.10
FROM pangeo/pangeo-notebook:${BASE_TAG}

USER root

# Install code-server (VS Code in browser)
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Switch back to jovyan user
USER ${NB_USER}

# Install jupyter-vscode-proxy for VS Code integration
# jupyter-server-proxy is already in pangeo-notebook base
RUN mamba install -y -c conda-forge jupyter-vscode-proxy && \
    mamba clean --all -f -y

# Verify installations
RUN code-server --version && \
    python -c "import jupyter_vscode_proxy; print('jupyter-vscode-proxy installed')"

# Add labels for tracking
LABEL maintainer="CAE Team"
LABEL description="Pangeo notebook with VSCode support for CAE JupyterHub"
LABEL base_image="pangeo/pangeo-notebook:${BASE_TAG}"
LABEL features="vscode,jupyter-vscode-proxy"
