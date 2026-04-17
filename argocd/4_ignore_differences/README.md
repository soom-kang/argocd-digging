# 4_ignore_differences

- 매칭 Git 경로: `github/4_ignore_differences`
- 목표: 특정 필드(`/spec/replicas`) 드리프트 무시 확인

## Step 1. Application 생성 (ignoreDifferences + yaml 파일 적용)

```bash
awk -v repo="$REPO_URL" '{gsub(/\$\{REPO_URL\}/,repo)}1' argocd/4_ignore_differences/argo_setup.yaml \
  | kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f -
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
