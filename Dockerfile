#stage-1
FROM public.ecr.aws/amazonlinux/amazonlinux:2023 AS builder

RUN dnf install -y \
    python3.11 \
    python3.11-pip \
    gcc \
 && dnf clean all
WORKDIR /build
COPY requirements.txt .
RUN python3.11 -m pip install --no-cache-dir --prefix=/install -r requirements.txt

#stage-2
FROM public.ecr.aws/amazonlinux/amazonlinux:2023
RUN dnf install -y \
    python3.11 \
    shadow-utils \
 && dnf clean all
WORKDIR /app
# Copy installed dependencies and app
COPY --from=builder /install /usr/local
COPY app/ ./app
RUN useradd -m appuser \
 && chown -R appuser:appuser /app /usr/local
USER appuser
EXPOSE 8080
CMD ["python3.11", "app/app.py"]