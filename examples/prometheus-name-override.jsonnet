((import 'nholuongut/kube-prometheus.libsonnet') + {
   prometheus+: {
     prometheus+: {
       metadata+: {
         name: 'my-name',
       },
     },
   },
 }).prometheus.prometheus
