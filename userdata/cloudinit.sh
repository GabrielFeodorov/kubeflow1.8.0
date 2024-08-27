# #!/bin/bash
# #adding comments to make code readable

set -o pipefail
LOG_FILE="/var/log/OKE-kubeflow-initialize.log"
log() { 
	echo "$(date) [${EXECNAME}]: $*" >> "${LOG_FILE}" 
}

region=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/regionInfo/regionIdentifier`
namespace=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/namespace`
availability_domain=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v2/instance/metadata/availability_domain`
oke_cluster_id=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v1/instance/metadata/oke_cluster_id`
kubeflow_password=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v1/instance/metadata/kubeflow_password`
mount_target_id=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v1/instance/metadata/mount_target`
kustomize_version=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v1/instance/metadata/kustomize_version`
kubeflow_branch=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v1/instance/metadata/kubeflow_version`
load_balancer_ip=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v1/instance/metadata/load_balancer_ip`
configure_oracle_auth=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v1/instance/metadata/configure_oracle_auth`
issuer=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v1/instance/metadata/oci_domain`
client_id=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v1/instance/metadata/client_id`
client_secret=`curl -s -H "Authorization: Bearer Oracle" -L http://169.254.169.254/opc/v1/instance/metadata/client_secret`


country=`echo $region|awk -F'-' '{print $1}'`
city=`echo $region|awk -F'-' '{print $2}'`

# Define the variables

EXECNAME="Kubectl & Git"

log "->Install"


cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
EOF
yum install kubectl git -y >> $LOG_FILE




# Kubectl is installed and now, you need to configure kubectl
log "->Configure"
mkdir -p /home/opc/.kube
echo "source <(kubectl completion bash)" >> ~/.bashrc
echo "alias k='kubectl'" >> ~/.bashrc
echo "source <(kubectl completion bash)" >> /home/opc/.bashrc
echo "alias k='kubectl'" >> /home/opc/.bashrc
source ~/.bashrc




# Get the OCI CLI installed
EXECNAME="OCI CLI"
log "->Install"
yum install python36-oci-cli -y >> $LOG_FILE
echo "export OCI_CLI_AUTH=instance_principal" >> ~/.bash_profile
echo "export OCI_CLI_AUTH=instance_principal" >> ~/.bashrc
echo "export OCI_CLI_AUTH=instance_principal" >> /home/opc/.bash_profile
echo "export OCI_CLI_AUTH=instance_principal" >> /home/opc/.bashrc
EXECNAME="Kubeconfig"
log "->Generate"

while [ ! -f /root/.kube/config ]
do
    sleep 5
	source ~/.bashrc
	oci ce cluster create-kubeconfig --cluster-id ${oke_cluster_id} --file /root/.kube/config  --region ${region} --token-version 2.0.0 >> $LOG_FILE
done



cp /root/.kube/config /home/opc/.kube/config
chown -R opc:opc /home/opc/.kube/



EXECNAME="Kustomize"
log "->Fetch & deploy to /bin/"
# Now that we have kubectl configured, let us download kustomize
wget "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${kustomize_version}/kustomize_v${kustomize_version}_linux_amd64.tar.gz"
tar -xzvf kustomize_v${kustomize_version}_linux_amd64.tar.gz
mv kustomize /bin/kustomize
chmod +x /bin/kustomize


# Download Kubeflow
EXECNAME="Kubeflow"
log "->Clone Repo"
mkdir -p /opt/kubeflow
cd /opt/kubeflow
# Ensure Kubeflow 1.8 alone is used
export kubeflow_branch
git clone -b v$kubeflow_branch https://github.com/kubeflow/manifests.git >> $LOG_FILE






LBIP="$load_balancer_ip"
DOMAIN="kubeflow.$load_balancer_ip.nip.io"


# Create certificates
mkdir -p /opt/kfsecure
cd /opt/kfsecure

cat <<EOF | tee /opt/kfsecure/istio_namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: istio-system
EOF

kubectl apply -f /opt/kfsecure/istio_namespace.yaml

sleep 20

openssl req -x509             -sha256 -days 356             -nodes             -newkey rsa:2048             -subj "/CN=${DOMAIN}/C=$country/L=$city"             -keyout rootCA.key -out rootCA.crt

cat > csr.conf <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn
[ dn ]
C = $country
ST = $city
L = $city
O = Kubeflow
OU = Kubeflow
CN = ${DOMAIN}
[ req_ext ]
subjectAltName = @alt_names
[ alt_names ]
DNS.1 = ${DOMAIN}
IP.1 = ${LBIP}
EOF

openssl genrsa -out "${DOMAIN}.key" 2048
openssl req -new -key "${DOMAIN}.key" -out "${DOMAIN}.csr" -config csr.conf

cat > cert.conf <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${DOMAIN}
IP.1 = ${LBIP}
EOF

