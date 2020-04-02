FROM alpine
RUN apk add jq curl python3
RUN curl -L https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl
COPY ./serve.sh /app/serve
RUN chmod 755 /usr/local/bin/kubectl /app/serve
ENV KUBECONFIG=/etc/kube/kube_config
