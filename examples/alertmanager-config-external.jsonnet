((import 'nholuongut/kube-prometheus.libsonnet') + {
   _config+:: {
     alertmanager+: {
       config: importstr 'alertmanager-config.yaml',
     },
   },
 }).alertmanager.secret
