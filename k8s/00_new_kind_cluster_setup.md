# 신규 kind 클러스터 생성 가이드 (기존 환경과 간섭 없음)

이 문서는 기존 kind 클러스터와 기존 Argo CD 환경을 건드리지 않고, 신규 스터디용 클러스터를 추가 생성하기 위한 절차입니다.

## Step 0. 사전 준비

```bash
kind version
kubectl version --client
docker version
```

## Step 1. 스터디용 변수 고정

```bash
export STUDY_CLUSTER_NAME="argocd-study"
export STUDY_KUBECONFIG="$HOME/.kube/config-kind-argocd-study"
export STUDY_KIND_CONFIG="/Users/soom.kang/Desktop/work/1.k8s/argocd-digging/k8s/kind-study-config.yaml"
```

핵심은 `--kubeconfig`를 별도 파일로 분리해 기존 kubeconfig와 컨텍스트를 섞지 않는 것입니다.

## Step 2. 기존 리소스 확인 (읽기 전용)

```bash
kind get clusters
kubectl config get-contexts
docker ps --format "table {{.Names}}\t{{.Ports}}"
```

기존 클러스터/컨텍스트/Argo CD 컨테이너 이름을 기록만 하고 수정하지 않습니다.

## Step 3. 신규 kind 클러스터 생성

```bash
kind create cluster \
  --name "$STUDY_CLUSTER_NAME" \
  --config "$STUDY_KIND_CONFIG" \
  --kubeconfig "$STUDY_KUBECONFIG"
```

## Step 4. 신규 클러스터 접근 확인

```bash
kubectl --kubeconfig "$STUDY_KUBECONFIG" config get-contexts
kubectl --kubeconfig "$STUDY_KUBECONFIG" cluster-info
kubectl --kubeconfig "$STUDY_KUBECONFIG" get nodes -o wide
```

## Step 5. 편의 alias 설정 (선택)

```bash
alias kstudy='kubectl --kubeconfig "$STUDY_KUBECONFIG"'
```

이후 스터디 클러스터 대상 명령은 `kstudy`로 실행하면 실수로 기존 클러스터를 건드릴 가능성이 줄어듭니다.

## Step 6. 간섭 여부 최종 확인

```bash
kind get clusters
kubectl --kubeconfig "$STUDY_KUBECONFIG" get ns
```

- `kind get clusters` 출력에 기존 클러스터 + `argocd-study`가 함께 보이면 정상
- 기존 Docker Argo CD 컨트롤 플레인은 그대로 유지되어야 함

## Step 7. 롤백/정리 (신규 클러스터만 삭제)

```bash
kind delete cluster --name "$STUDY_CLUSTER_NAME"
rm -f "$STUDY_KUBECONFIG"
```

위 명령은 신규 스터디 클러스터만 제거하며 기존 클러스터에는 영향이 없습니다.
