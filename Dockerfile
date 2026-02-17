# Stage 1: Builder (commented out - not needed for pure Python deps)
# FROM --platform=$BUILDPLATFORM amazonlinux:2023 AS builder
# RUN dnf install -y --nodocs \
#     python3.11 \
#     python3.11-pip \
#     gcc \
#  && dnf clean all \
#  && rm -rf /var/cache/dnf/* /var/lib/dnf/*
# WORKDIR /build
# COPY requirements.txt .
# RUN pip3.11 install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: Final Image
FROM --platform=$BUILDPLATFORM amazonlinux:2023 AS final
RUN dnf install -y --nodocs \
    python3.11 \
    python3.11-pip \
    python3.11-setuptools \
    shadow-utils \
 && dnf clean all \
 && rm -rf /var/cache/dnf/* /var/lib/dnf/*

RUN useradd -m appuser

WORKDIR /app
COPY requirements.txt .
RUN pip3.11 install --no-cache-dir -r requirements.txt

COPY app/ ./app
RUN chown -R appuser:appuser /app
USER appuser
EXPOSE 8080
CMD ["python3.11", "app/app.py"]