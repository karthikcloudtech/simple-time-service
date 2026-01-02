#!/bin/bash
# Script to check latest versions of Helm charts
# Run this to verify and update versions in ArgoCD Application manifests

set -e

echo "Checking latest Helm chart versions..."
echo ""

# Add repositories
echo "Adding Helm repositories..."
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server 2>/dev/null || true
helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add elastic https://helm.elastic.co 2>/dev/null || true
helm repo add fluent https://fluent.github.io/helm-charts 2>/dev/null || true
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
helm repo add autoscaler https://kubernetes.github.io/autoscaler 2>/dev/null || true
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true

echo "Updating Helm repositories..."
helm repo update > /dev/null 2>&1

echo ""
echo "Latest Helm Chart Versions:"
echo "=========================="
echo ""

echo "Metrics Server:"
helm search repo metrics-server/metrics-server --versions | head -1

echo ""
echo "AWS Load Balancer Controller:"
helm search repo eks/aws-load-balancer-controller --versions | head -1

echo ""
echo "Cert-Manager:"
helm search repo jetstack/cert-manager --versions | head -1

echo ""
echo "Prometheus Stack:"
helm search repo prometheus-community/kube-prometheus-stack --versions | head -1

echo ""
echo "Elasticsearch:"
helm search repo elastic/elasticsearch --versions | head -1

echo ""
echo "Kibana:"
helm search repo elastic/kibana --versions | head -1

echo ""
echo "Fluent-bit:"
helm search repo fluent/fluent-bit --versions | head -1

echo ""
echo "OpenTelemetry Collector:"
helm search repo open-telemetry/opentelemetry-collector --versions | head -1

echo ""
echo "Cluster Autoscaler:"
helm search repo autoscaler/cluster-autoscaler --versions | head -1

echo ""
echo "ArgoCD:"
helm search repo argo/argo-cd --versions | head -1

echo ""
echo "=========================="
echo "Update targetRevision in gitops/argo-apps/*.yaml files with the versions above"
echo ""

