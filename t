---
# The service account, cluster roles, and cluster role binding are
# only needed for Kubernetes with role-based access control (RBAC).
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    name: flux
  name: flux
  namespace: dev
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  labels:
    name: flux
  name: flux
rules:
  - apiGroups: ['*']
    resources: ['*']
    verbs: ['*']
  - nonResourceURLs: ['*']
    verbs: ['*']
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  labels:
    name: flux
  name: flux
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: flux
subjects:
  - kind: ServiceAccount
    name: flux
    namespace: dev
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flux
  namespace: dev
spec:
  replicas: 1
  selector:
    matchLabels:
      name: flux
  strategy:
    type: Recreate
  template:
    metadata:
      annotations:
        prometheus.io/port: "3031" # tell prometheus to scrape /metrics endpoint's port.
      labels:
        name: flux
    spec:
      nodeSelector:
        beta.kubernetes.io/os: linux
      serviceAccountName: flux
      volumes:
      - name: git-key
        secret:
          secretName: flux-git-deploy
          defaultMode: 0400 # when mounted read-only, we won't be able to chmod

      # This is a tmpfs used for generating SSH keys. In K8s >= 1.10,
      # mounted secrets are read-only, so we need a separate volume we
      # can write to.
      - name: git-keygen
        emptyDir:
          medium: Memory

      # The following volume is for using a customised known_hosts
      # file, which you will need to do if you host your own git
      # repo rather than using github or the like. You'll also need to
      # mount it into the container, below. See
      # https://docs.fluxcd.io/en/latest/guides/use-private-git-host.html
      # - name: ssh-config
      #   configMap:
      #     name: flux-ssh-config

      # The following volume is for using a customised .kube/config,
      # which you will need to do if you wish to have a different
      # default namespace. You will also need to provide the configmap
      # with an entry for `config`, and uncomment the volumeMount and
      # env entries below.
      # - name: kubeconfig
      #   configMap:
      #     name: flux-kubeconfig

      # The following volume is used to import GPG keys (for signing
      # and verification purposes). You will also need to provide the
      # secret with the keys, and uncomment the volumeMount and args
      # below.
      # - name: gpg-keys
      #   secret:
      #     secretName: flux-gpg-keys
      #     defaultMode: 0400

      containers:
      - name: flux
        # There are no ":latest" images for flux. Find the most recent
        # release or image version at https://hub.docker.com/r/fluxcd/flux/tags
        # and replace the tag here.
        image: docker.io/fluxcd/flux:1.18.0
        imagePullPolicy: IfNotPresent
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
        ports:
        - containerPort: 3030 # informational
        livenessProbe:
          httpGet:
            port: 3030
            path: /api/flux/v6/identity.pub
          initialDelaySeconds: 5
          timeoutSeconds: 5
        readinessProbe:
          httpGet:
            port: 3030
            path: /api/flux/v6/identity.pub
          initialDelaySeconds: 5
          timeoutSeconds: 5
        volumeMounts:
        - name: git-key
          mountPath: /etc/fluxd/ssh # to match location given in image's /etc/ssh/config
          readOnly: true # this will be the case perforce in K8s >=1.10
        - name: git-keygen
          mountPath: /var/fluxd/keygen # to match location given in image's /etc/ssh/config

        # Include this if you need to mount a customised known_hosts
        # file; you'll also need the volume declared above.
        # - name: ssh-config
        #   mountPath: /root/.ssh

        # Include this and the volume "kubeconfig" above, and the
        # environment entry "KUBECONFIG" below, to override the config
        # used by kubectl.
        # - name: kubeconfig
        #   mountPath: /etc/fluxd/kube

        # Include this to point kubectl at a different config; you
        # will need to do this if you have mounted an alternate config
        # from a configmap, as in commented blocks above.
        # env:
        # - name: KUBECONFIG
        #   value: /etc/fluxd/kube/config

        # Include this and the volume "gpg-keys" above, and the
        # args below.
        # - name: gpg-keys
        #   mountPath: /root/gpg-import
        #   readOnly: true

        # Include this if you want to supply HTTP basic auth credentials for git
        # via the `GIT_AUTHUSER` and `GIT_AUTHKEY` environment variables using a
        # secret.
        # envFrom:
        # - secretRef:
        #     name: flux-git-auth

        args:

        # If you deployed memcached in a different namespace to flux,
        # or with a different service name, you can supply these
        # following two arguments to tell fluxd how to connect to it.
        # - --memcached-hostname=memcached.default.svc.cluster.local

        # Use the memcached ClusterIP service name by setting the
        # memcached-service to string empty
        - --memcached-service=

        # This must be supplied, and be in the tmpfs (emptyDir)
        # mounted above, for K8s >= 1.10
        - --ssh-keygen-dir=/var/fluxd/keygen

        # Replace the following URL to change the Git repository used by Flux.
        # HTTP basic auth credentials can be supplied using environment variables:
        # https://$(GIT_AUTHUSER):$(GIT_AUTHKEY)@github.com/user/repository.git
        - --git-url=git@github.com:<your username>/flux-get-started
        - --git-branch=master
        # Include this if you want to restrict the manifests considered by flux
        # to those under the following relative paths in the git repository
        # - --git-path=subdir1,subdir2
        - --git-label=flux
        - --git-user=Flux
        - --git-email=vvv

        # Include these two to enable git commit signing
        # - --git-gpg-key-import=/root/gpg-import
        # - --git-signing-key=<key id>
        
        # Include this to enable git signature verification
        # - --git-verify-signatures

        # Tell flux it has readonly access to the repo (default `false`)
        # - --git-readonly

        # Instruct flux where to put sync bookkeeping (default "git", meaning use a tag in the upstream git repo)
        # - --sync-state=git

        # Include these next two to connect to an "upstream" service
        # (e.g., Weave Cloud). The token is particular to the service.
        # - --connect=wss://cloud.weave.works/api/flux
        # - --token=abc123abc123abc123abc123

        # Enable manifest generation (default `false`)
        # - --manifest-generation=false

        # Serve /metrics endpoint at different port;
        # make sure to set prometheus' annotation to scrape the port value.
        - --listen-metrics=:3031

      # Optional DNS settings, configuring the ndots option may resolve
      # nslookup issues on some Kubernetes setups.
      # dnsPolicy: "None"
      # dnsConfig:
      #   options:
      #     - name: ndots
      #       value: "1"
---
apiVersion: v1
kind: Secret
metadata:
  name: flux-git-deploy
  namespace: dev
type: Opaque
---
# memcached deployment used by Flux to cache
# container image metadata.
apiVersion: apps/v1
kind: Deployment
metadata:
  name: memcached
  namespace: dev
spec:
  replicas: 1
  selector:
    matchLabels:
      name: memcached
  template:
    metadata:
      labels:
        name: memcached
    spec:
      nodeSelector:
        beta.kubernetes.io/os: linux
      containers:
      - name: memcached
        image: memcached:1.5.20
        imagePullPolicy: IfNotPresent
        args:
        - -m 512   # Maximum memory to use, in megabytes
        - -I 5m    # Maximum size for one item
        - -p 11211 # Default port
        # - -vv    # Uncomment to get logs of each request and response.
        ports:
        - name: clients
          containerPort: 11211
        securityContext:
          runAsUser: 11211
          runAsGroup: 11211
          allowPrivilegeEscalation: false
---
apiVersion: v1
kind: Service
metadata:
  name: memcached
  namespace: dev
spec:
  ports:
    - name: memcached
      port: 11211
  selector:
    name: memcached
