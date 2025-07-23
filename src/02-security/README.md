TODO doc adguard:
- chosen: simple DNS forwarding
    - router setup to forward DNS queries to server's ip, adguard's loadbalancer's nodeport.
    - that establishes the binding server:nodePort<->service:port
    - the services forwards to the pod service:port<->pod:targetPort
- not chosen: DNS over HTTPS
    - router setup to DoH to traefik
      (queries to traefik (HTTPS) on adguard.domain_name:443/dns-query)
    - traefik terminates TLS connection and forwards to adguard by HTTP
- aktchually using a nodeport for adguard since single-node k8s provided by orbstack cannot bind hostIp twice and traefik already uses it as loadbalancer

TODO Check how to handle IPv6 DNS