openssl x509 -req     -in "${DOMAIN}.csr"     -CA rootCA.crt -CAkey rootCA.key     -CAcreateserial -out "${DOMAIN}.crt"     -days 365     -sha256 -extfile cert.conf

sleep 10
kubectl --kubeconfig /root/.kube/config create secret tls kubeflow-tls-cert --key=$DOMAIN.key --cert=$DOMAIN.crt -n istio-system




cp /opt/kubeflow/manifests/common/dex/base/config-map.yaml /opt/kubeflow/manifests/common/dex/base/config-map.yaml.DEFAULT
# Enable authentication through Oracle IDCS
if [ "$configure_oracle_auth" != false ]; then
  # Update the issuer line
  sed -i "s|issuer:.*|issuer: https://${DOMAIN}/dex|g" /opt/kubeflow/manifests/common/dex/base/config-map.yaml

  # Update the redirectURIs line 
  sed -i "s|redirectURIs:.*|redirectURIs: [\"/authservice/oidc/callback\",\"https://${DOMAIN}/dex/callback\"]|g" /opt/kubeflow/manifests/common/dex/base/config-map.yaml

  # Add Oracle connector
  cat <<EOF >> /opt/kubeflow/manifests/common/dex/base/config-map.yaml

    connectors:
    - type: oidc
      id: oracle
      name: Oracle
      config:
        issuer: ${issuer}
        clientID: ${client_id}
        clientSecret: ${client_secret}
        redirectURI: https://${DOMAIN}/dex/callback
        getUserInfo: true
        userNameKey: user_displayname
        insecureSkipEmailVerified: true
EOF

  ###### Update OIDC Provider
  sed -i "s|^OIDC_PROVIDER=.*|OIDC_PROVIDER=https://${DOMAIN}/dex|g" /opt/kubeflow/manifests/common/oidc-client/oidc-authservice/base/params.env

  # Add CA_BUNDLE to OIDC
  sed -i "/^OIDC_PROVIDER=.*/a\CA_BUNDLE=/cert/b64" /opt/kubeflow/manifests/common/oidc-client/oidc-authservice/base/params.env

  ####### Modify StatefulSet
  sed -i "/mountPath: \/var\/lib\/authservice/a\\
          - name: ca-cert\\
            readOnly: true\\
            mountPath: /cert" /opt/kubeflow/manifests/common/oidc-client/oidc-authservice/base/statefulset.yaml

  cat <<EOF >> /opt/kubeflow/manifests/common/oidc-client/oidc-authservice/base/statefulset.yaml

        - name: ca-cert
          secret:
            secretName: kubeflow-tls-cert
            items:
              - key: tls.crt
                path: b64
            defaultMode: 511
EOF

  ## Enable Automatic Profiles for Dashboard
  sed -i "s/^CD_REGISTRATION_FLOW=false/CD_REGISTRATION_FLOW=true/" /opt/kubeflow/manifests/apps/centraldashboard/upstream/base/params.env
fi







