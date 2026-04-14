# 1_basic_sync

- 매칭 Git 경로: `github/1_basic_sync`
- 목표: Argo CD 기본 sync/health 동작 확인

## Step 1. Application 생성

```bash
cat <<EOF | kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: study-basic-sync
spec:
  project: study
  source:
    repoURL: ${REPO_URL}
    targetRevision: main
    path: github/1_basic_sync
  destination:
    server: https://kubernetes.default.svc
    namespace: study-basic-sync
  syncPolicy:
    syncOptions:
      - CreateNamespace=false
EOF
```

## Step 2. 수동 Sync

```bash
argocd app sync study-basic-sync --argocd-context "$ARGOCD_CLI_CONTEXT"
```

## Step 3. 상태 확인

```bash
argocd app get study-basic-sync --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-basic-sync get all,cm
```

`Synced` + `Healthy` 상태면 성공입니다.
