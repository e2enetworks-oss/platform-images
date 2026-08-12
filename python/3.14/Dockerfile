# =============================================================================
# PYTHON CI/CD BASE IMAGE — Python 3.14
# =============================================================================
# Pre-baked CI image for Python services. Patch version floats on rebuild
# (3.14-slim always resolves to the latest 3.14.x).
# Differs from 3.11 only by libxml2/libxslt/libxmlsec headers.
#
# Components:
#   python 3.14 (slim)         — from official python image
#   uv, uvx                    — pinned, from official astral-sh image
#   pipenv, ansible            — env + deploy tooling
#   ruff, pyright, semgrep     — lint / typecheck / SAST
#   pytest + django stack      — test + framework batteries
# =============================================================================

FROM mirror.gcr.io/library/python:3.14-slim

LABEL org.opencontainers.image.source="https://github.com/e2enetworks-oss/platform-images" \
      org.opencontainers.image.description="Python 3.14 CI base image (uv, pipenv, ansible, ruff, pytest, Django stack, libxmlsec)" \
      org.opencontainers.image.licenses="MIT"

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1

# Install uv from official image (single static binary, pinned)
COPY --from=ghcr.io/astral-sh/uv:0.12.3 /uv /usr/local/bin/uv
COPY --from=ghcr.io/astral-sh/uv:0.12.3 /uvx /usr/local/bin/uvx

# Install system dependencies (including MySQL, FreeType and XML headers)
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    git \
    openssh-client \
    build-essential \
    pkg-config \
    default-libmysqlclient-dev \
    libfreetype6-dev \
    libxml2-dev \
    libxslt1-dev \
    libxmlsec1-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install all Python packages in a single layer
RUN pip install --no-cache-dir --no-compile --prefer-binary \
    pipenv \
    ansible \
    # Quality tools
    ruff==0.15.2 \
    pre-commit==4.5.1 \
    pyright==1.1.408 \
    semgrep==1.152.0 \
    coverage==7.13.4 \
    # Testing
    pytest==8.4.2 \
    pytest-django==4.12.0 \
    pytest-html==4.2.0 \
    pytest-sugar==1.1.1 \
    # Core Django (stable versions)
    Django==5.2.7 \
    djangorestframework==3.16.1 \
    django-environ==0.11.2 \
    mysqlclient==2.2.8 \
    # Django extensions and additional packages
    django-allauth==65.14.3 \
    django-appconf==1.2.0 \
    django-cors-headers==4.9.0 \
    django-countries==7.6.1 \
    django-dbtemplates==4.0 \
    django-extensions==4.1 \
    django-tinymce==4.1.0 \
    django-safedelete==1.4.1 \
    drf-spectacular==0.29.0 \
    # Additional testing and development tools
    django-stubs==5.2.9 \
    djangorestframework-stubs==3.16.8 \
    factory-boy==3.3.3 \
    Werkzeug==3.1.6 \
    ipdb==0.13.13 \
    # Core dependencies
    asgiref==3.11.1 \
    cryptography==45.0.4 \
    pycparser==2.22 \
    PyJWT==2.11.0 \
    pymemcache==4.0.0 \
    sqlparse==0.5.5 \
    typing_extensions==4.15.0 \
    whitenoise==6.11.0 \
    # Common utilities
    setuptools \
    wheel \
    && pipenv --version \
    && find /usr/local -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null; true

# Set working directory
WORKDIR /app

# Create a non-root user for security
RUN useradd --create-home --shell /bin/bash app \
    && chown -R app:app /app
USER app
