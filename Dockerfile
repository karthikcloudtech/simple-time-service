# Stage 1: Builder
FROM --platform=$BUILDPLATFORM amazonlinux:2023 AS builder
RUN dnf install -y python3.11 python3.11-pip gcc \
 && dnf clean all \
 && rm -rf /var/cache/dnf/*
WORKDIR /build
COPY requirements.txt .
RUN pip3.11 install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: Final Image
FROM --platform=$BUILDPLATFORM amazonlinux:2023 AS final
RUN dnf install -y python3.11 \
 && dnf clean all \
 && rm -rf /var/cache/dnf/* /var/lib/dnf/* \
 && useradd -m appuser
WORKDIR /app
# Copy installed dependencies and app
COPY --from=builder /install /usr/local
COPY app/ ./app
RUN chown -R appuser:appuser /app /usr/local
USER appuser
EXPOSE 8080
CMD ["python3.11", "app/app.py"]