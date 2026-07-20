# Runbook

**Last Updated:** 2026-07-19
**Purpose:** Day-to-day operational procedures for the Petclinic platform infrastructure.

---

### Procedure: Grant an additional IAM user/role access to an EKS cluster

**When:** A new teammate, CI role, or automation principal needs `kubectl`/API access to the `dev` or `prod` cluster.
**Who:** Whoever can run `terraform apply` against the target environment (dev: auto-sync engineers; prod: the manual-sync approver).
**Time:** ~5 minutes + one `terraform apply`

**Context:** The EKS module (`terraform/modules/eks/`) deliberately sets `bootstrap_cluster_creator_admin_permissions = false` and instead grants the deploying principal access via an explicit, Terraform-managed `aws_eks_access_entry` (see `module.eks.aws_eks_access_entry.deployer` in `terraform/modules/eks/main.tf`). Do not touch that resource — it's reserved for whichever principal runs the initial `terraform apply`. Additional users/roles are granted the same way: as their own access entry + policy association, added to the environment root module.

**Steps:**
1. In `terraform/environments/{env}/main.tf`, add an access entry and policy association for the new principal, after the `module "eks"` block:
   ```hcl
   resource "aws_eks_access_entry" "additional_user" {
     cluster_name  = module.eks.cluster_name
     principal_arn = "arn:aws:iam::<account-id>:user/<username>" # or role/<role-name>

     tags = {
       Project     = var.project
       Environment = var.environment
       ManagedBy   = "terraform"
     }
   }

   resource "aws_eks_access_policy_association" "additional_user_view" {
     cluster_name  = module.eks.cluster_name
     principal_arn = aws_eks_access_entry.additional_user.principal_arn
     policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy" # pick the least-privilege policy, see below

     access_scope {
       type = "cluster"
     }
   }
   ```
2. Pick the least-privilege access policy for what the principal actually needs:

   | Policy ARN suffix | Grants | Use for |
   |---|---|---|
   | `AmazonEKSViewPolicy` | Read-only | New teammates, auditors (default choice) |
   | `AmazonEKSEditPolicy` | Read/write to workloads, no RBAC or node changes | Engineers deploying/debugging apps |
   | `AmazonEKSAdminPolicy` | Full namespace-scoped admin | Namespace owners |
   | `AmazonEKSClusterAdminPolicy` | Full cluster admin | Break-glass only — this is what the deployer's own access entry uses; don't hand it out routinely |

   To scope access to specific namespaces instead of the whole cluster, change `access_scope` to:
   ```hcl
   access_scope {
     type       = "namespace"
     namespaces = ["petclinic-dev"]
   }
   ```
3. Run the standard workflow: `terraform fmt -recursive`, `terraform validate`, `terraform plan -out plan.out`, review the plan, then `terraform apply plan.out` (prod requires the usual manual approval — see CLAUDE.md).

**Verify:**
- The new principal runs `aws eks update-kubeconfig --name petclinic-{env} --region us-east-1` (the exact command is also available as the `eks_kubeconfig_command` Terraform output).
- `kubectl get nodes` (or `kubectl auth can-i --list`) succeeds for that principal, scoped to the policy granted.

**Rollback:**
- Remove the two resources from `main.tf` and re-apply, or run `terraform destroy -target=aws_eks_access_policy_association.additional_user_view -target=aws_eks_access_entry.additional_user` for that environment.

---

### Procedure: Build and push service images to ECR

**When:** Initial manual image push before any K8s manifests can be deployed (PETPLAT-85), or an ad hoc rebuild outside CI.
**Who:** Whoever has AWS credentials with ECR push access to the target account/region.
**Time:** ~10-15 minutes (Maven build + 8 image builds/pushes)

**Context:** CI (E-10) handles image builds on every commit going forward. This procedure is for the one-time initial push and any manual rebuilds. It deliberately does **not** use the app repo's `buildDocker` Maven profile — that profile shells out to plain `docker build --platform ...`, which cannot reliably cross-compile to `linux/arm64` (required for the Graviton t4g nodes) on an x86 host. Instead: Maven builds the JARs (in a `maven:3.9-eclipse-temurin-17` container — no local JDK/Maven install needed), then `docker buildx build --push` builds for `linux/arm64` and pushes straight to ECR without needing to load a foreign-arch image into the local Docker daemon.

**Prerequisites:**
- `spring-petclinic-microservices` checked out locally (sibling directory to `petclinic-platform` by default)
- Docker with buildx; QEMU registered for cross-platform emulation (Docker Desktop does this automatically — on plain Linux, run once: `docker run --privileged --rm tonistiigi/binfmt --install arm64`)
- ECR repositories already created (`terraform apply` for the `ecr` module — PETPLAT-20)
- No local JDK or Maven install needed — the JAR build step runs inside a Maven container

