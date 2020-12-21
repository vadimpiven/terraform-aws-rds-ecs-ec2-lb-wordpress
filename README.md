# Terrafrom AWS

## Contains
- Gateway
- Security group
- Load balancer
- MySQL
- Wordpress
- OWASP ZAP sidecar

## Outputs
Address of loadbalancer. Open it in your browser.

## Behaviour
Returns error 503 for several minutes, then shows wp-install.
When installation is complited - returns error 503 again, and after some time site is finally fully functional.

ZAP is started as sidecar in daemon mode and accesses wordpress via bridged network.

## Usage
`terraform apply`
