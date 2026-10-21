# --------------------------------------------------
# Stage 1: Build dependencies
# --------------------------------------------------
FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

RUN python -m venv /opt/venv

ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Remove package-management tooling from the copied environment.
RUN rm -rf \
    /opt/venv/bin/pip \
    /opt/venv/bin/pip3 \
    /opt/venv/bin/pip3.12 \
    /opt/venv/lib/python3.12/site-packages/pip \
    /opt/venv/lib/python3.12/site-packages/pip-*.dist-info


# --------------------------------------------------
# Stage 2: Production runtime
# --------------------------------------------------
FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=5000 \
    PATH="/opt/venv/bin:$PATH"

WORKDIR /app

RUN groupadd --system app && \
    useradd --system --gid app --create-home app

COPY --from=builder /opt/venv /opt/venv
COPY --chown=app:app app/ ./app/

USER app

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=2)" || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--threads", "4", "--timeout", "30", "app.main:app"]
