local kp = (import 'nholuongut/kube-prometheus.libsonnet') + {
  _config+:: {
    namespace: 'monitoring',
  },
  grafanaDashboards+:: {  //  monitoring-mixin compatibility
    'my-dashboard.json': (import 'example-grafana-dashboard.json'),
  },
  grafana+:: {
    dashboards+:: {  // use this method to import your dashboards to Grafana
      'my-dashboard.json': (import 'example-grafana-dashboard.json'),
    },
  },
};

{ ['00namespace-' + name]: kp.kubePrometheus[name] for name in std.objectFields(kp.kubePrometheus) } +
{ ['0prometheus-operator-' + name]: kp.prometheusOperator[name] for name in std.objectFields(kp.prometheusOperator) } +
{ ['node-exporter-' + name]: kp.nodeExporter[name] for name in std.objectFields(kp.nodeExporter) } +
{ ['kube-state-metrics-' + name]: kp.kubeStateMetrics[name] for name in std.objectFields(kp.kubeStateMetrics) } +
{ ['alertmanager-' + name]: kp.alertmanager[name] for name in std.objectFields(kp.alertmanager) } +
{ ['prometheus-' + name]: kp.prometheus[name] for name in std.objectFields(kp.prometheus) } +
{ ['grafana-' + name]: kp.grafana[name] for name in std.objectFields(kp.grafana) }
