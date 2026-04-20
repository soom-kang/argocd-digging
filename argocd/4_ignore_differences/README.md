# 4_ignore_differences

- 매칭 Git 경로: `github/4_ignore_differences`
- 목표: `ignoreDifferences`로 특정 필드 드리프트를 의도적으로 무시하는 동작 검증

---

# 1. ignoreDifferences 의미

Argo CD는 기본적으로 Git(desired state)와 클러스터(live state)를 비교해 차이가 있으면 `OutOfSync`로 판단합니다.
하지만 운영 환경에서는 일부 필드는 외부 컨트롤러(HPA, Operator)나 긴급 조치로 바뀔 수 있고, 이를 모두 drift로 보면 불필요한 재동기화가 반복됩니다.

`ignoreDifferences`는 이런 필드를 diff 계산에서 제외하는 기능입니다.

## 이 실습에서 확인하는 포인트

- `Deployment.spec.replicas`는 diff에서 제외
- 그 외 필드(예: image, label)는 계속 추적

---

# 2. argocd/4_ignore_differences/argo_setup.yaml 설명

`Application` 설정 핵심:

```yaml
spec:
  source:
    path: github/4_ignore_differences
  ignoreDifferences:
    - group: apps
      kind: Deployment
      name: ignore-diff-demo
      namespace: study-ignore-diff
      jsonPointers:
        - /spec/replicas
```

의미:

- `path`: Git에서 가져올 원본 매니페스트 경로
- `ignoreDifferences`: 특정 리소스의 특정 필드만 선택적으로 무시
- `jsonPointers: /spec/replicas`: replica 수 차이는 `OutOfSync` 원인에서 제외

---

# 3. github/4_ignore_differences YAML 설명

## namespace.yaml

- `study-ignore-diff` 네임스페이스 생성
- 실습 리소스를 격리

## deployment.yaml

- `ignore-diff-demo` Deployment
- 초기 `replicas: 2`
- 컨테이너 이미지: `nginx:1.27-alpine`

## service.yaml

- Deployment Pod를 대상으로 하는 ClusterIP Service
- 내부 HTTP(80) 트래픽 연결

즉, Git 기준 원본은 replicas 2지만, 실습 중 5로 수동 변경해도 Argo CD가 해당 차이를 무시하는지 검증하는 구성입니다.

---

## Step 1. Application 생성 (ignoreDifferences 설정 적용)

```bash
awk -v repo="$REPO_URL" '{gsub(/\$\{REPO_URL\}/,repo)}1' argocd/4_ignore_differences/argo_setup.yaml \
  | kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f -
```

## Step 2. Sync 실행

```bash
argocd app sync study-ignore-diff --argocd-context "$ARGOCD_CLI_CONTEXT"
```

## Step 3. replicas 드리프트 생성

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-ignore-diff scale deploy/ignore-diff-demo --replicas=5
```

## Step 4. 상태 확인

```bash
argocd app get study-ignore-diff --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-ignore-diff get deploy ignore-diff-demo
```

검증 포인트:

1. live replicas는 5로 변경됨
2. `ignoreDifferences` 대상이라 replicas 차이는 OutOfSync 원인에서 제외됨

---

# 운영 시 주의점

- 무시 범위를 넓게 잡으면 실제 장애 원인 drift까지 숨길 수 있음
- 꼭 필요한 필드만 최소 범위로 지정하는 것이 안전함
