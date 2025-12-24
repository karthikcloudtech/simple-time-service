## GitOps Apps Layout

This folder is designed to be copied into a dedicated GitOps repository and used by Argo CD.

### Structure

- `apps/<service-name>/base`  
  Base Kustomize manifests for each microservice (deployment, service, ingress, config).

- `apps/<service-name>/overlays/<env>`  
  Environment-specific Kustomize overlays (e.g. `dev`, `staging`, `prod`).

- `argo-apps/*.yaml`  
  Argo CD `Application` objects that point to the paths under `apps/`.

### Adding a New Microservice

1. Copy the existing `simple-time-service` folder as a starting point:
   - `apps/simple-time-service` → `apps/<new-service-name>`
2. Update names, labels, image, and ports in:
   - `base/deployment.yaml`
   - `base/service.yaml`
   - `base/ingress.yaml` (optional, if you expose it via ingress)
3. Update the `kustomization.yaml` files if you change filenames.
4. Create a new Argo CD `Application` manifest under `argo-apps/` pointing to:
   - `apps/<new-service-name>/overlays/<env>`