# Change the default Kubeflow Password
export kubeflow_password
pip3 install --upgrade pip
pip3 install passlib
pip3 install bcrypt
hashed_password=$(python3 -c "
import os
from passlib.hash import bcrypt
kubeflow_password = os.getenv('kubeflow_password')
print(bcrypt.using(rounds=12, ident='2y').hash(kubeflow_password))
")
sed -i "s|hash:.*|hash: $hashed_password|" /opt/kubeflow/manifests/common/dex/base/config-map.yaml




if [ "$mount_target_id" != "not_using" ]; then
  mkdir -p /opt/kubeflow_fs
  cd /opt/kubeflow_fs
  cat > existing-fss-st-class.yaml <<EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: existing-fss-storage
provisioner: fss.csi.oraclecloud.com
parameters:
  availabilityDomain: $availability_domain
  mountTargetOcid: $mount_target_id
EOF
sleep 20
  kubectl --kubeconfig /root/.kube/config apply -f existing-fss-st-class.yaml 
  kubectl --kubeconfig /root/.kube/config patch storageclass oci-bv -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
  kubectl --kubeconfig /root/.kube/config patch storageclass existing-fss-storage -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
  sed -i 's|chmod -R 777 /var/lib/authservice;|find /var/lib/authservice ! -name ".snapshot" -exec chmod 777 {} +;|' /opt/kubeflow/manifests/common/oidc-client/oidc-authservice/overlays/ibm-storage-config/statefulset.yaml

  # Install Kubeflow
  log "->Install via Kustomize with FS as storage class"
  source <(kubectl completion bash)
  log "-->Build & Deploy Kubeflow with FS as storage class"

  cd /opt/kubeflow/manifests
  while ! kustomize build example | kubectl apply --kubeconfig /root/.kube/config -f - | tee -a $LOG_FILE; do echo 'Retrying to apply resources'; sleep 60; done
  sleep 120
  # add another condition to wait for the pod status
  pod_status=$(kubectl --kubeconfig /root/.kube/config get pod "oidc-authservice-0" -n "istio-system" -o jsonpath='{.status.containerStatuses[?(@.state.waiting.reason == "CrashLoopBackOff")]}')
  if [ -n "$pod_status" ]; then
    echo "$pod_status"
    kustomize build common/oidc-client/oidc-authservice/overlays/ibm-storage-config | kubectl apply --kubeconfig /root/.kube/config -f -
    kubectl --kubeconfig /root/.kube/config delete pod "oidc-authservice-0" -n "istio-system"
  fi
else
  # Install Kubeflow
  log "->Install via Kustomize"
  source <(kubectl completion bash)
  log "-->Build & Deploy Kubeflow"  
  cd /opt/kubeflow/manifests
  while ! kustomize build example | kubectl apply --kubeconfig /root/.kube/config -f - | tee -a $LOG_FILE; do echo 'Retrying to apply resources'; sleep 60; done 
fi

sleep 30

# Check status for all pods
all_pods_running() {
  pods=$(kubectl --kubeconfig /root/.kube/config get pods --all-namespaces --no-headers)
  all_running=true
  echo "$pods" | while read -r namespace name ready status _; do
    if [[ "$status" != "Running" ]]; then
      all_running=false
      break
    fi
  done
  echo $all_running
}

# Check for Mount Volume error on failed pods
check_mount_volume_errors() {
  local name=$1
  local namespace=$2
  errors=$(kubectl --kubeconfig /root/.kube/config describe pod "$name" -n "$namespace" | grep "MountVolume.SetUp failed")
  echo "$errors"
}

# Reaply the kubeflow deployment untill all pods are running
status="NotRunning"
while [[ "$status" != "true" ]]; do
  echo "Checking pod statuses..."
  pods=$(kubectl --kubeconfig /root/.kube/config get pods --all-namespaces --no-headers)
  echo "$pods" | while read -r namespace name ready status _; do
    if [[ "$status" != "Running" ]]; then
      echo "Pod $name in namespace $namespace is not Running." >> $LOG_FILE
      errors=$(check_mount_volume_errors "$name" "$namespace")
      if [[ ! -z "$errors" ]]; then
        echo "MountVolume.SetUp error found for pod $name. Re-applying resources..." >> $LOG_FILE
        while ! kustomize build example | kubectl apply -f - | tee -a "$LOG_FILE"; do
          echo 'Retrying to apply resources...'
          sleep 60
        done

        # Recheck pod statuses after applying resources
        echo "Rechecking pod statuses after applying resources..." >> $LOG_FILE
        sleep 20
        status=$(all_pods_running)
        if [[ "$status" == "true" ]]; then
          echo "All pods are now Running after reapplying resources." >> $LOG_FILE
          break
        fi
      fi
    fi
  done
  # Check if all pods are now Running
  status=$(all_pods_running)
  if [[ "$status" == "true" ]]; then
    echo "All pods are now Running." >> $LOG_FILE
    break
  else
    echo "Not all pods are Running. Waiting..."
    sleep 10
  fi
done


cat <<EOF | tee /tmp/patchservice_lb.yaml
  spec:
    type: LoadBalancer
    loadBalancerIP: $load_balancer_ip
  metadata:
    annotations:
      oci.oraclecloud.com/load-balancer-type: "lb"
EOF

for i in {1..3}; do
  if [ $(kubectl --kubeconfig /root/.kube/config get pods -n istio-system --no-headers=true |egrep -i ingressgateway | awk '{print $3}') = "Running" ]; then
      echo "Ingress Gateway has been created successfully"

      break
  fi
  sleep 60
done

kubectl --kubeconfig /root/.kube/config patch svc istio-ingressgateway -n istio-system -p "$(cat /tmp/patchservice_lb.yaml)"
sleep 120



cat <<EOF | tee /opt/kfsecure/sslenableingress.yaml
apiVersion: v1
items:
- apiVersion: networking.istio.io/v1beta1
  kind: Gateway
  metadata:
    annotations:
    name: kubeflow-gateway
    namespace: kubeflow
  spec:
    selector:
      istio: ingressgateway
    servers:
    - hosts:
      - "*"
      port:
        name: https
        number: 443
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: kubeflow-tls-cert
    - hosts:
      - "*"
      port:
        name: http
        number: 80
        protocol: HTTP
      tls:
        httpsRedirect: true
kind: List
metadata:
  resourceVersion: ""
  selfLink: ""
EOF

kubectl --kubeconfig /root/.kube/config apply -f /opt/kfsecure/sslenableingress.yaml


echo "Load Balancer IP is ${LBIP}" |tee -a $LOG_FILE
echo "Point your browser to https://${DOMAIN}" |tee -a $LOG_FILE
