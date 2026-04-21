# 01_basic_sync

- 매칭 Git 경로: `github/01_basic_sync`
- 목표: Argo CD 기본 sync/health 동작 확인

## Step 1. Application 생성 (yaml 파일 적용)

```bash
awk -v repo="$REPO_URL" '{gsub(/\$\{REPO_URL\}/,repo)}1' argocd/01_basic_sync/application_setup.yaml \
  | kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f -

# or use alias
kstudy -f ./application_setup.yaml
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

## Step 4. 정리 (삭제)

```bash
argocd app delete study-basic-sync --cascade --yes --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" delete namespace study-basic-sync --ignore-not-found
```
