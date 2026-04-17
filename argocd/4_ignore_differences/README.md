# 1_ignore_differences

- 매칭 Git 경로: `github/1_ignore_differences`
- 목표: 특정 필드(`/spec/replicas`) 드리프트 무시 확인

## Step 1. Application 생성 (ignoreDifferences 포함)

```bash
cat <<EOF | kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: study-ignore-diff
spec:
  project: study
  source:
    repoURL: ${REPO_URL}
    targetRevision: main
    path: github/1_ignore_differences
  destination:
    server: https://kubernetes.default.svc
    namespace: study-ignore-diff
  ignoreDifferences:
    - group: apps
      kind: Deployment
      name: ignore-diff-demo
      namespace: study-ignore-diff
      jsonPointers:
        - /spec/replicas
EOF
```

## Step 2. Sync 실행

```bash
argocd app sync study-ignore-diff --argocd-context "$ARGOCD_CLI_CONTEXT"
```

## Step 3. 드리프트 생성 후 상태 확인

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-ignore-diff scale deploy/ignore-diff-demo --replicas=5
argocd app get study-ignore-diff --argocd-context "$ARGOCD_CLI_CONTEXT"
```

replicas 차이는 ignore 대상이므로 OutOfSync 원인에서 제외됩니다.