**Steps:**
1. Build and push all 8 images in one command:
   ```bash
   ./scripts/build-push-images.sh --tag v1.0.0
   ```
   This runs `./mvnw clean package -DskipTests` in the app repo, then for each service runs:
   ```bash
   docker buildx build \
     --platform linux/arm64 \
     -f <app-repo>/docker/Dockerfile \
     --build-arg ARTIFACT_NAME=spring-petclinic-<service>-<version> \
     --build-arg EXPOSED_PORT=<port> \
     -t <account>.dkr.ecr.us-east-1.amazonaws.com/petclinic-dev/<service>:v1.0.0 \
     --push \
     <app-repo>/spring-petclinic-<service>/target
   ```
   Ports come from the Application Services table in `CLAUDE.md`/`docs/technical-spec.md`, not from each service's `pom.xml` — several of those (`api-gateway`, `visits-service`, `vets-service`, `genai-service`) carry an incorrect copy-pasted value.
2. For prod, or a non-default app repo location:
   ```bash
   ./scripts/build-push-images.sh --tag v1.0.0 --env prod --app-repo /path/to/spring-petclinic-microservices
   ```
3. To re-push already-built jars under a new tag without rebuilding:
   ```bash
   ./scripts/build-push-images.sh --tag a1b2c3d --skip-build
   ```

**Verify:**
- Script output lists all 8 pushed image URIs.
- Images visible in the AWS ECR Console under `petclinic-{env}/` for each service, tagged as specified.
- `docker buildx imagetools inspect <image-uri>` shows `linux/arm64` as the platform.

**Rollback:**
- Nothing to roll back on the registry side — pushing a new tag never overwrites an existing one (dev is `MUTABLE`, but tags used here should still be unique per push; prod is `IMMUTABLE` and will reject a re-push of the same tag outright). To remove a bad image, delete it from the ECR Console or `aws ecr batch-delete-image`.

---

### Procedure: Database initialization strategy (RDS MySQL)

**When:** Reference this before first deploying `customers-service`, `visits-service`, or `vets-service` to an environment, or when debugging schema/connectivity issues.
**Who:** Whoever deploys the database-backed services.
**Time:** N/A — reference material, not a one-off action.

**Context (PETPLAT-24):** All three database-backed services share a single `petclinic` MySQL database on one RDS instance (`terraform/modules/rds/`) — confirmed by the cross-service foreign key `visits.pet_id -> pets.id`. There is no separate Terraform-driven schema-init step. Each service ships its own `schema.sql` under `src/main/resources/db/mysql/` in the app repo and self-initializes via Spring Boot with `spring.sql.init.mode=always` and the `mysql` Spring profile active. The RDS instance itself creates the empty `petclinic` database at provisioning time (`db_name = "petclinic"` on `aws_db_instance.this`); each service's schema script also carries `CREATE DATABASE IF NOT EXISTS petclinic; USE petclinic;`, which is idempotent against that.

**Schema ownership (7 tables, 3 services):**

| Service | Tables | Foreign keys |
|---|---|---|
| `customers-service` | `types`, `owners`, `pets` | none outbound |
| `vets-service` | `vets`, `specialties`, `vet_specialties` | none outbound (independent) |
| `visits-service` | `visits` | `visits.pet_id -> pets.id` |

**Init order — enforced by K8s deployment order, not by Terraform or Spring:**
1. `customers-service` first — creates `types`, `owners`, `pets`.
2. `vets-service` — independent, can run any time after `customers-service` or in parallel.
3. `visits-service` last — its schema has a hard FK dependency on `pets`, which only exists once `customers-service` has initialized.

This ordering is the same constraint documented for service startup generally (Config Server → Discovery Server → everything else); `customers-service` before `visits-service` is the one additional constraint specific to the database layer. Enforce it with K8s init containers or deployment ordering when wiring the Helm charts / ArgoCD Applications (E-8/E-16/E-17) — it is not enforced by this module.

**Connection string format** (for K8s ConfigMaps / Spring `SPRING_DATASOURCE_URL`):
```
jdbc:mysql://{rds-endpoint}:3306/petclinic
```
`{rds-endpoint}` is the `rds_endpoint` Terraform output (or `module.rds.endpoint`) for the target environment; username/password come from the `petclinic/{env}/rds-credentials` Secrets Manager secret (see `rds_secret_arn` output), synced into K8s via External Secrets Operator (E-7).

**Verify:**
- `terraform apply` on the `rds` module succeeds and the instance status is `available`.
- From a debug pod on the cluster: `kubectl run mysql-client --rm -it --image=mysql:8.0 -- mysql -h <rds_endpoint> -u petclinic -p petclinic` connects and `SHOW TABLES;` (after the services have started at least once) lists all 7 tables.

**Rollback:**
- Not applicable — this is a documentation/ordering convention, not an infrastructure resource. To reset schemas, drop and let Spring re-initialize on next pod restart (dev only; never on prod data).
