local k3 = import 'github.com/nholuongut/ksonnet-lib/ksonnet.beta.3/k.libsonnet';
local k = import 'github.com/nholuongut/ksonnet-lib/ksonnet.beta.4/k.libsonnet';

{
  _config+:: {
    namespace: 'default',

    versions+:: {
      prometheus: 'v2.22.1',
    },

    imageRepos+:: {
      prometheus: 'quay.io/prometheus/prometheus',
    },

    alertmanager+:: {
      name: 'main',
    },

    prometheus+:: {
      name: 'k8s',
      replicas: 2,
      rules: {},
      namespaces: ['default', 'kube-system', $._config.namespace],
    },
  },

  prometheus+:: {
    local p = self,

    name:: $._config.prometheus.name,
    namespace:: $._config.namespace,
    roleBindingNamespaces:: $._config.prometheus.namespaces,
    replicas:: $._config.prometheus.replicas,
    prometheusRules:: $._config.prometheus.rules,
    alertmanagerName:: $.alertmanager.service.metadata.name,

    serviceAccount:
      local serviceAccount = k.core.v1.serviceAccount;

      serviceAccount.new('prometheus-' + p.name) +
      serviceAccount.mixin.metadata.withNamespace(p.namespace),
    service:
      local service = k.core.v1.service;
      local servicePort = k.core.v1.service.mixin.spec.portsType;

      local prometheusPort = servicePort.newNamed('web', 9090, 'web');

      service.new('prometheus-' + p.name, { app: 'prometheus', prometheus: p.name }, prometheusPort) +
      service.mixin.spec.withSessionAffinity('ClientIP') +
      service.mixin.metadata.withNamespace(p.namespace) +
      service.mixin.metadata.withLabels({ prometheus: p.name }),

    rules:
      {
        apiVersion: 'monitoring.coreos.com/v1',
        kind: 'PrometheusRule',
        metadata: {
          labels: {
            prometheus: p.name,
            role: 'alert-rules',
          },
          name: 'prometheus-' + p.name + '-rules',
          namespace: p.namespace,
        },
        spec: {
          groups: p.prometheusRules.groups,
        },
      },

    roleBindingSpecificNamespaces:
      local roleBinding = k.rbac.v1.roleBinding;

      local newSpecificRoleBinding(namespace) =
        roleBinding.new() +
        roleBinding.mixin.metadata.withName('prometheus-' + p.name) +
        roleBinding.mixin.metadata.withNamespace(namespace) +
        roleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
        roleBinding.mixin.roleRef.withName('prometheus-' + p.name) +
        roleBinding.mixin.roleRef.mixinInstance({ kind: 'Role' }) +
        roleBinding.withSubjects([{ kind: 'ServiceAccount', name: 'prometheus-' + p.name, namespace: p.namespace }]);

      local roleBindingList = k3.rbac.v1.roleBindingList;
      roleBindingList.new([newSpecificRoleBinding(x) for x in p.roleBindingNamespaces]),
    clusterRole:
      local clusterRole = k.rbac.v1.clusterRole;
      local policyRule = clusterRole.rulesType;

      local nodeMetricsRule = policyRule.new() +
                              policyRule.withApiGroups(['']) +
                              policyRule.withResources(['nodes/metrics']) +
                              policyRule.withVerbs(['get']);

      local metricsRule = policyRule.new() +
                          policyRule.withNonResourceUrls('/metrics') +
                          policyRule.withVerbs(['get']);

      local rules = [nodeMetricsRule, metricsRule];

      clusterRole.new() +
      clusterRole.mixin.metadata.withName('prometheus-' + p.name) +
      clusterRole.withRules(rules),
    roleConfig:
      local role = k.rbac.v1.role;
      local policyRule = role.rulesType;

      local configmapRule = policyRule.new() +
                            policyRule.withApiGroups(['']) +
                            policyRule.withResources([
                              'configmaps',
                            ]) +
                            policyRule.withVerbs(['get']);

      role.new() +
      role.mixin.metadata.withName('prometheus-' + p.name + '-config') +
      role.mixin.metadata.withNamespace(p.namespace) +
      role.withRules(configmapRule),
    roleBindingConfig:
      local roleBinding = k.rbac.v1.roleBinding;

      roleBinding.new() +
      roleBinding.mixin.metadata.withName('prometheus-' + p.name + '-config') +
      roleBinding.mixin.metadata.withNamespace(p.namespace) +
      roleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
      roleBinding.mixin.roleRef.withName('prometheus-' + p.name + '-config') +
      roleBinding.mixin.roleRef.mixinInstance({ kind: 'Role' }) +
      roleBinding.withSubjects([{ kind: 'ServiceAccount', name: 'prometheus-' + p.name, namespace: p.namespace }]),
    clusterRoleBinding:
      local clusterRoleBinding = k.rbac.v1.clusterRoleBinding;

      clusterRoleBinding.new() +
      clusterRoleBinding.mixin.metadata.withName('prometheus-' + p.name) +
      clusterRoleBinding.mixin.roleRef.withApiGroup('rbac.authorization.k8s.io') +
      clusterRoleBinding.mixin.roleRef.withName('prometheus-' + p.name) +
      clusterRoleBinding.mixin.roleRef.mixinInstance({ kind: 'ClusterRole' }) +
      clusterRoleBinding.withSubjects([{ kind: 'ServiceAccount', name: 'prometheus-' + p.name, namespace: p.namespace }]),
    roleSpecificNamespaces:
      local role = k.rbac.v1.role;
      local policyRule = role.rulesType;
      local coreRule = policyRule.new() +
                       policyRule.withApiGroups(['']) +
                       policyRule.withResources([
                         'services',
                         'endpoints',
                         'pods',
                       ]) +
                       policyRule.withVerbs(['get', 'list', 'watch']);
      local ingressRule = policyRule.new() +
                          policyRule.withApiGroups(['extensions']) +
                          policyRule.withResources([
                            'ingresses',
                          ]) +
                          policyRule.withVerbs(['get', 'list', 'watch']);

      local newSpecificRole(namespace) =
        role.new() +
        role.mixin.metadata.withName('prometheus-' + p.name) +
        role.mixin.metadata.withNamespace(namespace) +
        role.withRules([coreRule, ingressRule]);

      local roleList = k3.rbac.v1.roleList;
      roleList.new([newSpecificRole(x) for x in p.roleBindingNamespaces]),
    prometheus:
      local statefulSet = k.apps.v1.statefulSet;
      local container = statefulSet.mixin.spec.template.spec.containersType;
      local resourceRequirements = container.mixin.resourcesType;
      local selector = statefulSet.mixin.spec.selectorType;


      local resources =
        resourceRequirements.new() +
        resourceRequirements.withRequests({ memory: '400Mi' });

      {
        apiVersion: 'monitoring.coreos.com/v1',
        kind: 'Prometheus',
        metadata: {
          name: p.name,
          namespace: p.namespace,
          labels: {
            prometheus: p.name,
          },
        },
        spec: {
          replicas: p.replicas,
          version: $._config.versions.prometheus,
          image: $._config.imageRepos.prometheus + ':' + $._config.versions.prometheus,
          serviceAccountName: 'prometheus-' + p.name,
          serviceMonitorSelector: {},
          podMonitorSelector: {},
          probeSelector: {},
          serviceMonitorNamespaceSelector: {},
          podMonitorNamespaceSelector: {},
          probeNamespaceSelector: {},
          nodeSelector: { 'kubernetes.io/os': 'linux' },
          ruleSelector: selector.withMatchLabels({
            role: 'alert-rules',
            prometheus: p.name,
          }),
          resources: resources,
          alerting: {
            alertmanagers: [
              {
                namespace: p.namespace,
                name: p.alertmanagerName,
                port: 'web',
              },
            ],
          },
          securityContext: {
            runAsUser: 1000,
            runAsNonRoot: true,
            fsGroup: 2000,
          },
        },
      },
    serviceMonitor:
      {
        apiVersion: 'monitoring.coreos.com/v1',
        kind: 'ServiceMonitor',
        metadata: {
          name: 'prometheus',
          namespace: p.namespace,
          labels: {
            'k8s-app': 'prometheus',
          },
        },
        spec: {
          selector: {
            matchLabels: {
              prometheus: p.name,
            },
          },
          endpoints: [
            {
              port: 'web',
              interval: '30s',
            },
          ],
        },
      },
    serviceMonitorKubeScheduler:
      {
        apiVersion: 'monitoring.coreos.com/v1',
        kind: 'ServiceMonitor',
        metadata: {
          name: 'kube-scheduler',
          namespace: p.namespace,
          labels: {
            'k8s-app': 'kube-scheduler',
          },
        },
        spec: {
          jobLabel: 'k8s-app',
          endpoints: [
            {
              port: 'https-metrics',
              interval: '30s',
              scheme: 'https',
              bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
              tlsConfig: {
                insecureSkipVerify: true,
              },
            },
          ],
          selector: {
            matchLabels: {
              'k8s-app': 'kube-scheduler',
            },
          },
          namespaceSelector: {
            matchNames: [
              'kube-system',
            ],
          },
        },
      },
    serviceMonitorKubelet:
      {
        apiVersion: 'monitoring.coreos.com/v1',
        kind: 'ServiceMonitor',
        metadata: {
          name: 'kubelet',
          namespace: p.namespace,
          labels: {
            'k8s-app': 'kubelet',
          },
        },
        spec: {
          jobLabel: 'k8s-app',
          endpoints: [
            {
              port: 'https-metrics',
              scheme: 'https',
              interval: '30s',
              honorLabels: true,
              tlsConfig: {
                insecureSkipVerify: true,
              },
              bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
              metricRelabelings: (import 'kube-prometheus/dropping-deprecated-metrics-relabelings.libsonnet'),
              relabelings: [
                {
                  sourceLabels: ['__metrics_path__'],
                  targetLabel: 'metrics_path',
                },
              ],
            },
            {
              port: 'https-metrics',
              scheme: 'https',
              path: '/metrics/cadvisor',
              interval: '30s',
              honorLabels: true,
              honorTimestamps: false,
              tlsConfig: {
                insecureSkipVerify: true,
              },
              bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
              relabelings: [
                {
                  sourceLabels: ['__metrics_path__'],
                  targetLabel: 'metrics_path',
                },
              ],
              metricRelabelings: [
                // Drop a bunch of metrics which are disabled but still sent, see
                // https://github.com/google/cadvisor/issues/1925.
                {
                  sourceLabels: ['__name__'],
                  regex: 'container_(network_tcp_usage_total|network_udp_usage_total|tasks_state|cpu_load_average_10s)',
                  action: 'drop',
                },
              ],
            },
            {
              port: 'https-metrics',
              scheme: 'https',
              path: '/metrics/probes',
              interval: '30s',
              honorLabels: true,
              tlsConfig: {
                insecureSkipVerify: true,
              },
              bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
              relabelings: [
                {
                  sourceLabels: ['__metrics_path__'],
                  targetLabel: 'metrics_path',
                },
              ],
            },
          ],
          selector: {
            matchLabels: {
              'k8s-app': 'kubelet',
            },
          },
          namespaceSelector: {
            matchNames: [
              'kube-system',
            ],
          },
        },
      },
    serviceMonitorKubeControllerManager:
      {
        apiVersion: 'monitoring.coreos.com/v1',
        kind: 'ServiceMonitor',
        metadata: {
          name: 'kube-controller-manager',
          namespace: p.namespace,
          labels: {
            'k8s-app': 'kube-controller-manager',
          },
        },
        spec: {
          jobLabel: 'k8s-app',
          endpoints: [
            {
              port: 'https-metrics',
              interval: '30s',
              scheme: 'https',
              bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
              tlsConfig: {
                insecureSkipVerify: true,
              },
              metricRelabelings: (import 'kube-prometheus/dropping-deprecated-metrics-relabelings.libsonnet') + [
                {
                  sourceLabels: ['__name__'],
                  regex: 'etcd_(debugging|disk|request|server).*',
                  action: 'drop',
                },
              ],
            },
          ],
          selector: {
            matchLabels: {
              'k8s-app': 'kube-controller-manager',
            },
          },
          namespaceSelector: {
            matchNames: [
              'kube-system',
            ],
          },
        },
      },
    serviceMonitorApiserver:
      {
        apiVersion: 'monitoring.coreos.com/v1',
        kind: 'ServiceMonitor',
        metadata: {
          name: 'kube-apiserver',
          namespace: p.namespace,
          labels: {
            'k8s-app': 'apiserver',
          },
        },
        spec: {
          jobLabel: 'component',
          selector: {
            matchLabels: {
              component: 'apiserver',
              provider: 'kubernetes',
            },
          },
          namespaceSelector: {
            matchNames: [
              'default',
            ],
          },
          endpoints: [
            {
              port: 'https',
              interval: '30s',
              scheme: 'https',
              tlsConfig: {
                caFile: '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt',
                serverName: 'kubernetes',
              },
              bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
              metricRelabelings: (import 'kube-prometheus/dropping-deprecated-metrics-relabelings.libsonnet') + [
                {
                  sourceLabels: ['__name__'],
                  regex: 'etcd_(debugging|disk|server).*',
                  action: 'drop',
                },
                {
                  sourceLabels: ['__name__'],
                  regex: 'apiserver_admission_controller_admission_latencies_seconds_.*',
                  action: 'drop',
                },
                {
                  sourceLabels: ['__name__'],
                  regex: 'apiserver_admission_step_admission_latencies_seconds_.*',
                  action: 'drop',
                },
                {
                  sourceLabels: ['__name__', 'le'],
                  regex: 'apiserver_request_duration_seconds_bucket;(0.15|0.25|0.3|0.35|0.4|0.45|0.6|0.7|0.8|0.9|1.25|1.5|1.75|2.5|3|3.5|4.5|6|7|8|9|15|25|30|50)',
                  action: 'drop',
                },
              ],
            },
          ],
        },
      },
    serviceMonitorCoreDNS:
      {
        apiVersion: 'monitoring.coreos.com/v1',
        kind: 'ServiceMonitor',
        metadata: {
          name: 'coredns',
          namespace: p.namespace,
          labels: {
            'k8s-app': 'coredns',
          },
        },
        spec: {
          jobLabel: 'k8s-app',
          selector: {
            matchLabels: {
              'k8s-app': 'kube-dns',
            },
          },
          namespaceSelector: {
            matchNames: [
              'kube-system',
            ],
          },
          endpoints: [
            {
              port: 'metrics',
              interval: '15s',
              bearerTokenFile: '/var/run/secrets/kubernetes.io/serviceaccount/token',
            },
          ],
        },
      },
  },
}
