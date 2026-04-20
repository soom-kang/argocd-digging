# 5_helm_chart

- 매칭 Git 경로: `github/5_helm_chart`
- 목표: Argo CD가 Helm chart를 렌더링하고 values 오버라이드를 반영하는 방식 이해

---

# 1. Argo CD + Helm 의미

Argo CD에서 Helm을 쓰면, Git에 있는 Chart를 기준으로 템플릿을 렌더링해 Kubernetes 리소스로 배포합니다.

핵심은 아래 두 가지입니다.

1. Chart 템플릿(`templates/*.yaml`) + values 조합으로 최종 매니페스트 생성
2. `values.yaml` 기본값 위에 `Application.spec.source.helm.values`로 추가 오버라이드 가능

즉, Helm chart를 Git에 두고 환경별 값만 Application에서 덮어쓰는 운영이 가능합니다.

---

# 2. argocd/5_helm_chart/argo_setup.yaml 설명

핵심 설정:

```yaml
spec:
  source:
    path: github/5_helm_chart
    helm:
      releaseName: study-helm
      values: |
        replicaCount: 2
        service:
          type: ClusterIP
          port: 80
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
```

의미:

- `path`: Helm chart 루트 경로(`Chart.yaml`가 있는 위치)
- `releaseName`: 템플릿 이름 계산 시 사용되는 Helm release 이름
- `helm.values`: `values.yaml` 기본값 위에 적용되는 inline 오버라이드
- `CreateNamespace=true`: 대상 네임스페이스가 없으면 생성

---

# 3. github/5_helm_chart 파일 설명

## Chart.yaml

```yaml
apiVersion: v2 # Helm Chart API 버전입니다. Helm 3에서 일반적으로 `v2`를 사용합니다.
name: study-helm-chart
description: Helm chart for Argo CD Helm feature testing
type: application # 이 차트가 애플리케이션 배포용인지, 라이브러리 차트인지 구분합니다.
version: 0.1.0 # 차트 자체 버전입니다. 차트 구조나 템플릿이 바뀌면 올립니다.
appVersion: "1.0.0" # 배포 대상 애플리케이션 버전입니다. 보통 컨테이너 앱 버전 표시에 씁니다.
```

- chart 메타데이터(name/version/type) 정의

### version vs appVersion

이 둘은 자주 헷갈립니다.

- `version` = **Helm chart 버전**
- `appVersion` = **배포되는 앱 버전**

예를 들어:

- 템플릿만 수정 → `version` 증가
- nginx 이미지 버전만 변경 → 보통 `appVersion` 변경 가능

## values.yaml

```yaml
replicaCount: 1

image:
  repository: nginx
  tag: "1.27-alpine"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80

labels:
  appPartOf: argocd-study
```

- 기본 파라미터 정의
- 예: `replicaCount: 1`, `image.tag: 1.27-alpine`, `service.type: ClusterIP`

## templates/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: { { include "study-helm-chart.fullname" . } } # Service와 마찬가지로 helper를 사용해 이름을 만듭니다.
  labels:
    app.kubernetes.io/name: { { include "study-helm-chart.name" . } }
    app.kubernetes.io/instance: { { .Release.Name } }
    app.kubernetes.io/part-of: { { .Values.labels.appPartOf } } # “이 앱이 어떤 상위 시스템에 속하는가”를 나타내는 라벨
spec:
  replicas: { { .Values.replicaCount } } # Pod를 몇 개 유지할지 결정
  selector: # 중요한 점은: `selector.matchLabels` `template.metadata.labels`이 둘이 반드시 일치해야 합니다. 그래야 Deployment가 생성한 Pod를 제대로 추적
    matchLabels: # Deployment가 어떤 Pod를 자기 관리 대상으로 볼지 정합니다.
      app.kubernetes.io/name: { { include "study-helm-chart.name" . } }
      app.kubernetes.io/instance: { { .Release.Name } }
  template:
    metadata:
      labels:
        app.kubernetes.io/name: { { include "study-helm-chart.name" . } }
        app.kubernetes.io/instance: { { .Release.Name } }
    spec:
      containers:
        - name: nginx
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: { { .Values.image.pullPolicy } }
          ports:
            - containerPort: 80
              name: http # `name: http`는 Service에서 `targetPort: http`와 연결
```

- `replicas: {{ .Values.replicaCount }}`로 values 반영
- 이미지(`repository`, `tag`, `pullPolicy`)도 values 기반
- 공통 라벨/이름은 helper 템플릿 사용

## templates/service.yaml

```yaml
apiVersion: v1
kind: Service # 이 리소스가 Service라는 뜻입니다.
metadata:
  name: { { include "study-helm-chart.fullname" . } } # Service 이름을 helper 템플릿으로 생성합니다.
  labels:
    app.kubernetes.io/name: { { include "study-helm-chart.name" . } } # 앱 이름
    app.kubernetes.io/instance: { { .Release.Name } } # 설치 인스턴스 이름
spec:
  type: { { .Values.service.type } }
  selector:
    app.kubernetes.io/name: { { include "study-helm-chart.name" . } } # 이 라벨을 가진 Pod를 Service가 선택합니다.
    app.kubernetes.io/instance: { { .Release.Name } } # Deployment가 만든 Pod와 Service를 연결하는 핵심
  ports:
    - name: http
      port: { { .Values.service.port } }
      targetPort: http # 숫자가 아니라 포트 이름 Deployment에서 container port에 `name: http`를 붙였기 때문에 연결
```

- Service 타입/포트를 values 기반으로 렌더링
- selector는 release/name 라벨 사용

## templates/\_helpers.tpl

- chart 이름/풀네임 생성 함수 정의
- releaseName과 결합해 리소스 이름 일관성 보장

이 실습에서는 `values.yaml` 기본 `replicaCount: 1`이 Application의 inline values(`replicaCount: 2`)로 덮어써지는 점이 핵심입니다.

---

## Step 1. Application 생성 (Helm 옵션 적용)

```bash
awk -v repo="$REPO_URL" '{gsub(/\$\{REPO_URL\}/,repo)}1' argocd/5_helm_chart/argo_setup.yaml \
  | kubectl --kubeconfig "$STUDY_KUBECONFIG" -n "$ARGOCD_NS" apply -f -

# or
kstudy apply -f ./application_setup.yaml
```

## Step 2. Sync 및 결과 확인

```bash
argocd app sync study-helm --argocd-context "$ARGOCD_CLI_CONTEXT"
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-helm get deploy,svc
kubectl --kubeconfig "$STUDY_KUBECONFIG" -n study-helm get deploy -o wide
```

검증 포인트:

1. Deployment replica 수가 2로 생성됨 (inline values 우선)
2. Service가 `ClusterIP:80`으로 생성됨

## Step 3. 값 변경 반영 테스트

예시:

- `github/5_helm_chart/values.yaml`의 `image.tag` 변경 후 push
- 또는 `argo_setup.yaml`의 `helm.values` 값 변경 후 Application 재적용

변경 후 sync 시 새 템플릿 결과가 반영되면 검증 완료입니다.

---

# 운영 시 주의점

- values 소스가 여러 개면 우선순위/출처 추적이 어려워짐
- 환경별 값은 한 위치(Application 또는 values 파일)로 정책화하는 것이 유지보수에 유리함
