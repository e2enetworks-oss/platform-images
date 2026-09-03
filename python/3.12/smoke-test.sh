#!/bin/sh
set -eu

python_version=$(python -c 'import platform; print(platform.python_version())')
case "$python_version" in
    3.12.*) ;;
    *)
        echo "expected Python 3.12.x, got $python_version" >&2
        exit 1
        ;;
esac

python -c 'import pkg_resources'

# The smoke environment is disposable. Do not retain its downloaded packages
# in the published image (or expose test-only package metadata to scanners).
export UV_NO_CACHE=1

smoke_venv=$(mktemp -d)
trap 'rm -rf "$smoke_venv"' EXIT HUP INT TERM

uv venv --python python "$smoke_venv"

# Prove every compatibility artifact is a wheel uv can install without an
# index or build backend. Dependencies are intentionally handled by the
# consumer's normal requirements resolution.
uv pip install \
    --python "$smoke_venv/bin/python" \
    --no-index \
    --no-deps \
    --find-links=/opt/wheels \
    --requirement=/opt/wheels/requirements.txt

# cffi needs pycparser at runtime. Force that dependency and the full
# Matplotlib stack to use published wheels so a missing Python 3.12 wheel makes
# the image build fail on the affected architecture.
uv pip install \
    --python "$smoke_venv/bin/python" \
    --only-binary=:all: \
    "setuptools<81" \
    Django==4.2.26 \
    django-simple-history==3.3.0 \
    pycparser==2.21 \
    numpy==1.26.4 \
    pillow==10.3.0 \
    matplotlib==3.8.4

"$smoke_venv/bin/python" -c 'from cffi import FFI; import cffi; ffi = FFI(); ffi.cdef("size_t strlen(const char *s);"); assert ffi.dlopen(None).strlen(b"wheelhouse") == 10; assert cffi.__version__ == "1.15.1"'
"$smoke_venv/bin/python" -c 'import matplotlib; assert matplotlib.__version__ == "3.8.4"'
"$smoke_venv/bin/python" - <<'PY'
from django.conf import settings

settings.configure(
    SECRET_KEY="wheelhouse-smoke-test",
    INSTALLED_APPS=[
        "django.contrib.auth",
        "django.contrib.contenttypes",
        "django.contrib.admin",
        "simple_history",
    ],
    DATABASES={
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": ":memory:",
        }
    },
    MIDDLEWARE=[],
    TEMPLATES=[
        {
            "BACKEND": "django.template.backends.django.DjangoTemplates",
            "APP_DIRS": True,
        }
    ],
)

import django

django.setup()

from django.contrib.auth.models import AbstractUser, UserManager
from django.db import models
from safedelete import SOFT_DELETE, safedelete_mixin_factory
from safedelete.admin import SafeDeleteAdmin  # noqa: F401
from simple_history.models import HistoricalRecords  # noqa: F401

safe_mixin = safedelete_mixin_factory(policy=SOFT_DELETE)


class SafeRecord(safe_mixin):
    class Meta:
        app_label = "wheelhouse_smoke"


admin_mixin = safedelete_mixin_factory(
    policy=SOFT_DELETE,
    manager_superclass=UserManager,
)


class SafeUser(admin_mixin, AbstractUser):
    class Meta:
        app_label = "wheelhouse_smoke"


assert isinstance(SafeRecord._meta.get_field("deleted"), models.BooleanField)
assert isinstance(SafeUser.objects, UserManager)
PY
