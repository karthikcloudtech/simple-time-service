# Stage 1: Builder
FROM --platform=$BUILDPLATFORM amazonlinux:2023 AS builder
RUN dnf install -y --nodocs --no-install-recommends python3.11 python3.11-pip gcc \
 && dnf clean all \
 && rm -rf /var/cache/dnf/* /var/lib/dnf/*
WORKDIR /build
COPY requirements.txt .
RUN pip3.11 install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: Final Image
FROM --platform=$BUILDPLATFORM amazonlinux:2023 AS final
RUN dnf install -y --nodocs --no-install-recommends python3.11 python3.11-setuptools shadow-utils \
 && dnf clean all \
 && rm -rf /var/cache/dnf/* /var/lib/dnf/*
WORKDIR /app
COPY --from=builder /install /usr/local
COPY app/ ./app
RUN useradd -m appuser \
 && chown -R appuser:appuser /app /usr/local
USER appuser
EXPOSE 8080
CMD ["python3.11", "app/app.py"]