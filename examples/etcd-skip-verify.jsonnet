local kp = (import 'nholuongut/kube-prometheus.libsonnet') +
           (import 'nholuongut/kube-prometheus-static-etcd.libsonnet') + {
  _config+:: {
    namespace: 'monitoring',

    etcd+:: {
      ips: ['127.0.0.1'],
      clientCA: importstr 'etcd-client-ca.crt',
      clientKey: importstr 'etcd-client.key',
      clientCert: importstr 'etcd-client.crt',
      insecureSkipVerify: true,
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
