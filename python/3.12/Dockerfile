# =============================================================================
# PYTHON CI/CD BASE IMAGE — Python 3.12
# =============================================================================
# Pre-baked CI image for Python services. Patch version floats on rebuild
# (3.12-slim always resolves to the latest 3.12.x).
# Includes libffi and libxml2/libxslt/libxmlsec development headers.
#
# Components:
#   python 3.12 (slim)         — from official python image
#   uv, uvx                    — pinned, from official astral-sh image
#   /opt/wheels                — e2e-gpu Python 3.12 compatibility wheels
#   pipenv, ansible            — env + deploy tooling
#   ruff, pyright, semgrep     — lint / typecheck / SAST
#   pytest + django stack      — test + framework batteries
# =============================================================================

FROM mirror.gcr.io/library/python:3.12-slim

LABEL org.opencontainers.image.source="https://github.com/e2enetworks-oss/platform-images" \
      org.opencontainers.image.description="Python 3.12 CI base image (uv, pipenv, ansible, ruff, pytest, Django stack, libffi, libxmlsec)" \
      org.opencontainers.image.licenses="MIT"

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1

# Install uv from official image (single static binary, pinned)
COPY --from=ghcr.io/astral-sh/uv:0.12.3 /uv /usr/local/bin/uv
COPY --from=ghcr.io/astral-sh/uv:0.12.3 /uvx /usr/local/bin/uvx

# Install system dependencies (including MySQL, FreeType, FFI and XML headers)
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    git \
    openssh-client \
    build-essential \
    patch \
    pkg-config \
    libffi-dev \
    default-libmysqlclient-dev \
    libfreetype6-dev \
    libxml2-dev \
    libxslt1-dev \
    libxmlsec1-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Build reusable wheels for e2e-gpu's legacy Python 3.12 pins. This runs once
# per target architecture, so /opt/wheels contains native amd64 or arm64 wheels
# instead of asking every CI job to compile the packages again.
COPY wheelhouse-requirements.txt /tmp/wheelhouse-requirements.txt
COPY django-safedelete-django42.patch /tmp/django-safedelete-django42.patch
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    export PIP_NO_CACHE_DIR=0 PIP_DEFAULT_TIMEOUT=120 PIP_RETRIES=10 \
    && python -m pip install --no-compile "setuptools<81" wheel \
    && mkdir -p /opt/wheels \
    && while IFS= read -r requirement; do \
        if [ "$requirement" = "django-safedelete==0.3.2" ]; then \
            mkdir -p /tmp/safedelete-source \
            && python -m pip download \
                    --no-deps \
                    --no-binary=:all: \
                    --dest=/tmp/safedelete-source \
                    "$requirement" \
            && tar -xzf /tmp/safedelete-source/django-safedelete-0.3.2.tar.gz \
                -C /tmp/safedelete-source \
            && patch -d /tmp/safedelete-source/django-safedelete-0.3.2 \
                -p1 < /tmp/django-safedelete-django42.patch \
            && python -m pip wheel \
                --no-deps \
                --wheel-dir=/opt/wheels \
                /tmp/safedelete-source/django-safedelete-0.3.2; \
        else \
            python -m pip wheel \
                --no-deps \
                --wheel-dir=/opt/wheels \
                "$requirement"; \
        fi; \
    done < /tmp/wheelhouse-requirements.txt \
    && cp /tmp/wheelhouse-requirements.txt /opt/wheels/requirements.txt \
    && rm -rf \
        /tmp/django-safedelete-django42.patch \
        /tmp/safedelete-source \
        /tmp/wheelhouse-requirements.txt

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
    Django==5.2.17 \
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
    cryptography==45.0.7 \
    pycparser==2.22 \
    PyJWT==2.13.0 \
    pymemcache==4.0.0 \
    sqlparse==0.5.5 \
    typing_extensions==4.15.0 \
    whitenoise==6.11.0 \
    # Common utilities
    "setuptools<81" \
    wheel \
    && pipenv --version \
    && python -c "import pkg_resources" \
    && find /usr/local -type d -name __pycache__ -prune -exec rm -rf {} +

# The same smoke test is run during both native architecture builds. Keeping it
# in the final image also lets consumers verify a pulled manifest explicitly.
COPY --chmod=0755 smoke-test.sh /usr/local/bin/python312-smoke-test
RUN python312-smoke-test

# Set working directory
WORKDIR /app

# Create a non-root user for security
RUN useradd --create-home --shell /bin/bash app \
    && chown -R app:app /app
USER app
