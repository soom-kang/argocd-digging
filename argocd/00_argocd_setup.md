# 신규 Argo CD 구성 가이드 (기존 Argo CD Plane과 분리)

이 문서는 `/k8s/00_new_kind_cluster_setup.md`로 생성한 신규 kind 클러스터에 Argo CD를 설치하고, 기존 Argo CD plane과 간섭 없이 운영하기 위한 절차입니다.

## Step 0. 변수 정의

```bash
export STUDY_KUBECONFIG="$HOME/.kube/config-kind-argocd-study"
export ARGOCD_NS="argocd-study"
export ARGOCD_PORT_HTTPS="18444"
export ARGOCD_CLI_CONTEXT="argocd-study-local"
export REPO_URL="https://github.com/<YOUR_ORG>/<YOUR_REPO>.git"
```

- `ARGOCD_NS`를 기존과 다른 네임스페이스로 분리
- 로컬 포트는 기존 사용 포트와 충돌하지 않도록 `18444` 사용

## Step 1. Argo CD 설치

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" create namespace "$ARGOCD_NS"
kubectl --kubeconfig "$STUDY_KUBECONFIG" apply -n "$ARGOCD_NS" \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" wait deployment \
  --all --for=condition=Available --timeout=300s
```

## Step 2. 초기 관리자 비밀번호 확인

```bash
ARGOCD_ADMIN_PASSWORD=$(kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" \
  get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
echo "$ARGOCD_ADMIN_PASSWORD"
```

## Step 3. 포트포워딩 (신규 Argo CD 전용 포트)

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" \
  port-forward svc/argocd-server ${ARGOCD_PORT_HTTPS}:443
```

포트포워딩 터미널은 열어둔 상태로 유지합니다.

## Step 4. Argo CD CLI 로그인 (별도 CLI 컨텍스트)

```bash
argocd login "localhost:${ARGOCD_PORT_HTTPS}" \
  --username admin \
  --password "$ARGOCD_ADMIN_PASSWORD" \
  --insecure \
  --grpc-web \
  --name "$ARGOCD_CLI_CONTEXT"
```

## Step 5. 스터디용 AppProject 생성

```bash
cat <<EOF2 | kubectl --kubeconfig "$STUDY_KUBECONFIG" apply -f -
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: study
  namespace: ${ARGOCD_NS}
spec:
  description: Argo CD feature study project
  sourceRepos:
    - ${REPO_URL}
  destinations:
    - namespace: '*'
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: '*'
      kind: '*'
EOF2
```

## Step 6. 저장소 등록 (필요 시)

공개 저장소면 생략 가능하지만, 명시적으로 등록하면 관리가 편합니다.

```bash
argocd repo add "$REPO_URL" --argocd-context "$ARGOCD_CLI_CONTEXT"
```

## Step 7. 기능 테스트 문서 실행 순서

아래 문서는 `github/` 경로와 1:1로 매칭됩니다.

1. `argocd/01_basic_sync/README.md`
2. `argocd/02_auto_sync_prune_self_heal/README.md`
3. `argocd/03_sync_waves_and_hooks/README.md`
4. `argocd/04_ignore_differences/README.md`
5. `argocd/05_helm_chart/README.md`
6. `argocd/06_kustomize_overlay/README.md`
7. `argocd/07_multi_source_helm_values/README.md`
8. `argocd/08_applicationset_list_generator/README.md`
9. `argocd/09_sync_windows/README.md`
10. `argocd/10_orphaned_resources_monitoring/README.md`
11. `argocd/11_sync_options/README.md`
12. `argocd/12_config_management_plugin/README.md`
