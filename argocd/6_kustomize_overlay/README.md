# 1_kustomize_overlay

- 매칭 Git 경로: `github/1_kustomize_overlay`
- 목표: Kustomize overlay 적용 결과 검증

## Step 1. Application 생성 (overlay 경로 지정)

```bash
cat <<EOF | kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: study-kustomize-dev
spec:
  project: study
  source:
    repoURL: ${REPO_URL}
    targetRevision: main
    path: github/1_kustomize_overlay/overlays/dev
  destination:
    server: https://kubernetes.default.svc
    namespace: study-kustomize
EOF
```

## Step 2. Sync 및 결과 확인

```bash
argocd app sync study-kustomize-dev --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-kustomize get deploy,svc -L environment
```

검증 포인트:

1. Deployment 이름에 `-dev` suffix 적용
2. label `environment=dev` 적용
3. overlay patch 값(replicas=2, nginx:1.27-alpine) 반영
