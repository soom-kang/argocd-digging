# 6_kustomize_overlay

- 매칭 Git 경로: `github/6_kustomize_overlay`
- 목표: base 리소스에 dev overlay를 적용해 환경별 차이를 선언적으로 관리하는 방식 검증

---

# 1. Kustomize Overlay 의미

Kustomize는 공통 리소스(`base`)와 환경별 변경점(`overlay`)을 분리해 관리합니다.

- `base`: 모든 환경에서 공통으로 쓰는 기본 리소스
- `overlay`: dev/stage/prod 같은 환경별 차이만 덧씌움

이 방식의 장점:

1. 중복 YAML 감소
2. 환경별 변경점이 명확하게 분리됨
3. Git diff에서 변경 의도가 잘 드러남

---

# 2. argocd/6_kustomize_overlay/argo_setup.yaml 설명

핵심 설정:

```yaml
spec:
  source:
    path: github/6_kustomize_overlay/overlays/dev
```

의미:

- Argo CD는 `base`가 아니라 `overlays/dev`를 빌드 대상으로 사용
- 결과적으로 dev overlay에서 정의한 suffix/label/patch가 반영된 매니페스트가 클러스터에 적용됨

---

# 3. github/6_kustomize_overlay 파일 설명

## base/\*

- `base/kustomization.yaml`: 공통 리소스 목록(namespace/deployment/service) 정의
- `base/deployment.yaml`: 기본값 `replicas: 1`, 이미지 `nginx:1.26-alpine`
- `base/service.yaml`: 기본 Service 정의
- `base/namespace.yaml`: `study-kustomize` 네임스페이스

## overlays/dev/kustomization.yaml

```yaml
nameSuffix: -dev # 모든 리소스 이름 변경
commonLabels:
  environment: dev # 모든 리소스에 label 추가
resources:
  - ../../base # base 전체를 가져온 뒤
patchesStrategicMerge:
  - patch-deployment.yaml # Deployment만 부분 수정
```

의미:

- `nameSuffix: -dev`: 리소스 이름에 `-dev` 접미사 추가
- `commonLabels.environment=dev`: 공통 환경 라벨 부여
- `patchesStrategicMerge`: base Deployment의 일부 필드만 변경

## overlays/dev/patch-deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kustomize-demo # suffix 적용 전 이름 기준으로 매칭됨 overlay 결과: `kustomize-demo-dev`
  namespace: study-kustomize
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
```

- 대상 Deployment(`kustomize-demo`)의 `replicas`를 2로 변경
- nginx 이미지를 `1.27-alpine`으로 변경

즉, base는 재사용하고 dev에서 필요한 차이만 overlay로 선언합니다.

---

## Step 1. Application 생성 (dev overlay 경로 적용)

```bash
awk -v repo="$REPO_URL" '{gsub(/\$\{REPO_URL\}/,repo)}1' argocd/6_kustomize_overlay/argo_setup.yaml \
  | kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f -


# or
kstudy apply -f ./application_setup.yaml
```

## Step 2. Sync 및 결과 확인

```bash
argocd app sync study-kustomize-dev --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-kustomize get deploy,svc -L environment
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-kustomize get deploy kustomize-demo-dev -o yaml | grep -E "replicas:|image:"
```

검증 포인트:

1. Deployment/Service 이름에 `-dev` suffix 적용
2. `environment=dev` 라벨 적용
3. patch 결과(`replicas=2`, `nginx:1.27-alpine`) 반영

---

# 운영 시 주의점

- overlay가 많아질수록 patch 충돌/중복이 생길 수 있어 공통값은 base로 최대한 올리는 것이 좋음
- 이름 변경(`nameSuffix`)을 쓰는 경우, patch 대상 이름과 최종 리소스 이름 관계를 정확히 이해해야 함
