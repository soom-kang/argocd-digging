# 07_multi_source_helm_values

- 매칭 Git 경로:
  - `github/07_multi_source_helm_values/chart`
  - `github/07_multi_source_helm_values/values`
- 목표: 하나의 Application에서 `sources[]`를 사용해 Helm chart와 외부 values 파일을 분리 관리하는 방식 검증

---

# 1. multi-source 핵심 개념

기존 `spec.source`(단일 소스) 대신 `spec.sources`(복수 소스)를 사용하면,
아래처럼 소스 역할을 분리할 수 있습니다.

- Source A: Helm chart 템플릿
- Source B: values 파일 저장소(또는 경로)

이 구조의 장점:

1. 템플릿 변경과 환경값 변경의 책임 분리
2. 운영 중 values 저장소 권한 최소화
3. 애플리케이션 코드와 운영 파라미터를 독립적으로 버전 관리

---

# 2. application_setup.yaml 핵심 옵션

```yaml
spec:
  sources:
    - path: github/07_multi_source_helm_values/chart
      helm:
        valueFiles:
          - $values/github/07_multi_source_helm_values/values/dev-values.yaml
    - ref: values
```

의미:

- 첫 번째 source는 Helm chart를 렌더링
- 두 번째 source는 `ref: values` 별칭으로 외부 values 위치 제공
- `$values/...` 경로로 첫 번째 source에서 두 번째 source의 파일을 참조

---

# 3. 실습 포인트

- chart 기본값: `replicaCount=1`, `service.port=80`, `image.tag=1.26-alpine`
- 외부 values(`dev-values.yaml`): `replicaCount=3`, `service.port=8080`, `image.tag=1.27-alpine`
- 최종 렌더링 결과는 외부 values 기준으로 생성되어야 함

---

## Step 1. Application 생성

```bash
awk -v repo="$REPO_URL" '{gsub(/\$\{REPO_URL\}/,repo)}1' argocd/07_multi_source_helm_values/application_setup.yaml \
  | kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f -
```

## Step 2. Sync 실행

```bash
argocd app sync study-multi-source --argocd-context "$ARGOCD_CLI_CONTEXT"
```

## Step 3. 결과 확인

```bash
argocd app get study-multi-source --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-multi-source get deploy,svc
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-multi-source get deploy study-multi-source -o jsonpath='{.spec.replicas}{"\n"}'
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-multi-source get svc study-multi-source -o jsonpath='{.spec.ports[0].port}{"\n"}'
```

검증 포인트:

1. Deployment replicas가 `3`
2. Service port가 `8080`
3. 이미지 태그가 `1.27-alpine`

---

## Step 4. 정리 (삭제)

```bash
argocd app delete study-multi-source --cascade --yes --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" delete namespace study-multi-source --ignore-not-found
```

---

# 운영 시 주의점

- multi-source는 강력하지만 source 간 참조 관계(`$values/...`)가 깨지면 즉시 sync 실패
- values 저장소를 별도 repo로 분리할 경우 접근 권한(credential) 정책을 같이 설계하는 것이 안전함
