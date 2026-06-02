# infra-sandbox

 **EKS GPU sandbox** you can stand up and tear down with one
command — plus a **vLLM** inference workload that demonstrates graceful request
draining on pod shutdown.

The infrastructure is **one generic Terraform root driven by per-environment data files**:
you add or change infra by editing *data*, never the `.tf`.

## What you get

- Public-only VPC (no NAT — cost-optimized), EKS, and two managed node groups:
  a small `system` group (t3.small) and a `gpu` group (g6.xlarge / **NVIDIA L4**).
- GPU stack: **Node Feature Discovery + NVIDIA device plugin (+GFD) + KEDA + cluster-autoscaler**.
- A sample **vLLM** workload (Qwen2.5-7B-Instruct-AWQ) with a **preStop drain hook** — see below.
- Modern EKS auth (**access entries + Pod Identity** — no `aws-auth` ConfigMap).
- AWS provider `~> 6.0`, Kubernetes 1.33.

## Architecture — one root, per-env data

```
terragrunt/
  common.hcl                 # S3 backend (+ lock) + shared paths   [copy from common.hcl.example]
  sandbox/terragrunt.hcl     # ← the environment, as one pure-data `inputs` block
  tf_files/envs/             # ← the single generic TF root; for_each over typed maps
    main.tf variables.tf vpc.tf eks.tf eks_nodes.tf iam.tf helm.tf outputs.tf
  helm_charts/               # vendored Helm values + the vLLM chart
Makefile
```

- `tf_files/envs/variables.tf` is the typed contract (`map(object({… optional()…}))`); every
  resource `for_each`es over a map, so **adding infra = adding a map entry** in the env file —
  the `.tf` never changes.
- Add another environment by copying `sandbox/` to e.g. `qa/` and editing its inputs; state
  auto-isolates by directory name.

## Prerequisites

- An AWS account + a configured CLI profile (default: `default`) with EKS/VPC/IAM permissions.
- Terraform **1.5.7+**, Terragrunt, `kubectl`, `aws` CLI v2, `helm`.

## Setup

```bash
# 1. Backend config (gitignored) — set your AWS account ID in the state-bucket name
cp terragrunt/common.hcl.example terragrunt/common.hcl
$EDITOR terragrunt/common.hcl

# 2. Bring it up (auto-creates the state bucket + lock table, applies, writes kubeconfig)
make up          # ~20-25 min until the cluster + GPU stack are ready

# 3. Day-to-day
make stop        # scale the GPU node group to 0 (cheapest idle state)
make start       # scale it back to 1
make destroy     # tear everything down (→ ~$0)
```

## Changing infrastructure

Edit **`terragrunt/sandbox/terragrunt.hcl`** — never the `.tf`:

| Want to… | Edit this key |
|---|---|
| Resize the GPU disk | `eks_node_groups.gpu.volume_size` |
| Change the GPU instance type | `eks_node_groups.gpu.instance_types` |
| Bump Kubernetes | `eks_kubernetes_version` |
| Pin a GPU-stack chart | `gpu_stack.*_version` |
| Add an EKS addon / node group | a new entry in `eks_addons` / `eks_node_groups` |

Then `make plan && make apply`.

## vLLM workload + graceful drain (preStop)

The repo ships a sample inference workload — **Qwen2.5-7B-Instruct-AWQ** on
`vllm/vllm-openai` — as a vendored Helm chart (`terragrunt/helm_charts/vllm-test/`), deployed
by `helm.tf`. Toggle it with `vllm_enabled` in the env file.

Its purpose is to demonstrate **graceful draining** so that **in-flight requests are not
dropped when the pod is deleted** (rolling update, scale-down, node drain).

**How it works.** The pod has a `lifecycle.preStop` hook — `drain.sh`, stored in the chart's
ConfigMap and mounted at `/scripts`. Kubernetes runs a preStop hook *to completion before* it
sends `SIGTERM`, so while the script runs vLLM stays up and keeps serving. The script:

1. polls vLLM's `vllm:num_requests_running` metric on `localhost:8000/metrics`,
2. holds the pod for at least `MIN_DRAIN_SECONDS` (covers Service endpoint deregistration +
   long generations),
3. exits as soon as in-flight requests reach 0 after that floor — but never past
   `MAX_DRAIN_SECONDS`, which is kept **under** `terminationGracePeriodSeconds` so the kubelet
   never `SIGKILL`s mid-drain.

These are all chart values (`helm_charts/vllm-test/values.yaml`): `drain.minSeconds` /
`drain.maxSeconds`, `termination.gracePeriodSeconds`, plus a `startupProbe` floor.

**Why it matters — with vs. without the hook:**

| | in-flight request | pod termination |
|---|---|---|
| **with** preStop drain | **completes** (`finish_reason: length`) | within the drain window, clean |
| **without** (grace = 1s) | **cut off** (`finish_reason: abort`) | ~seconds, ungraceful |

> vLLM closes the SSE stream politely either way (you always get `data: [DONE]`), so the real
> tell is **`finish_reason`**: `length`/`stop` = finished, `abort` = dropped.

**Try it:**

```bash
make kubeconfig
kubectl port-forward svc/vllm-test 8000:8000        # leave running in one terminal
curl -s localhost:8000/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen2.5-7B-Instruct-AWQ","messages":[{"role":"user","content":"hi"}],"max_tokens":64}'
```

## Notes

- **Device-plugin label override.** `helm_charts/nvidia-device-plugin/values.yaml` overrides
  the chart's default node affinity to match modern NFD's
  `feature.node.kubernetes.io/pci-0302_10de.present` label — without it the device-plugin
  DaemonSet schedules nowhere and no GPUs register.
- **Cost (us-west-2).** EKS control plane `$0.10/hr` + the L4 node `~$0.80/hr` (the dominant
  cost) + 2× t3.small `~$0.04/hr` ≈ **~$0.94/hr** running; **~$0/hr** after `make destroy`
  (only the tiny S3 state bucket remains). `make stop` (GPU → 0) is the idle-cost lever.
