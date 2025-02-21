local k = import 'github.com/nholuongut/ksonnet-lib/ksonnet.beta.4/k.libsonnet';

{
  _config+:: {
    namespace: 'default',

    versions+:: {
      prometheusAdapter: 'v0.8.2',
    },

    imageRepos+:: {
      prometheusAdapter: 'nholuongut/prometheus-adapter',
    },

    prometheusAdapter+:: {
      name: 'prometheus-adapter',
      namespace: $._config.namespace,
      labels: { name: $._config.prometheusAdapter.name },
      prometheusURL: 'http://prometheus-' + $._config.prometheus.name + '.' + $._config.namespace + '.svc.cluster.local:9090/',
      config: {
        resourceRules: {
          cpu: {
            containerQuery: 'sum(irate(container_cpu_usage_seconds_total{<<.LabelMatchers>>,container!="POD",container!="",pod!=""}[5m])) by (<<.GroupBy>>)',
            nodeQuery: 'sum(1 - irate(node_cpu_seconds_total{mode="idle"}[5m]) * on(namespace, pod) group_left(node) node_namespace_pod:kube_pod_info:{<<.LabelMatchers>>}) by (<<.GroupBy>>)',
            resources: {
              overrides: {
                node: {
                  resource: 'node'
                },
                namespace: {
                  resource: 'namespace'
                },
                pod: {
                  resource: 'pod'
                },
              },
            },
            containerLabel: 'container'
          },
          memory: {
            containerQuery: 'sum(container_memory_working_set_bytes{<<.LabelMatchers>>,container!="POD",container!="",pod!=""}) by (<<.GroupBy>>)',
            nodeQuery: 'sum(node_memory_MemTotal_bytes{job="node-exporter",<<.LabelMatchers>>} - node_memory_MemAvailable_bytes{job="node-exporter",<<.LabelMatchers>>}) by (<<.GroupBy>>)',
            resources: {
              overrides: {
                instance: {
                  resource: 'node'
                },
                namespace: {
                  resource: 'namespace'
                },
                pod: {
                  resource: 'pod'
                },
              },
            },
            containerLabel: 'container'
          },
          window: '5m',
        },
      }
    },
  },

  prometheusAdapter+:: {
    apiService:
      {
        apiVersion: 'apiregistration.k8s.io/v1',
        kind: 'APIService',
        metadata: {
          name: 'v1beta1.metrics.k8s.io',
        },
        spec: {
          service: {
            name: $.prometheusAdapter.service.metadata.name,
            namespace: $._config.prometheusAdapter.namespace,
          },
          group: 'metrics.k8s.io',
          version: 'v1beta1',
          insecureSkipTLSVerify: true,
          groupPriorityMinimum: 100,
          versionPriority: 100,
        },
      },

    configMap:
      local configmap = k.core.v1.configMap;
      configmap.new('adapter-config', { 'config.yaml': std.manifestYamlDoc($._config.prometheusAdapter.config) }) +

      configmap.mixin.metadata.withNamespace($._config.prometheusAdapter.namespace),

    serviceMonitor:
      {
        apiVersion: 'monitoring.coreos.com/v1',
        kind: 'ServiceMonitor',
        metadata: {
          name: $._config.prometheusAdapter.name,
          namespace: $._config.prometheusAdapter.namespace,
          labels: $._config.prometheusAdapter.labels,
        },
        spec: {
          selector: {
            matchLabels: $._config.prometheusAdapter.labels,
          },
          endpoints: [
            {
              port: 'https',
              interval: '30s',
              scheme: 'https',
              tlsConfig: {
                insecureSkipVerify: true,
              },
              bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
            },
          ],
        },
      },

    service:
      local service = k.core.v1.service;
      local servicePort = k.core.v1.service.mixin.spec.portsType;

      service.new(
        $._config.prometheusAdapter.name,
        $._config.prometheusAdapter.labels,
        servicePort.newNamed('https', 443, 6443),
      ) +
      service.mixin.metadata.withNamespace($._config.prometheusAdapter.namespace) +
      service.mixin.metadata.withLabels($._config.prometheusAdapter.labels),

    deployment:
      local deployment = k.apps.v1.deployment;
      local volume = deployment.mixin.spec.template.spec.volumesType;
      local container = deployment.mixin.spec.template.spec.containersType;
      local containerVolumeMount = container.volumeMountsType;

      local c =
        container.new($._config.prometheusAdapter.name, $._config.imageRepos.prometheusAdapter + ':' + $._config.versions.prometheusAdapter) +
        container.withArgs([
          '--cert-dir=/var/run/serving-cert',
          '--config=/etc/adapter/config.yaml',
          '--logtostderr=true',
          '--metrics-relist-interval=1m',
          '--prometheus-url=' + $._config.prometheusAdapter.prometheusURL,
          '--secure-port=6443',
        ]) +
        container.withPorts([{ containerPort: 6443 }]) +
        container.withVolumeMounts([
          containerVolumeMount.new('tmpfs', '/tmp'),
          containerVolumeMount.new('volume-serving-cert', '/var/run/serving-cert'),
          containerVolumeMount.new('config', '/etc/adapter'),
        ],);

      deployment.new($._config.prometheusAdapter.name, 1, c, $._config.prometheusAdapter.labels) +
      deployment.mixin.metadata.withNamespace($._config.prometheusAdapter.namespace) +
      deployment.mixin.spec.selector.withMatchLabels($._config.prometheusAdapter.labels) +
      deployment.mixin.spec.template.spec.withServiceAccountName($.prometheusAdapter.serviceAccount.metadata.name) +
      deployment.mixin.spec.template.spec.withNodeSelector({ 'kubernetes.io/os': 'linux' }) +
      deployment.mixin.spec.strategy.rollingUpdate.withMaxSurge(1) +
      deployment.mixin.spec.strategy.rollingUpdate.withMaxUnavailable(0) +
      deployment.mixin.spec.template.spec.withVolumes([
        volume.fromEmptyDir(name='tmpfs'),
        volume.fromEmptyDir(name='volume-serving-cert'),
        { name: 'config', configMap: { name: 'adapter-config' } },
      ]),

    serviceAccount:
      local serviceAccount = k.core.v1.serviceAccount;

      serviceAccount.new($._config.prometheusAdapter.name) +
      serviceAccount.mixin.metadata.withNamespace($._config.prometheusAdapter.namespace),

    clusterRole:
      local clusterRole = k.rbac.v1.clusterRole;
      local policyRule = clusterRole.rulesType;

      local rules =
        policyRule.new() +
        policyRule.withApiGroups(['']) +
        policyRule.withResources(['nodes', 'namespaces', 'pods', 'services']) +
        policyRule.withVerbs(['get', 'list', 'watch']);

      clusterRole.new() +
      clusterRole.mixin.metadata.withName($._config.prometheusAdapter.name) +
      clusterRole.withRules(rules),

    clusterRoleBinding:
      local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;

      clusterRoleBinding.new() +
      clusterRoleBinding.mixin.metadata.withName($._config.prometheusAdapter.name) +
      clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
      clusterRoleBinding.mixin.roleRef.withName($.prometheusAdapter.clusterRole.metadata.name) +
      clusterRoleBinding.mixin.roleRef.mixinInstance({ kind: 'ClusterRole' }) +
      clusterRoleBinding.withSubjects([{
        kind: 'ServiceAccount',
        name: $.prometheusAdapter.serviceAccount.metadata.name,
        namespace: $._config.prometheusAdapter.namespace,
      }]),

    clusterRoleBindingDelegator:
      local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;

      clusterRoleBinding.new() +
      clusterRoleBinding.mixin.metadata.withName('resource-metrics:system:auth-delegator') +
      clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
      clusterRoleBinding.mixin.roleRef.withName('system:auth-delegator') +
      clusterRoleBinding.mixin.roleRef.mixinInstance({ kind: 'ClusterRole' }) +
      clusterRoleBinding.withSubjects([{
        kind: 'ServiceAccount',
        name: $.prometheusAdapter.serviceAccount.metadata.name,
        namespace: $._config.prometheusAdapter.namespace,
      }]),

    clusterRoleServerResources:
      local clusterRole = k.rbac.v1.clusterRole;
      local policyRule = clusterRole.rulesType;

      local rules =
        policyRule.new() +
        policyRule.withApiGroups(['metrics.k8s.io']) +
        policyRule.withResources(['*']) +
        policyRule.withVerbs(['*']);

      clusterRole.new() +
      clusterRole.mixin.metadata.withName('resource-metrics-server-resources') +
      clusterRole.withRules(rules),

    clusterRoleAggregatedMetricsReader:
      local clusterRole = k.rbac.v1.clusterRole;
      local policyRule = clusterRole.rulesType;

      local rules =
        policyRule.new() +
        policyRule.withApiGroups(['metrics.k8s.io']) +
        policyRule.withResources(['pods', 'nodes']) +
        policyRule.withVerbs(['get','list','watch']);

      clusterRole.new() +
      clusterRole.mixin.metadata.withName('system:aggregated-metrics-reader') +
      clusterRole.mixin.metadata.withLabels({
        "rbac.authorization.k8s.io/aggregate-to-admin": "true",
        "rbac.authorization.k8s.io/aggregate-to-edit": "true",
        "rbac.authorization.k8s.io/aggregate-to-view": "true",
      }) +
      clusterRole.withRules(rules),

    roleBindingAuthReader:
      local roleBinding = k.rbac.v1.roleBinding;

      roleBinding.new() +
      roleBinding.mixin.metadata.withName('resource-metrics-auth-reader') +
      roleBinding.mixin.metadata.withNamespace('kube-system') +
      roleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
      roleBinding.mixin.roleRef.withName('extension-apiserver-authentication-reader') +
      roleBinding.mixin.roleRef.mixinInstance({ kind: 'Role' }) +
      roleBinding.withSubjects([{
        kind: 'ServiceAccount',
        name: $.prometheusAdapter.serviceAccount.metadata.name,
        namespace: $._config.prometheusAdapter.namespace,
      }]),
  },
}
