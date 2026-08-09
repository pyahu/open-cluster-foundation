locals {
  tags = merge(var.tags, {
    blueprint = "oci-oke-foundation"
    cluster   = var.cluster_name
  })

  kube_endpoint_mode = var.api_endpoint_public_enabled ? "PUBLIC_ENDPOINT" : "PRIVATE_ENDPOINT"
  kubeconfig_path    = "~/.kube/${var.cluster_name}.yaml"

  # The same operators that reach the API endpoint reach the bastion, unless a
  # dedicated allowlist is provided.
  bastion_allowed_cidrs = length(var.bastion_allowed_cidrs) > 0 ? var.bastion_allowed_cidrs : var.api_endpoint_allowed_cidrs

  node_metadata = var.ssh_public_key == null ? {} : {
    ssh_authorized_keys = var.ssh_public_key
  }

  # Taints must be registered by kubelet at node startup so that nodes created
  # by scaling or node cycling come up tainted. Overriding user_data replaces
  # the OKE default cloud-init, so the script must first download oke-init.sh
  # from the instance metadata endpoint — it does not exist on the image — and
  # then call it, mirroring the default script the override discards.
  node_pool_taint_args = {
    for pool_name, pool in var.node_pools :
    pool_name => join(",", [
      for taint in pool.taints : "${taint.key}=${taint.value}:${taint.effect}"
    ])
  }

  node_pool_metadata = {
    for pool_name, pool in var.node_pools :
    pool_name => length(pool.taints) == 0 ? local.node_metadata : merge(local.node_metadata, {
      user_data = base64encode(<<-CLOUD_INIT
        #!/usr/bin/env bash
        curl --fail -H "Authorization: Bearer Oracle" -L0 http://169.254.169.254/opc/v2/instance/metadata/oke_init_script | base64 --decode >/var/run/oke-init.sh
        bash /var/run/oke-init.sh --kubelet-extra-args "--register-with-taints=${local.node_pool_taint_args[pool_name]}"
      CLOUD_INIT
      )
    })
  }
}
