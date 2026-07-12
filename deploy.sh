#!/bin/bash
# Deploys the traflorkian replica lab (Q8) to your OpenShift cluster.
# Prerequisite: you're already logged in via `oc login ...` and this repo
# has already been pushed to https://github.com/sunilmohite/traflorkian-lab
#
# Usage: ./deploy.sh
set -euo pipefail

GH_USER="sunilmohite"
REPO_URL="https://github.com/${GH_USER}/traflorkian-lab.git"
RAW_BASE="https://raw.githubusercontent.com/${GH_USER}/traflorkian-lab/main/materials"
NS="tarf"

echo "==> Checking oc login"
oc whoami >/dev/null || { echo "Run 'oc login' first"; exit 1; }

echo "==> Creating/using project ${NS}"
oc get project "${NS}" >/dev/null 2>&1 || oc new-project "${NS}"
oc project "${NS}"

echo "==> Starting git-based build of the traflorkian image"
oc get bc traflorkian -n "${NS}" >/dev/null 2>&1 || \
  oc new-build --strategy=docker --name=traflorkian --context-dir=image "${REPO_URL}" -n "${NS}"
oc start-build traflorkian -n "${NS}" --follow

echo "==> Waiting for the imagestream to have a tag"
for i in $(seq 1 30); do
  if oc get istag traflorkian:latest -n "${NS}" >/dev/null 2>&1; then break; fi
  sleep 2
done

echo "==> Deploying the app"
oc get deploy traflorkian -n "${NS}" >/dev/null 2>&1 || \
  oc new-app --name=traflorkian --image-stream=traflorkian:latest -n "${NS}"

echo "==> Downloading materials from your GitHub repo"
TMPDIR=$(mktemp -d)
curl -sSL -o "${TMPDIR}/private-keys-v1.d.tar" "${RAW_BASE}/private-keys-v1.d.tar"
curl -sSL -o "${TMPDIR}/doc.gpg" "${RAW_BASE}/doc.gpg"
tar -xvf "${TMPDIR}/private-keys-v1.d.tar" -C "${TMPDIR}"

echo "==> Creating the marinara secret from the downloaded keys"
oc create secret generic marinara --from-file="${TMPDIR}/private-keys-v1.d/" -n "${NS}" \
  --dry-run=client -o yaml | oc apply -f -

echo "==> Patching the deployment: runAsUser + secret mounted at the image's home dir"
oc patch deploy traflorkian -n "${NS}" --type=json -p '[
  {"op":"add","path":"/spec/template/spec/securityContext","value":{"runAsUser":1000}},
  {"op":"add","path":"/spec/template/spec/volumes","value":[{"name":"marinara-vol","secret":{"secretName":"marinara"}}]},
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts","value":[{"name":"marinara-vol","mountPath":"/home/appuser","readOnly":true}]}
]'

echo "==> Adding the 1Gi CephFS PVC mounted at /data"
oc set volumes deploy/traflorkian --add --type=pvc --name=traflorkian-vol \
  --claim-name=traflorkian-data --claim-size=1Gi --claim-class=ocs-storagecluster-cephfs \
  --claim-mode=rwx --mount-path=/data -n "${NS}"

echo "==> Waiting for the pod to be ready"
oc rollout status deploy/traflorkian -n "${NS}" --timeout=180s

POD=$(oc get pod -n "${NS}" -l deployment=traflorkian -o jsonpath='{.items[0].metadata.name}')
echo "==> Copying doc.gpg into ${POD}:/data/doc.gpg"
oc cp "${TMPDIR}/doc.gpg" "${NS}/${POD}:/data/doc.gpg"

echo "==> Exposing the service and route (app listens on 8080)"
oc get svc traflorkian -n "${NS}" >/dev/null 2>&1 || oc expose deploy/traflorkian --port=8080 -n "${NS}"
oc get route traflorkian -n "${NS}" >/dev/null 2>&1 || oc expose service traflorkian -n "${NS}"

ROUTE=$(oc get route traflorkian -n "${NS}" -o jsonpath='{.spec.host}')
echo "==> Done. Verifying:"
sleep 5
oc logs deploy/traflorkian -n "${NS}" --tail=20
echo "---"
curl -sk "http://${ROUTE}" || echo "(route not reachable yet — give it a few more seconds and retry: curl -sk http://${ROUTE})"

echo ""
echo "==> Now create the snapshot:"
echo "cat <<EOF | oc create -f -"
echo "apiVersion: snapshot.storage.k8s.io/v1"
echo "kind: VolumeSnapshot"
echo "metadata:"
echo "  name: traflorkian-snap"
echo "  namespace: ${NS}"
echo "spec:"
echo "  volumeSnapshotClassName: ocs-storagecluster-cephfsplugin-snapclass"
echo "  source:"
echo "    persistentVolumeClaimName: traflorkian-data"
echo "EOF"

rm -rf "${TMPDIR}"
