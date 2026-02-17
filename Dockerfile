# Use single stage since no build compilation needed (all deps are pure Python or pre-built)
FROM --platform=$BUILDPLATFORM amazonlinux:2023

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