#stage-1
FROM public.ecr.aws/amazonlinux/amazonlinux:2023 AS builder

RUN dnf install -y \
    python3.14 \
    python3.14-pip \
    gcc \
 && dnf clean all
WORKDIR /build
COPY requirements.txt .
RUN python3.14 -m pip install --no-cache-dir --prefix=/install -r requirements.txt

#stage-2
FROM public.ecr.aws/amazonlinux/amazonlinux:2023
RUN dnf install -y \
    python3.14 \
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
CMD ["python3.14", "app/app.py"]