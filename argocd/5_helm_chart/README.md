# 5_helm_chart

- 매칭 Git 경로: `github/5_helm_chart`
- 목표: Argo CD의 Helm 렌더링/파라미터 오버라이드 확인

## Step 1. Application 생성 (Helm 옵션 + yaml 파일 적용)

```bash
awk -v repo="$REPO_URL" '{gsub(/\$\{REPO_URL\}/,repo)}1' argocd/5_helm_chart/argo_setup.yaml \
  | kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f -
```

## Step 2. Sync 및 리소스 확인

```bash
argocd app sync study-helm --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-helm get deploy,svc
```

## Step 3. Helm 값 변경 테스트

`github/5_helm_chart/values.yaml` 또는 Application 내 `helm.values`를 변경 후 push 하여, Argo CD가 변경분을 정상 렌더링/반영하는지 확인합니다.
