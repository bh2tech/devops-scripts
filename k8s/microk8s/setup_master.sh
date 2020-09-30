# /bin/bash

# install docker
sudo snap install docker

# install microk8s from snap
sudo snap install microk8s --classic

# enable addons
echo "Enable microk8s addons (helm3, dns)"
sudo microk8s enable dns helm3 ingress

sleep 7

# add helm repos
echo "Adding helm repos (stakater/reloader, jetstack/cert-manager, nginx-stable/nginx-ingress)"
sudo microk8s.helm3 repo add stakater https://stakater.github.io/stakater-charts
sudo microk8s.helm3 repo add jetstack https://charts.jetstack.io
sudo microk8s.helm3 repo add nginx-stable https://helm.nginx.com/stable
sudo microk8s.helm3 repo update

echo "Installing reloader chart"
sudo microk8s.helm3 install reloader stakater/reloader

echo "Installing cert-manager chart"
sudo microk8s.kubectl create ns cert-manager
sudo microk8s.helm3 install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --version v1.0.2 \
  --set installCRDs=true

# wait for pods start
sleep 5

read -p "Enter email for letsencrypt certificate: " EMAIL

# create issuer
cat << EOF | sudo microk8s.kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
 name: letsencrypt-prod
 namespace: cert-manager
spec:
 acme:
   # The ACME server URL
   server: https://acme-v02.api.letsencrypt.org/directory
   # Email address used for ACME registration
   email: $EMAIL
   # Name of a secret used to store the ACME account private key
   privateKeySecretRef:
     name: letsencrypt-prod
   # Enable the HTTP-01 challenge provider
   solvers:
   - http01:
       ingress:
         class: nginx
EOF

echo "To use the certificate on your API, using the following script"
cat << EOF
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
    namespace: {{ K8S_NAMESPACE }}
    name: {{ SERVICE_NAME_TAG }}
annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-dev"
spec:
tls:
- hosts:
    - {{ SERVICE_NAME }}.{{ DOMAIN }}
    secretName: {{ SERVICE_NAME }}-tls
rules:
- host: {{ SERVICE_NAME }}.{{ DOMAIN }}
    http:
    paths:
    - backend:
        serviceName: {{ SERVICE_NAME }}
        servicePort: 80
EOF

# show tokens
KNOWN_TOKENS_FILE=/var/snap/microk8s/current/credentials/known_tokens.csv
# KNOWN_TOKENS_FILE=known_hosts.csv

FIRST_LINE="$(sudo head -1 $KNOWN_TOKENS_FILE)"

IFS=',' read -ra DATA <<< "$FIRST_LINE"

K8S_TOKEN="${DATA[0]}"
K8S_USERNAME="${DATA[1]}"
K8S_CLUSTER_IP="$(dig @resolver1.opendns.com ANY myip.opendns.com +short)"

echo "The cluster crendentials are:"
echo ""
echo "K8S_TOKEN=$K8S_TOKEN"
echo "K8S_USERNAME=$K8S_USERNAME"
echo "K8S_CLUSTER_IP=https://$K8S_CLUSTER_IP:16443"

echo ""

echo "In order to configure the connection on your machine, run the following commands:"
echo ""
echo "kubectl config set-cluster cluster --server=$K8S_CLUSTER_IP --insecure-skip-tls-verify"
echo "kubectl config set-credentials $K8S_USERNAME --token=$K8S_TOKEN"
echo "kubectl config set-context dev --cluster=cluster --user=$K8S_USERNAME"

echo ""
echo ""
echo ""
echo "To get more info, go to https://microk8s.io/docs"
