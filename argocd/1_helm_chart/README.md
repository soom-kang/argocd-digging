# 1_helm_chart

- 매칭 Git 경로: `github/1_helm_chart`
- 목표: Argo CD의 Helm 렌더링/파라미터 오버라이드 확인

## Step 1. Application 생성 (Helm 옵션 포함)

```bash
cat <<EOF | kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: study-helm
spec:
  project: study
  source:
    repoURL: ${REPO_URL}
    targetRevision: main
    path: github/1_helm_chart
    helm:
      releaseName: study-helm
      values: |
        replicaCount: 2
        service:
          type: ClusterIP
          port: 80
  destination:
    server: https://kubernetes.default.svc
    namespace: study-helm
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
EOF
```

## Step 2. Sync 및 리소스 확인

```bash
argocd app sync study-helm --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-helm get deploy,svc
```

## Step 3. Helm 값 변경 테스트

`github/1_helm_chart/values.yaml` 또는 Application 내 `helm.values`를 변경 후 push 하여, Argo CD가 변경분을 정상 렌더링/반영하는지 확인합니다.
